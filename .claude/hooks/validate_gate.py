#!/usr/bin/env python3
"""
Stop hook: validate gate.

Runs the project's .claude/validate.sh when a session tries to end.
Blocks session completion on non-zero exit (turns test-first discipline
into an enforced gate). Fails open when .claude/validate.sh is absent
or unrunnable, so the global hook is harmless in non-harness projects.
"""

import json
import os
import subprocess
import sys
from pathlib import Path


MAX_OUTPUT_LINES = 20


def trim_output(text: str) -> str:
    """Return up to MAX_OUTPUT_LINES non-empty lines from the output."""
    lines = [l for l in text.splitlines() if l.strip()]
    trimmed = lines[:MAX_OUTPUT_LINES]
    result = "\n".join(trimmed)
    if len(lines) > MAX_OUTPUT_LINES:
        result += f"\n… ({len(lines) - MAX_OUTPUT_LINES} more lines truncated)"
    return result


def resolve_tree(data: dict) -> "Path | None":
    """Nearest ancestor of the payload cwd that contains .claude/validate.sh.

    Walk stops at $HOME and filesystem root so ~/.claude is never mistaken for
    a project root (retroactive: fix-validate-gate-worktree-cwd).
    """
    cwd = data.get("cwd")
    if not cwd:
        return None
    start = Path(cwd)
    if not start.is_dir():
        return None
    home = Path.home()
    for candidate in (start, *start.parents):
        if candidate == home or candidate == candidate.parent:
            break
        if (candidate / ".claude" / "validate.sh").is_file():
            return candidate
    return None


def main() -> None:
    try:
        data: dict = json.load(sys.stdin)
    except Exception as e:
        print(f"[validate-gate] Could not parse hook JSON: {e}", file=sys.stderr)
        sys.exit(0)  # fail open on bad stdin

    if data.get("stop_hook_active"):
        sys.exit(0)  # prevent infinite block loop

    resolved = resolve_tree(data)
    if resolved is not None:
        project_dir = str(resolved)
        validate_sh = resolved / ".claude" / "validate.sh"
    else:
        project_dir = os.environ.get("CLAUDE_PROJECT_DIR", "")
        if not project_dir:
            print("[validate-gate] CLAUDE_PROJECT_DIR not set; skipping", file=sys.stderr)
            sys.exit(0)
        validate_sh = Path(project_dir) / ".claude" / "validate.sh"
        if not validate_sh.is_file():
            print(f"[validate-gate] no .claude/validate.sh in {project_dir}; skipping", file=sys.stderr)
            sys.exit(0)

    timeout = int(os.environ.get("VALIDATE_GATE_TIMEOUT", "120"))
    try:
        result = subprocess.run(
            ["bash", str(validate_sh)],
            capture_output=True,
            text=True,
            cwd=project_dir,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        print(f"[validate-gate] validate.sh timed out after {timeout}s; skipping", file=sys.stderr)
        sys.exit(0)  # fail open on timeout
    except Exception as e:
        print(f"[validate-gate] failed to run validate.sh: {e}", file=sys.stderr)
        sys.exit(0)  # fail open on execution error

    if result.returncode != 0:
        # stderr first: bash runtime errors go there; stdout may be verbose progress noise
        combined = (result.stderr + "\n" + result.stdout).strip()
        summary = trim_output(combined) or "validate.sh exited non-zero with no output"
        reason = f"Validation gate failed:\n{summary}"
        # Best-effort FAIL notification. Captured (never touches our block-JSON
        # stdout) and guarded so it can neither fail nor delay the gate.
        first_line = summary.splitlines()[0] if summary else "validate.sh failed"
        notify = os.environ.get(
            "VALIDATE_GATE_NOTIFY", str(Path(__file__).resolve().parent / "notify.sh")
        )
        repo = Path(project_dir).name or project_dir
        try:
            subprocess.run(
                [notify, "fail", "Validate FAIL", f"{repo}: {first_line}"],
                capture_output=True,
                text=True,
                timeout=10,
            )
        except Exception:
            pass  # notification is best-effort; never fail or delay the gate
        print(json.dumps({"decision": "block", "reason": reason}))

    sys.exit(0)


if __name__ == "__main__":
    main()
