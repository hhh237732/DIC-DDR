`timescale 1ns/1ps

module scoreboard;
    int error_count;
    int wr_txn_count;
    int rd_txn_count;
    longint total_wr_beats;
    longint total_rd_beats;
    longint start_cycle;
    longint end_cycle;

    // Performance stats
    task automatic init();
        error_count    = 0;
        wr_txn_count   = 0;
        rd_txn_count   = 0;
        total_wr_beats = 0;
        total_rd_beats = 0;
        start_cycle    = $time;
    endtask

    task automatic record_write(input int beats);
        wr_txn_count++;
        total_wr_beats += beats;
    endtask

    task automatic record_read(input int beats);
        rd_txn_count++;
        total_rd_beats += beats;
    endtask

    task automatic check_equal(input logic [31:0] a, input logic [31:0] b, input string msg);
        if (a !== b) begin
            error_count++;
            $display("[SCB][ERR] %s exp=%h got=%h", msg, b, a);
        end
    endtask

    task automatic report_perf();
        longint elapsed;
        end_cycle = $time;
        elapsed   = end_cycle - start_cycle;
        $display("[SCB][PERF] WR txns=%0d beats=%0d  RD txns=%0d beats=%0d  elapsed=%0d ns",
                 wr_txn_count, total_wr_beats,
                 rd_txn_count, total_rd_beats,
                 elapsed);
        if (elapsed > 0) begin
            $display("[SCB][PERF] Effective WR BW = %0d MB/s  RD BW = %0d MB/s",
                     (total_wr_beats * 4 * 1000) / elapsed,
                     (total_rd_beats * 4 * 1000) / elapsed);
        end
    endtask

    task automatic report_and_finish();
        report_perf();
        if (error_count == 0) begin
            $display("PASS");
        end else begin
            $display("FAIL, error_count=%0d", error_count);
        end
    endtask
endmodule
