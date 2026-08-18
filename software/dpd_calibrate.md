# dpd_calibrate.m

Simulates and validates a Memory Polynomial (MP) digital predistorter (DPD) for a
nonlinear power amplifier (PA), then exports the quantized coefficients and I/Q
stimulus that feed the RTL implementation (`rtl/dpd/filter.sv`).

## Model

The MP model the DPD tries to invert is

```
y[n] = sum_{k=1..K} sum_{m=0..M-1} c_km * x[n-m] * |x[n-m]|^(2k-2)
```

with `K = 2` orders and `M = 2` memory taps, i.e. 4 complex taps:

| tap | order | delay |
|-----|-------|-------|
| 0   | 1     | 0     |
| 1   | 1     | 1     |
| 2   | 3     | 0     |
| 3   | 3     | 1     |

## Flow

1. **Input signal** — multi-tone (4 tones) with random phase noise, peak-normalized.
2. **PA model** — the input is passed through an MP built from fixed "true"
   coefficients `pa.c`, plus small additive noise (`sigma = 0.001`).
3. **Coefficient estimation** — the predistorter coefficients `c` are found by
   complex least squares `c = Phi(y_no_dpd) \ x`, using only the valid samples
   (skips the first `M-1` while the delay line settles).
4. **Predistortion** — `x_pd = Phi(x) * c` is pushed through the same PA model.
   With/without-DPD outputs are compared against the ideal linear output
   `G*x` (NMSE in dB, AM-AM curve, instantaneous error, output spectrum).
5. **Quantization** — `c` is quantized to signed Q2.10 (12-bit): `weights_i`
   = real part, `weights_q` = imaginary part.
6. **RTL export** — writes `ref_stimulus.txt` (20000 I/Q pairs, Q4.12 16-bit),
   `weights_i.txt`, `weights_q.txt` into `../results/reports`.
7. **Hardware validation (optional)** — if `../results/reports/cap_export.csv`
   (columns `ref_i, ref_q, fb_i, fb_q`) exists from the RTL simulation, it is
   imported to verify reference round-trip integrity and recompute the
   linearization metrics/plots for the hardware-generated predistorted signal.

## Configuration

- Plot mode controls plotting: `'both'` (show windows + save PNGs, default),
  `'save'` (PNGs only), `'show'` (windows only), or `'none'`.
  Set it in the file (`plot_mode` variable) or pass it as the first CLI arg:

  ```
  octave dpd_calibrate.m save
  ```
- No `cap_export.csv` present: the script only computes and exports
  stimulus + weights — no plots or images.

## Key points

- Tap ordering and the `(k-1)*M + m` index map match `filter.sv` exactly.
- Coefficients are complex; the I path uses `weights_i`, the Q path `weights_q`.
- Fixed-point formats: samples `Q4.12` (`DATA_WIDTH=16`), weights `Q2.10`
  (12-bit signed) — matching `filter.sv`.
- Deterministic run via `rng(42)`.
- Two-phase workflow: run the script to export stimulus + weights, run the RTL
  simulation to produce `cap_export.csv`, rerun the script for hardware validation.
- Run from the `software/` directory (file paths are relative to it).
- Written for Octave: script-local helper functions are defined before use.
