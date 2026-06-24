# Dangerous git push is gated deterministically in `security_guard.py`, not the permission layer

**Status:** Accepted (2026-06-15); supersedes ADR-0017; relates to ADR-0016 (deny hook),
ADR-0018 (auto mode). Born from the Issue #26 probe, which refuted the shared premise of
ADR-0017 and this ADR's own first draft.

## Context

ADR-0017 modeled graduation as moving `git push` from live `ask` to live `allow`, and assumed
that `auto` mode keeps force-push / push-to-default-branch gated — either by dropping the allow
rule or by the classifier still running over it. This ADR's **first draft** (graduate-by-removal)
rested on the same assumption from the other side: delete the live `ask` entry so push "falls to
the classifier," trusting that the classifier's documented `soft_deny` of "Git Push to Default
Branch" and "Git Destructive: Force pushing" would hold as the safety floor.

The Issue #26 probe (2026-06-15, binary v2.1.177) tested that assumption directly instead of
trusting the `auto-mode defaults` listing, and **refuted it**:

| Probe | Result | Evidence |
|-------|--------|----------|
| 1 — user-scope `defaultMode:auto` is accepted | **VERIFIED GREEN** | Differential: project scope → `settings defaultMode "auto" ignored` WARN; user scope → no such warning, `canEnterAuto=true`. (Project/local scope cannot grant auto mode; only user/policy/flag can.) |
| 2 — classifier's runtime verdict on dangerous push | **REFUTES the floor** | True auto mode, no allow rule. `git push origin main` → classifier ran (6.5s real model call), verdict logged `mode=auto, behavior=allow`; push landed. `git push --force origin main` → classifier ran (10.5s), `mode=auto, behavior=allow`; force-push landed. |

The classifier is **intent-aware** (the very property ADR-0018 adopted it for): an action that is
explicitly part of the agent's instructions is judged in-scope and approved. The `soft_deny`
defaults bind *unprompted escalation*, not explicitly-authorized actions. In unattended autonomy
the agent's task **is** its instruction, so a task that entails pushing is a push the classifier
approves — including to the default branch, including `--force`.

**Conclusion: the `auto`-mode classifier is not a deterministic floor for dangerous git push.**
Neither graduate-by-`allow` (ADR-0017) nor graduate-by-removal (this ADR's first draft) preserves
protection for force/main push under auto mode, because both route the decision through a layer
that says `allow`.

*Probe scope / honest caveat:* tested headless (`-p`) with explicit instruction; the classifier
genuinely engaged (multi-second model calls, not the trivial-command fast path). The
fully-autonomous, never-instructed push was not elicited (hard to trigger deterministically). A
safety floor cannot be built on "the classifier blocks only pushes the agent was not told to do,"
so the caveat does not rescue the floor.

## Decision

Separate two concerns the prior ADRs conflated:

1. **The benign `git push` `ask` checkpoint** — a friction/autonomy dial. May be graduated.
2. **The dangerous-push floor** — force-push and push-to-default-branch. MUST be deterministic
   and **independent of the permission layer** (neither a static `allow` rule nor the auto-mode
   classifier).

The dangerous-push floor lives in **`security_guard.py`** (the PreToolUse deny hook, extending
ADR-0016): it pattern-matches dangerous push forms and returns `deny` in **any** mode — auto,
default, or bypass — and cannot be talked around by the model or the classifier. This is the same
"keep determinism where it matters" principle ADR-0018 used; this ADR records that dangerous git
push *is* such a place, and the classifier cannot cover it.

With that floor in place, graduating the benign `ask` checkpoint is safe **regardless of
mechanism**, because dangerous pushes are blocked by the hook, not the permission layer.

## Why this over the alternatives

- **Graduate-by-`allow` (ADR-0017)** — rejected: Probe 2 shows the classifier returns `allow`
  for dangerous push even when it runs, so a kept allow rule is not the failure mode that matters;
  the classifier itself is not a floor.
- **Graduate-by-removal relying on the classifier (this ADR's first draft)** — rejected: same
  refutation. Removing the `ask` entry drops dangerous push onto a layer that approves it.
- **Keep `git push` on `ask` forever (never graduate)** — viable conservative fallback, and the
  **interim posture** until the hook floor exists. Rejected as the *end state* only because it
  forfeits the PRD's stated unattended-autonomy payoff; acceptable until the floor ships.

## Consequences

- **`security_guard.py` gains dangerous-push patterns** (force-push: `git push --force` / `-f` /
  `--force-with-lease` judged per policy; push-to-default-branch). This is the settings/sync
  slice's work and needs its own probe + tests, not this spike's.
- **Detecting "push to default branch" from a bash string is non-trivial** — the branch may be
  implicit (`git push` with an upstream), the remote/branch order varies, `HEAD:main` forms exist.
  This is a real risk for the slice. Until the hook reliably distinguishes it, the conservative
  posture is to **keep `git push` on `ask` (un-graduated)** — concern (1) does not graduate ahead
  of concern (2)'s floor.
- **Go/No-Go**: **NO-GO** for the settings/sync slice to ship graduation while relying on the
  classifier or a static allow rule to gate dangerous push. **GO** once `security_guard.py` carries
  the dangerous-push floor (probe-verified + tested); then the benign `ask` checkpoint may graduate.
- **ADR-0017 superseded.** Its surviving valid concern — *sync must not silently regress a
  deliberate graduation* — still applies to whatever graduation marker the slice adopts.
- **ADR-0018 stands** for the general toolchain (classifier over hand-filled allowlist), but is
  explicitly **not** extended to dangerous git push: that is the deterministic exception, fully
  consistent with ADR-0018's own "probabilistic inner layer, deterministic outer floor."
- A future reader tempted to "simplify" by trusting `auto` mode to gate force/main push should
  read Probe 2: the classifier logged `behavior=allow` for both. The hook is the floor.
- **Scope of the floor (added 2026-06-16, #36 plan grilling):** "cannot be talked around" above
  holds for the *string-detectable* dangerous-push forms, which is what the floor targets. A
  string matcher cannot see a value that is not literal in the command (the same class CONTEXT.md
  names *opaque code execution*), so three forms are out of the hook's reach **by design** and are
  left to the `git push: ask` backstop: the implicit bare `git push` (upstream target not in the
  string), quoted/variable-expanded tokens (`git push origin "main"`, `$BR`), and the fact that
  `main`/`master` are matched by convention, not by querying the repo's real default. The
  asymmetry where `git push origin main` denies but `git push origin "main"` does not is therefore
  intentional, not a bug — chasing quoting variants is a losing game for a string matcher. What the
  floor *does* cover, and must, includes global-option prefixes the agent emits naturally
  (`git -C <path> push …`, `git -c k=v push …`, `git --no-pager push …`): the hook anchor is
  `\bgit\b…\bpush\b`, not strict `git push` adjacency, precisely so these do not slip through.
- **Lease family allowed to non-default branches (added 2026-06-24, glossary slim-down):** the
  safe lease family (`--force-with-lease` / `--force-if-includes`) aimed at a **non-default**
  branch is **allowed**, not denied — `security_guard.py` matches `--force` with a negative
  lookahead `(?!-with-lease|-if-includes)`, so the lease flags pass. It is the agent's correct
  non-destructive recovery path and cannot clobber published history non-interactively. Bare
  `--force` / `-f` / `+refspec`, and any push whose literal destination is `main`/`master`,
  remain denied.
