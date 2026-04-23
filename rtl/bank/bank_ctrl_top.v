`timescale 1ns/1ps
`include "ddr3_params.vh"

// ============================================================
// Bank 控制器顶层（8 个 bank）
// 包含 tRRD/tFAW 的全局 ACT 约束（近似实现）。
// ============================================================
module bank_ctrl_top (
    input  wire                             clk,
    input  wire                             rst_n,

    input  wire                             issue_act,
    input  wire                             issue_rd,
    input  wire                             issue_wr,
    input  wire                             issue_pre,
    input  wire [`DDR_BANK_BITS-1:0]        issue_bank,
    input  wire [`DDR_ROW_BITS-1:0]         issue_row,

    output wire [`DDR_BANK_NUM-1:0]         row_open_vec,
    output wire [`DDR_BANK_NUM*`DDR_ROW_BITS-1:0] open_row_flat,

    output wire [`DDR_BANK_NUM-1:0]         can_act_vec,
    output wire [`DDR_BANK_NUM-1:0]         can_read_vec,
    output wire [`DDR_BANK_NUM-1:0]         can_write_vec,
    output wire [`DDR_BANK_NUM-1:0]         can_pre_vec,

    output wire                             global_can_act
);
    genvar b;

    reg [7:0] trrd_cnt;
    reg [4:0] faw_hist [0:`tFAW-1];
    integer i;
    reg [2:0] act_in_window;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trrd_cnt <= 0;
            for (i = 0; i < `tFAW; i = i + 1) faw_hist[i] <= 0;
        end else begin
            if (trrd_cnt != 0) trrd_cnt <= trrd_cnt - 1'b1;
            for (i = `tFAW-1; i > 0; i = i - 1) faw_hist[i] <= faw_hist[i-1];
            faw_hist[0] <= (issue_act) ? 5'd1 : 5'd0;
            if (issue_act) trrd_cnt <= `tRRD;
        end
    end

    always @(*) begin
        act_in_window = 0;
        for (i = 0; i < `tFAW; i = i + 1) act_in_window = act_in_window + faw_hist[i][0];
    end

    assign global_can_act = (trrd_cnt == 0) && (act_in_window < 4);

    generate
        for (b = 0; b < `DDR_BANK_NUM; b = b + 1) begin: G_BANK
            bank_ctrl u_bank_ctrl (
                .clk(clk), .rst_n(rst_n),
                .issue_act(issue_act && issue_bank == b[2:0] && global_can_act),
                .issue_rd(issue_rd && issue_bank == b[2:0]),
                .issue_wr(issue_wr && issue_bank == b[2:0]),
                .issue_pre(issue_pre && issue_bank == b[2:0]),
                .act_row(issue_row),
                .row_open(row_open_vec[b]),
                .open_row(open_row_flat[b*`DDR_ROW_BITS +: `DDR_ROW_BITS]),
                .can_act(can_act_vec[b]),
                .can_read(can_read_vec[b]),
                .can_write(can_write_vec[b]),
                .can_pre(can_pre_vec[b])
            );
        end
    endgenerate
endmodule
