`timescale 1ns/1ps

module axi_master_bfm #(
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 32,
    parameter AXI_ID_WIDTH   = 4
) (
    input  logic                        aclk,
    input  logic                        aresetn,

    output logic [AXI_ID_WIDTH-1:0]     m_axi_awid,
    output logic [AXI_ADDR_WIDTH-1:0]   m_axi_awaddr,
    output logic [7:0]                  m_axi_awlen,
    output logic [2:0]                  m_axi_awsize,
    output logic [1:0]                  m_axi_awburst,
    output logic                        m_axi_awvalid,
    input  logic                        m_axi_awready,

    output logic [AXI_DATA_WIDTH-1:0]   m_axi_wdata,
    output logic [AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
    output logic                        m_axi_wlast,
    output logic                        m_axi_wvalid,
    input  logic                        m_axi_wready,

    input  logic [AXI_ID_WIDTH-1:0]     m_axi_bid,
    input  logic [1:0]                  m_axi_bresp,
    input  logic                        m_axi_bvalid,
    output logic                        m_axi_bready,

    output logic [AXI_ID_WIDTH-1:0]     m_axi_arid,
    output logic [AXI_ADDR_WIDTH-1:0]   m_axi_araddr,
    output logic [7:0]                  m_axi_arlen,
    output logic [2:0]                  m_axi_arsize,
    output logic [1:0]                  m_axi_arburst,
    output logic                        m_axi_arvalid,
    input  logic                        m_axi_arready,

    input  logic [AXI_ID_WIDTH-1:0]     m_axi_rid,
    input  logic [AXI_DATA_WIDTH-1:0]   m_axi_rdata,
    input  logic [1:0]                  m_axi_rresp,
    input  logic                        m_axi_rlast,
    input  logic                        m_axi_rvalid,
    output logic                        m_axi_rready
);

    task automatic reset_signals();
        m_axi_awid    = '0;
        m_axi_awaddr  = '0;
        m_axi_awlen   = '0;
        m_axi_awsize  = 3'd2;
        m_axi_awburst = 2'b01;
        m_axi_awvalid = 1'b0;
        m_axi_wdata   = '0;
        m_axi_wstrb   = '1;
        m_axi_wlast   = 1'b0;
        m_axi_wvalid  = 1'b0;
        m_axi_bready  = 1'b1;
        m_axi_arid    = '0;
        m_axi_araddr  = '0;
        m_axi_arlen   = '0;
        m_axi_arsize  = 3'd2;
        m_axi_arburst = 2'b01;
        m_axi_arvalid = 1'b0;
        m_axi_rready  = 1'b1;
    endtask

    task automatic axi_write(
        input [AXI_ID_WIDTH-1:0] id,
        input [AXI_ADDR_WIDTH-1:0] addr,
        input int beats,
        input logic [AXI_DATA_WIDTH-1:0] base_data
    );
        int i;
        int to;
        bit done;
        begin
            m_axi_awid    = id;
            m_axi_awaddr  = addr;
            m_axi_awlen   = beats-1;
            m_axi_awsize  = 3'd2;
            m_axi_awburst = 2'b01;
            m_axi_awvalid = 1'b1;
            to = 0;
            done = 0;
            while (to < 2000 && !done) begin
                @(posedge aclk);
                if (m_axi_awready === 1'b1) begin
                    m_axi_awvalid = 1'b0;
                    done = 1;
                end
                to++;
            end
            if (!done) $fatal(1, "AXI AW 超时");

            for (i = 0; i < beats; i++) begin
                m_axi_wdata  = base_data + i;
                m_axi_wstrb  = '1;
                m_axi_wlast  = (i == beats-1);
                m_axi_wvalid = 1'b1;
                to = 0;
                done = 0;
                while (to < 2000 && !done) begin
                    @(posedge aclk);
                    if (m_axi_wready === 1'b1) begin
                        m_axi_wvalid = 1'b0;
                        done = 1;
                    end
                    to++;
                end
                if (!done) $fatal(1, "AXI W 超时 beat=%0d", i);
                @(posedge aclk);
            end

            to = 0;
            while (m_axi_bvalid !== 1'b1 && to < 10000) begin @(posedge aclk); to++; end
            if (m_axi_bvalid !== 1'b1) $fatal(1, "AXI B 超时");
            @(posedge aclk);
        end
    endtask

    task automatic axi_read(
        input [AXI_ID_WIDTH-1:0] id,
        input [AXI_ADDR_WIDTH-1:0] addr,
        input int beats,
        output logic [AXI_DATA_WIDTH-1:0] data_q[]
    );
        int i;
        int to;
        bit done;
        begin
            data_q = new[beats];
            m_axi_arid    = id;
            m_axi_araddr  = addr;
            m_axi_arlen   = beats-1;
            m_axi_arsize  = 3'd2;
            m_axi_arburst = 2'b01;
            m_axi_arvalid = 1'b1;
            to = 0;
            done = 0;
            while (to < 2000 && !done) begin
                @(posedge aclk);
                if (m_axi_arready === 1'b1) begin
                    m_axi_arvalid = 1'b0;
                    done = 1;
                end
                to++;
            end
            if (!done) $fatal(1, "AXI AR 超时");

            for (i = 0; i < beats; i++) begin
                to = 0;
                while (m_axi_rvalid !== 1'b1 && to < 10000) begin @(posedge aclk); to++; end
                if (m_axi_rvalid !== 1'b1) $fatal(1, "AXI R 超时 beat=%0d", i);
                data_q[i] = m_axi_rdata;
                if (i == beats-1 && !m_axi_rlast) $error("R last 未正确拉高");
                @(posedge aclk);
            end
        end
    endtask
endmodule
