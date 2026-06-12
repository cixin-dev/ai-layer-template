# Plan: Copy hooks into user scope (NFS-resilient) instead of symlinking

## Summary
`scripts/sync.sh` currently installs the two hooks (`security_guard.py`,
`validate_gate.py`) into `~/.claude/hooks/` as **symlinks** into the NFS share. When NFS is
unmounted, those symlinks dangle, Python can't open them, and **every tool call fails**
(PreToolUse error) plus the Stop hook misfires. This plan changes `sync.sh` to **copy** the
hook files into `~/.claude/hooks/` as real, executable files (issue #3), and — because a
copy-based run also *overwrites* any pre-existing symlink — re-running `sync.sh` on an
already-installed machine replaces the dangling links with real copies, which is the fix for
the installed machine (issue #2). Skills and commands keep their existing symlink behavior;
only hooks change. The symlink→copy switch for hooks reverses ADR-0007's "Symlink, not copy"
decision *for hooks specifically*, so the plan records that reversal in a new ADR-0012 and
flags ADR-0007's Status.

## User Story
As a developer whose `~/.claude/` machinery lives on an NFS share, I want the installed
hooks to be real local files so that a Claude Code session can start and run tools even when
the NFS share is unmounted, instead of every tool call failing on a dangling symlink.

## Metadata
| Field | Value |
|-------|-------|
| Type | BUG_FIX |
| Complexity | MEDIUM |
| Systems affected | `scripts/sync.sh`, `scripts/sync.test.sh`, `docs/adr/` |
| Issue | #3 (primary), #2 (installed-machine fix — same change) |

## Context: why #2 and #3 are one change
- **#3** = fix the *script* so it stops creating symlinks and copies instead.
- **#2** = fix the *already-installed machine* whose hooks are currently symlinks.

The single mechanism that satisfies both: `copy_item` **removes any existing dst (symlink or
stale copy) before copying**. So once `sync.sh` copies instead of links, *re-running it* on
the installed machine drops the dangling symlinks and lays down real files. There is no
separate migration script — "the installed machine needs the same fix" is satisfied by
running the fixed `sync.sh`. The plan encodes #2's acceptance criteria as a dedicated test
(Task 3, test (i)) so the migration path is proven, not assumed.

> Note on *this* dev box: `~/.claude/hooks/` does not currently exist here, so there is no
> live symlink to migrate in this checkout. Do **not** manually mutate `~/.claude/` as part
> of implementation — the deliverable is the script + tests. The installed-machine fix is
> the user later running `scripts/sync.sh`; correctness is proven by the test fixture, which
> simulates the symlink-into-NFS pre-state.

## Patterns to Follow

Current hook-install loop calls `link_item` (to be redirected to a new `copy_item`):
```bash
# SOURCE: scripts/sync.sh (hooks loop, ~lines 89-97)
hooks_src="$REPO_DIR/.claude/hooks"
if [ -d "$hooks_src" ]; then
  for hook_file in "$hooks_src"/*; do
    [ -f "$hook_file" ] || continue
    name="$(basename "$hook_file")"
    link_item "$hooks_src/$name" "$CLAUDE_DIR/hooks/$name"   # → copy_item
  done
fi
```

Existing `link_item` policy block to mirror style/comment density for `copy_item`:
```bash
# SOURCE: scripts/sync.sh (~lines 49-67)
# Link a single owned item. Policy:
#   - already correct symlink → skip (idempotent)
#   - real file/dir (not a symlink) → warn and skip (user data)
#   - absent or stale symlink → link/relink (owned names win)
link_item() {
  local src="$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    return
  fi
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    note "warn: $dst is a real file/directory — skipped"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would link: $dst -> $src"
  else
    ln -sfn "$src" "$dst"
    note "linked: $dst -> $src"
  fi
}
```

settings.json wiring already points at the *installed copy* path — **no change needed**:
```bash
# SOURCE: scripts/sync.sh (~lines 99-101)
SG_CMD="python3 \"$CLAUDE_DIR/hooks/security_guard.py\""
VG_CMD="python3 \"$CLAUDE_DIR/hooks/validate_gate.py\""
```

Test assertion helpers and fixture conventions to mirror for the new test:
```bash
# SOURCE: scripts/sync.test.sh:31-45  (assert_file_exists / assert_file_not_exists)
# SOURCE: scripts/sync.test.sh:64-66  (repo hook fixtures: touch validate_gate.py / security_guard.py)
# SOURCE: scripts/sync.test.sh:98-100 (pre-existing hook symlinks in CLAUDE_HOME fixture)
```

ADR Status-header convention to mirror (partial supersede):
```markdown
# SOURCE: docs/adr/0004-...md:1-5
**Status:** Superseded by ADR-0008 — its worked example (...) is retired:
... The general principle below (...) still stands; only the ... application is reversed.
```

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `scripts/sync.sh` | UPDATE | Add `copy_item`; route the hooks loop through it instead of `link_item`; update the header comment (symlink→ "symlink skills/commands, copy hooks"). |
| `scripts/sync.test.sh` | UPDATE | Switch hook assertions from symlink/"would link" to copy/"would copy"; assert installed hooks are real + executable; add test (i) proving symlink→real-file migration (issue #2). |
| `docs/adr/0012-hooks-copied-not-symlinked-for-nfs-resilience.md` | CREATE | Record the hooks-only reversal of ADR-0007's "Symlink, not copy" and the rationale (catastrophic-vs-graceful failure mode). |
| `docs/adr/0007-...symlink.md` | UPDATE | Add a `**Status:**` line noting hooks are partially superseded by ADR-0012. |

## Tasks

### Task 1: Add `copy_item` and route hooks through it
- File: `scripts/sync.sh`
- Action: UPDATE
- Implement:
  1. Add a `copy_item` function next to `link_item`. Policy (mirror `link_item`'s comment
     style):
     - dst is a **real file** (not a symlink) with contents identical to src (`cmp -s`) →
       `return` (idempotent; produces no output).
     - otherwise (absent, a symlink — including a dangling one — or a stale-content copy) →
       in dry-run print `note "would copy: $dst <- $src"`; in real run
       `rm -f "$dst"` (drops any stale symlink/copy first), `cp "$src" "$dst"`,
       `chmod +x "$dst"`, `note "copied: $dst <- $src"`.
     - Guard ordering matters: test `[ -f "$dst" ] && [ ! -L "$dst" ] && cmp -s "$src" "$dst"`
       — the `! -L` guard ensures a dangling symlink (where `cmp` would error) falls through
       to the copy branch rather than tripping `set -e`.
  2. In the hooks loop, replace `link_item` with `copy_item`.
  3. Update the top-of-file comment (currently "Symlink each owned skill/command/hook …") to
     state that skills/commands are symlinked but **hooks are copied** (real files, so they
     survive an unmounted NFS share). Keep it to one or two lines.
- Mirror: `scripts/sync.sh` `link_item` at ~lines 49-67; hooks loop at ~lines 89-97.
- Validate: `bash scripts/sync.test.sh` (after Task 2/3 land); manual dry-run:
  `SYNC_REPO_DIR=$PWD CLAUDE_HOME=$(mktemp -d) bash scripts/sync.sh --dry-run` shows
  `would copy:` for both hooks and `would link:` for skills/commands.

### Task 2: Update existing hook tests for copy semantics
- File: `scripts/sync.test.sh`
- Action: UPDATE
- Implement:
  - **Test (b) idempotency (~lines 89-106):** after the real run at line 102, hooks are real
    copies. Add an assertion that the second dry-run output contains no `would copy:`
    (`assert_not_contains "$output" "would copy:" "test(b): no 'would copy:' when hooks already real copies"`).
    Leave the existing `would link:` / `would wire hook` assertions intact (skills/commands
    still symlink).
  - **Test (d) (~lines 117-122):** the hook files now appear as `would copy:`, not
    `would link:`. The current asserts only check the filename substrings
    (`validate_gate.py`, `security_guard.py`), which still pass — but update the assertion
    *messages* from "would link:" to "would copy:" for accuracy. `validate.md` stays
    "would link:" (it's a command).
  - **Test (f) (~lines 130-138):** keep `assert_file_exists` for both hooks, and **add**:
    each installed hook is a real file not a symlink (`[ ! -L "$path" ]`) and is executable
    (`[ -x "$path" ]`). Add small helpers `assert_not_symlink` and `assert_executable`
    mirroring the existing `assert_*` helpers (lines 31-45), or inline the
    `if … then echo FAIL; FAILURES=$((FAILURES+1)); fi` pattern already used at lines 144-158.
- Mirror: assertion helpers `scripts/sync.test.sh:31-45`; inline-fail pattern `:144-158`.
- Validate: `bash scripts/sync.test.sh` → `All tests passed.`

### Task 3: Add migration test for the installed machine (issue #2)
- File: `scripts/sync.test.sh`
- Action: UPDATE
- Implement: add **test (i)** after the existing tests. It must:
  1. `setup_fixture` for a clean state, then create a fake "NFS" source dir with hook files
     containing known content, and pre-create `$CLAUDE_HOME_DIR/hooks/{security_guard.py,
     validate_gate.py}` as **symlinks pointing into that fake NFS dir** (simulating the
     current installed state — mirror the symlink fixture at lines 98-100).
  2. Run a real `sync.sh` (`SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" >/dev/null`).
  3. Assert, for each hook, that `$CLAUDE_HOME_DIR/hooks/<hook>`:
     - exists, is **not** a symlink (`[ ! -L ]`),
     - is executable (`[ -x ]`),
     - has contents identical to the **repo** source (`cmp -s "$REPO/.claude/hooks/<hook>"
       "$CLAUDE_HOME_DIR/hooks/<hook>"`) — i.e. it was refreshed from repo source, not left
       pointing at the old NFS path.
  This encodes issue #2's acceptance criteria: dangling-symlink pre-state → real, executable,
  repo-matching files after one `sync.sh` run.
- Mirror: symlink fixture `scripts/sync.test.sh:98-100`; real-run invocation `:132`;
  content/asserts `:141-158`.
- Validate: `bash scripts/sync.test.sh` → `All tests passed.`

### Task 4: Record the decision reversal in ADRs
- File: `docs/adr/0012-hooks-copied-not-symlinked-for-nfs-resilience.md` (CREATE) and
  `docs/adr/0007-sync-machinery-to-user-scope-by-per-item-symlink.md` (UPDATE)
- Action: CREATE + UPDATE
- Implement:
  - **CREATE 0012:** following the prose-ADR style of 0007/0004, state the decision: *hooks*
    are copied as real files into `~/.claude/hooks/`; *skills and commands remain symlinked*.
    Rationale: ADR-0007 accepted symlink fragility deliberately, but did not weigh the hook
    failure mode — skills/commands degrade *gracefully* when a link breaks (a missing skill
    is lazily loaded; a session still starts), whereas a broken **hook** is *catastrophic*:
    PreToolUse fails on every tool call and the session is unusable with NFS down. So the
    resilience/drift trade-off resolves differently for hooks than for skills/commands.
    Note the accepted cost: hook copies can drift from repo source until the next `sync.sh`
    run (mitigated by `copy_item` refreshing on every run via `cmp`). Reference issues #2/#3.
  - **UPDATE 0007:** add a `**Status:**` line near the top (mirror `0004:1-5`):
    "Partially superseded by ADR-0012 — hooks are now copied, not symlinked, for NFS
    resilience; skills and commands remain per-item symlinks as decided here."
- Mirror: `docs/adr/0004-...md:1-5` (Status header), `docs/adr/0007-...md` (prose structure,
  "Alternatives rejected" / "Consequence" sections).
- Validate: ADR renders; numbering is unique (0012 — 0008–0011 already exist).

## Validation
- **Automated gate:** `bash scripts/validate.sh` (which `exec`s `scripts/sync.test.sh`) →
  `All tests passed.` exit 0. This is the same gate the `validate_gate` Stop hook runs.
- **Direct test run:** `bash scripts/sync.test.sh`.
- **Manual dry-run (no mutation):**
  `SYNC_REPO_DIR="$PWD" CLAUDE_HOME="$(mktemp -d)" bash scripts/sync.sh --dry-run`
  → both hooks listed as `would copy:`, skills/commands as `would link:`, hooks as
  `would wire hook`.
- **Manual real run into a throwaway home (proves issue #2/#3 end-to-end):**
  ```bash
  TH="$(mktemp -d)"
  # simulate old install: hook symlinks into the repo (the "NFS share")
  mkdir -p "$TH/hooks"
  ln -s "$PWD/.claude/hooks/security_guard.py" "$TH/hooks/security_guard.py"
  ln -s "$PWD/.claude/hooks/validate_gate.py"  "$TH/hooks/validate_gate.py"
  SYNC_REPO_DIR="$PWD" CLAUDE_HOME="$TH" bash scripts/sync.sh
  # expect: real files, not symlinks, executable
  for h in security_guard.py validate_gate.py; do
    test ! -L "$TH/hooks/$h" && test -x "$TH/hooks/$h" \
      && cmp -s ".claude/hooks/$h" "$TH/hooks/$h" \
      && echo "OK $h" || echo "BAD $h"
  done
  ```
  Both lines print `OK`. (Throwaway dir only — do **not** point `CLAUDE_HOME` at the real
  `~/.claude`.)

## Acceptance Criteria
- [ ] All tasks completed
- [ ] `scripts/sync.sh` copies `security_guard.py` and `validate_gate.py` into
      `~/.claude/hooks/` as real, executable files — never symlinks (#3)
- [ ] Re-running `sync.sh` refreshes hooks from repo source (overwrites stale copies / old
      symlinks) and stays idempotent for `settings.json` entries (#3)
- [ ] After a run, no `~/.claude/hooks/*.py` is a symlink into the NFS share (#2/#3)
- [ ] Test (i) proves a symlink-into-NFS pre-state becomes real, executable, repo-matching
      files after one `sync.sh` run (#2)
- [ ] Skills and commands are untouched (still symlinks); change is surgical to hooks
- [ ] ADR-0012 records the hooks-only copy decision; ADR-0007 Status flags the partial
      supersede
- [ ] `bash scripts/validate.sh` passes with zero failures
- [ ] Follows existing `sync.sh` / `sync.test.sh` patterns
```
