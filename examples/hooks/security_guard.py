#!/usr/bin/env python3
"""
Concrete PreToolUse security guard example.
SOURCE: harness-engineering-demo/.claude/hooks/security_guard.py (verbatim reference)

This equals the adopted generic .claude/hooks/security_guard.py — vendored here for
completeness so you can see the original alongside the other examples.

Do NOT use this file directly — it lives in examples/hooks/ as adaptation reference.
The active version is .claude/hooks/security_guard.py.
"""

import json
import re
import sys


def check_env_file(tool_name: str, tool_input: dict) -> str | None:
    file_keys = []
    if tool_name in ("Read", "Edit", "MultiEdit", "Write"):
        file_keys = ["file_path"]
    elif tool_name == "Glob":
        file_keys = ["pattern"]
    elif tool_name == "Grep":
        file_keys = ["include"]

    for key in file_keys:
        path = tool_input.get(key, "")
        if not isinstance(path, str):
            continue
        filename = path.split("/")[-1]
        if re.match(r"^\.env$", filename):
            return f"Blocked: reading/writing real .env file '{path}'"
        if re.match(r"^\.env\.[^.]+$", filename):
            safe_suffixes = {"example", "template", "sample", "test"}
            suffix = filename.split(".", 2)[-1].lower()
            if suffix not in safe_suffixes:
                return f"Blocked: reading/writing real .env file '{path}'"

    return None


RECURSIVE_DELETE_PATTERNS = [
    r"\brm\s+(-\S*[rR]\S*|-\S*[fF]\S*[rR]\S*)\s",
    r"\brm\s+(-\S*[fF]\S*)\s",
    r"\brmdir\b",
    r"\bfind\b.*\s--delete\b",
    r"\bfind\b.*\s-delete\b",
    r"\bgit\s+clean\b.*\s-[a-zA-Z]*d",
]


def check_recursive_delete(tool_name: str, tool_input: dict) -> str | None:
    if tool_name != "Bash":
        return None
    command = tool_input.get("command", "")
    if not isinstance(command, str):
        return None
    for pattern in RECURSIVE_DELETE_PATTERNS:
        if re.search(pattern, command):
            return (
                f"Blocked: recursive delete detected in command: {command!r}. "
                "Run recursive deletes manually (e.g. `! rm -rf …`) so a human is in the loop."
            )
    return None


def main() -> None:
    try:
        data: dict = json.load(sys.stdin)
    except Exception as e:
        print(f"[security-guard] Could not parse hook JSON: {e}", file=sys.stderr)
        sys.exit(0)

    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input", {})

    reason = check_env_file(tool_name, tool_input) or check_recursive_delete(tool_name, tool_input)

    if reason:
        print(json.dumps({"permissionDecision": "deny", "reason": reason}))

    sys.exit(0)


if __name__ == "__main__":
    main()
