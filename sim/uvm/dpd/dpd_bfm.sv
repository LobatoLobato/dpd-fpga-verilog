`ifndef DPD_BFM_SV
`define DPD_BFM_SV
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"

interface dpd_bfm;
    bit clk;
    bit rst;

    task automatic generate_clock(
        input real freq    = 100_000_000.0,
        input bit  clk_pol = 0,
        input real delay   = 0.0
    );
        clk = ~clk_pol;
        #(delay);
        forever begin
            clk = ~clk;
            #(1.0 / (2.0 * freq) * 1e9);
        end
    endtask : generate_clock

    task automatic reset_pulse(
        input bit rst_pol   = 1,
        input int rst_width = 5,
        input bit rst_edge  = 1
    );
        if (rst_edge) @(posedge clk); else @(negedge clk);
        rst = rst_pol;
        repeat (rst_width) begin
            if (rst_edge) @(posedge clk); else @(negedge clk);
        end
        rst = ~rst_pol;
    endtask : reset_pulse

endinterface : dpd_bfm

`endif // DPD_BFM_SV
