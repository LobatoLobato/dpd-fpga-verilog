#!/usr/bin/env bash
# Usage: ./scripts/tb/integration.sh [none|show|save|both] [low_dist|high_dist]
#   Plot mode (default none, so the run_all.sh regression stays headless).
#   PA distortion mode (default high_dist), forwarded to dpd_calibrate.m.
set -euo pipefail
R="$(printf '\033[0;31m')" G="$(printf '\033[0;32m')" N="$(printf '\033[0m')"
C="s/.*ERROR:.*/${R}&${N}/; s/.*PASS:.*/${G}&${N}/; s/.*OK.*/${G}&${N}/"

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

mode="${1:-none}"
case "$mode" in
    none|show|save|both) ;;
    *) echo "${R}Unknown plot mode: $mode (use none|show|save|both)${N}" >&2; exit 2 ;;
esac

pa_mode="${2:-high_dist}"
case "$pa_mode" in
    low_dist|high_dist) ;;
    *) echo "${R}Unknown PA distortion mode: $pa_mode (use low_dist|high_dist)${N}" >&2; exit 2 ;;
esac

rm -rf xsim.dir results/reports
mkdir -p results/reports

echo "== 1/4 generating stimulus and weights (octave, $pa_mode) =="
octave --no-gui software/dpd_calibrate.m "$mode" "$pa_mode" 2>&1 | sed "$C" || exit 1

echo "== 2/4 compiling export testbench =="
xvlog --nolog -sv \
    rtl/interfaces/taxi_axis_if.sv \
    rtl/interfaces/taxi_axil_if.sv \
    rtl/datapath/configctl.sv \
    rtl/dpd/tddctl.sv \
    rtl/dpd/sampler.sv \
    rtl/dpd/filter.sv \
    rtl/top/top.sv \
    sim/testbenches/top/top_integration_tb.sv 2>&1 | sed "$C"

xelab --nolog top_integration_tb -s integration_sim 2>&1 | sed "$C"

echo "== 3/4 simulating =="
output="$(timeout 300 xsim --nolog integration_sim -runall \
    -testplusarg stimulus=results/reports/ref_stimulus.txt \
    -testplusarg weights_i=results/reports/weights_i.txt \
    -testplusarg weights_q=results/reports/weights_q.txt \
    -testplusarg output=results/reports/cap_export.csv 2>&1)" && rc=$? || rc=$?
echo "$output" | sed "$C"

sent=$(echo "$output" | awk '/Samples sent/ {gsub(/[^0-9]/,"",$NF); print $NF}')
captured=$(echo "$output" | awk '/Pairs captured/ {gsub(/[^0-9]/,"",$NF); print $NF}')
mismatches=$(echo "$output" | awk '/Internal mismatches/ {gsub(/[^0-9]/,"",$NF); print $NF}')

echo "== 4/4 scoring capture (octave, $pa_mode) =="
score_rc=0
octave --no-gui software/dpd_calibrate.m "$mode" "$pa_mode" 2>&1 | sed "$C" || score_rc=1

rm -f ./*.jou ./*.pb ./*.log

if [ "$rc" = 0 ] && [ -n "$sent" ] && [ "$sent" = "$captured" ] && [ "$mismatches" = 0 ] && [ "$score_rc" = 0 ]; then
    echo "  ${G}Export testbench OK (${sent} pairs, ${mismatches} mismatches)${N}"
    exit 0
fi
echo "  ${R}Export testbench FAILED (rc=$rc, sent=${sent:-?}, captured=${captured:-?}, mismatches=${mismatches:-?}, octave=$score_rc)${N}"
exit 1
