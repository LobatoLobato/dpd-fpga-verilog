`ifndef DPD_CONFIG_SEQ_SV
`define DPD_CONFIG_SEQ_SV
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "axil_item.sv"

class dpd_config_seq extends uvm_sequence #(axil_item #(32, configctl_defs::ADDR_W));
    `uvm_object_utils(dpd_config_seq)

    localparam int DATA_W      = 32;
    localparam int WEIGHT_WIDTH = 12;

    bit signed [11:0] wi [4] = '{ 12'sd1229, -12'sd614, 12'sd410, -12'sd307 };  // +0.60, -0.30, +0.20, -0.15
    bit signed [11:0] wq [4] = '{ 12'sd0,    12'sd0,    12'sd0,    12'sd0 };   // no cross-Q predistortion
    bit bypass = 0;
    int batch_length = 8;

    localparam int FILTER_LATENCY = 4;

    function new(string name = "dpd_config_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        for (int k = 0; k < 4; k++) begin
            write_config(configctl_defs::reg_addr_t'(int'(configctl_defs::REG_WEIGHT_I0) + k),
                         {{(DATA_W - WEIGHT_WIDTH){1'b0}}, wi[k]});
            write_config(configctl_defs::reg_addr_t'(int'(configctl_defs::REG_WEIGHT_Q0) + k),
                         {{(DATA_W - WEIGHT_WIDTH){1'b0}}, wq[k]});
        end
        write_config(configctl_defs::REG_BATCH_LEN, {16'b0, batch_length[15:0]});
        write_config(configctl_defs::REG_DELAY_LEN, {20'b0, FILTER_LATENCY[11:0]});
        // REG_CTRL: bit0=start (pulse), bit1=tdd_en, bit2=bypass
        write_config(configctl_defs::REG_CTRL, {29'b0, bypass, 1'b0, 1'b1});
    endtask : body

    virtual task write_config(input logic [configctl_defs::ADDR_W-1:0] addr,
                              input logic [31:0] data);
        axil_item #(32, configctl_defs::ADDR_W) item;
        item = axil_item #(32, configctl_defs::ADDR_W)::type_id::create("item");
        item.op   = axil_item #(32, configctl_defs::ADDR_W)::AXIL_WRITE;
        item.addr = addr;
        item.data = data;
        item.strb = '1;
        start_item(item);
        finish_item(item);
    endtask : write_config

endclass : dpd_config_seq

`endif // DPD_CONFIG_SEQ_SV
