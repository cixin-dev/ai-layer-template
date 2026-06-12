# Sync machinery to user scope by per-item symlink; install.sh retires

**Status:** Partially superseded by ADR-0012 — hooks are now copied, not symlinked, for NFS
resilience; skills and commands remain per-item symlinks as decided here.

ADR-0003 declared that this repo's machinery is synced to user scope (`~/.claude/`) and that
`install.sh` retires — but left the **mechanism** unspecified. This ADR settles it.

Existing setup: upstream (Matt Pocock) skills already coexist in `~/.claude/skills/` as
**symlinks** pointing back to their source repos on NFS. User scope is therefore already "a
set of symlinks, each pointing at the repo that owns it."

**Decision:** sync via a per-item symlink script (`sync.sh`). It does two things:

1. **Symlinks each skill/command this repo owns** into `~/.claude/{skills,commands}/`,
   item by item.
2. **Removes the specific upstream symlinks that this repo's forks supersede** — e.g. when it
   links `to-tickets`, it removes `~/.claude/skills/to-issues` (the mattpocock symlink that
   `to-tickets` replaces under ADR-0004).

**Symlink, not copy.** A copy reintroduces the per-copy drift ADR-0003 set out to kill;
a symlink means editing the machinery here upgrades every repo instantly ("edit here →
upgrades everyone"). It is also consistent with how upstream skills already mount.

**Per-item, not whole-directory.** `~/.claude/skills/` must hold *both* this repo's skills
*and* coexisting upstream skills; symlinking the whole `skills/` directory would clobber
upstream. So the script iterates only the items this repo owns.

**Script-managed upstream removal.** Forking-and-replacing (ADR-0004) is made atomic: the same
sync run that links `to-tickets` removes the superseded `to-issues` symlink, so the
two-producer intermediate state (both an "issue" producer and a "Ticket" producer live in user
scope) never persists.

`install.sh`'s direction **inverts**: the retired `install.sh` *pushed* (copied) the AI Layer
*into a project*; `sync.sh` *links* the machinery *into user scope*. Push-into-project →
link-into-global.

Alternatives rejected:
- **Copy-based sync**: reintroduces drift; directly contradicts ADR-0003.
- **Whole-directory symlink**: clobbers coexisting upstream skills.
- **Manual symlink management**: leaves non-atomic fork/replace windows and is error-prone.

Consequence: `~/.claude/` points into this repo's working tree on NFS; if the repo is moved or
the mount is gone, the links break — the same fragility the upstream symlinks already carry,
accepted deliberately. Downstream repos consume machinery purely through user scope; nothing is
copied into them.
