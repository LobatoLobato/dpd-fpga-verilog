`ifndef DPD_ENVIRONMENT_SV
`define DPD_ENVIRONMENT_SV
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "dpd_agent.sv"
`include "dpd_scoreboard.sv"
`include "dpd_coverage.sv"
`include "axil_agent.sv"

class dpd_environment extends uvm_env;
    `uvm_component_utils(dpd_environment)

    dpd_agent      dpd_ag;
    dpd_scoreboard dpd_scb;
    dpd_coverage   dpd_cov;
    axil_agent #(32, configctl_defs::ADDR_W) axil_ag;

    virtual taxi_axil_if #(.DATA_W(32), .ADDR_W(configctl_defs::ADDR_W)) axil_vif;

    function new(string name = "dpd_environment", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        dpd_ag  = dpd_agent     ::type_id::create("dpd_ag", this);
        dpd_scb = dpd_scoreboard::type_id::create("dpd_scb", this);
        dpd_cov = dpd_coverage  ::type_id::create("dpd_cov", this);

        if (!uvm_config_db#(virtual taxi_axil_if #(.DATA_W(32), .ADDR_W(configctl_defs::ADDR_W)))::get(this, "", "bfm_axil0", axil_vif))
            `uvm_fatal(get_full_name(), "axil virtual interface not set via uvm_config_db");

        uvm_config_db#(virtual taxi_axil_if #(.DATA_W(32), .ADDR_W(configctl_defs::ADDR_W)))::set(
            this, "axil_ag.*", "vif", axil_vif);

        axil_ag = axil_agent #(32, configctl_defs::ADDR_W)::type_id::create("axil_ag", this);
    endfunction : build_phase

    function void connect_phase(uvm_phase phase);
        dpd_ag.dpd_mon.ap_command.connect(dpd_scb.command_fifo.analysis_export);
        dpd_ag.dpd_mon.ap_command.connect(dpd_cov.analysis_export);
        dpd_ag.dpd_mon.ap_result.connect(dpd_scb.result_fifo.analysis_export);
    endfunction : connect_phase

endclass : dpd_environment

`endif // DPD_ENVIRONMENT_SV
