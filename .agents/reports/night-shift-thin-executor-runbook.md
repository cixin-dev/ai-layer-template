# Operator runbook — Night Shift live Seam-3 probes (#61, Task 2 + Task 6)

The deterministic executor is unit-green. This card drives the **live** end-to-end
verification a human must run, because it spends real subscription credit, opens a real PR,
and needs a throwaway Issue + the dedicated clone. Record the result in
`night-shift-thin-executor-report.md` (Go/No-Go) when done.

## Safety rails (read first)
- **Never merge** the PR the probe opens — it is throwaway.
- Run **only in the dedicated Night Shift clone**, never your working checkout. Sharing one
  checkout re-creates the HEAD race ADR-0024 resolves.
- Leave the **dangerous-push floor on** (`security_guard.py`, ADR-0020). Do not disable it.
- On **any** failure: STOP, record **NO-GO** with the failure, do not proceed. A failed probe
  means the substrate is invalid — escalate, don't paper over it.

Notation: `NS_CLONE` = the dedicated clone's main checkout; `FEAT_WT` = this feature worktree
(where the not-yet-merged `scripts/night_shift_run.sh` lives).

---

## 1. One-time host preconditions

```bash
# (a) No API key may shadow the claude.ai subscription (ADR-0024).
env | grep -i anthropic            # expect EMPTY. If set, unset + remove from ~/.bashrc.

# (b) Subscription auth actually works headless.
claude -p "reply with the single token SUBOK" < /dev/null   # expect: SUBOK, exit 0

# (c) Graduated push posture (#59): Bash(git push *) = allow in the USER-scope dial.
#     (Project/local-scope defaultMode:auto is ignored — spike-autonomy-probes-report.md.)

# (d) Dedicated clone, separate from your working checkout, on main:
git clone <same-remote-as-this-repo> ~/night-shift/ai-layer-template   # = NS_CLONE
git -C ~/night-shift/ai-layer-template checkout main
git -C ~/night-shift/ai-layer-template pull --ff-only
```

Set shell vars for the rest of the card:
```bash
NS_CLONE=~/night-shift/ai-layer-template
FEAT_WT=/mnt/nfs/dylan_workspace/ai-layer-template-feat61-night-shift-thin-executor
```

---

## 2. Create a throwaway `ready` Issue

Keep it **trivial** so the full PIV drive is fast and cheap (its `/implement` + `/validate`
run for real). A doc/no-op change is ideal.

```bash
gh issue create \
  --title "throwaway: ns probe — add a one-line greeting helper" \
  --body  "Disposable Issue to verify the Night Shift executor end to end. Add a trivial \
self-contained helper + its test. Will be closed unmerged." \
  --label ready-for-agent
# → note the number as $N
```

---

## 3. Task 2 — gate probe (one real slash command) ⟵ run FIRST

Confirms a real PIV slash command expands and runs unattended on the subscription **before**
trusting the full drive.

```bash
cd "$NS_CLONE"
claude -p "/plan $N" < /dev/null      # add `env -u ANTHROPIC_API_KEY` only if (1a) found a key
```
**GO if:** runs with no permission stall, exits 0, and writes `.agents/plans/<slug>.plan.md`
in `$NS_CLONE`. **If it stalls on a permission prompt:** turn on the user-scope auto posture
(spike report) or pass `--permission-mode`; re-run. **NO-GO** ⇒ stop here, the substrate fails.

Reset before the full drive so Task 6 exercises `/plan` itself:
```bash
rm -f "$NS_CLONE"/.agents/plans/<slug>.plan.md
```
(Or skip this reset and let the executor resume from the existing draft — that demonstrates
restartability, but you then see only 2 fresh `claude` processes, not 3.)

---

## 4. Task 6 — full end-to-end drive

Run **this branch's** executor, pointed at the **dedicated clone** via `NIGHT_SHIFT_ROOT`
(this is what keeps the clone on `main` so `/implement` branches correctly, and isolates it
from your checkout):

```bash
NIGHT_SHIFT_ROOT="$NS_CLONE" bash "$FEAT_WT/scripts/night_shift_run.sh" $N
```
It **blocks** through `/plan` → `/implement` → `/validate`, then prints `done: #$N (released
in-progress)` and exits 0. (`< /dev/null` is already applied per phase by the executor.)

---

## 5. Observe — the GO checklist (plan `## Validation` E2E)

```bash
# phase progression recorded (plan → implement → validate)
cat "$NS_CLONE/.night-shift/$N.state"

# 3 fresh phase sessions: watch live in another shell during the run
#   watch -n1 'pgrep -af "claude -p"'

# worktree created beside the clone
git -C "$NS_CLONE" worktree list                       # → ../ai-layer-template-feat$N-<slug>

# plan is the branch's FIRST commit
git -C "$NS_CLONE" log --oneline --reverse feat/$N-<slug> | head -1   # → docs(plan): add ...

# branch pushed + PR opened, and NEVER merged
gh pr list --head "feat/$N-<slug>" --state open --json number,url
gh pr view <PR#> --json state --jq .state              # → OPEN (not MERGED)

# claim released on terminal
gh issue view $N --json labels --jq '[.labels[].name]' # → no "in-progress"
```
Also confirm the **`pr-ready` notification fired** (bell on the tmux window, and ntfy push if
a topic is configured) when the PR opened, and that **no phase was advanced by hand**.

All boxes checked ⇒ **GO**. Any box fails ⇒ **NO-GO** (record the failure).

---

## 6. Record the verdict

Edit `night-shift-thin-executor-report.md` → **Go/No-Go**: change 🟡 to ✅ **GO** (or 🔴
**NO-GO**) with the observed evidence above, and commit on the feature branch:
```bash
cd "$FEAT_WT"
git add .agents/reports/night-shift-thin-executor-report.md
git commit -m "docs(report): record live Seam-3 probe Go/No-Go for #61"
```

---

## 7. Teardown (always — the probe artifacts are disposable)

```bash
gh pr close <PR#> --delete-branch        # discard the throwaway PR + its remote branch, UNMERGED
gh issue close $N                        # close the throwaway Issue
git -C "$NS_CLONE" worktree remove ../ai-layer-template-feat$N-<slug>   # or: /clean-worktree
# the dedicated clone itself can stay for future Night Shift use
```
NO-GO path: keep the artifacts for diagnosis instead of tearing down, and escalate.
