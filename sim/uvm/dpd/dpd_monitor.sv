`ifndef DPD_MONITOR_SV
`define DPD_MONITOR_SV
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"

class dpd_monitor extends uvm_monitor;
    `uvm_component_utils(dpd_monitor)

    localparam int DATA_WIDTH      = 16;
    localparam int PACKED_IQ_WIDTH = 2 * DATA_WIDTH;

    virtual dpd_bfm bfm_clk0;
    virtual taxi_axis_if #(.DATA_W(PACKED_IQ_WIDTH),   .USER_W(2)) bfm_ref0;
    virtual taxi_axis_if #(.DATA_W(2*PACKED_IQ_WIDTH), .USER_W(2)) bfm_cap0;

    uvm_analysis_port #(bit [PACKED_IQ_WIDTH-1:0])   ap_command; 
    uvm_analysis_port #(bit [2*PACKED_IQ_WIDTH-1:0]) ap_result; 

    function new(string name = "dpd_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        ap_command = new("ap_command", this);
        ap_result  = new("ap_result", this);

        if (!uvm_config_db#(virtual dpd_bfm)::get(this, "", "bfm_clk0", bfm_clk0))
            `uvm_fatal(get_full_name(), "BFM not set via uvm_config_db");
        if (!uvm_config_db#(virtual taxi_axis_if #(.DATA_W(PACKED_IQ_WIDTH), .USER_W(2)))::get(this, "", "bfm_ref0", bfm_ref0))
            `uvm_fatal(get_full_name(), "ref_axis virtual interface not set via uvm_config_db");
        if (!uvm_config_db#(virtual taxi_axis_if #(.DATA_W(2*PACKED_IQ_WIDTH), .USER_W(2)))::get(this, "", "bfm_cap0", bfm_cap0))
            `uvm_fatal(get_full_name(), "cap_axis virtual interface not set via uvm_config_db");
    endfunction : build_phase

    task command_monitor_task();
        forever begin
            @(posedge bfm_clk0.clk);
            if (bfm_ref0.tvalid && bfm_ref0.tready) begin
                ap_command.write(bfm_ref0.tdata);
            end
        end
    endtask

    task result_monitor_task();
        forever begin
            @(posedge bfm_clk0.clk);
            if (bfm_cap0.tvalid) begin
                ap_result.write(bfm_cap0.tdata);
            end
        end
    endtask

    task run_phase(uvm_phase phase);
        fork
            command_monitor_task();
            result_monitor_task();
        join_none
    endtask : run_phase

endclass : dpd_monitor

`endif // DPD_MONITOR_SV
