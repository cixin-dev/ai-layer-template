# Research: Cole Medin Harness Repos

A full inventory of three upstream repositories that define patterns and concepts the `ai-layer-template` borrows: `harness-engineering-demo`, `context-engineering-intro`, and `agency-agents`.

---

## 1. Provenance

### harness-engineering-demo
- **Remote**: `https://github.com/coleam00/harness-engineering-demo.git`
- **Last commit**: `0eef011` — "docs: reframe PIV loop to plan->implement + add a captured Ralph example run"
- **Top-level structure**: Real app (Schedulr: FastAPI backend + Next.js frontend) wrapped with harness machinery
  - `CLAUDE.md` — project-specific rules (naming, patterns, hard rules)
  - `.claude/skills/{plan,implement,validate,review}/SKILL.md` — the PIV Loop operationalized
  - `.claude/agents/code-reviewer.md` — sub-agent for code review (reads CLAUDE.md + codebase-search MCP)
  - `.claude/context/{architecture,auth,codebase-search,export-pattern,testing,timezones}.md` — on-demand modules
  - `.claude/hooks/{post_tool_use_lint,stop_validate,security_guard}.py` — automation hooks
  - `.mcp.json` + `tooling/mcp/codebase_search.py` — AST-based symbol navigation MCP
  - `ralph/` — Ralph loop (headless iteration driver; strings sessions together)
  - `app/` — the brownfield app itself (not harness)
  - `README.md` — full explanation of the harness concept + Ralph usage

### context-engineering-intro
- **Remote**: `https://github.com/coleam00/context-engineering-intro.git`
- **Last commit**: `a2d84b0` — "Add README for WISC framework use case"
- **Top-level structure**: Templates + methodology, not tied to a specific app
  - `CLAUDE.md` — global project rules (code structure, testing, documentation, style, AI behavior)
  - `.claude/commands/{generate-prp,execute-prp}.md` — commands to turn INITIAL.md → PRP → implementation
  - `PRPs/templates/prp_base.md` — base template for comprehensive implementation blueprints
  - `PRPs/EXAMPLE_multi_agent_prp.md` — example of a complete PRP
  - `examples/` — code examples referenced by PRPs
  - `validation/` — validation strategies and example commands
  - `use-cases/` — templated subdirs for different tech stacks (MCP server, Pydantic AI, agent-factory, WISC framework, etc.)
  - `INITIAL.md`, `INITIAL_EXAMPLE.md` — templates for feature requests

### agency-agents
- **Remote**: `https://github.com/msitarzewski/agency-agents.git`
- **Last commit**: `241dc5e` — "docs: refresh agent roster + fix stale counts (203 agents / 14 divisions)"
- **Top-level structure**: A large catalog of AI agent personas organized by domain
  - `README.md` — explains the Agency concept (collection of specialized agent personalities)
  - Directory structure by domain: `engineering/`, `design/`, `marketing/`, `sales/`, `product/`, `project-management/`, `specialized/`, `testing/`, `support/`, `academic/`, `finance/`, `spatial-computing/`, `game-development/`, `integrations/`
  - Each agent is a markdown file with: identity/personality traits, core mission/workflows, technical deliverables, success metrics, communication style
  - `project-management/` subdir: `project-manager-senior.md`, `project-shepherd.md`, `project-management-studio-producer.md`, `project-management-project-shepherd.md`, `project-management-experiment-tracker.md`, `project-management-studio-operations.md`, `project-management-meeting-notes-specialist.md`, `project-management-jira-workflow-steward.md`
  - `scripts/` — installation and conversion utilities for multiple tools (Claude Code, Copilot, Cursor, Aider, etc.)
  - `CONTRIBUTING.md`, `SECURITY.md`, `LICENSE` (MIT)

---

## 2. Per-Repo Findings

### harness-engineering-demo

