`ifndef TEST_REORDER_SV
`define TEST_REORDER_SV

task automatic run_test_reorder();
    logic [31:0] rd0[];
    logic [31:0] rd1[];
    $display("[TEST] test_reorder start");
    sb.init();

    fork
        bfm.axi_write(4'h4, 32'h0000_3000, 4, 32'h4400_0000);
        bfm.axi_write(4'h5, 32'h0000_3040, 4, 32'h5500_0000);
    join

    fork
        bfm.axi_read(4'h4, 32'h0000_3000, 4, rd0);
        bfm.axi_read(4'h5, 32'h0000_3040, 4, rd1);
    join

    for (int i = 0; i < 4; i++) begin
        sb.check_equal(rd0[i], 32'h4400_0000 + i, $sformatf("reorder id4 beat%0d", i));
        sb.check_equal(rd1[i], 32'h5500_0000 + i, $sformatf("reorder id5 beat%0d", i));
    end
    sb.report_and_finish();
endtask

`endif
