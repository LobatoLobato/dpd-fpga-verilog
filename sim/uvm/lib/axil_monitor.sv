`ifndef AXIL_MONITOR_SV
`define AXIL_MONITOR_SV
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "axil_item.sv"

class axil_monitor #(int DATA_W = 32, int ADDR_W = 4) extends uvm_monitor;
    `uvm_component_param_utils(axil_monitor #(DATA_W, ADDR_W))

    virtual taxi_axil_if #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) vif;

    uvm_analysis_port #(axil_item #(DATA_W, ADDR_W)) ap;

    int write_count;
    int read_count;

    function new(string name = "axil_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        write_count = 0;
        read_count = 0;
        if (!uvm_config_db#(virtual taxi_axil_if #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)))::get(this, "", "vif", vif))
            `uvm_fatal(get_full_name(), "Virtual interface not set via uvm_config_db");
    endfunction : build_phase

    task run_phase(uvm_phase phase);
        axil_item #(DATA_W, ADDR_W) item;
        logic [ADDR_W-1:0] raddr;

        forever begin
            @(posedge vif.tb_clk);

            if (vif.awvalid && vif.awready && vif.wvalid && vif.wready) begin
                item = axil_item #(DATA_W, ADDR_W)::type_id::create("item");
                item.op   = axil_item #(DATA_W, ADDR_W)::AXIL_WRITE;
                item.addr = vif.awaddr;
                item.data = vif.wdata;
                item.strb = vif.wstrb;
                write_count++;
                ap.write(item);
            end

            if (vif.arvalid && vif.arready)
                raddr = vif.araddr;

            if (vif.rvalid && vif.rready) begin
                item = axil_item #(DATA_W, ADDR_W)::type_id::create("item");
                item.op   = axil_item #(DATA_W, ADDR_W)::AXIL_READ;
                item.addr = raddr;
                item.data = vif.rdata;
                item.strb = '1;
                read_count++;
                ap.write(item);
            end
        end
    endtask : run_phase

endclass : axil_monitor

`endif // AXIL_MONITOR_SV
