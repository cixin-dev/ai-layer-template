# Report: Deterministic dangerous-push floor in `security_guard.py`

**Plan:** `.agents/plans/dangerous-push-floor.plan.md`
**Issue:** #36 (blocks #27; refs ADR-0020, ADR-0016, ADR-0018)
**Branch:** `feat/36-dangerous-push-floor`

## Tasks completed
- ✅ **Task 1** — Added `DANGEROUS_PUSH_PATTERNS` + `check_dangerous_push` to
  `.claude/hooks/security_guard.py`, wired it as the final `or` in the `main` reason
  chain, and extended the module docstring (`Denies:` bullet + a "Known string-layer
  limits" note).
- ✅ **Task 2** — Added a `DENY: dangerous git push` group (15 cases) and an
  `ALLOW: benign git push` group (10 cases) to `scripts/security_guard.test.sh`.

## Validation results
- `bash scripts/security_guard.test.sh` → **"All tests passed." exit 0** (41 assertions:
  25 new + 16 pre-existing). Run in the worktree against the actual hook (pipes real JSON
  payloads, asserts `exit(2)` deny / `exit(0)` allow).
- Regression: all pre-existing env / rm / opaque-exec / fail-open cases still pass.
- CI backstop: `.github/workflows/ci.yml` already runs this suite.
- PIV gate (`bash .claude/validate.sh`) is deferred to the `/validate` session (it runs
  `piv_check.sh` only, not the security suite — the security suite was run explicitly above).

## Files changed
| File | Change |
|------|--------|
| `.claude/hooks/security_guard.py` | +`DANGEROUS_PUSH_PATTERNS` (5 regexes), +`check_dangerous_push`, wired into `main`, docstring extended |
| `scripts/security_guard.test.sh` | +15 deny cases, +10 allow cases |
| `CONTEXT.md` | "dangerous push" glossary term (carried from main's working tree — see deviation) |
| `docs/adr/0020-…` | "Scope of the floor" note (carried from main's working tree — see deviation) |

## Coverage of the verified matrix
- **Deny — force-push:** `--force` (feature + main), `-f`, clustered `-fu`, `+HEAD:main`.
- **Deny — push-to-default:** `origin main`, `origin master`, `HEAD:main`, `feature:main`,
  `-u origin main`, `refs/heads/main`, `--force-with-lease origin main` (lease to default
  still denied — by the push-to-default pattern, not the force pattern).
- **Deny — global-option prefixes:** `git -C /repo push --force origin main`,
  `git -c http.sslVerify=false push --force origin main`, `git --no-pager push origin main`
  (widened `\bgit\b…\bpush\b` anchor must catch these).
- **Allow:** `origin feature`, `origin my-feature-branch`, `--force-with-lease origin
  feature`, `--force-with-lease --force-if-includes origin feature`, bare `git push`
  (covered by `ask`), `origin main:feature` (dest is feature), `origin develop`,
  `origin master-fix` (lookalike), `git config push.default simple`,
  `git checkout main && git push origin feature` (segment-guard control).

## Deviations from plan (with rationale)
1. **CONTEXT.md and ADR-0020 were uncommitted edits on `main`, not clean.** The plan's
   "Files to Change" listed only ADR-0020 as a doc change ("done in grilling"). On pickup,
   `main`'s working tree carried three modified tracked files (`CONTEXT.md` — the "dangerous
   push" glossary term; `docs/adr/0020` — the scope-of-floor note; `docs/adr/0017` — an
   unrelated "settings/sync slice" correction) plus a second untracked plan draft
   (`settings-shared-auto-mode-merge.plan.md`). Per `/implement` Phase 2 this is a STOP
   (dirty tracked files on `main`). **Resolved with the user:** carry the two #36-related
   docs (CONTEXT.md + ADR-0020) into this branch and commit them with the code (commit
   `7605836`); restore both on `main`; leave ADR-0017 + the settings plan draft on `main`
   for the other slice. CONTEXT.md was thus committed here although the plan did not list it
   — it is unambiguously #36 work (it defines the term the hook implements).
2. **No other deviations.** Patterns, anchor, lookaheads, wiring point, and test matrix
   match the plan's verified probes exactly. `examples/hooks/security_guard.py` left
   untouched (stale reference drift, per plan assumption).

## Tests written
25 new assertions in `scripts/security_guard.test.sh` (15 deny + 10 allow), mirroring the
existing `assert_deny` / `assert_allow` grouping and single-quoted JSON-payload style.

## Next step
`/validate .agents/plans/dangerous-push-floor.plan.md` in a fresh session (full gate + E2E +
human review), then open a PR. After merge, `/clean-worktree feat/36-dangerous-push-floor`.
