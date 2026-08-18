#!/usr/bin/env bash
set -euo pipefail

R="$(printf '\033[0;31m')" G="$(printf '\033[0;32m')" N="$(printf '\033[0m')"
root="$(cd "$(dirname "$0")/../.." && pwd)"

passed=0
failed=0

run_env() {
    env="$1"; shift
    for test in "$@"; do
        echo "=== $env: $test ==="
        output="$(
            cd "$root/sim/uvm/$env"
            timeout 900 vivado -mode tcl -nolog -nojournal -source run.tcl -tclargs all no-gui "$test" </dev/null 2>&1
        )" && rc=$? || rc=$?

        errs="$(echo "$output" | grep -oE 'UVM_ERROR\s*:\s*[0-9]+' | tail -1 | grep -oE '[0-9]+' || echo 1)"
        fatals="$(echo "$output" | grep -oE 'UVM_FATAL\s*:\s*[0-9]+' | tail -1 | grep -oE '[0-9]+' || echo 1)"

        if [ "$rc" = 0 ] && [ "${errs:-1}" = 0 ] && [ "${fatals:-1}" = 0 ]; then
            echo "  ${G}PASS${N}"
            passed=$((passed + 1))
        else
            echo "  ${R}FAIL${N} (rc=$rc, UVM_ERROR=${errs:-?}, UVM_FATAL=${fatals:-?})"
            echo "$output" | grep -E 'UVM_ERROR|UVM_FATAL|mismatch|checked' | tail -5 | sed 's/^/    /'
            failed=$((failed + 1))
        fi
    done
}

run_env dpd dpd_test dpd_bypass_test

echo "=== ${G}$passed passed${N}, ${R}$failed failed${N} ==="
exit $failed
