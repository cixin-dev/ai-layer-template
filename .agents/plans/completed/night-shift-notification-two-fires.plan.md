# Plan: Night Shift notification reshape — two fires only (escalate, pr-ready)

## Summary
Shrink *when* the notification mechanism fires for the Night Shift, without touching the
mechanism. `.claude/hooks/notify.sh` stays byte-for-byte unchanged. What changes: (1) remove
the two per-step `Notification` hooks (`permission_prompt`, `idle_prompt`) from
`.claude/settings.shared.json` — mid-loop nags are pointless when no human is at the keyboard;
(2) lock the **two-fire contract** with a new Seam-4 test (`scripts/notify_contract.test.sh`,
in the style of `scripts/notify.test.sh`) that asserts notify *reaches the phone* for the two
Night-Shift fires — **escalate** (→ `notify.sh fail`) and **pr-ready** (→ `notify.sh pass`) —
does **not** reach the phone for the per-step level (`info`), and that the per-step nudge
hooks are gone (regression guard). The two fires' *call sites* are wired by other executor
slices (pr-ready already lives in `/validate` Phase 5; escalate is a future slice); this slice
only establishes the contract, removes the old hooks, and pins both with a test proven to flip
red→green.

## User Story
As the operator of an AFK Night Shift, I want notifications to interrupt me at only the two
moments a human is actually wanted — a task is stuck (escalate) or a green gate opened a PR
(pr-ready) — so that per-step permission/idle nags stop firing into an empty room and can't
silently creep back.

## Metadata
| Field | Value |
|-------|-------|
| Type | ENHANCEMENT |
| Complexity | LOW |
| Systems affected | `.claude/settings.shared.json`, `scripts/notify_contract.test.sh` (new), `.github/workflows/ci.yml`, `scripts/sync.sh` (stale-note cleanup) |
| Issue | #58 |

## Assumptions & Risks
| Claim | VERIFIED / ASSUMED | Evidence (probe command + result) or mitigation |
|-------|--------------------|--------------------------------------------------|
| `notify.sh` pushes (reaches the phone) **only** for `fail`/`pass`; `info` rings the bell but never pushes; script stays unchanged | **VERIFIED** | Read `.claude/hooks/notify.sh`: network branch is `case "$level" in fail|pass)` only; bell `printf '\a'` is unconditional. Ran `bash scripts/notify.test.sh` → `All tests passed.` (test (d) = fail/pass push once each; test (e) = info never pushes). This slice does not edit notify.sh. |
| pr-ready fire = `notify.sh pass`; already wired, not this slice's call site | **VERIFIED** | `.claude/commands/validate.md:129`: `bash .claude/hooks/notify.sh pass "Validate PASS" "{branch}: PR ready"` (Phase 5, on green). |
| escalate fire = `notify.sh fail` (the contract this slice fixes) | **VERIFIED (level behavior) + design decision (mapping)** | escalate needs bell+push and "stuck/needs-human" severity → `fail` is the only pushing level not already claimed by the success milestone `pass`; `fail` push behavior verified above. The escalate *call site* is a future executor slice (`scripts/night_shift_run.sh` has no notify call today — `:123` comment "executor adds NO push/PR/notify of its own"; decider emits `escalate` at `night_shift_decide.sh:46`). This slice only pins the level via the contract test. |
| Removing the two `Notification` hooks from the real `settings.shared.json` does **not** break `sync.test.sh` | **VERIFIED** | `sync.test.sh` builds its own shared-settings fixture via heredoc in `setup_fixture()` (`scripts/sync.test.sh:85-110`, still using the old `notify-send` string) and drives sync with `SYNC_REPO_DIR="$REPO"` — it never reads the repo's real `.claude/settings.shared.json`. Tests (shared-a/b) at `:317-318,328` assert against that fixture. Ran `bash scripts/notify.test.sh` green as baseline; sync tests untouched by this change. |
| The `sync.sh` fallback notes at `:152-153,160-161` that name the two Notification hooks are **not** test-asserted | **VERIFIED** | They live in the `if ! command -v python3` branch (`sync.sh:146-162`). CI and `sync.test.sh` run with python3 present, so this branch is never executed; the `"would add Notification hook: …"` assertions in `sync.test.sh:317-318` are produced by the python3 path (`sync.sh:260`) driven by the fixture, not by these notes. Removing the stale notes is safe consistency-only cleanup. |
| Tests are wired into `.github/workflows/ci.yml`, **not** `.claude/validate.sh` (which runs only `piv_check.sh`) | **VERIFIED** | `.claude/validate.sh` → `bash scripts/piv_check.sh` only; `piv_check.sh` checks PIV artifact invariants, never globs `*.test.sh`. `ci.yml` lists each `bash scripts/*.test.sh` explicitly. |
| The Seam-4 config-guard is a real check (distinguishes pass from fail), not a reasoned-about check | **TO BE DEMONSTRATED in Task 1→2** | Per CLAUDE.md "verify-check-commands": Task 1 writes the test and runs it against the **known-bad** case (hooks still present) → the guard assertion FAILS red; Task 2 removes the hooks → re-run is GREEN. The observed red→green flip grounds the check command. |

