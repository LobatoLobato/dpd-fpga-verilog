`ifndef DPD_COVERAGE_SV
`define DPD_COVERAGE_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

class dpd_coverage extends uvm_subscriber #(bit [31:0]);
    `uvm_component_utils(dpd_coverage)

    protected bit signed [15:0] i_val; // I field of the packed {Q, I} sample

    covergroup dpd_cg;
        coverpoint i_val {
            bins near_min  = {[-32768:-28000]};
            bins large_neg = {[-27999:-10923]};
            bins small_neg = {[-10922:-1]};
            bins zero      = {0};
            bins small_pos = {[1:10922]};
            bins large_pos = {[10923:27999]};
            bins near_max  = {[28000:32767]};
        }
    endgroup : dpd_cg

    function new(string name = "dpd_coverage", uvm_component parent = null);
        super.new(name, parent);
        dpd_cg = new();
    endfunction : new

    function void write(bit [31:0] t);
        i_val = $signed(t[15:0]);
        dpd_cg.sample();
    endfunction : write

    function void report_phase(uvm_phase phase);
        `uvm_info(get_full_name(), $sformatf("\n--- DPD SAMPLE COVERAGE REPORT ---\nCoverage: %0.2f%%\n",
            dpd_cg.get_coverage()), UVM_LOW)
    endfunction : report_phase

endclass : dpd_coverage

`endif // DPD_COVERAGE_SV
