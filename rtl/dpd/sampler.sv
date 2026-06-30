`resetall
`timescale 1ns / 1ps
`default_nettype none

module sampler #(
    parameter integer DATA_WIDTH = 14,
    parameter integer FIFO_DEPTH = 16
)(
    input wire clk,
    input wire rst,
    input wire we,
    input wire start,
    
    input wire [11:0] delay_length,
    input wire [11:0] batch_length,
    
    axis_if.slave ref_axis,
    axis_if.slave fb_axis,

    axis_if.master cap_axis
);
    wire done, batch_done;
    wire capture_ref, capture_fb;
    wire capture_sample;

    // Capture Controller
    // Controls batching and the feedback sampling delay
    capturectl capturectl (
    	.clk(clk), .rst(rst), .start(start), .we(we),
    	.delay_length(delay_length),
    	.batch_length(batch_length),
    	.capture_done(done),
    	.capture_ref(capture_ref), .capture_fb(capture_fb),
        .capture_sample(capture_sample),
        .batch_done(batch_done)
    );
    
    // Reference data FIFO
    // Captures unfiltered input data
    wire fifo_ref_valid;
    wire fifo_ref_overflow, fifo_ref_bad_frame;
    wire logic [DATA_WIDTH-1:0] i_ref_capture;
    axis_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .KEEP_ENABLE(0), .LAST_ENABLE(0), .ID_ENABLE(0), .DEST_ENABLE(0), .USER_ENABLE(0),
        .DEPTH(FIFO_DEPTH)
    ) fifo_ref_inst (
        .clk(clk), .rst(rst),
        .s_axis_tvalid(ref_axis.tvalid & capture_ref),
        .s_axis_tready(ref_axis.tready),
        .s_axis_tdata (ref_axis.tdata),
        .s_axis_tkeep (2'd0), .s_axis_tlast (1'd0), .s_axis_tid(8'd0), .s_axis_tdest(8'd0), .s_axis_tuser(1'd0),
        .m_axis_tvalid(fifo_ref_valid),
        .m_axis_tready(done),
        .m_axis_tdata (i_ref_capture),
        .m_axis_tkeep(), .m_axis_tlast(), .m_axis_tid(), .m_axis_tdest(), .m_axis_tuser(),
        .pause_req(), .pause_ack(),
        .status_depth(), .status_depth_commit(), .status_good_frame(),
        .status_overflow(fifo_ref_overflow), .status_bad_frame(fifo_ref_bad_frame)
    );

    // Feedback FIFO
    // Captures feedback data after $fb_delay clock cycles
    wire logic [DATA_WIDTH-1:0] i_fb_capture;
    wire fifo_fb_valid;
    wire fifo_fb_overflow, fifo_fb_bad_frame;
    axis_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .KEEP_ENABLE(0), .LAST_ENABLE(0), .ID_ENABLE(0), .DEST_ENABLE(0), .USER_ENABLE(0),
        .DEPTH(FIFO_DEPTH)
    )
    fifo_fb_inst (
        .clk(clk), .rst(rst),
        .s_axis_tvalid(fb_axis.tvalid & capture_fb),
        .s_axis_tready(fb_axis.tready),
        .s_axis_tdata (fb_axis.tdata),
        .s_axis_tkeep (2'd0), .s_axis_tlast (1'd0), .s_axis_tid(8'd0), .s_axis_tdest(8'd0), .s_axis_tuser(1'd0),
        .m_axis_tvalid(fifo_fb_valid),
        .m_axis_tready(done),
        .m_axis_tdata (i_fb_capture),
        .m_axis_tkeep(), .m_axis_tlast(), .m_axis_tid(), .m_axis_tdest(), .m_axis_tuser(),
        .pause_req(1'd0), .pause_ack(),
        .status_depth(), .status_depth_commit(), .status_good_frame(),
        .status_overflow(fifo_fb_overflow), .status_bad_frame(fifo_fb_bad_frame)
    );

    assign done = fifo_ref_valid & fifo_fb_valid & capture_sample;
    
    assign cap_axis.tvalid = done;
    assign cap_axis.tdata = done ? {i_fb_capture, i_ref_capture} : 0;
    assign cap_axis.tlast = batch_done;
    assign cap_axis.tuser = {fifo_fb_bad_frame, fifo_fb_overflow, fifo_ref_bad_frame, fifo_ref_overflow};
endmodule

module capturectl (
    input wire clk, rst, start, we,
    input wire [11:0] delay_length,
    input wire [11:0] batch_length,
    input wire capture_done,

    output reg capture_ref, capture_fb,
    output wire capture_sample,
    output reg batch_done
);
    reg [11:0] delay_counter = 0;
    reg [11:0] sample_counter = 0;

    assign capture_sample = capture_ref & capture_fb;
    
    always @(posedge clk) begin
        if (rst) begin
            capture_ref <= 0;
            capture_fb <= 0;
            delay_counter <= 0;
            sample_counter <= 0;
            batch_done <= 0;
        end else begin
            if (!capture_ref & start & we) begin
                capture_ref <= 1;
                sample_counter <= 0;
                delay_counter <= 1;
                batch_done <= 0;
            end 
            
            if (delay_counter >= delay_length) begin
                capture_fb <= 1;
                delay_counter <= delay_length;
            end else if(capture_ref) begin
                delay_counter <= delay_counter + 1;
            end
            
            if (sample_counter >= batch_length - 1) begin
                capture_fb <= 0;
                capture_ref <= 0;
                batch_done <= 1;
            end else if(capture_fb & capture_done) begin
                sample_counter <= sample_counter + 1;
            end    
        end
    end
endmodule