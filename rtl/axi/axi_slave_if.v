`timescale 1ns/1ps
`include "ddr3_params.vh"

// ============================================================
// AXI4 Slave 接口（简化实现，支持 INCR/FIXED/WRAP 描述透传）
// - 完整 AR/AW/W/R/B 五通道握手
// - 内部通过同步 FIFO 与命令路径解耦
// ============================================================
module axi_slave_if #(
    parameter AXI_ADDR_WIDTH = `AXI_ADDR_WIDTH,
    parameter AXI_DATA_WIDTH = `DDR_DQ_WIDTH,
    parameter AXI_ID_WIDTH   = `AXI_ID_WIDTH,
    parameter MAX_OUTSTANDING = 4
) (
    input  wire                         aclk,
    input  wire                         aresetn,

    input  wire [AXI_ID_WIDTH-1:0]      s_axi_awid,
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [7:0]                   s_axi_awlen,
    input  wire [2:0]                   s_axi_awsize,
    input  wire [1:0]                   s_axi_awburst,
    input  wire                         s_axi_awvalid,
    output wire                         s_axi_awready,

    input  wire [AXI_DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [AXI_DATA_WIDTH/8-1:0]  s_axi_wstrb,
    input  wire                         s_axi_wlast,
    input  wire                         s_axi_wvalid,
    output wire                         s_axi_wready,

    output reg  [AXI_ID_WIDTH-1:0]      s_axi_bid,
    output reg  [1:0]                   s_axi_bresp,
    output reg                          s_axi_bvalid,
    input  wire                         s_axi_bready,

    input  wire [AXI_ID_WIDTH-1:0]      s_axi_arid,
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [7:0]                   s_axi_arlen,
    input  wire [2:0]                   s_axi_arsize,
    input  wire [1:0]                   s_axi_arburst,
    input  wire                         s_axi_arvalid,
    output wire                         s_axi_arready,

    output reg  [AXI_ID_WIDTH-1:0]      s_axi_rid,
    output reg  [AXI_DATA_WIDTH-1:0]    s_axi_rdata,
    output reg  [1:0]                   s_axi_rresp,
    output reg                          s_axi_rlast,
    output reg                          s_axi_rvalid,
    input  wire                         s_axi_rready,

    output wire                         req_valid,
    input  wire                         req_ready,
    output wire                         req_rw,
    output wire [AXI_ID_WIDTH-1:0]      req_id,
    output wire [AXI_ADDR_WIDTH-1:0]    req_addr,
    output wire [7:0]                   req_len,
    output wire [2:0]                   req_size,
    output wire [1:0]                   req_burst,

    output wire                         wbuf_valid,
    input  wire                         wbuf_ready,
    output wire [AXI_DATA_WIDTH-1:0]    wbuf_data,
    output wire [AXI_DATA_WIDTH/8-1:0]  wbuf_strb,
    output wire                         wbuf_last,
    output wire [AXI_ID_WIDTH-1:0]      wbuf_id,

    input  wire                         rbuf_valid,
    output wire                         rbuf_ready,
    input  wire [AXI_DATA_WIDTH-1:0]    rbuf_data,
    input  wire                         rbuf_last,
    input  wire [AXI_ID_WIDTH-1:0]      rbuf_id,

    input  wire                         wr_done_valid,
    input  wire [AXI_ID_WIDTH-1:0]      wr_done_id,
    output wire                         wr_done_ready
);

    localparam REQW = 1 + AXI_ID_WIDTH + AXI_ADDR_WIDTH + 8 + 3 + 2;
    localparam WW   = AXI_DATA_WIDTH + AXI_DATA_WIDTH/8 + 1 + AXI_ID_WIDTH;

    wire aw_push = s_axi_awvalid && s_axi_awready;
    wire ar_push = s_axi_arvalid && s_axi_arready;

    wire aw_full, aw_empty;
    wire ar_full, ar_empty;
    wire [AXI_ID_WIDTH+AXI_ADDR_WIDTH+8+3+2-1:0] aw_dout;
    wire [AXI_ID_WIDTH+AXI_ADDR_WIDTH+8+3+2-1:0] ar_dout;
    reg  aw_pop, ar_pop;

    sync_fifo #(
        .DATA_WIDTH(AXI_ID_WIDTH+AXI_ADDR_WIDTH+8+3+2),
        .DEPTH(16), .ADDR_WIDTH(4)
    ) u_aw_fifo (
        .clk(aclk), .rst_n(aresetn),
        .wr_en(aw_push), .wr_data({s_axi_awid,s_axi_awaddr,s_axi_awlen,s_axi_awsize,s_axi_awburst}),
        .rd_en(aw_pop), .rd_data(aw_dout),
        .full(aw_full), .empty(aw_empty), .level()
    );

    sync_fifo #(
        .DATA_WIDTH(AXI_ID_WIDTH+AXI_ADDR_WIDTH+8+3+2),
        .DEPTH(16), .ADDR_WIDTH(4)
    ) u_ar_fifo (
        .clk(aclk), .rst_n(aresetn),
        .wr_en(ar_push), .wr_data({s_axi_arid,s_axi_araddr,s_axi_arlen,s_axi_arsize,s_axi_arburst}),
        .rd_en(ar_pop), .rd_data(ar_dout),
        .full(ar_full), .empty(ar_empty), .level()
    );

    assign s_axi_awready = !aw_full;
    // outstanding read counter: allow up to MAX_OUTSTANDING concurrent read transactions
    assign s_axi_arready = !ar_full && (outstanding_rd_cnt < MAX_OUTSTANDING[2:0]);

    wire w_full, w_empty;
    wire [WW-1:0] w_dout;
    reg  w_pop;
    reg [AXI_ID_WIDTH-1:0] cur_wid;

    reg [8:0] aw_beats_rem;
    reg       aw_track_valid;

    assign s_axi_wready = !w_full;
    wire w_push = s_axi_wvalid && s_axi_wready;

    sync_fifo #(
        .DATA_WIDTH(WW),
        .DEPTH(64), .ADDR_WIDTH(6)
    ) u_w_fifo (
        .clk(aclk), .rst_n(aresetn),
        .wr_en(w_push), .wr_data({s_axi_wdata,s_axi_wstrb,s_axi_wlast,cur_wid}),
        .rd_en(w_pop), .rd_data(w_dout),
        .full(w_full), .empty(w_empty), .level()
    );

    // AW 跟踪：将写 burst 的 ID 附到 W 数据上
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            aw_track_valid <= 1'b0;
            aw_beats_rem   <= 9'd0;
            cur_wid        <= {AXI_ID_WIDTH{1'b0}};
        end else begin
            if (aw_push && !aw_track_valid) begin
                aw_track_valid <= 1'b1;
                aw_beats_rem   <= {1'b0, s_axi_awlen} + 9'd1;
                cur_wid        <= s_axi_awid;
            end
            if (w_push && aw_track_valid) begin
                if (aw_beats_rem == 9'd1) begin
                    aw_track_valid <= 1'b0;
                    aw_beats_rem   <= 9'd0;
                end else begin
                    aw_beats_rem   <= aw_beats_rem - 9'd1;
                end
            end
            if (aw_push && aw_track_valid && aw_beats_rem == 9'd0) begin
                cur_wid <= s_axi_awid;
            end
        end
    end

    reg req_v;
    reg [REQW-1:0] req_d;
    reg [8:0] r_beats_rem;
    reg [2:0] outstanding_rd_cnt;

    assign req_valid = req_v;
    assign {req_rw, req_id, req_addr, req_len, req_size, req_burst} = req_d;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            req_v <= 1'b0;
            req_d <= {REQW{1'b0}};
            aw_pop <= 1'b0;
            ar_pop <= 1'b0;
            r_beats_rem <= 9'd0;
            outstanding_rd_cnt <= 3'd0;
        end else begin
            aw_pop <= 1'b0;
            ar_pop <= 1'b0;
            if (!req_v) begin
                if (!ar_empty) begin
                    ar_pop <= 1'b1;
                    req_v  <= 1'b1;
                    req_d  <= {1'b0, ar_dout};
                    r_beats_rem <= {1'b0, ar_dout[12:5]} + 9'd1;
                    if (outstanding_rd_cnt < 3'd7)
                        outstanding_rd_cnt <= outstanding_rd_cnt + 1'b1;
                end else if (!aw_empty) begin
                    aw_pop <= 1'b1;
                    req_v  <= 1'b1;
                    req_d  <= {1'b1, aw_dout};
                end
            end else if (req_v && req_ready) begin
                req_v <= 1'b0;
            end
        end
    end

    reg wbuf_v;
    reg [WW-1:0] wbuf_d;

    assign wbuf_valid = wbuf_v;
    assign {wbuf_data,wbuf_strb,wbuf_last,wbuf_id} = wbuf_d;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wbuf_v <= 1'b0;
            wbuf_d <= {WW{1'b0}};
            w_pop  <= 1'b0;
        end else begin
            w_pop <= 1'b0;
            if (!wbuf_v && !w_empty) begin
                w_pop  <= 1'b1;
                wbuf_v <= 1'b1;
                wbuf_d <= w_dout;
            end else if (wbuf_v && wbuf_ready) begin
                wbuf_v <= 1'b0;
            end
        end
    end

    assign rbuf_ready = (!s_axi_rvalid);

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rid    <= {AXI_ID_WIDTH{1'b0}};
            s_axi_rdata  <= {AXI_DATA_WIDTH{1'b0}};
            s_axi_rresp  <= 2'b00;
            s_axi_rlast  <= 1'b0;
        end else begin
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
            if (!s_axi_rvalid && rbuf_valid) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rid    <= rbuf_id;
                s_axi_rdata  <= rbuf_data;
                s_axi_rresp  <= 2'b00;
                s_axi_rlast  <= (r_beats_rem == 9'd1);
                if (r_beats_rem != 0) r_beats_rem <= r_beats_rem - 1'b1;
                if (r_beats_rem == 9'd1 && outstanding_rd_cnt > 3'd0)
                    outstanding_rd_cnt <= outstanding_rd_cnt - 1'b1;
            end
        end
    end

    assign wr_done_ready = (!s_axi_bvalid) || (s_axi_bvalid && s_axi_bready);

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            s_axi_bvalid <= 1'b0;
            s_axi_bid    <= {AXI_ID_WIDTH{1'b0}};
            s_axi_bresp  <= 2'b00;
        end else begin
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
            if (!s_axi_bvalid && wr_done_valid) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bid    <= wr_done_id;
                s_axi_bresp  <= 2'b00;
            end
        end
    end
endmodule
