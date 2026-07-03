# Plan: Deterministic launch-guard linter (`launch_guard_check.sh`)

## Summary
Close the asymmetry PR #94 left behind: Miss-1 (exec-bit) got a deterministic gate, Miss-2
(an unguarded `*/5` cron missing `flock`) got prose only. Build a deterministic tripwire —
symmetric with `scripts/exec_bit_check.sh` and wired into `.claude/validate.sh` — that scans
**all tracked `*.md`** for **unguarded scheduled launch commands inside ` ```cron ` fenced
blocks**, and fails the gate when it finds one. Scanning the whole `*.md` file class (not a
name-glob subset) mirrors exec_bit_check's all-`*.sh` coverage: no runbook can silently escape
the gate by living outside a designated folder or lacking "runbook" in its name — a
filename-convention scope would reintroduce, at the file-selection layer, the very
silent-miss class #96 exists to kill. Detection is **fence-scoped**: only non-blank,
non-comment lines inside a ` ```cron ` block are candidates; each must carry a guard token
(`flock`/lockfile) or an explicit **`# linter:allow-unguarded-cron: <reason>`** opt-out — the
reason is **required** (a bare marker does *not* exempt), and every exemption is printed for
audit so a lazy bypass costs a self-documenting justification a reviewer can see in the diff.
Out of scope **by design**: single-launch background forms (`bash … &`, `nohup … &` — not
scheduler-reentered, so they can't self-overlap; the runbook §4 persistent form uses one
deliberately) and cron written *outside* a ` ```cron ` fence (systemd timers, `crontab`
installs, ` ```bash ` snippets). That recall boundary is **printed on every run** so a green
result never reads as "covered everything" (CLAUDE.md *"no silent caps"*). The gate
**complements** `/validate` Phase 3.5's prose (which still catches recognition on any branch
and the out-of-scope launch surfaces); it does not replace it.

## User Story
As the operator of this Harness, I want a mechanical gate that fails when a runbook ships a
scheduler-reentered cron line without a `flock` guard, so that the HEAD race (ADR-0024) can't
recur through the exact "a launch line reads as an example, not a check" blind spot that
caused the original Night Shift miss — without me having to *recognize* the danger by eye.

## Metadata
| Field | Value |
|-------|-------|
| Type | REFACTOR (System Evolution / outer-loop hardening) |
| Complexity | MEDIUM (mechanical shape is LOW; the detection rule is the HIGH-risk design, now resolved + probe-verified) |
| Systems affected | `scripts/` (new check + test), `.claude/validate.sh` (wire-in) |
| Issue | #96 |

