# Hooks are copied as real files, not symlinked, for NFS resilience

ADR-0007 accepted symlink fragility deliberately — if the NFS mount is gone, links break — but
did not weigh the failure modes separately across item types. Issues #2 and #3 exposed that the
trade-off resolves differently for hooks than for skills and commands.

**Decision:** `sync.sh` **copies** hook files (`security_guard.py`, `validate_gate.py`) into
`~/.claude/hooks/` as real, executable files. Skills and commands **remain per-item symlinks**
as decided in ADR-0007.

**Rationale: catastrophic vs. graceful failure.**
When the NFS share is unmounted:

- A broken **skill or command symlink** degrades *gracefully*: the skill is simply absent. The
  session starts, existing tools still function, and the user notices a missing feature rather
  than a broken environment.
- A broken **hook symlink** fails *catastrophically*: Python cannot open the dangling path, so
  PreToolUse fires an error on every tool call and the session is unusable. The Stop hook also
  misfires. The entire Claude Code session is dead until the mount comes back.

This asymmetry — graceful vs. catastrophic — overrides the drift argument that led ADR-0007 to
prefer symlinks. The cost for skills and commands (slight drift until next `sync.sh` run) is not
worth paying to avoid a session-killing failure mode; for hooks, it is.

**Accepted cost: hook drift.**
Copied hooks can drift from repo source between `sync.sh` runs. This is mitigated: `copy_item`
uses `cmp -s` to detect content changes and refreshes on every run, so any drift lasts only
until the next sync. The hooks are small (~100 lines each) and change infrequently, so the
practical drift window is narrow.

**Migration of already-installed machines (issue #2).**
Machines that currently have symlinks in `~/.claude/hooks/` are fixed by running the updated
`sync.sh` once. `copy_item` writes to a temp file then renames into place (atomic on POSIX for same-filesystem
moves), so a dangling symlink is replaced cleanly in a single `sync.sh` run. No separate
migration script is needed.

Alternatives rejected:

- **Keep symlinks for hooks**: the session-breaking failure mode on NFS-down is unacceptable.
- **Copy everything (skills, commands, hooks)**: needlessly reintroduces the per-copy drift
  ADR-0007 set out to kill for skills and commands, whose broken-link failure mode is tolerable.
- **Guard hooks at Python load time**: shifts the fix to the wrong layer; the hook loader is
  upstream code and the right fix is at the file-installation layer.

Consequence: `~/.claude/hooks/` contains real files, not NFS-dependent symlinks. Skills and
commands in `~/.claude/{skills,commands}/` retain ADR-0007's symlink behaviour. Running
`sync.sh` is sufficient to both install and migrate hook files. References: issues #2, #3.
