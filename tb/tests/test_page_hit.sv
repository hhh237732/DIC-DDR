`ifndef TEST_PAGE_HIT_SV
`define TEST_PAGE_HIT_SV

task automatic run_test_page_hit();
    logic [31:0] rd[];
    $display("[TEST] test_page_hit start");
    sb.init();
    // 同一 row 不同 col，观察 page hit 路径
    bfm.axi_write(4'h3, 32'h0000_2000, 8, 32'h3300_0000);
    bfm.axi_read (4'h3, 32'h0000_2000, 8, rd);
    for (int i = 0; i < 8; i++) sb.check_equal(rd[i], 32'h3300_0000 + i, $sformatf("page_hit beat%0d", i));
    sb.report_and_finish();
endtask

`endif
