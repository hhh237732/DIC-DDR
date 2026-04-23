`timescale 1ns/1ps
module tb_top;
    reg [8*64-1:0] testname;
    integer init_to;
    logic aclk;
    logic aresetn;

    logic [3:0]  awid;
    logic [31:0] awaddr;
    logic [7:0]  awlen;
    logic [2:0]  awsize;
    logic [1:0]  awburst;
    logic        awvalid;
    logic        awready;
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wlast;
    logic        wvalid;
    logic        wready;
    logic [3:0]  bid;
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;
    logic [3:0]  arid;
    logic [31:0] araddr;
    logic [7:0]  arlen;
    logic [2:0]  arsize;
    logic [1:0]  arburst;
    logic        arvalid;
    logic        arready;
    logic [3:0]  rid;
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rlast;
    logic        rvalid;
    logic        rready;

    logic dfi_cke, dfi_cs_n, dfi_ras_n, dfi_cas_n, dfi_we_n;
    logic [2:0] dfi_bank;
    logic [14:0] dfi_addr;
    logic [31:0] dfi_wrdata;
    logic [3:0] dfi_wrdata_mask;
    logic dfi_wrdata_en;
    logic [31:0] dfi_rddata;
    logic dfi_rddata_valid;

    axi_master_bfm bfm (
        .aclk(aclk), .aresetn(aresetn),
        .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize), .m_axi_awburst(awburst),
        .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast), .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bid(bid), .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize), .m_axi_arburst(arburst),
        .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rid(rid), .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rlast(rlast), .m_axi_rvalid(rvalid), .m_axi_rready(rready)
    );

    scoreboard sb();

    `include "test_basic_rw.sv"
    `include "test_burst.sv"
    `include "test_page_hit.sv"
    `include "test_reorder.sv"
    `include "test_refresh.sv"

    ddr3_ctrl_top dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awid(awid), .s_axi_awaddr(awaddr), .s_axi_awlen(awlen), .s_axi_awsize(awsize), .s_axi_awburst(awburst),
        .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wlast(wlast), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bid(bid), .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_arid(arid), .s_axi_araddr(araddr), .s_axi_arlen(arlen), .s_axi_arsize(arsize), .s_axi_arburst(arburst),
        .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rid(rid), .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rlast(rlast), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .dfi_cke(dfi_cke), .dfi_cs_n(dfi_cs_n), .dfi_ras_n(dfi_ras_n), .dfi_cas_n(dfi_cas_n), .dfi_we_n(dfi_we_n),
        .dfi_bank(dfi_bank), .dfi_addr(dfi_addr), .dfi_wrdata(dfi_wrdata), .dfi_wrdata_mask(dfi_wrdata_mask), .dfi_wrdata_en(dfi_wrdata_en),
        .dfi_rddata(dfi_rddata), .dfi_rddata_valid(dfi_rddata_valid)
    );

    ddr3_model mem (
        .clk(aclk), .rst_n(aresetn),
        .cke(dfi_cke), .cs_n(dfi_cs_n), .ras_n(dfi_ras_n), .cas_n(dfi_cas_n), .we_n(dfi_we_n),
        .bank(dfi_bank), .addr(dfi_addr),
        .wrdata(dfi_wrdata), .wrdata_mask(dfi_wrdata_mask), .wrdata_en(dfi_wrdata_en),
        .rddata(dfi_rddata), .rddata_valid(dfi_rddata_valid)
    );

    initial begin
        aclk = 0;
        forever #5 aclk = ~aclk;
    end

    initial begin
        bfm.reset_signals();
        aresetn = 1'b0;
        repeat (20) @(posedge aclk);
        aresetn = 1'b1;

        init_to = 0;
        while (!dut.u_init.init_done && init_to < 20000) begin
            @(posedge aclk);
            init_to++;
        end
        if (!dut.u_init.init_done) begin
            $display("FAIL");
            $fatal(1, "初始化未完成");
        end

        if (!$value$plusargs("TESTNAME=%s", testname)) begin
            testname = "test_basic_rw";
        end
        $display("[TB] running %s", testname);

        if (testname == "test_basic_rw") run_test_basic_rw();
        else if (testname == "test_burst") run_test_burst();
        else if (testname == "test_page_hit") run_test_page_hit();
        else if (testname == "test_reorder") run_test_reorder();
        else if (testname == "test_refresh") run_test_refresh();
        else begin
            $display("[TB] unknown TESTNAME=%s", testname);
            $display("FAIL");
        end

        repeat (20) @(posedge aclk);
        $finish;
    end
endmodule
