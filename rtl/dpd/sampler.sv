`resetall
`timescale 1ns / 1ps
`default_nettype none

module sampler #(
    parameter integer DATA_WIDTH = 32, // {Q[16], I[16]}
    parameter BATCH_LEN_MAX = 512,
    parameter DELAY_LEN_MAX = 16,
    localparam BATCH_LEN_WIDTH = $clog2(BATCH_LEN_MAX + 1),
    localparam DELAY_LEN_WIDTH = $clog2(DELAY_LEN_MAX)
)(
    input wire clk,
    input wire rst,
    input wire we,
    input wire start,

    input wire [DELAY_LEN_WIDTH - 1:0] delay_length,
    input wire [BATCH_LEN_WIDTH - 1:0] batch_length,

    taxi_axis_if.snk ref_axis,
    taxi_axis_if.snk fb_axis,

    taxi_axis_if.src cap_axis
);

    taxi_axis_if #(.DATA_W(DATA_WIDTH*2), .USER_W(2)) presynced_axis();

    wire cap_tready;
    assign cap_tready = cap_axis.tready;

    presync #(
        .BATCH_LEN_MAX(BATCH_LEN_MAX),
        .DELAY_LEN_MAX(DELAY_LEN_MAX)
    ) presync (
        .clk         (clk),
        .rst         (rst),
        .we          (we),
        .start       (start),
        .delay_length(delay_length),
        .batch_length(batch_length),
        .ref_axis    (ref_axis),
        .fb_axis     (fb_axis),
        .presynced_axis   (presynced_axis)
    );

    sync_buffer #(
        .DATA_WIDTH   (DATA_WIDTH),
        .BATCH_LEN_MAX(BATCH_LEN_MAX)
    ) sync_buffer (
        .clk          (clk),
        .rst          (rst),
        .we           (we),
        .start        (start),
        .presynced_axis    (presynced_axis),
        .buffered_axis(cap_axis),
        .rd_en        (cap_tready)
    );
endmodule // sampler

module presync #(
    parameter BATCH_LEN_MAX = 512,
    parameter DELAY_LEN_MAX = 16,
    localparam BATCH_LEN_WIDTH = $clog2(BATCH_LEN_MAX + 1),
    localparam DELAY_LEN_WIDTH = $clog2(DELAY_LEN_MAX)
)(
    input wire clk,
    input wire rst,
    input wire we,
    input wire start,

    input wire [DELAY_LEN_WIDTH - 1:0] delay_length,
    input wire [BATCH_LEN_WIDTH - 1:0] batch_length,

    taxi_axis_if.snk ref_axis,
    taxi_axis_if.snk fb_axis,

    taxi_axis_if.src presynced_axis
);
    reg [DELAY_LEN_WIDTH - 1:0] capture_cnt;
    reg [BATCH_LEN_WIDTH - 1:0] ref_batch_cnt;
    reg [BATCH_LEN_WIDTH - 1:0] fb_batch_cnt;
    reg running;
    wire capturing_ref = (ref_batch_cnt < batch_length) && ref_axis.tvalid;
    wire capturing_fb  = (capture_cnt >= delay_length) && (fb_batch_cnt < batch_length) && fb_axis.tvalid;

    assign ref_axis.tready = 1'b1;
    assign fb_axis.tready  = 1'b1;

    always_comb begin
        presynced_axis.tvalid = 1'b1;
        presynced_axis.tdata  = {fb_axis.tdata, ref_axis.tdata};
        presynced_axis.tuser  = {(running && capturing_fb), (running && capturing_ref)};

        // tlast marks the beat that completes the batch, whether ref, fb, or
        // both streams finish it last, so input stalls never abort a capture.
        presynced_axis.tlast  = running && (
            (capturing_fb  && (fb_batch_cnt == batch_length - 1) && (ref_batch_cnt == batch_length)) ||
            (capturing_ref && (ref_batch_cnt == batch_length - 1) && (fb_batch_cnt == batch_length)) ||
            (capturing_ref && (ref_batch_cnt == batch_length - 1) && capturing_fb  && (fb_batch_cnt == batch_length - 1))
        );
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            running       <= 1'b0;
            capture_cnt   <= '0;
            ref_batch_cnt <= '0;
            fb_batch_cnt  <= '0;
        end else begin
            if (start && we) begin
                running       <= 1'b1;
                capture_cnt   <= '0;
                ref_batch_cnt <= '0;
                fb_batch_cnt  <= '0;
            end else if (running) begin
                if (ref_batch_cnt >= batch_length && fb_batch_cnt >= batch_length)
                    running <= 1'b0;
                if (ref_axis.tvalid && ref_batch_cnt < batch_length)
                    ref_batch_cnt <= ref_batch_cnt + 1'b1;
                if (fb_axis.tvalid && capture_cnt >= delay_length && fb_batch_cnt < batch_length)
                    fb_batch_cnt <= fb_batch_cnt + 1'b1;
                if (ref_axis.tvalid && fb_axis.tvalid && capture_cnt < delay_length)
                    capture_cnt <= capture_cnt + 1'b1;
            end
        end
    end
endmodule // presync

module sync_buffer #(
    parameter unsigned DATA_WIDTH = 32, // {Q[16], I[16]}
    parameter unsigned BATCH_LEN_MAX = 512,

    localparam unsigned BATCH_LEN_WIDTH = $clog2(BATCH_LEN_MAX)
)(
    input wire clk,
    input wire rst,
    input wire we,
    input wire start,

    taxi_axis_if.snk presynced_axis,

    taxi_axis_if.src buffered_axis,
    input wire rd_en = 1'b1
);
    logic [DATA_WIDTH-1:0] ref_fifo [BATCH_LEN_MAX];
    logic [BATCH_LEN_WIDTH-1:0] ref_wr_ptr;

    logic [DATA_WIDTH-1:0] fb_fifo  [BATCH_LEN_MAX];
    logic [BATCH_LEN_WIDTH-1:0] fb_wr_ptr;

    logic [BATCH_LEN_WIDTH-1:0] rd_ptr;
    logic capturing;

    wire ref_we = presynced_axis.tvalid && presynced_axis.tuser[0] && capturing;
    wire fb_we  = presynced_axis.tvalid && presynced_axis.tuser[1] && capturing;

    wire [BATCH_LEN_WIDTH:0] ref_fill = (ref_wr_ptr >= rd_ptr) ? (ref_wr_ptr - rd_ptr)
                                                                 : (ref_wr_ptr + BATCH_LEN_MAX - rd_ptr);
    wire [BATCH_LEN_WIDTH:0] fb_fill  = (fb_wr_ptr  >= rd_ptr) ? (fb_wr_ptr  - rd_ptr)
                                                                 : (fb_wr_ptr  + BATCH_LEN_MAX - rd_ptr);

    logic [BATCH_LEN_WIDTH-1:0] rd_next;
    assign rd_next = (rd_ptr == BATCH_LEN_MAX - 1) ? '0 : rd_ptr + 1;

    always_comb presynced_axis.tready = 1'b1;

    assign buffered_axis.tvalid = (ref_fill > 0) && (fb_fill > 0) && (fb_fill <= ref_fill);
    assign buffered_axis.tdata  = {fb_fifo[rd_ptr], ref_fifo[rd_ptr]};
    assign buffered_axis.tuser  = '0;
    assign buffered_axis.tlast  = buffered_axis.tvalid && !capturing &&
                                  (rd_next == ref_wr_ptr && rd_next == fb_wr_ptr);

    always_ff @(posedge clk) begin
        if (rst) begin
            capturing  <= 1'b0;
            ref_wr_ptr <= '0;
            fb_wr_ptr  <= '0;
            rd_ptr     <= '0;
        end else if (start && we) begin
            capturing  <= 1'b1;
            ref_wr_ptr <= '0;
            fb_wr_ptr  <= '0;
            rd_ptr     <= '0;
        end else begin
            if (capturing && presynced_axis.tvalid && presynced_axis.tlast) begin
                capturing <= 1'b0;
            end
            if (ref_we) begin
                ref_fifo[ref_wr_ptr] <= presynced_axis.tdata[DATA_WIDTH-1:0];
                ref_wr_ptr <= ref_wr_ptr + 1;
            end
            if (fb_we) begin
                fb_fifo[fb_wr_ptr] <= presynced_axis.tdata[DATA_WIDTH*2-1:DATA_WIDTH];
                fb_wr_ptr <= fb_wr_ptr + 1;
            end
            if (buffered_axis.tvalid && rd_en) begin
                rd_ptr <= rd_ptr + 1;
            end
        end
    end
endmodule // sync_buffer
