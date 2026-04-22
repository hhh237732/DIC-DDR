`timescale 1ns/1ps
`include "ddr3_params.vh"

// ============================================================
// 通用同步 FIFO（单时钟域）
// 可复用在 AXI 解耦、命令队列、数据缓冲等场景。
// ============================================================
module sync_fifo #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH      = 16,
    parameter ADDR_WIDTH = 4
) (
    input  wire                  clk,        // 时钟
    input  wire                  rst_n,      // 低有效复位
    input  wire                  wr_en,      // 写使能
    input  wire [DATA_WIDTH-1:0] wr_data,    // 写入数据
    input  wire                  rd_en,      // 读使能
    output wire [DATA_WIDTH-1:0] rd_data,    // 读出数据
    output wire                  full,       // FIFO 满标志
    output wire                  empty,      // FIFO 空标志
    output wire [ADDR_WIDTH:0]   level       // FIFO 当前占用深度
);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [ADDR_WIDTH:0]   count;

    assign full  = (count == DEPTH);
    assign empty = (count == 0);
    assign level = count;

    assign rd_data = mem[rd_ptr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr  <= {ADDR_WIDTH{1'b0}};
            rd_ptr  <= {ADDR_WIDTH{1'b0}};
            count   <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            case ({wr_en && !full, rd_en && !empty})
                2'b10: begin
                    mem[wr_ptr] <= wr_data;
                    wr_ptr      <= wr_ptr + 1'b1;
                    count       <= count + 1'b1;
                end
                2'b01: begin
                    rd_ptr  <= rd_ptr + 1'b1;
                    count   <= count - 1'b1;
                end
                2'b11: begin
                    mem[wr_ptr] <= wr_data;
                    wr_ptr      <= wr_ptr + 1'b1;
                    rd_ptr       <= rd_ptr + 1'b1;
                end
                default: begin
                end
            endcase
        end
    end
endmodule
