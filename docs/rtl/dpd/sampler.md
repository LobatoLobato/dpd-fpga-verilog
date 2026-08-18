# DPD/Sampler (sampler)

File: `rtl/dpd/sampler.sv` — contains three modules: `sampler` (top), `presync` and
`sync_buffer`.

## What it does
Captures a batch of synchronized {ref, fb} sample pairs into an AXI-Stream FIFO.

## Number format
`DATA_WIDTH = 32` carries a packed `{Q[16], I[16]}` sample (Q4.12 signed per component, same
format as the `filter`). The internal `presynced_axis` bus is `DATA_WIDTH*2 = 64` bits wide and
packs `{fb, ref}` pairs.

## Trigger
`start` + `we` on the same cycle starts capture on the next cycle. Neither alone does anything.

## Presync
Forwards ref and fb samples as {fb, ref} on `presynced_axis`.  
`presynced_axis.tvalid` is always high — the `tuser` flags indicate which data is valid:
- `tuser[0]` (valid_ref): asserted from the cycle after start through `$batch_length` captures
- `tuser[1]` (valid_fb): same, but delayed by `$delay_length` cycles

Example with `$batch_length=3`, `$delay_length=4`:

| Cycle | start | tdata          | valid_fb | valid_ref |
|-------|-------|----------------|----------|-----------|
| 0     | 0     | {dfb0, dref0} | 0        | 0         |
| 1     | 1     | {dfb1, dref1} | 0        | 0         |
| 2     | 0     | {dfb2, dref2} | 0        | 1         |
| 3     | 0     | {dfb3, dref3} | 0        | 1         |
| 4     | 0     | {dfb4, dref4} | 0        | 1         |
| 5     | 0     | {dfb5, dref5} | 0        | 0         |
| 6     | 0     | {dfb6, dref6} | 1        | 0         |
| 7     | 0     | {dfb7, dref7} | 1        | 0         |
| 8     | 0     | {dfb8, dref8} | 1        | 0         |
| 9     | 0     | {dfb9, dref9} | 0        | 0         |

Result: aligned pairs are {dfb6, dref2}, {dfb7, dref3}, {dfb8, dref4}.

## Sync Buffer
Stores captured pairs in two FIFOs (ref, fb) keyed by write pointer.  
Pushing stops when presync asserts `tlast`.

`buffered_axis.tvalid` is high only when both FIFOs have data at the same index.  
`buffered_axis.tlast` is asserted on the last readable pair when `!capturing && (rd_ptr+1 == ref_wr_ptr && rd_ptr+1 == fb_wr_ptr)` — next read drains both FIFOs and capture is done.

Same sequence (`~` = fb invalid — not yet arrived for that index):

| Cycle | start | tdata          | valid_fb | valid_ref | buffered_data                                  |
|-------|-------|----------------|----------|-----------|------------------------------------------------|
| 0     | 0     | {dfb0, dref0} | 0        | 0         | []                                             |
| 1     | 1     | {dfb1, dref1} | 0        | 0         | []                                             |
| 2     | 0     | {dfb2, dref2} | 0        | 1         | [{~, dref2}]                                   |
| 3     | 0     | {dfb3, dref3} | 0        | 1         | [{~, dref2}, {~, dref3}]                       |
| 4     | 0     | {dfb4, dref4} | 0        | 1         | [{~, dref2}, {~, dref3}, {~, dref4}]           |
| 5     | 0     | {dfb5, dref5} | 0        | 0         | [{~, dref2}, {~, dref3}, {~, dref4}]           |
| 6     | 0     | {dfb6, dref6} | 1        | 0         | [{dfb6, dref2}, {~, dref3}, {~, dref4}]        |
| 7     | 0     | {dfb7, dref7} | 1        | 0         | [{dfb6, dref2}, {dfb7, dref3}, {~, dref4}]     |
| 8     | 0     | {dfb8, dref8} | 1        | 0         | [{dfb6, dref2}, {dfb7, dref3}, {dfb8, dref4}]  |
| 9     | 0     | {dfb9, dref9} | 0        | 0         | [{dfb6, dref2}, {dfb7, dref3}, {dfb8, dref4}]  |

- Cycles 0–1, 9: no data to pop.
- Cycles 2–5: ref-only data in FIFO — pairs incomplete, cannot pop.
- Cycles 6–8: both FIFOs have matching indices — can pop. By cycle 8 all 3 pairs are available.

## Verification

- Standalone testbenches: `sim/testbenches/dpd/sampler/sampler_tb.sv` (end-to-end pair capture
  with an internal reference model), `presync_tb.sv` (presync alignment/timing) and
  `sync_buffer_tb.sv` (FIFO fill/tlast behaviour). See
  [../../sim/testbenches/README.md](../../sim/testbenches/README.md).
- UVM environment: `sim/uvm/sampler/` — BFM/agent/sequencer, a scoreboard that predicts
  expected `{ref, fb}` pairs and an end-of-test pair check, plus a functional covergroup.
  See [../../sim/uvm/README.md](../../sim/uvm/README.md).