## Patterns to Follow

**curl-shim harness + assert helpers (mirror for the primitive-contract half):**
```bash
# SOURCE: scripts/notify.test.sh:19-33  (fake curl on PATH logging argv)
BIN="$WORK/bin"; mkdir -p "$BIN"
export CURL_LOG="$WORK/curl.log"
cat > "$BIN/curl" << 'EOF'
#!/usr/bin/env bash
echo "curl $*" >> "$CURL_LOG"
exit 0
EOF
chmod +x "$BIN/curl"
export PATH="$BIN:$PATH"
```
```bash
# SOURCE: scripts/notify.test.sh:44-66  (helpers: cap / assert_rc0 / assert_empty / assert_lines)
cap() { OUT="$("$@" 2>"$ERR")"; RC=$?; }
assert_lines() { local n; n=$(wc -l < "$1" | tr -d ' '); if [ "$n" -ne "$2" ]; then echo "FAIL: $3 …"; FAILURES=$((FAILURES + 1)); fi; }
```
```bash
# SOURCE: scripts/notify.test.sh:77-83 & 96-101  (push fires once for pass; info never pushes)
: > "$CURL_LOG"
cap env -u TMUX NTFY_TOPIC=t bash "$HOOK" fail "Validate FAIL" "msg-fail"
assert_lines "$CURL_LOG" 1 "test(d): fail pushes exactly once"
...
cap env TMUX=fake NTFY_TOPIC=t NOTIFY_BELL_TARGET="$BELL_FILE" bash "$HOOK" info "T" "M"
assert_lines "$CURL_LOG" 0 "test(e): info never pushes"
```

**python3 JSON read of a settings file (mirror for the config-guard half):**
```python
# SOURCE: scripts/sync.sh:219 & 236-240  (read hooks.Notification matchers, robust to absent keys)
shared_notifs = [b for b in shared.get("hooks", {}).get("Notification", []) if isinstance(b, dict)]
live_notif_matchers = { b.get("matcher") for b in data.get("hooks", {}).get("Notification", []) if isinstance(b, dict) }
```
```bash
# SOURCE: scripts/sync.test.sh:304-309  (python3 heredoc taking a settings path via argv)
python3 - "$CLAUDE_HOME_DIR/settings.json" "$1" <<'PYEOF'
import json, sys, pathlib
...
PYEOF
```

**test footer convention (all repo tests):**
```bash
# SOURCE: scripts/notify.test.sh:110-116
if [ "$FAILURES" -eq 0 ]; then echo "All tests passed."; else echo "$FAILURES test(s) failed."; fi
exit $FAILURES
```

**CI run-list to extend:**
```yaml
# SOURCE: .github/workflows/ci.yml (test job, run: block)
          bash scripts/notify.test.sh
          bash scripts/night_shift_decide.test.sh
          ...
```

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `scripts/notify_contract.test.sh` | CREATE | Seam-4 two-fire contract test (primitive-contract half + settings config-guard); `chmod +x` |
| `.claude/settings.shared.json` | UPDATE | Remove both `Notification` hooks (`permission_prompt`, `idle_prompt`); drop the now-empty `hooks` object |
| `.github/workflows/ci.yml` | UPDATE | Add `bash scripts/notify_contract.test.sh` to the test run-list |
| `scripts/sync.sh` | UPDATE | Remove the 4 stale no-python3 fallback notes that name the two Notification hooks (consistency; not test-asserted) |

