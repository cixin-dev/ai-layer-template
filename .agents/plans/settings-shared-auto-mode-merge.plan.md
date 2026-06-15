# Plan: settings.shared.json + auto-mode merge into ~/.claude

## Summary
Ship the unattended-autonomy *posture* as a versioned, inert `.claude/settings.shared.json`
and teach `scripts/sync.sh` to additively merge it into the live `~/.claude/settings.json`
the ADR-0003 way (one source in repo → synced once to user scope → one live copy). The
shared file carries `permissions.defaultMode: "auto"`, `permissions.ask: ["Bash(git push *)"]`,
two explicit `hooks.Notification` matcher blocks (`permission_prompt`, `idle_prompt`, each
running its own `notify-send`), and **no** `allow`/`deny` block. The merge unions `ask`/`allow`
(dedupe, preserve existing), sets `defaultMode` only when absent, is **graduation-aware**
(does not re-add the `git push` `ask` entry when the operator has moved `Bash(git push *)`
into live `allow` — a general "never add an `ask` entry the live `allow` already covers"
invariant, ADR-0017's surviving concern), emits a **loud warning** whenever live `defaultMode`
is **any** non-`auto` value (the skip silently no-ops the whole posture), appends Notification
blocks **deduped by `matcher`**, and reuses the existing single `.bak`, `[sync] would …` dry-run
style, idempotency, and fail-open-with-manual-snippet behavior. The posture is documented in
CONTEXT.md (US-18). This slice keeps `git push` **un-graduated** (on `ask`); graduation stays
blocked until the deterministic dangerous-push floor (ADR-0020 / Issue #36) ships.

> **Sequencing — BLOCKED-BY #36 (grill 2026-06-16).** This slice must **not** ship
> `defaultMode: auto` until the dangerous-push floor (#36, ADR-0020) lands in
> `security_guard.py` first. Rationale: with `auto` enabled and no floor, dangerous push has
> **zero** deterministic guard — the classifier approves force/main push (spike Probe 2,
> `behavior=allow`), `security_guard.py` carries no push floor yet (#36 unstarted), and whether
> `git push: ask` even survives under `auto` was **never cleanly probed** (spike C(b) failed:
> only user scope grants `auto`, so the project-scope probe ran in default mode). Shipping the
> hook floor first makes `auto` safe **regardless** of the unverified ask-vs-auto precedence,
> because the floor gates dangerous push outside the permission layer entirely (ADR-0020 GO
> condition). Build order: **#36 floor → then this slice's `auto` posture.**

## User Story
As an operator running N parallel worktree agents, I want one versioned posture file that
`sync.sh` additively merges into my live settings — switching agents to unattended `auto`
mode while keeping `git push` as the single human checkpoint — so that I get unattended
autonomy without hand-maintaining an allowlist, and without a sync ever silently
un-graduating my deliberate dial flip.

## Metadata
| Field | Value |
|-------|-------|
| Type | NEW (+ ENHANCEMENT of `scripts/sync.sh`) |
| Complexity | MEDIUM |
| Systems affected | `.claude/settings.shared.json` (new), `scripts/sync.sh` (Python merge), `scripts/sync.test.sh` (tests), `CONTEXT.md` (docs) |
| Issue | #27 — **blocked-by #36** (dangerous-push floor, ADR-0020); spike #26 → ADR-0017/0018/0020 |

## Assumptions & Risks
| Claim | VERIFIED / ASSUMED | Evidence (probe command + result) or mitigation |
|-------|--------------------|--------------------------------------------------|
| Claude Code does **not** auto-load `settings.shared.json` (so versioning it in-repo is inert/safe) | **VERIFIED** | Spike Probe A (`.agents/reports/spike-autonomy-probes-report.md`): file watcher lists only `settings.json` / project `settings.json` / `settings.local.json`; `settings.shared.json` not watched/loaded. |
| `permissions.defaultMode: "auto"` is honored at **user scope** (where sync writes) and ignored at project/local scope | **VERIFIED** | Spike Probe 1 & B: user scope → `canEnterAuto=true`, no warning; project scope → `defaultMode "auto" ignored` WARN. sync writes `~/.claude/settings.json` = user scope. |
| Graduation marker = `Bash(git push *)` present in live `permissions.allow`; sync must not re-add the `ask` entry when present | **VERIFIED (decision)** | ADR-0017 Decision (`docs/adr/0017-…md:32-37`): "if `Bash(git push *)` is already in the live `permissions.allow`, the merge does not re-add it to `ask`." Carried forward by ADR-0020 ("sync must not silently regress a deliberate graduation"). |
| The classifier is **not** a floor for dangerous push | **VERIFIED** | Spike Probe 2: true `auto`, no allow rule → `git push origin main` and `git push --force origin main` both logged `mode=auto, behavior=allow`; pushes landed. |
| Shipping `defaultMode: auto` in this slice is safe before the floor, because `git push: ask` holds as the checkpoint under `auto` | **REFUTED / UNVERIFIED → resequenced** | The premise that `ask` forces a prompt under `auto` was **never cleanly probed** (spike C(b) failed — project scope can't grant `auto`). Rather than depend on it, this slice is **blocked-by #36**: ship the deterministic dangerous-push floor in `security_guard.py` first, after which `auto` is safe independent of ask-vs-auto precedence (ADR-0020 GO condition). The floor is a **blocking prerequisite**, not out-of-scope. |
| The Python heredoc accepts an extra `argv` (shared-settings path) and `json` round-trips the structure without reordering breakage | **VERIFIED (trivially, by construction)** | Same pattern already in `scripts/sync.sh:154` (`python3 - "$SETTINGS" … <<'PYEOF'`); JSON load→mutate→`json.dumps(indent=2)` is the existing idempotent write path (`scripts/sync.sh:224`). The new test suite (cases a–f) is the verification of merge correctness. |
| Exact `hooks.Notification` matcher tokens (`permission_prompt`, `idle_prompt`) fire correctly at Claude Code runtime | **TO PROBE EARLY (grounding required)** | "Issue #27 dictates the token" is the *requirement source*, not evidence of runtime behavior — and CLAUDE.md's Verification-led rule forbids asserting external-component behavior from docs/reasoning alone. The cost of a wrong token is asymmetric and silent: the operator gets **no** permission/idle notification, defeating the posture's core UX, and no merge-logic test catches it. **Action:** before relying on these blocks, confirm `permission_prompt` / `idle_prompt` are real Claude Code Notification matcher values (check CC's Notification matcher docs/source, or fire one and observe `notify-send`). Upgrade to VERIFIED on success; if unverifiable, mark the blocks as known-untriggered and track separately. |
| Adding `settings.shared.json` to the test fixture's `setup_fixture` does not break existing hook tests (a–n) | **ASSUMED → de-risk first** | Existing tests assert presence/absence of `would link` / `would copy` / `would wire hook` only — none assert absence of the new permission/notification lines. First Implement step after editing `setup_fixture`: run the full `sync.test.sh` and confirm a–n still pass before adding new cases. |

## Patterns to Follow

**1. The additive Python merge + dry-run/real split + single `.bak` (extend this exact block).**
```python
# SOURCE: scripts/sync.sh:154-229
python3 - "$SETTINGS" "$SG_CMD" "$VG_CMD" "$DRY_RUN" <<'PYEOF'
import json, sys, shutil, pathlib
settings_path = pathlib.Path(sys.argv[1])
...
try:
    data = json.loads(settings_path.read_text()) if settings_path.exists() else {}
except Exception as e:
    if dry_run: ...   # fail-open dry-run lines
    else: ...         # fail-open manual snippet
    sys.exit(0)
...
if dry_run:
    if needs_pre:  print(f"[sync] would wire hook: PreToolUse -> security_guard.py", flush=True)
else:
    ...
    if needs_pre or needs_stop:
        bak_path = pathlib.Path(str(settings_path) + ".bak")
        if settings_path.exists() and not bak_path.exists():
            shutil.copy2(settings_path, bak_path)
        settings_path.write_text(json.dumps(data, indent=2) + "\n")
PYEOF
```
Mirror: pass a 6th argv (`$SHARED_SETTINGS` path), keep all writes behind `if not dry_run`,
reuse the one `.bak`/`needs_*`→write gate, reuse the `[sync] would …` line style.

**2. Fail-open-with-manual-snippet when python3 is absent.**
```bash
# SOURCE: scripts/sync.sh:144-152
if ! command -v python3 >/dev/null 2>&1; then
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would wire hook: ..."
  else
    note "warn: python3 not found — wire hooks manually by adding to $SETTINGS:"
    ...
  fi
else
  python3 - ... <<'PYEOF' ... PYEOF
fi
```
Mirror: the new posture lines must also appear in this no-python3 branch (both dry-run "would"
form and real-run manual-snippet form), so behavior is uniform when python3 is missing.

**3. Test fixture + redirection + assertion helpers.**
```bash
# SOURCE: scripts/sync.test.sh:63-91 (setup_fixture), 15-45 (assert_contains/_not_contains/_file_exists)
setup_fixture() {
  rm -rf "$REPO" "$CLAUDE_HOME_DIR"
  mkdir -p "$REPO/.claude/skills/piv-loop" ...
  # ADD: write $REPO/.claude/settings.shared.json (the posture file)
}
output="$(SYNC_REPO_DIR="$REPO" CLAUDE_HOME="$CLAUDE_HOME_DIR" bash "$SYNC_SH" --dry-run)"
assert_contains "$output" "..." "msg"
```
Mirror: every new case uses `SYNC_REPO_DIR`/`CLAUDE_HOME` redirection (never touches real
`~/.claude`); seed live `~/.claude/settings.json` per-case via `python3`/heredoc as needed
(see `scripts/sync.test.sh:251-266` for the in-test JSON-mutation pattern).

**4. Glossary-prose style for the posture doc.**
```markdown
# SOURCE: CONTEXT.md:174-193 (### Unattended Autonomy, **sandbox** entry)
### Unattended Autonomy
The posture that lets N parallel agents run without per-tool-use approval: verify *outputs* …
**sandbox**: …
_Avoid_: …
```
Mirror: add the auto-approved / gated / why prose under this existing heading; cross-reference
ADR-0018, ADR-0020, and note graduation is blocked until the #36 floor ships (ADR-0020).

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `.claude/settings.shared.json` | CREATE | The inert, versioned posture: `defaultMode: auto`, `ask: ["Bash(git push *)"]`, two Notification matcher blocks; no `allow`, no `deny`. |
| `scripts/sync.sh` | UPDATE | Extend the Python merge (and the no-python3 fail-open branch) to read `settings.shared.json` and additively merge permissions + Notification hooks, graduation-aware, with the loud `default` warning. |
| `scripts/sync.test.sh` | UPDATE | Add `settings.shared.json` to `setup_fixture`; add dry-run/real cases a–f. |
| `CONTEXT.md` | UPDATE | Document the autonomy posture (auto-approved / gated / why) under `### Unattended Autonomy` (US-18). |

## Tasks
Ordered, atomic, each independently verifiable. Build the posture file first (it is the input
to everything else), then the tests (red), then the merge (green), then docs.

### Task 1: Create the posture file `.claude/settings.shared.json`
- File: `.claude/settings.shared.json`
- Action: CREATE
- Implement: Write exactly:
  ```json
  {
    "permissions": {
      "defaultMode": "auto",
      "ask": [
        "Bash(git push *)"
      ]
    },
    "hooks": {
      "Notification": [
        {
          "matcher": "permission_prompt",
          "hooks": [
            { "type": "command", "command": "notify-send 'Claude Code' 'Permission needed'" }
          ]
        },
        {
          "matcher": "idle_prompt",
          "hooks": [
            { "type": "command", "command": "notify-send 'Claude Code' 'Waiting for input'" }
          ]
        }
      ]
    }
  }
  ```
  No `permissions.allow` (its absence is the point — ADR-0018). No `deny` (the dangerous-push
  floor is ADR-0020/#36, not a settings deny — ADR-0016). The two Notification matchers are
  **separate blocks**, not one catch-all branching via `jq`.
- Mirror: structure mirrors the live `hooks` block shape in `~/.claude/settings.json:8-30`.
- Validate: `python3 -c 'import json;json.load(open(".claude/settings.shared.json"))'` (valid JSON); visual check against acceptance criteria #1.

### Task 2: Add the posture file to the test fixture
- File: `scripts/sync.test.sh`
- Action: UPDATE
- Implement: In `setup_fixture()` (after the hooks block, ~`scripts/sync.test.sh:83`), write a
  `$REPO/.claude/settings.shared.json` containing the same posture JSON as Task 1 (a heredoc
  `cat > "$REPO/.claude/settings.shared.json" <<'JSON' … JSON`). This makes the fixture mirror
  the real repo so `SYNC_REPO_DIR="$REPO"` finds the file.
- Mirror: `scripts/sync.test.sh:80-83` (how hook files are seeded in the fixture).
- Validate: run `bash scripts/sync.test.sh` — **existing cases a–n must still pass** (de-risks
  the "fixture change breaks hook tests" assumption) before adding new cases.

### Task 3: Add merge test cases a–f (red)
- File: `scripts/sync.test.sh`
- Action: UPDATE
- Implement: Append a "settings.shared.json merge" section with six cases, each using
  `SYNC_REPO_DIR`/`CLAUDE_HOME` redirection and seeding live settings via `python3` heredoc
  where a pre-state is needed:
  - **(shared-a) fresh-fixture dry-run plans the posture.** No live `settings.json`. Assert
    output contains a "would set defaultMode: auto" line, a "would add ask: Bash(git push *)"
    line, and a "would add Notification" line for **both** matchers; assert it does **not**
    plan any toolchain `allow` entry, and dry-run creates no `settings.json`
    (`assert_file_not_exists`).
  - **(shared-b) idempotent.** Real run, then second dry-run plans **no** permission/hook
    additions (`assert_not_contains` the "would set defaultMode" / "would add ask" / "would add
    Notification" lines).
  - **(shared-c) preservation.** Seed live settings with `permissions.allow:["Bash(gws drive:*)"]`
    and `permissions.defaultMode:"plan"`. Real run. Assert `Bash(gws drive:*)` still present and
    `defaultMode` still `"plan"` (not overwritten); assert no `.bak`-less data loss. (Also asserts
    the non-`auto` warning fires for `"plan"` — see shared-d.)
  - **(shared-d) loud no-op on any non-`auto` value.** Run **two** sub-cases — seed live
    `permissions.defaultMode:"default"`, and separately `"plan"`. For each: assert the loud
    warning line is printed (contains `not 'auto'` and the live value) and `auto` is **not**
    applied (live `defaultMode` is unchanged after a real run). This pins the grill-2026-06-16
    decision that the warning fires on **every** non-`auto` value, not just `"default"`.
  - **(shared-e) graduation survives.** Seed live `permissions.allow:["Bash(git push *)"]`
    (graduated). Dry-run. Assert it does **not** plan "would add ask: Bash(git push *)"; real
    run leaves no `ask` entry for `git push`.
  - **(shared-f) fail-open + backup.** (i) Real run from fresh creates `.bak`? Note: `.bak` is
    only written when a prior `settings.json` exists — seed a live `settings.json` first, real
    run, assert `settings.json.bak` exists and mutation occurred. (ii) Unparseable live
    `settings.json` (write `not json`) → real run prints a manual-snippet warn and exits 0
    (script continues); dry-run prints the fail-open "would" lines. (Reuse the existing
    `assert_contains "$output" "warn"` style.)
- Mirror: `scripts/sync.test.sh:105-126` (real-run-then-dry-run idempotency), `:247-268`
  (in-test JSON mutation via python heredoc), `:151-163` (real-run file assertions).
- Validate: `bash scripts/sync.test.sh` — new cases **fail** (merge not yet implemented).
  This is the TDD red bar.

### Task 4: Extend the merge in `scripts/sync.sh` (green)
- File: `scripts/sync.sh`
- Action: UPDATE
- Implement:
  1. Add a `SHARED_SETTINGS="$REPO_DIR/.claude/settings.shared.json"` var near
     `SETTINGS=` (`scripts/sync.sh:140`).
  2. Pass `"$SHARED_SETTINGS"` as a 6th argv to the existing `python3 - … <<'PYEOF'`
     invocation (`scripts/sync.sh:154`); read `shared_path = pathlib.Path(sys.argv[5])` and
     `shared = json.loads(shared_path.read_text()) if shared_path.exists() else {}` inside.
  3. After the existing hook-wiring logic, compute posture deltas from `shared` against `data`:
     - **defaultMode** (use `data.setdefault("permissions", {})` — live may have no `permissions`
       key at all): live absent → plan/set `="auto"` ("would set defaultMode: auto"); live present
       and `== "auto"` → leave (idempotent, silent); live present and **any other value**
       (`"default"`, `"plan"`, `"acceptEdits"`, …) → emit the **loud warning**
       `⚠ defaultMode is '<live>', not 'auto' — autonomy posture inactive` (printed in both
       dry-run and real run; not gated behind `needs_*`) and do **not** overwrite. *(Grill
       2026-06-16: the warning fires on **any** non-`auto` value, not just `"default"` — every
       non-`auto` value equally means the posture did not take effect; keying only on `"default"`
       left a silent-no-op hole for `"plan"`/`"acceptEdits"`.)*
     - **ask union (graduation-aware)**: for each entry in `shared.permissions.ask`, skip if it
       is already in live `permissions.allow` (graduation — ADR-0017) **or** already in live
       `permissions.ask`; else plan/add ("would add ask: Bash(git push *)").
     - **allow union**: union `shared.permissions.allow` (empty here) into live — **preserve
       only**, never remove existing entries. (No-op given the shared file has no `allow`, but
       implement the union so the merge is correct if `allow` is ever added.)
     - **Notification hooks**: for each block in `shared.hooks.Notification`, dedupe by
       **`matcher`** against existing `data.hooks.Notification` (a matcher slot already present is
       left untouched); append missing blocks ("would add Notification hook: <matcher>"). *(Grill
       2026-06-16: key on `matcher`, not the inner `command` string — `command` is cosmetic and
       mutable, so deduping by it would append a duplicate `permission_prompt` block whenever the
       notify-send text changes. Mirrors the existing PreToolUse matcher check, `sync.sh:181`.)*
  4. Fold the new "needs write" conditions into the existing single write/`.bak` gate
     (`scripts/sync.sh:220-224`) so `needs_pre or needs_stop or needs_posture` triggers one
     backup + one write.
  5. Mirror the new posture lines into the **no-python3 fail-open branch**
     (`scripts/sync.sh:144-152`): dry-run "would" forms + real-run manual-snippet forms.
- Mirror: `scripts/sync.sh:175-228` (needs-detection → dry-run lines → real mutation → single
  backup+write).
- Validate: `bash scripts/sync.test.sh` — **all** cases (a–n + shared-a–f) pass (green).

### Task 5: Document the autonomy posture in CONTEXT.md (US-18)
- File: `CONTEXT.md`
- Action: UPDATE
- Implement: Under the existing `### Unattended Autonomy` heading (`CONTEXT.md:174`), add a
  prose block (glossary style) stating:
  - **Auto-approved** (sandbox-internal: read / search / test / edit / commit; the whole
    dev/test/git toolchain via `defaultMode: auto`, **no** hand-filled allowlist — ADR-0018).
  - **Gated** (`git push` on `ask` — the single human checkpoint; opaque code execution denied
    by `security_guard.py`; session-end by the validate gate).
  - **Why** (verify outputs at the boundary, not inputs; the classifier is the probabilistic
    inner layer, the deterministic floor lives at the boundary — ADR-0018/0020).
  - **Graduation** is the single dial (`ask`→`allow`) and is **blocked** until the
    deterministic dangerous-push floor ships (ADR-0020 / Issue #36); sync is graduation-aware
    so it never springs the dial back (ADR-0017).
- Mirror: `CONTEXT.md:174-193` (heading + prose + `_Avoid_:` style).
- Validate: visual check against acceptance criteria #8; `bash scripts/piv_check.sh` (the
  validate gate) still passes.

## Validation
- **Unit/merge tests**: `bash scripts/sync.test.sh` → "All tests passed." (existing a–n +
  new shared-a–f). This is the primary gate.
- **Posture file valid JSON**: `python3 -c 'import json;json.load(open(".claude/settings.shared.json"))'`.
- **Project gate**: `bash .claude/validate.sh` (runs `scripts/piv_check.sh`) → green.
- **End-to-end (manual, against a temp `CLAUDE_HOME`, never real `~/.claude`)**:
  ```bash
  tmp=$(mktemp -d)
  SYNC_REPO_DIR="$PWD" CLAUDE_HOME="$tmp" bash scripts/sync.sh --dry-run   # plans posture
  SYNC_REPO_DIR="$PWD" CLAUDE_HOME="$tmp" bash scripts/sync.sh             # writes it
  python3 -m json.tool "$tmp/settings.json"   # defaultMode:auto, ask git push, 2 Notification blocks, gws-drive preserved if seeded
  SYNC_REPO_DIR="$PWD" CLAUDE_HOME="$tmp" bash scripts/sync.sh --dry-run   # plans nothing (idempotent)
  rm -rf "$tmp"
  ```

## Acceptance Criteria
- [ ] `.claude/settings.shared.json` exists with `defaultMode: auto`, the `git push` ask entry, two Notification matchers, no `allow`, no `deny`.
- [ ] `sync.sh --dry-run` against a fresh fixture plans: set `defaultMode: auto`, add the `git push` ask entry, add both Notification hooks; no toolchain `allow` entries.
- [ ] Idempotent: a second run against already-merged settings plans no permission/hook additions.
- [ ] Preservation: existing `Bash(gws drive:*)` is never removed; a non-`default` `defaultMode` (e.g. `plan`) is not overwritten.
- [ ] Loud no-op: against **any** non-`auto` `defaultMode` (`"default"`, `"plan"`, …), the `not 'auto'` warning line is printed and `auto` is **not** applied.
- [ ] Graduation survives: against settings that already graduated `git push` (in `allow`), sync does **not** re-add the `ask` entry.
- [ ] A real run writes `.bak` before mutating; merge fails open with a manual snippet when python3 is missing or the file is unparseable.
- [ ] The autonomy posture is documented in CONTEXT.md (auto-approved / gated / why).
- [ ] All tasks completed; `bash scripts/sync.test.sh` and `bash .claude/validate.sh` pass with zero errors.
- [ ] Every external-behavior claim is VERIFIED by a probe or carried as an explicit risk (Notification runtime firing is the one ASSUMED item, out of scope for this slice).
- [ ] Follows existing patterns (single `.bak`, `[sync] would …` style, fixture redirection).
