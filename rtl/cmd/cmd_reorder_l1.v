`timescale 1ns/1ps
`include "ddr3_params.vh"

// ============================================================
// 命令重排 L1：page hit 优先插队
// 机制：
// - 输入命令先进先出进入 pending 队列
// - 若队列内存在“命中已开行”的命令，则优先取最早命中项
// - 否则按原始顺序（队头）输出
// ============================================================
module cmd_reorder_l1 #(
    parameter ID_WIDTH = `AXI_ID_WIDTH,
    parameter DEPTH    = 16,
    parameter AW       = 4
) (
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire                     in_valid,
    output wire                     in_ready,
    input  wire                     in_rw,
    input  wire [ID_WIDTH-1:0]      in_id,
    input  wire [`DDR_BANK_BITS-1:0] in_bank,
    input  wire [`DDR_ROW_BITS-1:0]  in_row,
    input  wire [`DDR_COL_BITS-1:0]  in_col,
    input  wire [7:0]               in_len,

    input  wire [`DDR_BANK_NUM-1:0] open_row_valid,
    input  wire [`DDR_BANK_NUM*`DDR_ROW_BITS-1:0] open_row_flat,

    output reg                      out_valid,
    input  wire                     out_ready,
    output reg                      out_rw,
    output reg  [ID_WIDTH-1:0]      out_id,
    output reg  [`DDR_BANK_BITS-1:0] out_bank,
    output reg  [`DDR_ROW_BITS-1:0]  out_row,
    output reg  [`DDR_COL_BITS-1:0]  out_col,
    output reg  [7:0]               out_len
);

    reg q_rw   [0:DEPTH-1];
    reg [ID_WIDTH-1:0] q_id [0:DEPTH-1];
    reg [`DDR_BANK_BITS-1:0] q_bank [0:DEPTH-1];
    reg [`DDR_ROW_BITS-1:0]  q_row  [0:DEPTH-1];
    reg [`DDR_COL_BITS-1:0]  q_col  [0:DEPTH-1];
    reg [7:0]                q_len  [0:DEPTH-1];
    reg                      q_vld  [0:DEPTH-1];
    reg [7:0]                q_starve[0:DEPTH-1];

    integer i;
    reg [AW:0] used;
    reg [AW-1:0] free_idx;
    reg free_found;

    reg [AW-1:0] sel_idx;
    reg sel_found;
    reg hit_found;
    reg [AW-1:0] hit_idx;
    reg [AW-1:0] first_idx;
    reg starve_found;
    reg [AW-1:0] starve_idx;

    assign in_ready = (used < DEPTH);

    always @(*) begin
        free_found  = 1'b0;
        free_idx    = {AW{1'b0}};
        first_idx   = {AW{1'b0}};
        sel_idx     = {AW{1'b0}};
        sel_found   = 1'b0;
        hit_found   = 1'b0;
        hit_idx     = {AW{1'b0}};
        starve_found = 1'b0;
        starve_idx  = {AW{1'b0}};

        for (i = 0; i < DEPTH; i = i + 1) begin
            if (!q_vld[i] && !free_found) begin
                free_found = 1'b1;
                free_idx   = i[AW-1:0];
            end
            if (q_vld[i] && !sel_found) begin
                sel_found = 1'b1;
                first_idx = i[AW-1:0];
            end
        end

        for (i = 0; i < DEPTH; i = i + 1) begin
            if (q_vld[i] && !hit_found) begin
                if (open_row_valid[q_bank[i]] &&
                    open_row_flat[q_bank[i]*`DDR_ROW_BITS +: `DDR_ROW_BITS] == q_row[i]) begin
                    hit_found = 1'b1;
                    hit_idx   = i[AW-1:0];
                end
            end
        end

        // Starvation check: if any entry starved to max, force-select it
        for (i = 0; i < DEPTH; i = i + 1) begin
            if (q_vld[i] && !starve_found && q_starve[i] >= 8'd255) begin
                starve_found = 1'b1;
                starve_idx   = i[AW-1:0];
            end
        end

        if (starve_found)    sel_idx = starve_idx;
        else if (hit_found)  sel_idx = hit_idx;
        else                 sel_idx = first_idx;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            used      <= {(AW+1){1'b0}};
            out_valid <= 1'b0;
            out_rw    <= 1'b0;
            out_id    <= {ID_WIDTH{1'b0}};
            out_bank  <= {`DDR_BANK_BITS{1'b0}};
            out_row   <= {`DDR_ROW_BITS{1'b0}};
            out_col   <= {`DDR_COL_BITS{1'b0}};
            out_len   <= 8'd0;
            for (i = 0; i < DEPTH; i = i + 1) begin
                q_vld[i]    <= 1'b0;
                q_starve[i] <= 8'd0;
            end
        end else begin
            if (in_valid && in_ready && free_found) begin
                q_vld[free_idx]    <= 1'b1;
                q_rw[free_idx]     <= in_rw;
                q_id[free_idx]     <= in_id;
                q_bank[free_idx]   <= in_bank;
                q_row[free_idx]    <= in_row;
                q_col[free_idx]    <= in_col;
                q_len[free_idx]    <= in_len;
                q_starve[free_idx] <= 8'd0;
                used               <= used + 1'b1;
            end

            // Starvation counter: increment all valid entries each cycle;
            // reset on entry insertion or on selection
            for (i = 0; i < DEPTH; i = i + 1) begin
                if (in_valid && in_ready && free_found && free_idx == i[AW-1:0]) begin
                    q_starve[i] <= 8'd0;
                end else if (out_valid && out_ready && sel_idx == i[AW-1:0]) begin
                    q_starve[i] <= 8'd0;
                end else if (q_vld[i] && q_starve[i] < 8'd255) begin
                    q_starve[i] <= q_starve[i] + 8'd1;
                end
            end

            if (!out_valid && sel_found) begin
                out_valid <= 1'b1;
                out_rw    <= q_rw[sel_idx];
                out_id    <= q_id[sel_idx];
                out_bank  <= q_bank[sel_idx];
                out_row   <= q_row[sel_idx];
                out_col   <= q_col[sel_idx];
                out_len   <= q_len[sel_idx];
            end

            if (out_valid && out_ready) begin
                out_valid    <= 1'b0;
                q_vld[sel_idx] <= 1'b0;
                used         <= used - 1'b1;
            end
        end
    end
endmodule
