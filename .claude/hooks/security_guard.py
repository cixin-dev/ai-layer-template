#!/usr/bin/env python3
"""
PreToolUse security guard hook.

Denies:
  - Reading or writing real .env files (but not .env.example, .env.template, etc.)
  - Recursive deletes (rm -r/-rf/-fr, rmdir, find -delete, git clean -d)
  - Untrusted fetch-and-execute (curl … | sh, wget … | bash, bare … | sh,
    sh -c "$(…)" / backtick / eval command-substitution forms)

Denials exit(2) with the reason on stderr. Per ADR-0016, only an exit(2) block is
evaluated before the deny→ask→allow rule flow, so it overrides a matching allow rule
instead of being silently ignored (an exit(0)+JSON deny would lose to a broad allowlist).

Fails open (exit 0) on parse errors so it never blocks non-Bash/file tools unexpectedly.
"""

import json
import re
import sys


def check_env_file(tool_name: str, tool_input: dict) -> str | None:
    """Return a denial reason if a real .env file is being accessed, else None."""
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
        # Match .env exactly, or .env followed by a non-alphanumeric non-dot char
        # This allows .env.example, .env.local.example but blocks .env, .env.local, .env.production
        if re.match(r"^\.env$", filename):
            return f"Blocked: reading/writing real .env file '{path}'"
        # Block .env.<word> but not .env.example or .env.template or .env.sample
        if re.match(r"^\.env\.[^.]+$", filename):
            safe_suffixes = {"example", "template", "sample", "test"}
            suffix = filename.split(".", 2)[-1].lower()
            if suffix not in safe_suffixes:
                return f"Blocked: reading/writing real .env file '{path}'"

    return None


RECURSIVE_DELETE_PATTERNS = [
    r"\brm\s+(-\S*[rR]\S*|-\S*[fF]\S*[rR]\S*)\s",   # rm -r, rm -rf, rm -fr, rm -Rf, etc.
    r"\brmdir\b.*-[a-zA-Z]*p",                         # rmdir -p removes the ancestor chain
    r"\bfind\b.*\s--?delete\b",                        # find -delete / find --delete
    r"\bgit\s+clean\b.*\s-[a-zA-Z]*d",                 # git clean -d, git clean -fd, etc.
]


def check_recursive_delete(tool_name: str, tool_input: dict) -> str | None:
    """Return a denial reason if a recursive delete is detected, else None."""
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


REMOTE_EXEC_PATTERNS = [
    r"\|\s*(sudo\s+)?(sh|bash|zsh)\b",          # … | sh, curl … | sudo bash, wget … | bash (\b avoids | shasum)
    r"\b(sh|bash|zsh)\s+-c\b.*(\$\(|`)",        # sh -c "$(…)" / bash -c `…` command-substitution exec
    r"\beval\b.*(\$\(|`)",                       # eval "$(…)" / eval `…`
]


def check_remote_exec(tool_name: str, tool_input: dict) -> str | None:
    """Return a denial reason if untrusted fetch-and-execute is detected, else None."""
    if tool_name != "Bash":
        return None
    command = tool_input.get("command", "")
    if not isinstance(command, str):
        return None
    for pattern in REMOTE_EXEC_PATTERNS:
        if re.search(pattern, command):
            return (
                f"Blocked: untrusted fetch-and-execute detected in command: {command!r}. "
                "Review and run it manually if you trust the source."
            )
    return None


def main() -> None:
    try:
        data: dict = json.load(sys.stdin)
    except Exception as e:
        print(f"[security-guard] Could not parse hook JSON: {e}", file=sys.stderr)
        sys.exit(0)  # fail open

    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input", {})

    reason = (
        check_env_file(tool_name, tool_input)
        or check_recursive_delete(tool_name, tool_input)
        or check_remote_exec(tool_name, tool_input)
    )

    if reason:
        print(reason, file=sys.stderr)
        sys.exit(2)

    sys.exit(0)


if __name__ == "__main__":
    main()
