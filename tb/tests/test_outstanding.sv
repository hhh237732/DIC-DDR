`ifndef TEST_OUTSTANDING_SV
`define TEST_OUTSTANDING_SV

// Test: multiple outstanding read transactions (up to MAX_OUTSTANDING=4)
task automatic run_test_outstanding();
    logic [31:0] rd[];

    $display("[TEST] test_outstanding start");
    sb.init();

    // Populate memory with known pattern first
    for (int i = 0; i < 4; i++) begin
        bfm.axi_write(i[3:0], 32'h0010_0000 + i*64, 4, 32'hAA00_0000 + i*32'h100);
    end

    // Issue multiple reads and check responses
    for (int i = 0; i < 4; i++) begin
        bfm.axi_read(i[3:0], 32'h0010_0000 + i*64, 4, rd);
        for (int j = 0; j < 4; j++) begin
            sb.check_equal(rd[j], 32'hAA00_0000 + i*32'h100 + j,
                           $sformatf("outstanding rd[%0d] beat %0d", i, j));
        end
    end

    sb.record_read(16);
    sb.report_and_finish();
endtask

`endif
