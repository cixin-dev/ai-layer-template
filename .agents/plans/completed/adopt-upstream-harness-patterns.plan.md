# Plan: Adopt Upstream Harness Patterns (hooks gate + validate split)

## Summary
Adopt three owner-confirmed upstream patterns from Cole Medin's `harness-engineering-demo`
into this language-agnostic machinery template. (1) **Hooks**: add a generic enforcement
**validate gate `Stop` hook** (runs each project's own `.claude/validate.sh` and *blocks*
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
| Systems affected | `.claude/hooks/` (new), `.claude/commands/` (validate.md new, implement.md), `.claude/skills/piv-loop`, `scripts/sync.sh` + `sync.test.sh`, `examples/hooks/` (new), `CLAUDE.md`, `CONTEXT.md`, `README.md`, `docs/adr/0009` (new), `.claude/validate.sh` (new) |
| Ticket | N/A |

## Key design decisions (read before implementing)

1. **Generic hooks are language-agnostic; concrete ones are examples.** The demo's
   `security_guard.py` is already toolchain-free → adopt near-verbatim as the active
   `.claude/hooks/security_guard.py`. The demo's `stop_validate.py` / `post_tool_use_lint.py`
   hardcode `uv run ruff` / `pytest` / `app/backend` → they are NOT adopted active; they go to
   `examples/hooks/` verbatim as adaptation reference. The active `Stop` gate is a NEW generic
   `validate_gate.py` that runs a project-supplied `.claude/validate.sh`.

2. **Convention-over-config for the gate command.** `validate_gate.py` runs
   `$CLAUDE_PROJECT_DIR/.claude/validate.sh`. If that file is absent or not runnable, the hook
   **fails open** (exit 0, advisory note to stderr) so the global hook is harmless in
   non-harness projects and in this template out-of-the-box. Each project writes its own
   `.claude/validate.sh`. `.claude/validate.sh` is **project-specific → NOT synced** (like
   `CLAUDE.md` project specifics).

   **Naming (single "validate" root).** Cole uses ONE root for both layers — `stop_validate.py`
   is literally a "validation gate" and the explicit skill is `/validate` ("the same gate the
   Stop hook enforces automatically"); "verify" in his repos is only incidental English, never a
   named layer. So name everything `validate`: `validate_gate.py` (hook), `.claude/validate.sh`
   (script), `/validate` (command). Do **not** introduce a "verify" layer — a verify-vs-validate
   split would be a false distinction (both mean "check correctness"; the real difference is
   automatic-floor vs explicit-full, not kind) and would fight upstream vocabulary. "verify"
   survives ONLY as generic English: CLAUDE.md's existing `Verify commands` slot and the
   `Verification-led` principle name the *commands you check with*, which `validate.sh` bundles —
   leave those two as-is, do not rename them. The `.claude/validate.sh` indirection itself is a
   deliberate **language-agnostic extension** of Cole (who hardcodes ruff/pytest in the hook);
   it is what lets ONE global, cross-language hook serve N projects. Record both in ADR-0009.

3. **Hooks are global machinery (ADR-0003).** `sync.sh` symlinks `.claude/hooks/*` into
   `~/.claude/hooks/` and additively wires the hooks block into **user-scope**
   `~/.claude/settings.json`. Global scope is consistent with this repo's model and both hooks
   are safe globally (validate gate fails open; security_guard is a pure safety net). This is
   recorded in ADR-0009 as a deliberate tradeoff. **Accepted cost of the global security_guard**:
   it blanket-denies *all* agent-issued recursive deletes (`rm -r/-rf/-fr`, `rmdir`, `find -delete`,
   `git clean -d`) in every project — including routine `rm -rf node_modules`/`build`/`dist`. The
   friction falls on the agent, not the owner: the deny returns a reason, the agent asks, and the
   owner runs such deletes manually (e.g. `!rm -rf …`). This is intended — recursive deletion is
   exactly the irreversible class that wants a human in the loop. NOT scoped down to a "safe
   relative paths" allowlist (option B), to avoid forking the verbatim upstream hook and the
   allowlist's own escape-the-sandbox holes.

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

7. **Vocabulary (ADR-0008).** `/validate` consumes a **plan path / branch**, not a work unit —
   it does not create branches or post linkbacks (those stay in `/implement`). So `validate.md`
   **avoids the work-unit noun entirely** (neither "Ticket" nor "Issue"); the false "mirror
   implement.md's Ticket usage" instruction is dropped. A fresh file born with "Ticket" would be
   exactly the "new use" CONTEXT.md's `Issue` entry forbids. `validate.md` is the **last** Phase-2
   command that could carry the legacy term, and it carries none. At the GitHub cutover, sweep the
   surviving "Ticket" usages in `plan.md` + `implement.md` (and `.agents/tickets/`) to "Issue"
   together. Still do NOT introduce "issue/story/Jira" loosely in `validate.md`.

8. **Validate's problem branch hands off to `/retroactive` (ADR-0010).** The Validate step
   continues past the mechanical gate into human review; when review surfaces a *problem*, the
   System Evolution outer loop is **triggered through the workflow** — `validate.md` ends its
   problem branch by deterministically routing to `/retroactive` in a fresh session, mirroring how
   `/implement` hands off to `/validate`. This is the *trigger* (it surfaces the option, not from
   memory or a hook); whether a retroactive is actually run stays judgment (severity × recurrence).
   Do NOT add a hook for this — System Evolution's trigger is a semantic event a mechanical hook
   can't judge (ADR-0010: hooks enforce objective red/green floors, handoffs carry semantic flow).
   ADR-0010 already exists; this plan only wires the handoff into `validate.md` + `piv-loop`.

## Patterns to Follow

### A. Stop-gate loop guard + block decision — mirror for `validate_gate.py`
```python
# SOURCE: github-repo/harness-engineering-demo/.claude/hooks/stop_validate.py:34-71
def main() -> None:
    try:
        data: dict = json.load(sys.stdin)
    except Exception as e:
        print(f"[validate-gate] Could not parse hook JSON: {e}", file=sys.stderr)
        sys.exit(0)                       # fail open on bad stdin
    if data.get("stop_hook_active"):
        sys.exit(0)                       # prevent infinite block loop
    # ... run gate ...
    if failures:
        print(json.dumps({"decision": "block", "reason": reason}))
        sys.exit(0)
    sys.exit(0)
```
Adaptation: instead of hardcoded ruff/pytest, resolve `validate = $CLAUDE_PROJECT_DIR/.claude/validate.sh`;
if missing/not a file → `print("[validate-gate] no .claude/validate.sh; skipping", file=sys.stderr); sys.exit(0)`;
else run `bash validate` capturing output; non-zero → block with a short summary (first ~20 non-empty
lines, same trimming as `stop_validate.py:28-31`).

### B. `security_guard.py` — vendor near-verbatim
```python
# SOURCE: github-repo/harness-engineering-demo/.claude/hooks/security_guard.py:1-171 (entire file)
# Already language-agnostic. Copy verbatim into .claude/hooks/security_guard.py.
```

### C. settings.json hooks block — shape to merge (POSIX-ified)
```jsonc
// SOURCE: github-repo/harness-engineering-demo/.claude/settings.json:1-36 (shape)
// Adopt only PreToolUse(security_guard) + Stop(validate_gate); POSIX command strings:
{
  "hooks": {
    "PreToolUse": [{ "matcher": "Bash|Read|Edit|Write|MultiEdit|NotebookEdit|Glob|Grep",
      "hooks": [{ "type": "command", "command": "python3 \"<CLAUDE_DIR>/hooks/security_guard.py\"" }] }],
    "Stop": [{ "hooks": [{ "type": "command", "command": "python3 \"<CLAUDE_DIR>/hooks/validate_gate.py\"" }] }]
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
# Add to fixture: mkdir -p "$REPO/.claude/hooks"; touch validate_gate.py security_guard.py
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
# (CLAUDE.md → Verify commands / .claude/validate.sh)".
```

### H. implement.md section to remove/relocate
```markdown
<!-- SOURCE: .claude/commands/implement.md:72-86 (Phase 4 — Validate + E2E hard gate) -->
<!-- This whole block moves to /validate; implement keeps only per-task validation (Phase 3 step 3). -->
```

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `.claude/hooks/validate_gate.py` | CREATE | Generic `Stop` gate; runs `.claude/validate.sh`, blocks on failure, fails open if absent |
| `.claude/hooks/security_guard.py` | CREATE | Generic `PreToolUse` guard; vendored near-verbatim from demo |
| `.claude/validate.sh` | CREATE | This repo's own gate script: `exec bash scripts/sync.test.sh` (dogfood) |
| `.claude/commands/validate.md` | CREATE | New Phase-2 `/validate` command (full gate + E2E) |
| `examples/hooks/stop_validate.py` | CREATE | Demo verbatim — concrete specialization reference for validate_gate |
| `examples/hooks/post_tool_use_lint.py` | CREATE | Demo verbatim — advisory per-edit lint reference (no active counterpart) |
| `examples/hooks/security_guard.py` | CREATE | Demo verbatim — completeness; note it equals the adopted generic one |
| `examples/hooks/README.md` | CREATE | Explains the reference set + relationship to active `.claude/hooks/` |
| `docs/adr/0009-enforce-validate-gate-by-hook-and-split-validate-step.md` | CREATE | Records validate split, hook adoption + global-scope tradeoff, MCP rejection; amends ADR-0005 |
| `scripts/sync.sh` | UPDATE | Hooks symlink pass + additive settings.json merge + `--dry-run` + usage text |
| `scripts/sync.test.sh` | UPDATE | New assertions: hooks linked, settings merged additively + idempotently, dry-run mutates nothing, validate.md picked up |
| `.claude/commands/implement.md` | UPDATE | Remove Phase 4 full gate + E2E; end by handing off to `/validate`; renumber phases |
| `.claude/skills/piv-loop/SKILL.md` | UPDATE | Reframe Validate phase as its own `/validate` session before human review |
| `CLAUDE.md` | UPDATE | PIV Validate step → own session; document `.claude/validate.sh` + validate gate hook (stay <~2.5k tokens) |
| `CONTEXT.md` | DONE (verify only) | PIV Loop entry reframed + new **validate gate** entry — written in the alignment session; Implement only verifies, does not rewrite |
| `README.md` | UPDATE | Layout (+hooks, +validate.md, +examples/hooks, +validate.sh), implement description, Sync section (hooks + settings merge), loop sequence |

## Tasks
Ordered; each independently verifiable. Run the listed check after each task; fix before moving on.

### Task 1: Generic active hooks
- Files: `.claude/hooks/validate_gate.py` (CREATE), `.claude/hooks/security_guard.py` (CREATE)
- Implement: `security_guard.py` = verbatim copy of demo file (Pattern B). `validate_gate.py` =
  new, following Pattern A: stdin-parse + `stop_hook_active` passthrough + resolve
  `$CLAUDE_PROJECT_DIR/.claude/validate.sh` + fail-open-if-absent + run via `bash` + block on
  non-zero with trimmed summary. Stdlib only (json, os, subprocess, sys, pathlib, shutil).
- Mirror: `github-repo/harness-engineering-demo/.claude/hooks/stop_validate.py:34-71`,
  `.../security_guard.py:1-171`
- Validate: `python3 -c "import ast,sys; [ast.parse(open(f).read()) for f in sys.argv[1:]]" .claude/hooks/validate_gate.py .claude/hooks/security_guard.py`
  then behavioral fixtures:
  - `printf '{"stop_hook_active":true}' | python3 .claude/hooks/validate_gate.py; echo $?` → exits 0, no output
  - with no `.claude/validate.sh` present in a temp `CLAUDE_PROJECT_DIR` → exits 0, stderr note, no block JSON
  - with a temp `validate.sh` that `exit 1` → prints `{"decision": "block"...}`, exits 0
  - `printf '{"tool_name":"Read","tool_input":{"file_path":".env"}}' | python3 .claude/hooks/security_guard.py` → prints `permissionDecision":"deny"`
  - same with `.env.example` → no deny
  - `printf '{"tool_name":"Bash","tool_input":{"command":"rm -rf build"}}' | python3 .claude/hooks/security_guard.py` → deny

### Task 2: This repo's own gate script
- File: `.claude/validate.sh` (CREATE, `chmod +x`)
- Implement: `#!/usr/bin/env bash` + `set -euo pipefail` + `exec bash "$(dirname "$0")/../scripts/sync.test.sh"`.
  (Dogfoods: the global validate gate hook will run this repo's tests on Stop after sync.)
- Validate: `bash -n .claude/validate.sh` and `bash .claude/validate.sh` → `All tests passed.`

### Task 3: sync.sh — carry hooks + wire settings
- File: `scripts/sync.sh` (UPDATE)
- Implement: (a) extend real-run `mkdir -p` (`:42`) to add `"$CLAUDE_DIR/hooks"`. (b) Add the
  hooks symlink loop (Pattern D) after the commands loop. (c) Add an additive settings merge
  step per Design decision 4: resolve `SETTINGS="$CLAUDE_DIR/settings.json"`; build the two
  command strings from `$CLAUDE_DIR`; if `python3` available, run an inline python3 program
  (heredoc) that loads `SETTINGS` (or `{}`), ensures `hooks.PreToolUse`/`hooks.Stop` lists,
  appends our two entries only if no existing entry has the same `command` string, writes a
  `.bak` then the file; under `--dry-run` it prints `[sync] would wire hook: Stop -> validate_gate.py`
  (etc.) and writes nothing; if `python3` missing or file unparseable, print the snippet +
  `[sync] warn: wire hooks manually` and skip. (d) Update the usage/comment header
  (`scripts/sync.sh:3-11`) to mention hooks + settings.
- Mirror: `scripts/sync.sh:36-84`
- Validate: `bash -n scripts/sync.sh`; manual `SYNC_REPO_DIR=. CLAUDE_HOME=$(mktemp -d) bash scripts/sync.sh --dry-run` prints hook link + settings-wire plan and creates nothing.

### Task 4: Extend sync.test.sh
- File: `scripts/sync.test.sh` (UPDATE)
- Implement: extend `setup_fixture` (`:31-54`) to add `$REPO/.claude/hooks/{validate_gate.py,security_guard.py}`.
  Add assertions: (d) dry-run mentions `validate_gate.py` and `security_guard.py` as `would link:`;
  (e) dry-run mentions `would wire hook` for Stop + PreToolUse and leaves no `settings.json`;
  (f) real run creates `$CLAUDE_HOME_DIR/hooks/validate_gate.py` symlink and a `settings.json`
  containing `validate_gate.py` and `security_guard.py`; (g) second real run is idempotent
  (settings.json unchanged — capture sha before/after) and adds no duplicate hook entries;
  (h) `validate.md` (add to command fixture) appears as `would link:` (proves the existing glob
  carries the new command). Keep the existing assert helpers/style.
- Mirror: `scripts/sync.test.sh:15-54`
- Validate: `bash scripts/sync.test.sh` → `All tests passed.`

### Task 5: New /validate command
- File: `.claude/commands/validate.md` (CREATE)
- Implement: frontmatter per Pattern F. Body: a Phase-2 command that (1) resolves the plan via a
  fixed three-tier contract — **(a)** plan path given → use its E2E section; **(b)** blank → infer
  the plan from the current branch name (`feat/{NN}-{slug}` → `.agents/plans/{slug}.plan.md`, the
  inverse of implement.md's branch convention); **(c)** no plan found → run only `validate.sh` (the
  mechanical gate) and state explicitly "no plan; E2E skipped" rather than inferring E2E from the
  conversation (files are the only durable source — never the chat); (2) runs the
  project's verify commands (CLAUDE.md → Verify commands / `.claude/validate.sh`); (3) runs the
  plan's E2E steps as a checklist (the hard gate relocated from implement); (4) reports
  PASS/FAIL per command + Overall (Pattern G); (5) on PASS, states the tree is ready for human
  review → merge; on FAIL, fix-and-rerun; **(6) when human review surfaces a *problem*, end by
  routing to `/retroactive` in a fresh session** (the System Evolution trigger — Design decision 8 /
  ADR-0010), mirroring how `/implement` hands off here; frame it as surfacing the option, not
  forcing the work (whether to run a retroactive stays judgment). Note the relationship to the
  `Stop` validate gate hook (hook = automatic green-on-stop safety net; `/validate` = the
  deliberate full gate + E2E + human-review entry + the System Evolution handoff). Use NO work-unit
  noun — operate on plan path / branch (Design decision 7).
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
    gate + E2E), then human review; pass → merge, **problem → deterministic handoff to
    `/retroactive`** (the System Evolution trigger, Design decision 8 / ADR-0010 — workflow-routed,
    not a hook). Update the one-line phase summary at `:22-35` accordingly.
  - `CLAUDE.md` PIV Loop section (the numbered Validate item): Validate = own session
    (`/validate`) running full gate + E2E, then human review. Add one lean line under Project
    specifics / Verification-led pointing to the `.claude/validate.sh` convention and the
    validate gate `Stop` hook. Respect the <~2.5k-token budget — keep edits surgical.
  - `CONTEXT.md`: **already written during the alignment session** — the PIV Loop entry now
    reframes Validate as its own session and a new **validate gate** entry was added. Do NOT
    rewrite; only **verify** it is present, internally consistent with the final code, and that
    no stale "checks during Implement" framing remains. (Glossary wording is the deliverable;
    it was authored in the smart zone, not to be re-composed here.)
- Validate: grep the three files for the now-stale phrase "checks already ran during Implement"
  / "automated checks ... run during Implement" → none remain; PIV described consistently as
  three sessions (plan/implement/validate).

### Task 8: ADR-0009
- File: `docs/adr/0009-enforce-validate-gate-by-hook-and-split-validate-step.md` (CREATE)
- Implement: status line `Amends ADR-0005`. Record: (1) split Validate out of /implement into
  `/validate` command + why (dedicated smart-zone session for the full gate + E2E; mirrors the
  demo's separate validate skill but stays a *command* per ADR-0005's interaction-shape rule);
  (2) enforcement via generic `validate_gate` `Stop` hook + its relationship to `/validate` (hook
  = automatic green-on-stop net every session; `/validate` = deliberate full gate + E2E +
  human-review entry); (3) hooks shipped as global machinery in `~/.claude/` with user-scope
  settings merge — the global-scope tradeoff (validate gate fails open; security_guard is a safe
  net whose accepted cost is a blanket global deny of all agent-issued recursive deletes, owner
  runs those by hand; option B "safe-paths allowlist" rejected to avoid forking upstream) accepted; (4) **MCP codebase-search rejected** (sub-agent + grep suffice; demo impl is
  Python-AST-specific, breaks language-agnostic stance); (5) **single "validate" root + the
  `validate.sh` language-agnostic extension**: keep Cole's one root (no "verify" layer — that
  would be a false distinction and fight upstream), and record that the project-supplied
  `.claude/validate.sh` indirection is a deliberate extension of Cole's hardcoded hook, required
  because this repo's hook is global + cross-language (a reader will wonder why this repo adds the
  script layer Cole lacks — that's the answer). Alternatives rejected: keep validate
  in implement; manual settings snippet only; project-scope hooks; a verify-vs-validate two-root
  split; hardcoding commands in the hook like Cole (breaks the global/cross-language invariant);
  an env-var escape hatch (e.g. `VALIDATE_GATE_OFF=1`) to stop on red — rejected because an opt-out
  turns the enforced gate back into a norm, defeating the purpose; the gate is already opt-in per
  project via the presence of `.claude/validate.sh` (fail-open when absent), which is the only
  granularity offered.
- Mirror: `docs/adr/0008-unit-of-work-is-natively-a-github-issue.md` (status/structure)
- Validate: file present; references ADR-0005; no forbidden vocab.

### Task 9: README
- File: `README.md` (UPDATE)
- Implement: Layout block (`:42-61`) — add `.claude/commands/validate.md`, `.claude/hooks/`
  (validate_gate.py, security_guard.py), `examples/hooks/`, and `.claude/validate.sh` (note: not
  synced). Change implement.md description (`:49`) from "+ E2E gate" → "Implement phase";
  add validate.md line. Sync section (`:64-86`) — document that sync.sh also links
  `.claude/hooks/*` and additively wires the hooks block into `~/.claude/settings.json` (with
  `.bak`, idempotent, dry-run, manual-snippet fallback). Add the `.claude/validate.sh`
  convention + global-hook fail-open note. "After syncing" loop (`:98-99`) — insert `/validate`
  into the sequence.
- Validate: read-through; `bash scripts/sync.test.sh` still green; layout matches files on disk.

## Validation
- **Static**: `bash -n scripts/sync.sh scripts/sync.test.sh .claude/validate.sh`;
  `python3 -c "import ast,sys;[ast.parse(open(f).read()) for f in sys.argv[1:]]" .claude/hooks/*.py examples/hooks/*.py`
- **Unit/behavioral**: the `validate_gate.py` and `security_guard.py` stdin fixtures from Task 1.
- **Mechanical gate**: `bash scripts/sync.test.sh` → `All tests passed.` (extended in Task 4).
- **Glossary gate**: `grep -rniE "\b(jira|user story|story)\b" .claude/commands/validate.md docs/adr/0009-*.md` — no loose work-unit usage (Ticket allowed per ADR-0008).

## End-to-end verification (hard gate)
> Do NOT report complete until every step passes.
1. `bash scripts/sync.test.sh` → `All tests passed.`
2. Dry-run into a temp home: `T=$(mktemp -d); SYNC_REPO_DIR=$(pwd) CLAUDE_HOME=$T bash scripts/sync.sh --dry-run`
   → output lists `would link:` for validate_gate.py/security_guard.py + `would wire hook` for
   Stop & PreToolUse; assert `T` has NO `settings.json` and NO `hooks/` (mutated nothing).
3. Real run: `SYNC_REPO_DIR=$(pwd) CLAUDE_HOME=$T bash scripts/sync.sh` → assert symlinks
   `$T/hooks/validate_gate.py`, `$T/hooks/security_guard.py`, `$T/commands/validate.md`, and
   `$T/settings.json` contains both `validate_gate.py` and `security_guard.py`.
4. Idempotency: re-run step 3; assert `$T/settings.json` byte-identical (sha256) and no
   duplicate hook entries.
5. Gate behavior: in a temp project dir with `.claude/validate.sh` that `exit 1`,
   `CLAUDE_PROJECT_DIR=<dir> printf '{}' | python3 .claude/hooks/validate_gate.py` → emits a
   `block` decision; with `exit 0` → silent exit 0; with no validate.sh → silent exit 0.
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
