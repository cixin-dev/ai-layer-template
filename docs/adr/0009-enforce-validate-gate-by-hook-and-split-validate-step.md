# Enforce the validate gate by hook and split Validate into its own PIV step

**Status:** Amends ADR-0005.

## Decision

Three related changes ship together because each reinforces the others:

1. **Split Validate out of `/implement` into its own `/validate` command** (a new Phase-2
   command per ADR-0005's interaction-shape rule). The full gate (`validate.sh` + the plan's
   E2E checklist) and the human-review entry move there. `/implement` retains only per-task
   validation (run-check-fix-proceed).

2. **Enforce the validate gate mechanically via a `Stop` hook** (`validate_gate.py`). The hook
   runs the project's `.claude/validate.sh` when any session tries to end and *blocks*
   completion on failure — turning the test-first discipline from a norm into an enforced gate.
   Two layers, one "validate" root: the **validate gate** is the automatic floor (every
   session); **`/validate`** is the deliberate full pass (PIV Validate step).

3. **Add a generic `PreToolUse` `security_guard` hook** that denies agent-issued reads/writes
   of real `.env` files and all recursive deletes.

## Why split Validate

`/implement` finishing its own E2E gate violates the PIV session-separation principle: the
session that wrote the code is a poorer reviewer of it than a fresh session would be (context
decay + planning bias). Splitting forces a clean-slate review of the same gate the hook
already enforces automatically, and adds the E2E and human-review entry that `/implement`
cannot reliably do.

This amends ADR-0005's consequence "Phase-2 commands unchanged" — `/validate` is a net-new
Phase-2 command. The interaction shape (procedural, `$ARGUMENTS`-driven, no conversational
loop) follows the same rule ADR-0005 established; the amendment is additive.

## Why one "validate" root

Cole Medin's upstream uses a single "validate" root for both layers — his `stop_validate.py`
is literally a "validation gate" and his explicit skill is named "validate" ("the same gate
the Stop hook enforces automatically"). Introducing a "verify-vs-validate" split would fight
upstream vocabulary without adding meaning: both words mean "check correctness"; the real
distinction is *automatic floor* vs *deliberate full pass*, not kind. "Verify" survives only
in CLAUDE.md's `Verify commands` slot (the commands you check with, which `validate.sh`
bundles) — not a second layer name.

## The `validate.sh` language-agnostic extension

Cole's upstream hook hardcodes ruff/pytest. This repo's hook is global and cross-language, so
it runs a project-supplied `.claude/validate.sh` instead. That indirection is what lets one
global hook serve N projects with different stacks. Each project writes its own `validate.sh`
(not synced — project-specific, like `CLAUDE.md`'s Project specifics section). The hook
**fails open** when `validate.sh` is absent or not runnable (exit 0, advisory stderr note) so
it is harmless in non-harness projects.

An env-var escape hatch (e.g. `VALIDATE_GATE_OFF=1`) to opt out was considered and rejected:
an opt-out turns the enforced gate back into a norm, defeating the purpose. The only opt-out
granularity is the presence of `.claude/validate.sh` (fail-open when absent), which is opt-in
per project and already the right granularity.

## Hooks shipped as global machinery

Consistent with ADR-0003 (global harness machinery, not per-project copies), `sync.sh`
symlinks `.claude/hooks/*` into `~/.claude/hooks/` and additively wires the two hook entries
into user-scope `~/.claude/settings.json` (backs up the file first; idempotent; never removes
user keys; falls back to printing the snippet if python3 is missing or the file is
unparseable).

Global scope is appropriate: the validate gate fails open (harmless in any project), and the
security_guard is a pure safety net.

**Accepted cost of the global security_guard**: it blanket-denies *all* agent-issued recursive
deletes (`rm -r/-rf/-fr`, `rmdir`, `find -delete`, `git clean -d`) in every project —
including routine `rm -rf node_modules`/`build`/`dist`. The friction falls on the agent, not
the owner: the deny returns a reason, the agent asks, and the owner runs such deletes manually
(e.g. `! rm -rf …`). This is intentional — recursive deletion is exactly the irreversible
class that warrants a human in the loop.

**Option B rejected** — a "safe relative paths" allowlist (e.g. allow `rm -rf node_modules`
if the path is relative and known-safe): rejected to avoid forking the verbatim upstream hook
and because such an allowlist creates its own sandbox-escape surface (any path that passes the
filter is now auto-approved).

## MCP codebase-search rejected

The upstream harness-engineering-demo includes a Python-AST-based MCP codebase-search server.
Rejected for this template: sub-agent + grep suffice for search; the implementation is
Python-AST-specific, breaking the language-agnostic stance; and the complexity cost exceeds
the benefit for a template that must stay portable. No code added; decision recorded here.

## Alternatives considered

- **Keep Validate inside `/implement`**: rejected — the reviewer is the (degraded) implementer;
  session separation is the core PIV invariant.
- **Manual settings snippet only** (no sync.sh merge): rejected — too easy to miss; defeats
  the "sync once" contract.
- **Project-scope hooks** (`.claude/settings.json` in each project, not global): rejected —
  inconsistent with ADR-0003; each project would need its own copy.
- **Hardcoding commands in the hook** (like Cole): rejected — breaks the global/cross-language
  invariant; the `validate.sh` indirection is the required extension.
- **Two-root split (verify vs validate)**: rejected — false distinction; fights upstream
  vocabulary; the real axis is automatic-floor vs deliberate-full-pass, not kind.
