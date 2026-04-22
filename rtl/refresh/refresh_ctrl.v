`timescale 1ns/1ps
`include "ddr3_params.vh"

// ============================================================
// 刷新控制器
// - 周期到期产生 refresh_pending
// - 超过 8*tREFI 进入紧急刷新 urgent_refresh
// ============================================================
module refresh_ctrl (
    input  wire clk,
    input  wire rst_n,
    input  wire refresh_ack,
    output reg  refresh_pending,
    output reg  urgent_refresh
);
    reg [15:0] ref_cnt;
    reg [18:0] overdue_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ref_cnt         <= 16'd0;
            overdue_cnt     <= 19'd0;
            refresh_pending <= 1'b0;
            urgent_refresh  <= 1'b0;
        end else begin
            if (refresh_ack) begin
                ref_cnt         <= 16'd0;
                overdue_cnt     <= 19'd0;
                refresh_pending <= 1'b0;
                urgent_refresh  <= 1'b0;
            end else begin
                if (ref_cnt < `tREFI) ref_cnt <= ref_cnt + 1'b1;
                else begin
                    refresh_pending <= 1'b1;
                    if (&overdue_cnt) overdue_cnt <= overdue_cnt;
                    else              overdue_cnt <= overdue_cnt + 1'b1;
                end
                if (overdue_cnt > (`tREFI * 8)) urgent_refresh <= 1'b1;
            end
        end
    end
endmodule
