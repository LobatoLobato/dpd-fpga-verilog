`ifndef AXIS_SEQUENCER_SV
`define AXIS_SEQUENCER_SV
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "axis_item.sv"

class axis_sequencer extends uvm_sequencer #(axis_item);
    `uvm_component_utils(axis_sequencer)

    function new(string name = "axis_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

endclass : axis_sequencer

`endif // AXIS_SEQUENCER_SV
