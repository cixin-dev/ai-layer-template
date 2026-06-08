# Plan: Adopt Upstream Harness Patterns (hooks gate + validate split)

## Summary
Adopt three owner-confirmed upstream patterns from Cole Medin's `harness-engineering-demo`
into this language-agnostic machinery template. (1) **Hooks**: add a generic enforcement
**verify-gate `Stop` hook** (runs each project's own `.claude/verify.sh` and *blocks*
session completion on failure — turning the tdd-gate from a norm into an enforced gate) plus
a generic **`security_guard` PreToolUse hook** (deny reading/writing real `.env`, deny
recursive deletes); `sync.sh` carries both into `~/.claude/`. The three concrete Python demo
hooks are vendored into `examples/hooks/` as adapt-per-project reference. (2) **MCP
codebase-search**: explicitly rejected (recorded, no code). (3) **Validate split**: extract
the full validation gate + E2E out of `/implement` into a new `/validate` Phase-2 command, so
PIV becomes plan → implement → validate (+ retroactive); review stays human. A new ADR-0009
records the split, the hook relationship, and the MCP rejection.

## User Story
As the owner of this harness machinery, I want the validation gate enforced by a hook and
run as its own PIV step, and I want the upstream hook patterns available as reusable
machinery, so that broken state can't silently reach review and each project gets the same
safety net without per-repo copies.

## Metadata
| Field | Value |
|-------|-------|
| Type | ENHANCEMENT |
| Complexity | HIGH |
| Systems affected | `.claude/hooks/` (new), `.claude/commands/` (validate.md new, implement.md), `.claude/skills/piv-loop`, `scripts/sync.sh` + `sync.test.sh`, `examples/hooks/` (new), `CLAUDE.md`, `CONTEXT.md`, `README.md`, `docs/adr/0009` (new), `.claude/verify.sh` (new) |
| Ticket | N/A |

## Key design decisions (read before implementing)

1. **Generic hooks are language-agnostic; concrete ones are examples.** The demo's
   `security_guard.py` is already toolchain-free → adopt near-verbatim as the active
   `.claude/hooks/security_guard.py`. The demo's `stop_validate.py` / `post_tool_use_lint.py`
   hardcode `uv run ruff` / `pytest` / `app/backend` → they are NOT adopted active; they go to
   `examples/hooks/` verbatim as adaptation reference. The active `Stop` gate is a NEW generic
   `verify_gate.py` that runs a project-supplied `.claude/verify.sh`.

2. **Convention-over-config for the gate command.** `verify_gate.py` runs
   `$CLAUDE_PROJECT_DIR/.claude/verify.sh`. If that file is absent or not runnable, the hook
   **fails open** (exit 0, advisory note to stderr) so the global hook is harmless in
   non-harness projects and in this template out-of-the-box. Each project writes its own
   `.claude/verify.sh`. `.claude/verify.sh` is **project-specific → NOT synced** (like
   `CLAUDE.md` project specifics).

3. **Hooks are global machinery (ADR-0003).** `sync.sh` symlinks `.claude/hooks/*` into
   `~/.claude/hooks/` and additively wires the hooks block into **user-scope**
   `~/.claude/settings.json`. Global scope is consistent with this repo's model and both hooks
   are safe globally (verify-gate fails open; security_guard is a pure safety net). This is
   recorded in ADR-0009 as a deliberate tradeoff.

4. **settings.json is merged, never clobbered.** `sync.sh` uses `python3` (already required by
   the hooks) to do an **additive, idempotent, backed-up** merge of only our two hook entries
   into `~/.claude/settings.json`; it never removes user keys, writes a `.bak` first, supports
   `--dry-run`, and if `python3` is missing or the file is unparseable it **prints the snippet
   and skips** (never corrupts). This preserves sync.sh's existing "warn, don't clobber"
   contract (`scripts/sync.sh:54-56`).

5. **POSIX only.** Active hooks use `python3`, `bash`, `$CLAUDE_PROJECT_DIR` (not the demo's
   Windows `python` / `%CLAUDE_PROJECT_DIR%`). The Windows-style demo commands survive only in
   `examples/hooks/` as reference.

