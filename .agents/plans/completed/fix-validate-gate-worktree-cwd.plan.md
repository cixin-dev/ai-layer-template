# Plan: fix(hooks): validate_gate resolves the session's actual working tree, not CLAUDE_PROJECT_DIR

## Summary
`validate_gate.py` resolves the project exclusively from `CLAUDE_PROJECT_DIR` (`.claude/hooks/validate_gate.py:41-46`) and runs `.claude/validate.sh` with `cwd=project_dir` (`:53-59`). When `/implement` moves all work into a sibling worktree `../{repo-dirname}-{branch}` (`.claude/commands/implement.md:51,60`), the env var still points at the main repo, so the Stop-hook gate validates main's untouched checkout — always green, hence vacuous for exactly the sessions ADR-0009 built it to gate. The fix: prefer the hook payload's `cwd` field (a documented common hook-input field), walk up from it to the nearest directory containing `.claude/validate.sh` (bounded at `$HOME` / filesystem root), run that tree's script with that tree as cwd, and fall back to the existing `CLAUDE_PROJECT_DIR` path when the walk finds nothing. Every fail-open behavior is preserved verbatim. Test-led: a new `scripts/validate_gate.test.sh` (mirroring the `sync.test.sh` harness style) is written first and wired into `.claude/validate.sh`. The synced copy in `~/.claude/hooks/` picks the change up through the existing `sync.sh` copy flow (ADR-0012) — no sync.sh changes needed.

## User Story
As a developer whose `/implement` sessions work in a git worktree, I want the session-end validate gate to run the worktree's `validate.sh` against the worktree, so that a red branch actually blocks session completion instead of the gate green-lighting main's unchanged checkout.

## Metadata
| Field | Value |
|-------|-------|
| Type | BUG_FIX |
| Complexity | MEDIUM |
| Systems affected | `.claude/hooks/validate_gate.py`, `scripts/validate_gate.test.sh` (new), `.claude/validate.sh`, sync flow (verification only) |
| Issue | #14 |

## Scope guard
Do **not** touch `.claude/commands/implement.md` or `.claude/commands/validate.md` — that is Issue #11's territory, owned by another agent running concurrently. `scripts/sync.sh`, `scripts/unsync.sh` and their tests need **no code changes** (see Task 4); only run them to prove they stay green.

## Current behavior (exact reference)

Resolution and invocation — the bug:

```python
# SOURCE: .claude/hooks/validate_gate.py:41-49
project_dir = os.environ.get("CLAUDE_PROJECT_DIR", "")
if not project_dir:
    print("[validate-gate] CLAUDE_PROJECT_DIR not set; skipping", file=sys.stderr)
    sys.exit(0)

validate_sh = Path(project_dir) / ".claude" / "validate.sh"
if not validate_sh.is_file():
    print(f"[validate-gate] no .claude/validate.sh in {project_dir}; skipping", file=sys.stderr)
    sys.exit(0)
```

```python
# SOURCE: .claude/hooks/validate_gate.py:53-59
result = subprocess.run(
    ["bash", str(validate_sh)],
    capture_output=True, text=True,
    cwd=project_dir,
    timeout=timeout,
)
```

Fail-open paths that MUST survive unchanged (all `sys.exit(0)`):
1. Unparsable stdin — `.claude/hooks/validate_gate.py:33-36`
2. `stop_hook_active` true (loop guard) — `:38-39`
3. `CLAUDE_PROJECT_DIR` unset — `:42-44` (becomes "no tree resolved at all")
4. No `.claude/validate.sh` in the resolved dir — `:47-49`
5. Timeout (`VALIDATE_GATE_TIMEOUT`, default 120s) — `:60-62`
6. Any other execution error — `:63-65`

Blocking is signaled by printing `{"decision": "block", "reason": ...}` to **stdout** and still exiting 0 (`:67-74`) — tests must assert on stdout content, not exit codes.

## Patterns to Follow

### Hook payload `cwd` field
All Claude Code hook events receive common stdin fields including `cwd` — "Current working directory when the hook is invoked" (code.claude.com/docs/en/hooks, verified 2026-06-13; the repo itself does not document the payload — see Risks). Existing hooks already parse the payload dict the same way:

```python
# SOURCE: .claude/hooks/validate_gate.py:32-39
data: dict = json.load(sys.stdin)
...
if data.get("stop_hook_active"):
    sys.exit(0)
```

### Bash test harness style (the repo's only test convention)
Helpers + failure counter + tmpdir fixture + trap cleanup:

