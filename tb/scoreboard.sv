`timescale 1ns/1ps

module scoreboard;
    int error_count;

    task automatic init();
        error_count = 0;
    endtask

    task automatic check_equal(input logic [31:0] a, input logic [31:0] b, input string msg);
        if (a !== b) begin
            error_count++;
            $display("[SCB][ERR] %s exp=%h got=%h", msg, b, a);
        end
    endtask

    task automatic report_and_finish();
        if (error_count == 0) begin
            $display("PASS");
        end else begin
            $display("FAIL, error_count=%0d", error_count);
        end
    endtask
endmodule
