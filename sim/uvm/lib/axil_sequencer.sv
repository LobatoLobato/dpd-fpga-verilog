`ifndef AXIL_SEQUENCER_SV
`define AXIL_SEQUENCER_SV
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "axil_item.sv"

class axil_sequencer #(int DATA_W = 32, int ADDR_W = 4) extends uvm_sequencer #(axil_item #(DATA_W, ADDR_W));
    `uvm_component_param_utils(axil_sequencer #(DATA_W, ADDR_W))

    function new(string name = "axil_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

endclass : axil_sequencer

`endif // AXIL_SEQUENCER_SV
