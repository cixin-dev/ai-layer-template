# Plan: unsync.sh teardown script

## Summary
Build `scripts/unsync.sh`, the exact inverse of `scripts/sync.sh`. It discovers the owned
skills/commands/hooks dynamically from this repo's `.claude/` tree (mirroring how `sync.sh`
discovers them), then: removes the owned symlinks from `~/.claude/{skills,commands}/` (only
those that point back into this repo — never user/upstream entries), removes the copied hook
files from `~/.claude/hooks/`, and either restores `~/.claude/settings.json` from its `.bak`
backup or surgically removes the two wired hook entries. It supports `--dry-run` for parity
with `sync.sh`, is idempotent, and exits non-zero with a clear message when a target is in an
unexpected state. A mirrored test file `scripts/unsync.test.sh` is added and wired into the
validate gate.

## User Story
As a developer who installed this AI Layer with `sync.sh`, I want a `unsync.sh` teardown
script so that I can cleanly and safely reverse the install — removing only the machinery this
repo added, leaving my own and upstream `~/.claude/` entries untouched.

## Metadata
| Field | Value |
|-------|-------|
| Type | NEW |
| Complexity | MEDIUM |
| Systems affected | `scripts/` (new script + test), `.claude/validate.sh`, `README.md` |
| Issue | #5 |

## Key design decisions (read before implementing)

**Ownership is what makes teardown safe. The two install mechanisms have two ownership tests:**

1. **Skills & commands are symlinks.** `sync.sh` only ever creates a symlink if the target is
   absent or a stale symlink, and it *skips* real files/dirs (user data) — see
   `scripts/sync.sh:56-71`. So a target is "owned" iff it is a symlink whose `readlink` equals
   the repo source path. unsync removes **only** those. A real file/dir, a symlink pointing
   elsewhere (e.g. upstream `/upstream/placeholder`), or an absent target → leave untouched.

