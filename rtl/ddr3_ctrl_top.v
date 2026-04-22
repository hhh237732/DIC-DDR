`timescale 1ns/1ps
`include "ddr3_params.vh"

// ============================================================
// DDR3 控制器顶层
// 集成：AXI -> split -> reorder -> bank/refresh/init -> dfi
// ============================================================
module ddr3_ctrl_top (
    input  wire                         aclk,
    input  wire                         aresetn,

    input  wire [`AXI_ID_WIDTH-1:0]     s_axi_awid,
    input  wire [`AXI_ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire [7:0]                   s_axi_awlen,
    input  wire [2:0]                   s_axi_awsize,
    input  wire [1:0]                   s_axi_awburst,
    input  wire                         s_axi_awvalid,
    output wire                         s_axi_awready,

    input  wire [`DDR_DQ_WIDTH-1:0]     s_axi_wdata,
    input  wire [`DDR_STRB_WIDTH-1:0]   s_axi_wstrb,
    input  wire                         s_axi_wlast,
    input  wire                         s_axi_wvalid,
    output wire                         s_axi_wready,

    output wire [`AXI_ID_WIDTH-1:0]     s_axi_bid,
    output wire [1:0]                   s_axi_bresp,
    output wire                         s_axi_bvalid,
    input  wire                         s_axi_bready,

    input  wire [`AXI_ID_WIDTH-1:0]     s_axi_arid,
    input  wire [`AXI_ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire [7:0]                   s_axi_arlen,
    input  wire [2:0]                   s_axi_arsize,
    input  wire [1:0]                   s_axi_arburst,
    input  wire                         s_axi_arvalid,
    output wire                         s_axi_arready,

    output wire [`AXI_ID_WIDTH-1:0]     s_axi_rid,
    output wire [`DDR_DQ_WIDTH-1:0]     s_axi_rdata,
    output wire [1:0]                   s_axi_rresp,
    output wire                         s_axi_rlast,
    output wire                         s_axi_rvalid,
    input  wire                         s_axi_rready,

    output wire                         dfi_cke,
    output wire                         dfi_cs_n,
    output wire                         dfi_ras_n,
    output wire                         dfi_cas_n,
    output wire                         dfi_we_n,
    output wire [`DDR_BANK_BITS-1:0]    dfi_bank,
    output wire [`DDR_ROW_BITS-1:0]     dfi_addr,
    output wire [`DDR_DQ_WIDTH-1:0]     dfi_wrdata,
    output wire [`DDR_STRB_WIDTH-1:0]   dfi_wrdata_mask,
    output wire                         dfi_wrdata_en,
    input  wire [`DDR_DQ_WIDTH-1:0]     dfi_rddata,
    input  wire                         dfi_rddata_valid
);

    // ---------------- AXI IF ----------------
    wire req_valid, req_ready, req_rw;
    wire [`AXI_ID_WIDTH-1:0] req_id;
    wire [`AXI_ADDR_WIDTH-1:0] req_addr;
    wire [7:0] req_len;
    wire [2:0] req_size;
    wire [1:0] req_burst;

    wire wbuf_in_valid, wbuf_in_ready, wbuf_in_last;
    wire [`DDR_DQ_WIDTH-1:0] wbuf_in_data;
    wire [`DDR_STRB_WIDTH-1:0] wbuf_in_strb;
    wire [`AXI_ID_WIDTH-1:0] wbuf_in_id;

    wire rb_out_valid, rb_out_ready, rb_out_last;
    wire [`DDR_DQ_WIDTH-1:0] rb_out_data;
    wire [`AXI_ID_WIDTH-1:0] rb_out_id;

    reg wr_done_valid;
    reg [`AXI_ID_WIDTH-1:0] wr_done_id;
    wire wr_done_ready;

    axi_slave_if u_axi (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awid(s_axi_awid), .s_axi_awaddr(s_axi_awaddr), .s_axi_awlen(s_axi_awlen),
        .s_axi_awsize(s_axi_awsize), .s_axi_awburst(s_axi_awburst),
        .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wlast(s_axi_wlast),
        .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bid(s_axi_bid), .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_arid(s_axi_arid), .s_axi_araddr(s_axi_araddr), .s_axi_arlen(s_axi_arlen),
        .s_axi_arsize(s_axi_arsize), .s_axi_arburst(s_axi_arburst),
        .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rid(s_axi_rid), .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
        .s_axi_rlast(s_axi_rlast), .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .req_valid(req_valid), .req_ready(req_ready), .req_rw(req_rw), .req_id(req_id),
        .req_addr(req_addr), .req_len(req_len), .req_size(req_size), .req_burst(req_burst),
        .wbuf_valid(wbuf_in_valid), .wbuf_ready(wbuf_in_ready), .wbuf_data(wbuf_in_data),
        .wbuf_strb(wbuf_in_strb), .wbuf_last(wbuf_in_last), .wbuf_id(wbuf_in_id),
        .rbuf_valid(rb_out_valid), .rbuf_ready(rb_out_ready), .rbuf_data(rb_out_data),
        .rbuf_last(rb_out_last), .rbuf_id(rb_out_id),
        .wr_done_valid(wr_done_valid), .wr_done_id(wr_done_id), .wr_done_ready(wr_done_ready)
    );

    // ---------------- cmd split ----------------
    wire sp_valid, sp_ready, sp_rw;
    wire [`AXI_ID_WIDTH-1:0] sp_id;
    wire [`DDR_BANK_BITS-1:0] sp_bank;
    wire [`DDR_ROW_BITS-1:0] sp_row;
    wire [`DDR_COL_BITS-1:0] sp_col;
    wire [7:0] sp_len;

    cmd_split u_split (
        .clk(aclk), .rst_n(aresetn),
        .in_valid(req_valid), .in_ready(req_ready), .in_rw(req_rw), .in_id(req_id),
        .in_addr(req_addr), .in_len(req_len), .in_size(req_size), .in_burst(req_burst),
        .out_valid(sp_valid), .out_ready(sp_ready), .out_rw(sp_rw), .out_id(sp_id),
        .out_bank(sp_bank), .out_row(sp_row), .out_col(sp_col), .out_len(sp_len), .busy()
    );

    // ---------------- bank status + l1/l2 ----------------
    wire [`DDR_BANK_NUM-1:0] row_open_vec;
    wire [`DDR_BANK_NUM*`DDR_ROW_BITS-1:0] open_row_flat;
    wire [`DDR_BANK_NUM-1:0] can_act_vec, can_read_vec, can_write_vec, can_pre_vec;
    wire global_can_act;

    reg issue_act, issue_rd, issue_wr, issue_pre;
    reg [`DDR_BANK_BITS-1:0] issue_bank;
    reg [`DDR_ROW_BITS-1:0] issue_row;

    bank_ctrl_top u_bank_top (
        .clk(aclk), .rst_n(aresetn),
        .issue_act(issue_act), .issue_rd(issue_rd), .issue_wr(issue_wr), .issue_pre(issue_pre),
        .issue_bank(issue_bank), .issue_row(issue_row),
        .row_open_vec(row_open_vec), .open_row_flat(open_row_flat),
        .can_act_vec(can_act_vec), .can_read_vec(can_read_vec), .can_write_vec(can_write_vec), .can_pre_vec(can_pre_vec),
        .global_can_act(global_can_act)
    );

    wire l1_valid, l1_ready, l1_rw;
    wire [`AXI_ID_WIDTH-1:0] l1_id;
    wire [`DDR_BANK_BITS-1:0] l1_bank;
    wire [`DDR_ROW_BITS-1:0] l1_row;
    wire [`DDR_COL_BITS-1:0] l1_col;
    wire [7:0] l1_len;

    cmd_reorder_l1 u_l1 (
        .clk(aclk), .rst_n(aresetn),
        .in_valid(sp_valid), .in_ready(sp_ready), .in_rw(sp_rw), .in_id(sp_id),
        .in_bank(sp_bank), .in_row(sp_row), .in_col(sp_col), .in_len(sp_len),
        .open_row_valid(row_open_vec), .open_row_flat(open_row_flat),
        .out_valid(l1_valid), .out_ready(l1_ready), .out_rw(l1_rw), .out_id(l1_id),
        .out_bank(l1_bank), .out_row(l1_row), .out_col(l1_col), .out_len(l1_len)
    );

    wire rf_pending, rf_urgent, allow_refresh;
    reg  rf_ack;

    refresh_ctrl u_refresh (
        .clk(aclk), .rst_n(aresetn), .refresh_ack(rf_ack),
        .refresh_pending(rf_pending), .urgent_refresh(rf_urgent)
    );

    wire l2_valid, l2_ready, l2_rw, l2_auto_pre;
    wire [`AXI_ID_WIDTH-1:0] l2_id;
    wire [`DDR_BANK_BITS-1:0] l2_bank;
    wire [`DDR_ROW_BITS-1:0] l2_row;
    wire [`DDR_COL_BITS-1:0] l2_col;
    wire [7:0] l2_len;

    cmd_reorder_l2 u_l2 (
        .clk(aclk), .rst_n(aresetn),
        .in_valid(l1_valid), .in_ready(l1_ready), .in_rw(l1_rw), .in_id(l1_id),
        .in_bank(l1_bank), .in_row(l1_row), .in_col(l1_col), .in_len(l1_len),
        .refresh_pending(rf_pending), .urgent_read(rf_urgent),
        .out_valid(l2_valid), .out_ready(l2_ready), .out_rw(l2_rw), .out_id(l2_id),
        .out_bank(l2_bank), .out_row(l2_row), .out_col(l2_col), .out_len(l2_len), .out_auto_pre(l2_auto_pre),
        .allow_refresh(allow_refresh)
    );

    // ---------------- data buffers ----------------
    wire wb_out_valid, wb_out_ready, wb_out_last;
    wire [`DDR_DQ_WIDTH-1:0] wb_out_data;
    wire [`DDR_STRB_WIDTH-1:0] wb_out_strb;
    wire [`AXI_ID_WIDTH-1:0] wb_out_id;

    write_buffer u_wbuf (
        .clk(aclk), .rst_n(aresetn),
        .in_valid(wbuf_in_valid), .in_ready(wbuf_in_ready), .in_data(wbuf_in_data), .in_strb(wbuf_in_strb),
        .in_last(wbuf_in_last), .in_id(wbuf_in_id),
        .out_valid(wb_out_valid), .out_ready(wb_out_ready), .out_data(wb_out_data), .out_strb(wb_out_strb),
        .out_last(wb_out_last), .out_id(wb_out_id)
    );

    reg rb_in_valid, rb_in_last;
    reg [`DDR_DQ_WIDTH-1:0] rb_in_data;
    reg [`AXI_ID_WIDTH-1:0] rb_in_id;
    wire rb_in_ready;

    read_buffer u_rbuf (
        .clk(aclk), .rst_n(aresetn),
        .in_valid(rb_in_valid), .in_ready(rb_in_ready), .in_data(rb_in_data), .in_last(rb_in_last), .in_id(rb_in_id),
        .out_valid(rb_out_valid), .out_ready(rb_out_ready), .out_data(rb_out_data), .out_last(rb_out_last), .out_id(rb_out_id)
    );

    // ---------------- init + dfi ----------------
    wire init_done;
    wire init_cmd_valid, init_cmd_ready;
    wire [2:0] init_cmd;
    wire [`DDR_BANK_BITS-1:0] init_bank;
    wire [`DDR_ROW_BITS-1:0] init_addr;
    wire init_cke;

    init_fsm u_init (
        .clk(aclk), .rst_n(aresetn), .init_done(init_done),
        .cmd_valid(init_cmd_valid), .cmd_ready(init_cmd_ready), .cmd(init_cmd),
        .cmd_bank(init_bank), .cmd_addr(init_addr), .cke(init_cke)
    );

    reg dfi_cmd_valid;
    reg [2:0] dfi_cmd;
    reg [`DDR_BANK_BITS-1:0] dfi_cmd_bank_r;
    reg [`DDR_ROW_BITS-1:0] dfi_cmd_addr_r;
    reg dfi_cmd_a10;

    reg dfi_wr_valid_r;
    reg [`DDR_DQ_WIDTH-1:0] dfi_wr_data_r;
    reg [`DDR_STRB_WIDTH-1:0] dfi_wr_mask_r;

    wire dfi_cmd_ready;
    wire dfi_wr_ready;
    wire [`DDR_DQ_WIDTH-1:0] dfi_rd_data_int;
    wire dfi_rd_valid_int;

    dfi_if u_dfi (
        .clk(aclk), .rst_n(aresetn),
        .cmd_valid(dfi_cmd_valid), .cmd_ready(dfi_cmd_ready),
        .cmd(dfi_cmd), .cmd_bank(dfi_cmd_bank_r), .cmd_addr(dfi_cmd_addr_r), .cmd_a10(dfi_cmd_a10), .cke_in(init_cke),
        .wr_data(dfi_wr_data_r), .wr_mask(dfi_wr_mask_r), .wr_data_valid(dfi_wr_valid_r), .wr_data_ready(dfi_wr_ready),
        .rd_data(dfi_rd_data_int), .rd_data_valid(dfi_rd_valid_int),
        .dfi_cke(dfi_cke), .dfi_cs_n(dfi_cs_n), .dfi_ras_n(dfi_ras_n), .dfi_cas_n(dfi_cas_n), .dfi_we_n(dfi_we_n),
        .dfi_bank(dfi_bank), .dfi_addr(dfi_addr), .dfi_wrdata(dfi_wrdata), .dfi_wrdata_mask(dfi_wrdata_mask), .dfi_wrdata_en(dfi_wrdata_en),
        .dfi_rddata(dfi_rddata), .dfi_rddata_valid(dfi_rddata_valid)
    );

    assign init_cmd_ready = dfi_cmd_ready;

    // ---------------- read tag fifo ----------------
    wire [6:0] rtag_level;
    wire rtag_full, rtag_empty;
    reg rtag_wr_en, rtag_rd_en;
    reg [`AXI_ID_WIDTH:0] rtag_wr_data;
    wire [`AXI_ID_WIDTH:0] rtag_rd_data;

    sync_fifo #(.DATA_WIDTH(`AXI_ID_WIDTH+1), .DEPTH(64), .ADDR_WIDTH(6)) u_rtag_fifo (
        .clk(aclk), .rst_n(aresetn),
        .wr_en(rtag_wr_en), .wr_data(rtag_wr_data), .rd_en(rtag_rd_en), .rd_data(rtag_rd_data),
        .full(rtag_full), .empty(rtag_empty), .level(rtag_level)
    );

    // ---------------- scheduler FSM ----------------
    localparam SCH_IDLE  = 3'd0;
    localparam SCH_PRE   = 3'd1;
    localparam SCH_ACT   = 3'd2;
    localparam SCH_RW    = 3'd3;
    localparam SCH_APRE  = 3'd4;
    localparam SCH_REF   = 3'd5;

    reg [2:0] sch_st;
    reg cur_rw;
    reg [`AXI_ID_WIDTH-1:0] cur_id;
    reg [`DDR_BANK_BITS-1:0] cur_bank;
    reg [`DDR_ROW_BITS-1:0] cur_row;
    reg [`DDR_COL_BITS-1:0] cur_col;
    reg [8:0] cur_beats;
    reg cur_auto_pre;

    wire bank_row_open = row_open_vec[cur_bank];
    wire [`DDR_ROW_BITS-1:0] bank_open_row = open_row_flat[cur_bank*`DDR_ROW_BITS +: `DDR_ROW_BITS];

    assign l2_ready = (sch_st == SCH_IDLE) && init_done;

    assign wb_out_ready = (sch_st == SCH_RW) && cur_rw && can_write_vec[cur_bank] && dfi_cmd_ready && dfi_wr_ready;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            sch_st <= SCH_IDLE;
            cur_rw <= 1'b0; cur_id <= 0; cur_bank <= 0; cur_row <= 0; cur_col <= 0; cur_beats <= 0; cur_auto_pre <= 1'b0;
            issue_act <= 1'b0; issue_rd <= 1'b0; issue_wr <= 1'b0; issue_pre <= 1'b0; issue_bank <= 0; issue_row <= 0;
            dfi_cmd_valid <= 1'b0; dfi_cmd <= `CMD_NOP; dfi_cmd_bank_r <= 0; dfi_cmd_addr_r <= 0; dfi_cmd_a10 <= 1'b0;
            dfi_wr_valid_r <= 1'b0; dfi_wr_data_r <= 0; dfi_wr_mask_r <= 0;
            wr_done_valid <= 1'b0; wr_done_id <= 0;
            rb_in_valid <= 1'b0; rb_in_last <= 1'b0; rb_in_data <= 0; rb_in_id <= 0;
            rf_ack <= 1'b0;
            rtag_wr_en <= 1'b0; rtag_rd_en <= 1'b0; rtag_wr_data <= 0;
        end else begin
            issue_act <= 1'b0; issue_rd <= 1'b0; issue_wr <= 1'b0; issue_pre <= 1'b0;
            dfi_cmd_valid <= 1'b0;
            dfi_cmd <= `CMD_NOP;
            dfi_cmd_a10 <= 1'b0;
            dfi_wr_valid_r <= 1'b0;
            wr_done_valid <= 1'b0;
            rb_in_valid <= 1'b0;
            rf_ack <= 1'b0;
            rtag_wr_en <= 1'b0;
            rtag_rd_en <= 1'b0;

            if (!init_done) begin
                if (init_cmd_valid && init_cmd_ready) begin
                    dfi_cmd_valid  <= 1'b1;
                    dfi_cmd        <= init_cmd;
                    dfi_cmd_bank_r <= init_bank;
                    dfi_cmd_addr_r <= init_addr;
                end
            end else begin
                if (dfi_rd_valid_int && !rtag_empty && rb_in_ready) begin
                    rb_in_valid <= 1'b1;
                    rb_in_data  <= dfi_rd_data_int;
                    rb_in_last  <= (rtag_level == 7'd1);
                    rb_in_id    <= rtag_rd_data[`AXI_ID_WIDTH:1];
                    rtag_rd_en  <= 1'b1;
                end

                case (sch_st)
                    SCH_IDLE: begin
                        if (rf_pending && allow_refresh) begin
                            sch_st <= SCH_REF;
                        end else if (l2_valid) begin
                            cur_rw   <= l2_rw;
                            cur_id   <= l2_id;
                            cur_bank <= l2_bank;
                            cur_row  <= l2_row;
                            cur_col  <= l2_col;
                            cur_beats<= {1'b0,l2_len} + 9'd1;
                            cur_auto_pre <= l2_auto_pre;
                            if (bank_row_open && bank_open_row != l2_row) sch_st <= SCH_PRE;
                            else if (!bank_row_open) sch_st <= SCH_ACT;
                            else sch_st <= SCH_RW;
                        end
                    end
                    SCH_PRE: begin
                        if (can_pre_vec[cur_bank] && dfi_cmd_ready) begin
                            dfi_cmd_valid  <= 1'b1;
                            dfi_cmd        <= `CMD_PRE;
                            dfi_cmd_bank_r <= cur_bank;
                            dfi_cmd_addr_r <= 0;
                            dfi_cmd_a10    <= 1'b0;
                            issue_pre      <= 1'b1;
                            issue_bank     <= cur_bank;
                            sch_st         <= SCH_ACT;
                        end
                    end
                    SCH_ACT: begin
                        if (can_act_vec[cur_bank] && global_can_act && dfi_cmd_ready) begin
                            dfi_cmd_valid  <= 1'b1;
                            dfi_cmd        <= `CMD_ACT;
                            dfi_cmd_bank_r <= cur_bank;
                            dfi_cmd_addr_r <= cur_row;
                            issue_act      <= 1'b1;
                            issue_bank     <= cur_bank;
                            issue_row      <= cur_row;
                            sch_st         <= SCH_RW;
                        end
                    end
                    SCH_RW: begin
                        if (cur_rw) begin
                            if (can_write_vec[cur_bank] && wb_out_valid && dfi_cmd_ready && dfi_wr_ready) begin
                                dfi_cmd_valid  <= 1'b1;
                                dfi_cmd        <= `CMD_WR;
                                dfi_cmd_bank_r <= cur_bank;
                                dfi_cmd_addr_r <= {5'd0,cur_col};
                                dfi_cmd_a10    <= 1'b0;
                                dfi_wr_valid_r <= 1'b1;
                                dfi_wr_data_r  <= wb_out_data;
                                dfi_wr_mask_r  <= ~wb_out_strb;
                                issue_wr       <= 1'b1;
                                issue_bank     <= cur_bank;
                                if (cur_beats == 9'd1) begin
                                    wr_done_valid <= 1'b1;
                                    wr_done_id    <= cur_id;
                                    if (cur_auto_pre) sch_st <= SCH_APRE;
                                    else sch_st <= SCH_IDLE;
                                end
                                cur_beats <= cur_beats - 1'b1;
                                cur_col   <= cur_col + 1'b1;
                            end
                        end else begin
                            if (can_read_vec[cur_bank] && dfi_cmd_ready && !rtag_full) begin
                                dfi_cmd_valid  <= 1'b1;
                                dfi_cmd        <= `CMD_RD;
                                dfi_cmd_bank_r <= cur_bank;
                                dfi_cmd_addr_r <= {5'd0,cur_col};
                                dfi_cmd_a10    <= 1'b0;
                                issue_rd       <= 1'b1;
                                issue_bank     <= cur_bank;
                                rtag_wr_en     <= 1'b1;
                                rtag_wr_data   <= {cur_id,(cur_beats==9'd1)};
                                if (cur_beats == 9'd1) begin
                                    if (cur_auto_pre) sch_st <= SCH_APRE;
                                    else sch_st <= SCH_IDLE;
                                end
                                cur_beats <= cur_beats - 1'b1;
                                cur_col   <= cur_col + 1'b1;
                            end
                        end
                    end
                    SCH_APRE: begin
                        if (can_pre_vec[cur_bank] && dfi_cmd_ready) begin
                            dfi_cmd_valid  <= 1'b1;
                            dfi_cmd        <= `CMD_PRE;
                            dfi_cmd_bank_r <= cur_bank;
                            dfi_cmd_addr_r <= 0;
                            dfi_cmd_a10    <= 1'b0;
                            issue_pre      <= 1'b1;
                            issue_bank     <= cur_bank;
                            sch_st         <= SCH_IDLE;
                        end
                    end
                    SCH_REF: begin
                        if (dfi_cmd_ready) begin
                            dfi_cmd_valid  <= 1'b1;
                            dfi_cmd        <= `CMD_REF;
                            dfi_cmd_bank_r <= 0;
                            dfi_cmd_addr_r <= 0;
                            rf_ack         <= 1'b1;
                            sch_st         <= SCH_IDLE;
                        end
                    end
                    default: sch_st <= SCH_IDLE;
                endcase
            end
        end
    end
endmodule
