`ifndef TEST_STARVATION_SV
`define TEST_STARVATION_SV

// Test: starvation prevention in cmd_reorder_l1.
// Strategy: flood same-bank page-hit reads so a different-bank command
// would be starved. Verify all commands eventually complete.
task automatic run_test_starvation();
    logic [31:0] rd[];

    $display("[TEST] test_starvation start");
    sb.init();

    // Pre-populate: bank0 row0 and bank1 row0
    bfm.axi_write(4'h0, 32'h0000_0000, 8, 32'hC0DE_0000);  // bank0, row0
    bfm.axi_write(4'h1, 32'h0001_0000, 8, 32'hFACE_0000);  // bank1 (different row)

    // Repeatedly read bank0 (page-hit) to starve bank1 request
    for (int i = 0; i < 8; i++) begin
        bfm.axi_read(4'h0, 32'h0000_0000, 4, rd);
    end

    // Now read bank1 - starvation mechanism must have promoted this
    bfm.axi_read(4'h1, 32'h0001_0000, 8, rd);
    for (int i = 0; i < 8; i++) begin
        sb.check_equal(rd[i], 32'hFACE_0000 + i,
                       $sformatf("starvation bank1 beat %0d", i));
    end

    sb.report_and_finish();
endtask

`endif
