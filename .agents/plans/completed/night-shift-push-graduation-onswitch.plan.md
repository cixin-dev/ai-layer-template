# Plan: Night Shift — push-graduation on-switch + preserved dangerous-push deny floor

## Summary
Make graduating `git push` from `ask` → `allow` the **single, documented on-switch** for the
Night Shift, and lock — by test — that the dangerous-push deny floor stays enforced
**independently** of that dial. The machinery already exists: the shared posture ships
`git push` on `ask` (`.claude/settings.shared.json`), `sync.sh` is graduation-aware
(ADR-0017), and `security_guard.py` denies force-push / push-to-default in every mode
(ADR-0020). This slice is therefore *documentation + regression locks*, not new behavior:
(1) a README operator how-to naming graduation as the on-switch; (2) a dial-independence
regression block **plus** a structural "the hook reads no settings" assertion in
`security_guard.test.sh`; (3) a shipped-posture guard in `sync.test.sh` that the versioned
default never pre-graduates `git push`. `security_guard.py` behavior is **not** touched
(PRD Out of Scope). Verified: `security_guard.py` reads only `json.load(sys.stdin)` — no
`open(`, no settings read — so the floor is structurally blind to the dial.

## User Story
As an operator, I want enabling the whole Night Shift to be one deliberate, auditable dial
(`git push: ask → allow`) — while the force-push / push-to-default-branch floor keeps denying
regardless — so that turning on unattended push never silently relaxes the hard safety floor.

## Metadata
| Field | Value |
|-------|-------|
| Type | ENHANCEMENT (docs + regression tests; no behavior change) |
| Complexity | LOW–MEDIUM |
| Systems affected | `README.md`, `scripts/security_guard.test.sh`, `scripts/sync.test.sh` |
| Issue | #59 |

