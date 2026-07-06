// slang lint_off unconnected-output-port
`timescale 1ns/1ps

module top(
    input clk,
    input rst,
    input tdd_sig
);
    parameter DATA_WIDTH = 14;
    parameter FIFO_DEPTH = 16;
    parameter AXIL_DATA_W = 32;
    parameter AXIL_ADDR_W = configctl_defs::ADDR_W;
    
    axis_if #(.DATA_WIDTH(DATA_WIDTH))   ref_axis();
    axis_if #(.DATA_WIDTH(DATA_WIDTH))   fb_axis ();
    axis_if #(.DATA_WIDTH(DATA_WIDTH*2)) cap_axis();

    taxi_axil_if #(.DATA_W(AXIL_DATA_W), .ADDR_W(AXIL_ADDR_W)) axil(.tb_clk());

    configctl #(.DATA_W(AXIL_DATA_W)) config_controller (
    	.clk         (clk),
    	.rst         (rst),
    	.axil_wr     (axil),
    	.axil_rd     (axil)
    );
    
    tddctl tdd_controller (
        .clk(clk), .rst(rst),
        .tdd_tx(tdd_sig),
        .tdd_en(config_controller.tdd_en),
        .trigger(config_controller.start)
    );
    
    sampler #(.DATA_WIDTH(DATA_WIDTH), .FIFO_DEPTH(FIFO_DEPTH)) sampler_inst (
    	.clk(clk), .rst(rst),
        .we           (tdd_controller.we),
        .start        (tdd_controller.start),
        .delay_length (config_controller.delay_length),
        .batch_length (config_controller.batch_length),
    	.ref_axis     (ref_axis),
    	.fb_axis      (fb_axis),
        .cap_axis     (cap_axis)
    );
    
    filter #(
    	.DATA_WIDTH(DATA_WIDTH)
    ) filter_inst (
        .clk(clk), .rst(rst),
        .weights     (config_controller.weights),
        .bypass      (config_controller.bypass),
    	.input_axis  (ref_axis),
    	.output_axis (fb_axis)
    );
endmodule