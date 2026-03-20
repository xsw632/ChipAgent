# Roadmap: ChipAgent

## Milestones

- ✅ **v1.0 MVP** — Phases 1-4 (shipped 2026-03-18)
- 🚧 **v1.1 Refine** — Phases 5-8 (in progress)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases 1-4) — SHIPPED 2026-03-18</summary>

- [x] Phase 1: Plugin Scaffold + Build Foundation (2/2 plans) — completed 2026-03-17
- [x] Phase 2: NL Parsing + Chisel Generation (2/2 plans) — completed 2026-03-17
- [x] Phase 3: Lint, Auto-Fix + Hooks (3/3 plans) — completed 2026-03-17
- [x] Phase 4: Testbench, Simulation + Verification (2/2 plans) — completed 2026-03-18

</details>

### 🚧 v1.1 Refine (Phases 5-8)

**Milestone Goal:** Decompose the monolithic generate pipeline into modular slash commands with per-module workspace isolation and environment detection.

- [ ] **Phase 5: Workspace Foundation** — Per-module workspace directories and script parameterization
- [ ] **Phase 6: Skill Decomposition** — Individual slash commands wrapping scripts and agents
- [x] **Phase 7: Orchestrator + Initialize** — Refactored generate pipeline and environment detection
- [x] **Phase 8: Debug Command** — Failure analysis from simulation artifacts (completed 2026-03-20)

## Phase Details

### Phase 5: Workspace Foundation
**Goal**: Each module's artifacts live in an isolated workspace directory, and all scripts accept workspace paths
**Depends on**: Phase 4 (v1.0 complete)
**Requirements**: WKSP-01, WKSP-02, WKSP-03
**Success Criteria** (what must be TRUE):
  1. Running the pipeline for module "Foo" creates `workspace/Foo/` containing spec, generated Verilog, and sim artifacts in organized subdirectories
  2. `scripts/compile.sh workspace/Foo` outputs Verilog to `workspace/Foo/generated/` instead of the flat `generated/` directory
  3. Running `scripts/compile.sh` with no arguments still works against the original flat directory layout (backward compatible)
  4. `workspace/` and per-module `obj_dir/` are listed in `.gitignore` and produce no untracked files
**Plans**: 2 plans

Plans:
- [x] 05-01-PLAN.md — Workspace-aware compile.sh + gitignore + verification script
- [ ] 05-02-PLAN.md — Workspace-aware lint.sh + simulate.sh + full verification

### Phase 6: Skill Decomposition
**Goal**: Users can invoke individual pipeline stages as standalone slash commands that read/write workspace artifacts
**Depends on**: Phase 5
**Requirements**: SKILL-01, SKILL-02, SKILL-03, SKILL-04, SKILL-05, SPEC-01, SPEC-02
**Success Criteria** (what must be TRUE):
  1. `/chip-agent:compile Foo` compiles module Foo's Chisel source and writes Verilog to `workspace/Foo/generated/`
  2. `/chip-agent:lint Foo` runs Verilator lint-only on the generated Verilog and reports warnings/errors
  3. `/chip-agent:simulate Foo` runs the full Verilator simulation and produces `workspace/Foo/sim/logs/sim_result.log`
  4. `/chip-agent:requirement-parser` writes a structured `spec.json` to `workspace/<Module>/spec.json` containing module name, ports, operations, and test vectors
  5. `/chip-agent:testbench Foo` reads `spec.json` from workspace and generates a C++ testbench (no conversation context dependency)
**Plans**: 2 plans

Plans:
- [ ] 06-01-PLAN.md — Script-wrapper skills (compile, lint, simulate) + test scaffold
- [ ] 06-02-PLAN.md — Agent-backed skills (requirement-parser, testbench) + spec.json communication

### Phase 7: Orchestrator + Initialize
**Goal**: The generate command orchestrates sub-skills end-to-end, and users can detect their local toolchain before first use
**Depends on**: Phase 6
**Requirements**: SKILL-06, INIT-01, INIT-02, INIT-03
**Success Criteria** (what must be TRUE):
  1. `/chip-agent:generate` invokes sub-skills in sequence (requirement-parser, compile, lint, testbench, simulate, report) and produces the same end-to-end result as v1.0
  2. `/chip-agent:initialize` detects installed versions of Java, sbt, Scala, Verilator, Make, and g++ and reports missing tools
  3. Initialize writes `.chipagent/env.json` with tool versions, paths, and capability flags (can_compile, can_lint, can_simulate)
  4. Initialize updates the CLAUDE.md Tech Stack table rows with actually detected local versions
**Plans**: 2 plans

Plans:
- [x] 07-01-PLAN.md — Refactored generate orchestrator skill + PostToolUse hook fix + test scaffold
- [x] 07-02-PLAN.md — Environment detection script + initialize skill + gitignore

### Phase 8: Debug Command
**Goal**: Users can diagnose simulation failures without manually cross-referencing artifacts
**Depends on**: Phase 6
**Requirements**: SKILL-07
**Success Criteria** (what must be TRUE):
  1. `/chip-agent:debug Foo` reads spec.json, Chisel source, and sim_result.log from workspace and produces a failure analysis with targeted fix suggestions
  2. Debug output identifies which test vectors failed and maps failures back to specific spec requirements and Chisel logic
**Plans**: 2 plans

Plans:
- [ ] 08-01-PLAN.md — VCD trace infrastructure (simulate.sh --trace + testbench VCD hooks)
- [ ] 08-02-PLAN.md — Debug command (VCD parser + debug-analyzer agent + debug skill)

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Plugin Scaffold + Build Foundation | v1.0 | 2/2 | Complete | 2026-03-17 |
| 2. NL Parsing + Chisel Generation | v1.0 | 2/2 | Complete | 2026-03-17 |
| 3. Lint, Auto-Fix + Hooks | v1.0 | 3/3 | Complete | 2026-03-17 |
| 4. Testbench, Simulation + Verification | v1.0 | 2/2 | Complete | 2026-03-18 |
| 5. Workspace Foundation | v1.1 | 1/2 | In progress | - |
| 6. Skill Decomposition | 1/2 | In Progress|  | - |
| 7. Orchestrator + Initialize | v1.1 | 2/2 | Complete | 2026-03-20 |
| 8. Debug Command | 2/2 | Complete   | 2026-03-20 | - |

## v1.1 Coverage

| Requirement | Phase | Status |
|-------------|-------|--------|
| WKSP-01 | Phase 5 | In Progress |
| WKSP-02 | Phase 5 | In Progress |
| WKSP-03 | Phase 5 | Complete |
| SKILL-01 | Phase 6 | Pending |
| SKILL-02 | Phase 6 | Pending |
| SKILL-03 | Phase 6 | Pending |
| SKILL-04 | Phase 6 | Pending |
| SKILL-05 | Phase 6 | Pending |
| SKILL-06 | Phase 7 | Complete |
| SKILL-07 | Phase 8 | Pending |
| SPEC-01 | Phase 6 | Pending |
| SPEC-02 | Phase 6 | Pending |
| INIT-01 | Phase 7 | Complete |
| INIT-02 | Phase 7 | Complete |
| INIT-03 | Phase 7 | Complete |

**Mapped: 15/15 v1.1 requirements -- no orphans**

---
*Full v1.0 details archived to `.planning/milestones/v1.0-ROADMAP.md`*