## Tasks
Ordered so the check command is proven by a red→green flip (CLAUDE.md "verify-check-commands").

### Task 1: Create the Seam-4 contract test — run it RED against the known-bad case
- File: `scripts/notify_contract.test.sh`
- Action: CREATE (then `chmod +x`)
- Implement: header comment "Seam 4 — Night Shift two-fire notification contract". `set -euo pipefail`;
  `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"`; `HOOK="$SCRIPT_DIR/../.claude/hooks/notify.sh"`;
  `SETTINGS="$SCRIPT_DIR/../.claude/settings.shared.json"`; `mktemp -d` workspace + `trap … EXIT`;
  `FAILURES=0`; `cap`/`assert_rc0`/`assert_empty`/`assert_lines` helpers copied from `notify.test.sh:44-66`;
  the curl shim from `notify.test.sh:19-33`. Two halves:
  - **Primitive-contract half** (the two fires reach the phone; per-step does not):
    - escalate → `cap env -u TMUX NTFY_TOPIC=t bash "$HOOK" fail "Escalation" "task stuck after K"`;
      `assert_lines "$CURL_LOG" 1 "escalate (fail) pushes exactly once"`; `assert_rc0`; `assert_empty "$OUT"`.
    - pr-ready → `: > "$CURL_LOG"; cap env -u TMUX NTFY_TOPIC=t bash "$HOOK" pass "Validate PASS" "branch: PR ready"`;
      `assert_lines "$CURL_LOG" 1 "pr-ready (pass) pushes exactly once"`; `assert_rc0`.
    - per-step → `: > "$CURL_LOG"; cap env -u TMUX NTFY_TOPIC=t bash "$HOOK" info "Permission needed" "M"`;
      `assert_lines "$CURL_LOG" 0 "per-step (info) never pushes to the phone"`; `assert_rc0`.
  - **Config-guard half** (per-step nudge hooks gone; Seam 4 regression guard) — read the real
    versioned settings with python3 and assert **zero** `Notification` hooks remain:
    ```bash
    matchers="$(python3 - "$SETTINGS" <<'PY'
    import json, sys
    d = json.load(open(sys.argv[1]))
    notif = d.get("hooks", {}).get("Notification", [])
    print(",".join(b.get("matcher","") for b in notif if isinstance(b, dict)))
    PY
    )"
    if [ -n "$matchers" ]; then
      echo "FAIL: per-step Notification hooks must be gone (permission_prompt/idle_prompt); found: $matchers"
      FAILURES=$((FAILURES + 1))
    fi
    ```
  - Footer + `exit $FAILURES` per `notify.test.sh:110-116`.
- Mirror: `scripts/notify.test.sh:19-66,77-101,110-116`; `scripts/sync.sh:219,236-240`; `scripts/sync.test.sh:304-309`.
- Validate: `bash scripts/notify_contract.test.sh` → **expected RED here**: the primitive-contract
  half passes, but the config-guard FAILS with "per-step Notification hooks must be gone … found:
  permission_prompt,idle_prompt" (hooks still in settings). Record this red output — it proves the
  guard detects the known-bad case.

### Task 2: Remove the two Notification hooks — flip the guard GREEN
- File: `.claude/settings.shared.json`
- Action: UPDATE
- Implement: delete the entire `"hooks": { "Notification": [ … ] }` block (both `permission_prompt`
  and `idle_prompt` entries). It is the only member of `hooks`, so drop the whole `hooks` key,
  leaving the file as just `{ "permissions": { … } }`. Keep valid JSON (no trailing comma after
  `permissions`).
- Mirror: current `.claude/settings.shared.json` structure (permissions block stays verbatim).
- Validate:
  - `python3 -c "import json; json.load(open('.claude/settings.shared.json'))"` → parses.
  - `bash scripts/notify_contract.test.sh` → **now GREEN** (`All tests passed.`). The Task 1 red →
    Task 2 green flip is the grounding required by "verify-check-commands".
  - `bash scripts/notify.test.sh` → still `All tests passed.` (notify.sh untouched).
  - `bash scripts/sync.test.sh` → still `All tests passed.` (uses its own fixture, not this file).

