# Report: Night Shift — push-graduation on-switch + preserved dangerous-push deny floor

## Tasks Completed

- ✅ **Task 1**: README `## Enabling the Night Shift (the push dial)` operator section inserted after `## Sync` block (line 123), before `## After syncing`.
- ✅ **Task 2**: `scripts/security_guard.test.sh` — dial-independence deny block (5 cases: 4 deny + 1 allow) + structural settings-blind assertion inserted before FAIL-OPEN section.
- ✅ **Task 3**: `scripts/sync.test.sh` — `test(shared-g)` inserted after `test(shared-f)` footer, before summary; asserts shipped posture keeps `git push` on `ask` not `allow`.
- ✅ **Task 4**: Verification — `security_guard.py` and `settings.shared.json` byte-identical to main; all three suites pass.

## Validation Results

```
bash scripts/security_guard.test.sh  → All tests passed.
bash scripts/sync.test.sh            → All tests passed.
bash .claude/validate.sh             → PIV checks passed.
```

`git diff --name-only HEAD~1` lists only the 4 expected files:
- `.agents/plans/night-shift-push-graduation-onswitch.plan.md` (plan seed commit)
- `README.md`
- `scripts/security_guard.test.sh`
- `scripts/sync.test.sh`

`security_guard.py` and `settings.shared.json` — **not listed** (byte-identical to main). ✅

## Files Changed

| File | Change |
|------|--------|
| `README.md` | +22 lines — new `## Enabling the Night Shift (the push dial)` section |
| `scripts/security_guard.test.sh` | +21 lines — dial-independence block + structural assertion |
| `scripts/sync.test.sh` | +19 lines — `test(shared-g)` shipped-posture guard |

## Deviations from Plan

None. All patterns mirrored exactly as specified.

## Tests Written

- `security_guard.test.sh`: 5 new test cases (4 `assert_deny` + 1 `assert_allow`) covering the dial-independence invariant; 1 structural grep assertion locking settings-blindness.
- `sync.test.sh`: 2 new assertions (`assert_contains` + `assert_not_contains`) in `test(shared-g)` locking shipped posture.

## Branch

`feat/59-push-graduation-onswitch` — 2 commits ahead of main (plan seed + implementation).

## Artifacts

- Plan: `.agents/plans/night-shift-push-graduation-onswitch.plan.md`
- Report: `.agents/reports/night-shift-push-graduation-onswitch-report.md` (this file)
