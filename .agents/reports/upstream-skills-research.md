# Upstream Skills Adoption Research — Cole Medin & Matt Pocock

**Research Date:** 2026-06-09  
**Scope:** Which upstream skills (Cole Medin + Matt Pocock) should be deliberately adopted into the ai-layer-template's two-phase harness?  
**Purpose:** Provide raw material for adoption decision; not a recommendation.

> ⚠️ **Read [§7 Verification corrections](#7-verification-corrections-main-session) first.** A main-session
> pass against the real repos found two material errors below: (1) all four "strong-fit" Matt Pocock
> candidates are **deprecated upstream**, and (2) Cole Medin's `second-brain-skills` is **not actually
> present locally** (the 6-skill list is KB-article hearsay, unverified). Two on-point Cole repos were
> also missed.

---

## 1. Source Map

### Knowledge Base Files Used

| File Path | Author(s) | Relevance |
|-----------|-----------|-----------|
| `/mnt/nfs/dylan_workspace/llm-knowledge-base/raw/20260212 Second Brain Skills Collection Reference.md` | Dylan (reading Cole Medin's repo) | **Primary source** for Cole Medin's 6-skill collection (brand-voice, mcp-client, pptx-gen, remotion, skill-creator, sop-creator) |
| `/mnt/nfs/dylan_workspace/llm-knowledge-base/raw/20260430 FULL Guide to Becoming a Principled Agentic Engineer (Build Anything with AI).md` | Cole Medin video transcript | Foundation for PIV Loop concept; covers Phase 1 (ideation/PRD) + Phase 2 (PIV Loop) + Phase 3 (System Evolution) |
| `/mnt/nfs/dylan_workspace/llm-knowledge-base/raw/20260424 Full Walkthrough Workflow for AI Coding — Matt Pocock.md` | Matt Pocock workshop transcript | Detailed workflow: grill-me → PRD → vertical slices → AFK agent loop; covers smart zone, session separation, Kanban boards |

### Installed Repos

| Repo Path | Author | Upstream Skills Available |
|-----------|--------|---------------------------|
| `/mnt/nfs/dylan_workspace/github-repo/mattpocock-skills/` | Matt Pocock | 25 skills across 5 categories (engineering, productivity, personal, misc, in-progress) |
| `/mnt/nfs/dylan_workspace/github-repo/ai-transformation-workshop/` | Cole Medin | 2 skills: `agent-browser`, `pptx-generator` |
| `/mnt/nfs/dylan_workspace/github-repo/second-brain-starter/` | Cole Medin | 1 skill: `create-second-brain-prd` |

### GitHub Repos Referenced (Not Cloned)

| Repo | Author | Note |
|------|--------|------|
| `coleam00/second-brain-skills` | Cole Medin | **Not found locally.** Source for KB article; contains the 6-skill collection (brand-voice-generator, mcp-client, pptx-generator, remotion, skill-creator, sop-creator) |
| `mattpocock/mattpocock-skills` | Matt Pocock | Symlinked into `~/.claude/skills/` — 25 skills available |

### Key Gaps

- Cole Medin's `second-brain-skills` repo is **referenced in KB but not cloned** locally. The 6 Cole skills are **not installed**.
- Matt Pocock skills are **comprehensive and installed** (25 of ~28 total are symlinked).

---

## 2. Upstream Skill Inventory — Cole Medin + Matt Pocock

### Cole Medin Skills (from second-brain-skills)

**Status:** Not installed locally. Described in KB article. Sourced from repo: `https://github.com/coleam00/second-brain-skills`.

| Skill Name | Author | One-Line Purpose | Installed Locally? | Phase Fit |
|-----------|--------|------------------|-------------------|-----------|
| **brand-voice-generator** | Cole | Interactive wizard to produce brand.json + tone-of-voice.md; single source of truth for brand/voice across projects | ❌ No | Writing-only (not Phase 1/2 for code harness) |
| **mcp-client** | Cole | Unified Python wrapper to connect MCP servers (Zapier, Notion, etc.); on-demand tool loading to reduce context bloat | ❌ No | Cross-cutting (platform/integration) |
| **pptx-generator** | Cole | Generate 16:9 slides + 1:1 LinkedIn carousels using python-pptx; visual-first decision tree for layout choice | ❌ No | Writing-only (content output, not harness) |
| **remotion** (remotion-best-practices) | Cole | Progressive disclosure of Remotion/React video framework; 28 rules for animations, compositions, captions, 3D | ❌ No | Writing-only (domain knowledge for video, not harness) |
| **skill-creator** | Cole | Meta-skill: six-step flow (understand → plan → init → edit → package → validate) for building new skills. Ships three Python scripts (init, validate, package) | ❌ No | **Strong fit for harness infrastructure** — enables skill authorship |
| **sop-creator** | Cole | Generate runbooks/playbooks/SOPs with Definition of Done, action-first wording, decision trees. Kills anti-patterns (vague language, passive voice) | ❌ No | Ops/documentation (useful, not critical to code harness) |

### Matt Pocock Skills — Currently Installed (22 total)

| Skill Name | Category | One-Line Purpose | Installed? | Phase Fit |
|-----------|----------|------------------|-----------|-----------|
| **caveman** | Productivity | Ultra-compressed mode (~75% token savings); drops filler while keeping accuracy | ✅ Yes | Cross-cutting (efficiency) |
| **diagnose** | Engineering | Structured bug diagnosis: reproduce → minimise → hypothesise → instrument → fix → test | ✅ Yes | Phase 2 (validation/fixing within PIV) |
| **edit-article** | Personal | Restructure, improve clarity, tighten prose of articles | ✅ Yes | Writing-only |
| **git-guardrails-claude-code** | Misc | Block dangerous git commands (push --force, reset --hard, clean, branch -D) | ✅ Yes | Cross-cutting (safety) |
| **grill-me** | Productivity | Relentless interview until shared understanding; one-at-a-time questions with recommendations | ✅ Yes | **Phase 1 (Alignment): codebase-free variant** |
| **grill-with-docs** | Engineering | Grill-me that reads CONTEXT.md + ADRs, updates them inline as decisions crystallise | ✅ Yes | **Phase 1 (Alignment): with-docs variant** |
| **handoff** | Productivity | Compact conversation into a handoff document for fresh session pickup | ✅ Yes | **Cross-cutting (session management)** |
| **improve-codebase-architecture** | Engineering | Find refactoring/deepening opportunities using CONTEXT.md + ADRs as domain language | ✅ Yes | Phase 2 (architecture review within PIV) |
| **migrate-to-shoehorn** | Misc | Migrate projects to Shoehorn (web framework) | ✅ Yes | Stack-specific (not harness) |
| **obsidian-vault** | Personal | Obsidian workspace management | ✅ Yes | Writing-only |
| **prototype** | Engineering | Build prototypes to de-risk uncertain design decisions | ✅ Yes | **Phase 1 or Phase 2 (pre-PIV research)** |
| **review** | In-Progress | Code review (implementation TBD) | ✅ Yes | Phase 2 (Validate step of PIV) |
| **scaffold-exercises** | Misc | Generate exercise scaffolds for teaching | ✅ Yes | Teaching-only |
| **setup-pre-commit** | Misc | Configure pre-commit hooks | ✅ Yes | Stack-specific setup |
| **tdd** | Engineering | Test-driven development with red-green-refactor loop | ✅ Yes | **Phase 2 (Implement step of PIV)** |
| **to-issues** | Engineering | Break PRD/plan into vertically-sliced, independently-grabbable issues with dependencies | ✅ Yes | **Phase 1 → Phase 2 bridge** |
| **to-prd** | Engineering | Turn conversation into PRD; publish to issue tracker | ✅ Yes | **Phase 1 (Strategic Planning)** |
| **triage** | Engineering | Interactive QA session; file bugs as issues via state machine | ✅ Yes | **Phase 1 or Phase 2 (bug intake)** |
| **write-a-skill** | Productivity | Author a new skill (workflow scaffolding) | ✅ Yes | Harness infrastructure (meta) |
| **writing-beats** | In-Progress | Writing structure/rhythm guide | ✅ Yes | Writing-only |
| **writing-fragments** | In-Progress | Writing composition patterns | ✅ Yes | Writing-only |
| **writing-shape** | In-Progress | Writing design/structure | ✅ Yes | Writing-only |
| **zoom-out** | Engineering | Extract a high-level summary of a codebase | ✅ Yes | Phase 2 (Plan/Explore step of PIV) |

### Matt Pocock Skills — NOT Installed (5 candidates)

| Skill Name | Category | One-Line Purpose | Installed? | Phase Fit | Rationale |
|-----------|----------|------------------|-----------|-----------|-----------|
| **design-an-interface** | Engineering | "Design It Twice" — generate multiple radically different module designs in parallel using sub-agents; compare shapes | ❌ No | **Phase 1 or Phase 2 pre-research** | Useful for exploring API/module design before lock-in; could feed into Plan step |
| **qa** | Engineering | Interactive QA session where user reports bugs conversationally; agent files issues w/ domain language | ❌ No | **Phase 1 (bug intake)** or Phase 2 (validation) | Overlaps with `triage`; differs in "conversational bug report" vs "state machine." Value: more natural for users unfamiliar with issue templates |
| **request-refactor-plan** | Engineering | Plan a refactor via interview; break into tiny commits; file as issue | ❌ No | **Phase 2 (pre-PIV planning)** or Phase 1 (special case) | Fills a gap: refactors aren't feature work (Phase 1) but need their own plan. Could be Phase 2 sub-workflow. |
| **teach** | Personal | Stateful teaching of a new skill/concept within workspace | ❌ No | Writing-only (educational, not harness) | Meta-skill for running courses; not relevant to code harness |
| **ubiquitous-language** | Engineering | Extract DDD-style glossary from conversation; flag ambiguities; propose canonical terms; save to UBIQUITOUS_LANGUAGE.md | ❌ No | **Phase 1 (Alignment)** | Direct-hit for Ubiquitous Language goal; complementary to `grill-with-docs`. Could be Phase 1's term-capture mechanism. |

---

## 3. Two-Phase Harness Context

The ai-layer-template project organizes work in two phases:

### Phase 1 — Project Setup (project-level, once per feature)

**Goal:** Turn a brain dump into a PRD + independently-grabbable Issues.  
**Steps:** Brain dump → Alignment (grill-with-docs) → Strategic Planning (PM persona) → PRD → Issues.  
**Cadence:** Once per feature; Alignment re-entered if new terms surface.  
**Existing infrastructure:**
- Skill `strategic-planning` — PM persona for brain dump → clarifying questions → PRD → Issues
- Upstream skills `to-prd`, `to-issues` — PRD creation and decomposition
- Upstream skills `grill-me`, `grill-with-docs` — Alignment session

### Phase 2 — Development (per-ticket, ongoing)

**Goal:** Turn one Issue into working software via the PIV Loop, with System Evolution for bugs.  
**Inner loop (PIV):** Plan → Implement → Validate (three fresh sessions).  
**Outer loop (System Evolution):** When bug surfaces → improve AI Layer (CLAUDE.md, commands, skills, templates).  
**Existing infrastructure:**
- Skill `piv-loop` — documents the three-phase flow
- Commands `/plan`, `/implement`, `/retroactive` — execute each phase
- Skill `tdd-gate` — test-first verification during Implement
- Skill `system-evolution` — retroactive session mechanism

---

## 4. Adoption Candidates

### Category A: Strong Fit, Not Yet Adopted

Skills that would **fill a real gap in Phase 1 or Phase 2** and align with the harness's intent.

#### Phase 1 — Alignment & Strategic Planning

| Skill | From | Fit | Rationale | Risk / Notes |
|-------|------|-----|-----------|-------------|
| **ubiquitous-language** | Matt Pocock | ⭐⭐⭐⭐⭐ | Direct-hit for Ubiquitous Language goal in Alignment. Extracts glossary from conversation, flags ambiguities, saves to `UBIQUITOUS_LANGUAGE.md`. Complements `grill-with-docs`. | `disable-model-invocation: true` — cannot be auto-triggered. Requires explicit `/ubiquitous-language` invocation. Could cause confusion if used instead of `grill-with-docs`. **Mitigation:** Position as "post-grill glossary consolidation step." |
| **skill-creator** | Cole Medin | ⭐⭐⭐⭐ | Enables authorship of new harness machinery. Six-step flow (understand → plan → init → edit → package → validate) + three Python scripts. Critical for harness evolution. | Requires Python + PyYAML. Not a Phase 1/2 skill per se, but infrastructure for building them. **Mitigation:** Position as "harness extension tool," not a phase skill. |

#### Phase 2 — PIV Loop (all steps) + System Evolution

| Skill | From | Fit | Rationale | Risk / Notes |
|-------|------|-----|-----------|-------------|
| **design-an-interface** | Matt Pocock | ⭐⭐⭐ | Useful for Plan step: de-risk API/module design choices before implementation. "Design It Twice" principle. Generates multiple options in parallel using sub-agents. | Not a blocker; many codebases skip this. **Optional add:** pair with `/plan` when design is uncertain. No vocabulary conflict. |
| **request-refactor-plan** | Matt Pocock | ⭐⭐⭐ | Fills gap: refactors aren't feature work (Phase 1) but need their own planning. Could be triggered *before* a refactor ticket enters the PIV Loop. | Moderate complexity. Assumes `request-refactor-plan` → local issue file → Phase 2 pickup. **Mitigation:** Position as "pre-PIV planning for refactors." Requires workflow documentation. |

#### Cross-Cutting (both phases)

| Skill | From | Fit | Rationale | Risk / Notes |
|-------|------|-----|-----------|-------------|
| **mcp-client** | Cole Medin | ⭐⭐⭐ | Enables unified MCP server integration (Zapier, Notion, etc.). Solves context bloat by on-demand tool loading. **Adoption cost:** 30 min setup (copy config, fill API key). | Optional; only needed if project uses external MCP servers. **Setup path:** clear, documented. No conflict with existing machinery. |

### Category B: Already Adopted / Core Infrastructure

These are already symlinked / integrated and form the backbone.

| Skill | Phase | Status | Note |
|-------|-------|--------|------|
| `grill-me` / `grill-with-docs` | Phase 1 (Alignment) | ✅ Installed | Core to Alignment; `grill-with-docs` reads/updates CONTEXT.md + ADRs inline |
| `to-prd` | Phase 1 (Strategic Planning) | ✅ Installed | Converts brain dump + clarifications into PRD markdown |
| `to-issues` | Phase 1 → Phase 2 bridge | ✅ Installed | Decomposes PRD into vertically-sliced, independently-grabbable Issues |
| `piv-loop` / `/plan` / `/implement` / `/retroactive` | Phase 2 (PIV + System Evolution) | ✅ Installed | Core per-ticket loop; three fresh sessions |
| `tdd-gate` / `tdd` | Phase 2 (Implement) | ✅ Installed | Test-first verification during code writing |
| `system-evolution` / `retroactive` | Phase 2 (outer loop) | ✅ Installed | Retroactive session for improving AI Layer after bugs |
| `handoff` | Both | ✅ Installed | Session-to-session transfer mechanism |
| `zoom-out` | Phase 2 (Plan/Explore) | ✅ Installed | High-level codebase summary for Plan step exploration |
| `diagnose` | Phase 2 (Validate/regression-test) | ✅ Installed | Structured bug diagnosis when issues surface |

### Category C: Out of Scope (Writing-Only, Stack-Specific, or Educational)

These are **intentionally excluded** from the two-phase harness; they solve different problems.

| Skill | From | Category | Rationale |
|-------|------|----------|-----------|
| **brand-voice-generator**, **pptx-generator**, **remotion** | Cole | Writing/Content Design | Output-generation skills, not harness machinery. Useful for content projects; not relevant to coding harness. |
| **edit-article**, **writing-beats**, **writing-fragments**, **writing-shape** | Matt | Writing-Only | Prose composition, not code. Valid skills; different domain. |
| **obsidian-vault** | Matt | Personal Knowledge Mgmt | Obsidian-specific; not part of coding harness. |
| **teach** | Matt | Educational Meta-Skill | Stateful course delivery; not harness machinery. |
| **migrate-to-shoehorn**, **setup-pre-commit**, **scaffold-exercises** | Matt | Stack/Project-Specific | Useful, but not universal harness machinery. |
| **sop-creator** | Cole | Ops/Documentation | Generates runbooks/SOPs; useful for teams, not critical to code harness. |

---

## 5. Vocabulary Conflict Risk Assessment

**Rule:** Upstream skills must not introduce conflicting terminology with the harness's Ubiquitous Language (defined in CONTEXT.md).

| Term | Harness Definition | Upstream Skills Using It | Risk | Mitigation |
|------|-------------------|--------------------------|------|------------|
| **Issue** | One independently-grabbable unit of work; GitHub Issue or `.agents/tickets/{NN}.md` (pre-GitHub) | `to-issues`, `qa`, `triage` | None — Matt Pocock skills use "issue" consistently with GitHub Issues | Ensure docs clarify the `.agents/tickets/` ↔ GitHub Issue transition |
| **PRD** | Document output of Strategic Planning; superseded as intent changes | `to-prd`, `design-an-interface` | None — both use "PRD" as the destination artifact | ✅ Clear |
| **Plan** | Document output of Plan step of PIV Loop (file: `.agents/plans/{name}.plan.md`) | `request-refactor-plan`, `/plan` command | **Potential confusion:** `request-refactor-plan` *produces* a plan file but *outside* the PIV context. | **Mitigation:** Rename in documentation to "pre-PIV refactor plan" or position as "refactor issue file creation" step, separate from Phase 2's `/plan`. Or align naming: `.agents/refactors/{name}.refactor.md`. |
| **Phase** | Internal structure within a PRD; **not** a glossary term | Strategic Planning, PIV | None — upstream skills don't use "phase" for harness phases | ✅ Clear |
| **Ticket** | *Deprecated term* (transitional during GitHub cutover); Issues are the canonical name | N/A | N/A | No conflict — `ticket` is internally legacy; don't use in new skills |
| **Session** | A contiguous interaction with the agent; ends when context cleared | `/plan`, `/implement`, `/retroactive`, all Phase 1 skills | None — Matt Pocock uses "session" the same way | ✅ Clear |
| **Grill** | `grill-me` (codebase-free) vs `grill-with-docs` (with CONTEXT.md + ADRs) | Matt Pocock coined term; both skills present | None — terminology is tight and distinct | ✅ Clear |
| **Skill** vs **Command** | Skill = interactive dialogue (Phase 1). Command = structured procedure with phases (Phase 2) | ADR-0005 codifies this split | **None if adoption respects the split** | Keep Phase 1 new machinery as skills; Phase 2 as commands. `skill-creator` + `write-a-skill` support this. |

**Glossary conflict forbids:**  
- Using "issue" / "ticket" / "story" loosely (done; all use consistent)
- Confusing "phase" within PRD with Phase 1 / Phase 2 harness phases (risk: low if documented)
- Conflating "refactor plan" (from `request-refactor-plan`) with "implementation plan" (PIV Plan step) — **medium risk if not clarified**

---

## 6. Open Questions for the Owner

1. **Cole Medin skills adoption priority:**
   - Is `skill-creator` important enough to install? (Enables harness extension; adds Python dependency.)
   - Is `mcp-client` relevant to your immediate roadmap? (Platform integration; optional.)
   - Are the content-generation skills (brand-voice, pptx-gen, sop-creator) out of scope or worth evaluating for future projects?

2. **Matt Pocock gap-fillers:**
   - Should `ubiquitous-language` be a formal Alignment step, or is `grill-with-docs` sufficient for term capture?
   - Is `design-an-interface` worth offering as a pre-Plan research tool, or too specialized?
   - Should `request-refactor-plan` exist as a Phase 2 sub-workflow, or should refactors just follow the standard `/plan` → `/implement` flow?

3. **Harness extensibility:**
   - Do you plan to author custom skills for this project (beyond the upstream set)? If yes, `skill-creator` should be adopted.
   - Should the harness support MCP servers at all? If yes, prioritize `mcp-client` setup.

4. **Vocabulary hardening:**
   - The term "refactor" currently has no entry in CONTEXT.md. Should `request-refactor-plan` be adopted, adding one is necessary.
   - Should "Ubiquitous Language" get a formal skill (`ubiquitous-language`), or is documentation in CONTEXT.md sufficient?

5. **Writing-only skills boundary:**
   - Are there projects downstream of this harness that *will* use Cole's content-gen skills (brand-voice, pptx-gen)? Should the harness document their integration path?

---

## Appendix: Skill Source Reference

### Cole Medin — second-brain-skills Repo
**GitHub:** `https://github.com/coleam00/second-brain-skills`  
**KB Reference:** `/mnt/nfs/dylan_workspace/llm-knowledge-base/raw/20260212 Second Brain Skills Collection Reference.md`  
**Skills:**
1. brand-voice-generator
2. mcp-client
3. pptx-generator
4. remotion (remotion-best-practices)
5. skill-creator
6. sop-creator

**Local Status:** Not cloned; KB article is the source.

### Matt Pocock — mattpocock-skills Repo
**GitHub:** `https://github.com/mattpocock/mattpocock-skills`  
**Local Clone:** `/mnt/nfs/dylan_workspace/github-repo/mattpocock-skills/`  
**Symlinked into:** `~/.claude/skills/` (25 of ~28 skills)  
**KB Reference:** 
- `/mnt/nfs/dylan_workspace/llm-knowledge-base/raw/20260424 Full Walkthrough Workflow for AI Coding — Matt Pocock.md` (workshop, covers grill-me, to-prd, to-issues, Ralph loop/AFK agent)
- Implicit in project design (grill-with-docs, handoff, triage, ubiquitous-language, etc.)

### Cole Medin — ai-transformation-workshop
**GitHub:** Implied from KB; repo exists locally at `/mnt/nfs/dylan_workspace/github-repo/ai-transformation-workshop/`  
**Local Skills:** `agent-browser`, `pptx-generator` (duped from second-brain-skills)  
**KB Reference:** Indirectly (Cole's workshops and tutorials)

---

## Summary Table: Upstream Skills Landscape

| Source | Total Identified | Installed Locally | Strong Adoption Candidates | Already Core to Harness |
|--------|-----------------|-------------------|---------------------------|------------------------|
| **Cole Medin (second-brain-skills)** | 6 | 0 | 2 (skill-creator, mcp-client) | — |
| **Matt Pocock (mattpocock-skills)** | ~28 | 25 | 3–4 (ubiquitous-language, design-an-interface, request-refactor-plan, qa) | 18 (grill-me/with-docs, to-prd, to-issues, tdd, diagnose, etc.) |
| **Project-specific** | 4 | 4 | — | 4 (piv-loop, strategic-planning, system-evolution, tdd-gate) |
| **TOTAL** | ~38 | 29 | **5–6 candidates** | **22–23 core** |

---

## 7. Verification corrections (main session)

Main-session pass on 2026-06-09 against the actual repos in `/mnt/nfs/dylan_workspace/github-repo/`
and `~/.claude/skills/`. Two material errors and two gaps in the above:

1. **The four "strong-fit" Matt Pocock candidates are DEPRECATED upstream.** `design-an-interface`,
   `qa`, `request-refactor-plan`, and `ubiquitous-language` all live under
   `mattpocock-skills/skills/deprecated/` — Matt removed them from active use. Notably
   `ubiquitous-language` (rated ⭐⭐⭐⭐⭐ above) was deprecated in favour of `grill-with-docs`, which
   this project **already** uses for Alignment. Treat these as "deliberately retired upstream," not
   as gaps to fill — adopting a deprecated skill inherits abandonware.

2. **Cole Medin's `second-brain-skills` is NOT present locally.** `github-repo/second-brain-skills/`
   exists but is **empty** (no remote, no `SKILL.md`). The entire 6-skill Cole list
   (`skill-creator`, `mcp-client`, `brand-voice-generator`, `pptx-generator`, `remotion`,
   `sop-creator`) is **KB-article hearsay only**, never verified against real code. `skill-creator`
   and `mcp-client` recommendations rest on an unread source.

3. **Two on-point Cole Medin repos were missed** (both `coleam00`, both relevant to *this* harness):
   - `github-repo/context-engineering-intro/` — Cole's context-engineering method (likely source for
     the Plan/Explore + sub-agent-research patterns).
   - `github-repo/harness-engineering-demo/` — Cole's "Harness Engineering" demo; directly names the
     concept this repo's CONTEXT.md borrows. **Most likely the richest unexamined source.**
   Also present: `agency-agents` (msitarzewski — plausible origin of the `strategic-planning` PM
   persona) and `Archon` (empty locally; Cole's orchestrator, the "control plane" ADR-0003 defers).

4. **Net effect on adoption candidates:** after correction there is **no verified, non-deprecated,
   strong-fit candidate** from the existing inventory. The real next move is to mine
   `harness-engineering-demo` and `context-engineering-intro` (Cole, verifiable on disk) before
   deciding, rather than adopting deprecated Matt skills or unread Cole skills.