## Assumptions & Risks
| Claim | VERIFIED / ASSUMED | Evidence (probe command + result) or mitigation |
|-------|--------------------|--------------------------------------------------|
| `security_guard.py` reads no settings/permissions — only the stdin tool payload — so the floor is structurally independent of the dial | **VERIFIED** | `grep -nE 'settings\.json\|permissions\|defaultMode\|open\(' .claude/hooks/security_guard.py` → no matches. `grep -nE 'json\.load\|sys\.stdin\|sys\.argv\|os\.environ' …` → only `194: data = json.load(sys.stdin)`. The structural test's grep returns empty against current source → PASS. |
| The dangerous-push floor denies force-push + push-to-default in every mode (unaffected by `allow`) | **VERIFIED** | `bash scripts/security_guard.test.sh` → "All tests passed." Existing deny cases at `security_guard.test.sh:58-77,111-115`. |
| `sync.sh` does not re-add a graduated (`allow`) `git push` back to `ask` (AC #3, ADR-0017) | **VERIFIED** | Existing `test(shared-e)` at `sync.test.sh:350-366` seeds live `allow:[Bash(git push *)]` and asserts no `ask` re-add. `bash scripts/sync.test.sh` → "All tests passed." No new code needed; this slice only re-confirms it. |
| Shipped posture ships un-graduated (`git push` on `ask`, not `allow`) | **VERIFIED** | `cat .claude/settings.shared.json` → `ask:["Bash(git push *)"]`; `allow` holds only Skill/Read entries. New `test(shared-g)` locks this against drift. |
| `security_guard.test.sh` is run by CI but **not** by `.claude/validate.sh` (only `piv_check.sh`) | **VERIFIED** | `.claude/validate.sh` delegates to `scripts/piv_check.sh`; CI runs the test at `.github/workflows/ci.yml:21`. Mitigation: run both `*.test.sh` suites explicitly in Implement/Validate. |
| README is in-scope; CONTEXT.md / ADR edits are out-of-scope for this slice | **VERIFIED (convention)** | PRD `.agents/prds/piv-ralph-loop.prd.md:228,235-236` lists "Any change to … `security_guard.py` deny floor" and "Editing CONTEXT.md / ADRs" as Out of Scope. README is not listed. The on-switch concept is already in CONTEXT.md:186-190 + ADR-0017/0020; README adds the operator *how-to*. |

## Patterns to Follow

**Behavioral deny/allow one-liners** (mirror exactly — same quoting, `assert_*` + label):
```bash
# SOURCE: scripts/security_guard.test.sh:58-66
# --- DENY: dangerous git push — force-push + push-to-default-branch (ADR-0020, RC=2) ---
assert_deny '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'  "deny: push --force main"
assert_deny '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'          "deny: push origin main"
assert_allow '{"tool_name":"Bash","tool_input":{"command":"git push origin feature"}}'      "allow: push origin feature"
```

**Helpers available** (do not redefine): `run_hook`, `assert_deny`, `assert_allow`,
`assert_fail_open`, the `$HOOK` path var, and the `FAILURES` counter
(`security_guard.test.sh:7,11-46`). The summary/exit footer is at `:120-126` — insert new
blocks **before** it.

**Inline-python JSON probe inside a test** (mirror for the shared-posture parse):
```bash
# SOURCE: scripts/sync.test.sh:356-362  (test shared-e reads ask[] from a settings file)
ask_has_push="$(python3 - "$CLAUDE_HOME_DIR/settings.json" <<'PYEOF'
import json, sys
data = json.loads(open(sys.argv[1]).read())
ask = data.get("permissions", {}).get("ask", [])
print("yes" if "Bash(git push *)" in ask else "no")
PYEOF
)"
```

**`sync.test.sh` assertion helpers** (mirror; `grep -qF` substring semantics — choose
sentinel tokens that are NOT substrings of each other): `assert_contains` /
`assert_not_contains` (`sync.test.sh:15-29`). `$SCRIPT_DIR` is the `scripts/` dir
(`sync.test.sh:4`), so the real shared file is `"$SCRIPT_DIR/../.claude/settings.shared.json"`.

**README operator section style** (mirror the imperative, fenced-command voice):
```
# SOURCE: README.md:77-94  (## Sync — imperative steps + fenced shell + one explanatory paragraph)
```

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `README.md` | UPDATE | New `## Enabling the Night Shift (the push dial)` operator section — AC #1 |
| `scripts/security_guard.test.sh` | UPDATE | Dial-independence deny regression + structural settings-blind assertion — AC #2, #4 |
| `scripts/sync.test.sh` | UPDATE | `test(shared-g)`: shipped posture keeps `git push` on `ask`, not `allow` — AC #1 default-safe |

**Explicitly NOT changed:** `.claude/hooks/security_guard.py` (behavior frozen — PRD Out of
Scope; AC #4) and `.claude/settings.shared.json` (graduation is a live-settings edit, never a
shared-file edit — ADR-0017). Implement must leave both byte-identical.

## Tasks
Ordered, atomic, each independently verifiable.

### Task 1: README on-switch operator how-to
- File: `README.md`
- Action: UPDATE
- Implement: Insert a new top-level section **after the `## Sync` block (after line 123) and
  before `## After syncing` (line 125)**. Content must: name graduation (`git push` `ask` →
  `allow` in the **live** `~/.claude/settings.json`) as the **single on-switch**; state that
  the shared posture ships un-graduated and `sync.sh` never auto-graduates (so it is always a
  deliberate act); give the exact `allow`/`ask` edit; note re-`sync` won't regress it
  (ADR-0017); give the off-switch (move back to `ask`); and state that the force-push /
  push-to-default floor in `security_guard.py` stays denied regardless (ADR-0020), verifiable
  with `bash scripts/security_guard.test.sh`. Draft:
  ```markdown
  ## Enabling the Night Shift (the push dial)

  The whole Night Shift has a **single on-switch**: graduating `git push` from `ask` to
  `allow`. Until you flip it, every push pauses for your approval — the human checkpoint.

  The shared posture ships **un-graduated** (`.claude/settings.shared.json` keeps
  `Bash(git push *)` on `ask`) and `sync.sh` never auto-graduates it, so enabling unattended
  push is always your deliberate act. To graduate, edit your **live**
  `~/.claude/settings.json` and move that one entry from `ask` to `allow`:

  ```jsonc
  "permissions": {
    "allow": [ "Bash(git push *)" ],   // ← moved here to enable the Night Shift
    "ask":   [ /* git push removed */ ]
  }
  ```

  A re-`sync` will not spring it back to `ask` — the merge is graduation-aware (ADR-0017).
  To turn the Night Shift back off, move the entry back to `ask`.

  Graduating benign push does **not** relax the hard floor: force-push and
  push-to-the-default-branch stay denied in every mode by `.claude/hooks/security_guard.py`
  (ADR-0020), which is independent of this dial. Confirm the floor with
  `bash scripts/security_guard.test.sh`.
  ```
- Mirror: `README.md:77-94`
- Validate: section renders; `## After syncing` still immediately follows; no CONTEXT.md/ADR touched (`git diff --name-only` lists only README.md for this task).

### Task 2: Dial-independence regression + structural settings-blind assertion
- File: `scripts/security_guard.test.sh`
- Action: UPDATE
- Implement: Insert two blocks **before the FAIL-OPEN section (before line 117)**.
  (a) A dial-independence deny block framed as the issue-#59 invariant — the floor holds when
  benign push is graduated `ask`→`allow`:
  ```bash
  # --- DIAL-INDEPENDENCE: floor holds when benign push is graduated ask→allow (issue #59) ---
  # AC #2/#4: graduating `git push` ask→allow (the Night Shift on-switch, ADR-0017) must NOT
  # relax the dangerous-push floor. The hook never reads settings (see STRUCTURAL below), so
  # these denials hold in every dial state; the cases lock the canonical force/default pair.
  assert_deny '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'  "deny: force-push to main holds when push graduated"
  assert_deny '{"tool_name":"Bash","tool_input":{"command":"git push -f origin feature"}}'     "deny: force-push to feature holds when push graduated"
  assert_deny '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'           "deny: push-to-default holds when push graduated"
  assert_deny '{"tool_name":"Bash","tool_input":{"command":"git push origin HEAD:master"}}'    "deny: push-to-default (master refspec) holds when push graduated"
  assert_allow '{"tool_name":"Bash","tool_input":{"command":"git push origin feature"}}'       "allow: benign feature push — the graduated path"
  ```
  (b) A structural assertion that the hook is settings-blind (executably locks independence):
  ```bash
  # --- STRUCTURAL: the floor is independent of the permission dial (issue #59, AC #2/#4) ---
  # The deny floor must hold regardless of whether `git push` is graduated, because
  # security_guard.py reads ONLY the stdin tool payload — never settings.json / the permission
  # layer. Lock that: a change making the hook consult settings would couple floor to dial.
  forbidden="$(grep -nE 'settings\.json|permissions|defaultMode|open\(' "$HOOK" || true)"
  if [ -n "$forbidden" ]; then
    echo "FAIL: structural: security_guard.py reads settings/permissions — floor must stay dial-independent:"
    echo "$forbidden"
    FAILURES=$((FAILURES + 1))
  fi
  ```
- Mirror: deny one-liners `security_guard.test.sh:58-66`; `FAILURES` increment pattern
  `security_guard.test.sh:21-22`; `$HOOK` var `:5`.
- Validate: `bash scripts/security_guard.test.sh` → "All tests passed." (Sanity-check the
  structural guard actually bites: temporarily append `# settings.json` to a comment line in
  a *throwaway copy* of the hook and confirm the grep would fire — do **not** modify the real
  hook.)

### Task 3: Shipped-posture guard — shared file stays un-graduated
- File: `scripts/sync.test.sh`
- Action: UPDATE
- Implement: Insert `test(shared-g)` **after `test(shared-f)` (after line 382) and before the
  summary footer (before line 384)**. Read the **real** repo shared file and assert
  `Bash(git push *)` is on `ask` and **not** on `allow`. Use sentinel tokens that are not
  substrings of one another (so `grep -qF` can't false-match):
  ```bash
  # --- Test (shared-g): the SHIPPED posture stays un-graduated — git push on `ask`, not `allow` ---
  # AC #1: graduation (ask→allow) is the operator's single deliberate edit to LIVE settings.
  # The versioned shared posture must never ship `git push` pre-graduated, or a sync would
  # silently graduate everyone and the on-switch would stop being a deliberate act.
  SHARED="$SCRIPT_DIR/../.claude/settings.shared.json"
  posture="$(python3 - "$SHARED" <<'PYEOF'
  import json, sys
  d = json.loads(open(sys.argv[1]).read())
  perm = d.get("permissions", {})
  print("PUSH_ON_ASK" if "Bash(git push *)" in perm.get("ask", []) else "PUSH_NOT_ON_ASK")
  print("PUSH_ON_ALLOW" if "Bash(git push *)" in perm.get("allow", []) else "PUSH_NOT_GRADUATED")
  PYEOF
  )"
  assert_contains "$posture" "PUSH_ON_ASK"        "test(shared-g): shipped posture keeps git push on ask"
  assert_not_contains "$posture" "PUSH_ON_ALLOW"  "test(shared-g): shipped posture must NOT pre-graduate git push to allow"
  ```
- Mirror: inline-python settings probe `sync.test.sh:356-362`; `assert_contains` /
  `assert_not_contains` `sync.test.sh:15-29`; `$SCRIPT_DIR` `:4`.
- Validate: `bash scripts/sync.test.sh` → "All tests passed."

### Task 4: Verify floor behavior unchanged + AC #3 still locked (no file changes)
- File: — (verification only)
- Action: VERIFY
- Implement: Confirm `security_guard.py` and `settings.shared.json` are byte-identical to
  `main` (`git diff --name-only` must NOT list either). Re-run both suites and confirm
  `test(shared-e)` (AC #3) still passes.
- Validate: `git diff --name-only` lists only `README.md scripts/security_guard.test.sh
  scripts/sync.test.sh`; `bash scripts/security_guard.test.sh && bash scripts/sync.test.sh`
  both print "All tests passed."

## Validation
Project checks (run from repo root):
```bash
bash scripts/security_guard.test.sh   # AC #2, #4 — dial-independence + structural guard
bash scripts/sync.test.sh             # AC #1 default-safe (shared-g) + AC #3 (shared-e)
bash .claude/validate.sh              # PIV gate (piv_check.sh) — fails open on missing items
git diff --name-only                  # must be exactly the 3 intended files
```
End-to-end / AC mapping:
- **AC #1** — README names graduation as the single on-switch with the exact edit; `test(shared-g)` locks the shipped default to `ask` so the on-switch stays a deliberate act.
- **AC #2** — dial-independence deny block + structural grep prove the floor denies regardless of the `allow` dial.
- **AC #3** — existing `test(shared-e)` (re-confirmed) proves `sync.sh` won't re-add a graduated push to `ask`.
- **AC #4** — `git diff` proves `security_guard.py` is untouched; the structural assertion proves it stays settings-blind.

Reminder (not this plan's deliverable): `/validate` Phase 5 authors the PR-body
`## 變更說明` (Traditional Chinese), per ADR-0022 — not a CI gate.

## Acceptance Criteria
- [ ] Graduation (`git push` `ask` → `allow`) is documented in README as the single on-switch, with the exact edit and the off-switch (AC #1)
- [ ] `security_guard.test.sh` extended: dial-independence deny regression + structural settings-blind assertion; suite green (AC #2, #4)
- [ ] `sync.test.sh` `test(shared-g)` locks shipped posture to `ask`, not `allow`; suite green (AC #1 default-safe)
- [ ] `test(shared-e)` still passes — sync does not regress a graduated dial (AC #3, ADR-0017)
- [ ] `security_guard.py` and `settings.shared.json` byte-identical to `main` — floor not weakened (AC #4)
- [ ] All three suites pass with zero failures; `git diff --name-only` lists only the 3 intended files
- [ ] Follows existing patterns (one-liner asserts, inline-python probe, README operator voice)
- [ ] Every external-behavior claim VERIFIED by a probe (see Assumptions & Risks) or carried as an explicit risk
