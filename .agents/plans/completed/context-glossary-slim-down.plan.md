# Plan: CONTEXT.md glossary slim-down

## Summary
Slim the 6 "fat" term entries in `CONTEXT.md` (`validate gate`, `sandbox`, `boundary`,
`opaque code execution`, `dangerous push`, `notification`) from ~15-line essays back to the
glossary shape the lean front entries already use: **one-line definition + `_Avoid_` line +
`(ADR-00XX)` pointer**. Every "why / edge-case / context" sentence is *moved* — pushed into its
ADR (already covers it, verified per-entry below) or retained as a short clause where no ADR home
exists — never deleted. Net effect: the file becomes an *index* again; the ADRs remain the home of
"why". One small, **verified** ADR edit is required: ADR-0020 gains an explicit line documenting
the lease-family allowance so the `dangerous push` entry can drop that detail with zero loss. No
behavior changes, no code touched.

## User Story
As the TC-native author of this harness, I want `CONTEXT.md` to be a tight glossary I can re-read
in one pass, so that I can navigate my own canonical docs without chasing 3 ADR jumps per term.

## Metadata
| Field | Value |
|-------|-------|
| Type | REFACTOR (documentation) |
| Complexity | MEDIUM |
| Systems affected | `CONTEXT.md`; `docs/adr/0020-*.md` (one verified line); PR body (TC gate) |
| Issue | N/A (cleanup approved in conversation; future-fix already shipped in PR #46) |

## Background (so this plan stands alone)
- **Why this exists:** `grill-with-docs` was mis-used as a cold-start feature entry point; each run
  re-wrote canonical docs until entries bloated to 15 lines / 3 ADR jumps. The *future* is already
  fixed (PR #46: routing floor + CI comprehension gate `scripts/doc_change_gate.sh`). **This task is
  the optional cleanup of existing bloat.** The disease is *comprehension*, not line count.
- **Approved shape (by user, after two before/after demos):** each term = one-line def + `_Avoid_`,
  push "why" to its ADR via `(ADR-00XX)`. Demos shown: `validate gate` 15→7, `dangerous push` 15→6.
- **Not in scope (user did NOT approve):** ADR consolidation (0016/0019/0020), an ADR index, and the
  lean front entries (lines 1–141: Harness … handoff) get **no touch**. The `### Unattended Autonomy`
  prose block (lines 174–195) is **left as-is** — it is a section preamble, not one of the 6 named
  fat entries; slimming it would expand scope. Note it as a possible follow-up.

## Assumptions & Risks
A claim is **VERIFIED** only if a probe was run. Reasoning-from-docs is **ASSUMED**.

| Claim | Status | Evidence (probe + result) or mitigation |
|-------|--------|------------------------------------------|
| Each pushed-out "why" sentence in all 6 entries is already covered by its target ADR | **VERIFIED** | 6 sub-agents read the ADRs and quoted covering text verbatim. See per-entry coverage map in **Patterns / per-task**. Net: validate gate→ADR-0009 (full), sandbox→ADR-0018/0020 (full), boundary→ADR-0009/0018 (full), opaque code execution→ADR-0019 (full), dangerous push→ADR-0020 (full *except* lease line — see next row), notification→ADR-0021 (full except naming, which stays in `_Avoid_`). |
| Lease family (`--force-with-lease`/`--force-if-includes`) to a **non-default** branch is allowed by the floor | **VERIFIED** | `.claude/hooks/security_guard.py:13-14` docstring states it; `:128-130` matches `--force` with negative lookahead `(?!-with-lease\|-if-includes)`; `:136-138` denies `main`/`master` destinations. ADR-0020 currently only says "`--force-with-lease` judged per policy" (line 73) — too vague to be the drop target, so add a precise verified line first. |
| "exfiltration is out of scope" has **no** ADR home (ADR-0016 actually calls `curl\|sh` "network-exfil") | **VERIFIED** | Sub-agents confirmed no ADR states exfiltration-out-of-scope. Mitigation: **retain** a short exfiltration clause in the `opaque code execution` entry (the term it most disambiguates) and **drop** it from `boundary` — it survives in a sibling entry, so zero loss, **no ADR edit**. Do NOT "fix" ADR-0016's mislabel here (pre-existing, out of scope). |
| `notification` Source-A/B naming + sink/channel rejection has no ADR home (ADR-0021 still says "Channel A/B") | **VERIFIED** | Sub-agent confirmed ADR-0021 uses the old "Channel" names. Mitigation: **keep** the full `_Avoid_` line and the two-axis distinction in CONTEXT — they are load-bearing identity with no ADR home. |
| CI doc gate blocks the PR unless body has a TC `## 變更說明` section | **VERIFIED** | `scripts/doc_change_gate.sh:19,30-32` triggers on `^CONTEXT\.md$\|^docs/adr/` and requires `^#{1,6}\s*變更說明` + a CJK char (`\x{4e00}-\x{9fff}`) outside heading lines. `.github/workflows/ci.yml:27-31` feeds it the PR body. |
| `validate.sh` stays green (no code changed) | **VERIFIED (path)** | `.claude/validate.sh` → `scripts/piv_check.sh` (PIV artifact invariants only). Doc-only edits don't break it. Implement re-runs to confirm. |
| Cross-references between entries stay intact after slimming | ASSUMED | Slimmed entries keep the bold terms (`**boundary**`, `**validate gate**`, `dashboard`, `worktree`). Mitigation: Task 8 re-read greps every `**term**` reference resolves. |

## Patterns to Follow
The target shape **already exists** in the file's lean front entries — mirror them exactly, do not
invent a new format:

```markdown
**Smart Zone**:
{one-paragraph definition}
_Avoid_: {contrasts}
```
`// SOURCE: CONTEXT.md:30-37 (Smart Zone), CONTEXT.md:56-62 (grill-with-docs)`

Pointer convention: append `(ADR-00XX)` inline at the end of the definition sentence, exactly as the
current `validate gate` entry already does — `// SOURCE: CONTEXT.md:152 ("(ADR-0009)")`.

ADR-edit shape (append a Consequences bullet, mirror existing dated bullets):
`// SOURCE: docs/adr/0020-...md:88 ("**Scope of the floor (added 2026-06-16, #36 plan grilling):**")`

**IMPORTANT for Implement:** edit by matching each `**term**:` header (with the trailing colon) as a
unique anchor — `grep -n '^\*\*validate gate\*\*:'` → line 143, NOT line 138 (line 138 is the same
bold term mid-sentence inside the PIV Loop entry). Each edit shifts subsequent line numbers, so
re-anchor on header text per entry rather than trusting the line numbers below.

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `CONTEXT.md` | UPDATE | Slim 6 fat entries to def + `_Avoid_` + pointer |
| `docs/adr/0020-dangerous-push-floor-in-hook-not-permission-layer.md` | UPDATE | Add one verified Consequences line: lease-family-to-non-default-branch is allowed |

## Tasks
Ordered. Task 1 (ADR edit) precedes Task 6 so the lease detail has a home **before** it is dropped
(zero-loss ordering). Tasks 2–7 are independent edits to one file — apply sequentially, re-anchoring
on each header.

### Task 1: Add verified lease-allowance line to ADR-0020
- File: `docs/adr/0020-dangerous-push-floor-in-hook-not-permission-layer.md`
- Action: UPDATE (append a Consequences bullet after the existing "Scope of the floor" bullet)
- Implement: add this bullet (text is verified against the hook, do not soften it):
  > - **Lease family allowed to non-default branches:** the safe lease family
  >   (`--force-with-lease` / `--force-if-includes`) aimed at a **non-default** branch is **allowed**,
  >   not denied — `security_guard.py` matches `--force` with a negative lookahead
  >   `(?!-with-lease|-if-includes)`, so the lease flags pass. It is the agent's correct
  >   non-destructive recovery path and cannot clobber published history non-interactively. Bare
  >   `--force` / `-f` / `+refspec`, and any push whose literal destination is `main`/`master`,
  >   remain denied.
- Mirror: `docs/adr/0020-...md:88` (dated Consequences bullet style)
- Validate: re-read; the claim matches `security_guard.py:128-138`

### Task 2: Slim `validate gate`
- File: `CONTEXT.md` — anchor `^\*\*validate gate\*\*:` (currently line 143)
- Action: UPDATE — replace the entry body (def through `_Avoid_`) with:
  > **validate gate**:
  > The automatic enforcement floor of the Validate step — a `Stop` hook (`validate_gate.py`) that
  > runs the project's `.claude/validate.sh` when a session tries to end and *blocks* completion on
  > failure, turning the test-first discipline from a norm into an enforced gate. One "validate"
  > root, two layers: the validate gate is the *automatic floor*; **`/validate`** is the *deliberate
  > full pass* run as the Validate step's own session (ADR-0009).
  > _Avoid_: "verify" as a second layer (no verify-vs-validate split; "verify" survives only in
  > CLAUDE.md's `Verify commands` slot, naming the commands `validate.sh` bundles); conflating the
  > validate gate (automatic hook) with `/validate` (deliberate command); tdd-gate (the red-green
  > discipline the gate enforces, not the gate itself).
- Pushed to ADR-0009 (all verified covered): global-machinery/`~/.claude` sync (ADR:59-65), opt-in
  via presence of `validate.sh` / fails-open (ADR:51-57), Cole-Medin single-root framing (ADR:37-39),
  `validate.sh` language-agnostic-extension rationale (ADR:45-49).
- Validate: entry reads def + `_Avoid_` + `(ADR-0009)`; `**`/`/validate`` cross-refs intact

### Task 3: Slim `sandbox`
- File: `CONTEXT.md` — anchor `^\*\*sandbox\*\*:` (currently line 197)
- Action: UPDATE — replace body with:
  > **sandbox**:
  > A **worktree** (isolation container) paired **with** the synced auto-approve posture
  > (`defaultMode: auto` — a safety-classifier model judges each action by intent) so its internal
  > ops — read / search / test / edit / commit — run without per-tool-use prompts. Safety is the
  > **boundary** gate, not the directory wall (ADR-0018, ADR-0020).
  > _Avoid_: treating sandbox ≡ worktree (the worktree is only the isolation half; the posture is
  > the other half and is broader than it); "sandbox" as a directory or VM (the protection is the
  > boundary gate, not isolation).
- Pushed to ADR-0018 (verified covered): classifier = probabilistic-inner / deterministic-floor
  (ADR-0018 "tension" section), posture synced at user scope outliving the worktree + "posture
  without container = accepted residual risk" (ADR-0018 "intent-awareness" + Consequences). The
  boundary-mechanics sentences are duplicative of the `boundary` entry and drop with no loss.
- Keep `**worktree**` entry (lines ~213-219) untouched.
- Validate: def + `_Avoid_` + `(ADR-0018, ADR-0020)`; `**worktree**`/`**boundary**` refs intact

### Task 4: Slim `boundary`
- File: `CONTEXT.md` — anchor `^\*\*boundary\*\*:` (currently line 221)
- Action: UPDATE — replace body with:
  > **boundary**:
  > The line a sandbox's *outputs* must cross to become durable or irreversible — where verification
  > moves from "trust the inside" to "gate the crossing": session-end held by the validate gate,
  > irreversible side effects gated by `security_guard.py` (ADR-0009, ADR-0018).
  > _Avoid_: perimeter, firewall (those imply keeping things out; the boundary gates what the
  > sandbox sends out).
- Pushed/consolidated (verified): the benign-push/dangerous-push/recursive-delete/opaque-exec
  enumeration lives in the sibling entries + their ADRs; the graduation dial lives in the
  `### Unattended Autonomy` Graduation bullet + ADR-0020/0017. **Drop the exfiltration sentence here**
  — it survives in the `opaque code execution` entry (Task 5), zero loss, no ADR edit.
- Validate: def + `_Avoid_` + `(ADR-0009, ADR-0018)`; keep crisp one-line core

### Task 5: Slim `opaque code execution`
- File: `CONTEXT.md` — anchor `^\*\*opaque code execution\*\*:` (currently line 231)
- Action: UPDATE — replace body with:
  > **opaque code execution**:
  > A command `security_guard.py` denies at the **boundary**: one whose real payload is **not literal
  > in the command**, so no human sees what will run when it is authored — via **pipe-to-shell**
  > (`curl … | sh`) or **command substitution into a shell** (`eval "$(…)"`). The threat is the
  > *opacity*, not the fetch; bare local substitution is denied too. Distinct from `exfiltration`
  > (data going *out*, out of scope) (ADR-0019).
  > _Avoid_: fetch-and-execute (names only the network-fetch source; under-describes the class and
  > mislabels the local-substitution denials — superseded by this term); remote code execution
  > (implies a remote attacker/foothold, not the local-opacity framing here).
- Keep the **two mechanism names** (pipe-to-shell / command-substitution) — load-bearing identity, not
  "why" — but compress the full payload enumeration (`wget … | bash`, bare `… | sh`, `sh -c`/backtick)
  into one canonical example each (full list verified in ADR-0019:7-11). Keep the short exfiltration
  clause (no ADR home — retained here on purpose).
- Validate: def + `_Avoid_` + `(ADR-0019)`; exfiltration distinction preserved

### Task 6: Slim `dangerous push`
- File: `CONTEXT.md` — anchor `^\*\*dangerous push\*\*:` (currently line 244)
- Action: UPDATE — replace body with:
  > **dangerous push**:
  > The subset of `git push` **denied** at the **boundary** — two forms: **force-push** (rewriting
  > published history) and **push-to-default-branch** (clobbering `main`/`master`) — distinct from the
  > benign `git push` merely gated on `ask`. Benign push is a *friction dial* (`ask → allow`);
  > dangerous push is a *deterministic floor* in **every** permission mode, living in the
  > `security_guard.py` deny hook, **not** the permission layer (ADR-0020).
  > _Avoid_: conflating with the benign `git push` checkpoint (that is the dial on `ask`; this is the
  > floor on `deny` — they graduate independently); treating the auto-mode classifier as the floor (it
  > is the probabilistic inner layer, not the deterministic one — ADR-0020).
- Pushed to ADR-0020 (verified covered): probe evidence the classifier approved both forms (ADR:22,89),
  literal-string bound + bare-push/quoted-target out-of-scope (ADR:88-98), and the lease allowance
  (now added in **Task 1**). Depends on Task 1 being done first.
- Validate: ~6-line entry matching the approved demo; def + `_Avoid_` + `(ADR-0020)`

### Task 7: Slim `notification`
- File: `CONTEXT.md` — anchor `^\*\*notification\*\*:` (currently line 260)
- Action: UPDATE — replace body with:
  > **notification**:
  > The boundary's **outbound signal to the operator** — the complement to the validate gate
  > (**polling → interrupt**: a boundary event interrupts the operator so they stop polling the
  > `dashboard`). One primitive (`notify.sh`) owns delivery; described on two axes — **transport**
  > (*where*: the at-keyboard **tmux bell** and the AFK **network push**) and **source** (*what event*:
  > **Source A** = the validate verdict, **Source B** = the PR-state watcher). A source reuses the
  > transports; **adding a source must not touch a transport** (ADR-0021).
  > _Avoid_: conflating transport and source (transport = delivery mechanism, source = triggering
  > event — Source B reuses both transports); "sink" / "channel" (the pre-canonical names; Issue
  > #40's "Channel A" is Source A); alert, ping.
- Keep the two-axis distinction + the "must not touch a transport" invariant + the full `_Avoid_`
  (the Channel→Source rename has no ADR home). Pushed to ADR-0021 (verified covered): tmux flag
  auto-clear + push-is-source-of-truth/severity (ADR:33-47,75-76), Source A fail/pass call-sites
  (ADR:52-55), Source B follow-up (ADR:87).
- Validate: def + two-axis + `_Avoid_` + `(ADR-0021)`

### Task 8: Zero-loss + comprehension re-read
- Implement: `git diff CONTEXT.md` — for **every** removed sentence, confirm it is (a) quoted-covered
  in the cited ADR per the coverage map above, or (b) retained elsewhere in CONTEXT (exfiltration →
  opaque code execution; naming → notification `_Avoid_`). Then read the 6 entries top-to-bottom as a
  first-time reader: each is def + `_Avoid_` + pointer, every bold cross-ref term still resolves, file
  dropped from 275 lines to roughly ~215-225.
- Validate: no orphaned references; `grep -n '(ADR-0' CONTEXT.md` shows the 6 new pointers

### Task 9: Open PR with TC change-note
- Implement: branch (never commit to local `main`), commit CONTEXT.md + ADR-0020, open PR whose body
  includes a `## 變更說明` section in Traditional Chinese (what changed + why). Canonical files stay
  **English**; TC lives only in the PR body.
- Validate: see Validation below

## Validation
- **Local gate:** `bash .claude/validate.sh` → green (doc-only change; `piv_check.sh` unaffected).
- **Doc gate (the CI blocker) — dry-run locally before pushing:**
  `printf 'CONTEXT.md\ndocs/adr/0020-dangerous-push-floor-in-hook-not-permission-layer.md\n' > /tmp/cf.txt`
  → write the intended PR body to `/tmp/pb.txt` → `bash scripts/doc_change_gate.sh /tmp/cf.txt /tmp/pb.txt`
  must exit 0 (proves the `## 變更說明` + CJK body satisfies the gate before the PR runs CI).
- **Zero-loss audit:** Task 8 diff walk — every dropped sentence is ADR-covered (cited) or retained.
- **Comprehension re-read:** the 6 entries read in one pass; ~50-line reduction; cross-refs intact.

## Acceptance Criteria
- [ ] All 9 tasks completed
- [ ] `bash .claude/validate.sh` passes; `doc_change_gate.sh` dry-run exits 0
- [ ] 6 entries follow the existing lean-entry shape (def + `_Avoid_` + `(ADR-00XX)`)
- [ ] Every removed sentence is ADR-covered (per coverage map) or retained in a sibling entry — zero loss
- [ ] ADR-0020 lease line matches `security_guard.py` (VERIFIED, not softened)
- [ ] Canonical docs stay English; PR body carries the TC `## 變更說明` section
- [ ] Front lean entries (1–141) and the `### Unattended Autonomy` block (174–195) untouched
