# Example Hooks (reference only)

These are concrete, project-specific hook specializations vendored from
Cole Medin's `harness-engineering-demo` as adaptation reference.

**Do NOT use these files directly.** They are not active hooks — they live here
to show how a project would specialise the generic active hooks in `.claude/hooks/`.

| File | Source | What to adapt |
|------|--------|---------------|
| `stop_validate.py` | `harness-engineering-demo/.claude/hooks/stop_validate.py` | Concrete `Stop` gate specialization — hardcodes `uv run ruff` + `pytest` for a Python project. For a language-agnostic gate, use `validate_gate.py` + a project `.claude/validate.sh` instead. |
| `post_tool_use_lint.py` | `harness-engineering-demo/.claude/hooks/post_tool_use_lint.py` | Advisory per-edit lint (runs `ruff` after every file write). No active counterpart in this template — add one if your project benefits from per-edit feedback. |
| `security_guard.py` | `harness-engineering-demo/.claude/hooks/security_guard.py` | Equals the adopted generic `.claude/hooks/security_guard.py` — vendored here for completeness so you can see the original. |

## Active hooks

The active hooks for this template live in `.claude/hooks/` and are synced to
`~/.claude/hooks/` by `sync.sh`:

- **`validate_gate.py`** — generic `Stop` gate; delegates to `.claude/validate.sh`
- **`security_guard.py`** — generic `PreToolUse` guard; denies `.env` reads/writes + recursive deletes
