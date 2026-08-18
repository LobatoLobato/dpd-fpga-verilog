#!/usr/bin/env bash
set -euo pipefail
R="$(printf '\033[0;31m')" G="$(printf '\033[0;32m')" N="$(printf '\033[0m')"
C="s/.*ERROR:.*/${R}&${N}/; s/.*PASS:.*/${G}&${N}/; s/.*OK.*/${G}&${N}/"
xvlog --nolog -sv -d TESTBENCH rtl/interfaces/taxi_axil_if.sv rtl/datapath/configctl.sv sim/testbenches/datapath/configctl_tb.sv 2>&1 | sed "$C"
xelab --nolog configctl_tb -s configctl_sim 2>&1 | sed "$C"
mode="${1:--runall}"
[ "$mode" = "--gui" ] && mode="-gui"
rc=0
timeout 180 xsim --nolog configctl_sim "$mode" -wdb xsim.dir/configctl_sim.wdb 2>&1 | sed "$C" || rc=$?
rm -f ./*.jou ./*.pb ./*.log 2>/dev/null
exit $rc
