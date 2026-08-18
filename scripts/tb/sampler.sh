#!/usr/bin/env bash
set -euo pipefail
R="$(printf '\033[0;31m')" G="$(printf '\033[0;32m')" N="$(printf '\033[0m')"
C="s/.*ERROR:.*/${R}&${N}/; s/.*PASS:.*/${G}&${N}/; s/.*OK.*/${G}&${N}/"
xvlog --nolog -sv -d TESTBENCH rtl/interfaces/taxi_axis_if.sv rtl/dpd/sampler.sv sim/testbenches/dpd/sampler/sampler_tb.sv 2>&1 | sed "$C"
xelab --nolog sampler_tb -s sampler_sim 2>&1 | sed "$C"
mode="${1:--runall}"
[ "$mode" = "--gui" ] && mode="-gui"
rc=0
timeout 180 xsim --nolog sampler_sim "$mode" -wdb xsim.dir/sampler_sim.wdb 2>&1 | sed "$C" || rc=$?
rm -f ./*.jou ./*.pb ./*.log 2>/dev/null
exit $rc
