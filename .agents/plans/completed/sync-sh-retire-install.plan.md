# Plan: sync.sh + retire install.sh + dry-run tests

## Summary

Replace the copy-per-project `install.sh` with a per-item symlink installer `sync.sh` that
mounts this repo's `.claude/skills/*` and `.claude/commands/*.md` into `~/.claude/` via
symlinks. The script discovers owned items dynamically (no hardcoded list), is idempotent,
refuses to clobber real files, leaves all upstream symlinks untouched, and supports
`--dry-run`. A self-contained bash assertion test `sync.test.sh` drives the script against
fixture directories and is the PIV validate gate.

## User Story

As a developer I want a `sync.sh` that symlinks each skill/command this repo owns into
`~/.claude/` so that editing the machinery here upgrades every repo at once with no drift.

## Metadata

| Field | Value |
|-------|-------|
| Type | NEW + BUG_FIX (retire install.sh) |
| Complexity | LOW |
| Systems affected | `scripts/`, test contract |
| Ticket | 01 |

## Key Decisions (ticket overrides PRD where they diverge)

- **No removal map.** ADR-0008 retired the `to-tickets`→removes-`to-issues` fork. The ticket
  is explicit: `sync.sh` carries no removal map and leaves every upstream symlink untouched.
  PRD story 18 (remove superseded upstream symlinks) is superseded by the ticket.
- **Dynamic discovery.** Iterate `$REPO_DIR/.claude/skills/*/` dirs and
  `$REPO_DIR/.claude/commands/*.md` files — no hardcoded list — so new items are picked up
  automatically.
- **Testing seam.** `SYNC_REPO_DIR` env var overrides the repo root; `CLAUDE_HOME` env var
  overrides `~/.claude`. Both default to natural values; the test sets both to temp dirs.
- **Command symlink names keep `.md` extension.** Claude Code reads `~/.claude/commands/*.md`,
  so the symlink at the target must preserve the filename including extension.

## Patterns to Follow

### install.sh flag parsing and note() function
```bash
# SOURCE: scripts/install.sh:15-55
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) ...
  esac
done

note() { echo "[install] $*"; }   # sync.sh uses [sync] prefix

if [ "$DRY_RUN" -eq 1 ]; then
  note "DRY RUN — no changes will be made"
fi
```

### install.sh dry-run line style
```bash
# SOURCE: scripts/install.sh:80-87
# "would copy: $rel" (sync.sh mirrors as "would link: $dst -> $src")
if [ "$DRY_RUN" -eq 1 ]; then
  note "would copy: $rel"
else
  cp "$src" "$dst"
  note "copied: $rel"
fi
```

### install.sh REPO_DIR derivation
```bash
# SOURCE: scripts/install.sh:46
SRC="$(cd "$(dirname "$0")/.." && pwd)"
# sync.sh mirrors this for REPO_DIR, plus adds SYNC_REPO_DIR override for testing
```

## Files to Change

| File | Action | Purpose |
|------|--------|---------|
| `scripts/sync.sh` | CREATE | Per-item symlink installer with --dry-run |
| `scripts/sync.test.sh` | CREATE | Self-contained bash assertion test (PIV gate) |
| `scripts/install.sh` | DELETE | Retired — copy-per-project path must not survive |

## Tasks

### Task 1: Create `scripts/sync.sh`

- **File:** `scripts/sync.sh`
- **Action:** CREATE
- **Implement:**

  ```bash
  #!/usr/bin/env bash
  set -euo pipefail

  # Symlink each owned skill/command into ~/.claude/{skills,commands}/.
  # Owned items are discovered dynamically from this repo's .claude/ tree.
  #
  # Usage:
  #   sync.sh [--dry-run]
  #
  #   --dry-run   Print what would happen; change nothing.
  #   -h|--help   Show this help.

  DRY_RUN=0

  usage() {
    sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'
  }

  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) DRY_RUN=1; shift ;;
      -h|--help) usage; exit 0 ;;
      --) shift; break ;;
      -*) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
      *) echo "error: unexpected argument: $1" >&2; usage >&2; exit 2 ;;
    esac
  done

  # SYNC_REPO_DIR allows tests to point the script at a fixture repo.
  REPO_DIR="${SYNC_REPO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
  # CLAUDE_HOME allows tests to redirect ~/.claude to a temp dir.
  CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"

  note() { echo "[sync] $*"; }

  if [ "$DRY_RUN" -eq 1 ]; then
    note "DRY RUN — no changes will be made"
  fi

  # Ensure target dirs exist (real run only).
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/commands"
  fi

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

  # Skills: each subdirectory under .claude/skills/
  skills_src="$REPO_DIR/.claude/skills"
  if [ -d "$skills_src" ]; then
    for skill_dir in "$skills_src"/*/; do
      [ -d "$skill_dir" ] || continue
      name="$(basename "${skill_dir%/}")"
      link_item "$skills_src/$name" "$CLAUDE_DIR/skills/$name"
    done
  fi

  # Commands: each .md file under .claude/commands/
  commands_src="$REPO_DIR/.claude/commands"
  if [ -d "$commands_src" ]; then
    for cmd_file in "$commands_src"/*.md; do
      [ -f "$cmd_file" ] || continue
      name="$(basename "$cmd_file")"
      link_item "$commands_src/$name" "$CLAUDE_DIR/commands/$name"
    done
  fi
  ```

