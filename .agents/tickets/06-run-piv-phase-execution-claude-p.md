---
id: "06"
slug: run-piv-phase-execution-claude-p
title: Per-phase claude -p execution with CLAUDE.md loaded + file-based state
type: AFK
status: ready-for-agent
blocked_by: ["05"]
prd: .agents/prds/piv-pipeline-automation.prd.md
covers_stories: [2, 3, 4, 5, 8]
---

# Per-phase `claude -p` execution + file-based state

## What to build

Fill the skeleton's stubbed phase loop (Ticket 05) with real, fresh-process execution. Each
phase becomes a separate `claude -p` invocation; state passes only through files.

In `scripts/run-piv.sh`, for each Ticket in order:

- **Plan phase** — `claude -p "<plan prompt referencing the ticket file>"` writes
  `.agents/plans/{slug}.plan.md`. The prompt references the Ticket file by path; it does not
  inline Ticket content.
- **Implement phase** — a fresh `claude -p "<implement prompt referencing the plan file>"`
  reads `.agents/plans/{slug}.plan.md`, edits code, runs the project's Verify commands.
- **Validate phase** — a fresh `claude -p "<validate prompt>"` reads the plan and re-runs the
  Verify commands.
- **No `--bare`.** Every invocation loads this repo's CLAUDE.md (the AI Layer contract). Pass
  `--allowedTools` and `--permission-mode` so headless phases never block on a prompt; pass a
  model flag if the project pins one.
- **Exit-code contract.** A phase's success is the **exit code of the project's Verify
  commands**, not the model's prose. A phase is red iff a Verify command exits non-zero.
  (Failure *handling* — retry / FAILED.md / stop — is Ticket 07; here, simply propagate: a red
  phase aborts the run with a non-zero exit and no commit.)
- **Fresh-process guarantee.** Phases are independent processes — never `--continue` /
  `--resume`. The only thing crossing a phase boundary is a file.

The Verify commands come from CLAUDE.md "Project specifics → Verify commands"; the driver reads
them from there (or a single config point) and hardcodes no stack tool.

## Acceptance criteria

- [ ] Each Ticket triggers exactly three `claude -p` invocations (Plan, Implement, Validate),
      each a separate process, none passed `--bare`, none using `--continue`/`--resume`.
- [ ] Plan writes `.agents/plans/{slug}.plan.md`; Implement and Validate read it back (verified
      via the stub recording which files each phase was pointed at).
- [ ] A phase is judged red/green by the **Verify command exit code**, not model output.
- [ ] A red phase aborts the run with a non-zero exit and produces no commit (full handling is
      Ticket 07).
- [ ] `--dry-run` still works and now prints the real `claude -p …` command lines it would run.
- [ ] `scripts/run-piv.test.sh` is extended and remains the validate gate, using a **`claude`
      stub earlier on `PATH`** that records args + emits canned exit codes, and a **stub Verify
      command** to force a phase red/green. Tests stay hermetic (no real `claude`, no token
      spend) and leave no residue.
- [ ] New test cases: (a) three separate invocations per Ticket; (b) no `--bare`/`--continue`
      in any invocation; (c) plan file written then read by later phases; (d) Verify-exit-code
      drives red/green.

## Blocked by

Ticket 05 (needs the discovery + ordering + phase-loop skeleton and the test harness).

## Notes

This is where the Smart Zone philosophy becomes mechanical (ADR-0008): independence is the
memoryless `claude -p` process; the contract is the loaded CLAUDE.md; the only inter-phase
interface is the plan file. Keep phase prompts terse and path-referencing so the driver carries
no embedded state.

Real token-spending behavior first appears here, but tests must never invoke the real binary —
the `claude` stub is mandatory. Manual first-run verification against a trivial fixture Ticket
is the way to confirm real end-to-end behavior.
