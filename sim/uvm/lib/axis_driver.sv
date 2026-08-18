`ifndef AXIS_DRIVER_SV
`define AXIS_DRIVER_SV
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "axis_item.sv"

class axis_driver #(int DATA_W = 32) extends uvm_driver #(axis_item);
    `uvm_component_param_utils(axis_driver #(DATA_W))

    virtual taxi_axis_if #(.DATA_W(DATA_W), .USER_W(2)) vif;

    function new(string name = "axis_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual taxi_axis_if #(.DATA_W(DATA_W), .USER_W(2)))::get(this, "", "vif", vif))
            `uvm_fatal(get_full_name(), "Virtual interface not set via uvm_config_db");
    endfunction : build_phase

    task run_phase(uvm_phase phase);
        axis_item item;

        forever begin
            seq_item_port.get_next_item(item);
            vif.send(item.data[DATA_W - 1:0], item.user, item.last);
            seq_item_port.item_done();
        end
    endtask : run_phase

endclass : axis_driver

`endif // AXIS_DRIVER_SV
