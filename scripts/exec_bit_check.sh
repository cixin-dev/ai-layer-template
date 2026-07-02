#!/usr/bin/env bash
# exec_bit_check.sh — assert every tracked *.sh is committed executable.
#
# A shell script committed non-executable (git mode 100644) rc-126's the instant
# anything execs it by path — no shell wrapper, no interpreter prefix, just
# "Permission denied". night_shift_run.sh shipped 100644 and died exactly this
# way at Night Shift launch, exec'd directly at night_shift_loop.sh:110
# ("$RUN" "$n"). Nothing caught it because the break is silent until run.
#
# We read git's INDEX mode, not the working-tree bit: core.fileMode is false on
# the NFS checkout, so the on-disk +x is unreliable and untracked — the committed
# mode is the only truth. Fix a flagged file with:
#   git update-index --chmod=+x <file>
set -euo pipefail

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "[exec-bit-check] not a git repo; skipping" >&2
  exit 0
fi

# ls-files --stage prints:  <mode> <object> <stage>\t<path>
# Split on the tab so paths with spaces survive; mode is the space-separated $1.
non_exec=$(git ls-files --stage -- '*.sh' \
  | awk '{ split($0, a, "\t"); if ($1 != "100755") print a[2] }')

if [ -n "$non_exec" ]; then
  echo "FAIL: tracked shell scripts committed non-executable (mode != 100755):"
  printf '%s\n' "$non_exec" | sed 's/^/  /'
  echo "  A direct exec of these rc-126's ('Permission denied')."
  echo "  Fix: git update-index --chmod=+x <file>"
  exit 1
fi

echo "exec-bit check passed (all tracked *.sh are executable)."
exit 0
