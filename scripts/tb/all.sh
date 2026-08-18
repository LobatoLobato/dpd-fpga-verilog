#!/usr/bin/env bash
set -eu

R="$(printf '\033[0;31m')" G="$(printf '\033[0;32m')" N="$(printf '\033[0m')"
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

passed=0
failed=0

for script in scripts/tb/*.sh; do
    name="$(basename "$script" .sh)"
    [ "$name" = "all" ] && continue
    [ "$name" = "integration" ] && continue

    echo "=== $name ==="
    output="$("$script" 2>&1)" && rc=$? || rc=$?
    if [ "$rc" = 0 ] && echo "$output" | grep -q "Testbench Result: OK"; then
        echo "  ${G}PASS${N}"
        passed=$((passed + 1))
    elif [ "$rc" != 0 ]; then
        echo "  ${R}FAIL${N} (exit code $rc)"
        echo "$output" | tail -5 | sed 's/^/    /'
        failed=$((failed + 1))
    else
        echo "  ${R}FAIL${N} (result not OK)"
        echo "$output" | tail -5 | sed 's/^/    /'
        failed=$((failed + 1))
    fi
done

echo "=== ${G}$passed passed${N}, ${R}$failed failed${N} ==="
exit $failed
