#!/usr/bin/env python3
"""
Advisory PostToolUse hook example: per-edit lint for a Python/uv project.
SOURCE: harness-engineering-demo/.claude/hooks/post_tool_use_lint.py (verbatim reference)

Runs ruff after every file write to surface lint issues immediately (advisory —
does not block). No active counterpart in this template. Add one in your project's
.claude/hooks/ if you want per-edit feedback.

Do NOT use this file directly — it lives in examples/hooks/ as adaptation reference.
"""

import json
import subprocess
import sys


def main() -> None:
    try:
        data: dict = json.load(sys.stdin)
    except Exception as e:
        print(f"Error parsing hook data: {e}", file=sys.stderr)
        sys.exit(0)

    tool_name = data.get("tool_name", "")
    if tool_name not in ("Write", "Edit", "MultiEdit"):
        sys.exit(0)

    tool_input = data.get("tool_input", {})
    file_path = tool_input.get("file_path", "")
    if not file_path.endswith(".py"):
        sys.exit(0)

    result = subprocess.run(
        ["uv", "run", "ruff", "check", file_path],
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        print(f"[lint] ruff found issues in {file_path}:", file=sys.stderr)
        print(result.stdout, file=sys.stderr)

    sys.exit(0)


if __name__ == "__main__":
    main()
