#!/usr/bin/env bash
set -uo pipefail
dir="$(dirname "$0")/../scripts"
# Run every check; fail the gate if any fails (don't stop at the first).
rc=0
bash "$dir/exec_bit_check.sh" || rc=1
bash "$dir/piv_check.sh" || rc=1
bash "$dir/launch_guard_check.sh" || rc=1
exit "$rc"
