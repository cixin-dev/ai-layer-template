# Operator runbook — Night Shift live Seam-3 probes (#61, Task 2 + Task 6)

The deterministic executor is unit-green. This card drives the **live** end-to-end
verification a human must run, because it spends real subscription credit, opens a real PR,
and needs a throwaway Issue + the dedicated clone. Record the result in
`night-shift-thin-executor-report.md` (Go/No-Go) when done.

## Safety rails (read first)
- **Never merge** the PR the probe opens — it is throwaway.
- Run **only in the dedicated Night Shift clone**, never your working checkout. Sharing one
  checkout re-creates the HEAD race ADR-0024 resolves.
- **Quiesce the drain cron first** (§0) — it also runs in the clone and takes any
  `ready-for-agent` Issue, §2's throwaway included.
- Leave the **dangerous-push floor on** (`security_guard.py`, ADR-0020). Do not disable it.
- On **any** failure: STOP, record **NO-GO** with the failure, do not proceed. A failed probe
  means the substrate is invalid — escalate, don't paper over it.

Notation: `NS_CLONE` = the dedicated clone's main checkout (its `scripts/night_shift_run.sh`
is the executor under test); `NS_LOCK` = the drain cron's `flock` (loop runbook §4).

---

## 0. Quiesce the drain cron (if one is live)

A `*/5` drain in `NS_CLONE` alongside this probe is two actors on one checkout — the HEAD
race. Stop it before §1(d), wait out any in-flight drive, and resume only after §7:
```bash
touch ~/night-shift/ai-layer-template/.night-shift/stop   # drain exits at its next check, before claiming
flock -n -E 75 ~/.night-shift-loop.lock true; echo "rc $?"   # rc 0 = free; rc 75 = a drive in flight — wait, re-check
# (rc 0/75 flip grounded by §4's contention case — same flock; a */5 idle tick holds it for seconds)
```
Grounding — the live clone's `drain`, zero credit (fake `gh`/executor; re-run by `/validate` Phase 3.5):
```bash
T=$(mktemp -d); touch "$T/stop"
NIGHT_SHIFT_STATE_DIR="$T" NIGHT_SHIFT_GH=true NIGHT_SHIFT_RUN=false bash ~/night-shift/ai-layer-template/scripts/night_shift_loop.sh drain; echo "rc $?"
# → observed: kill switch: /tmp/tmp.…/stop present — stopping, rc 0  ✓
rm "$T/stop"   # known-bad: no stop file → drain polls instead (empty fake queue)
NIGHT_SHIFT_STATE_DIR="$T" NIGHT_SHIFT_GH=true NIGHT_SHIFT_RUN=false bash ~/night-shift/ai-layer-template/scripts/night_shift_loop.sh drain; echo "rc $?"
# → observed: (no kill-switch line — it polled the empty fake queue), rc 0  ✓  — rc 0, not 127: it ran
```

---

## 1. One-time host preconditions

```bash
# (a) No API key may shadow the claude.ai subscription (ADR-0024).
env | grep -i anthropic            # expect EMPTY. If set, unset + remove from ~/.bashrc.

# (b0) The spawner the SCRIPT will exec clears the version floor — resolved the way
#      night_shift_run.sh resolves it, never via your shell alias (aliases are invisible to
#      scripts and cron; a bare-PATH `claude` once resolved to a stale npm-global 1.0.8 here).
bash scripts/night_shift_run.sh check-claude      # expect: <path> 2.1.x (floor 2.1.83), exit 0
# → observed: /home/cixinit/.local/bin/claude 2.1.280 (floor 2.1.83), rc 0  ✓
# known-bad (a floor no install clears — exercises the refusal whatever this host has installed):
NIGHT_SHIFT_CLAUDE_MIN=99.0.0 bash scripts/night_shift_run.sh check-claude
# → observed: night_shift_run.sh: claude at /home/cixinit/.local/bin/claude is 2.1.280, below floor 99.0.0 — …, rc 5  ✓

# (b) Subscription auth actually works headless — through the path (b0) printed, never bare `claude`.
CLAUDE_BIN=$(bash scripts/night_shift_run.sh check-claude | cut -d' ' -f1)   # the (b0) path; reused in §3
"$CLAUDE_BIN" -p "reply with the single token SUBOK" < /dev/null   # expect: SUBOK, exit 0

# (c) Graduated push posture (#59): Bash(git push *) = allow in the USER-scope dial.
#     (Project/local-scope defaultMode:auto is ignored — spike-autonomy-probes-report.md.)
#     OPERATOR MUST FLIP THIS BY HAND: an agent editing ~/.claude/settings.json to turn push
#     ask→allow is blocked as [Self-Modification], and routing it via Bash defeats the guard —
#     so the agent cannot set this up. See memory night-shift-probe-push-dial-self-mod.md.

# (d) Dedicated clone, separate from your working checkout, on main:
git clone <same-remote-as-this-repo> ~/night-shift/ai-layer-template   # = NS_CLONE
git -C ~/night-shift/ai-layer-template checkout main
git -C ~/night-shift/ai-layer-template pull --ff-only
```

