`resetall
`timescale 1ns/1ps
`default_nettype none

import uvm_pkg::*;
`include "uvm_macros.svh"

module testbench;
    parameter int DATA_WIDTH = 16;
    parameter int PACKED_IQ_DATA_WIDTH = DATA_WIDTH * 2;
    parameter int BATCH_LEN_MAX = 64;
    parameter int DELAY_LEN_MAX = 32;
    parameter int AXIL_DATA_W = 32;
    parameter int AXIL_ADDR_W = configctl_defs::ADDR_W;

    dpd_bfm bfm_clk0();

    taxi_axis_if #(.DATA_W(PACKED_IQ_DATA_WIDTH), .USER_W(2)) ref_axis(.tb_clk(bfm_clk0.clk));
    taxi_axis_if #(.DATA_W(PACKED_IQ_DATA_WIDTH), .USER_W(2)) predistorted_axis(.tb_clk(bfm_clk0.clk));
    taxi_axis_if #(.DATA_W(PACKED_IQ_DATA_WIDTH * 2), .USER_W(2)) cap_axis(.tb_clk(bfm_clk0.clk));
    taxi_axil_if #(.DATA_W(AXIL_DATA_W), .ADDR_W(AXIL_ADDR_W)) axil(.tb_clk(bfm_clk0.clk));

    top #(
        .DATA_WIDTH   (DATA_WIDTH),
        .BATCH_LEN_MAX(BATCH_LEN_MAX),
        .DELAY_LEN_MAX(DELAY_LEN_MAX),
        .AXIL_DATA_W  (AXIL_DATA_W),
        .AXIL_ADDR_W  (AXIL_ADDR_W)
    ) dut (
        .clk              (bfm_clk0.clk),
        .rst              (bfm_clk0.rst),
        .tdd_sig          (1'b0),
        .ref_axis         (ref_axis),
        .fb_axis          (predistorted_axis),
        .predistorted_axis(predistorted_axis),
        .cap_axis         (cap_axis),
        .axil             (axil)
    );

    initial begin
        uvm_config_db#(virtual dpd_bfm)::set(null, "*", "bfm_clk0", bfm_clk0);
        uvm_config_db#(virtual taxi_axis_if #(.DATA_W(PACKED_IQ_DATA_WIDTH), .USER_W(2)))::set(null, "*", "bfm_ref0", ref_axis);
        uvm_config_db#(virtual taxi_axis_if #(.DATA_W(PACKED_IQ_DATA_WIDTH * 2), .USER_W(2)))::set(null, "*", "bfm_cap0", cap_axis);
        uvm_config_db#(virtual taxi_axil_if #(.DATA_W(AXIL_DATA_W), .ADDR_W(AXIL_ADDR_W)))::set(null, "*", "bfm_axil0", axil);
        run_test();
    end

endmodule
