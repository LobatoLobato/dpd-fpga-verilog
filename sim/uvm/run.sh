#!/usr/bin/env bash
#
# UVM run wrapper for the sim/uvm/* projects.
#
# Wraps the Vivado xsim UVM flow (xvlog/xelab/xsim via run.tcl) with
# -nolog -nojournal so no vivado.log / vivado.jou files are written to
# your working directory. Tool outputs go into <project>/work/sim.
# Run it from anywhere.
#
# Usage:
#   run.sh <project> [target] [gui|no-gui] [test]
#
#   project  name of any UVM directory under sim/uvm/ (must contain run.tcl)
#   target   all (default) | compile | elaborate | run | clean | help
#   gui      no-gui (default) | gui
#   test     UVM test class to run (overrides config.tcl UVM_TEST)
#
# Examples:
#   run.sh sampler            # full compile+elab+sim flow (default test)
#   run.sh sampler run sampler_suite   # simulate only, run the suite
#   run.sh sampler clean      # wipe <project>/work

set -euo pipefail

UVM_ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="${1:?usage: run.sh <project> [target] [gui|no-gui] [test]}"
PROJ_DIR="$UVM_ROOT/$PROJECT"

TARGET="${2:-all}"
GUI="${3:-no-gui}"
TEST="${4:-}"

if [ ! -f "$PROJ_DIR/run.tcl" ]; then
    echo "error: no UVM project '$PROJECT' at $PROJ_DIR (expected run.tcl)" >&2
    exit 1
fi

# Run from the project dir: vivado -nolog -nojournal leaves nothing in cwd,
# and run.tcl redirects every tool output into $PROJECT/work/sim.
# -mode batch runs the script then exits instead of dropping to a Vivado%
# shell when the simulation finishes.
cd "$PROJ_DIR"
if [ -n "$TEST" ]; then
    exec vivado -mode batch -nolog -nojournal -source run.tcl -tclargs "$TARGET" "$GUI" "$TEST"
else
    exec vivado -mode batch -nolog -nojournal -source run.tcl -tclargs "$TARGET" "$GUI"
fi