- **Mirror:** `scripts/install.sh:15-55` (flag parsing), `scripts/install.sh:51` (note()),
  `scripts/install.sh:46` (REPO_DIR derivation)
- **Validate:** `bash -n scripts/sync.sh` (syntax check), then `bash scripts/sync.test.sh`

### Task 2: Delete `scripts/install.sh`

- **File:** `scripts/install.sh`
- **Action:** DELETE
- **Implement:** `git rm scripts/install.sh`
- **Validate:** `ls scripts/` — `install.sh` must not appear

### Task 3: Create `scripts/sync.test.sh`

- **File:** `scripts/sync.test.sh`
- **Action:** CREATE
- **Implement:**

  Self-contained bash test. No external framework. Uses `mktemp -d` for fixtures; cleans up
  on exit via `trap`. Sets `SYNC_REPO_DIR` and `CLAUDE_HOME` to temp dirs so the real
  `scripts/sync.sh` runs against fixture data. All assertions count into `FAILURES`; script
  exits non-zero if any fail.

  **Fixture layout:**
  ```
  $TMPDIR/
    repo/
      .claude/
        skills/
          piv-loop/SKILL.md      # placeholder files
          system-evolution/SKILL.md
          tdd-gate/SKILL.md
        commands/
          plan.md
          implement.md
          retroactive.md
    claude_home/
      skills/
        grill-with-docs -> /upstream/placeholder    # upstream symlinks
        to-prd          -> /upstream/placeholder
        grill-me        -> /upstream/placeholder
        to-issues       -> /upstream/placeholder
      commands/
  ```

  **Test case (a) — fresh state:**
  Run `--dry-run` against fixture repo with claude_home having no owned symlinks yet.
  Assert output contains `would link:` for each of: `piv-loop`, `system-evolution`,
  `tdd-gate`, `plan.md`, `implement.md`, `retroactive.md`.

  **Test case (b) — idempotency:**
  Manually create correct symlinks in fixture claude_home (`ln -s $REPO/… $CLAUDE/…`).
  Run `--dry-run` again. Assert output contains **no** `would link:` lines.

  **Test case (c) — upstream safety:**
  Reuse fresh state fixture from (a). Assert output does **not** contain any of:
  `grill-with-docs`, `to-prd`, `grill-me`, `to-issues`.

  **Assertion helpers:**
  ```bash
  FAILURES=0
  assert_contains() {
    local output="$1" pattern="$2" msg="$3"
    if ! printf '%s' "$output" | grep -qF "$pattern"; then
      echo "FAIL: $msg"
      FAILURES=$((FAILURES + 1))
    fi
  }
  assert_not_contains() {
    local output="$1" pattern="$2" msg="$3"
    if printf '%s' "$output" | grep -qF "$pattern"; then
      echo "FAIL: $msg"
      FAILURES=$((FAILURES + 1))
    fi
  }
  ```

  End: `exit $FAILURES` (0 = all pass, >0 = failures).

- **Mirror:** `scripts/install.sh:90-108` (the per-item iteration structure); bash test
  pattern of `FAILURES` counter + `exit $FAILURES`
- **Validate:** `bash scripts/sync.test.sh` — must exit 0

## Validation

```bash
# Syntax check
bash -n scripts/sync.sh
bash -n scripts/sync.test.sh

# Run test suite (PIV gate — must pass before task is complete)
bash scripts/sync.test.sh

# Verify install.sh is gone
ls scripts/
```

## Acceptance Criteria

- [ ] `scripts/sync.sh` exists and is executable bash (`bash -n` passes)
- [ ] `scripts/install.sh` is deleted (git rm'd)
- [ ] `scripts/sync.test.sh` exists and exits 0 (`bash scripts/sync.test.sh`)
- [ ] Test (a): fresh-state dry-run output mentions every owned skill and command
- [ ] Test (b): idempotent dry-run output contains no `would link:` lines
- [ ] Test (c): upstream names (`grill-with-docs`, `to-prd`, `grill-me`, `to-issues`) never
      appear in sync.sh output
- [ ] Owned-items list is dynamic: script has no hardcoded skill/command names
- [ ] Occupied-target policy implemented: real file/dir at target → warn + skip; stale
      symlink → relink
