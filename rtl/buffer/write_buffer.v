`timescale 1ns/1ps
`include "ddr3_params.vh"

// ============================================================
// 写数据缓冲：按命令调度顺序吐出写 beat
// ============================================================
module write_buffer #(
    parameter DW = `DDR_DQ_WIDTH,
    parameter IW = `AXI_ID_WIDTH
) (
    input  wire             clk,
    input  wire             rst_n,

    input  wire             in_valid,
    output wire             in_ready,
    input  wire [DW-1:0]    in_data,
    input  wire [DW/8-1:0]  in_strb,
    input  wire             in_last,
    input  wire [IW-1:0]    in_id,

    output wire             out_valid,
    input  wire             out_ready,
    output wire [DW-1:0]    out_data,
    output wire [DW/8-1:0]  out_strb,
    output wire             out_last,
    output wire [IW-1:0]    out_id
);
    localparam W = DW + DW/8 + 1 + IW;
    wire [W-1:0] rd_data;
    wire full, empty;

    sync_fifo #(.DATA_WIDTH(W), .DEPTH(128), .ADDR_WIDTH(7)) u_wb_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_en(in_valid && in_ready), .wr_data({in_data,in_strb,in_last,in_id}),
        .rd_en(out_ready && out_valid), .rd_data(rd_data),
        .full(full), .empty(empty), .level()
    );

    assign in_ready = !full;
    assign out_valid = !empty;
    assign {out_data,out_strb,out_last,out_id} = rd_data;
endmodule
