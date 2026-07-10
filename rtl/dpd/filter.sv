`resetall
`timescale 1ns / 1ps
`default_nettype none

// DPD/Filter (filter)
//
// Real-coefficient Memory Polynomial predistorter.
//
// Implements the same model used to generate `weights` offline
// (see memory_polynomial.m): non-linearity orders K=2 (odd orders 1
// and 3 only) and memory depth M=2, i.e. 4 taps:
//
//   y[n] = w0*x[n]   + w1*x[n-1]
//        + w2*x[n]^3 + w3*x[n-1]^3
//
// weights[tap] <-> (order, delay) mapping, matching
// configctl_defs::REG_WEIGHT_0..3 and coeffs_real(idx), idx=(k-1)*M+m:
//   weights[0] : order 1, delay 0
//   weights[1] : order 1, delay 1
//   weights[2] : order 3, delay 0
//   weights[3] : order 3, delay 1
//
// The general memory-polynomial basis function is x[n-m]*|x[n-m]|^(order-1).
// tdata carries a real-valued (not complex I/Q) fixed-point sample, and for
// every order used here (order-1 is even) |x|^(order-1) = x^(order-1), so
// the basis functions reduce to plain odd integer powers of x[n-m] and no
// magnitude/CORDIC hardware is required.
//
// Fixed-point formats:
//   tdata      : signed Q1.(DATA_WIDTH-1)  (matches ADC/DAC full-scale +-1)
//   weights[i] : signed Q1.11, 12 bits     (matches quantize_fixed_point.m,
//                                            WL=12, FL=11)
//
// When `bypass` is asserted the sample is forwarded unmodified (used to
// capture the PA's un-linearized response, y_no_dpd in memory_polynomial.m).
//
// Fixed 4-stage pipeline (capture -> square -> cube+weight -> sum+output).
// Backpressure is handled with a single global stall: the whole pipeline
// (and input_axis.tready) freezes whenever a result is waiting to be
// accepted downstream, so no in-flight sample is ever dropped or duplicated.
module filter #(
    parameter integer DATA_WIDTH = 14
) (
    input wire clk, input wire rst,
    input wire [11:0] weights [4],
    input wire bypass,
    axis_if.slave  input_axis,
    axis_if.master output_axis
);
    localparam integer SAMPLE_FRAC  = DATA_WIDTH - 1; // Q1.(DATA_WIDTH-1)
    localparam integer WEIGHT_WIDTH = 12;
    localparam integer WEIGHT_FRAC  = 11;              // Q1.11
    localparam integer GUARD_BITS   = 2;                // headroom for 4-term sum
    localparam integer ACC_WIDTH    = DATA_WIDTH + GUARD_BITS;

    // ------------------------------------------------------------------
    // Saturating helpers (widths are elaboration-time constants derived
    // from DATA_WIDTH, so these stay correct for any DATA_WIDTH value).
    // ------------------------------------------------------------------
    function automatic signed [DATA_WIDTH-1:0] sat_sample(input signed [2*DATA_WIDTH-1:0] v);
        localparam signed [DATA_WIDTH-1:0] MAXV = {1'b0, {(DATA_WIDTH-1){1'b1}}};
        localparam signed [DATA_WIDTH-1:0] MINV = {1'b1, {(DATA_WIDTH-1){1'b0}}};
        begin
            if (v > MAXV)      sat_sample = MAXV;
            else if (v < MINV) sat_sample = MINV;
            else               sat_sample = v[DATA_WIDTH-1:0];
        end
    endfunction

    function automatic signed [ACC_WIDTH-1:0] sat_acc(input signed [WEIGHT_WIDTH+DATA_WIDTH-1:0] v);
        localparam signed [ACC_WIDTH-1:0] MAXV = {1'b0, {(ACC_WIDTH-1){1'b1}}};
        localparam signed [ACC_WIDTH-1:0] MINV = {1'b1, {(ACC_WIDTH-1){1'b0}}};
        begin
            if (v > MAXV)      sat_acc = MAXV;
            else if (v < MINV) sat_acc = MINV;
            else               sat_acc = v[ACC_WIDTH-1:0];
        end
    endfunction

    function automatic signed [DATA_WIDTH-1:0] sat_out(input signed [ACC_WIDTH+1:0] v);
        localparam signed [DATA_WIDTH-1:0] MAXV = {1'b0, {(DATA_WIDTH-1){1'b1}}};
        localparam signed [DATA_WIDTH-1:0] MINV = {1'b1, {(DATA_WIDTH-1){1'b0}}};
        begin
            if (v > MAXV)      sat_out = MAXV;
            else if (v < MINV) sat_out = MINV;
            else               sat_out = v[DATA_WIDTH-1:0];
        end
    endfunction

    // ------------------------------------------------------------------
    // Flow control: freeze the whole pipeline whenever the output stage
    // holds a valid result that hasn't been accepted yet.
    // ------------------------------------------------------------------
    reg samp3_valid;
    wire enable = !(samp3_valid && !output_axis.tready);
    assign input_axis.tready = enable;

    // ------------------------------------------------------------------
    // Stage 0: capture new sample, shift the M=2 memory line, latch
    // weights/bypass/control so a mid-stream coefficient update never
    // corrupts a sample already in flight.
    // ------------------------------------------------------------------
    reg signed [DATA_WIDTH-1:0] x_line [0:1]; // x_line[0]=x[n], x_line[1]=x[n-1]
    reg samp0_valid;
    reg [3:0] samp0_tuser;
    reg samp0_tlast;
    reg samp0_bypass;
    reg signed [WEIGHT_WIDTH-1:0] w0_r, w1_r, w2_r, w3_r;

    always @(posedge clk) begin
        if (rst) begin
            x_line[0]  <= '0;
            x_line[1]  <= '0;
            samp0_valid <= 1'b0;
            samp0_tuser <= '0;
            samp0_tlast <= 1'b0;
            samp0_bypass <= 1'b0;
            {w0_r, w1_r, w2_r, w3_r} <= '0;
        end else if (enable) begin
            samp0_valid <= input_axis.tvalid;
            if (input_axis.tvalid) begin
                x_line[1]     <= x_line[0];
                x_line[0]     <= $signed(input_axis.tdata);
                samp0_tuser   <= input_axis.tuser;
                samp0_tlast   <= input_axis.tlast;
                samp0_bypass  <= bypass;
                w0_r <= $signed(weights[0]);
                w1_r <= $signed(weights[1]);
                w2_r <= $signed(weights[2]);
                w3_r <= $signed(weights[3]);
            end
        end
    end

    // ------------------------------------------------------------------
    // Stage 1: x0^2, x1^2 (needed for the order-3 basis functions)
    // ------------------------------------------------------------------
    reg signed [DATA_WIDTH-1:0] x0_s1, x1_s1;
    reg signed [DATA_WIDTH-1:0] x0_sq_s1, x1_sq_s1;
    reg samp1_valid, samp1_tlast, samp1_bypass;
    reg [3:0] samp1_tuser;
    reg signed [WEIGHT_WIDTH-1:0] w0_s1, w1_s1, w2_s1, w3_s1;

    always @(posedge clk) begin
        if (rst) begin
            samp1_valid <= 1'b0;
        end else if (enable) begin
            samp1_valid  <= samp0_valid;
            samp1_tuser  <= samp0_tuser;
            samp1_tlast  <= samp0_tlast;
            samp1_bypass <= samp0_bypass;
            x0_s1 <= x_line[0];
            x1_s1 <= x_line[1];
            x0_sq_s1 <= sat_sample($signed(x_line[0]) * $signed(x_line[0]) >>> SAMPLE_FRAC);
            x1_sq_s1 <= sat_sample($signed(x_line[1]) * $signed(x_line[1]) >>> SAMPLE_FRAC);
            {w0_s1, w1_s1, w2_s1, w3_s1} <= {w0_r, w1_r, w2_r, w3_r};
        end
    end

    // ------------------------------------------------------------------
    // Stage 2: x0^3, x1^3, and the 4 weighted terms
    // ------------------------------------------------------------------
    reg signed [DATA_WIDTH-1:0] x0_s2;
    reg signed [ACC_WIDTH-1:0] t0_s2, t1_s2, t2_s2, t3_s2;
    reg samp2_valid, samp2_tlast, samp2_bypass;
    reg [3:0] samp2_tuser;

    always @(posedge clk) begin
        if (rst) begin
            samp2_valid <= 1'b0;
        end else if (enable) begin
            samp2_valid  <= samp1_valid;
            samp2_tuser  <= samp1_tuser;
            samp2_tlast  <= samp1_tlast;
            samp2_bypass <= samp1_bypass;
            x0_s2 <= x0_s1;

            t0_s2 <= sat_acc(w0_s1 * x0_s1 >>> WEIGHT_FRAC);
            t1_s2 <= sat_acc(w1_s1 * x1_s1 >>> WEIGHT_FRAC);
            t2_s2 <= sat_acc(w2_s1 * sat_sample(x0_sq_s1 * x0_s1 >>> SAMPLE_FRAC) >>> WEIGHT_FRAC);
            t3_s2 <= sat_acc(w3_s1 * sat_sample(x1_sq_s1 * x1_s1 >>> SAMPLE_FRAC) >>> WEIGHT_FRAC);
        end
    end

    // ------------------------------------------------------------------
    // Stage 3: accumulate, saturate, select bypass, drive the output
    // ------------------------------------------------------------------
    reg [3:0] samp3_tuser;
    reg samp3_tlast;
    reg signed [DATA_WIDTH-1:0] samp3_tdata;

    always @(posedge clk) begin
        if (rst) begin
            samp3_valid <= 1'b0;
        end else if (enable) begin
            samp3_valid <= samp2_valid;
            samp3_tuser <= samp2_tuser;
            samp3_tlast <= samp2_tlast;
            samp3_tdata <= samp2_bypass
                ? x0_s2
                : sat_out($signed(t0_s2) + $signed(t1_s2) + $signed(t2_s2) + $signed(t3_s2));
        end
    end

    assign output_axis.tvalid = samp3_valid;
    assign output_axis.tdata  = samp3_tdata;
    assign output_axis.tuser  = samp3_tuser;
    assign output_axis.tlast  = samp3_tlast;
endmodule
