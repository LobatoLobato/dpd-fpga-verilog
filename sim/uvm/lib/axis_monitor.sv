`ifndef AXIS_MONITOR_SV
`define AXIS_MONITOR_SV
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "axis_item.sv"

class axis_monitor #(int DATA_W = 32) extends uvm_monitor;
    `uvm_component_param_utils(axis_monitor #(DATA_W))

    virtual taxi_axis_if #(.DATA_W(DATA_W), .USER_W(2)) vif;

    uvm_analysis_port #(axis_item) ap;

    int trans_count;   // beats observed (detects output where none is expected)
    int last_count;    // tlast beats observed (detects a premature completion)

    function new(string name = "axis_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        trans_count = 0;
        last_count = 0;
        if (!uvm_config_db#(virtual taxi_axis_if #(.DATA_W(DATA_W), .USER_W(2)))::get(this, "", "vif", vif))
            `uvm_fatal(get_full_name(), "Virtual interface not set via uvm_config_db");
    endfunction : build_phase

    task run_phase(uvm_phase phase);
        axis_item item;

        forever begin
            @(posedge vif.tb_clk);
            if (vif.tvalid && vif.tready) begin
                item = axis_item::type_id::create("item");
                item.data = vif.tdata;
                item.user = vif.tuser;
                item.last = vif.tlast;
                trans_count++;
                if (item.last)
                    last_count++;
                ap.write(item);
            end
        end
    endtask : run_phase

endclass : axis_monitor

`endif // AXIS_MONITOR_SV
