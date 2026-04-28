`timescale 1ns/1ps
`include "ddr3_params.vh"

// ============================================================
// AXI 请求拆分模块 v2
// 功能：
// 1) 将单条 AXI burst 拆分为不跨 row 的 DDR 访问子命令
// 2) 同时检查 4KB 地址边界，防止单次 burst 跨越 4KB 边界
// 3) 输出统一命令描述符：{rw,id,bank,row,col,len}
// ============================================================
module cmd_split #(
    parameter ADDR_WIDTH = `AXI_ADDR_WIDTH,
    parameter ID_WIDTH   = `AXI_ID_WIDTH
) (
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire                     in_valid,
    output wire                     in_ready,
    input  wire                     in_rw,
    input  wire [ID_WIDTH-1:0]      in_id,
    input  wire [ADDR_WIDTH-1:0]    in_addr,
    input  wire [7:0]               in_len,
    input  wire [2:0]               in_size,
    input  wire [1:0]               in_burst,

    output reg                      out_valid,
    input  wire                     out_ready,
    output reg                      out_rw,
    output reg  [ID_WIDTH-1:0]      out_id,
    output reg  [`DDR_BANK_BITS-1:0] out_bank,
    output reg  [`DDR_ROW_BITS-1:0]  out_row,
    output reg  [`DDR_COL_BITS-1:0]  out_col,
    output reg  [7:0]               out_len,

    output reg                      busy
);

    reg active;
    reg [ID_WIDTH-1:0]      cur_id;
    reg                     cur_rw;
    reg [ADDR_WIDTH-1:0]    cur_addr;
    reg [8:0]               beats_left;
    reg [2:0]               beat_bytes_lg2;

    wire [`DDR_BANK_BITS-1:0] map_bank;
    wire [`DDR_ROW_BITS-1:0]  map_row;
    wire [`DDR_COL_BITS-1:0]  map_col;
    wire [1:0] map_bofs;

    addr_map u_addr_map (
        .axi_addr(cur_addr),
        .bank(map_bank),
        .row(map_row),
        .col(map_col),
        .byte_ofs(map_bofs)
    );

    // Row boundary: remaining columns in current row
    wire [10:0] col_room = 11'd1024 - {1'b0, map_col};
    wire [8:0]  chunk_by_row = (beats_left > col_room[8:0]) ? col_room[8:0] : beats_left;

    // 4KB boundary: bytes remaining until next 4KB boundary
    wire [12:0] boundary_4k = 13'h1000 - {1'b0, cur_addr[11:0]};
    // Convert byte distance to beats (divide by 4 for size=2 / 4-byte beats)
    wire [8:0]  beats_to_4k_raw = boundary_4k[10:2];
    // If exactly at 4KB boundary, beats_to_4k_raw wraps to 0; treat as 256
    wire [8:0]  beats_to_4k = (beats_to_4k_raw == 9'd0) ? 9'd256 : beats_to_4k_raw;

    // Final chunk: min of row constraint, 4KB constraint, beats remaining
    wire [8:0] chunk_row_4k  = (chunk_by_row < beats_to_4k) ? chunk_by_row : beats_to_4k;
    wire [8:0] chunk_beats   = (chunk_row_4k > beats_left) ? beats_left : chunk_row_4k;
    wire [8:0] safe_chunk_beats = (chunk_beats == 0) ? 9'd1 : chunk_beats;

    assign in_ready = (!active);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active        <= 1'b0;
            busy          <= 1'b0;
            out_valid     <= 1'b0;
            out_rw        <= 1'b0;
            out_id        <= {ID_WIDTH{1'b0}};
            out_bank      <= {`DDR_BANK_BITS{1'b0}};
            out_row       <= {`DDR_ROW_BITS{1'b0}};
            out_col       <= {`DDR_COL_BITS{1'b0}};
            out_len       <= 8'd0;
            cur_id        <= {ID_WIDTH{1'b0}};
            cur_rw        <= 1'b0;
            cur_addr      <= {ADDR_WIDTH{1'b0}};
            beats_left    <= 9'd0;
            beat_bytes_lg2<= 3'd2;
        end else begin
            if (in_valid && in_ready) begin
                active         <= 1'b1;
                busy           <= 1'b1;
                cur_id         <= in_id;
                cur_rw         <= in_rw;
                cur_addr       <= in_addr;
                beats_left     <= {1'b0, in_len} + 9'd1;
                beat_bytes_lg2 <= in_size;
                out_valid      <= 1'b0;
            end

            if (active && !out_valid) begin
                out_rw    <= cur_rw;
                out_id    <= cur_id;
                out_bank  <= map_bank;
                out_row   <= map_row;
                out_col   <= map_col;
                out_len   <= safe_chunk_beats[7:0] - 8'd1;
                out_valid <= 1'b1;
            end

            if (out_valid && out_ready) begin
                out_valid <= 1'b0;
                if (beats_left <= safe_chunk_beats) begin
                    active     <= 1'b0;
                    busy       <= 1'b0;
                    beats_left <= 9'd0;
                end else begin
                    beats_left <= beats_left - safe_chunk_beats;
                    cur_addr   <= cur_addr + (safe_chunk_beats << beat_bytes_lg2);
                end
            end
        end
    end
endmodule
