`ifndef TEST_REFRESH_SV
`define TEST_REFRESH_SV

task automatic run_test_refresh();
    logic [31:0] rd[];
    $display("[TEST] test_refresh start");
    sb.init();

    bfm.axi_write(4'h6, 32'h0000_4000, 4, 32'h6600_0000);
    repeat (7000) @(posedge aclk); // 跨过至少一个 tREFI 窗口
    bfm.axi_read (4'h6, 32'h0000_4000, 4, rd);

    for (int i = 0; i < 4; i++) begin
        sb.check_equal(rd[i], 32'h6600_0000 + i, $sformatf("refresh beat%0d", i));
    end
    sb.report_and_finish();
endtask

`endif