#### Skills (the PIV Loop operationalized)
| File | Purpose | Key excerpt |
|------|---------|-------------|
| `.claude/skills/plan/SKILL.md` | Phase 1 of PIV: analyze ticket, read codebase, identify patterns, write plan to `.agents/plans/{name}.plan.md`. No code. | "Identify: Files to modify (with line refs). New files to create. Migration needed?" |
| `.claude/skills/implement/SKILL.md` | Phase 2 of PIV: read plan, execute tasks in dependency order, validate after each task, write `.agents/reports/{name}-implementation-report.md`. | "Run the task's `Validate:` command immediately. If it fails, fix before continuing." |
| `.claude/skills/validate/SKILL.md` | Run full quality gate: ruff + mypy + pytest + tsc + vitest. Run before any commit or PR. | "This is the same gate the `Stop` hook enforces automatically." |
| `.claude/skills/review/SKILL.md` | Sub-agent code review: delegates diff to code-reviewer sub-agent, writes `.agents/reports/{name}-review.md`. | Mentioned but full file not read. |

#### Agents
| File | Purpose |
|------|---------|
| `.claude/agents/code-reviewer.md` | Sub-agent persona for code review against CLAUDE.md rules using codebase-search MCP. |

#### Hooks (automation)
| File | Purpose | Key behavior |
|------|---------|--------------|
| `.claude/hooks/post_tool_use_lint.py` | Runs after every file edit (Edit/Write/MultiEdit): ruff for Python, tsc for TS. Non-blocking. | Surfaces issues without stopping work. |
| `.claude/hooks/stop_validate.py` | Before Claude finishes: runs ruff + pytest. Blocks if either fails. | Makes PIV self-validating: agent can't stop until gate is green. |
| `.claude/hooks/security_guard.py` | PreToolUse: denies reading/writing real `.env` files and recursive directory deletes. | "It returns a `permissionDecision: deny` so Claude adapts." |

#### MCP / Codebase Search
| File | Purpose |
|------|---------|
| `.mcp.json` | Registers codebase-search MCP server. |
| `tooling/mcp/codebase_search.py` | FastMCP server with three tools: `find_references`, `where_is`, `outline` — AST-based symbol navigation. |

#### Ralph Loop (session orchestration)
| File | Purpose |
|------|---------|
| `ralph/ralph.py`, `ralph/ralph.sh` | Headless driver: strings together multiple Claude sessions, re-feeding a spec each iteration until `DONE.txt` appears. Each iteration commits, so all steps reversible. |
| `ralph/example-run/` | Captured example run: spec input, iteration log, fix plan, produced code. |

#### Context Modules (on-demand)
| File | Purpose |
|------|---------|
| `.claude/context/architecture.md` | When adding a new resource, service, or route. |
| `.claude/context/auth.md` | When working on authentication or authorization. |
| `.claude/context/codebase-search.md` | How to use the MCP tools (where_is, find_references, outline). |
| `.claude/context/export-pattern.md` | CSV/export escaping pattern; prevents formula-injection attacks. |
| `.claude/context/testing.md` | When writing or modifying tests. |
| `.claude/context/timezones.md` | Datetime display, serialization, and storage rules. |

#### Project-Specific CLAUDE.md
The `CLAUDE.md` is application-specific (Schedulr B2B meeting-scheduling SaaS):
- Naming conventions (snake_case Python, PascalCase classes, kebab-case TS files, etc.)
- Core code patterns (Pydantic schemas, SQLAlchemy 2.0 mapped columns, structured errors, DB sessions)
- Build & validation commands (backend: ruff, mypy, pytest; frontend: tsc, npm test)
- Hard rules (run `/validate` before PR, no secrets in version control, Alembic migrations must be reversible, no formula injection in CSV, forward auth pattern only)
- Symbol navigation via MCP instead of grep
- Gotchas (Postgres on port 5433, two auth systems coexist, brownfield `.createdAt` camelCase column, `uv.lock` committed, `node_modules` NOT committed)

---

### context-engineering-intro

