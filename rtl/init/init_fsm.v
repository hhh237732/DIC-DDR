`timescale 1ns/1ps
`include "ddr3_params.vh"

// ============================================================
// DDR3 初始化状态机 v2（11步完整初始化序列）
// CKE低待机 → CKE拉高 → tXPR → MRS2/3/1/0 → ZQCL → done
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
    localparam S_CKE_DEASSERT  = 4'd1;
    localparam S_CKE_HIGH_WAIT = 4'd2;
    localparam S_MRS2          = 4'd3;
    localparam S_WAIT_MRS2     = 4'd4;
    localparam S_MRS3          = 4'd5;
    localparam S_WAIT_MRS3     = 4'd6;
    localparam S_MRS1          = 4'd7;
    localparam S_WAIT_MRS1     = 4'd8;
    localparam S_MRS0          = 4'd9;
    localparam S_WAIT_MRS0     = 4'd10;
    localparam S_ZQCL          = 4'd11;
    localparam S_WAIT_ZQINIT   = 4'd12;
    localparam S_DONE          = 4'd13;

    reg [3:0]  st;
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
                // Keep CKE low for T_SIM_INIT_CKE_LOW cycles
                S_CKE_LOW_WAIT: begin
                    cke <= 1'b0;
                    if (wait_cnt >= `T_SIM_INIT_CKE_LOW) begin
                        wait_cnt <= 16'd0;
                        st       <= S_CKE_DEASSERT;
                    end else begin
                        wait_cnt <= wait_cnt + 1'b1;
                    end
                end
                // Assert CKE for one cycle
                S_CKE_DEASSERT: begin
                    cke      <= 1'b1;
                    wait_cnt <= 16'd0;
                    st       <= S_CKE_HIGH_WAIT;
                end
                // Wait tXPR after CKE high
                S_CKE_HIGH_WAIT: begin
                    cke <= 1'b1;
                    if (wait_cnt >= `T_SIM_TXPR) begin
                        wait_cnt <= 16'd0;
                        st       <= S_MRS2;
                    end else begin
                        wait_cnt <= wait_cnt + 1'b1;
                    end
                end
                // MRS2: CWL=8 → addr bit[5:3]=001 → 0x0018
                S_MRS2: begin
                    cmd_valid <= 1'b1;
                    cmd       <= `CMD_MRS;
                    cmd_bank  <= 3'd2;
                    cmd_addr  <= 15'h0018;
                    if (cmd_ready) begin
                        wait_cnt <= 16'd0;
                        st       <= S_WAIT_MRS2;
                    end
                end
                S_WAIT_MRS2: begin
                    if (wait_cnt >= `T_INIT_TMRD) begin
                        wait_cnt <= 16'd0;
                        st       <= S_MRS3;
                    end else begin
                        wait_cnt <= wait_cnt + 1'b1;
                    end
                end
                // MRS3: no MPR, addr=0
                S_MRS3: begin
                    cmd_valid <= 1'b1;
                    cmd       <= `CMD_MRS;
                    cmd_bank  <= 3'd3;
                    cmd_addr  <= 15'h0000;
                    if (cmd_ready) begin
                        wait_cnt <= 16'd0;
                        st       <= S_WAIT_MRS3;
                    end
                end
                S_WAIT_MRS3: begin
                    if (wait_cnt >= `T_INIT_TMRD) begin
                        wait_cnt <= 16'd0;
                        st       <= S_MRS1;
                    end else begin
                        wait_cnt <= wait_cnt + 1'b1;
                    end
                end
                // MRS1: enable DLL, AL=0 → addr=0x0004 (DLL enable bit)
                S_MRS1: begin
                    cmd_valid <= 1'b1;
                    cmd       <= `CMD_MRS;
                    cmd_bank  <= 3'd1;
                    cmd_addr  <= 15'h0004;
                    if (cmd_ready) begin
                        wait_cnt <= 16'd0;
                        st       <= S_WAIT_MRS1;
                    end
                end
                S_WAIT_MRS1: begin
                    if (wait_cnt >= `T_INIT_TMRD) begin
                        wait_cnt <= 16'd0;
                        st       <= S_MRS0;
                    end else begin
                        wait_cnt <= wait_cnt + 1'b1;
                    end
                end
                // MRS0: CL=11(0b1110→bits[6:4,2])=0x0650, DLL reset, BL=8
                S_MRS0: begin
                    cmd_valid <= 1'b1;
                    cmd       <= `CMD_MRS;
                    cmd_bank  <= 3'd0;
                    cmd_addr  <= 15'h0650;
                    if (cmd_ready) begin
                        wait_cnt <= 16'd0;
                        st       <= S_WAIT_MRS0;
                    end
                end
                S_WAIT_MRS0: begin
                    if (wait_cnt >= `T_SIM_TMOD) begin
                        wait_cnt <= 16'd0;
                        st       <= S_ZQCL;
                    end else begin
                        wait_cnt <= wait_cnt + 1'b1;
                    end
                end
                // ZQCL calibration
                S_ZQCL: begin
                    cmd_valid <= 1'b1;
                    cmd       <= `CMD_ZQCL;
                    cmd_bank  <= 3'd0;
                    cmd_addr  <= 15'h0400;
                    if (cmd_ready) begin
                        wait_cnt <= 16'd0;
                        st       <= S_WAIT_ZQINIT;
                    end
                end
                S_WAIT_ZQINIT: begin
                    if (wait_cnt >= `T_SIM_ZQINIT) begin
                        wait_cnt <= 16'd0;
                        st       <= S_DONE;
                    end else begin
                        wait_cnt <= wait_cnt + 1'b1;
                    end
                end
                S_DONE: begin
                    init_done <= 1'b1;
                end
                default: st <= S_CKE_LOW_WAIT;
            endcase
        end
    end
endmodule
