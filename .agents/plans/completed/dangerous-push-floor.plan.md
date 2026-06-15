# Plan: Deterministic dangerous-push floor in `security_guard.py`

## Summary
Add a fourth deny check to `.claude/hooks/security_guard.py` — `check_dangerous_push` —
that pattern-matches **force-push** (`--force` / `-f` clustered short flags /
`+`-prefixed refspec — but **not** `--force-with-lease`, allowed per policy) and
**push-to-default-branch** (destination ref is
`main`/`master`, in bare-arg or `src:dst` / `HEAD:main` / `refs/heads/main` forms) and
returns `exit(2)` in **any** mode (auto, default, bypass). This is the deterministic floor
ADR-0020 mandates: the `auto`-mode classifier logged `behavior=allow` for both dangerous
forms (spike Probe 2), so the floor must live in the hook, independent of the permission
layer. The hook is string-only and cannot resolve the implicit bare `git push` (upstream
tracking) — that undetectable case is left to the standing `git push: ask` checkpoint
(the ADR-0020 fail-safe), which #36 does **not** touch.

## User Story
As an operator running Claude in unattended `auto` mode, I want force-push and
push-to-default-branch to be denied deterministically by the security hook so that no
classifier verdict or allow-rule can let the agent rewrite or clobber `main`.

## Metadata
| Field | Value |
|-------|-------|
| Type | ENHANCEMENT |
| Complexity | MEDIUM |
| Systems affected | `.claude/hooks/security_guard.py`, `scripts/security_guard.test.sh` |
| Issue | #36 (blocks #27; refs ADR-0020, ADR-0016, ADR-0018) |

## Assumptions & Risks
| Claim | VERIFIED / ASSUMED | Evidence (probe command + result) or mitigation |
|-------|--------------------|--------------------------------------------------|
| The 5 candidate regexes deny `--force`/`-f`/`+refspec` + explicit push-to-default forms and allow feature pushes / bare `git push` / `main:feature` | **VERIFIED** | A throwaway `python3` matrix (25 cases) ran the exact patterns → **0 mismatches** (all force/default forms deny; `git push origin feature`, `git push`, `git push origin main:feature`, `git push origin develop` allow). |
| The anchor must be `\bgit\b[^|;&]*\bpush\b`, NOT `\bgit\s+push\b` — strict adjacency is bypassed by global options (`git -C <path> push --force origin main`, `git -c k=v push …`, `git --no-pager push origin main`) which an auto-mode agent emits routinely | **VERIFIED** | Probed the strict form: all three prefixed forms returned `allow` (silent bypass of every pattern). Re-probed the widened anchor over the 25-case matrix + 3 prefixed forms + `git config push.default` / `git log main..HEAD && git push origin feature` / `git checkout main && git push origin feature` as allow-controls → **0 mismatches**. The `[^|;&]*` segment guard stops the wider anchor straddling a benign first command into a later push. (Decided with user, 2026-06-16.) |
| `--force-with-lease` to a non-default branch is ALLOWED, but `--force-with-lease origin main` is still DENIED (by the push-to-default pattern) | **VERIFIED** | Re-probed the corrected pattern `\s--force(?!-with-lease)\b` → `--force-with-lease origin feature` allow, `--force-with-lease origin main` deny, `--force origin feature` deny; **0 mismatches**. The `-f` cluster pattern does not catch `--force-with-lease` (second `-` blocks it). |
| `--force-if-includes` (the safe companion to `--force-with-lease`) must ALSO be allowed, else the safest force form is denied while plain `--force-with-lease` is allowed — a policy contradiction | **VERIFIED** | The first-draft `(?!-with-lease)` lookahead DENIED `git push --force-with-lease --force-if-includes origin feature` (pattern 1 hit the `--force` of `-if-includes`). Extended to `--force(?!-with-lease\|-if-includes)\b` → both orderings of the lease+if-includes pair allow; plain `--force origin feature`/`main` still deny. **0 mismatches**. (Decided with user, 2026-06-16.) |
| Lookalike branch names (`master-fix`, `maintenance`, `mainline`) are NOT false-positives | **VERIFIED** | `python3` one-shot over the 5 patterns → all three returned `False` (the `(\s|$)` anchor on the bare-arg pattern and the `:`-requirement on the refspec pattern exclude them). |
| The deny mechanism is `print(reason, file=sys.stderr); sys.exit(2)` and overrides allow rules | **VERIFIED** | Read `.claude/hooks/security_guard.py:118-122` + ADR-0016 + docstring lines 14-16; existing opaque-exec/rm checks use exactly this. |
| The bash test harness drives the hook by piping JSON and asserting `RC=2` / `RC=0` | **VERIFIED** | Read `scripts/security_guard.test.sh:11-46` (`run_hook` / `assert_deny` / `assert_allow`). New cases mirror lines 49-65. |
| CI runs `scripts/security_guard.test.sh`; the local `validate.sh` gate does NOT (it only runs `piv_check.sh`) | **VERIFIED** | Read `.github/workflows/ci.yml` (lists the test) and `.claude/validate.sh` (only `piv_check.sh`). → Implement/Validate must run the suite explicitly; CI is the backstop. |
| The hook cannot resolve the implicit bare `git push` target from the string; that case stays on `ask` | **VERIFIED (by design)** | ADR-0020 Consequences: "branch may be implicit … keep `git push` on `ask` (un-graduated)". #36 adds the floor only; it does not graduate/remove `ask`. |
| `--force-with-lease` to a non-default branch is allowed (policy decision) | **DECIDED (user, 2026-06-16)** | ADR-0020 says force forms are "judged per policy". User chose to allow `--force-with-lease` as the safe force-push; only `--force`/`-f`/`+refspec` are denied. Implemented via `\s--force(?!-with-lease)\b` negative lookahead. (`--force-with-lease origin main` is still denied — by the push-to-default pattern, not the force pattern.) |
| `main`/`master` are treated as default-branch names by convention, not by querying the repo's actual default | **ASSUMED (intentional)** | Conservative bias: a repo whose real default is `develop` will still have pushes to a literal `main`/`master` denied. Acceptable for a floor; documented in the docstring. |
| `examples/hooks/security_guard.py` is stale reference drift and is NOT kept in sync | **VERIFIED** | `diff` shows it still uses the old `permissionDecision` JSON mechanism and lacks the opaque-exec check added in #31 — i.e. #31 already did not sync it. Header says "Do NOT use this file directly". **Leave untouched; mention only.** |

