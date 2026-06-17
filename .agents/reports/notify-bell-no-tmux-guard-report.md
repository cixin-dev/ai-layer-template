# Report: notify bell tmux guard removal

## Outcome: PASS

## What shipped

Removed the `[ -n "${TMUX:-}" ]` guard from `notify.sh`'s bell transport so the BEL
character fires in any terminal emulator, not only under tmux. Wrapped the `printf '\a'`
in a group command (`{ ...; } 2>/dev/null`) to fully silence the stderr leak when
`/dev/tty` is unavailable in subprocess contexts.

## Validation

- Manual test with Windows Terminal (window-flash enabled): `sleep 3 && notify.sh info Test bell` → switched away → taskbar flashed ✅
- subprocess context (no tty): script exits 0, no stderr output ✅
- tmux bell behaviour: unchanged ✅

## PR

https://github.com/cixin-dev/ai-layer-template/pull/43