Set shell vars for the rest of the card:
```bash
NS_CLONE=~/night-shift/ai-layer-template
NS_LOCK=~/.night-shift-loop.lock
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
"$CLAUDE_BIN" -p "/plan $N" < /dev/null   # the (b0) path, never bare `claude`; add `env -u ANTHROPIC_API_KEY` only if (1a) found a key
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

Run the **clone's** executor, pointed at the **dedicated clone** via `NIGHT_SHIFT_ROOT`
(this is what keeps the clone on `main` so `/implement` branches correctly, and isolates it
from your checkout), under the drain cron's lock so a missed §0 can't overlap a drain:

```bash
NIGHT_SHIFT_ROOT="$NS_CLONE" flock -n -E 75 "$NS_LOCK" bash "$NS_CLONE/scripts/night_shift_run.sh" $N
```
It **blocks** through `/plan` → `/implement` → `/validate`, then prints `done: #$N (released
in-progress)` and exits 0. (`< /dev/null` is already applied per phase by the executor.)
**rc 75** = the lock is held (a drain is in flight): nothing ran — redo §0, re-launch.

Grounding — zero credit, read-only `snapshot` in place of `$N` (re-run by `/validate` Phase 3.5):
```bash
NIGHT_SHIFT_ROOT="$NS_CLONE" flock -n -E 75 "$NS_LOCK" bash "$NS_CLONE/scripts/night_shift_run.sh" snapshot 97; echo "rc $?"
# → observed: ISSUE_READY=1 … ATTEMPTS=0 (7 KEY=value lines), rc 0  ✓
# known-bad (the pre-fix path — #61's feature worktree, removed when #61 merged):
bash /mnt/nfs/dylan_workspace/ai-layer-template-feat61-night-shift-thin-executor/scripts/night_shift_run.sh snapshot 97; echo "rc $?"
# → observed: bash: …/night_shift_run.sh: No such file or directory, rc 127  ✓  — the dead path this fix replaces
# contention — hold the lock (an in-flight drain); the launch refuses before the executor starts:
exec 9>"$NS_LOCK"; flock -n 9
NIGHT_SHIFT_ROOT="$NS_CLONE" flock -n -E 75 "$NS_LOCK" bash "$NS_CLONE/scripts/night_shift_run.sh" snapshot 97; echo "rc $?"
# → observed: (no snapshot printed), rc 75  ✓  — flock refused; the executor never started
flock -u 9; exec 9>&-
```

---

## 5. Observe — the GO checklist (plan `## Validation` E2E)

```bash
# phase progression recorded (plan → implement → validate)
cat "$NS_CLONE/.night-shift/$N.state"

# 3 fresh phase sessions: watch live in another shell during the run
#   watch -n1 'pgrep -af "claude -p"'

# worktree created beside the clone (dir mirrors the branch, so the path carries a slash)
git -C "$NS_CLONE" worktree list                       # → entry on feat/$N-<slug>, dir ../ai-layer-template-feat/$N-<slug>

# plan is the branch's FIRST commit (scope to main.. — a bare branch walks from the
# root commit and returns "Initial commit", never verifying the claim)
git -C "$NS_CLONE" log --oneline --reverse main..feat/$N-<slug> | head -1   # → docs(plan): add ...

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
**NO-GO**) with the observed evidence above, and commit on a `docs/` branch → PR (never local `main`):
```bash
cd <your working checkout>                     # never $NS_CLONE
git checkout -b docs/ns-probe-verdict main
git add .agents/reports/night-shift-thin-executor-report.md
git commit -m "docs(report): record live Seam-3 probe Go/No-Go for #61"
```

---

## 7. Teardown (always — the probe artifacts are disposable)

```bash
gh pr close <PR#> --delete-branch        # discard the throwaway PR + its remote branch, UNMERGED
gh issue close $N                        # close the throwaway Issue
# The worktree dir mirrors the branch (carries a slash) — resolve it, never hardcode a path.
# Exec the resolver by path (it is 100755) — never `| bash …`: the security guard blocks that
# as pipe-to-shell.
WT=$(git -C "$NS_CLONE" worktree list --porcelain | "$NS_CLONE/scripts/worktree_path.sh" "feat/$N-<slug>")
git -C "$NS_CLONE" worktree remove "$WT"
# the dedicated clone itself can stay for future Night Shift use
rm "$NS_CLONE/.night-shift/stop"          # resume the drain cron quiesced in §0
```
Grounding — the resolver exec'd by path in `NS_CLONE` (re-run by `/validate` Phase 3.5):
```bash
git -C "$NS_CLONE" worktree list --porcelain | "$NS_CLONE/scripts/worktree_path.sh" main; echo "rc $?"
# → observed: /home/cixinit/night-shift/ai-layer-template, rc 0  ✓
# known-bad (no worktree has that branch):
git -C "$NS_CLONE" worktree list --porcelain | "$NS_CLONE/scripts/worktree_path.sh" feat/0-no-such; echo "rc $?"
# → observed: (empty), rc 0  ✓  — rc 0 proves it ran; an exec failure is 126/127, not "no match"
```
NO-GO path: keep the artifacts for diagnosis instead of tearing down, and escalate.
