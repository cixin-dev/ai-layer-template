# `security_guard.py` denies *opaque code execution*, not just network fetch-and-execute

**Status:** Extends ADR-0016 (the `exit(2)` deny hook). Informs the Unattended-Autonomy PRD.

## Context

ADR-0016 added untrusted fetch-and-execute to the `exit(2)` deny hook and enumerated three
forms: `curl … | sh`, `wget … | bash`, and bare `… | sh`. The shipped patterns (PR #31) went
further — they also deny command substitution into a shell (`sh -c "$(…)"`, backtick, and
`eval "$(…)"`). That is broader than "fetch": those last patterns fire on **any** command
substitution, including purely local ones with no network access (`eval "$(ssh-agent)"`,
`eval "$(direnv hook bash)"`, `sh -c "$(cat ./local.sh)"`). So two things were left unstated:
what class is *actually* being denied, and whether the local-only collateral is intended.

## Decision

The class denied is **opaque code execution** (CONTEXT.md), not "fetch-and-execute": a command
whose real payload is **not literal in the command**, so no human sees what will run when it is
authored — whether the payload arrives by pipe-to-shell or by command substitution. The
network fetch is only one source of the payload; the threat is the **opacity**.

We **accept the full blast radius**: benign local command substitution (`eval "$(ssh-agent)"`
and friends) is denied too, as a deliberate false positive — not narrowed to "only when the
substitution contains `curl`/`wget`".

## Why deny the whole class, not just fetch

- **Narrowing to "fetch" reopens the hole.** Requiring `curl`/`wget` inside the `$( )` is
  trivially bypassed by obfuscation: `eval "$(echo Y3VybC4uLg== | base64 -d)"` fetches and runs
  with no literal `curl`. Defeating obfuscation is the whole point; an opacity test catches it,
  a fetch test does not.
- **This hook is the deterministic floor, not the UX path.** Under `auto` mode (ADR-0018) the
  probabilistic classifier is the inner layer and already waves through obviously-benign
  `ssh-agent`; this `exit(2)` hook only backstops it. A backstop is allowed to be blunt.
- **The escape hatch is cheap.** A denied-but-trusted command runs with one manual `! eval
  "$(ssh-agent)"` — a human-in-the-loop line, not a workflow tax — so the false-positive cost is
  near zero against the silent-bypass cost it prevents.

## Consequences

- The glossary term is **opaque code execution**; `fetch-and-execute` is retired to its
  _Avoid_ list (it names only one source and mislabels the local-substitution denials). The
  hook's deny message, docstring, identifiers (`OPAQUE_EXEC_PATTERNS`, `check_opaque_exec`), and
  the `boundary`/`sandbox` CONTEXT.md entries all use the new term.
- `security_guard.test.sh` asserts a benign local substitution (`eval "$(ssh-agent)"`) is
  **denied** — the accepted false positive is an executable contract, not a latent surprise.
- A future reader who sees `eval "$(ssh-agent)"` blocked and wants to "fix" it by scoping the
  command-substitution patterns to network commands should read this first: that narrowing is
  the obfuscation hole, declined on purpose.