## Assumptions & Risks
| Claim | VERIFIED / ASSUMED | Evidence (probe command + result) or mitigation |
|-------|--------------------|--------------------------------------------------|
| Fence-scoped rule (candidate = non-blank, non-comment line inside a ` ```cron ` block; require `flock`) is green on the whole tree and flips for the right reason | **VERIFIED** | `probe_final.sh` part A: fence-only scan of **all** tracked `*.md` → only `night-shift-loop-runbook.md:90` `OK` (guarded), **0 offenders**. Part B synthetic: unguarded ```cron → `OFFENDER`; marker **with reason** → `ALLOWED`; **bare marker (no reason) → `OFFENDER`**. Persistent `&` and grounding `flock … echo` lines live in ` ```bash ` fences → never candidates. |
| #94 is merged into local `main`; basing #96 on current `main` has no `validate.sh` adjacency conflict | **VERIFIED** | `gh pr view 94` → `state: MERGED, mergedAt 2026-07-03`. `git log main` shows `78d9483 retroactive: gate script exec-bit…`. `git show main:.claude/validate.sh` already has the exec-bit line + rc aggregation. |
| Scanning **all** tracked `*.md` (not a name-glob subset) yields zero false positives today — fence-scoping ignores the 3 `*/5`-bearing docs because their `*/5` is backtick-prose *outside* any ` ```cron ` fence | **VERIFIED** | `probe_broadscan.sh` + `probe_final.sh` part A → **0 offenders** across all `*.md`. The `*/5` in `CLAUDE.md:136`, `validate.md:80`, `…hybrid-trigger-loop.plan.md:226` is inline `` `*/5` `` prose, never inside a ` ```cron ` block → not a candidate. (This retires the earlier "designated-set" scope: its premise — that these files are false positives — was false; a name-glob would only add a silent recall hole.) |
| exec-bit gate globs **all** tracked `*.sh`, so the two new scripts must be committed `100755` or they self-fail the gate | **VERIFIED** | `scripts/exec_bit_check.sh:23` → `git ls-files --stage -- '*.sh'`. `core.fileMode` is false on this NFS checkout, so `chmod +x` won't stage the bit — must use `git update-index --chmod=+x`. |
| No `*.test.sh` runner exists; tests run by path (like `exec_bit_check.test.sh`), and `validate.sh` wires only the *check*, not its test | **VERIFIED** | `git grep 'test.sh' -- '*.sh'` returns only completed-plan docs, no runner. `grep -c 'test.sh' .claude/validate.sh` → 0. |
| Guard token set `flock\|lockfile\|setlock` is sufficient; other single-instance mechanisms are handled by the reason-required escape hatch | **ASSUMED** (low risk) | The only real guard in-tree is `flock`. Mitigation: the `# linter:allow-unguarded-cron: <reason>` marker covers any exotic guard; Implement's known-good test uses `flock`. Known soundness limit: token *presence* ≠ token *guards this command* (e.g. `flock` in a comment) — accepted; offenders are reviewer-visible and the escape hatch is the pressure valve. |
| Reason-required escape hatch binds: a bare `# linter:allow-unguarded-cron` (no reason) does **not** exempt | **VERIFIED** | `probe_final.sh` part B case c: bare marker above an unguarded cron line → still `OFFENDER`. Only `linter:allow-unguarded-cron:` + a non-empty reason → `ALLOWED` (case b). |

## Patterns to Follow

### The deterministic-gate shape — mirror end to end
```bash
# SOURCE: scripts/exec_bit_check.sh:14-35
set -euo pipefail
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "[exec-bit-check] not a git repo; skipping" >&2
  exit 0
fi
non_exec=$(git ls-files --stage -- '*.sh' | awk '...')   # enumerate → detect
if [ -n "$non_exec" ]; then
  echo "FAIL: ..."; printf '%s\n' "$non_exec" | sed 's/^/  /'
  echo "  Fix: git update-index --chmod=+x <file>"        # print offenders + fix hint
  exit 1
fi
echo "exec-bit check passed (...)."; exit 0
```

### The grounding seam — known-good + known-bad with rc-1 flip proven
```bash
# SOURCE: scripts/exec_bit_check.test.sh:40-58
# known-bad: assert rc is EXACTLY 1 (the check's own fail path), not 127 (forged flip),
# and that the message names the offender.
rc=0
out_bad="$(cd "$BAD" && bash "$CHECK" 2>&1)" || rc=$?
if [ "$rc" -ne 1 ]; then
  echo "FAIL: known-bad should exit 1 (check's fail path), got rc=$rc: $out_bad"
  FAILURES=$((FAILURES + 1))
elif ! printf '%s' "$out_bad" | grep -q "committed non-executable"; then ...
elif ! printf '%s' "$out_bad" | grep -q "tool.sh"; then ...    # names the offender
fi
```

### The wire-in — one line per check, rc aggregates, don't stop at first
```bash
# SOURCE: .claude/validate.sh:5-8
rc=0
bash "$dir/exec_bit_check.sh" || rc=1
bash "$dir/piv_check.sh"      || rc=1
bash "$dir/launch_guard_check.sh" || rc=1   # <-- ADD THIS
exit "$rc"
```

## Detection rule (the spec Implement encodes into `launch_guard_check.sh`)

Grounded end-to-end by `probe_final.sh` (part A: all-`*.md` → 0 offenders; part B: the three
verdicts). Implement should mirror this logic, not re-derive it.

1. **Git guard** — `git rev-parse --git-dir` fails → `echo "[launch-guard-check] not a git repo; skipping" >&2; exit 0` (fail open, mirror `exec_bit_check.sh:16-19`).
2. **Enumerate the whole `*.md` file class** — `git ls-files -- '*.md'` (no name-glob subset;
   symmetric with `exec_bit_check`'s `git ls-files … '*.sh'`). Empty → print pass message, `exit 0`.
3. **Per file, line-scan** with two bits of state — `in_cron` (fence) and `allow_next` (escape hatch armed):
   - **Fence tracking**: a line matching `^```cron` → `in_cron=1`, reset `allow_next=0`; any
     other line matching `^```` (a bare closing fence, or ` ```bash ` etc.) → `in_cron=0`,
     reset `allow_next=0`. *(Markdown fences don't nest — this two-state toggle suffices; probe-confirmed.)*
   - **Candidates exist only while `in_cron=1`.** A cron line written outside a ` ```cron `
     fence is out of scope by design (see the recall boundary in the pass message, step 5).
   - **Escape-hatch marker (reason required)**: a line matching
     `linter:allow-unguarded-cron:[[:space:]]*[^[:space:]]` (the literal marker, a colon, then a
     **non-empty reason**) that is itself a `#`-comment line → set `allow_next=1`, `continue`.
     A **bare** `# linter:allow-unguarded-cron` with no reason does **not** arm the hatch
     (probe case c → still an offender). Also honor the same reason-bearing marker **inline**
     trailing a cron line. Evaluate the marker **before** the comment-skip below (the marker *is* a `#`).
   - **Comment / blank skip**: inside `in_cron`, a blank line or a `^[[:space:]]*#` crontab
     comment (that is *not* an armed marker) → skip and reset `allow_next=0`.
   - **A real scheduled line** = `in_cron` AND non-blank AND not a comment. For each:
     - contains a **guard token** (`flock`, `lockfile`, or `setlock`) → **OK**.
     - else if armed (`allow_next=1`) or a reason-bearing inline marker → record **allowed**
       (`file:line` + reason; report, don't fail).
     - else → record **offender** (`file:line` + trimmed snippet).
     - reset `allow_next=0` after the line.
4. **Verdict** — any offender → print a `FAIL:` block naming each `file:line` + snippet, the fix
   hint (`add flock -n -E 0 <lockfile> before the command — see ADR-0024 (the HEAD race)`), and
   the escape-hatch usage (`# linter:allow-unguarded-cron: <why>` — reason required); `exit 1`.
5. **Pass path** — print `launch-guard check passed`, then **always** print the scope-boundary
   line (CLAUDE.md *"no silent caps"*): *"scanned ` ```cron ` fences in all tracked `*.md`; does
   NOT cover systemd timers, `crontab` installs, cron in non-`cron` fences, or single-launch
   `&`/`nohup` daemons (out of scope by design)."* List any allowed exemptions (file:line + reason). `exit 0`.

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `scripts/launch_guard_check.sh` | CREATE | The deterministic detector (spec above). Committed `100755`. |
| `scripts/launch_guard_check.test.sh` | CREATE | Grounding seam: known-good / known-bad (rc==1) / escape-hatch-with-reason / bare-marker-still-fails / out-of-scope-not-flagged / non-git. Committed `100755`. |
| `.claude/validate.sh` | UPDATE | Wire in `bash "$dir/launch_guard_check.sh" \|\| rc=1`. |

*(No CLAUDE.md change: this closes the gap with a gate, so the `launch-command-grounding`
prose can now lean on a mechanical backstop rather than needing a new bullet — matches the
handoff's "keep CLAUDE.md lean" constraint.)*

## Tasks

### Task 1: Write the grounding seam first (TDD — red)
- File: `scripts/launch_guard_check.test.sh`
- Action: CREATE
- Implement: Mirror `exec_bit_check.test.sh` structure (`mktemp -d` root, `trap … EXIT`,
  `make_repo` helper that inits a git repo with `core.fileMode false` and writes a tracked
  `*.md` file, `FAILURES` counter, `exit "$FAILURES"`). Six cases:
  1. **known-good** — a ` ```cron ` block whose `*/5` line has `flock` → rc 0, output matches `passed`.
  2. **known-bad** — an unguarded ` ```cron ` `*/5` line → assert **rc `-ne 1` is a FAIL** (exactly 1, not 127), output names the file + says unguarded.
  3. **escape-hatch (reason)** — same unguarded line preceded by `# linter:allow-unguarded-cron: <reason>` → rc 0, output reports it as `allowed` with the reason.
  4. **bare-marker-still-fails** — same unguarded line preceded by a **reason-less** `# linter:allow-unguarded-cron` → assert **rc exactly 1** (proves the reason requirement binds; probe case c).
  5. **out-of-scope-not-flagged** — a file (named e.g. `notes.md`, *not* "runbook") whose only launch is a ` ```bash ` `bash night_shift_loop.sh &` (persistent) plus an unguarded `*/5` line **outside** any ` ```cron ` fence → rc 0 (neither is a candidate; also proves all-`*.md` scope doesn't over-reach beyond `cron` fences).
  6. **non-git dir** — → rc 0 (skip / fail open).
- Mirror: `scripts/exec_bit_check.test.sh:14-68`
- Validate: `bash scripts/launch_guard_check.test.sh` — expected RED now (check doesn't exist → non-1 rc), proving the test can fail.

### Task 2: Implement the detector to green the seam
- File: `scripts/launch_guard_check.sh`
- Action: CREATE
- Implement: The Detection rule above. Header comment states the honest scope = **unguarded
  scheduled commands inside ` ```cron ` fences, across all tracked `*.md`**; why single-launch
  `&`/`nohup` are correctly excluded (launched once → can't self-overlap); why the whole
  `*.md` class is scanned (a name-glob would silently skip a misnamed runbook — the exact
  miss); and the ADR-0024 HEAD-race rationale — mirror the didactic header of `exec_bit_check.sh:1-13`.
- Mirror: `scripts/exec_bit_check.sh:14-35` (git guard, enumerate, offender block, fix hint, exit codes).
- Validate: `bash scripts/launch_guard_check.test.sh` → all 6 pass (`exit 0`). Then
  `bash scripts/launch_guard_check.sh` from repo root → passes on the real tree (only the
  guarded `night-shift-loop-runbook.md:90` is a candidate, and it has `flock`), and the pass
  output ends with the scope-boundary line.

### Task 3: Stage the exec bit on both new scripts
- File: `scripts/launch_guard_check.sh`, `scripts/launch_guard_check.test.sh`
- Action: UPDATE (index mode)
- Implement: `git add` both, then `git update-index --chmod=+x scripts/launch_guard_check.sh scripts/launch_guard_check.test.sh` (`chmod +x` alone won't stage it — `core.fileMode` is false on this NFS checkout).
- Mirror: the fix hint in `scripts/exec_bit_check.sh:12`.
- Validate: `git ls-files --stage -- 'scripts/launch_guard_check*.sh'` shows `100755` for both, then `bash scripts/exec_bit_check.sh` still passes.

### Task 4: Wire into the gate
- File: `.claude/validate.sh`
- Action: UPDATE
- Implement: Add `bash "$dir/launch_guard_check.sh" || rc=1` after the `piv_check.sh` line.
- Mirror: `.claude/validate.sh:6-7`
- Validate: `bash .claude/validate.sh` → green on current tree (all three checks pass; PIV skips off-worktree).

## Validation
- **Unit / seam**: `bash scripts/launch_guard_check.test.sh` → `All tests passed.`, rc 0. The
  known-bad case asserts rc **exactly 1** (not a forged 127); the bare-marker case asserts rc
  **exactly 1** too (the reason requirement binds), proving the flip fires for the right reason.
- **Full gate**: `bash .claude/validate.sh` → rc 0 on the current tree (all three checks pass).
- **End-to-end catch (do this live, don't reason it)**: create a scratch `*.md` with an
  unguarded ` ```cron `/`*/5 …` block **and `git add` it** (the check reads `git ls-files` —
  an untracked file is invisible and would give a false green). Run `bash scripts/launch_guard_check.sh`,
  confirm rc 1 + the offender is named; add `# linter:allow-unguarded-cron: <reason>` above it
  → rc 0 + "allowed (reason…)"; strip the reason to a bare marker → rc 1 again. Then
  `git rm --cached` + delete the scratch file.
- **Scope proof**: confirm the real `night-shift-loop-runbook.md` §4 persistent `bash … &`
  form is **not** an offender, and that the pass output ends with the scope-boundary line.

## Acceptance Criteria
- [ ] All tasks completed
- [ ] `launch_guard_check.sh` wired into `.claude/validate.sh`; both new scripts committed `100755`
- [ ] `launch_guard_check.test.sh` green; known-bad asserts rc **exactly 1** and names the offender
- [ ] Passes on the current tree (guarded §4 cron OK; persistent `&` not flagged; scope-boundary line printed)
- [ ] Catches a newly-added unguarded ` ```cron ` line; a **reasoned** `# linter:allow-unguarded-cron: <why>` opts out (and is reported); a **bare** marker does **not**
- [ ] Follows `exec_bit_check.sh`/`.test.sh` patterns (git guard, offender+fix-hint, rc-1 flip seam)
- [ ] Every external-behavior claim VERIFIED (detection rule probe-verified) or carried as an explicit risk
- [ ] End-to-end catch + false-positive guard verified live, not reasoned

## Notes for Implement
- **Base branch**: branch off current `main` (#94 already merged — no `validate.sh` conflict).
  Never commit to local `main`; branch → PR (CLAUDE.md Do-not).
- **Night Shift is STOPPED** and runs in a separate clone — this checkout is safe for branch work.
- **Naming**: `launch_guard_check.sh` keeps the issue/`launch-command-grounding` vocabulary; the
  header comment must state the honest scope (` ```cron ` fences across all tracked `*.md`).
- **Scope decision (why all-`*.md`, not a name-glob)**: scanning the whole `*.md` class mirrors
  `exec_bit_check`'s all-`*.sh` coverage and can't silently skip a misnamed/misplaced runbook —
  a filename-convention scope would reintroduce the silent-miss class #96 kills. Probe-verified
  0 false positives today; future teaching examples use the reasoned escape hatch (loud-and-recoverable
  beats silent-and-shipped).
- **Complement, not replace**: leave `/validate` Phase 3.5 item 4 and the CLAUDE.md
  `launch-command-grounding` bullet in place — the gate covers ` ```cron ` fences in tracked
  `*.md` mechanically; the prose still covers recognition on any branch and the out-of-scope
  launch surfaces (systemd timers, `crontab` installs, non-`cron` fences).
