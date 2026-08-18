#!/usr/bin/env bash
set -euo pipefail
R="$(printf '\033[0;31m')" G="$(printf '\033[0;32m')" N="$(printf '\033[0m')"
C="s/.*ERROR:.*/${R}&${N}/; s/.*PASS:.*/${G}&${N}/; s/.*OK.*/${G}&${N}/"
xvlog --nolog -sv rtl/dpd/tddctl.sv sim/testbenches/dpd/tddctl_tb.sv 2>&1 | sed "$C"
xelab --nolog tddctl_tb -s tddctl_sim 2>&1 | sed "$C"
mode="${1:--runall}"
[ "$mode" = "--gui" ] && mode="-gui"
rc=0
timeout 180 xsim --nolog tddctl_sim "$mode" -wdb xsim.dir/tddctl_sim.wdb 2>&1 | sed "$C" || rc=$?
rm -f ./*.jou ./*.pb ./*.log 2>/dev/null
exit $rc
