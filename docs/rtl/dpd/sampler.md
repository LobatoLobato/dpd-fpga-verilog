# DPD/Sampler (sampler)

## What it does
Captures a batch of synchronized {ref_sample, fb_sample} pairs into an AXI-Stream FIFO when triggered

## How it works
### Synchronization
Uses a counter to compensate the delay of the feedback datapath by waiting until that counter reaches the configured delay length before enabling the feedback axis fifo.

### Batching
Uses a counter to keep capturing samples until it reaches the configured batch length.