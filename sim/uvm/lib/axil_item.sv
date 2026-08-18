`ifndef AXIL_ITEM_SV
`define AXIL_ITEM_SV
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"

class axil_item #(int DATA_W = 32, int ADDR_W = 4) extends uvm_sequence_item;
    `uvm_object_param_utils(axil_item #(DATA_W, ADDR_W))

    typedef enum bit { AXIL_WRITE, AXIL_READ } axil_op_e;

    rand axil_op_e           op;
    rand logic [ADDR_W-1:0]  addr;
    rand logic [DATA_W-1:0]  data;
    rand logic [DATA_W/8-1:0] strb;

    constraint c_strb { strb != '0; }

    function new(string name = "axil_item");
        super.new(name);
    endfunction : new

    function string convert2string();
        return $sformatf("%s addr=0x%0h data=0x%0h strb=%b", op.name(), addr, data, strb);
    endfunction : convert2string

endclass : axil_item

`endif // AXIL_ITEM_SV