```bash
# SOURCE: scripts/sync.test.sh:7-21
TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT
...
FAILURES=0
assert_contains() {
  local output="$1" pattern="$2" msg="$3"
  if ! printf '%s' "$output" | grep -qF "$pattern"; then
    echo "FAIL: $msg"
    FAILURES=$((FAILURES + 1))
  fi
}
```

Per-test reset via a `setup_fixture`-style function (`scripts/sync.test.sh:63-91`), final summary + `exit $FAILURES` (`scripts/sync.test.sh:270-276`). Test files are executable (`chmod +x`, cf. commit 1ab07f6).

### Verify-bundle wiring
```bash
# SOURCE: .claude/validate.sh:1-5
#!/usr/bin/env bash
set -euo pipefail
dir="$(dirname "$0")/../scripts"
bash "$dir/sync.test.sh"
bash "$dir/unsync.test.sh"
```

### Sync flow (why no sync.sh change is needed)
`sync.sh` copies every file under `.claude/hooks/` into `~/.claude/hooks/` and refreshes stale copies via `cmp -s` on each run (`scripts/sync.sh:79-105` `copy_item`, invoked at `:127-135`). ADR-0012 explicitly accepts drift-until-next-sync (`docs/adr/0012-hooks-copied-not-symlinked-for-nfs-resilience.md:25-29`). The sync tests use content-agnostic fixture hooks (`scripts/sync.test.sh:80-82` just `touch` them), so hook-content changes cannot break them.

## Design

New resolution order in `validate_gate.py` `main()` (replacing lines 41-49):

1. Read `data.get("cwd")`. If present and an existing directory, walk `[cwd, *cwd.parents]`; **stop the walk (without checking) when the candidate is `Path.home()` or the filesystem root**; return the first candidate containing `.claude/validate.sh`.
   - The `$HOME` bound exists because `~/.claude` is Claude Code's own config dir, not a project — a stray `~/.claude/validate.sh` must never become a global gate.
   - The walk-up (rather than checking `cwd` only) is what satisfies "session ending **inside** a worktree": the shell may sit in a subdirectory at Stop time.
2. If the walk yields nothing (no `cwd` in payload, cwd not a dir, or no `validate.sh` found), fall back to `CLAUDE_PROJECT_DIR` exactly as today, including the two existing skip messages (`:43`, `:48`).
3. Run the resolved tree's `.claude/validate.sh` with `cwd=<resolved tree>` — subprocess call, timeout, output trimming, and block JSON all unchanged (`:51-74`).

Behavioral consequences:
- Main-repo session: `cwd` == project root → walk finds the same `validate.sh` `CLAUDE_PROJECT_DIR` would → byte-identical behavior (acceptance criterion 2).
- Worktree session: walk finds the worktree's `validate.sh` and runs it there → red branch blocks (acceptance criterion 1).
- Non-harness directory: walk finds nothing → fall back → today's behavior (criteria 3).

Sketch (final shape up to the implementer; keep the flat style of the existing file — no new abstractions beyond one helper):

```python
def resolve_tree(data: dict) -> "Path | None":
    """Nearest ancestor of the payload cwd that contains .claude/validate.sh."""
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
```

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `scripts/validate_gate.test.sh` | CREATE | Bash test harness for the hook: worktree cwd, main-repo cwd, subdir walk-up, fallback, all fail-open paths |
| `.claude/hooks/validate_gate.py` | UPDATE | Prefer payload `cwd` (bounded walk-up) over `CLAUDE_PROJECT_DIR`; run validate.sh with the resolved tree as cwd |
| `.claude/validate.sh` | UPDATE | Add `bash "$dir/validate_gate.test.sh"` so the gate's own tests join the verify bundle |

## Test cases (write these FIRST — Task 1)

