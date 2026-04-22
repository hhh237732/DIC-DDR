`timescale 1ns/1ps
`include "ddr3_params.vh"

// ============================================================
// 命令重排 L2：读写分组 + 优先级 + look-ahead + auto-precharge
// 优先级：refresh > urgent_read > write_group > read_group
// ============================================================
module cmd_reorder_l2 #(
    parameter ID_WIDTH = `AXI_ID_WIDTH,
    parameter DEPTH    = 16,
    parameter AW       = 4,
    parameter GROUP_MAX= 8
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

    input  wire                     refresh_pending,
    input  wire                     urgent_read,

    output reg                      out_valid,
    input  wire                     out_ready,
    output reg                      out_rw,
    output reg  [ID_WIDTH-1:0]      out_id,
    output reg  [`DDR_BANK_BITS-1:0] out_bank,
    output reg  [`DDR_ROW_BITS-1:0]  out_row,
    output reg  [`DDR_COL_BITS-1:0]  out_col,
    output reg  [7:0]               out_len,
    output reg                      out_auto_pre,

    output wire                     allow_refresh
);

    reg rd_vld[0:DEPTH-1], wr_vld[0:DEPTH-1];
    reg [ID_WIDTH-1:0] rd_id[0:DEPTH-1], wr_id[0:DEPTH-1];
    reg [`DDR_BANK_BITS-1:0] rd_bank[0:DEPTH-1], wr_bank[0:DEPTH-1];
    reg [`DDR_ROW_BITS-1:0]  rd_row[0:DEPTH-1],  wr_row[0:DEPTH-1];
    reg [`DDR_COL_BITS-1:0]  rd_col[0:DEPTH-1],  wr_col[0:DEPTH-1];
    reg [7:0]                rd_len[0:DEPTH-1],  wr_len[0:DEPTH-1];

    integer i;
    reg [AW:0] rd_used, wr_used;
    reg [AW-1:0] rd_free, wr_free, rd_head, wr_head;
    reg rd_free_found, wr_free_found, rd_found, wr_found;

    reg mode_rw;
    reg [3:0] mode_cnt;

    assign in_ready = (in_rw ? (wr_used < DEPTH) : (rd_used < DEPTH));
    assign allow_refresh = (rd_used == 0 && wr_used == 0 && !out_valid);

    always @(*) begin
        rd_free_found = 1'b0; wr_free_found = 1'b0;
        rd_found = 1'b0; wr_found = 1'b0;
        rd_free = {AW{1'b0}}; wr_free = {AW{1'b0}};
        rd_head = {AW{1'b0}}; wr_head = {AW{1'b0}};

        for (i = 0; i < DEPTH; i = i + 1) begin
            if (!rd_vld[i] && !rd_free_found) begin rd_free_found = 1'b1; rd_free = i[AW-1:0]; end
            if (!wr_vld[i] && !wr_free_found) begin wr_free_found = 1'b1; wr_free = i[AW-1:0]; end
            if ( rd_vld[i] && !rd_found) begin rd_found = 1'b1; rd_head = i[AW-1:0]; end
            if ( wr_vld[i] && !wr_found) begin wr_found = 1'b1; wr_head = i[AW-1:0]; end
        end
    end

    function has_future_hit;
        input this_rw;
        input [`DDR_BANK_BITS-1:0] bank;
        input [`DDR_ROW_BITS-1:0] row;
        integer k;
        begin
            has_future_hit = 1'b0;
            if (this_rw) begin
                for (k = 0; k < DEPTH; k = k + 1) begin
                    if (wr_vld[k] && wr_bank[k] == bank && wr_row[k] == row) has_future_hit = 1'b1;
                end
            end else begin
                for (k = 0; k < DEPTH; k = k + 1) begin
                    if (rd_vld[k] && rd_bank[k] == bank && rd_row[k] == row) has_future_hit = 1'b1;
                end
            end
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_used <= 0; wr_used <= 0;
            out_valid <= 1'b0;
            out_rw <= 1'b0;
            out_id <= 0;
            out_bank <= 0;
            out_row <= 0;
            out_col <= 0;
            out_len <= 0;
            out_auto_pre <= 1'b0;
            mode_rw <= 1'b0;
            mode_cnt <= 4'd0;
            for (i = 0; i < DEPTH; i = i + 1) begin
                rd_vld[i] <= 1'b0;
                wr_vld[i] <= 1'b0;
            end
        end else begin
            if (in_valid && in_ready) begin
                if (in_rw) begin
                    wr_vld[wr_free]  <= 1'b1;
                    wr_id[wr_free]   <= in_id;
                    wr_bank[wr_free] <= in_bank;
                    wr_row[wr_free]  <= in_row;
                    wr_col[wr_free]  <= in_col;
                    wr_len[wr_free]  <= in_len;
                    wr_used          <= wr_used + 1'b1;
                end else begin
                    rd_vld[rd_free]  <= 1'b1;
                    rd_id[rd_free]   <= in_id;
                    rd_bank[rd_free] <= in_bank;
                    rd_row[rd_free]  <= in_row;
                    rd_col[rd_free]  <= in_col;
                    rd_len[rd_free]  <= in_len;
                    rd_used          <= rd_used + 1'b1;
                end
            end

            if (!out_valid && !refresh_pending) begin
                if (urgent_read && rd_found) begin
                    out_valid <= 1'b1;
                    out_rw    <= 1'b0;
                    out_id    <= rd_id[rd_head];
                    out_bank  <= rd_bank[rd_head];
                    out_row   <= rd_row[rd_head];
                    out_col   <= rd_col[rd_head];
                    out_len   <= rd_len[rd_head];
                    out_auto_pre <= !has_future_hit(1'b0, rd_bank[rd_head], rd_row[rd_head]);
                end else if (mode_rw && wr_found && (mode_cnt < GROUP_MAX)) begin
                    out_valid <= 1'b1;
                    out_rw    <= 1'b1;
                    out_id    <= wr_id[wr_head];
                    out_bank  <= wr_bank[wr_head];
                    out_row   <= wr_row[wr_head];
                    out_col   <= wr_col[wr_head];
                    out_len   <= wr_len[wr_head];
                    out_auto_pre <= !has_future_hit(1'b1, wr_bank[wr_head], wr_row[wr_head]);
                end else if (!mode_rw && rd_found && (mode_cnt < GROUP_MAX)) begin
                    out_valid <= 1'b1;
                    out_rw    <= 1'b0;
                    out_id    <= rd_id[rd_head];
                    out_bank  <= rd_bank[rd_head];
                    out_row   <= rd_row[rd_head];
                    out_col   <= rd_col[rd_head];
                    out_len   <= rd_len[rd_head];
                    out_auto_pre <= !has_future_hit(1'b0, rd_bank[rd_head], rd_row[rd_head]);
                end else if (wr_found) begin
                    mode_rw <= 1'b1;
                    mode_cnt <= 0;
                    out_valid <= 1'b1;
                    out_rw    <= 1'b1;
                    out_id    <= wr_id[wr_head];
                    out_bank  <= wr_bank[wr_head];
                    out_row   <= wr_row[wr_head];
                    out_col   <= wr_col[wr_head];
                    out_len   <= wr_len[wr_head];
                    out_auto_pre <= !has_future_hit(1'b1, wr_bank[wr_head], wr_row[wr_head]);
                end else if (rd_found) begin
                    mode_rw <= 1'b0;
                    mode_cnt <= 0;
                    out_valid <= 1'b1;
                    out_rw    <= 1'b0;
                    out_id    <= rd_id[rd_head];
                    out_bank  <= rd_bank[rd_head];
                    out_row   <= rd_row[rd_head];
                    out_col   <= rd_col[rd_head];
                    out_len   <= rd_len[rd_head];
                    out_auto_pre <= !has_future_hit(1'b0, rd_bank[rd_head], rd_row[rd_head]);
                end
            end

            if (out_valid && out_ready) begin
                out_valid <= 1'b0;
                mode_cnt  <= mode_cnt + 1'b1;
                if (out_rw) begin
                    wr_vld[wr_head] <= 1'b0;
                    wr_used         <= wr_used - 1'b1;
                    mode_rw         <= 1'b1;
                end else begin
                    rd_vld[rd_head] <= 1'b0;
                    rd_used         <= rd_used - 1'b1;
                    mode_rw         <= 1'b0;
                end
            end
        end
    end
endmodule
