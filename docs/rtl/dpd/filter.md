# filter — Complex memory-polynomial predistorter

File: `rtl/dpd/filter.sv`

Fixed-point complex FIR filter implementing the memory-polynomial linearizer core of the DPD.

## Algorithm

Memory polynomial with 4 taps (K=2 orders, M=2 delays):

```
  y_I = Σ_t (wi_t·oI_t − wq_t·oQ_t)
  y_Q = Σ_t (wi_t·oQ_t + wq_t·oI_t)

  tap 0: o = x0       (order 1, delay 0)
  tap 1: o = x1       (order 1, delay 1)
  tap 2: o = x0·M0    (order 3, delay 0)
  tap 3: o = x1·M1    (order 3, delay 1)

  M = |x|² = I² + Q², re-quantised to DATA_WIDTH
```

`weights_i[k] = Re(a_k)`, `weights_q[k] = Im(b_k)`. Tap/order numbering matches the software
reference (`dpd_calibrate.m`).

## Number formats

| Quantity | Format |
|----------|--------|
| I/Q samples | Q4.12 signed, `DATA_WIDTH = 16` bits |
| Weights | Q2.10 signed, `WEIGHT_WIDTH = 12` bits |
| Accumulator | `ACC_WIDTH = DATA_WIDTH + 4` guard bits |
| Output | Q4.12 signed, saturated |

## Pipeline (AXI-Stream, 4 cycles of latency)

The input is `{Q, I}`-packed, `DATA_WIDTH` per component. Backpressure is a single `out_valid`
register: the input stalls (`enable` low) while a valid output beat is unaccepted.

- **Stage 0** — latch `{Q,I}`, shift the 2-deep delay line (`i_line/q_line`), snapshot weights
  and `bypass`/`tuser`/`tlast`.
- **Stage 1** — compute `M0 = I0² + Q0²` and `M1 = I1² + Q1²`, each term saturated to
  `DATA_WIDTH` after the Q4.12 right-shift.
- **Stage 2** — per tap, build the operand `o` (`x` for order-1 taps, `sat(x·M ≫ 12)` for
  order-3 taps) and compute the four weight products `t_ii`, `t_qi`, `t_iq`, `t_qq`, each
  saturated into the accumulator width after the Q2.10 right-shift.
- **Stage 3** — combine: `y_I = t_ii − t_qi` summed over taps, `y_Q = t_iq + t_qq` summed over
  taps; each result saturated back to `DATA_WIDTH`. In `bypass` mode the input sample is
  forwarded unmodified.

Output drives `tvalid/tdata{tuser,tlast}` on `output_axis`.

## Verification

- Standalone testbenches: `sim/testbenches/dpd/filter_tb.sv` (weighted/random/backpressure/
  saturation/weights-change/basic) and `sim/testbenches/top/top_tb.sv`. See
  [../sim/testbenches/README.md](../../sim/testbenches/README.md).
- UVM environment: `sim/uvm/filter/` — directed + backpressure + reset tests, a scoreboard
  with a bit-accurate software model, and a covergroup on taps, weights, bypass and handshake
  conditions. See [../sim/uvm/README.md](../../sim/uvm/README.md).
