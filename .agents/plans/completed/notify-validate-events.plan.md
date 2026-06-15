# Plan: Event-driven validate notification (tmux flag + ntfy) — Channel A

## Summary
Build one notification primitive — `.claude/hooks/notify.sh <level> <title> <message>`
(`level` ∈ `fail`/`info`/`pass`/`clear`) — a deep module owning two independent,
error-swallowing sinks (tmux window flag + bell; network push via ntfy/Pushover) that
**never writes stdout** and **never fails its caller**.
Wire it into the validate boundary: the `validate_gate.py` block path fires `notify.sh fail`
deterministically on every real gate failure (in any session), and `/validate` Phase 5 fires
`notify.sh pass` on a green PR-ready gate (only in real validate sessions). Repoint the two
`settings.shared.json` Notification hooks from the SSH-invisible `notify-send` to the same
primitive so agent-attention notifications actually reach the operator over SSH+tmux. Tests
follow the repo's existing convention (`scripts/notify.test.sh`, wired into CI), and a
regression case in `validate_gate.test.sh` proves the FAIL stdout stays pure block JSON.

### Notification semantics (grilling outcome — see ADR-0021)
The operator's real tmux layout is **one window per project**, with **multiple split panes
running concurrent PIV flows** inside it (+ often a dashboard pane). tmux's status bar is
**window-granular**, so the flag is a **coarse, per-project** signal that aggregates N
concurrent streams into one colour slot. Three consequences drive the sink behaviour:

