`timescale 1ns/1ps
`include "ddr3_params.vh"

// ============================================================
// 简化 DDR3 行为模型
// 支持 ACT/RD/WR/PRE/REF 基本行为，用于控制器功能验证。
// ============================================================
module ddr3_model (
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      cke,
    input  wire                      cs_n,
    input  wire                      ras_n,
    input  wire                      cas_n,
    input  wire                      we_n,
    input  wire [`DDR_BANK_BITS-1:0] bank,
    input  wire [`DDR_ROW_BITS-1:0]  addr,
    input  wire [`DDR_DQ_WIDTH-1:0]  wrdata,
    input  wire [`DDR_STRB_WIDTH-1:0] wrdata_mask,
    input  wire                      wrdata_en,
    output reg  [`DDR_DQ_WIDTH-1:0]  rddata,
    output reg                       rddata_valid
);
    localparam MEM_AW = 20;
    localparam MEM_DW = `DDR_DQ_WIDTH;
    localparam MEM_WORDS = (1 << MEM_AW);

    reg [MEM_DW-1:0] mem [0:MEM_WORDS-1];

    reg bank_open [0:`DDR_BANK_NUM-1];
    reg [`DDR_ROW_BITS-1:0] open_row [0:`DDR_BANK_NUM-1];

    reg [15:0] rd_delay [0:63];
    reg [MEM_AW-1:0] rd_addr_q [0:63];
    reg rd_vld_q [0:63];

    integer i, b;
    reg [`DDR_COL_BITS-1:0] col_ctr [0:`DDR_BANK_NUM-1];
    reg [MEM_AW-1:0] curr_addr;

    function [MEM_AW-1:0] pack_addr;
        input [`DDR_BANK_BITS-1:0] f_bank;
        input [`DDR_ROW_BITS-1:0]  f_row;
        input [`DDR_COL_BITS-1:0]  f_col;
        reg [`DDR_ROW_BITS+`DDR_BANK_BITS+`DDR_COL_BITS-1:0] full_addr;
        begin
            // 使用完整 row/bank/col 位宽，并折叠到仿真内存地址宽度
            full_addr = {f_row, f_bank, f_col};
            pack_addr = full_addr[MEM_AW-1:0] ^ full_addr[MEM_AW+7:8];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rddata <= 0;
            rddata_valid <= 1'b0;
            for (b = 0; b < `DDR_BANK_NUM; b = b + 1) begin
                bank_open[b] <= 1'b0;
                open_row[b]  <= 0;
                col_ctr[b]   <= 0;
            end
            for (i = 0; i < 64; i = i + 1) begin
                rd_delay[i] <= 0;
                rd_addr_q[i] <= 0;
                rd_vld_q[i] <= 1'b0;
            end
        end else begin
            rddata_valid <= 1'b0;
            for (i = 0; i < 64; i = i + 1) begin
                if (rd_vld_q[i] && rd_delay[i] != 0) rd_delay[i] <= rd_delay[i] - 1'b1;
            end
            for (i = 0; i < 64; i = i + 1) begin
                if (rd_vld_q[i] && rd_delay[i] == 0) begin
                    rddata <= mem[rd_addr_q[i]];
                    rddata_valid <= 1'b1;
                    rd_vld_q[i] <= 1'b0;
                end
            end

            if (cke && !cs_n) begin
                // ACT
                if (!ras_n && cas_n && we_n) begin
                    bank_open[bank] <= 1'b1;
                    open_row[bank]  <= addr;
                    col_ctr[bank]   <= 0;
                end
                // READ
                if (ras_n && !cas_n && we_n) begin
                    if (bank_open[bank]) begin
                        for (i = 0; i < 64; i = i + 1) begin
                            if (!rd_vld_q[i]) begin
                                rd_vld_q[i]  <= 1'b1;
                                rd_delay[i]  <= `CL;
                                rd_addr_q[i] <= pack_addr(bank, open_row[bank], addr[`DDR_COL_BITS-1:0]);
                                col_ctr[bank] <= addr[`DDR_COL_BITS-1:0] + 1'b1;
                                i = 64;
                            end
                        end
                    end
                end
                // WRITE
                if (ras_n && !cas_n && !we_n && wrdata_en) begin
                    if (bank_open[bank]) begin
                        curr_addr = pack_addr(bank, open_row[bank], addr[`DDR_COL_BITS-1:0]);
                        for (i = 0; i < `DDR_STRB_WIDTH; i = i + 1) begin
                            if (!wrdata_mask[i]) mem[curr_addr][i*8 +: 8] <= wrdata[i*8 +: 8];
                        end
                        col_ctr[bank] <= addr[`DDR_COL_BITS-1:0] + 1'b1;
                    end
                end
                // PRE
                if (!ras_n && cas_n && !we_n) begin
                    if (addr[10]) begin
                        for (b = 0; b < `DDR_BANK_NUM; b = b + 1) bank_open[b] <= 1'b0;
                    end else begin
                        bank_open[bank] <= 1'b0;
                    end
                end
                // REF：仅作为接收，不建模详细阻塞
                if (!ras_n && !cas_n && we_n) begin
                    // no-op in simplified model
                end
            end
        end
    end
endmodule
