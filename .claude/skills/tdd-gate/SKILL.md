---
name: tdd-gate
description: Test-driven development as the verification gate during implementation. Use when building features or fixing bugs test-first, when the user mentions TDD or red-green-refactor, or when deciding how to verify a change before writing it.
---

# TDD Gate

Rate of feedback is your speed limit. An agent left without feedback constraints
"outruns its headlights" — generating large amounts of code before discovering it's wrong.
TDD forces small steps and gives machine-readable feedback the agent can self-correct
against. Define how you'll verify *before* you write.

## Tests verify behavior, not implementation

A good test exercises the public interface and reads like a specification ("user can
checkout with a valid cart"). It survives refactors because it doesn't care about internal
structure. A bad test mocks internal collaborators or asserts on private details — it breaks
when you rename a function even though behavior is unchanged. Warning sign: the test fails
on a refactor that didn't change behavior.

## Anti-pattern: horizontal slices

Do **not** write all tests first, then all implementation. Tests written in bulk verify
*imagined* behavior — you end up testing the *shape* of things (signatures, data
structures) instead of real, user-facing behavior, and the tests go insensitive to actual
breakage.

```
WRONG (horizontal):  RED: test1..test5   then  GREEN: impl1..impl5
RIGHT (vertical):    test1→impl1, test2→impl2, test3→impl3, ...
```

## The loop

1. **Tracer bullet** — one test for one behavior → it fails (RED) → minimal code to pass
   (GREEN). Proves the path works end to end.
2. **Incremental** — for each remaining behavior: next test (RED) → minimal code (GREEN).
   One test at a time; only enough code to pass it; don't anticipate future tests.
3. **Refactor** — only once GREEN. Extract duplication, deepen modules (move complexity
   behind simple interfaces — see [`deep-module-pattern`](../../../examples/deep-module-pattern.md)),
   re-run tests after each step. Never refactor while RED.

## Per-cycle checklist

```
[ ] Test describes behavior, not implementation
[ ] Test uses the public interface only
[ ] Test would survive an internal refactor
[ ] Code is minimal for this test
[ ] No speculative features added
```

## Honest limits

You can't test everything — confirm which behaviors matter most and focus there.
AI-written tests can be self-fulfilling (they verify exactly the behavior the agent chose
to implement, not what was actually required), so a human should review the test *design*,
not just that the suite is green.