#### Commands
| File | Purpose | Key behavior |
|------|---------|--------------|
| `.claude/commands/generate-prp.md` | Research-driven PRP creation: codebase analysis + external research → comprehensive implementation blueprint. Output to `PRPs/{name}.md`. | "The goal is one-pass implementation success through comprehensive context." |
| `.claude/commands/execute-prp.md` | Execute a PRP: read it, iterate until validation gates pass. | Implied from folder structure; full file not read. |

#### PRP (Product Requirements Prompt) Templates
| File | Purpose |
|------|---------|
| `PRPs/templates/prp_base.md` | Base template covering: Goal, Why, What, Success Criteria, All Needed Context (docs + examples), Current & Desired Codebase tree, Known Gotchas, Data Models, Task list, Pseudocode, Integration Points, Validation Loops (3 levels: syntax, unit tests, integration), Final Checklist, Anti-Patterns. |
| `PRPs/EXAMPLE_multi_agent_prp.md` | Concrete example of a complete PRP. |

#### CLAUDE.md (Global Rules)
Project-agnostic rules emphasizing context engineering:
- Project Awareness: read `PLANNING.md`, check `TASK.md`, use consistent naming
- Code Structure: no files >500 LOC, clear module organization (e.g. agent.py / tools.py / prompts.py)
- Testing & Reliability: Pytest unit tests, 3 per feature (happy path + edge case + failure), tests mirror main structure
- Task Completion: mark completed tasks in `TASK.md`, add discovered TODOs
- Style & Conventions: Python + PEP8 + type hints + black + Pydantic + FastAPI/SQLAlchemy, Google-style docstrings
- Documentation & Explainability: update README, comment non-obvious code, explain the why
- AI Behavior Rules: ask if uncertain, never hallucinate libraries, confirm file paths exist, never silently overwrite

#### Use Cases (Stack-Specific Templates)
Directory structure offering templated entry points for different tech stacks:
- `use-cases/mcp-server/` — MCP server setup
- `use-cases/pydantic-ai/` — Pydantic AI agents
- `use-cases/template-generator/` — Generator patterns
- `use-cases/agent-factory-with-subagents/` — Multi-agent setups
- `use-cases/ai-coding-wisc-framework/` — WISC framework integration
- `use-cases/ai-coding-workflows-foundation/` — Foundational workflows

Each subdir contains its own `CLAUDE.md`, `README.md`, and example `PRPs/`.

#### Validation & Examples
| File | Purpose |
|------|---------|
| `validation/README.md` | Documentation of validation strategies. |
| `validation/example-validate.md` | Concrete example of a validation run. |
| `validation/ultimate_validate_command.md` | Master validation script. |

---

### agency-agents

#### PM / Product Management Personas
| File | Purpose | Key instincts |
|------|---------|--------------|
| `project-management/project-manager-senior.md` | Converts specs to tasks with realistic scope. **Not** a strategic planner — focuses on spec analysis, task list creation, acceptance criteria. | "Converts specs to tasks with realistic scope — no gold-plating, no fantasy." No luxury features not in spec. Task structure for 30–60 min developer implementation. |
| `project-management/project-shepherd.md` | Cross-functional project orchestration: timeline management, stakeholder alignment, resource coordination, risk mitigation. **Not** tactical task-making — strategic and long-term project health. | "Herds cross-functional chaos into on-time, on-scope delivery." 95% on-time delivery goal. Emphasis on stakeholder communication, risk identification, change control. |
| `project-management/project-management-studio-producer.md` | Studio/media production oversight (not read; name suggests film/game production domain). | Likely management of talent, schedules, asset pipelines. |

**Key finding on strategic planning**: Agency-agents does **not** contain a "Product Manager" or "Strategic Planning" persona that matches the `strategic-planning` skill in `ai-layer-template`. The closest is "Senior Project Manager" (spec → tasks), but that is **tactical task decomposition**, not the **strategic brain dump → clarifying questions → PRD** interaction that the project's Strategic Planning skill models. The Project Shepherd is closer to strategic/stakeholder work but focuses on cross-functional coordination, not product discovery.