### Task 3: Wire the contract test into CI
- File: `.github/workflows/ci.yml`
- Action: UPDATE
- Implement: add `          bash scripts/notify_contract.test.sh` to the `run:` block, adjacent to
  the existing `bash scripts/notify.test.sh` line (match indentation exactly).
- Mirror: `.github/workflows/ci.yml` run-list.
- Validate: `grep -n 'notify_contract.test.sh' .github/workflows/ci.yml` → one hit.

### Task 4: Remove the stale sync.sh fallback notes (consistency)
- File: `scripts/sync.sh`
- Action: UPDATE
- Implement: in the `if ! command -v python3` fallback branch, delete the two `note` lines naming
  the Notification hooks in the dry-run sub-branch (`:152-153`, the `"would add Notification hook:
  permission_prompt/idle_prompt"` lines) and the two in the non-dry sub-branch (`:160-161`, the
  `hooks.Notification[permission_prompt]/[idle_prompt]` manual-instruction lines). Leave every
  other note (PreToolUse/Stop/defaultMode/git-push ask) intact — those still reflect what sync does.
  This branch is never exercised by CI/tests (python3 present), so it is consistency-only.
- Mirror: surrounding `note "…"` lines in `scripts/sync.sh:146-162`.
- Validate: `grep -nc 'Notification' scripts/sync.sh` shows only the still-valid python3-path
  references (lines ~219,236-240,260,284,302 region), none in the `146-162` fallback branch;
  `bash scripts/sync.test.sh` → still `All tests passed.`

## Validation
Mechanical gate (run all, expect green after Task 2+):
```
bash scripts/notify_contract.test.sh   # All tests passed.  (was RED before Task 2 — record the flip)
bash scripts/notify.test.sh            # All tests passed.  (notify.sh unchanged)
bash scripts/sync.test.sh              # All tests passed.  (fixture-driven; unaffected)
python3 -c "import json; json.load(open('.claude/settings.shared.json'))"   # valid JSON
grep -n 'notify_contract.test.sh' .github/workflows/ci.yml                  # wired into CI
git diff --stat .claude/hooks/notify.sh                                     # EMPTY — notify.sh untouched
bash .claude/validate.sh               # piv_check (PIV invariants) green
```
End-to-end / contract:
1. **Check command flips** (the core grounding): `git stash` the settings edit (or check out the
   pre-Task-2 file) → `bash scripts/notify_contract.test.sh` FAILS on the config-guard; restore →
   PASSES. Confirms the guard distinguishes known-bad from known-good.
2. **Two fires reach the phone:** with `NTFY_TOPIC` set in `notify.local.conf`, run
   `bash .claude/hooks/notify.sh fail "Escalation" "stuck"` and `… pass "Validate PASS" "b: PR ready"`
   → each yields one push; `… info "Permission needed" "x"` → no push.
3. **Nudge hooks gone at the source:** `python3 -c "import json;print(json.load(open('.claude/settings.shared.json')).get('hooks'))"`
   → `None` (no Notification hooks remain to fire mid-loop).

## Acceptance Criteria
- [ ] All tasks completed
- [ ] `permission_prompt` and `idle_prompt` Notification hooks removed from `.claude/settings.shared.json` (hooks key dropped; valid JSON)
- [ ] `.claude/hooks/notify.sh` unchanged (`git diff` empty)
- [ ] `scripts/notify_contract.test.sh` asserts notify pushes for escalate (`fail`) and pr-ready (`pass`)
- [ ] Same test asserts the per-step level (`info`) never pushes (notify does not fire on per-step/per-phase)
- [ ] Same test asserts zero `Notification` nudge hooks remain in settings (regression guard — Seam 4)
- [ ] The config-guard check command was observed RED (Task 1, hooks present) → GREEN (Task 2, hooks removed)
- [ ] Contract test wired into `.github/workflows/ci.yml` and green; `notify.test.sh` and `sync.test.sh` still green
- [ ] Follows existing patterns (test harness, python3 settings read, CI run-list)
