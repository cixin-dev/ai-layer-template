# CONTEXT.md (nouns) vs CLAUDE.md (process) boundary

This template ships two always-relevant documents that both describe the Harness, so it is
easy for the same vocabulary to leak into both — and for a future contributor to ask, every
time a term comes up, "does this go in CONTEXT.md or CLAUDE.md?"

We split them on a single rule: **CONTEXT.md is a glossary of nouns — the things/concepts the
project talks about; CLAUDE.md describes the process — how to work.** A term earns a
CONTEXT.md entry only when it is (a) a coined, project-specific noun **and** (b) has competing
names or is referenced across enough places to need one canonical meaning. Pure working
principles and procedure steps stay in CLAUDE.md. So `Smart Zone`, `Ticket`, `PRD` are
glossary nouns; `verification-led` and the `TDD gate` are process and stay in CLAUDE.md.
Artifacts bound to one process step (the plan file, the report, the retroactive session) are
folded into that step's glossary entry rather than given standalone entries.

We accept **light overlap** deliberately: CLAUDE.md may use a term in passing that CONTEXT.md
defines, rather than forcing a single-source-of-truth that would make either file unreadable
on its own. The alternative — one combined file, or strict no-repetition — was rejected
because each file must stand alone for its job (CONTEXT.md primes shared language; CLAUDE.md
primes how to act).