#### Other Personas (Engineering, Design, Marketing, etc.)
| Domain | Sample agents | Purpose |
|--------|---------------|---------|
| **Engineering** | Frontend Developer, Backend Architect, Mobile App Builder, AI Engineer, DevOps, Security Engineer, Codebase Onboarding Engineer, etc. | Specialized personas for different coding domains. Each includes identity, core mission, deliverables, success metrics, communication style. |
| **Design** | — | (Directory exists; not explored in depth.) |
| **Marketing** | — | (Directory exists; not explored in depth.) |
| **Product** | — | (Directory exists; not explored in depth.) |
| **Testing** | — | (Directory exists; not explored in depth.) |

#### Tooling / Scripts
| File | Purpose |
|------|---------|
| `scripts/install.sh` | Interactive installation to Claude Code and other tools (Copilot, Cursor, Aider, Windsurf, Kimi, Codex, etc.). Detects installed tools and installs agents. |
| `scripts/convert.sh` | Convert agent definitions to formats for other tools. |

---

## 3. Mapping to the Two-Phase Harness

The `ai-layer-template` defines two phases:
- **Phase 1 — Project Setup**: Alignment + Strategic Planning → PRD + Issues
- **Phase 2 — Development (PIV Loop)**: per-ticket Plan → Implement → Validate, with outer System Evolution loop

