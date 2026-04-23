`timescale 1ns/1ps
`include "ddr3_params.vh"

// ============================================================
// 单 Bank 控制器
// 维护开行状态与关键时序计数器，给调度层提供可发命令条件。
// ============================================================
module bank_ctrl #(
    parameter ROW_BITS = `DDR_ROW_BITS
) (
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire                   issue_act,
    input  wire                   issue_rd,
    input  wire                   issue_wr,
    input  wire                   issue_pre,
    input  wire [ROW_BITS-1:0]    act_row,

    output reg                    row_open,
    output reg  [ROW_BITS-1:0]    open_row,

    output wire                   can_act,
    output wire                   can_read,
    output wire                   can_write,
    output wire                   can_pre
);
    reg [7:0] trcd_cnt, trp_cnt, tras_cnt, trc_cnt, twr_cnt, trtp_cnt, tccd_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_open <= 1'b0;
            open_row <= {ROW_BITS{1'b0}};
            trcd_cnt <= 0; trp_cnt <= 0; tras_cnt <= 0; trc_cnt <= 0;
            twr_cnt  <= 0; trtp_cnt<= 0; tccd_cnt<= 0;
        end else begin
            if (trcd_cnt != 0) trcd_cnt <= trcd_cnt - 1'b1;
            if (trp_cnt  != 0) trp_cnt  <= trp_cnt  - 1'b1;
            if (tras_cnt != 0) tras_cnt <= tras_cnt - 1'b1;
            if (trc_cnt  != 0) trc_cnt  <= trc_cnt  - 1'b1;
            if (twr_cnt  != 0) twr_cnt  <= twr_cnt  - 1'b1;
            if (trtp_cnt != 0) trtp_cnt <= trtp_cnt - 1'b1;
            if (tccd_cnt != 0) tccd_cnt <= tccd_cnt - 1'b1;

            if (issue_act && can_act) begin
                row_open <= 1'b1;
                open_row <= act_row;
                trcd_cnt <= `tRCD;
                tras_cnt <= `tRAS;
                trc_cnt  <= `tRC;
            end

            if (issue_rd && can_read) begin
                tccd_cnt <= `tCCD;
                trtp_cnt <= `tRTP;
            end

            if (issue_wr && can_write) begin
                tccd_cnt <= `tCCD;
                twr_cnt  <= `tWR;
            end

            if (issue_pre && can_pre) begin
                row_open <= 1'b0;
                trp_cnt  <= `tRP;
            end
        end
    end

    assign can_act   = (!row_open) && (trp_cnt == 0) && (trc_cnt == 0);
    assign can_read  = row_open && (trcd_cnt == 0) && (tccd_cnt == 0);
    assign can_write = row_open && (trcd_cnt == 0) && (tccd_cnt == 0);
    assign can_pre   = row_open && (tras_cnt == 0) && (twr_cnt == 0) && (trtp_cnt == 0);
endmodule
