`ifndef TEST_BURST_SV
`define TEST_BURST_SV

task automatic run_test_burst();
    logic [31:0] rd[];
    int beats_list [0:3];
    $display("[TEST] test_burst start");
    sb.init();
    beats_list[0] = 1;
    beats_list[1] = 2;
    beats_list[2] = 8;
    beats_list[3] = 16;
    for (int k = 0; k < 4; k++) begin
        int beats = beats_list[k];
        bfm.axi_write(4'h2, 32'h0000_1000 + k*64, beats, 32'hA500_0000 + (k<<8));
        bfm.axi_read (4'h2, 32'h0000_1000 + k*64, beats, rd);
        for (int i = 0; i < beats; i++) begin
            sb.check_equal(rd[i], 32'hA500_0000 + (k<<8) + i, $sformatf("burst%0d beat%0d", beats, i));
        end
    end
    sb.report_and_finish();
endtask

`endif
