`ifndef DPD_RANDOM_SEQUENCE_SV
`define DPD_RANDOM_SEQUENCE_SV
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "dpd_item.sv"

class random_sequence extends uvm_sequence #(dpd_item);
    `uvm_object_utils(random_sequence)

    dpd_item seq_item;
    int item_count;
    int num_items = 32;

    function new(string name = "random_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        seq_item = dpd_item::type_id::create("seq_item");
        item_count = 0;
        repeat (num_items) begin
            start_item(seq_item);
            if (!seq_item.randomize()) begin
                `uvm_error(get_full_name(), "Failed to randomize dpd_item")
            end
            item_count++;
            `uvm_info(get_full_name(), $sformatf("Sequence item %0d: %s", item_count, seq_item.convert2string()), UVM_MEDIUM)
            finish_item(seq_item);
        end
    endtask : body

endclass : random_sequence

`endif // DPD_RANDOM_SEQUENCE_SV
