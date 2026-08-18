`ifndef DPD_ITEM_SV
`define DPD_ITEM_SV
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"

class dpd_item extends uvm_sequence_item;
    `uvm_object_utils(dpd_item)

    rand bit signed [15:0] i;
    rand bit signed [15:0] q;

    function new(string name = "dpd_item");
        super.new(name);
    endfunction : new

    function string convert2string();
        return $sformatf("i=%0d q=%0d", i, q);
    endfunction : convert2string

endclass : dpd_item

`endif // DPD_ITEM_SV
