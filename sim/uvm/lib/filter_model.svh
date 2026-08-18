`ifndef FILTER_MODEL_SVH
`define FILTER_MODEL_SVH

// Bit-exact reference model for the filter pipeline (rtl/dpd/filter.sv).
// Mirrors the RTL arithmetic exactly: operand widths, arithmetic shifts,
// context-width wraparound, and the three saturating helpers.

function automatic signed [15:0] filter_sat16(input signed [31:0] v);
    localparam signed [15:0] MAXV = {1'b0, {15{1'b1}}};
    localparam signed [15:0] MINV = {1'b1, {15{1'b0}}};
    begin
        if (v > MAXV)      filter_sat16 = MAXV;
        else if (v < MINV) filter_sat16 = MINV;
        else               filter_sat16 = v[15:0];
    end
endfunction

// Mirrors sat_acc: input is the full 28-bit (weight*sample) product context.
function automatic signed [19:0] filter_sat20(input signed [27:0] v);
    localparam signed [19:0] MAXV = {1'b0, {19{1'b1}}};
    localparam signed [19:0] MINV = {1'b1, {19{1'b0}}};
    begin
        if (v > MAXV)      filter_sat20 = MAXV;
        else if (v < MINV) filter_sat20 = MINV;
        else               filter_sat20 = v[19:0];
    end
endfunction

function automatic signed [15:0] filter_sat_out(input signed [21:0] v);
    localparam signed [15:0] MAXV = {1'b0, {15{1'b1}}};
    localparam signed [15:0] MINV = {1'b1, {15{1'b0}}};
    begin
        if (v > MAXV)          filter_sat_out = MAXV;
        else if (v < MINV)     filter_sat_out = MINV;
        else                   filter_sat_out = v[15:0];
    end
endfunction

// Computes the filter output for one sample given the current sample
// (i0, q0), the previous sample (i1, q1), and the weights. Inputs are the
// packed {Q,I} 16-bit fields; outputs are the packed {Q,I} result.
function automatic void filter_ref(
    input  logic signed [15:0] i0,
    input  logic signed [15:0] q0,
    input  logic signed [15:0] i1,
    input  logic signed [15:0] q1,
    input  logic signed [11:0] wi [4],
    input  logic signed [11:0] wq [4],
    output logic signed [15:0] y_i,
    output logic signed [15:0] y_q
);
    longint m2_0, m2_1;
    longint m2xi_0, m2xq_0;
    longint m2xi_1, m2xq_1;
    longint t0_ii, t0_qi, t0_iq, t0_qj;
    longint t1_ii, t1_qi, t1_iq, t1_qj;
    longint t2_ii, t2_qi, t2_iq, t2_qj;
    longint t3_ii, t3_qi, t3_iq, t3_qj;
    longint sum;

    m2_0 = filter_sat16($signed(i0) * $signed(i0) >>> 12) + filter_sat16($signed(q0) * $signed(q0) >>> 12);
    m2_0 = $signed(m2_0[15:0]);
    m2_1 = filter_sat16($signed(i1) * $signed(i1) >>> 12) + filter_sat16($signed(q1) * $signed(q1) >>> 12);
    m2_1 = $signed(m2_1[15:0]);

    // Re-quantised |x|*mag2 and |q|*mag2 products (the RTL computes each path
    // separately before the weight multiply).
    m2xi_0 = filter_sat16($signed(i0) * $signed(m2_0[15:0]) >>> 12);
    m2xq_0 = filter_sat16($signed(q0) * $signed(m2_0[15:0]) >>> 12);
    m2xi_1 = filter_sat16($signed(i1) * $signed(m2_1[15:0]) >>> 12);
    m2xq_1 = filter_sat16($signed(q1) * $signed(m2_1[15:0]) >>> 12);

    // Weight products: each is computed directly in the RTL's 28-bit context
    // (sat_acc input [27:0]) and arithmetic-shifted by WEIGHT_FRAC, exactly
    // like `sat_acc(wi_s1[t] * oi >>> 10)`. Do NOT route the product through
    // a wider value and slice [26:0] -- that truncates the two's-complement
    // representation and flips the sign of products with bit 27 set.

    // Order 1, delay 0
    t0_ii = filter_sat20($signed(wi[0]) * $signed(i0) >>> 10);
    t0_qi = filter_sat20($signed(wq[0]) * $signed(q0) >>> 10);
    t0_iq = filter_sat20($signed(wi[0]) * $signed(q0) >>> 10);
    t0_qj = filter_sat20($signed(wq[0]) * $signed(i0) >>> 10);

    // Order 1, delay 1
    t1_ii = filter_sat20($signed(wi[1]) * $signed(i1) >>> 10);
    t1_qi = filter_sat20($signed(wq[1]) * $signed(q1) >>> 10);
    t1_iq = filter_sat20($signed(wi[1]) * $signed(q1) >>> 10);
    t1_qj = filter_sat20($signed(wq[1]) * $signed(i1) >>> 10);

    // Order 3, delay 0
    t2_ii = filter_sat20($signed(wi[2]) * $signed(m2xi_0[15:0]) >>> 10);
    t2_qi = filter_sat20($signed(wq[2]) * $signed(m2xq_0[15:0]) >>> 10);
    t2_iq = filter_sat20($signed(wi[2]) * $signed(m2xq_0[15:0]) >>> 10);
    t2_qj = filter_sat20($signed(wq[2]) * $signed(m2xi_0[15:0]) >>> 10);

    // Order 3, delay 1
    t3_ii = filter_sat20($signed(wi[3]) * $signed(m2xi_1[15:0]) >>> 10);
    t3_qi = filter_sat20($signed(wq[3]) * $signed(m2xq_1[15:0]) >>> 10);
    t3_iq = filter_sat20($signed(wi[3]) * $signed(m2xq_1[15:0]) >>> 10);
    t3_qj = filter_sat20($signed(wq[3]) * $signed(m2xi_1[15:0]) >>> 10);

    sum = $signed(t0_ii) - $signed(t0_qi)
        + $signed(t1_ii) - $signed(t1_qi)
        + $signed(t2_ii) - $signed(t2_qi)
        + $signed(t3_ii) - $signed(t3_qi);
    y_i = filter_sat_out($signed(sum[21:0]));

    sum = $signed(t0_iq) + $signed(t0_qj)
        + $signed(t1_iq) + $signed(t1_qj)
        + $signed(t2_iq) + $signed(t2_qj)
        + $signed(t3_iq) + $signed(t3_qj);
    y_q = filter_sat_out($signed(sum[21:0]));
endfunction

`endif // FILTER_MODEL_SVH
