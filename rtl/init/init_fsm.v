`timescale 1ns/1ps
`include "ddr3_params.vh"

// ============================================================
// DDR3 初始化状态机（仿真友好版本）
// 序列：CKE低 -> 等待 -> CKE高 -> 等待 -> MRS2/3/1/0 -> ZQCL -> done
// ============================================================
module init_fsm (
    input  wire                     clk,
    input  wire                     rst_n,
    output reg                      init_done,

    output reg                      cmd_valid,
    input  wire                     cmd_ready,
    output reg [2:0]                cmd,
    output reg [`DDR_BANK_BITS-1:0] cmd_bank,
    output reg [`DDR_ROW_BITS-1:0]  cmd_addr,
    output reg                      cke
);
    localparam S_CKE_LOW_WAIT  = 4'd0;
    localparam S_CKE_HIGH_WAIT = 4'd1;
    localparam S_MRS2          = 4'd2;
    localparam S_MRS3          = 4'd3;
    localparam S_MRS1          = 4'd4;
    localparam S_MRS0          = 4'd5;
    localparam S_ZQCL          = 4'd6;
    localparam S_DONE          = 4'd7;

    reg [3:0] st;
    reg [15:0] wait_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st        <= S_CKE_LOW_WAIT;
            wait_cnt  <= 16'd0;
            init_done <= 1'b0;
            cmd_valid <= 1'b0;
            cmd       <= `CMD_NOP;
            cmd_bank  <= 3'd0;
            cmd_addr  <= {`DDR_ROW_BITS{1'b0}};
            cke       <= 1'b0;
        end else begin
            cmd_valid <= 1'b0;
            cmd       <= `CMD_NOP;
            case (st)
                S_CKE_LOW_WAIT: begin
                    cke <= 1'b0;
                    if (wait_cnt == `INIT_200US_CYC) begin
                        wait_cnt <= 16'd0;
                        st <= S_CKE_HIGH_WAIT;
                    end else wait_cnt <= wait_cnt + 1'b1;
                end
                S_CKE_HIGH_WAIT: begin
                    cke <= 1'b1;
                    if (wait_cnt == `INIT_500US_CYC) begin
                        wait_cnt <= 16'd0;
                        st <= S_MRS2;
                    end else wait_cnt <= wait_cnt + 1'b1;
                end
                S_MRS2,S_MRS3,S_MRS1,S_MRS0: begin
                    cmd_valid <= 1'b1;
                    cmd       <= `CMD_MRS;
                    cmd_bank  <= (st==S_MRS2)?3'd2:(st==S_MRS3)?3'd3:(st==S_MRS1)?3'd1:3'd0;
                    cmd_addr  <= {`DDR_ROW_BITS{1'b0}};
                    if (cmd_ready) st <= st + 1'b1;
                end
                S_ZQCL: begin
                    cmd_valid <= 1'b1;
                    cmd       <= `CMD_ZQCL;
                    if (cmd_ready) st <= S_DONE;
                end
                S_DONE: begin
                    init_done <= 1'b1;
                end
                default: st <= S_CKE_LOW_WAIT;
            endcase
        end
    end
endmodule
