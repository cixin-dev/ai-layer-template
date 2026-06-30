#!/usr/bin/env bash
# Throwaway Night Shift executor probe (Issue #73) — prints a one-line greeting.
# The PR for this helper is closed UNMERGED: its value is proving the
# plan → implement → validate → PR → CI loop works, not the helper itself.
#
# Optional first arg is the name to greet; defaults to "world". Usage:
#   scripts/greeting.sh           # -> Hello, world!
#   scripts/greeting.sh "Night Shift"  # -> Hello, Night Shift!
set -euo pipefail

name="${1:-world}"
echo "Hello, ${name}!"
