`ifndef AXIS_AGENT_SV
`define AXIS_AGENT_SV
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "axis_sequencer.sv"
`include "axis_driver.sv"
`include "axis_monitor.sv"

class axis_agent #(int DATA_W = 32) extends uvm_agent;
    `uvm_component_param_utils(axis_agent #(DATA_W))

    axis_sequencer         sqr;
    axis_driver #(DATA_W)  drv;
    axis_monitor #(DATA_W) mon;

    function new(string name = "axis_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(uvm_active_passive_enum)::get(this, "", "is_active", is_active)) begin
            is_active = UVM_ACTIVE;
        end

        if (is_active == UVM_ACTIVE) begin
            sqr = axis_sequencer::type_id::create("sqr", this);
            drv = axis_driver #(DATA_W)::type_id::create("drv", this);
        end

        mon = axis_monitor #(DATA_W)::type_id::create("mon", this);
    endfunction : build_phase

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (is_active == UVM_ACTIVE) begin
            drv.seq_item_port.connect(sqr.seq_item_export);
        end
    endfunction : connect_phase

endclass : axis_agent

`endif // AXIS_AGENT_SV
