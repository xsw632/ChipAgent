# Phase 19: Unified Chipyard Flow - Context

**Gathered:** 2026-04-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement `/chip-agent:chipyard <config>` as the single user-facing entrypoint for Chipyard-based RTL generation. This phase should reuse the existing Chipyard RTL and SRAM analysis skills internally, generate Chipyard RTL for a requested config such as `tinyrocket`, run SRAM mapping as part of the same flow, and stage the resulting artifacts into `MyDesign/<Config>/workspace/` so the existing `/chip-agent:pnr <Config>` flow can run afterward.

</domain>

<decisions>
## Implementation Decisions

### User Entry and Skill Reuse
- **D-01:** The only user-facing command for this flow is `/chip-agent:chipyard <config>`; users should not need to invoke `chipyard-rtl` separately.
- **D-02:** Reuse `skills/chipyard-rtl/SKILL.md` internally for Chipyard elaboration and artifact discovery instead of designing a new generation flow from scratch.
- **D-03:** Reuse `skills/sram-mapping/SKILL.md` internally as a pipeline step within `/chip-agent:chipyard`, not as the primary command users run for this roadmap flow.
- **D-04:** Keep `chipyard-rtl` and `sram-mapping` as implementation building blocks, while `/chip-agent:chipyard` becomes the orchestrating skill that composes them.

### Flow Shape and Handoff
- **D-05:** `/chip-agent:chipyard` runs a single integrated pipeline: resolve config → validate environment → generate RTL → run SRAM mapping → copy/stage outputs into `MyDesign/<Config>/workspace/`.
- **D-06:** The command must auto-map shorthand user input like `tinyrocket` to `TinyRocketConfig` before generation.
- **D-07:** The workspace handoff is mandatory, not optional: generated RTL and related Chipyard outputs are moved or copied into `MyDesign/<Config>/workspace/` as part of successful completion.
- **D-08:** The staged workspace must be ready for the existing `/chip-agent:pnr <Config>` flow without requiring the user to manually reorganize files.

### SRAM Mapping Integration
- **D-09:** SRAM mapping is an automatic step in `/chip-agent:chipyard`, immediately after RTL generation succeeds.
- **D-10:** The flow should analyze the generated Chipyard RTL for SRAM-related structures and persist structured mapping output for downstream use.
- **D-11:** Mapping outputs should live alongside other staged Chipyard artifacts in `MyDesign/<Config>/workspace/` so `/chip-agent:pnr` and verification can reference them consistently.
- **D-12:** Phase 19 fully owns the integrated SRAM mapping/reporting contract inside the same `/chip-agent:chipyard` skill; there is no second roadmap phase for SRAM mapping.

### Output Contract and UX
- **D-13:** `/chip-agent:chipyard` must show a generation summary that includes config name, generated output path, file count, top module, and `mems.conf` contents.
- **D-14:** The command should also report that SRAM mapping ran and indicate where staged artifacts were written in `MyDesign/<Config>/workspace/`.
- **D-15:** Completion messaging should clearly hand the user to the next backend step: run `/chip-agent:pnr <Config>`.

### Claude's Discretion
- Exact internal factoring between the orchestrating `/chip-agent:chipyard` skill and the reused helper skills/scripts.
- Whether staging uses copy vs move for specific Chipyard collateral, as long as Chipyard source outputs remain discoverable and MyDesign workspace becomes the canonical downstream location.
- Exact formatting of progress updates during the long-running Chipyard generation step.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone and requirements
- `.planning/ROADMAP.md` — Phase 19 unified scope, success criteria, and milestone sequencing.
- `.planning/REQUIREMENTS.md` — CYR/SRM/E2E requirements now consolidated into Phase 19.
- `.planning/PROJECT.md` — v1.3 milestone goal, Chipyard→PnR flow, and workspace handoff intent.

### Existing implementation assets
- `skills/chipyard-rtl/SKILL.md` — existing Chipyard RTL generation flow to be reused internally.
- `skills/sram-mapping/SKILL.md` — existing SRAM mapping flow to be reused internally inside `/chip-agent:chipyard`.
- `skills/pnr/SKILL.md` — downstream workspace and input contract that staged Chipyard outputs must satisfy.
- `skills/initialize/SKILL.md` — environment detection behavior that `/chip-agent:chipyard` should rely on or align with.
- `scripts/detect-env.sh` — current env.json schema and `can_chipyard` capability source.
- `.chipagent/env.json` — current machine-readable environment contract consumed by Chipyard-related flows.

### Prior phase context
- `.planning/phases/18-chipyard-environment-detection/18-CONTEXT.md` — locked decisions for Chipyard/RISCV detection and `can_chipyard` capability semantics.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `skills/chipyard-rtl/SKILL.md`: already defines config validation, environment setup, `make verilog`, output discovery, summary formatting, and optional workspace copy behavior.
- `skills/sram-mapping/SKILL.md`: already defines memory identification, hierarchy tracing, macro enumeration, mapping strategy, and `sram_mapping.json` output.
- `skills/pnr/SKILL.md`: already consumes `MyDesign/<Module>/workspace/generated/<Module>.v`, so Chipyard staging should align to that contract.
- `scripts/detect-env.sh` + `.chipagent/env.json`: already expose `chipyard.path`, RISCV toolchain path, and `can_chipyard` capability from Phase 18.
- `skills/generate/SKILL.md` and `skills/workflow/SKILL.md`: show the established ChipAgent pattern of a single user-facing orchestrator writing into `MyDesign/<Module>/workspace/`.

### Established Patterns
- ChipAgent favors one top-level user command per workflow, with internal orchestration of sub-steps and workspace materialization under `MyDesign/<Module>/workspace/`.
- Environment capability checks are centralized in `.chipagent/env.json` rather than rediscovered ad hoc by each flow.
- Existing downstream tooling expects canonical generated artifacts under `workspace/generated/` and related metadata beside them.
- Long-running flows report progress in staged pipeline steps, then end with a concise artifact summary.

### Integration Points
- New `/chip-agent:chipyard` skill should integrate with Phase 18 env detection by consuming `.chipagent/env.json` and honoring `chipyard.path` / `can_chipyard`.
- The orchestrator should call or absorb the logic from `skills/chipyard-rtl/SKILL.md` and `skills/sram-mapping/SKILL.md`.
- Staged outputs must land in `MyDesign/<Config>/workspace/generated/` and related workspace files so `skills/pnr/SKILL.md` can operate on them.
- Phase 20 should extend this same orchestrated skill path rather than splitting the user journey across multiple top-level commands.

</code_context>

<specifics>
## Specific Ideas

- The intended roadmap UX is `/chip-agent:chipyard tinyrocket` → internal RTL generation + SRAM analysis + artifact staging → `/chip-agent:pnr TinyRocketConfig`.
- The user explicitly wants Chipyard-side relevant content moved into `MyDesign/` before PnR.
- `sram-mapping` should remain reusable, but in the roadmap flow it is a hidden/internal stage rather than a separate required user action.

</specifics>

<deferred>
## Deferred Ideas

- Making `chipyard-rtl` a separate recommended end-user command for the main roadmap flow.
- Introducing a second top-level SRAM-mapping-centric UX for v1.3.
- Any changes to `/chip-agent:pnr` behavior beyond what is necessary to consume staged Chipyard outputs.

</deferred>

---
*Phase: 19-chipyard-rtl-generation-command*
*Context gathered: 2026-04-14*