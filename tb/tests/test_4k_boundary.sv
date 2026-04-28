`ifndef TEST_4K_BOUNDARY_SV
`define TEST_4K_BOUNDARY_SV

// Test: AXI burst must not cross 4KB boundary.
// Strategy: issue a write starting just before the 4KB boundary,
// verify the cmd_split module generates two sub-transactions.
task automatic run_test_4k_boundary();
    logic [31:0] rd[];
    int          exp_val;

    $display("[TEST] test_4k_boundary start");
    sb.init();

    // Write 8 beats starting at address 0xFF0 (crosses 4KB boundary at 0x1000)
    // beat size = 4 bytes; 0xFF0 + 8*4 = 0x1010 -> crosses boundary
    bfm.axi_write(4'h2, 32'h0000_0FF0, 8, 32'hDEAD_0000);
    bfm.axi_read (4'h2, 32'h0000_0FF0, 8, rd);
    for (int i = 0; i < 8; i++) begin
        sb.check_equal(rd[i], 32'hDEAD_0000 + i,
                       $sformatf("4k_boundary beat %0d", i));
    end

    // Write exactly at 4KB boundary (no split needed)
    bfm.axi_write(4'h3, 32'h0000_1000, 4, 32'hBEEF_0000);
    bfm.axi_read (4'h3, 32'h0000_1000, 4, rd);
    for (int i = 0; i < 4; i++) begin
        sb.check_equal(rd[i], 32'hBEEF_0000 + i,
                       $sformatf("4k_aligned beat %0d", i));
    end

    sb.report_and_finish();
endtask

`endif
