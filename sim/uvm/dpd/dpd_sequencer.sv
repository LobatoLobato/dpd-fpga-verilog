`ifndef DPD_SEQUENCER_SV
`define DPD_SEQUENCER_SV
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "dpd_item.sv"

class dpd_sequencer extends uvm_sequencer #(dpd_item);
    `uvm_component_utils(dpd_sequencer)

    function new(string name = "dpd_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

endclass : dpd_sequencer

`endif // DPD_SEQUENCER_SV