| Artifact | Repo | Maps to | Already in ai-layer-template? | Adoption note |
|----------|------|---------|------|----------------|
| PIV Loop (Plan/Implement/Validate skills) | harness-engineering-demo | Phase 2 (PIV) | YES — borrowed directly | harness-engineering-demo shows it in action on a real app; no adoption needed (already imported concept) |
| Hooks (PostToolUse lint, Stop gate, PreToolUse security) | harness-engineering-demo | Phase 2 (validation automation) | NO — harness-engineering-demo shows hooks pattern | hooks/ machinery could be extracted and offered as a reusable addon if projects want per-task validation |
| Ralph loop (headless multi-session orchestrator) | harness-engineering-demo | Cross-phase orchestration | NO — orchestration layer | Ralph is a separate orchestrator layer (ADR-0003 excludes orchestration from this repo's scope) |
| MCP codebase-search (AST-based symbol navigation) | harness-engineering-demo | Phase 2 (codebase research) | NO — tool/capability | Could be offered as an optional MCP for downstream repos needing fast symbol lookup |
| Context modules (architecture, auth, export-pattern, etc.) | harness-engineering-demo | Phase 2 (on-demand context) | PARTIAL — `.claude/context/` pattern exists; examples domain-specific | Pattern borrowed; each project adds its own domain-specific modules |
| PRP template + generate-prp / execute-prp commands | context-engineering-intro | Phase 1 & 2 hybrid (research → implementation blueprint) | NO — alternative to Plan-Implement split | PRPs are Cole's alternative to the full PIV separation; context-engineering-intro does **one** big PRP phase, harness does **two** (Plan separate from Implement). Both valid; `ai-layer-template` deliberately chose PIV's session separation (CLAUDE.md rationale). |
| Project-agnostic CLAUDE.md rules | context-engineering-intro | Cross-cutting (global rules for any project) | YES — template provided; project fills in stack-specific parts | AI-layer-template's CLAUDE.md borrows the idea; context-engineering-intro is more detailed for Python/FastAPI/Pytest stacks |
| Use-case templates (MCP server, Pydantic AI, agent-factory) | context-engineering-intro | Phase 1 (project scaffolding) | NO — stack-specific onboarding | Could be adapted as Phase 1 templates for downstream repos using those stacks |
| Validation checklist (syntax, unit tests, integration) | context-engineering-intro | Phase 2 (validation strategy) | YES — conceptually via tdd-gate | context-engineering-intro's 3-level checklist is more granular than ai-layer-template's gate |
| PM persona (Senior Project Manager, Project Shepherd) | agency-agents | Phase 1 (Strategic Planning) | NO — but not a clean fit | Agency-agents' PM personas are **tactical** (spec → tasks) or **organizational** (stakeholder management), not **strategic** (problem discovery). Strategic Planning in ai-layer-template is different: brain dump → clarifying questions → PRD. No adoption. |
| Engineering personas (Frontend, Backend, AI Engineer, etc.) | agency-agents | Phase 2 (role personas) | NO — alternative approach | Agency-agents treats each role as a persona to invoke; ai-layer-template uses commands/skills for procedures instead. Different philosophy. |
| Agent-factory / multi-agent setup | agency-agents | Potential Phase 1 research tool | NO — adjacent to this harness | Could be useful for projects needing agents, but not core to the harness. |

---

## 4. Concept Lineage — Where Upstream Defines Terms

The `ai-layer-template` CONTEXT.md and CLAUDE.md reference the following concepts from upstream:

### From harness-engineering-demo (Cole Medin origin)

**Harness** — CONTEXT.md 14–19:
> Everything besides the model that lets a coding agent reliably finish work in a project — the deliberately engineered, continuously iterated scaffolding (rules, commands, skills, examples, hooks, sub-agents, context policies, feedback loops). [...] This is the thing this repository builds. Borrowed framing: Cole Medin / Addy Osmani ("Harness Engineering").

**AI Layer** — CONTEXT.md 22–28:
> The user-authored, version-controlled document asset at the core of the Harness: `CLAUDE.md` + `.claude/commands/` + `.claude/skills/` + `examples/`. [...] Borrowed term: Cole Medin.

**Smart Zone** — CONTEXT.md 30–36:
> The span of a session — roughly the first ~100k tokens — in which an agent still does its best work, before attention overloads and decisions get sloppy (the *dumb zone* beyond it). [...] Coined here; the underlying limits are *context decay* and *amnesia*.

**PIV Loop** — CONTEXT.md 132–139:
> The per-ticket inner loop — Plan → Implement → Validate — where each phase is a fresh session [...] Term: Cole Medin.

**System Evolution** — CONTEXT.md 141–147:
> The outer loop: when a bug slips through, fix the Harness (rules, commands, skills) so the class of problem can't recur. [...] Term: Cole Medin.

**Strategic Planning** — CONTEXT.md 73–81:
> The project-level planning stage: brain dump → clarifying questions → PRD → tickets. Runs **once per feature** and *outputs* the tickets that Phase 2 consumes. [...] Term: Cole Medin.

### From context-engineering-intro (Cole Medin origin)

**Context Engineering** (not explicitly in CONTEXT.md, but the methodology):
> The discipline of engineering context for AI coding assistants so they have the information necessary to get the job done end-to-end. "10x better than prompt engineering and 100x better than vibe coding."

**PRP (Product Requirements Prompt)** — Not in CONTEXT.md; Cole's term from context-engineering-intro:
> Comprehensive implementation blueprints including context, documentation, implementation steps with validation, error handling patterns, test requirements.

### From Domain-Driven Design (Evans, via Matt Pocock)

**Ubiquitous Language** — CONTEXT.md 49–54:
> The single language shared by domain expert, developer, and code to describe the system. Establishing it is the goal of Alignment [...] Source: Eric Evans (Domain-Driven Design), via Matt Pocock.

**grill-with-docs** — CONTEXT.md 56–62:
> A relentless interview session that reads `CONTEXT.md` and the ADRs, challenges fuzzy or conflicting terms [...] Term: Matt Pocock.

**ADR** — CONTEXT.md 64–71:
> Architecture Decision Record [...] The ADRs form a cumulative, append-only history [...] Together with `CONTEXT.md` it is the agent's durable memory across sessions. Term: widely used; adopted via Matt Pocock.

**handoff** — CONTEXT.md 122–127:
> A written document that transfers a task to a fresh session so the current session stays focused. [...] Term: Matt Pocock.

---

## 5. agency-agents: PM Persona Deep Dive

### Does it contain a strategic product-manager persona?

**YES, but not the right fit for Strategic Planning in ai-layer-template.**

Agency-agents contains **three** PM personas:

1. **Senior Project Manager** (`project-manager-senior.md`)
   - **Role**: Convert **site specifications** into actionable task lists
   - **Core responsibility**: Specification analysis → task decomposition → acceptance criteria
   - **Judgment instincts**: Realistic scope (no gold-plating), no "luxury" features not in spec, tasks sized 30–60 min per developer, memory from past projects
   - **What it does NOT do**: discover problems, ask "why" until the need is understood, name Non-Goals, reject additions, hold scope discipline at the problem level
   - **Evidence** (lines 39–45, project-manager-senior.md): "Realistic Scope Setting — Don't add 'luxury' or 'premium' requirements unless explicitly in spec."

2. **Project Shepherd** (`project-management-project-shepherd.md`)
   - **Role**: Cross-functional project orchestration and stakeholder management
   - **Core mission**: timeline management, resource allocation, risk mitigation, stakeholder alignment, communication
   - **Judgment instincts**: Transparent reporting, solution-focused escalation, resource discipline, buffer time, team balance
   - **What it does NOT do**: discover the core problem, iteratively probe requirements, scope from first principles
   - **Evidence** (lines 22–40, project-management-project-shepherd.md): "Orchestrate Complex Cross-Functional Projects," "Align Stakeholders and Manage Communications," "Mitigate Risks."

3. **Studio Producer** (`project-management-studio-producer.md`)
   - **Role**: Production-domain project leadership (film, game, etc.)
   - **Judgment**: Content pipeline, talent, asset scheduling, creative oversight
   - **Not read in detail; domain-specific to creative studios.**

### How it differs from ai-layer-template's Strategic Planning

**Strategic Planning** (ai-layer-template CONTEXT.md 73–81 + SKILL.md):
- **Judgment instincts**:
  1. **Problem first** — "What problem are we solving?" before jumping to solution
  2. **Ask 'why' repeatedly** — Surface the deeper driver behind each stated need
  3. **Name Non-Goals explicitly** — The scope boundary is as important as what's in scope
  4. **Be willing to say no** — Reject additions that don't serve the core problem
  5. **Hold scope discipline** — Shippable beats comprehensive
- **Flow**: Brain dump → clarifying questions → PRD → Issues
- **Input**: Fuzzy problem statement or idea
- **Output**: PRD + GitHub Issues
- **Runs**: **Once per feature** (not per task)
- **Interactive**: Yes — conducted as a relentless dialogue

**Senior Project Manager** (agency-agents):
- **Judgment instincts**:
  1. **Spec analysis** — Read the actual specification
  2. **Avoid gold-plating** — Don't add features not in spec
  3. **Scope realism** — Tasks sized for 30–60 min implementation
  4. **Memory** — Learn from past projects
- **Flow**: Specification → task list
- **Input**: Written specification (assumed to exist)
- **Output**: Task list with acceptance criteria
- **Runs**: Whenever you have a spec to decompose
- **Interactive**: No — mechanical specification parsing

### Does the project's strategic-planning skill derive from agency-agents?

**NO.** The strategic-planning skill encodes **problem discovery** and **scope discipline** (problem-first, ask why, name Non-Goals, say no). Agency-agents has **task decomposition** (spec → tasks) and **stakeholder orchestration** (cross-team alignment). These are adjacent but different phases.

**Evidence of non-derivation**:
- Agency-agents does not appear in ai-layer-template's `.git log`, `.github/`, or CONTEXT.md lineage
- The judgment instincts (problem-first, ask why, Non-Goals) are closer to Eric Evans' Domain-Driven Design and Matt Pocock's teaching than to any Agency-agents persona
- ADR-0001 (ai-layer-template) explains the PM agent fills a **missing human PM role for a solo developer** — it's a necessity fill for a context (non-technical stakeholder), not a borrowing from Agency-agents

---

## 6. Gaps: What's Not There

### harness-engineering-demo
- **Empty**: None identified. Repo is complete and production-grade.
- **Gap**: No example of how to integrate harness-engineering-demo's patterns into a **new** brownfield project (the repo itself is the demo; no template for applying it elsewhere).

### context-engineering-intro
- **Empty**: None identified. Repo is well-populated with templates.
- **Gap**: The `/generate-prp` and `/execute-prp` commands reference `$ARGUMENTS` but the actual command implementations are not shown (they are inlined in the README as pseudo-pseudocode). Unclear how they handle the research and generation phases.

### agency-agents
- **Empty / sparse**:
  - `design/`, `marketing/`, `sales/`, `product/`, `testing/`, `support/`, `academic/`, `finance/`, `spatial-computing/`, `game-development/` directories exist but were not explored. Likely populated (README says 203 agents), but not verified on disk for this research.
- **Gap**: No "Strategic Product Manager" or "Product Discovery" persona — the closest is the Senior Project Manager (tactical task decomposition), not strategic problem-finding.
- **Gap**: No orchestration layer or multi-session driver (like Ralph); Agency-agents is persona-only, not workflow.

---

## 7. Adoption Candidates

Grouped by confidence and fit:

### Strong Fit (Direct use case for downstream projects)

| Artifact | Repo | Rationale | Vocabulary risk |
|----------|------|-----------|-----------------|
| PIV Loop skills (Plan, Implement, Validate) | harness-engineering-demo | **Already borrowed.** Proven on a production app; aligns with Smart Zone / session separation. | None — term is established in CONTEXT.md. |
| Context modules pattern (`.claude/context/{domain}.md`) | harness-engineering-demo | **Already borrowed.** On-demand context keeps Smart Zone lean. | None — pattern is established. |
| PRP template (if diverging from PIV toward one-phase workflow) | context-engineering-intro | Alternative to PIV for projects preferring one comprehensive blueprint phase. Clear if chosen explicitly. | **CONFLICT**: PRPs are Cole's alternative framing; ai-layer-template chose PIV's two-phase split. Adopting PRPs means revising the PIV Loop philosophy. Doable, but a breaking change. |
| Validation checklist (3 levels: syntax, unit tests, integration) | context-engineering-intro | More granular than tdd-gate's binary pass/fail. Could enrich validation strategy in plan templates. | None — orthogonal to PIV. |
| CLAUDE.md template (Python/FastAPI/Pytest specific) | context-engineering-intro | Stack-specific rules for Python projects. Existing template is project-agnostic; context-engineering-intro's is opinionated and detailed. | None — complementary. Downstream projects can adopt selectively. |

### Maybe (Useful but requires decision)

| Artifact | Repo | Rationale | Vocabulary risk |
|----------|------|-----------|-----------------|
| Hooks machinery (PostToolUse lint, Stop gate, PreToolUse security) | harness-engineering-demo | Per-task validation is powerful; currently not in ai-layer-template. Adds automation layer. Could be offered as optional add-on. | None — new capability, no conflict. |
| MCP codebase-search (AST symbol navigation) | harness-engineering-demo | Faster than grep for large codebases. Requires codebase-search binary. Optional tool, not core. | None — optional capability. |
| Ralph loop (headless orchestration) | harness-engineering-demo | Strings multiple sessions together automatically. Powerful for unattended iteration. ADR-0003 explicitly scopes it **out of this repo** (orchestration is a separate layer). | None — architectural scope question, not vocabulary. Decision: keep out of machinery repo, offer as separate orchestrator layer later. |
| Use-case templates (MCP server, Pydantic AI, agent-factory, WISC) | context-engineering-intro | Stack-specific Phase 1 scaffolding. Useful for projects using those stacks. Could be adapted as optional add-ons. | MINOR: Each use-case has its own CLAUDE.md and PRPs; unclear if they conflict with global harness CLAUDE.md. Requires testing. |
| Agency-agents personas as role-switching add-on | agency-agents | If a project wants to invoke "Frontend Developer mode" or "Backend Architect mode" inline, Agency-agents personas are production-ready. Could be offered as optional persona library. | MODERATE: Agency-agents treats personas as **static role switchovers** (you activate one persona for a task). AI-layer-template uses **skills as procedures** (you run `/plan`, not "activate Planner mode"). Mixing both requires clarifying when to use personas vs. skills. |

### Out of Scope

| Artifact | Repo | Rationale | Vocabulary conflict |
|----------|------|-----------|-------------------|
| "PM agent as a sub-agent" pattern | agency-agents | Agency-agents' Senior Project Manager is designed as a standalone agent persona you invoke on specs. ADR-0006 (ai-layer-template) **explicitly rejects** sub-agent PM architecture: "The PM role is a **persona skill** run in the main session, not a sub-agent. Sub-agents can't conduct the interactive brain dump → clarifying-questions dialogue." | **CONFLICT**: ADR-0006 justifies the design choice against sub-agents; adopting Agency-agents' model would reverse that decision. |
| Project Shepherd (cross-functional orchestration) | agency-agents | Designed for teams with multiple disciplines and stakeholders. This harness is for solo developers or small teams. Oversized for the use case. | None — just oversized. |
| Studio operations / creative studio PM | agency-agents | Domain-specific to film/game production. Out of scope unless the project is creative. | None — just domain-specific. |
| Pricing / cost-optimization agents | agency-agents | Business operations / finance domain. Out of scope for engineering harness. | None — just domain-specific. |

---

## Summary of Key Findings

### Concept Borrowing
The `ai-layer-template` explicitly borrows **Smart Zone**, **PIV Loop**, **System Evolution**, and **Strategic Planning** from Cole Medin's harness-engineering-demo and context-engineering-intro repos. CONTEXT.md and CLAUDE.md cite Cole by name; the intellectual lineage is clear and credited.

### Architecture Decisions
- **Global machinery vs. per-project templates** (ADR-0003): This repo is the **single source** of project-agnostic machinery (commands, skills, rules); each downstream repo keeps its own `CONTEXT.md`, `docs/adr/`, and `.agents/`. Synced via symlinks, not copies. This is a deliberate departure from template-per-project.
- **PM role as persona skill, not sub-agent** (ADR-0006): The Strategic Planning PM runs in the main session, not as a Claude Code sub-agent, to conduct the interactive brain dump → clarifying-questions dialogue. This is a deliberate non-adoption of Agency-agents' sub-agent PM pattern.
- **PIV over PRP** (implicit in CLAUDE.md): The harness chose **Plan → Implement (fresh session) → Validate** over Cole's alternative **PRP (one comprehensive phase)**. Both are valid; this repo chose session separation for Smart Zone benefits.

### What's Not Available Upstream
- **A strategic product-manager persona matching the Strategic Planning skill**: Agency-agents has task-decomposition (Senior PM) and orchestration (Project Shepherd), but not the problem-discovery / scope-discipline persona that Strategic Planning models. This was designed in-house.
- **Orchestration machinery**: Ralph (headless multi-session driver) is out of scope per ADR-0003; the orchestrator layer is a future separate project.
- **Hooks system**: Automation via PreToolUse/PostToolUse/Stop hooks is unique to harness-engineering-demo; not extracted as reusable machinery yet.

### Strongest Adoption Candidates
1. **Hooks machinery** (if validation automation is desired by downstream projects)
2. **MCP codebase-search** (if fast symbol lookup is needed)
3. **Validation checklist (3-level)** (to enrich tdd-gate)
4. **Context-engineering-intro's stack-specific CLAUDE.md variants** (for Python/FastAPI projects)

### Not Recommended for Adoption
1. **PRP template / generate-prp / execute-prp** — breaks the PIV session-separation philosophy; explicit in CLAUDE.md rationale
2. **Agency-agents sub-agent PM** — reversed by ADR-0006 after explicit analysis
3. **Agency-agents personas as role-switching** — philosophically different from skills-as-procedures; requires design decision
4. **Ralph loop** — out of scope per ADR-0003; belongs in a separate orchestrator layer

