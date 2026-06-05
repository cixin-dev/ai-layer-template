# Deep Module Pattern

The `examples/` folder is on-demand context: concrete patterns an agent learns from. This
one captures the single most important shape for testable, agent-friendly code. Add more
examples as your project develops conventions worth mirroring — more good examples means
better implementations.

## The idea

From *A Philosophy of Software Design*: a **deep module** has a **small interface** over a
**large implementation**. The simple surface is what callers (and tests) touch; complexity
is hidden behind it.

```
Deep module (good)                    Shallow module (avoid)
┌─────────────────────┐               ┌─────────────────────────────────┐
│   Small interface   │ few methods   │       Large interface           │ many methods
├─────────────────────┤               ├─────────────────────────────────┤
│                     │               │  Thin implementation            │ just passes through
│  Deep implementation│ complexity    └─────────────────────────────────┘
│      hidden         │
└─────────────────────┘
```

A shallow module — large interface, little behind it — leaks complexity to its callers and
is hard to test, because the test has to know about the internals to say anything useful.

## Why it matters for AI-assisted work

- **Testability**: with a small public interface you test *behavior* through that interface
  and never touch internals. Tests survive refactors (see
  [`../.claude/skills/tdd-gate/SKILL.md`](../.claude/skills/tdd-gate/SKILL.md)).
- **Smart zone**: a narrow interface is less context an agent must hold to use the module
  correctly. Complexity hidden behind it doesn't have to be re-read on every change.
- **Surgical changes**: clear boundaries mean a change stays inside one module instead of
  rippling across callers.

## Design questions when shaping an interface

- Can I reduce the number of methods?
- Can I simplify the parameters?
- Can I hide more complexity *inside* the module?

## Sketch (language-agnostic)

```
# Small interface — the only thing callers and tests depend on
getProject(id, requestingUser) -> Project        # raises NotFound / AccessDenied

# Deep implementation, hidden behind that one call:
#   - fetch the record
#   - enforce visibility / ownership rules
#   - structured logging of start / completed / failed
#   - map storage errors to domain errors
```

A test asserts on the *behavior* — "a non-owner requesting a private project gets
AccessDenied" — without ever knowing how visibility is stored or logged. The implementation
can change entirely; the test does not.

## Related conventions

- **Separate the pure data layer from business logic** so each can be reasoned about and
  tested on its own; expose only the business-logic surface as the module's public API.
- **Vertical slices**: keep a feature's whole stack in one folder so an agent reads one
  place, not every layer — fewer cross-layer context jumps.
