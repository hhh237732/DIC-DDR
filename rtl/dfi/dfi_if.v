`timescale 1ns/1ps
`include "ddr3_params.vh"

// ============================================================
// DFI 接口映射
// 将内部命令编码映射为 DDR 命令脚（CS#/RAS#/CAS#/WE#）与地址/Bank。
// ============================================================
module dfi_if (
    input  wire                      clk,
    input  wire                      rst_n,

    input  wire                      cmd_valid,
    output wire                      cmd_ready,
    input  wire [2:0]                cmd,
    input  wire [`DDR_BANK_BITS-1:0] cmd_bank,
    input  wire [`DDR_ROW_BITS-1:0]  cmd_addr,
    input  wire                      cmd_a10,
    input  wire                      cke_in,

    input  wire [`DDR_DQ_WIDTH-1:0]  wr_data,
    input  wire [`DDR_STRB_WIDTH-1:0] wr_mask,
    input  wire                      wr_data_valid,
    output wire                      wr_data_ready,

    output wire [`DDR_DQ_WIDTH-1:0]  rd_data,
    output wire                      rd_data_valid,

    output reg                       dfi_cke,
    output reg                       dfi_cs_n,
    output reg                       dfi_ras_n,
    output reg                       dfi_cas_n,
    output reg                       dfi_we_n,
    output reg [`DDR_BANK_BITS-1:0]  dfi_bank,
    output reg [`DDR_ROW_BITS-1:0]   dfi_addr,
    output reg [`DDR_DQ_WIDTH-1:0]   dfi_wrdata,
    output reg [`DDR_STRB_WIDTH-1:0] dfi_wrdata_mask,
    output reg                       dfi_wrdata_en,

    input  wire [`DDR_DQ_WIDTH-1:0]  dfi_rddata,
    input  wire                      dfi_rddata_valid
);
    assign cmd_ready = 1'b1;
    assign wr_data_ready = 1'b1;
    assign rd_data = dfi_rddata;
    assign rd_data_valid = dfi_rddata_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dfi_cke <= 1'b0;
            dfi_cs_n <= 1'b1;
            dfi_ras_n <= 1'b1;
            dfi_cas_n <= 1'b1;
            dfi_we_n <= 1'b1;
            dfi_bank <= 0;
            dfi_addr <= 0;
            dfi_wrdata <= 0;
            dfi_wrdata_mask <= 0;
            dfi_wrdata_en <= 1'b0;
        end else begin
            dfi_cke <= cke_in;
            dfi_cs_n <= 1'b1;
            dfi_ras_n <= 1'b1;
            dfi_cas_n <= 1'b1;
            dfi_we_n <= 1'b1;
            dfi_wrdata_en <= 1'b0;

            if (cmd_valid) begin
                dfi_bank <= cmd_bank;
                dfi_addr <= cmd_addr;
                dfi_addr[10] <= cmd_a10;
                case (cmd)
                    `CMD_ACT: begin dfi_cs_n <= 1'b0; dfi_ras_n <= 1'b0; dfi_cas_n <= 1'b1; dfi_we_n <= 1'b1; end
                    `CMD_RD : begin dfi_cs_n <= 1'b0; dfi_ras_n <= 1'b1; dfi_cas_n <= 1'b0; dfi_we_n <= 1'b1; end
                    `CMD_WR : begin dfi_cs_n <= 1'b0; dfi_ras_n <= 1'b1; dfi_cas_n <= 1'b0; dfi_we_n <= 1'b0; end
                    `CMD_PRE: begin dfi_cs_n <= 1'b0; dfi_ras_n <= 1'b0; dfi_cas_n <= 1'b1; dfi_we_n <= 1'b0; end
                    `CMD_REF: begin dfi_cs_n <= 1'b0; dfi_ras_n <= 1'b0; dfi_cas_n <= 1'b0; dfi_we_n <= 1'b1; end
                    `CMD_MRS: begin dfi_cs_n <= 1'b0; dfi_ras_n <= 1'b0; dfi_cas_n <= 1'b0; dfi_we_n <= 1'b0; end
                    `CMD_ZQCL:begin dfi_cs_n <= 1'b0; dfi_ras_n <= 1'b1; dfi_cas_n <= 1'b1; dfi_we_n <= 1'b0; end
                    default: begin end
                endcase
            end

            if (wr_data_valid) begin
                dfi_wrdata      <= wr_data;
                dfi_wrdata_mask <= wr_mask;
                dfi_wrdata_en   <= 1'b1;
            end
        end
    end
endmodule
