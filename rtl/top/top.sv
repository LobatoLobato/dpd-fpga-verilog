`timescale 1ns/1ps

module top(
    input clk,
    input rst,
    input tdd_sig
);
    parameter DATA_WIDTH = 14;
    parameter FIFO_DEPTH = 16;

    capture_cfg_if #(.DATA_WIDTH(DATA_WIDTH)) cap_cfg();
    filter_cfg_if filt_cfg();
    
    axis_if #(.DATA_WIDTH(DATA_WIDTH))   ref_axis();
    axis_if #(.DATA_WIDTH(DATA_WIDTH))   fb_axis ();
    axis_if #(.DATA_WIDTH(DATA_WIDTH*2)) cap_axis();
    
    wire sampler_we;

    configctl reg_bank_inst (
        .cap_cfg(cap_cfg),
        .filt_cfg(filt_cfg)
    );

    assign cap_cfg.data = cap_axis.tdata;
    assign cap_cfg.err_code = cap_axis.tuser;
    
    tddctl tdd_controller_inst(
        .tdd_sig(tdd_sig),
        .tdd_en(cap_cfg.tdd_en),
        .we(sampler_we)
    );
    
    sampler #(
    	.DATA_WIDTH(DATA_WIDTH),
    	.FIFO_DEPTH(FIFO_DEPTH)
    ) sampler_inst (
    	.clk      (clk),
    	.rst      (rst),
        .we       (sampler_we),
        .start    (cap_cfg.start),
        .delay_length (cap_cfg.delay_length),
        .batch_length   (cap_cfg.batch_length),
    	.ref_axis (ref_axis),
    	.fb_axis  (fb_axis),
        .cap_axis (cap_axis),
        .batch_done(cap_cfg.done)
    );
    
    filter #(
    	.DATA_WIDTH(DATA_WIDTH)
    ) filter_inst (
        .clk(clk), .rst(rst),
        .weights(filt_cfg.weights),
        .bypass(filt_cfg.bypass),
    	.input_axis (ref_axis),
    	.output_axis(fb_axis)
    );
endmodule