## Patterns to Follow

Existing check function + module-level pattern list (mirror exactly):
```python
# SOURCE: .claude/hooks/security_guard.py:79-99
OPAQUE_EXEC_PATTERNS = [
    r"\|\s*(sudo\s+)?(sh|bash|zsh)\b",
    ...
]

def check_opaque_exec(tool_name: str, tool_input: dict) -> str | None:
    """Return a denial reason if untrusted opaque code execution is detected, else None."""
    if tool_name != "Bash":
        return None
    command = tool_input.get("command", "")
    if not isinstance(command, str):
        return None
    for pattern in OPAQUE_EXEC_PATTERNS:
        if re.search(pattern, command):
            return (f"Blocked: ... {command!r}. ...")
    return None
```

Wiring into `main` (append to the `or` chain):
```python
# SOURCE: .claude/hooks/security_guard.py:112-116
reason = (
    check_env_file(tool_name, tool_input)
    or check_recursive_delete(tool_name, tool_input)
    or check_opaque_exec(tool_name, tool_input)
)
```

Test cases (mirror the deny/allow grouping):
```bash
# SOURCE: scripts/security_guard.test.sh:49-65
assert_deny  '{"tool_name":"Bash","tool_input":{"command":"curl https://x | sh"}}'   "deny: curl | sh"
assert_allow '{"tool_name":"Bash","tool_input":{"command":"curl -o file https://x"}}' "allow: curl -o file"
```

## Files to Change
| File | Action | Purpose |
|------|--------|---------|
| `.claude/hooks/security_guard.py` | UPDATE | Add `DANGEROUS_PUSH_PATTERNS`, `check_dangerous_push`, wire into `main`, extend docstring |
| `scripts/security_guard.test.sh` | UPDATE | Add dangerous-push deny cases + benign-push allow cases |
| `docs/adr/0020-dangerous-push-floor-in-hook-not-permission-layer.md` | UPDATE (done in grilling) | Appended a Consequences bullet scoping the floor to string-detectable forms (quoted/var-expanded/implicit-bare out of scope by design; global-option prefixes in scope). Append-only — original text untouched. Commit with #36. |