| level | tmux window colour | bell | network push (ntfy) |
|-------|--------------------|------|---------------------|
| `fail` | **set red** (latch; floor — never downgraded) | ✓ | ✓ |
| `info` (permission/idle) | set **yellow** *only if not already red* | ✓ | ✗ (at-keyboard signal; `idle_prompt` too frequent for the phone) |
| `pass` | **untouched** (a peer pass must not false-clear another pane's live fail) | ✓ | ✓ (`{branch}: PR ready`) |
| `clear` | reset `@claude_attention` + `window-status-style` | ✗ | ✗ |

- Severity precedence on the single slot: `fail > info > pass`; `pass` is off the colour path.
- The flag is released **only** by an explicit `clear` (operator-triggered) — never by `pass`,
  because the window aggregates concurrent streams and a false-clear (red wiped while a fail is
  live) is the dangerous direction. Reliable AFK truth = the **network push**; per-stream detail
  = the **dashboard pane** (which is read-only and cannot auto-clear the flag). Stale-red is the
  accepted safe bias. Full rationale + rejected alternatives: **ADR-0021**.

## User Story
As the operator running Claude on a remote machine over SSH+tmux, I want a validate
PASS/FAIL (and agent-attention) to flag the tmux window and/or push to my phone, so that I
stop polling the dashboard and get interrupted only when a pane actually needs me.

## Metadata
| Field | Value |
|-------|-------|
| Type | NEW |
| Complexity | MEDIUM |
| Systems affected | `.claude/hooks/` (new `notify.sh`, `validate_gate.py`), `.claude/commands/validate.md`, `.claude/settings.shared.json`, `.gitignore`, `scripts/` (tests + sync notes), `.github/workflows/ci.yml` |
| Issue | #40 |

## Assumptions & Risks
| Claim | VERIFIED / ASSUMED | Evidence (probe command + result) or mitigation |
|-------|--------------------|--------------------------------------------------|
| `notify.sh` can be no-op-safe and stdout-pure under `set -u`: exit 0 + empty stdout with no `$TMUX` and no config | **VERIFIED** | Throwaway skeleton (`set -u`, conf-source guarded by `[ -f ] && . … \|\| true`, sinks gated on `${TMUX:-}`/`${NTFY_TOPIC:-}`): `env -u TMUX -u NTFY_TOPIC notify.sh info T M` → stdout empty, `RC=0`. |
| Network sink fires exactly one `curl` push carrying Title + message, still exit 0 / no stdout | **VERIFIED** | Shimmed `curl` on PATH, `NTFY_TOPIC=mytopic`: log = `CURL_CALLED -fsS -m 5 -H Title: Validate PASS -d branch: PR ready https://ntfy.sh/mytopic`, exactly 1 line, stdout empty, RC=0. |
| tmux window-flag mechanism works and is observable (shimmable) | **VERIFIED** | Throwaway detached server (`tmux -S sock`): `set-window-option window-status-style 'fg=red,bold'` → OK; `set-option -w @claude_attention 1` → OK; `show-options -w @claude_attention` reads back `1`. tmux 3.4 present; this session is itself inside tmux (`$TMUX` set), matching the operator's SSH+tmux workflow. |
| The flag lands on the **correct** project window (the failing agent's own), not some other active window — critical now that window = project and the operator runs several project windows | **VERIFIED** | This session's Bash/Python subprocesses (same class as the validate_gate Stop-hook subprocess) inherit `TMUX_PANE=%0`; `tmux display-message -p '#{window_id}'` with no `-t` resolves via `TMUX_PANE` → `@0` (the calling pane's window). `set-option -w -t @0` colours that window regardless of which window is active. So the Stop hook flags the failing agent's own project window. |
| The bell `\a` is capturable in tests without `/dev/tty` | **VERIFIED** | Skeleton writes bell to `${NOTIFY_BELL_TARGET:-/dev/tty}`; test points it at a temp file. (The *visible* tmux bell flag still depends on the operator's `monitor-bell`; that's why the deterministic window-flag — independent of `monitor-bell` — is the primary signal and the bell is complementary.) |
| `sync.sh` Notification merge is unaffected by changing the command string | **VERIFIED** | `sync.sh:236-240` dedupes Notification blocks **by matcher** ("command text is cosmetic"); `sync.test.sh` assertions (lines 317-318, 328) key on the matcher tokens `permission_prompt`/`idle_prompt`, never on the `notify-send` text. `grep` confirms no test asserts the command string. |
| `notify.sh` auto-installs to `~/.claude/hooks/notify.sh` | **VERIFIED** | `sync.sh:130-134` copies every file in `.claude/hooks/*` to `$CLAUDE_DIR/hooks/` and `chmod`s it; no sync.sh change needed for install. `sync.test.sh` positive `assert_contains` checks won't break on an extra copied hook. |
| Claude Code expands `$HOME` in a Notification hook `command` string (so `"$HOME/.claude/hooks/notify.sh" …` resolves globally) | **ASSUMED** | The existing committed hook is a **bare** `notify-send …` — a command resolvable only via shell PATH lookup, which proves Claude Code runs Notification commands through a shell; a shell expands `$HOME`. Strong inference, not a fired event. **De-risk (first Implement step after Task 6):** trigger one permission/idle event (or run the exact rendered command string through `bash -c`) and confirm `notify.sh` executes; if Claude Code does *not* shell-expand, fall back to a literal absolute path noted in the issue's follow-up. |
| FAIL notify cannot corrupt the gate's block-JSON stdout | **VERIFIED (by design) + test** | `validate_gate.py` will invoke notify via `subprocess.run(..., capture_output=True)` (notify's stdout/stderr captured & discarded) **and** `notify.sh` itself never writes stdout. Task 7 adds a `validate_gate.test.sh` case asserting stdout == exact block JSON while notify is invoked. |

### Two deviations from the issue text (deliberate, to match real repo convention)
1. **Test location/wiring.** The issue says `.claude/hooks/notify.test.sh` wired into
   `validate.sh`. Real convention: all unit tests live in `scripts/*.test.sh` and reference
   `../.claude/hooks/<hook>` (see `security_guard.test.sh:5`), and are wired into
   `.github/workflows/ci.yml` — **not** `validate.sh`, which runs only `piv_check.sh` (the
   runtime PIV-invariant check, not the unit-test runner). → Create `scripts/notify.test.sh`;
   wire into `ci.yml`. This satisfies the acceptance criterion ("wired into validate.sh / CI
   and green") via CI, consistent with every other test.
2. **Notify path reference.** The issue writes bare `notify.sh info …`. A bare command needs
   PATH; the hooks are not on PATH. → settings.shared.json uses
   `"$HOME/.claude/hooks/notify.sh" …` (global install path, shell-expanded); `validate_gate.py`
   resolves its sibling by `__file__`; `/validate` (run from a checkout) uses the repo-relative
   `.claude/hooks/notify.sh`.

## Patterns to Follow

**Hook shape — fail-open, single-purpose, stderr-only diagnostics:**
```python
# SOURCE: .claude/hooks/validate_gate.py:52-99
def main() -> None:
    try:
        data: dict = json.load(sys.stdin)
    except Exception as e:
        print(f"[validate-gate] Could not parse hook JSON: {e}", file=sys.stderr)
        sys.exit(0)  # fail open
    ...
    timeout = int(os.environ.get("VALIDATE_GATE_TIMEOUT", "120"))  # ← env-knob idiom to mirror
```

**Test harness — capture rc/stderr around an intentional non-zero, count failures:**
```bash
# SOURCE: scripts/security_guard.test.sh:11-46
run_hook() { set +e; STDERR="$(printf '%s' "$1" | python3 "$HOOK" 2>&1 >/dev/null)"; RC=$?; set -e; }
assert_allow() { run_hook "$1"; if [ "$RC" -ne 0 ]; then echo "FAIL: $2 …"; FAILURES=$((FAILURES+1)); fi; }
# … and at end:  if [ "$FAILURES" -eq 0 ]; then echo "All tests passed."; else echo "$FAILURES test(s) failed."; fi; exit $FAILURES
```

**stdout-purity assertion via captured stdout + separate stderr file:**
```bash
# SOURCE: scripts/validate_gate.test.sh:74-77
stdout_a="$(printf '%s' "$payload_a" | CLAUDE_PROJECT_DIR="$MAIN_A" python3 "$HOOK" 2>"$STDERR_FILE")"
assert_contains "$stdout_a" '"decision": "block"' "test(a): worktree red blocks"
```

**CI test list (append here):**
```yaml
# SOURCE: .github/workflows/ci.yml
run: |
  bash scripts/sync.test.sh
  bash scripts/unsync.test.sh
  bash scripts/validate_gate.test.sh
  bash scripts/security_guard.test.sh
  bash scripts/piv_check.test.sh
```

**Notification block to repoint (matcher unchanged; only the `command` string changes):**
```json
// SOURCE: .claude/settings.shared.json:9-22
{ "matcher": "permission_prompt", "hooks": [ { "type": "command", "command": "notify-send 'Claude Code' 'Permission needed'" } ] }
```

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `.claude/hooks/notify.sh` | CREATE | The notification primitive (two sinks); `chmod +x` |
| `.claude/notify.local.conf.example` | CREATE | Committed example of gitignored env config |
| `scripts/notify.test.sh` | CREATE | Unit tests for `notify.sh`; `chmod +x` |
| `.claude/hooks/validate_gate.py` | UPDATE | FAIL block path fires `notify.sh fail …` (sibling, captured, never corrupts stdout) |
| `scripts/validate_gate.test.sh` | UPDATE | Regression: FAIL invokes notify **and** stdout stays exact block JSON |
| `.claude/commands/validate.md` | UPDATE | Phase 5 PASS step emits `notify.sh pass …` with branch |
| `.claude/settings.shared.json` | UPDATE | Repoint both Notification commands `notify-send` → `notify.sh info …` |
| `.gitignore` | UPDATE | Ignore `notify.local.conf` |
| `.github/workflows/ci.yml` | UPDATE | Add `bash scripts/notify.test.sh` |
| `scripts/sync.sh` | UPDATE | Stale manual-snippet note text (no-python3 branch, lines 160-161) `notify-send` → notify.sh |

## Tasks

### Task 1: Create the `notify.sh` primitive
- File: `.claude/hooks/notify.sh`
- Action: CREATE (then `chmod +x`)
- Implement: `#!/usr/bin/env bash` + `set -u` (NOT `-e` — a failing sink must not abort;
  always `exit 0`). Args: `level="${1:-info}"` (`fail`/`info`/`pass`/`clear`), `title="${2:-Claude Code}"`,
  `message="${3:-}"`. Source optional config: `CONF="$(dirname "$0")/notify.local.conf"; [ -f "$CONF" ] && . "$CONF" 2>/dev/null || true`.
  - **tmux sink** (gated on `[ -n "${TMUX:-}" ]`, whole block wrapped so any error is swallowed).
    Resolve the target window once: `win=$(tmux display-message -p '#{window_id}' 2>/dev/null)`
    (verified to resolve to the calling agent's own pane's window via inherited `$TMUX_PANE`).
    Then branch on `level` (the **`fail > info > pass`** precedence on the single colour slot):
    - **`clear`**: `tmux set-option -w -t "$win" -u @claude_attention 2>/dev/null || true` and
      `tmux set-window-option -t "$win" -u window-status-style 2>/dev/null || true` (restore default).
      No bell, no push. (The *only* thing that releases the latch.)
    - **`fail`**: bell (see below); `set-option -w -t "$win" @claude_attention fail`; set
      `window-status-style 'fg=red,bold'`. Red is the floor — set unconditionally.
    - **`info`**: bell; **only if the window is not already red** — read current state
      `cur=$(tmux show-options -wv -t "$win" @claude_attention 2>/dev/null)`; if `cur != fail`,
      `set-option -w -t "$win" @claude_attention info` + `window-status-style 'fg=yellow,bold'`
      (don't downgrade a live fail).
    - **`pass`**: bell only — **do not touch `@claude_attention` or `window-status-style`**
      (a peer pass must not false-clear another concurrent pane's live fail — ADR-0021).
    - **bell** (for `fail`/`info`/`pass`, not `clear`): `printf '\a' > "${NOTIFY_BELL_TARGET:-/dev/tty}" 2>/dev/null || true`.
  - **network sink** — gated on **both** `[ -n "${NTFY_TOPIC:-}" ]` **and** `level` ∈ `fail`/`pass`
    (milestones only; `info`/`clear` skip the push — `idle_prompt` is too frequent for the phone):
    `curl -fsS -m 5 -H "Title: $title" -d "$message" "${NTFY_URL:-https://ntfy.sh}/$NTFY_TOPIC" >/dev/null 2>&1 || true`.
    Leave a Pushover branch as a config-only comment (out of scope to wire).
  - **Never** write stdout in any path. End with `exit 0`.
- Mirror: structure/comment density of `.claude/hooks/validate_gate.py:1-49`; sink-guard idiom from Spike B.
- Validate: `bash scripts/notify.test.sh` (after Task 3).

### Task 2: Create the example config
- File: `.claude/notify.local.conf.example`
- Action: CREATE
- Implement: shell-sourced `KEY=value` lines, all commented out, documenting
  `NTFY_TOPIC=`, `NTFY_URL=https://ntfy.sh` (default), and a noted Pushover placeholder.
  One-line header: copy to `notify.local.conf` (gitignored) to enable the network sink.
- Mirror: n/a (new artifact; keep terse).
- Validate: file exists; `bash -n`-safe when sourced (`. notify.local.conf.example` is a no-op).

### Task 3: Create `scripts/notify.test.sh`
- File: `scripts/notify.test.sh`
- Action: CREATE (then `chmod +x`)
- Implement: `SCRIPT_DIR=…; HOOK="$SCRIPT_DIR/../.claude/hooks/notify.sh"`; `FAILURES=0`;
  `mktemp -d` workspace with `trap … EXIT`; `assert_contains`/`assert_not_contains` helpers
  (from `validate_gate.test.sh:15-29`). Cases covering every acceptance criterion:
  - **(a) stdout pure:** every invocation captured → assert empty stdout.
  - **(b) unconfigured no-op:** `env -u TMUX -u NTFY_TOPIC … notify.sh info T M` → RC=0, empty stdout, no error.
  - **(c) tmux sink (fail):** shim a `tmux` binary on PATH that appends argv to a log + echoes a fake
    window id for `display-message`; set `TMUX=fake` and `NOTIFY_BELL_TARGET=<tmpfile>`; `notify.sh fail …`
    → assert the log contains `set-option … @claude_attention fail` + a `window-status-style` red call,
    and the bell file contains the bell byte.
  - **(d) network sink (fail/pass push):** shim `curl` on PATH logging argv; `NTFY_TOPIC=t`;
    `notify.sh fail …` and `notify.sh pass …` → each asserts exactly one call carrying `Title: <title>`
    and the message, RC=0, empty stdout.
  - **(e) info severity — no downgrade + no push:** make the `tmux` shim's `show-options -wv … @claude_attention`
    echo `fail` (window already red); `notify.sh info …` → assert the log has **no** `window-status-style`
    write (red not downgraded to yellow) and the `curl` shim was **not** called (info never pushes).
    Second case: shim echoes empty (not red) → `info` **does** set `@claude_attention info` + yellow style,
    still no `curl`.
  - **(f) clear releases the latch:** `notify.sh clear` → assert the log contains the `-u @claude_attention`
    and `-u window-status-style` unset calls, no bell write, no `curl` call.
  - Footer: `All tests passed.` / `N test(s) failed.`; `exit $FAILURES`.
- Mirror: `scripts/security_guard.test.sh` (shim+capture) and `scripts/validate_gate.test.sh:7-29` (tmpdir+asserts).
- Validate: `bash scripts/notify.test.sh` → `All tests passed.`

### Task 4: Wire FAIL into `validate_gate.py`
- File: `.claude/hooks/validate_gate.py`
- Action: UPDATE (inside `if result.returncode != 0:`, around line 92-97)
- Implement: after computing `summary`/`reason`, before `sys.exit(0)`, fire notify without
  touching the gate's stdout:
  ```python
  first_line = summary.splitlines()[0] if summary else "validate.sh failed"
  notify = os.environ.get("VALIDATE_GATE_NOTIFY", str(Path(__file__).resolve().parent / "notify.sh"))
  repo = Path(project_dir).name or project_dir
  try:
      subprocess.run([notify, "fail", "Validate FAIL", f"{repo}: {first_line}"],
                     capture_output=True, text=True, timeout=10)
  except Exception:
      pass  # notification is best-effort; never fail or delay the gate
  print(json.dumps({"decision": "block", "reason": reason}))
  ```
  Keep the existing `print(json.dumps(...))` as the **only** stdout write. The
  `VALIDATE_GATE_NOTIFY` env override mirrors the existing `VALIDATE_GATE_TIMEOUT` idiom and
  is the seam Task 5's test uses.
- Mirror: `.claude/hooks/validate_gate.py:76` (env-knob), `:92-97` (block path).
- Validate: `bash scripts/validate_gate.test.sh`.

### Task 5: Regression-test the FAIL stdout purity + notify invocation
- File: `scripts/validate_gate.test.sh`
- Action: UPDATE (add a case after test (c), the existing red-blocks case)
- Implement: build a red tree (`make_tree DIR 1`); set `VALIDATE_GATE_NOTIFY=<shim>` where the
  shim appends its argv to a log file; capture stdout into a var and stderr to file. Assert:
  (1) stdout is **exactly** `{"decision": "block", "reason": …}` — use `assert_contains "$stdout"
  '"decision": "block"'` AND `assert_not_contains "$stdout" 'fail'`/`'Validate FAIL'` (proves the
  notify args did not leak into stdout); (2) the shim log contains `fail` + `Validate FAIL` + the
  repo/first-failing-line. Reset the log between runs.
- Mirror: `scripts/validate_gate.test.sh:88-94` (red-blocks case) + shim idiom from Task 3.
- Validate: `bash scripts/validate_gate.test.sh` → `All tests passed.`

### Task 6: Wire PASS into `/validate` Phase 5
- File: `.claude/commands/validate.md`
- Action: UPDATE (Phase 5, after the push/PR steps, ~line 116)
- Implement: add a step instructing the agent, on PASS, to run
  `bash .claude/hooks/notify.sh pass "Validate PASS" "{branch}: PR ready"` (rich context; only
  in real validate sessions — the deliberate FAIL/hook vs PASS/command asymmetry). Note it is
  best-effort and must not gate the PR flow.
- Mirror: surrounding Phase 5 numbered-step style (`validate.md:92-116`).
- Validate: `grep -n 'notify.sh pass' .claude/commands/validate.md`.

### Task 7: Repoint `settings.shared.json` Notification hooks
- File: `.claude/settings.shared.json`
- Action: UPDATE (both Notification blocks)
- Implement: change each `command` from `notify-send 'Claude Code' '<text>'` to
  `"$HOME/.claude/hooks/notify.sh" info 'Claude Code' '<text>'` (permission_prompt → 'Permission needed';
  idle_prompt → 'Waiting for input'). Matchers unchanged. Keep valid JSON (escape the inner quotes).
- Mirror: `.claude/settings.shared.json:9-22`.
- Validate: `python3 -c "import json; json.load(open('.claude/settings.shared.json'))"`; `bash scripts/sync.test.sh` (still green — dedupe is by matcher).
- **De-risk immediately after:** fire one permission/idle event or run the rendered command via
  `bash -c` and confirm `notify.sh` executes (resolves the only ASSUMED claim).

### Task 8: gitignore + CI wiring + stale sync note
- Files: `.gitignore`, `.github/workflows/ci.yml`, `scripts/sync.sh`
- Action: UPDATE (3 small edits)
- Implement:
  - `.gitignore` += `notify.local.conf` (keep existing `.obsidian/`).
  - `ci.yml`: add `bash scripts/notify.test.sh` to the test list (alongside the others).
  - `sync.sh:160-161`: update the two no-python3 manual-snippet `note` lines from
    `notify-send 'Claude Code' '…'` to `"$HOME/.claude/hooks/notify.sh" info 'Claude Code' '…'`
    so the fallback instructions match the new wiring (not test-asserted; consistency only).
- Mirror: `.github/workflows/ci.yml` run list; `.gitignore` existing line.
- Validate: `git check-ignore notify.local.conf`; CI list contains notify; `grep -n notify.sh scripts/sync.sh`.

## Validation
Mechanical gate (run all, expect green):
```
bash scripts/notify.test.sh          # All tests passed.
bash scripts/validate_gate.test.sh   # All tests passed.
bash scripts/security_guard.test.sh  # unchanged — still green
bash scripts/sync.test.sh            # unchanged — dedupe-by-matcher, still green
bash scripts/piv_check.test.sh
bash .claude/validate.sh             # piv_check (PIV invariant) green
python3 -c "import json; json.load(open('.claude/settings.shared.json'))"  # valid JSON
```
End-to-end:
1. **stdout purity:** `printf '%s' '{"cwd":"<red-tree>"}' | python3 .claude/hooks/validate_gate.py`
   → stdout is exactly the block JSON, nothing else.
2. **FAIL notify fires:** with `NTFY_TOPIC` set in `notify.local.conf`, force a red gate →
   one push titled "Validate FAIL"; inside tmux the window goes **red** + bell.
3. **PASS notify fires (no recolor):** run the Phase 5 command manually → push titled
   "Validate PASS" carrying the branch; the window colour is **unchanged** (a red set by a
   concurrent pane's FAIL survives).
4. **`clear` releases:** `bash .claude/hooks/notify.sh clear` → the window's red/yellow flag
   resets to default; no push, no bell.
5. **No-op safety:** `env -u TMUX -u NTFY_TOPIC bash .claude/hooks/notify.sh info T M` →
   exit 0, no output, no error.
6. **Notification hook resolves:** `$HOME` expansion de-risk from Task 7.

## Acceptance Criteria
- [ ] All tasks completed
- [ ] `notify.sh` exists; `level` ∈ `fail`/`info`/`pass`/`clear`; never writes stdout (asserted)
- [ ] No `$TMUX` → tmux no-op; no ntfy config → network no-op; neither errors (exit 0)
- [ ] `$TMUX` faked, `fail` → window gets bell + **red** flag (asserted via shim)
- [ ] Precedence `fail > info > pass`: `info` with window already `fail` does **not** downgrade to yellow; `pass` never touches the window colour (asserted)
- [ ] `clear` is the only release: resets `@claude_attention` + `window-status-style` (asserted)
- [ ] Network push fires **only** for `fail`/`pass` (curl faked); `info`/`clear` never push (asserted)
- [ ] `NTFY_TOPIC` set (curl faked) → exactly one push carrying title + message
- [ ] `validate_gate.py` FAIL invokes `notify.sh fail …` AND stdout stays exact block JSON (asserted)
- [ ] `/validate` Phase 5 PASS emits `notify.sh pass …` with the branch name
- [ ] `settings.shared.json` Notification hooks point to `notify.sh`, not `notify-send`
- [ ] `notify.test.sh` wired into CI and green
- [ ] `.gitignore` ignores `notify.local.conf`; `.example` is committed
- [ ] Checks pass with zero errors; follows existing patterns
- [ ] The one ASSUMED claim (`$HOME` expansion in Notification hooks) is de-risked or carried as a tracked follow-up
