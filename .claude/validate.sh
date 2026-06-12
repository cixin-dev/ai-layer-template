#!/usr/bin/env bash
set -euo pipefail
dir="$(dirname "$0")/../scripts"
bash "$dir/sync.test.sh"
bash "$dir/unsync.test.sh"