6. **Phase-2 commands, not skills (ADR-0005).** `/validate` is procedural (`$ARGUMENTS` → run
   gate → report) → a **command**, matching `/plan` and `/implement`. Do not author it as a
   skill. ADR-0009 *amends* ADR-0005's "Phase-2 commands unchanged" consequence.

7. **Vocabulary (ADR-0008).** Phase-2 machinery keeps the legacy word **Ticket** until the
   GitHub cutover. `validate.md` must mirror `implement.md`'s existing "Ticket" usage — do NOT
   introduce "issue/story/Jira" loosely. (The platform-fact word for the new command file is
   fine; this is about the work-unit noun.)

## Patterns to Follow

### A. Stop-gate loop guard + block decision — mirror for `verify_gate.py`
```python
# SOURCE: github-repo/harness-engineering-demo/.claude/hooks/stop_validate.py:34-71
def main() -> None:
    try:
        data: dict = json.load(sys.stdin)
    except Exception as e:
        print(f"[verify-gate] Could not parse hook JSON: {e}", file=sys.stderr)
        sys.exit(0)                       # fail open on bad stdin
    if data.get("stop_hook_active"):
        sys.exit(0)                       # prevent infinite block loop
    # ... run gate ...
    if failures:
        print(json.dumps({"decision": "block", "reason": reason}))
        sys.exit(0)
    sys.exit(0)
```
Adaptation: instead of hardcoded ruff/pytest, resolve `verify = $CLAUDE_PROJECT_DIR/.claude/verify.sh`;
if missing/not a file → `print("[verify-gate] no .claude/verify.sh; skipping", file=sys.stderr); sys.exit(0)`;
else run `bash verify` capturing output; non-zero → block with a short summary (first ~20 non-empty
lines, same trimming as `stop_validate.py:28-31`).

### B. `security_guard.py` — vendor near-verbatim
```python
# SOURCE: github-repo/harness-engineering-demo/.claude/hooks/security_guard.py:1-171 (entire file)
# Already language-agnostic. Copy verbatim into .claude/hooks/security_guard.py.
```

### C. settings.json hooks block — shape to merge (POSIX-ified)
```jsonc
// SOURCE: github-repo/harness-engineering-demo/.claude/settings.json:1-36 (shape)
// Adopt only PreToolUse(security_guard) + Stop(verify_gate); POSIX command strings:
{
  "hooks": {
    "PreToolUse": [{ "matcher": "Bash|Read|Edit|Write|MultiEdit|NotebookEdit|Glob|Grep",
      "hooks": [{ "type": "command", "command": "python3 \"<CLAUDE_DIR>/hooks/security_guard.py\"" }] }],
    "Stop": [{ "hooks": [{ "type": "command", "command": "python3 \"<CLAUDE_DIR>/hooks/verify_gate.py\"" }] }]
  }
}
```

### D. `link_item` symlink pass — mirror for a hooks pass in sync.sh
```bash
# SOURCE: scripts/sync.sh:66-84 (skills + commands loops)
# Add a third loop after commands: link each file under .claude/hooks/ into $CLAUDE_DIR/hooks/.
hooks_src="$REPO_DIR/.claude/hooks"
if [ -d "$hooks_src" ]; then
  for hook_file in "$hooks_src"/*; do
    [ -f "$hook_file" ] || continue
    name="$(basename "$hook_file")"
    link_item "$hooks_src/$name" "$CLAUDE_DIR/hooks/$name"
  done
fi
```
Also extend the real-run `mkdir -p` (`scripts/sync.sh:42`) to include `"$CLAUDE_DIR/hooks"`.

### E. sync test fixture + assertion style — extend
```bash
# SOURCE: scripts/sync.test.sh:31-54 (setup_fixture) and :15-29 (assert helpers)
# Add to fixture: mkdir -p "$REPO/.claude/hooks"; touch verify_gate.py security_guard.py
# Add a settings fixture path under $CLAUDE_HOME_DIR/settings.json
```

