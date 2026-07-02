# Operator runbook — Night Shift outer loop (`night_shift_loop.sh`, #63)

The outer loop drains the `ready-for-agent` Issue queue one task at a time: it selects the
next grabbable Issue and hands it to the thin executor (`night_shift_run.sh`), running
back-to-back while work exists and sleeping ~5 min only when the queue is empty. Serial (one
task at a time), with a file + signal kill switch.

---

## 1. Purpose + safety rails (read first)

- Run **only in the dedicated Night Shift clone**, never your working checkout. Sharing one
  checkout re-creates the HEAD race (ADR-0024 / CLAUDE.md do-not).
- The loop drives **real** PRs — it spends subscription credit for every Issue it touches.
- Leave the **dangerous-push floor on** (`security_guard.py`, ADR-0020). It never merges.
- `CONCURRENCY` defaults to 1. Setting it above 1 exits non-zero (v1 is intentionally serial).

---

## 2. Preconditions

Reuse the executor runbook §1 in full — all four preconditions apply:

1. No `ANTHROPIC_API_KEY` shadowing the subscription.
2. Headless `claude -p` works (subscription auth).
3. `git push` dial graduated to `allow` by the **operator** by hand (agent can't self-modify).
4. Dedicated clone on `main` (`NS_CLONE=~/night-shift/ai-layer-template`).

See `.agents/reports/night-shift-thin-executor-runbook.md §1` for the check commands.

---

## 3. Dry-run first (read-only, no credit)

```bash
NS_CLONE=~/night-shift/ai-layer-template
bash "$NS_CLONE/scripts/night_shift_loop.sh" select
```

Prints the Issue number the loop would grab next. Nothing is dispatched. If the output is
empty, the queue is empty — nothing will run.

**Grounding evidence (dry-run against known-good AND known-bad, zero credit):**

```bash
# Setup
PROBEDIR=$(mktemp -d)
cat > "$PROBEDIR/gh-good" << 'EOF'
#!/usr/bin/env bash
case "$1 $2" in "issue list") printf '62\tready-for-agent\n' ;; esac; exit 0
EOF
cat > "$PROBEDIR/gh-empty" << 'EOF'
#!/usr/bin/env bash
case "$1 $2" in "issue list") : ;; esac; exit 0
EOF
cat > "$PROBEDIR/run" << 'EOF'
#!/usr/bin/env bash
case "$1" in snapshot) printf 'PR_OPEN=0\nESCALATED=0\n' ;; esac; exit 0
EOF
chmod +x "$PROBEDIR/gh-good" "$PROBEDIR/gh-empty" "$PROBEDIR/run"
mkdir -p "$PROBEDIR/state"

# known-good: a ready issue → prints 62
NIGHT_SHIFT_GH="$PROBEDIR/gh-good" NIGHT_SHIFT_RUN="$PROBEDIR/run" \
  NIGHT_SHIFT_STATE_DIR="$PROBEDIR/state" \
  bash scripts/night_shift_loop.sh select
# → observed: 62  ✓

# known-bad: empty queue → empty output
NIGHT_SHIFT_GH="$PROBEDIR/gh-empty" NIGHT_SHIFT_RUN="$PROBEDIR/run" \
  NIGHT_SHIFT_STATE_DIR="$PROBEDIR/state" \
  bash scripts/night_shift_loop.sh select
# → observed: (empty)  ✓
```

---

## 4. Start

**Persistent (long-lived background process):**
```bash
cd "$NS_CLONE"
# optional: NIGHT_SHIFT_POLL_INTERVAL=300 (default) — seconds between idle polls
bash scripts/night_shift_loop.sh &
```
Runs one Issue at a time, sleeping between polls when the queue drains. Logs go to stdout.

**Cron (external poll cadence, one drain per invocation):**
```cron
*/5 * * * * cd ~/night-shift/ai-layer-template && bash scripts/night_shift_loop.sh drain >> ~/.night-shift-loop.log 2>&1
```
Cron supplies the poll cadence; `drain` does one pass and exits. Simpler for cron; persistent
is better for event-driven throughput (drain loop re-selects immediately after each executor
returns, with no fixed idle gap).

Serial (dial = 1): only one Issue runs at a time.

---

## 5. Kill switch / stop

**Graceful stop** (stops before the next task/poll; an in-flight task finishes first):
```bash
NS_STATE="${NS_CLONE}/.night-shift"
touch "$NS_STATE/stop"
# → loop prints "kill switch: $NS_STATE/stop present — stopping loop" at the next check
```

**Resume** (clear the stop file):
```bash
rm "$NS_STATE/stop"
```

**Immediate stop** (signal):
```bash
kill -TERM <loop-pid>     # or Ctrl-C — the loop traps INT/TERM and exits cleanly
```

**Grounding evidence:**

```bash
# known-good: stop file present → exits with "kill switch" message, rc 0
STOPDIR=$(mktemp -d); touch "$STOPDIR/stop"
OUT="$(NIGHT_SHIFT_GH="$PROBEDIR/gh-good" NIGHT_SHIFT_RUN="$PROBEDIR/run" \
       NIGHT_SHIFT_STATE_DIR="$STOPDIR" NIGHT_SHIFT_STOP_FILE="$STOPDIR/stop" \
       NIGHT_SHIFT_MAX_POLLS=1 \
       bash scripts/night_shift_loop.sh loop 2>&1)"
# → observed: rc=0, output contains "kill switch"  ✓

# known-bad: no stop file → loop runs (exits via MAX_POLLS=1 here, not kill switch)
RUNDIR=$(mktemp -d)
OUT2="$(NIGHT_SHIFT_GH="$PROBEDIR/gh-empty" NIGHT_SHIFT_RUN="$PROBEDIR/run" \
        NIGHT_SHIFT_STATE_DIR="$RUNDIR" NIGHT_SHIFT_STOP_FILE="$RUNDIR/stop" \
        NIGHT_SHIFT_MAX_POLLS=1 NIGHT_SHIFT_SLEEP=true \
        bash scripts/night_shift_loop.sh loop 2>&1)"
# → observed: rc=0, output contains "reached MAX_POLLS=1" (not "kill switch")  ✓
```

---

## 6. Observe

```bash
# Current phase + attempt count for Issue N
cat "$NS_CLONE/.night-shift/$N.state"

# Live executor sessions during a run
pgrep -af 'claude -p'

# Dashboard (cross-Issue overview)
/dashboard
```

---

## 7. Quiescence & stuck tasks

The loop idles (polling every `POLL_INTERVAL` seconds) when the queue is empty. It never spins:

- **Stuck task** (executor left `in-progress`): `select_issue` skips it. Un-stick by human
  triage — fix the underlying issue, then `gh issue edit N --remove-label in-progress` to
  re-offer it.
- **Escalated task** (carries the `ESCALATED` marker + no `in-progress`, no open PR): also
  excluded by the terminal check. Clear via `loop_state.sh` + relabel `ready-for-agent` to
  re-try after human intervention.
- **Runaway cap** (executor exited rc 3): same as stuck — Issue keeps `in-progress`, loop
  skips it indefinitely.

---

## 8. Concurrency guard

v1 is intentionally serial. Setting `NIGHT_SHIFT_CONCURRENCY` above 1 is reserved for a
future graduation and exits non-zero immediately.

**Grounding evidence:**

```bash
# known-bad: CONCURRENCY=2 → exits non-zero + "serial only"
RC=0; OUT="$(NIGHT_SHIFT_CONCURRENCY=2 bash scripts/night_shift_loop.sh loop 2>&1)" || RC=$?
# → observed: rc=2, output contains "serial only in v1 (concurrency=2 …)"  ✓

# known-good: CONCURRENCY=1 (default) → no "serial only" error
RC=0; OUT="$(NIGHT_SHIFT_CONCURRENCY=1 NIGHT_SHIFT_MAX_POLLS=1 NIGHT_SHIFT_SLEEP=true \
             NIGHT_SHIFT_GH="$PROBEDIR/gh-empty" NIGHT_SHIFT_RUN="$PROBEDIR/run" \
             NIGHT_SHIFT_STATE_DIR="$(mktemp -d)" \
             bash scripts/night_shift_loop.sh loop 2>&1)" || RC=$?
# → observed: rc=0, output contains "reached MAX_POLLS=1" (no "serial only")  ✓
```

---

## 9. Teardown

The dedicated clone can stay for reuse. When done for a session:

1. Engage the kill switch: `touch "$NS_CLONE/.night-shift/stop"`
2. Wait for any in-flight task to finish (or send SIGTERM for immediate stop).
3. Confirm stopped: `pgrep -af 'night_shift_loop\|claude -p'` should be empty.
4. Optionally clear the stop file for next session: `rm "$NS_CLONE/.night-shift/stop"`
