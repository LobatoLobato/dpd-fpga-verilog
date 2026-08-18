`ifndef DPD_DRIVER_SV
`define DPD_DRIVER_SV
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "dpd_item.sv"

class dpd_driver extends uvm_driver #(dpd_item);
    `uvm_component_utils(dpd_driver)

    localparam int DATA_WIDTH      = 16;
    localparam int PACKED_IQ_WIDTH = 2 * DATA_WIDTH;

    virtual dpd_bfm                        bfm_clk0;
    virtual taxi_axis_if #(.DATA_W(PACKED_IQ_WIDTH),       .USER_W(2)) bfm_ref0;
    virtual taxi_axis_if #(.DATA_W(2*PACKED_IQ_WIDTH),     .USER_W(2)) bfm_cap0;

    function new(string name = "dpd_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual dpd_bfm)::get(this, "", "bfm_clk0", bfm_clk0))
            `uvm_fatal(get_full_name(), "BFM not set via uvm_config_db");
        if (!uvm_config_db#(virtual taxi_axis_if #(.DATA_W(PACKED_IQ_WIDTH), .USER_W(2)))::get(this, "", "bfm_ref0", bfm_ref0))
            `uvm_fatal(get_full_name(), "ref_axis virtual interface not set via uvm_config_db");
        if (!uvm_config_db#(virtual taxi_axis_if #(.DATA_W(2*PACKED_IQ_WIDTH), .USER_W(2)))::get(this, "", "bfm_cap0", bfm_cap0))
            `uvm_fatal(get_full_name(), "cap_axis virtual interface not set via uvm_config_db");
    endfunction : build_phase

    task automatic send_ref(input signed [DATA_WIDTH-1:0] i_val,
                            input signed [DATA_WIDTH-1:0] q_val);
        bfm_ref0.send({q_val, i_val});
    endtask : send_ref

    task run_phase(uvm_phase phase);
        dpd_item it;

        fork
            bfm_clk0.generate_clock(100_000_000, 0, 0);
            bfm_clk0.reset_pulse(1, 5, 1);
        join_any

        bfm_ref0.tvalid    <= 1'b0;
        bfm_ref0.tdata     <= '0;
        bfm_cap0.tready    <= 1'b1;
        repeat (7) @(posedge bfm_clk0.clk);

        forever begin
            seq_item_port.get_next_item(it);
            send_ref(it.i, it.q);
            seq_item_port.item_done();
        end
    endtask : run_phase

endclass : dpd_driver

`endif // DPD_DRIVER_SV
