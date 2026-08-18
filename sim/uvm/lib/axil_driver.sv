`ifndef AXIL_DRIVER_SV
`define AXIL_DRIVER_SV
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "axil_item.sv"

class axil_driver #(int DATA_W = 32, int ADDR_W = 4) extends uvm_driver #(axil_item #(DATA_W, ADDR_W));
    `uvm_component_param_utils(axil_driver #(DATA_W, ADDR_W))

    virtual taxi_axil_if #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) vif;

    function new(string name = "axil_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual taxi_axil_if #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)))::get(this, "", "vif", vif))
            `uvm_fatal(get_full_name(), "Virtual interface not set via uvm_config_db");
    endfunction : build_phase

    // Single-cycle-capable AW/W handshake; honors item.strb for partial writes.
    // AW/W are held until the write response is observed and then deasserted in
    // the same cycle, so a slave that accepted the write on the AW/W handshake
    // cannot re-accept a still-asserted AW/W once it clears bvalid.
    task automatic do_write(input logic [ADDR_W-1:0] addr, input logic [DATA_W-1:0] data, input logic [DATA_W/8-1:0] strb);
        @(posedge vif.tb_clk);
        vif.awaddr  <= addr;
        vif.awvalid <= 1'b1;
        vif.wdata   <= data;
        vif.wstrb   <= strb;
        vif.wvalid  <= 1'b1;
        vif.bready  <= 1'b1;

        fork
            while (!vif.awready) @(posedge vif.tb_clk);
            while (!vif.wready)  @(posedge vif.tb_clk);
        join
        while (!vif.bvalid) @(posedge vif.tb_clk);

        vif.awaddr  <= '0;
        vif.awvalid <= 1'b0;
        vif.wdata   <= '0;
        vif.wstrb   <= '0;
        vif.wvalid  <= 1'b0;
        vif.bready  <= 1'b0;
    endtask : do_write

    // Read with AR/R handshake; returns the sampled read data via `data`.
    // AR is held until the read data is captured and then deasserted in the
    // same cycle, matching the write-side behavior above.
    task automatic do_read(input logic [ADDR_W-1:0] addr, output logic [DATA_W-1:0] data);
        @(posedge vif.tb_clk);
        vif.araddr  <= addr;
        vif.arvalid <= 1'b1;
        vif.rready  <= 1'b1;

        while (!vif.arready) @(posedge vif.tb_clk);
        while (!vif.rvalid)  @(posedge vif.tb_clk);
        data = vif.rdata;

        vif.araddr  <= '0;
        vif.arvalid <= 1'b0;
        vif.rready  <= 1'b0;
    endtask : do_read

    task run_phase(uvm_phase phase);
        axil_item #(DATA_W, ADDR_W) item;

        forever begin
            seq_item_port.get_next_item(item);
            if (item.op == axil_item #(DATA_W, ADDR_W)::AXIL_WRITE)
                do_write(item.addr, item.data, item.strb);
            else begin
                do_read(item.addr, item.data);
                rsp_port.write(item);
            end
            seq_item_port.item_done();
        end
    endtask : run_phase

endclass : axil_driver

`endif // AXIL_DRIVER_SV