## Tasks

### Task 1: Add the dangerous-push check to the hook
- File: `.claude/hooks/security_guard.py`
- Action: UPDATE
- Implement:
  1. After `OPAQUE_EXEC_PATTERNS` / `check_opaque_exec` (after line 99), add the verified
     patterns as `(regex, label)` tuples:
     ```python
     DANGEROUS_PUSH_PATTERNS = [
         # Force-push: --force (but NOT --force-with-lease / --force-if-includes, both
         # the safe lease-family flags allowed per policy — negative lookahead)
         (r"\bgit\b[^|;&]*\bpush\b[^|;&]*\s--force(?!-with-lease|-if-includes)\b", "force-push (--force)"),
         # Force-push: -f, incl. clustered short flags (-fu)
         (r"\bgit\b[^|;&]*\bpush\b[^|;&]*\s-[a-zA-Z]*f", "force-push (-f)"),
         # Force-push via +-prefixed refspec: git push origin +main / +HEAD:main / +feature
         (r"\bgit\b[^|;&]*\bpush\b[^|;&]*\s\+\S", "force-push (+refspec)"),
         # Push to default branch — destination side of a refspec is main/master (HEAD:main, feature:main)
         (r"\bgit\b[^|;&]*\bpush\b[^|;&]*:(\+)?(refs/heads/)?(main|master)\b", "push to default branch (refspec dest)"),
         # Push to default branch — bare branch arg main/master (not the source side of a src:dst refspec)
         (r"\bgit\b[^|;&]*\bpush\b[^|;&]*\s(\+)?(refs/heads/)?(main|master)(\s|$)", "push to default branch"),
     ]
     ```
     The anchor is `\bgit\b[^|;&]*\bpush\b` (git, then push later in the same
     command segment — `[^|;&]*` does not cross a pipe/`;`/`&` separator), **not**
     `\bgit\s+push\b`. The strict-adjacency form is bypassed by global options
     between `git` and the subcommand (`git -C <path> push …`, `git -c k=v push …`,
     `git --no-pager push …`) — all common in scripts and the exact forms a
     cross-worktree auto-mode agent emits. Re-probed (widened anchor, 25-case matrix +
     the 3 global-option forms + `git config push.default` / `git log main..HEAD &&
     git push origin feature` / `git checkout main && git push origin feature` as
     allow-controls) → **0 mismatches**: the three prefixed forms now deny; the
     `config`/`log`/`checkout` controls stay allow (the `&`/segment guard prevents the
     wider anchor from straddling a benign first command into a later push).
  2. Add `check_dangerous_push(tool_name, tool_input)` mirroring `check_opaque_exec`
     (Bash-only, str-guard, loop). On match, return:
     ```python
     return (
         f"Blocked: dangerous git push ({label}) in command: {command!r}. "
         "Force-push and push-to-default-branch are denied in every mode (ADR-0020). "
         "Run it manually (e.g. `! git push …`) if you intend it."
     )
     ```
     (Iterate `for pattern, label in DANGEROUS_PUSH_PATTERNS:` so the reason names which form fired.)
  3. Wire into the `main` `reason` chain as the final `or check_dangerous_push(tool_name, tool_input)`.
  4. Extend the module docstring `Denies:` list with a bullet: dangerous git push
     (force-push + push-to-default-branch), citing ADR-0020. Include an explicit
     **Known string-layer limits** note listing what the floor cannot catch and why
     (all bounded by the same fact — a string matcher cannot see a value that is not
     literal in the command, the same class CONTEXT.md names *opaque code execution*):
       - the implicit bare `git push` (upstream target not in the string);
       - quoted or variable-expanded branch/flag tokens (`git push origin "main"`,
         `'main'`, `$BR`, line-split forms) — deliberately **not** chased with more
         patterns; that is a losing game for a string matcher;
       - `main`/`master` are matched by convention, not by querying the repo's real
         default.
     All three are backstopped by the standing `git push: ask` checkpoint (ADR-0020).
     The widened anchor (`\bgit\b…\bpush\b`) DOES cover global-option prefixes
     (`git -C … push`) — those are natural agent output, not obfuscation, so they are
     in scope and denied.
