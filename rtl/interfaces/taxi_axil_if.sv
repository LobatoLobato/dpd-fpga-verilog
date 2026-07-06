// SPDX-License-Identifier: MIT
/*

Copyright (c) 2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

interface taxi_axil_if #(
    // Width of data bus in bits
    parameter DATA_W = 32,
    // Width of address bus in bits
    parameter ADDR_W = 32,
    // Width of wstrb (width of data bus in words)
    parameter STRB_W = (DATA_W/8),
    // Use awuser signal
    parameter logic AWUSER_EN = 1'b0,
    // Width of awuser signal
    parameter AWUSER_W = 1,
    // Use wuser signal
    parameter logic WUSER_EN = 1'b0,
    // Width of wuser signal
    parameter WUSER_W = 1,
    // Use buser signal
    parameter logic BUSER_EN = 1'b0,
    // Width of buser signal
    parameter BUSER_W = 1,
    // Use aruser signal
    parameter logic ARUSER_EN = 1'b0,
    // Width of aruser signal
    parameter ARUSER_W = 1,
    // Use ruser signal
    parameter logic RUSER_EN = 1'b0,
    // Width of ruser signal
    parameter RUSER_W = 1
)
(input logic tb_clk);
    // AW
    logic [ADDR_W-1:0]    awaddr;
    logic [2:0]           awprot;
    logic [AWUSER_W-1:0]  awuser;
    logic                 awvalid;
    logic                 awready;
    // W
    logic [DATA_W-1:0]    wdata;
    logic [STRB_W-1:0]    wstrb;
    logic [WUSER_W-1:0]   wuser;
    logic                 wvalid;
    logic                 wready;
    // B
    logic [1:0]           bresp;
    logic [BUSER_W-1:0]   buser;
    logic                 bvalid;
    logic                 bready;
    // AR
    logic [ADDR_W-1:0]    araddr;
    logic [2:0]           arprot;
    logic [ARUSER_W-1:0]  aruser;
    logic                 arvalid;
    logic                 arready;
    // R
    logic [DATA_W-1:0]    rdata;
    logic [1:0]           rresp;
    logic [RUSER_W-1:0]   ruser;
    logic                 rvalid;
    logic                 rready;

    modport wr_mst (
        // AW
        output awaddr,
        output awprot,
        output awuser,
        output awvalid,
        input  awready,
        // W
        output wdata,
        output wstrb,
        output wuser,
        output wvalid,
        input  wready,
        // B
        input  bresp,
        input  buser,
        input  bvalid,
        output bready
    );

    modport rd_mst (
        // AR
        output araddr,
        output arprot,
        output aruser,
        output arvalid,
        input  arready,
        // R
        input  rdata,
        input  rresp,
        input  ruser,
        input  rvalid,
        output rready
    );

    modport wr_slv (
        // AW
        input  awaddr,
        input  awprot,
        input  awuser,
        input  awvalid,
        output awready,
        // W
        input  wdata,
        input  wstrb,
        input  wuser,
        input  wvalid,
        output wready,
        // B
        output bresp,
        output buser,
        output bvalid,
        input  bready
    );

    modport rd_slv (
        // AR
        input  araddr,
        input  arprot,
        input  aruser,
        input  arvalid,
        output arready,
        // R
        output rdata,
        output rresp,
        output ruser,
        output rvalid,
        input  rready
    );

    modport wr_mon (
        // AW
        input  awaddr,
        input  awprot,
        input  awuser,
        input  awvalid,
        input  awready,
        // W
        input  wdata,
        input  wstrb,
        input  wuser,
        input  wvalid,
        input  wready,
        // B
        input  bresp,
        input  buser,
        input  bvalid,
        input  bready
    );

    modport rd_mon (
        // AR
        input  araddr,
        input  arprot,
        input  aruser,
        input  arvalid,
        input  arready,
        // R
        input  rdata,
        input  rresp,
        input  ruser,
        input  rvalid,
        input  rready
    );

    // Based on ref: https://www.realdigital.org/doc/a9fee931f7a172423e1ba73f66ca4081 figure 3
    task automatic read(input logic [ADDR_W-1:0] addr, output logic [DATA_W-1:0] data);
        @(posedge tb_clk);       // Starts the read transaction (ref: starts on cycle 7)
        araddr  <= addr; //   sends the read address
        arvalid <= 1;    //   indicates the address is valid
        rready  <= 1;    //   ready to receive data
        
        while (~arready) @(posedge tb_clk); // Waits for ar handshake (ref: completes on cycle 11)
        
        while (~rvalid) @(posedge tb_clk); // Waits for rvalid (ref: happens on cycle 12)
        data = rdata;  // samples the data
        rready <= 0;   // stops receiving data
        arvalid <= 0;  // deasserts arvalid
        araddr  <= 0;  // clears the address
        assert(~arready) else $fatal(1, "Slave did not deassert arready after the handshake");

        fork begin
            @(posedge tb_clk); // Completes the read transaction (ref: settles on cycle 13)
            assert(~rvalid) else $fatal(1, "rvalid still high after transaction is completed");
        end join_none        
    endtask

    // Based on ref: https://www.realdigital.org/doc/a9fee931f7a172423e1ba73f66ca4081 figure 4
    task automatic write(input logic [ADDR_W-1:0] addr, input logic [DATA_W-1:0] data);
        @(posedge tb_clk);       // Starts the write transaction (ref: starts on cycle 7)
        wdata   <= data; //   writes the data
        awaddr  <= addr; //   sets the address
        wstrb   <= '1;   //   sets the write strobe
        awvalid <= 1;    //   asserts awvalid
        wvalid  <= 1;    //   asserts wvalid
        bready  <= 1;    //   asserts bready
        
        // Waits for write address and write data channels to acknowledge handshake (ref: completes on cycle 11)
        fork
            begin while (~awready) @(posedge tb_clk); end // write addr handshake
            begin while (~wready)  @(posedge tb_clk); end // write data handshake
        join
        
        while (~bvalid) @(posedge tb_clk); // Waits for bvalid (ref: happens on cycle 12)
        awvalid <= 0; // deasserts awvalid
        wvalid  <= 0; // deasserts wvalid
        awaddr  <= 0; // deasserts awaddr
        wdata   <= 0; // clears write data
        wstrb   <= 0; // clears write address
        bready  <= 0; // deasserts bready
        assert(bresp == 2'b00) else $fatal(1, "bresp not OK(b00) after the handshakes, got %b", bresp);
        assert(~awready)       else $fatal(1, "Slave did not deassert awready after the handshakes");
        assert(~wready)        else $fatal(1, "Slave did not deassert wready after the handshakes");

        fork begin
            @(posedge tb_clk);    // Completes write transaction (ref: settles on cycle 13)
            assert(~bvalid) else $fatal(1, "bvalid still high after transaction is completed");
        end join_none
    endtask
endinterface