#!/usr/bin/env bash
# launch_guard_check.sh — fail the gate when a runbook ships an unguarded
# scheduled command inside a ```cron fence.
#
# A scheduler-reentered command (e.g. a */5 cron) can outlast its own tick and
# overlap the next run. With no single-instance guard (flock) two copies race on
# main's HEAD — the HEAD race, ADR-0024. The original Night Shift miss shipped an
# unguarded */5 cron in a runbook precisely because a launch line reads as an
# "example," not a "check." This is the mechanical backstop for that blind spot.
#
# Scope (deliberately narrow, and PRINTED on every run so a green never reads as
# "covered everything" — CLAUDE.md "no silent caps"): we flag ONLY non-blank,
# non-comment lines inside a ```cron fence, across ALL tracked *.md. We scan the
# whole *.md class — not a name-glob subset — for the same reason exec_bit_check
# globs all *.sh: a filename convention would let a misnamed/misplaced runbook
# silently escape the gate, reintroducing the very silent-miss class this kills.
# Out of scope BY DESIGN: single-launch `&`/`nohup` daemons (launched once, so
# they can't self-overlap) and cron written outside a ```cron fence (systemd
# timers, crontab installs, ```bash snippets) — the /validate 3.5 prose gate
# still covers recognition on those surfaces.
#
# Escape hatch (reason REQUIRED): a `# linter:allow-unguarded-cron: <why>` line
# just above the command (or inline after it) opts it out and is printed for
# audit. A bare marker with no reason does NOT exempt.
set -euo pipefail

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "[launch-guard-check] not a git repo; skipping" >&2
  exit 0
fi

marker_re='linter:allow-unguarded-cron:[[:space:]]*[^[:space:]]'
guard_re='flock|lockfile|setlock'

offenders=()
allowed=()

while IFS= read -r file; do
  [ -f "$file" ] || continue
  in_cron=0
  allow_next=0
  allow_reason=""
  lineno=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))

    # Fence tracking (markdown fences don't nest — a two-state toggle suffices).
    # A ```cron line opens; any other ``` line (bare close, or ```bash etc.) closes.
    case "$line" in
      '```cron'*) in_cron=1; allow_next=0; allow_reason=""; continue ;;
      '```'*)     in_cron=0; allow_next=0; allow_reason=""; continue ;;
    esac

    # Candidates exist only inside a ```cron fence.
    [ "$in_cron" -eq 1 ] || continue

    # Escape-hatch marker as its own #-comment line (reason required). Evaluated
    # BEFORE the comment-skip below, since the marker IS itself a #-comment.
    if [[ "$line" =~ ^[[:space:]]*# ]] && [[ "$line" =~ $marker_re ]]; then
      allow_next=1
      allow_reason="$(printf '%s' "$line" | sed -E 's/.*linter:allow-unguarded-cron:[[:space:]]*//')"
      continue
    fi

    # Blank or (non-marker) crontab comment → skip, disarm.
    if [[ "$line" =~ ^[[:space:]]*$ ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
      allow_next=0; allow_reason=""; continue
    fi

    # A real scheduled line: guarded, allowed, or an offender.
    if [[ "$line" =~ $guard_re ]]; then
      :   # carries a guard token — OK
    elif [ "$allow_next" -eq 1 ]; then
      allowed+=("$file:$lineno — $allow_reason")
    elif [[ "$line" =~ $marker_re ]]; then
      reason="$(printf '%s' "$line" | sed -E 's/.*linter:allow-unguarded-cron:[[:space:]]*//')"
      allowed+=("$file:$lineno — $reason")
    else
      snippet="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//')"
      offenders+=("$file:$lineno    $snippet")
    fi
    allow_next=0; allow_reason=""
  done < "$file"
done < <(git ls-files -- '*.md')

if [ "${#offenders[@]}" -gt 0 ]; then
  echo "FAIL: unguarded scheduled command(s) inside a \`\`\`cron fence (no flock guard):"
  for o in "${offenders[@]}"; do echo "  $o"; done
  echo "  A scheduler-reentered command with no single-instance guard can overlap its"
  echo "  next run and race on main's HEAD (ADR-0024, the HEAD race)."
  echo "  Fix: add 'flock -n -E 0 <lockfile>' before the command."
  echo "  Or opt out (reason REQUIRED): '# linter:allow-unguarded-cron: <why>'."
  exit 1
fi

echo "launch-guard check passed (no unguarded cron in tracked *.md)."
echo "  Scope: \`\`\`cron fences in all tracked *.md. Does NOT cover systemd timers,"
echo "  crontab installs, cron in non-cron fences, or single-launch &/nohup daemons"
echo "  (out of scope by design — the /validate 3.5 prose gate still covers those)."
if [ "${#allowed[@]}" -gt 0 ]; then
  echo "  Allowed exemptions (# linter:allow-unguarded-cron: <reason>):"
  for a in "${allowed[@]}"; do echo "    $a"; done
fi
exit 0