Fixture helper `make_tree <dir> <exit_code>` creates `<dir>/.claude/validate.sh` that appends a marker line to `$TMPDIR_ROOT/ran.log` (proves *which* tree's script executed) and exits `<exit_code>`. Invoke the hook under test as:

```bash
printf '%s' "$payload_json" | CLAUDE_PROJECT_DIR="$MAIN" python3 "$HOOK" 2>"$stderr_file"
```

(`HOOK` = the repo's `.claude/hooks/validate_gate.py`; use `env -u CLAUDE_PROJECT_DIR` for the unset cases. The hook always exits 0 — assert on stdout/stderr/marker, not exit codes.)

| # | Case | Setup | Assert |
|---|------|-------|--------|
| a | **Worktree cwd wins** (the bug) | `MAIN` green, `WORKTREE` red; payload `{"cwd": "$WORKTREE"}`; `CLAUDE_PROJECT_DIR=$MAIN` | stdout contains `"decision": "block"`; `ran.log` shows worktree marker, not main's |
| b | **Main-repo green unchanged** | `MAIN` green; payload cwd = `$MAIN`; env = `$MAIN` | stdout empty (no block); main marker ran |
| c | **Main-repo red still blocks** (regression) | `MAIN` red; payload cwd = `$MAIN`; env = `$MAIN` | stdout contains `"decision": "block"` |
| d | **Subdir of worktree** (walk-up) | `WORKTREE` red; payload `{"cwd": "$WORKTREE/src/deep"}`; env = `$MAIN` (green) | block; worktree marker ran |
| e | **No `cwd` in payload → env fallback** | payload `{}` (valid JSON, no cwd); `MAIN` red; env = `$MAIN` | block (today's path preserved) |
| f | **cwd tree has no validate.sh → env fallback** | payload cwd = bare dir (no `.claude/` anywhere up to `/tmp` root); `MAIN` red; env = `$MAIN` | block via fallback |
| g | **Fail open: nothing resolvable** | payload cwd = bare dir; `env -u CLAUDE_PROJECT_DIR` | exit 0, no stdout block, stderr mentions skipping |
| h | **Fail open: unparsable stdin** | `echo 'not json' \| python3 "$HOOK"` | exit 0, no block, stderr `Could not parse` |
| i | **Fail open: stop_hook_active** | `{"stop_hook_active": true, "cwd": "$WORKTREE"}` with red worktree | exit 0, no block, `ran.log` absent (script never ran) |
| j | **Fail open: timeout** | `WORKTREE` validate.sh sleeps 5; `VALIDATE_GATE_TIMEOUT=1`; payload cwd = `$WORKTREE` | exit 0, no block, stderr `timed out` |

Note for (f)/(g): tmpdir fixtures live under `/tmp/...`, outside `$HOME`, so the walk terminates at `/` (`candidate == candidate.parent`) without ever finding a stray `validate.sh` — no `$HOME` interference in tests.

## Tasks

### Task 1: Create the failing test harness
- File: `scripts/validate_gate.test.sh`
- Action: CREATE (executable, `chmod +x` — cf. commit 1ab07f6 making test scripts executable)
- Implement: harness mirroring `scripts/sync.test.sh:7-29` (tmpdir + trap, `FAILURES`, `assert_contains`/`assert_not_contains`; add `assert_file_exists`/`assert_file_not_exists` from `scripts/sync.test.sh:31-45` for the `ran.log` marker checks), `make_tree` fixture helper, then tests (a)–(j) above. Resolve `HOOK="$(dirname "$0")/../.claude/hooks/validate_gate.py"`.
- Mirror: `scripts/sync.test.sh:7-29,63-91,270-276`
- Validate: `bash scripts/validate_gate.test.sh` → tests (a) and (d) FAIL against the current hook (red proves the tests bite); (b),(c),(e)–(j) already pass (they exercise preserved behavior).

### Task 2: Fix the hook
- File: `.claude/hooks/validate_gate.py`
- Action: UPDATE
- Implement: add the bounded walk-up resolver (Design section); replace lines 41-49 so the payload-cwd tree is preferred and `CLAUDE_PROJECT_DIR` is the fallback with its existing messages; pass the resolved tree to `subprocess.run(..., cwd=<resolved>)` at lines 53-59. Touch nothing else — `trim_output`, timeout handling, and the block-JSON emission stay byte-identical.
- Mirror: `.claude/hooks/validate_gate.py:31-74` (existing flat structure), `examples/hooks/stop_validate.py:35-44` (payload-parsing idiom)
- Validate: `bash scripts/validate_gate.test.sh` → all tests pass.

### Task 3: Wire the new test into the verify bundle
- File: `.claude/validate.sh`
- Action: UPDATE — append `bash "$dir/validate_gate.test.sh"` after the existing two lines.
- Mirror: `.claude/validate.sh:4-5`
- Validate: `bash .claude/validate.sh` → all three suites green.

### Task 4: Prove the sync flow carries the fix (no code changes)
- Files: none (verification task)
- Implement: run `bash scripts/sync.test.sh` and `bash scripts/unsync.test.sh` — both must stay green with zero modifications (fixtures are content-agnostic: `scripts/sync.test.sh:80-82`; `unsync.sh` removes hooks by name with a `cmp` warning, `scripts/unsync.sh:85-106` — neither inspects hook internals). Optionally `SYNC_REPO_DIR=<worktree> CLAUDE_HOME=$(mktemp -d) bash scripts/sync.sh` to watch `copied: .../validate_gate.py` refresh a stale copy.
- Validate: both suites exit 0.
- **Post-merge operational step (record in the implement report's follow-ups, do not run from the worktree):** after the PR merges and main is pulled, run `bash scripts/sync.sh` from the **main checkout** so `~/.claude/hooks/validate_gate.py` is refreshed (`scripts/sync.sh:127-135` + ADR-0012's drift-refresh contract). Running the real sync from the worktree would point skill/command symlinks at a path that disappears when the worktree is removed.

### Task 5: Record the retroactive output
- Files: the implement report (Phase 4 artifact, `.agents/reports/` per the implement flow) — no AI-Layer doc edits needed.
- Implement: state which AI Layer dimension changed and why: **the global-machinery hook itself** (the enforcement floor of ADR-0009) — `validate_gate.py`'s `CLAUDE_PROJECT_DIR` resolution predates the worktree convention, so the floor went vacuous when `/implement` adopted worktrees; the fix re-anchors the gate to the session's actual tree. Note that ADR-0009 (intent: enforced floor every session) and ADR-0012 (copy mechanism) remain accurate as written, and `CONTEXT.md:143-152`'s glossary entry ("runs the project's `.claude/validate.sh`") stays correct — "the project" now resolves to the session's working tree. No new ADR: no decision is reversed, only an implementation gap closed.

## Validation
```bash
bash scripts/validate_gate.test.sh   # new suite: (a)–(j) green
bash scripts/sync.test.sh            # unchanged, green
bash scripts/unsync.test.sh          # unchanged, green
bash .claude/validate.sh             # full bundle (now includes the new suite)
```
End-to-end (manual, in /validate phase): in a scratch worktree with a deliberately red `validate.sh`, end a session started/working there and confirm the Stop hook blocks with the worktree's failure output; repeat in the main repo to confirm unchanged behavior. After merge: `bash scripts/sync.sh` from main checkout, then `cmp .claude/hooks/validate_gate.py ~/.claude/hooks/validate_gate.py` shows identical files.

## Risks & Assumptions
1. **Stop-payload `cwd` semantics (explicit assumption).** The repo nowhere documents the hook stdin payload; the official docs (code.claude.com/docs/en/hooks, checked 2026-06-13) list `cwd` as a common field — "current working directory when the hook is invoked" — but do not state whether it tracks the Bash tool's persistent shell directory after the agent `cd`s into a worktree, or only the session's launch directory. **Assumption: it reflects the session's effective working directory at Stop time.** If that assumption is wrong for cd-style worktree entry, the fix degrades gracefully to today's behavior (fallback path — never worse) and still fully fixes sessions *launched* inside the worktree. Mitigation: the /validate E2E step above empirically confirms it; if `cwd` proves static, file a follow-up issue (e.g. derive the tree from the transcript or last shell cwd) rather than widening this change.
2. **Walk-up overreach.** Ascending from `cwd` could in principle hit an unrelated ancestor's `.claude/validate.sh`. Bounded by stopping at `$HOME`/filesystem root; in practice `validate.sh` only exists at project roots, and the worktree convention (`../{repo-dirname}-{branch}`, `.claude/commands/implement.md:60`) keeps worktrees siblings of the repo, sharing a script-less parent.
3. **`~/.claude` must never match.** Handled by breaking the walk *before* checking `Path.home()` (a project checked out at exactly `$HOME` falls back to `CLAUDE_PROJECT_DIR` — acceptable edge).
4. **Self-gating during implementation.** The installed `~/.claude/hooks/validate_gate.py` is the *old* copy while this change is being implemented in a worktree, so the implementing session's own Stop gate is still vacuous — exactly the bug; the new suite + per-task validation cover it until the post-merge sync.

## Acceptance Criteria
- [ ] All tasks completed
- [ ] Test (a): session ending inside a worktree runs *that worktree's* `validate.sh`; red blocks with `"decision": "block"`
- [ ] Tests (b),(c): main-repo sessions behave exactly as before (green passes, red blocks)
- [ ] Tests (g)–(j): all fail-open paths preserved (no validate.sh anywhere, unparsable stdin, `stop_hook_active`, timeout)
- [ ] `bash .claude/validate.sh` green, including unchanged `sync.test.sh` / `unsync.test.sh`
- [ ] No edits to `scripts/sync.sh`, `scripts/unsync.sh`, `implement.md`, `validate.md`
- [ ] Post-merge `scripts/sync.sh` refresh recorded as a follow-up; retroactive output (dimension: global-machinery hook; why: resolution predates worktree convention) recorded in the implement report
