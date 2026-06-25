#!/usr/bin/env bash
set -euo pipefail
dir="$(dirname "$0")/../scripts"
bash "$dir/piv_check.sh"
# Non-blocking: remind about the canonical-doc PR-body requirement (ADR-0022)
# when this branch touches CONTEXT.md / docs/adr/. Always exits 0.
bash "$dir/doc_change_reminder.sh"
