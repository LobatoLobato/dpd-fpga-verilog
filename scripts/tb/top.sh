#!/usr/bin/env bash
set -euo pipefail
R="$(printf '\033[0;31m')" G="$(printf '\033[0;32m')" N="$(printf '\033[0m')"
C="s/.*ERROR:.*/${R}&${N}/; s/.*PASS:.*/${G}&${N}/; s/.*OK.*/${G}&${N}/"

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

delays="${FB_DELAY_VALUES:-0 4 8 23}"

xvlog --nolog -sv -i sim/uvm/lib \
    rtl/interfaces/taxi_axis_if.sv \
    rtl/interfaces/taxi_axil_if.sv \
    rtl/datapath/configctl.sv \
    rtl/dpd/tddctl.sv \
    rtl/dpd/sampler.sv \
    rtl/dpd/filter.sv \
    rtl/top/top.sv \
    sim/testbenches/top/top_tb.sv 2>&1 | sed "$C"

failed=0
for d in $delays; do
    echo "=== FB_DELAY_CYCLES=$d ==="
    xelab --nolog top_tb -s top_sim_$d --generic_top "FB_DELAY_CYCLES=$d" 2>&1 | sed "$C" || exit 1
    output="$(timeout 180 xsim --nolog top_sim_$d -runall 2>&1)" && rc=$? || rc=$?
    echo "$output" | sed "$C"
    if [ "$rc" = 0 ] && echo "$output" | grep -q "Testbench Result: OK"; then
        echo "  ${G}FB_DELAY=$d OK${N}"
    else
        echo "  ${R}FB_DELAY=$d FAILED${N}"
        failed=1
    fi
done

rm -f ./*.jou ./*.pb ./*.log
exit $failed
