#!/usr/bin/env bash
set -eu

R="$(printf '\033[0;31m')" G="$(printf '\033[0;32m')" N="$(printf '\033[0m')"
root="$(cd "$(dirname "$0")/.." && pwd)"

quiet=0
for arg in "$@"; do
    case "$arg" in
        -q|--quiet)   quiet=1 ;;
        -v|--verbose) quiet=0 ;;
        -h|--help)    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${R}Unknown option: $arg${N}" >&2; exit 2 ;;
    esac
done

run_suite() {
    label="$1"; shift
    echo "${G}### $label${N}"
    output="$("$@" 2>&1)" && rc=$? || rc=$?
    if [ "$quiet" = 1 ]; then
        echo "$output" | grep -E "PASS|FAIL|passed|failed|OK" || true
        if [ "$rc" != 0 ]; then
            echo "$output" | tail -20 | sed 's/^/    /'
        fi
    else
        printf '%s\n' "$output"
    fi
    return "$rc"
}

run_suite "1/3 Standalone testbenches" "$root/scripts/tb/all.sh"
run_suite "2/3 UVM environments" "$root/scripts/uvm/all.sh"
run_suite "3/3 Export (golden-reference) testbench" "$root/scripts/tb/integration.sh" save

echo "${G}All suites passed${N}"
