`ifndef AXIS_ITEM_SV
`define AXIS_ITEM_SV
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"

class axis_item extends uvm_sequence_item;
    `uvm_object_utils(axis_item)

    rand logic [31:0] data;
    rand logic [1:0]  user;
    rand logic        last;

    constraint c_last { last == 1'b0; }

    function new(string name = "axis_item");
        super.new(name);
    endfunction : new

    function string convert2string();
        return $sformatf("data=%0d user=%b last=%b", data, user, last);
    endfunction : convert2string

endclass : axis_item

`endif // AXIS_ITEM_SV
