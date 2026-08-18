`resetall
`timescale 1ns / 1ps
`default_nettype none

// Complex memory-polynomial predistorter (K=2, M=2, 4 taps):
//
//   y_I = sum_t (wi_t * oI_t - wq_t * oQ_t)
//   y_Q = sum_t (wi_t * oQ_t + wq_t * oI_t)
//
//   tap 0: o = x0      (order 1, delay 0)
//   tap 1: o = x1      (order 1, delay 1)
//   tap 2: o = x0 * M0 (order 3, delay 0)
//   tap 3: o = x1 * M1 (order 3, delay 1)
//   M = |x|^2, re-quantised to DATA_WIDTH.
module filter #(
    parameter integer DATA_WIDTH = 16
) (
    input wire clk, input wire rst,
    input wire [11:0] weights_i [4],
    input wire [11:0] weights_q [4],
    input wire bypass,
    taxi_axis_if.snk input_axis,
    taxi_axis_if.src output_axis
);
    localparam integer SAMPLE_FRAC  = 12;
    localparam integer WEIGHT_WIDTH = 12;
    localparam integer WEIGHT_FRAC  = 10;
    localparam integer GUARD_BITS   = 4;
    localparam integer ACC_WIDTH    = DATA_WIDTH + GUARD_BITS;

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

    function automatic signed [DATA_WIDTH-1:0] tap_op(
        input int t,
        input signed [DATA_WIDTH-1:0] x0, x1, m0, m1
    );
        logic signed [DATA_WIDTH-1:0] x, m;
        begin
            x = (t[0] == 0) ? x0 : x1;
            m = (t[0] == 0) ? m0 : m1;
            tap_op = (t < 2) ? x : sat_sample(x * m >>> SAMPLE_FRAC);
        end
    endfunction

    reg out_valid;
    wire enable = !(out_valid && !output_axis.tready);
    assign input_axis.tready = enable;

    // Stage 0: latch {Q, I}, shift delay line, latch weights
    reg signed [DATA_WIDTH-1:0] i_line [0:1], q_line [0:1];
    reg signed [WEIGHT_WIDTH-1:0] wi_r [4], wq_r [4];
    reg s0_valid;
    reg [3:0] s0_tuser;
    reg s0_tlast;
    reg s0_bypass;

    always @(posedge clk) begin
        if (rst) begin
            {i_line[0], i_line[1], q_line[0], q_line[1]} <= '0;
            s0_valid  <= 1'b0;
            s0_tuser  <= '0;
            s0_tlast  <= 1'b0;
            s0_bypass <= 1'b0;
            foreach (wi_r[k]) wi_r[k] <= '0;
            foreach (wq_r[k]) wq_r[k] <= '0;
        end else if (enable) begin
            s0_valid <= input_axis.tvalid;
            if (input_axis.tvalid) begin
                {i_line[1], q_line[1]} <= {i_line[0], q_line[0]};
                i_line[0] <= $signed(input_axis.tdata[DATA_WIDTH-1:0]);
                q_line[0] <= $signed(input_axis.tdata[DATA_WIDTH*2-1:DATA_WIDTH]);
                s0_tuser  <= input_axis.tuser;
                s0_tlast  <= input_axis.tlast;
                s0_bypass <= bypass;
                for (int k = 0; k < 4; k++) begin
                    wi_r[k] <= $signed(weights_i[k]);
                    wq_r[k] <= $signed(weights_q[k]);
                end
            end
        end
    end

    // Stage 1: M = I^2 + Q^2, re-quantised to DATA_WIDTH
    reg signed [DATA_WIDTH-1:0] i0_s1, q0_s1, i1_s1, q1_s1;
    reg signed [DATA_WIDTH-1:0] m2_0_s1, m2_1_s1;
    reg signed [WEIGHT_WIDTH-1:0] wi_s1 [4], wq_s1 [4];
    reg s1_valid, s1_tlast, s1_bypass;
    reg [3:0] s1_tuser;

    always @(posedge clk) begin
        if (rst) begin
            s1_valid <= 1'b0;
        end else if (enable) begin
            s1_valid  <= s0_valid;
            s1_tuser  <= s0_tuser;
            s1_tlast  <= s0_tlast;
            s1_bypass <= s0_bypass;
            i0_s1 <= i_line[0]; q0_s1 <= q_line[0];
            i1_s1 <= i_line[1]; q1_s1 <= q_line[1];
            m2_0_s1 <= sat_sample($signed(i_line[0]) * $signed(i_line[0]) >>> SAMPLE_FRAC)
                     + sat_sample($signed(q_line[0]) * $signed(q_line[0]) >>> SAMPLE_FRAC);
            m2_1_s1 <= sat_sample($signed(i_line[1]) * $signed(i_line[1]) >>> SAMPLE_FRAC)
                     + sat_sample($signed(q_line[1]) * $signed(q_line[1]) >>> SAMPLE_FRAC);
            wi_s1 <= wi_r;
            wq_s1 <= wq_r;
        end
    end

    // Stage 2: weight products per tap
    reg signed [ACC_WIDTH-1:0] t_ii [4], t_qi [4], t_iq [4], t_qq [4];
    reg signed [DATA_WIDTH-1:0] i0_s2, q0_s2;
    reg s2_valid, s2_tlast, s2_bypass;
    reg [3:0] s2_tuser;

    always @(posedge clk) begin
        if (rst) begin
            s2_valid <= 1'b0;
        end else if (enable) begin
            s2_valid  <= s1_valid;
            s2_tuser  <= s1_tuser;
            s2_tlast  <= s1_tlast;
            s2_bypass <= s1_bypass;
            i0_s2 <= i0_s1; q0_s2 <= q0_s1;

            for (int t = 0; t < 4; t++) begin
                automatic logic signed [DATA_WIDTH-1:0] oi, oq;
                oi = tap_op(t, i0_s1, i1_s1, m2_0_s1, m2_1_s1);
                oq = tap_op(t, q0_s1, q1_s1, m2_0_s1, m2_1_s1);
                t_ii[t] <= sat_acc(wi_s1[t] * oi >>> WEIGHT_FRAC);
                t_qi[t] <= sat_acc(wq_s1[t] * oq >>> WEIGHT_FRAC);
                t_iq[t] <= sat_acc(wi_s1[t] * oq >>> WEIGHT_FRAC);
                t_qq[t] <= sat_acc(wq_s1[t] * oi >>> WEIGHT_FRAC);
            end
        end
    end

    // Stage 3: sum I/Q paths, saturate, bypass, drive output
    reg [3:0] s3_tuser;
    reg s3_tlast;
    reg signed [DATA_WIDTH-1:0] s3_tdata_i, s3_tdata_q;

    always @(posedge clk) begin
        if (rst) begin
            out_valid <= 1'b0;
        end else if (enable) begin
            out_valid <= s2_valid;
            s3_tuser  <= s2_tuser;
            s3_tlast  <= s2_tlast;
            s3_tdata_i <= s2_bypass
                ? i0_s2
                : sat_out($signed(t_ii[0]) - $signed(t_qi[0])
                        + $signed(t_ii[1]) - $signed(t_qi[1])
                        + $signed(t_ii[2]) - $signed(t_qi[2])
                        + $signed(t_ii[3]) - $signed(t_qi[3]));
            s3_tdata_q <= s2_bypass
                ? q0_s2
                : sat_out($signed(t_iq[0]) + $signed(t_qq[0])
                        + $signed(t_iq[1]) + $signed(t_qq[1])
                        + $signed(t_iq[2]) + $signed(t_qq[2])
                        + $signed(t_iq[3]) + $signed(t_qq[3]));
        end
    end

    assign output_axis.tvalid = out_valid;
    assign output_axis.tdata  = {s3_tdata_q, s3_tdata_i};
    assign output_axis.tuser  = s3_tuser;
    assign output_axis.tlast  = s3_tlast;
endmodule
