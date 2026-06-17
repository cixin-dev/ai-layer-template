# Plan: remove tmux guard from notify.sh bell transport

## Summary

Remove the `[ -n "${TMUX:-}" ]` guard from `notify.sh` so the terminal bell fires in any
terminal emulator, not just tmux. Also wrap the `printf '\a'` in a group command to fully
silence the stderr leak when `/dev/tty` is unavailable (e.g. subprocess with no controlling
terminal).

## User Story

As a user running Claude Code in a non-tmux terminal (e.g. Windows Terminal), I want the
bell transport to fire so that I receive at-keyboard notifications via my terminal emulator's
own bell/flash behaviour.

## Metadata

| Field | Value |
|-------|-------|
| Type | BUG_FIX |
| Complexity | TRIVIAL |
| Systems affected | `.claude/hooks/notify.sh` |

## Key Decisions

- **Remove guard entirely.** `printf '\a' > /dev/tty` is standard POSIX; every terminal
  emulator responds to BEL. The guard was tmux-centric by accident, not by design.
- **Group command for silent failure.** `{ printf '\a' > /dev/tty; } 2>/dev/null` suppresses
  the shell-level error when `/dev/tty` is inaccessible (subprocess with no controlling tty),
  unlike a plain `2>/dev/null` on the simple command which does not catch redirection setup errors.
- **tmux behaviour unchanged.** Under tmux, `/dev/tty` resolves to the agent's pane tty;
  `monitor-bell` + `window-status-bell-style` render the flag in the status bar as before.

## Files Changed

- `.claude/hooks/notify.sh` — remove tmux guard, wrap in group command, update comments

## Validation

- `bash scripts/notify.test.sh` passes
- Manual: `sleep 3 && bash ~/.claude/hooks/notify.sh info Test bell` with Windows Terminal
  window-flash enabled → switch away → taskbar flashes
