`ifndef TEST_BASIC_RW_SV
`define TEST_BASIC_RW_SV

task automatic run_test_basic_rw();
    logic [31:0] rd[];
    $display("[TEST] test_basic_rw start");
    sb.init();
    bfm.axi_write(4'h1, 32'h0000_0040, 4, 32'h1234_0000);
    bfm.axi_read (4'h1, 32'h0000_0040, 4, rd);
    for (int i = 0; i < 4; i++) begin
        sb.check_equal(rd[i], 32'h1234_0000 + i, $sformatf("basic_rw beat %0d", i));
    end
    sb.report_and_finish();
endtask

`endif
