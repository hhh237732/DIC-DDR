`timescale 1ns/1ps
`include "ddr3_params.vh"

// ============================================================
// 地址映射模块
// 默认策略：{row[14:0], bank[2:0], col[9:0], byte[1:0]}
// 备选策略：bank-interleave（将低位部分异或到 bank）
// ============================================================
module addr_map #(
    parameter ADDR_WIDTH = `AXI_ADDR_WIDTH,
    parameter MAP_MODE   = 0 // 0: default, 1: bank interleave
) (
    input  wire [ADDR_WIDTH-1:0] axi_addr,  // AXI 字节地址
    output reg  [`DDR_BANK_BITS-1:0] bank,  // bank 编号
    output reg  [`DDR_ROW_BITS-1:0]  row,   // row 地址
    output reg  [`DDR_COL_BITS-1:0]  col,   // col 地址（不含 byte）
    output wire [1:0]                byte_ofs
);
    wire [`DDR_ROW_BITS-1:0] row_def;
    wire [`DDR_BANK_BITS-1:0] bank_def;
    wire [`DDR_COL_BITS-1:0] col_def;

    assign byte_ofs = axi_addr[1:0];
    assign col_def  = axi_addr[11:2];
    assign bank_def = axi_addr[14:12];
    assign row_def  = axi_addr[29:15];

    always @(*) begin
        row  = row_def;
        col  = col_def;
        bank = bank_def;
        if (MAP_MODE == 1) begin
            bank = bank_def ^ col_def[2:0];
        end
    end
endmodule
