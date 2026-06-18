#!/usr/bin/env bash
# Gate: PRs touching canonical docs (CONTEXT.md, docs/adr/) must include a
# Traditional Chinese "## 變更說明" section in the PR body.
# Usage: doc_change_gate.sh <changed-files-file> <pr-body-file>
# Exits 0 (pass) or 1 (block). Requires GNU grep -P for CJK detection (Linux/CI only).
set -euo pipefail

CHANGED_FILES="${1:-}"
PR_BODY_FILE="${2:-}"

if [ -z "$CHANGED_FILES" ] || [ -z "$PR_BODY_FILE" ]; then
  echo "Usage: doc_change_gate.sh <changed-files-file> <pr-body-file>" >&2
  exit 1
fi

canonical_changed=0
while IFS= read -r file || [ -n "$file" ]; do
  [ -z "$file" ] && continue
  if printf '%s' "$file" | grep -qE '^CONTEXT\.md$|^docs/adr/'; then
    canonical_changed=1
    break
  fi
done < "$CHANGED_FILES"

[ "$canonical_changed" -eq 0 ] && exit 0

has_section=0
has_cjk=0

grep -qE '^#{1,6}[[:space:]]*變更說明' "$PR_BODY_FILE" 2>/dev/null && has_section=1
grep -qP '[\x{4e00}-\x{9fff}]' "$PR_BODY_FILE" 2>/dev/null && has_cjk=1

[ "$has_section" -eq 1 ] && [ "$has_cjk" -eq 1 ] && exit 0

cat >&2 << 'MSG'
[doc_change_gate] ERROR: This PR modifies canonical documentation (CONTEXT.md or docs/adr/).
The PR body must include a "## 變更說明" section (Traditional Chinese) explaining what changed and why.

[doc_change_gate] 錯誤：此 PR 修改了 canonical 文件（CONTEXT.md 或 docs/adr/）。
PR body 必須包含「## 變更說明」段落（繁體中文），說明改了什麼、為什麼改。
MSG

exit 1
