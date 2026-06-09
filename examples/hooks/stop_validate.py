#!/usr/bin/env python3
"""
Concrete Stop-hook example: validate gate for a Python/uv project.
SOURCE: harness-engineering-demo/.claude/hooks/stop_validate.py (verbatim reference)

This hardcodes ruff + pytest under uv for a specific Python project.
For a language-agnostic gate, use .claude/hooks/validate_gate.py + a project
.claude/validate.sh instead.

Do NOT use this file directly — it lives in examples/hooks/ as adaptation reference.
"""

import json
import subprocess
import sys


def run_command(command: list[str], cwd: str | None = None) -> tuple[int, str, str]:
    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        cwd=cwd,
    )
    return result.returncode, result.stdout, result.stderr


def trim_output(output: str, max_lines: int = 20) -> str:
    lines = [line for line in output.splitlines() if line.strip()]
    if len(lines) <= max_lines:
        return "\n".join(lines)
    return "\n".join(lines[:max_lines]) + f"\n... ({len(lines) - max_lines} more lines)"


def main() -> None:
    try:
        data: dict = json.load(sys.stdin)
    except Exception as e:
        print(f"Error parsing hook data: {e}", file=sys.stderr)
        sys.exit(0)

    if data.get("stop_hook_active"):
        sys.exit(0)

    failures: list[str] = []
    project_dir = "app/backend"

    # Run ruff linter
    returncode, stdout, stderr = run_command(
        ["uv", "run", "ruff", "check", "."],
        cwd=project_dir,
    )
    if returncode != 0:
        output = trim_output(stdout + stderr)
        failures.append(f"Ruff linting failed:\n{output}")

    # Run pytest
    returncode, stdout, stderr = run_command(
        ["uv", "run", "pytest", "--tb=short", "-q"],
        cwd=project_dir,
    )
    if returncode != 0:
        output = trim_output(stdout + stderr)
        failures.append(f"Tests failed:\n{output}")

    if failures:
        reason = "\n\n".join(failures)
        print(
            json.dumps(
                {
                    "decision": "block",
                    "reason": f"Validation failed. Please fix these issues:\n\n{reason}",
                }
            )
        )

    sys.exit(0)


if __name__ == "__main__":
    main()
