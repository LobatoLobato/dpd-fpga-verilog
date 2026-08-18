`ifndef AXIL_AGENT_SV
`define AXIL_AGENT_SV
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "axil_sequencer.sv"
`include "axil_driver.sv"
`include "axil_monitor.sv"

class axil_agent #(int DATA_W = 32, int ADDR_W = 4) extends uvm_agent;
    `uvm_component_param_utils(axil_agent #(DATA_W, ADDR_W))

    axil_sequencer #(DATA_W, ADDR_W) sqr;
    axil_driver    #(DATA_W, ADDR_W) drv;
    axil_monitor   #(DATA_W, ADDR_W) mon;

    function new(string name = "axil_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(uvm_active_passive_enum)::get(this, "", "is_active", is_active)) begin
            is_active = UVM_ACTIVE;
        end

        if (is_active == UVM_ACTIVE) begin
            sqr = axil_sequencer #(DATA_W, ADDR_W)::type_id::create("sqr", this);
            drv = axil_driver    #(DATA_W, ADDR_W)::type_id::create("drv", this);
        end

        mon = axil_monitor #(DATA_W, ADDR_W)::type_id::create("mon", this);
    endfunction : build_phase

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (is_active == UVM_ACTIVE) begin
            drv.seq_item_port.connect(sqr.seq_item_export);
        end
    endfunction : connect_phase

endclass : axil_agent

`endif // AXIL_AGENT_SV
