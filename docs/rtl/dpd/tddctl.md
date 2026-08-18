# DPD/TDD Controller (tddctl)

File: `rtl/dpd/tddctl.sv`

## What it does

When enabled, monitors the external TDD transmit signal (`tdd_tx`) and derives two things for
the rest of the datapath:

- **`we`** — a write-enable for the sample window: keeps the sampler window open whenever the
  TDD link is in a state where samples should be captured.
- **`start`** — a one-cycle capture trigger. A trigger requested while the link is idle is
  deferred until the next transmit window opens (trigger delegation).

Ports: `clk`, `rst`, `tdd_en` (config), `tdd_tx` (external transmit pulse), `trigger` (pulse
from configctl), outputs `we` and `start`.

## How it works

### Write enable

Combinational:

```
we = (tdd_en & tdd_tx) | ~tdd_en
```

| tdd_en | tdd_tx | we  |
| :---:  | :---:  | :-: |
|   0    |   0    |  1  |
|   0    |   1    |  1  |
|   1    |   0    |  0  |
|   1    |   1    |  1  |

When TDD is disabled the window is always open; when enabled it is open only during a transmit
pulse.

### Trigger delegation

`trigger` is detected on its rising edge (`trigger_posedge`). The 2-state FSM `Idle → WaitTdd`
implements:

- Trigger while TDD **disabled** (`tdd_en=0`): `start` is pulsed immediately.
- Trigger while TDD **enabled and transmitting** (`tdd_tx=1`): `start` is pulsed immediately.
- Trigger while TDD **enabled and idle** (`tdd_tx=0`): the controller moves to `WaitTdd`; the
  trigger is held back and `start` is pulsed only when `tdd_tx` rises (or TDD becomes disabled).

`start` is a single-cycle pulse (the FSM returns to `Idle` and drives it low again).

Truth table (actuation only after a trigger is seen):

| trigger seen | tdd_en | tdd_tx | start (immediate) |
|   :---:      | :---:  | :---:  |     :---:         |
|     0        |   *    |   *    |       0           |
|     1        |   0    |   0    |       1           |
|     1        |   0    |   1    |       1           |
|     1        |   1    |   0    |       0 (deferred) |
|     1        |   1    |   1    |       1           |

## Consumption in `top`

`top` wires `tdd_sig` (the top-level port) to `tdd_tx`, `configctl.start` to `trigger`,
`configctl.tdd_en` to `tdd_en`, and forwards `we`/`start` to `sampler`. See
[top.md](../top/top.md).

## Verification

- Standalone testbench: `sim/testbenches/dpd/tddctl_tb.sv` — covers the we truth table and
  every trigger-delegation path. See [../sim/testbenches/README.md](../../sim/testbenches/README.md).
- UVM environment: `sim/uvm/tddctl/` — BFM-driven, with a scoreboard on `we`/`start` and a
  covergroup over the enable/transmit/trigger space. See [../sim/uvm/README.md](../../sim/uvm/README.md).
