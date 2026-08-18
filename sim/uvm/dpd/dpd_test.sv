`ifndef DPD_TEST_SV
`define DPD_TEST_SV
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "dpd_environment.sv"
`include "dpd_config_seq.sv"
`include "random_sequence.sv"

class dpd_coverage_seq extends uvm_sequence #(dpd_item);
    `uvm_object_utils(dpd_coverage_seq)

    int band_i [11] = '{ 0, 100, -100, 10922, -10922, 10923, -10923,
                          28000, -28000, 32767, -32768 };

    function new(string name = "dpd_coverage_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        dpd_item item;
        foreach (band_i[k]) begin
            item = dpd_item::type_id::create("item");
            item.i = band_i[k];
            item.q = 0;
            start_item(item);
            finish_item(item);
        end
    endtask : body

endclass : dpd_coverage_seq

class dpd_test extends uvm_test;
    `uvm_component_utils(dpd_test)

    dpd_environment dpd_env;
    bit test_bypass_mode = 0;
    int test_num_items = 32;

    function new(string name = "dpd_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_active_passive_enum)::set(this, "dpd_env.dpd_ag", "is_active", UVM_ACTIVE);
        uvm_config_db#(bit)::set(this, "dpd_env.*", "bypass_mode", test_bypass_mode);
        dpd_env = dpd_environment::type_id::create("dpd_env", this);
    endfunction : build_phase

    task run_phase(uvm_phase phase);
        dpd_config_seq  cfg_seq;
        random_sequence rnd_seq;
        dpd_coverage_seq cov_seq;
        phase.raise_objection(this);

        wait (dpd_env.dpd_ag.dpd_mon.bfm_clk0.rst === 1'b1);
        wait (dpd_env.dpd_ag.dpd_mon.bfm_clk0.rst === 1'b0);
        repeat (7) @(posedge dpd_env.dpd_ag.dpd_mon.bfm_clk0.clk);

        cfg_seq = dpd_config_seq::type_id::create("cfg_seq");
        cfg_seq.bypass = test_bypass_mode;
        `uvm_info(get_full_name(), "Configuring DPD datapath via AXI-Lite...", UVM_LOW)
        cfg_seq.start(dpd_env.axil_ag.sqr);

        repeat (20) @(posedge dpd_env.dpd_ag.dpd_mon.bfm_clk0.clk);

        rnd_seq = random_sequence::type_id::create("rnd_seq");
        rnd_seq.num_items = test_num_items;
        `uvm_info(get_full_name(), "Starting RANDOM SEQUENCE on DPD sequencer...", UVM_LOW)
        rnd_seq.start(dpd_env.dpd_ag.dpd_sqr);

        cov_seq = dpd_coverage_seq::type_id::create("cov_seq");
        `uvm_info(get_full_name(), "Driving coverage band anchors on DPD sequencer...", UVM_LOW)
        cov_seq.start(dpd_env.dpd_ag.dpd_sqr);

        repeat (60) @(posedge dpd_env.dpd_ag.dpd_mon.bfm_clk0.clk);

        phase.drop_objection(this);
    endtask : run_phase

endclass : dpd_test

class dpd_bypass_test extends dpd_test;
    `uvm_component_utils(dpd_bypass_test)

    function new(string name = "dpd_bypass_test", uvm_component parent = null);
        super.new(name, parent);
        test_bypass_mode = 1;
    endfunction : new

endclass : dpd_bypass_test

`endif // DPD_TEST_SV