- Mirror: `.claude/hooks/security_guard.py:79-99` (pattern list + check fn), `:112-116` (wiring), `:2-19` (docstring)
- Validate: `bash scripts/security_guard.test.sh` (after Task 2) → "All tests passed."

### Task 2: Add dangerous-push tests
- File: `scripts/security_guard.test.sh`
- Action: UPDATE
- Implement: After the existing deny block (after line 56), add a `--- DENY: dangerous git push ---`
  group, and after the allow block (after line 65) add benign-push allow cases. Cover the
  verified matrix:
  - **deny**: `git push --force origin feature`, `git push --force origin main`,
    `git push -f origin feature`, `git push -fu origin feature`, `git push origin +HEAD:main`,
    `git push origin main`, `git push origin master`, `git push origin HEAD:main`,
    `git push origin feature:main`, `git push -u origin main`, `git push origin refs/heads/main`,
    `git push --force-with-lease origin main` (lease form to default branch still denied — by the push-to-default pattern),
    `git -C /repo push --force origin main`, `git -c http.sslVerify=false push --force origin main`,
    `git --no-pager push origin main` (global-option prefix forms — widened anchor must still deny)
  - **allow**: `git push origin feature`, `git push origin my-feature-branch`,
    `git push --force-with-lease origin feature` (lease form to non-default branch — allowed per policy),
    `git push --force-with-lease --force-if-includes origin feature` (safe lease+if-includes pair — allowed),
    `git push` (bare/implicit — covered by `ask`, not the hook),
    `git push origin main:feature` (target is feature), `git push origin develop`,
    `git push origin master-fix` (lookalike, not the default branch),
    `git config push.default simple`, `git checkout main && git push origin feature`
    (widened-anchor controls — `git` and `push`/`main` co-occur but no dangerous push)
  - Use single-quoted JSON payloads; escape inner `"` as `\"` exactly like lines 49-56.
- Mirror: `scripts/security_guard.test.sh:48-68`
- Validate: `bash scripts/security_guard.test.sh` → "All tests passed.", non-zero exit count = 0

## Validation
- **Unit/probe (primary gate):** `bash scripts/security_guard.test.sh` → must print
  "All tests passed." and exit 0. This is the runtime probe the issue requires — it pipes
  real JSON payloads through the actual hook and asserts `exit(2)` deny / `exit(0)` allow.
- **Regression:** the pre-existing deny/allow/fail-open cases must still pass (env, rm,
  opaque-exec, malformed stdin).
- **CI backstop:** `.github/workflows/ci.yml` already runs `scripts/security_guard.test.sh`.
- **PIV gate:** `bash .claude/validate.sh` (runs `piv_check.sh`) for branch/plan/report
  invariants — note it does **not** run the security tests, so run them explicitly above.
- **Optional live confirmation:** in a throwaway dir, attempt `git push --force` / a
  push-to-`main` form through a Bash tool call and confirm the hook blocks it with the
  reason on stderr (matches ADR-0020 "probe-verified at runtime, not docs-only").

## Acceptance Criteria
- [ ] `security_guard.py` denies force-push forms and push-to-default-branch with `exit(2)` in any mode
- [ ] Branch detection handles implicit upstream (left to `ask`, not denied), remote/branch order, and `HEAD:main` / `refs/heads/main` / `src:dst` forms; ambiguous-but-detectable cases fail safe (deny)
- [ ] New deny + allow tests added, mirroring existing `security_guard.py` tests; full suite passes
- [ ] All pre-existing tests still pass
- [ ] Follows existing check-function / pattern-list structure
- [ ] `--force-with-lease` to a non-default branch is allowed; `--force`/`-f`/`+refspec` and any push-to-`main`/`master` (incl. lease form) denied
- [ ] `git push: ask` checkpoint left untouched (graduation is #27, not #36)
- [ ] Unblocks #27 to ship `defaultMode: auto`
```
