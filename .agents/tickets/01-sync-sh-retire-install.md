---
id: "01"
slug: sync-sh-retire-install
title: sync.sh + retire install.sh + dry-run tests
type: AFK
status: ready-for-agent
blocked_by: []
prd: .agents/prds/phase-1-machinery.prd.md
covers_stories: [16, 17, 18, 19, 20, 21, 22]
---

# sync.sh + retire install.sh + dry-run tests

## What to build

Replace the retired copy-into-project installer with a per-item symlink installer that mounts
this repo's machinery into user scope (`~/.claude/`). Editing the machinery here then upgrades
every repo at once — no per-project copies (ADR-0003, ADR-0007).

`scripts/sync.sh`:

- **Discovers owned items dynamically** — iterates this repo's `.claude/skills/*` and
  `.claude/commands/*` rather than a hardcoded list, so newly added skills/commands are picked
  up automatically and the script needs no edit per new item.
- **Symlinks each owned item, per item**, into `~/.claude/{skills,commands}/`, pointing back
  into this repo's working tree. Per-item (never whole-directory) so coexisting upstream
  (Matt Pocock) symlinks in `~/.claude/` are never clobbered.
- **Symlink, not copy** — a copy reintroduces the drift ADR-0003 kills.
- **Removes superseded upstream symlinks** via a small static map. The only current entry:
  linking `to-tickets` ⇒ remove `~/.claude/skills/to-issues`. The removal fires **only when the
  superseding item actually exists** in this repo, so running sync before `to-tickets` lands
  leaves `to-issues` in place.
- **Idempotent** — re-running converges to the same state (refresh existing links, no
  duplication, no error on already-correct state).
- **Occupied-target policy (refines ADR-0007).** For a name **this repo owns**: refresh the
  symlink to point here regardless of its prior (symlink) target — owned names win, so "edit
  here upgrades everywhere" holds even when a stale/foreign symlink already sits at that name.
  But if the target is a **real file or directory** (not a symlink), refuse and warn — that is
  user data, not a link to reclaim. Names this repo does **not** own are never touched (that is
  the operative meaning of ADR-0007's "never clobber coexisting upstream").
- **`--dry-run`** — prints exactly which links it would create and which upstream symlinks it
  would remove, and mutates nothing. Mirror the retired `install.sh`'s contract ("print what
  would happen; change nothing") and its `[sync] would …` line style.

Delete `scripts/install.sh`: its direction inverts (push-into-project → link-into-global), so
no copy-per-project path survives to drift.

## Acceptance criteria

- [ ] `scripts/sync.sh` exists; `scripts/install.sh` is deleted.
- [ ] A real run symlinks every owned skill/command into `~/.claude/{skills,commands}/`
      pointing back into this repo; coexisting upstream symlinks (`grill-with-docs`, `to-prd`,
      `grill-me`) are untouched.
- [ ] When `to-tickets` exists, a run removes `~/.claude/skills/to-issues`; when it does not,
      `to-issues` is left in place.
- [ ] Re-running `sync.sh` is a no-op against an already-synced state (idempotent).
- [ ] `sync.sh --dry-run` prints the planned create/remove actions and changes nothing on disk.
- [ ] A self-contained bash assertion script `scripts/sync.test.sh` (no external test
      framework — `CLAUDE.md` forbids stack-specific tooling) is runnable as
      `bash scripts/sync.test.sh`, exits non-zero on any failed assertion, and is this
      ticket's PIV **validate gate** (validation gates must be executable, not prose — per
      Cole's `generate-prp.md` "Validation Gates (Must be Executable)" and the KB's stop-hook
      convention).
- [ ] The test drives `sync.sh --dry-run` and asserts on its `[sync] would …` stdout, using
      **fixture directories** for the owned-items source and a fake `~/.claude` target — so the
      test is self-contained and needs neither a real `~/.claude` nor the real `to-tickets`
      skill (keeps this ticket unblocked by Ticket 02; supersession is exercised with a fixture
      `to-tickets`).
- [ ] Test cases cover: (a) fresh state — all owned items planned for linking; (b) supersession
      — `to-issues` planned for removal when `to-tickets` is present; (c) idempotency — dry-run
      against an already-synced state plans no changes; (d) upstream safety — `grill-with-docs` /
      `to-prd` / `grill-me` never appear in the removal plan.

## Blocked by

None - can start immediately.

## Notes

**Two-producer (`to-issues` re-add) is out-of-band.** sync.sh removes the superseded
`to-issues` symlink every run, but re-running `setup-matt-pocock-skills` would re-add it.
sync.sh does **not** guard against this — it is the authority; document "run `sync.sh` last,
after any upstream skill setup." No watch/marker logic (keeps the script simple and
idempotent).

Testing seam is the **dry-run output assertion** (chosen over a temp-HOME integration test);
`--dry-run` mutates nothing, so tests need no real `~/.claude` and leave no residue. Real
mutation is verified manually on first run. Accepted fragility (ADR-0007): the links point into
this repo's NFS working tree; if the repo moves or the mount drops, links break.
