`ifndef DPD_AGENT_SV
`define DPD_AGENT_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "dpd_sequencer.sv"
`include "dpd_driver.sv"
`include "dpd_monitor.sv"

class dpd_agent extends uvm_agent;
    `uvm_component_utils(dpd_agent)

    localparam int DATA_WIDTH      = 16;
    localparam int PACKED_IQ_WIDTH = 2 * DATA_WIDTH;

    dpd_sequencer dpd_sqr;
    dpd_driver    dpd_drv;
    dpd_monitor   dpd_mon;

    function new(string name = "dpd_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(uvm_active_passive_enum)::get(this, "", "is_active", is_active)) begin
            is_active = UVM_ACTIVE;
        end

        if (is_active == UVM_ACTIVE) begin
            `uvm_info(get_full_name(), "Building ACTIVE agent: Driver and Sequencer included.", UVM_HIGH)
            dpd_sqr = dpd_sequencer::type_id::create("dpd_sqr", this);
            dpd_drv = dpd_driver   ::type_id::create("dpd_drv", this);
        end else begin
            `uvm_info(get_full_name(), "Building PASSIVE agent: Only Monitor included.", UVM_HIGH)
        end

        dpd_mon = dpd_monitor::type_id::create("dpd_mon", this);

        if (!uvm_config_db#(virtual dpd_bfm)::get(this, "", "bfm_clk0", dpd_mon.bfm_clk0)) begin
            `uvm_fatal("DPD_AGENT", "Virtual interface 'bfm_clk0' not set for Monitor.")
        end
        if (!uvm_config_db#(virtual taxi_axis_if #(.DATA_W(PACKED_IQ_WIDTH), .USER_W(2)))::get(this, "", "bfm_ref0", dpd_mon.bfm_ref0)) begin
            `uvm_fatal("DPD_AGENT", "Virtual interface 'bfm_ref0' not set for Monitor.")
        end
        if (!uvm_config_db#(virtual taxi_axis_if #(.DATA_W(2*PACKED_IQ_WIDTH), .USER_W(2)))::get(this, "", "bfm_cap0", dpd_mon.bfm_cap0)) begin
            `uvm_fatal("DPD_AGENT", "Virtual interface 'bfm_cap0' not set for Monitor.")
        end

        if (is_active == UVM_ACTIVE) begin
            if (!uvm_config_db#(virtual dpd_bfm)::get(this, "", "bfm_clk0", dpd_drv.bfm_clk0)) begin
                `uvm_fatal("DPD_AGENT", "Virtual interface 'bfm_clk0' not set for Driver.")
            end
            if (!uvm_config_db#(virtual taxi_axis_if #(.DATA_W(PACKED_IQ_WIDTH), .USER_W(2)))::get(this, "", "bfm_ref0", dpd_drv.bfm_ref0)) begin
                `uvm_fatal("DPD_AGENT", "Virtual interface 'bfm_ref0' not set for Driver.")
            end
            if (!uvm_config_db#(virtual taxi_axis_if #(.DATA_W(2*PACKED_IQ_WIDTH), .USER_W(2)))::get(this, "", "bfm_cap0", dpd_drv.bfm_cap0)) begin
                `uvm_fatal("DPD_AGENT", "Virtual interface 'bfm_cap0' not set for Driver.")
            end
        end
    endfunction : build_phase

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        if (is_active == UVM_ACTIVE) begin
            dpd_drv.seq_item_port.connect(dpd_sqr.seq_item_export);
            `uvm_info(get_full_name(), "Connected driver to sequencer.", UVM_MEDIUM)
        end
    endfunction : connect_phase

endclass : dpd_agent

`endif // DPD_AGENT_SV