### F. Command frontmatter — mirror for validate.md
```markdown
<!-- SOURCE: .claude/commands/implement.md:1-4 -->
---
description: Run the full validation gate (project verify commands + E2E) as its own PIV session
argument-hint: <path/to/plan.md | blank to use current branch>
---
```

### G. validate report format — mirror (made language-agnostic)
```markdown
<!-- SOURCE: github-repo/harness-engineering-demo/.claude/skills/validate/SKILL.md:36-56 -->
# PASS/FAIL per command + Overall, then "fix and re-run" on FAIL.
# Replace the hardcoded ruff/mypy/pytest/tsc/vitest list with "the project's verify commands
# (CLAUDE.md → Verify commands / .claude/verify.sh)".
```

### H. implement.md section to remove/relocate
```markdown
<!-- SOURCE: .claude/commands/implement.md:72-86 (Phase 4 — Validate + E2E hard gate) -->
<!-- This whole block moves to /validate; implement keeps only per-task validation (Phase 3 step 3). -->
```

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `.claude/hooks/verify_gate.py` | CREATE | Generic `Stop` gate; runs `.claude/verify.sh`, blocks on failure, fails open if absent |
| `.claude/hooks/security_guard.py` | CREATE | Generic `PreToolUse` guard; vendored near-verbatim from demo |
| `.claude/verify.sh` | CREATE | This repo's own gate script: `exec bash scripts/sync.test.sh` (dogfood) |
| `.claude/commands/validate.md` | CREATE | New Phase-2 `/validate` command (full gate + E2E) |
| `examples/hooks/stop_validate.py` | CREATE | Demo verbatim — concrete specialization reference for verify_gate |
| `examples/hooks/post_tool_use_lint.py` | CREATE | Demo verbatim — advisory per-edit lint reference (no active counterpart) |
| `examples/hooks/security_guard.py` | CREATE | Demo verbatim — completeness; note it equals the adopted generic one |
| `examples/hooks/README.md` | CREATE | Explains the reference set + relationship to active `.claude/hooks/` |
| `docs/adr/0009-enforce-validate-gate-by-hook-and-split-validate-step.md` | CREATE | Records validate split, hook adoption + global-scope tradeoff, MCP rejection; amends ADR-0005 |
| `scripts/sync.sh` | UPDATE | Hooks symlink pass + additive settings.json merge + `--dry-run` + usage text |
| `scripts/sync.test.sh` | UPDATE | New assertions: hooks linked, settings merged additively + idempotently, dry-run mutates nothing, validate.md picked up |
| `.claude/commands/implement.md` | UPDATE | Remove Phase 4 full gate + E2E; end by handing off to `/validate`; renumber phases |
| `.claude/skills/piv-loop/SKILL.md` | UPDATE | Reframe Validate phase as its own `/validate` session before human review |
| `CLAUDE.md` | UPDATE | PIV Validate step → own session; document `.claude/verify.sh` + verify-gate hook (stay <~2.5k tokens) |
| `CONTEXT.md` | UPDATE | PIV Loop glossary entry: Validate is its own step/session; mention the verify gate |
| `README.md` | UPDATE | Layout (+hooks, +validate.md, +examples/hooks, +verify.sh), implement description, Sync section (hooks + settings merge), loop sequence |

## Tasks
Ordered; each independently verifiable. Run the listed check after each task; fix before moving on.

### Task 1: Generic active hooks
- Files: `.claude/hooks/verify_gate.py` (CREATE), `.claude/hooks/security_guard.py` (CREATE)
- Implement: `security_guard.py` = verbatim copy of demo file (Pattern B). `verify_gate.py` =
  new, following Pattern A: stdin-parse + `stop_hook_active` passthrough + resolve
  `$CLAUDE_PROJECT_DIR/.claude/verify.sh` + fail-open-if-absent + run via `bash` + block on
  non-zero with trimmed summary. Stdlib only (json, os, subprocess, sys, pathlib, shutil).
- Mirror: `github-repo/harness-engineering-demo/.claude/hooks/stop_validate.py:34-71`,
  `.../security_guard.py:1-171`