2. **Hooks are real copies, discovered by name.** `sync.sh` copies `security_guard.py` and
   `validate_gate.py` into `~/.claude/hooks/` (`scripts/sync.sh:79-105`). A copy carries no
   backlink to the repo, so ownership is by **name** (the names discovered from the repo's
   `.claude/hooks/` tree), exactly as the issue specifies. unsync removes a hook path that is a
   real file *or* a leftover symlink (pre-issue-#2 installs symlinked hooks). If content differs
   from the repo source, warn ("removing locally-modified hook") but still remove — symmetric
   with `sync.sh`'s warn-then-overwrite policy (`scripts/sync.sh:95-97`). A **directory** at a
   hook path is an unexpected state → print a clear message, do not touch it, exit non-zero.

**settings.json branch selector is `.bak` presence** (per the issue):
- `settings.json.bak` exists → restore it via `mv` (consumes the `.bak`, so a re-run is
  idempotent and finds nothing to do). `sync.sh` writes the `.bak` once, before its first
  modification, and only if `settings.json` already existed (`scripts/sync.sh:221-223`).
- No `.bak` → surgically remove the two entries with `python3`, mirroring the wire-in block
  (`scripts/sync.sh:154-229`) in reverse. **The surgical path must NOT create a `.bak`** — if it
  did, a second run would see that `.bak` (which still contains the hook entries) and "restore"
  the hooks back, breaking idempotency. This is the single most important correctness trap.
- Only write `settings.json` if something actually changed (idempotency).
- `python3` missing or file unparseable → mirror `sync.sh`: warn, print a manual instruction,
  fail open (do not block the file/symlink teardown). This is not an "unexpected target state."

**The hook command strings must match `sync.sh` byte-for-byte** so the surgical removal finds
them. Reconstruct them identically to `scripts/sync.sh:140-142`:
```sh
SETTINGS="$CLAUDE_DIR/settings.json"
SG_CMD="python3 \"$CLAUDE_DIR/hooks/security_guard.py\""
VG_CMD="python3 \"$CLAUDE_DIR/hooks/validate_gate.py\""
```

**Unexpected-state handling:** accumulate into an error counter and keep going (do every safe
removal possible), then `exit $ERRORS` at the end. The only unexpected state in scope is a
directory where a hook file is expected.

**Env-var redirection:** reuse the *same* names `sync.sh` uses — `SYNC_REPO_DIR` (repo root
override) and `CLAUDE_HOME` (the `~/.claude` override) — so the test harness mirrors
`sync.test.sh` and the two scripts share one mental model. See `scripts/sync.sh:32-35`.

## Patterns to Follow

**Arg-parse + scaffolding — mirror near-verbatim, swapping `[sync]`→`[unsync]`:**
```sh
// SOURCE: scripts/sync.sh:16-41
DRY_RUN=0
usage() { sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) echo "error: unexpected argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
REPO_DIR="${SYNC_REPO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"
note() { echo "[unsync] $*"; }
if [ "$DRY_RUN" -eq 1 ]; then note "DRY RUN — no changes will be made"; fi
```

**Discovery loops — mirror the structure, call `unlink_*`/`remove_hook` instead of link/copy:**
```sh
// SOURCE: scripts/sync.sh:107-135
skills_src="$REPO_DIR/.claude/skills"
if [ -d "$skills_src" ]; then
  for skill_dir in "$skills_src"/*/; do
    [ -d "$skill_dir" ] || continue
    name="$(basename "${skill_dir%/}")"
    unlink_owned "$skills_src/$name" "$CLAUDE_DIR/skills/$name"
  done
fi
# commands: for cmd_file in "$commands_src"/*.md  → unlink_owned "$commands_src/$name" "$CLAUDE_DIR/commands/$name"
# hooks:    for hook_file in "$hooks_src"/*       → remove_hook  "$CLAUDE_DIR/hooks/$name"
```

**Owned-symlink ownership check — invert `link_item`:**
```sh
// SOURCE: scripts/sync.sh:56-71 (link_item) — invert to remove only the symlink we created
unlink_owned() {
  local src="$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then note "would remove symlink: $dst"
    else rm -f "$dst"; note "removed symlink: $dst"; fi
    return
  fi
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then note "skip: $dst is a real file/directory — not ours"; return; fi
  # absent, or symlink pointing elsewhere (upstream/user) → leave untouched, no-op
}
```

**settings surgical-removal — invert the wire-in `python3` heredoc (`scripts/sync.sh:154-229`).**
Reconstruct `data`, then for `hooks["PreToolUse"]` drop any hook entry whose `command == sg_cmd`
(and any flat block whose top-level `command == sg_cmd`); same for `hooks["Stop"]` with `vg_cmd`.
Drop a block when its `hooks` list becomes empty; drop the `PreToolUse`/`Stop` key when its list
becomes empty; drop `hooks` when it becomes empty. Track a `changed` flag; only `write_text`
(`json.dumps(data, indent=2) + "\n"`) when `changed` and not `dry_run`. On `dry_run`, print
`[unsync] would unwire hook: ...` for each removal. Reuse the same parse-failure fail-open
pattern as `scripts/sync.sh:162-173`. **Do not create a `.bak` here.**

**Test harness — copy assertion helpers + `setup_fixture` verbatim from `sync.test.sh`:**
```sh
// SOURCE: scripts/sync.test.sh:1-91 (helpers + setup_fixture are reusable as-is)
```

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `scripts/unsync.sh` | CREATE | The teardown script (inverse of `sync.sh`). |
| `scripts/unsync.test.sh` | CREATE | Mirrored test suite for `unsync.sh`. |
| `.claude/validate.sh` | UPDATE | Run both `sync.test.sh` and `unsync.test.sh` in the gate. |
| `README.md` | UPDATE | Document `unsync.sh` alongside `sync.sh` (tree + usage). |

## Tasks
Ordered, atomic, each independently verifiable.

### Task 1: Create `scripts/unsync.sh`
- File: `scripts/unsync.sh`
- Action: CREATE
- Implement: A header comment block (lines 3-10 form the `usage` body via the `sed` trick) that
  describes the teardown and `--dry-run`/`--help`. `set -euo pipefail`. Arg-parse + scaffolding
  mirroring `scripts/sync.sh:16-41` with `[unsync]` prefix and an `ERRORS=0` counter. Define:
  - `unlink_owned(src,dst)` — per the ownership pattern above (skills/commands).
  - `remove_hook(dst)` — absent → no-op; symlink → remove (dry-run: "would remove"); real file →
    `cmp -s` against the repo source (passed in or recomputed) and warn if different, then remove;
    directory → `note "error: $dst is a directory — unexpected state"` and `ERRORS=$((ERRORS+1))`,
    no removal. Pass the repo source path so the content check can run. (Signature may be
    `remove_hook(src,dst)` to enable `cmp -s "$src" "$dst"`.)
  - Discovery loops mirroring `scripts/sync.sh:107-135` calling the above.
  - settings.json handling: compute `SETTINGS`/`SG_CMD`/`VG_CMD` exactly as `scripts/sync.sh:140-142`.
    If `"$SETTINGS.bak"` exists → dry-run: `note "would restore: $SETTINGS from $SETTINGS.bak"`;
    real: `mv "$SETTINGS.bak" "$SETTINGS"; note "restored: $SETTINGS from backup"`. Else, if
    `python3` available → run the inverse surgical-removal heredoc (no `.bak` written); else warn
    + manual instruction + fail open (mirror `scripts/sync.sh:144-152`).
  - End with `exit $ERRORS`.
- Mirror: `scripts/sync.sh:16-41`, `:56-71`, `:107-135`, `:140-173`, `:200-229`
- Validate: `bash scripts/unsync.sh --help` prints usage; `bash scripts/unsync.sh --bad` exits 2.

### Task 2: Create `scripts/unsync.test.sh`
- File: `scripts/unsync.test.sh`
- Action: CREATE
- Implement: Copy the assertion helpers and `setup_fixture` from `scripts/sync.test.sh:1-91`
  (point `UNSYNC_SH="$SCRIPT_DIR/unsync.sh"` and keep `SYNC_SH` for the install step). Each test
  first installs with `sync.sh` (real run) to create the state, then exercises `unsync.sh`:
  - **(a) dry-run is read-only:** after a real `sync.sh`, run `unsync.sh --dry-run`; assert output
    contains `would remove` for an owned skill/command and a hook, and `would restore`/`would
    unwire`; assert the symlinks, hook files, and `settings.json` still exist afterward.
  - **(b) idempotency:** run `unsync.sh` twice (real); second run produces no `removed`/`unwired`
    lines and exits 0; owned targets already gone.
  - **(c) upstream safety:** the upstream symlinks (`grill-with-docs`, `to-prd`, `grill-me`,
    `to-issues`) are never mentioned and still exist after a real `unsync.sh`.
  - **(d) removes owned symlinks:** after real `unsync.sh`, `assert_file_not_exists` for each owned
    skill/command path; `assert_file_exists` for the upstream symlinks.
  - **(e) removes hook copies:** `assert_file_not_exists` for both hooks after real `unsync.sh`.
  - **(f) restore from `.bak`:** pre-create `settings.json` with a user key (e.g.
    `{"theme":"dark"}`) *before* `sync.sh` (so `sync.sh` writes a `.bak`), run `sync.sh`, then
    `unsync.sh`; assert `settings.json` no longer references `security_guard.py`/`validate_gate.py`,
    still contains `theme`, and `settings.json.bak` is gone.
  - **(g) surgical removal (no `.bak`):** fresh fixture (no pre-existing `settings.json` → `sync.sh`
    writes no `.bak`), run `sync.sh` then `unsync.sh`; assert `grep -c security_guard.py == 0` and
    `grep -c validate_gate.py == 0`; assert no `settings.json.bak` was created; run `unsync.sh`
    again and assert it exits 0 and still references neither hook (idempotent, no resurrection).
  - **(h) unexpected state:** replace an installed hook with a directory
    (`rm + mkdir "$CLAUDE_HOME_DIR/hooks/validate_gate.py"`), run `unsync.sh`, capture exit code;
    assert non-zero and output contains a clear message; assert the other hook was still removed.
  - **(i) preserve user real file:** put a real (non-symlink) file at an owned command path before
    `unsync.sh`; assert it still exists after (not removed).
  - End with the `FAILURES`/exit pattern from `scripts/sync.test.sh:270-277`.
- Mirror: `scripts/sync.test.sh:1-91`, `:93-149`, `:270-277`
- Validate: `bash scripts/unsync.test.sh` prints `All tests passed.` and exits 0.

### Task 3: Wire `unsync.test.sh` into the validate gate
- File: `.claude/validate.sh`
- Action: UPDATE
- Implement: Replace the single `exec bash .../sync.test.sh` with a runner that executes both test
  files (drop `exec` so both run; `set -euo pipefail` already stops on the first failure):
  ```sh
  #!/usr/bin/env bash
  set -euo pipefail
  dir="$(dirname "$0")/../scripts"
  bash "$dir/sync.test.sh"
  bash "$dir/unsync.test.sh"
  ```
- Mirror: existing `.claude/validate.sh`
- Validate: `bash .claude/validate.sh` runs both suites and exits 0.

### Task 4: Document `unsync.sh` in `README.md`
- File: `README.md`
- Action: UPDATE
- Implement: In the repo-tree block (around `README.md:70-71`) add `unsync.sh` and
  `unsync.test.sh` lines next to `sync.sh`. In the usage section (around `README.md:81-87`) add a
  short note that `bash scripts/unsync.sh [--dry-run]` reverses the install, removing only
  repo-owned symlinks/hooks and restoring/cleaning `settings.json`. Keep it brief and matched to
  the existing style.
- Mirror: `README.md:70-71`, `:81-87`
- Validate: `grep -n unsync README.md` shows the new references.

## Validation
- **Unit/gate:** `bash scripts/unsync.test.sh` → `All tests passed.`; `bash .claude/validate.sh`
  → both suites pass (exit 0). The `validate_gate` `Stop` hook runs `.claude/validate.sh`
  automatically on session end.
- **Lint/exec:** `bash -n scripts/unsync.sh` (syntax); `bash scripts/unsync.sh --help` (usage);
  `bash scripts/unsync.sh --nope` exits 2.
- **End-to-end (manual, against a temp HOME):**
  ```sh
  T=$(mktemp -d)
  SYNC_REPO_DIR="$PWD" CLAUDE_HOME="$T" bash scripts/sync.sh        # install
  SYNC_REPO_DIR="$PWD" CLAUDE_HOME="$T" bash scripts/unsync.sh --dry-run  # preview, no change
  SYNC_REPO_DIR="$PWD" CLAUDE_HOME="$T" bash scripts/unsync.sh      # teardown
  ls -la "$T/skills" "$T/commands" "$T/hooks"; cat "$T/settings.json" 2>/dev/null  # clean
  SYNC_REPO_DIR="$PWD" CLAUDE_HOME="$T" bash scripts/unsync.sh; echo "exit=$?"  # idempotent, exit 0
  rm -rf "$T"
  ```

## Acceptance Criteria
- [ ] All tasks completed
- [ ] Checks pass with zero errors (`bash .claude/validate.sh` exits 0, both suites)
- [ ] Follows existing patterns (arg-parse, discovery loops, ownership checks, test harness mirror `sync.sh`/`sync.test.sh`)
- [ ] `unsync.sh --dry-run` prints every action and changes nothing
- [ ] Removes only symlinks pointing into this repo; upstream/user entries untouched
- [ ] Removes copied hook files from `~/.claude/hooks/`
- [ ] Restores `settings.json` from `.bak` if present; otherwise removes only the two hook entries
- [ ] Idempotent — safe to run repeatedly (no hook-entry resurrection on the surgical path)
- [ ] Exits non-zero with a clear message on an unexpected target state (directory at a hook path)
