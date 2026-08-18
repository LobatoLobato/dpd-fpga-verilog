`timescale 1ns/1ps

module top #(
    parameter integer DATA_WIDTH = 16,
    parameter integer BATCH_LEN_MAX = 16,
    parameter integer DELAY_LEN_MAX = 0,
    parameter integer WEIGHT_W      = 12,
    parameter integer AXIL_DATA_W = 32,
    parameter integer AXIL_ADDR_W = configctl_defs::ADDR_W
) (
    input wire clk,
    input wire rst,
    input wire tdd_sig,

    taxi_axis_if.snk ref_axis,
    taxi_axis_if.snk fb_axis,

    taxi_axis_if.src predistorted_axis,
    taxi_axis_if.src cap_axis,

    taxi_axil_if axil
);
    localparam integer PACKED_IQ_DATA_WIDTH = DATA_WIDTH * 2; // {Q, I}

    // ref_axis fan-out to the filter and sampler
    taxi_axis_if #(.DATA_W(PACKED_IQ_DATA_WIDTH)) ref_to_filter();
    taxi_axis_if #(.DATA_W(PACKED_IQ_DATA_WIDTH)) ref_to_sampler();

    always_comb begin
        ref_to_filter.tvalid <= ref_axis.tvalid;
        ref_to_filter.tdata  <= ref_axis.tdata;
        ref_to_filter.tuser  <= ref_axis.tuser;
        ref_to_filter.tlast  <= ref_axis.tlast;

        ref_to_sampler.tvalid <= ref_axis.tvalid;
        ref_to_sampler.tdata  <= ref_axis.tdata;
        ref_to_sampler.tuser  <= ref_axis.tuser;
        ref_to_sampler.tlast  <= ref_axis.tlast;
    end

    assign ref_axis.tready = ref_to_filter.tready & ref_to_sampler.tready;

    configctl #(
        .DATA_W        (AXIL_DATA_W),
        .BATCH_LEN_MAX (BATCH_LEN_MAX),
        .DELAY_LEN_MAX (DELAY_LEN_MAX),
        .WEIGHT_W      (WEIGHT_W)
    ) config_controller (
        .clk(clk), .rst(rst),
        .axil_wr(axil),
        .axil_rd(axil)
    );

    tddctl tdd_controller (
        .clk(clk), .rst(rst),
        .tdd_tx(tdd_sig),
        .tdd_en(config_controller.tdd_en),
        .trigger(config_controller.start)
    );

    filter #(.DATA_WIDTH(DATA_WIDTH)) filter_inst (
        .clk(clk), .rst(rst),
        .weights_i(config_controller.weights_i),
        .weights_q(config_controller.weights_q),
        .bypass(config_controller.bypass),
        .input_axis(ref_to_filter),
        .output_axis(predistorted_axis)
    );

    sampler #(
        .DATA_WIDTH(PACKED_IQ_DATA_WIDTH),
        .BATCH_LEN_MAX(BATCH_LEN_MAX),
        .DELAY_LEN_MAX(DELAY_LEN_MAX)
    ) sampler_inst (
        .clk(clk), .rst(rst),
        .we(tdd_controller.we),
        .start(tdd_controller.start),
        .delay_length(config_controller.delay_length),
        .batch_length(config_controller.batch_length),
        .ref_axis(ref_to_sampler),
        .fb_axis(fb_axis),
        .cap_axis(cap_axis)
    );
endmodule