- Validate: `python3 -c "import ast,sys; [ast.parse(open(f).read()) for f in sys.argv[1:]]" .claude/hooks/verify_gate.py .claude/hooks/security_guard.py`
  then behavioral fixtures:
  - `printf '{"stop_hook_active":true}' | python3 .claude/hooks/verify_gate.py; echo $?` → exits 0, no output
  - with no `.claude/verify.sh` present in a temp `CLAUDE_PROJECT_DIR` → exits 0, stderr note, no block JSON
  - with a temp `verify.sh` that `exit 1` → prints `{"decision": "block"...}`, exits 0
  - `printf '{"tool_name":"Read","tool_input":{"file_path":".env"}}' | python3 .claude/hooks/security_guard.py` → prints `permissionDecision":"deny"`
  - same with `.env.example` → no deny
  - `printf '{"tool_name":"Bash","tool_input":{"command":"rm -rf build"}}' | python3 .claude/hooks/security_guard.py` → deny

### Task 2: This repo's own gate script
- File: `.claude/verify.sh` (CREATE, `chmod +x`)
- Implement: `#!/usr/bin/env bash` + `set -euo pipefail` + `exec bash "$(dirname "$0")/../scripts/sync.test.sh"`.
  (Dogfoods: the global verify-gate hook will run this repo's tests on Stop after sync.)
- Validate: `bash -n .claude/verify.sh` and `bash .claude/verify.sh` → `All tests passed.`

### Task 3: sync.sh — carry hooks + wire settings
- File: `scripts/sync.sh` (UPDATE)
- Implement: (a) extend real-run `mkdir -p` (`:42`) to add `"$CLAUDE_DIR/hooks"`. (b) Add the
  hooks symlink loop (Pattern D) after the commands loop. (c) Add an additive settings merge
  step per Design decision 4: resolve `SETTINGS="$CLAUDE_DIR/settings.json"`; build the two
  command strings from `$CLAUDE_DIR`; if `python3` available, run an inline python3 program
  (heredoc) that loads `SETTINGS` (or `{}`), ensures `hooks.PreToolUse`/`hooks.Stop` lists,
  appends our two entries only if no existing entry has the same `command` string, writes a
  `.bak` then the file; under `--dry-run` it prints `[sync] would wire hook: Stop -> verify_gate.py`
  (etc.) and writes nothing; if `python3` missing or file unparseable, print the snippet +
  `[sync] warn: wire hooks manually` and skip. (d) Update the usage/comment header
  (`scripts/sync.sh:3-11`) to mention hooks + settings.
- Mirror: `scripts/sync.sh:36-84`
- Validate: `bash -n scripts/sync.sh`; manual `SYNC_REPO_DIR=. CLAUDE_HOME=$(mktemp -d) bash scripts/sync.sh --dry-run` prints hook link + settings-wire plan and creates nothing.

### Task 4: Extend sync.test.sh
- File: `scripts/sync.test.sh` (UPDATE)
- Implement: extend `setup_fixture` (`:31-54`) to add `$REPO/.claude/hooks/{verify_gate.py,security_guard.py}`.
  Add assertions: (d) dry-run mentions `verify_gate.py` and `security_guard.py` as `would link:`;
  (e) dry-run mentions `would wire hook` for Stop + PreToolUse and leaves no `settings.json`;
  (f) real run creates `$CLAUDE_HOME_DIR/hooks/verify_gate.py` symlink and a `settings.json`
  containing `verify_gate.py` and `security_guard.py`; (g) second real run is idempotent
  (settings.json unchanged — capture sha before/after) and adds no duplicate hook entries;
  (h) `validate.md` (add to command fixture) appears as `would link:` (proves the existing glob
  carries the new command). Keep the existing assert helpers/style.
- Mirror: `scripts/sync.test.sh:15-54`
- Validate: `bash scripts/sync.test.sh` → `All tests passed.`

### Task 5: New /validate command
- File: `.claude/commands/validate.md` (CREATE)
- Implement: frontmatter per Pattern F. Body: a Phase-2 command that (1) loads the plan path
  arg (or uses current branch/conversation if blank) to find the E2E section; (2) runs the
  project's verify commands (CLAUDE.md → Verify commands / `.claude/verify.sh`); (3) runs the
  plan's E2E steps as a checklist (the hard gate relocated from implement); (4) reports
  PASS/FAIL per command + Overall (Pattern G); (5) on PASS, states the tree is ready for human
  review → merge; on FAIL, fix-and-rerun. Note the relationship to the `Stop` verify-gate hook
  (hook = automatic green-on-stop safety net; `/validate` = the deliberate full gate + E2E +
  human-review entry). Mirror "Ticket" usage from implement.md (Design decision 7).
- Mirror: `.claude/commands/implement.md:72-103`, `github-repo/harness-engineering-demo/.claude/skills/validate/SKILL.md:36-56`
- Validate: frontmatter parses (has `description`); `grep -niE "\b(issue|story|jira)\b" .claude/commands/validate.md` returns nothing problematic; internal links resolve.

### Task 6: Trim implement.md to hand off validate
- File: `.claude/commands/implement.md` (UPDATE)
- Implement: remove Phase 4 (`:72-86`, full suite + E2E hard gate). Keep per-task "Validate
  immediately" (Phase 3 step 3). Renumber: Phase 4 → Report (was Phase 5), Phase 5 → Output
  (was Phase 6). In the new final Output, the next step becomes `/validate <plan-path>` in a
  fresh session (then review, then PR). Keep worktree cleanup. Keep the "do not transition
  ticket status" rule. Update the top "Golden rule" only if it referenced the E2E gate.
- Mirror: existing structure `.claude/commands/implement.md:88-107`
- Validate: read-through — implement no longer claims to run the full gate/E2E; points to `/validate`.

### Task 7: Reframe piv-loop skill + CLAUDE.md + CONTEXT.md
- Files: `.claude/skills/piv-loop/SKILL.md` (UPDATE), `CLAUDE.md` (UPDATE), `CONTEXT.md` (UPDATE)
- Implement:
  - `piv-loop/SKILL.md:33-35`: Validate is now its own fresh session running `/validate` (full
    gate + E2E), then human review; pass → merge, problem → system-evolution. Update the
    one-line phase summary at `:22-35` accordingly.
  - `CLAUDE.md` PIV Loop section (the numbered Validate item): Validate = own session
    (`/validate`) running full gate + E2E, then human review. Add one lean line under Project
    specifics / Verification-led pointing to the `.claude/verify.sh` convention and the
    verify-gate `Stop` hook. Respect the <~2.5k-token budget — keep edits surgical.
  - `CONTEXT.md` PIV Loop entry (`:132-139`): reframe — Validate is its own step/session (not
    "checks during Implement"); the verify-gate `Stop` hook enforces green-on-stop. Keep
    glossary style; no new forbidden vocab.
- Validate: grep the three files for the now-stale phrase "checks already ran during Implement"
  / "automated checks ... run during Implement" → none remain; PIV described consistently as
  three sessions (plan/implement/validate).

### Task 8: ADR-0009
- File: `docs/adr/0009-enforce-validate-gate-by-hook-and-split-validate-step.md` (CREATE)
- Implement: status line `Amends ADR-0005`. Record: (1) split Validate out of /implement into
  `/validate` command + why (dedicated smart-zone session for the full gate + E2E; mirrors the
  demo's separate validate skill but stays a *command* per ADR-0005's interaction-shape rule);
  (2) enforcement via generic `verify_gate` `Stop` hook + its relationship to `/validate` (hook
  = automatic green-on-stop net every session; `/validate` = deliberate full gate + E2E +
  human-review entry); (3) hooks shipped as global machinery in `~/.claude/` with user-scope
  settings merge — the global-scope tradeoff (verify-gate fails open; security_guard is a safe
  net) accepted; (4) **MCP codebase-search rejected** (sub-agent + grep suffice; demo impl is
  Python-AST-specific, breaks language-agnostic stance). Alternatives rejected: keep validate
  in implement; manual settings snippet only; project-scope hooks.
- Mirror: `docs/adr/0008-unit-of-work-is-natively-a-github-issue.md` (status/structure)
- Validate: file present; references ADR-0005; no forbidden vocab.

### Task 9: README
- File: `README.md` (UPDATE)
- Implement: Layout block (`:42-61`) — add `.claude/commands/validate.md`, `.claude/hooks/`
  (verify_gate.py, security_guard.py), `examples/hooks/`, and `.claude/verify.sh` (note: not
  synced). Change implement.md description (`:49`) from "+ E2E gate" → "Implement phase";
  add validate.md line. Sync section (`:64-86`) — document that sync.sh also links
  `.claude/hooks/*` and additively wires the hooks block into `~/.claude/settings.json` (with
  `.bak`, idempotent, dry-run, manual-snippet fallback). Add the `.claude/verify.sh`
  convention + global-hook fail-open note. "After syncing" loop (`:98-99`) — insert `/validate`
  into the sequence.
- Validate: read-through; `bash scripts/sync.test.sh` still green; layout matches files on disk.

## Validation
- **Static**: `bash -n scripts/sync.sh scripts/sync.test.sh .claude/verify.sh`;
  `python3 -c "import ast,sys;[ast.parse(open(f).read()) for f in sys.argv[1:]]" .claude/hooks/*.py examples/hooks/*.py`
- **Unit/behavioral**: the `verify_gate.py` and `security_guard.py` stdin fixtures from Task 1.
- **Mechanical gate**: `bash scripts/sync.test.sh` → `All tests passed.` (extended in Task 4).
- **Glossary gate**: `grep -rniE "\b(jira|user story|story)\b" .claude/commands/validate.md docs/adr/0009-*.md` — no loose work-unit usage (Ticket allowed per ADR-0008).

## End-to-end verification (hard gate)
> Do NOT report complete until every step passes.
1. `bash scripts/sync.test.sh` → `All tests passed.`
2. Dry-run into a temp home: `T=$(mktemp -d); SYNC_REPO_DIR=$(pwd) CLAUDE_HOME=$T bash scripts/sync.sh --dry-run`
   → output lists `would link:` for verify_gate.py/security_guard.py + `would wire hook` for
   Stop & PreToolUse; assert `T` has NO `settings.json` and NO `hooks/` (mutated nothing).
3. Real run: `SYNC_REPO_DIR=$(pwd) CLAUDE_HOME=$T bash scripts/sync.sh` → assert symlinks
   `$T/hooks/verify_gate.py`, `$T/hooks/security_guard.py`, `$T/commands/validate.md`, and
   `$T/settings.json` contains both `verify_gate.py` and `security_guard.py`.
4. Idempotency: re-run step 3; assert `$T/settings.json` byte-identical (sha256) and no
   duplicate hook entries.
5. Gate behavior: in a temp project dir with `.claude/verify.sh` that `exit 1`,
   `CLAUDE_PROJECT_DIR=<dir> printf '{}' | python3 .claude/hooks/verify_gate.py` → emits a
   `block` decision; with `exit 0` → silent exit 0; with no verify.sh → silent exit 0.
6. `/validate` command frontmatter valid; `/implement` no longer claims the E2E gate; PIV docs
   (CLAUDE.md, piv-loop, CONTEXT.md) describe validate as its own session consistently.

## Acceptance Criteria
- [ ] All tasks completed
- [ ] `bash scripts/sync.test.sh` passes with zero failures (incl. new hook/settings assertions)
- [ ] Generic hooks are language-agnostic; demo Python hooks live only in `examples/hooks/`
- [ ] `sync.sh` carries hooks + wires settings additively, idempotently, non-destructively, with dry-run
- [ ] `/validate` exists as a command; `/implement` hands off to it; PIV docs reframed consistently
- [ ] ADR-0009 records the split, hook relationship + global-scope tradeoff, and MCP rejection
- [ ] No forbidden work-unit vocabulary introduced (ADR-0008); CLAUDE.md stays lean
- [ ] End-to-end steps 1–6 all pass
