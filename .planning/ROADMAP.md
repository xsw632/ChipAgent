# Roadmap: ChipAgent

## Milestones

- v1.0 MVP -- Phases 1-4 (shipped 2020-03-18)
- v1.1 Refine -- Phases 5-8 (shipped 2020-03-23)
- v1.1.2 RTL-to-GDS -- Phases 9-12 (shipped 2020-04-01)
- v1.1.5 sky130hd MCP Backend -- Phases 13-15 (shipped 2020-04-02)
- v1.2.0 Smart Retry & QoR Optimization -- Phases 16-17 (shipped 2020-04-02)
- v1.3 Chipyard Integration & Full-Flow Automation -- Phases 18-21 (in progress)

## Phases

<details>
<summary>v1.0 MVP (Phases 1-4) -- SHIPPED 2020-03-18</summary>

- [x] Phase 1: Plugin Scaffold + Build Foundation (2/2 plans) -- completed 2020-03-17
- [x] Phase 2: NL Parsing + Chisel Generation (2/2 plans) -- completed 2020-03-17
- [x] Phase 3: Lint, Auto-Fix + Hooks (3/3 plans) -- completed 2020-03-17
- [x] Phase 4: Testbench, Simulation + Verification (2/2 plans) -- completed 2020-03-18

</details>

<details>
<summary>v1.1 Refine (Phases 5-8) -- SHIPPED 2020-03-23</summary>

- [x] Phase 5: Workspace Foundation (2/2 plans) -- completed 2020-03-20
- [x] Phase 6: Skill Decomposition (2/2 plans) -- completed 2020-03-20
- [x] Phase 7: Orchestrator + Initialize (2/2 plans) -- completed 2020-03-20
- [x] Phase 8: Debug Command (2/2 plans) -- completed 2020-03-20

</details>

<details>
<summary>v1.1.2 RTL-to-GDS (Phases 9-12) -- SHIPPED 2020-04-01</summary>

- [x] Phase 9: Environment + SDC Foundation (2/2 plans) -- completed 2020-03-31
- [x] Phase 10: Yosys Synthesis (1/1 plan) -- completed 2020-03-31
- [x] Phase 11: OpenROAD PnR + GDS Export (1/1 plan) -- completed 2020-04-01
- [x] Phase 12: PnR Command + Report Integration (1/1 plan) -- completed 2020-04-01

</details>

<details>
<summary>v1.1.5 sky130hd MCP Backend (Phases 13-15) -- SHIPPED 2020-04-02</summary>

- [x] Phase 13: MCP Server + Environment Foundation (2/2 plans) -- completed 2020-04-02
- [x] Phase 14: Config Generation + ORFS Stage Execution (2/2 plans) -- completed 2020-04-02
- [x] Phase 15: PnR Skill Orchestration + PPA Reporting (2/2 plans) -- completed 2020-04-02

</details>

<details>
<summary>v1.2.0 Smart Retry & QoR Optimization (Phases 16-17) -- SHIPPED 2020-04-02</summary>

- [x] Phase 16: Diagnosis & Retry Infrastructure (2/2 plans) -- completed 2020-04-02
- [x] Phase 17: Retry Orchestration & QoR Optimization (2/2 plans) -- completed 2020-04-02

</details>

### v1.3 Chipyard Integration & Full-Flow Automation (In Progress)

**Milestone Goal:** Integrate Chipyard RTL generation with SRAM analysis and ORFS PnR for tinyRocket processor end-to-end flow.

- [x] **Phase 18: Chipyard Environment Detection** - Extend initialize skill and detect-env.sh to discover Chipyard installation and RISCV toolchain (completed 2020-04-14)
- [ ] **Phase 19: Chipyard RTL Generation Command** - Implement `/chip-agent:chipyard` skill for Verilog generation from Chipyard configs

## Phase Details

### Phase 18: Chipyard Environment Detection
**Goal**: Users can discover Chipyard and RISCV toolchain availability through the existing initialize command
**Depends on**: Phase 17 (v1.2.0 shipped)
**Requirements**: ENV-01, ENV-02, ENV-03
**Success Criteria** (what must be TRUE):
  1. Running `/chip-agent:initialize` in a project with Chipyard installed writes `can_chipyard: true` and the Chipyard path to `.chipagent/env.json`
  2. Running `/chip-agent:initialize` without Chipyard installed writes `can_chipyard: false` without errors
  3. `detect-env.sh` script detects and reports Chipyard directory and RISCV toolchain path when present
  4. Environment validation checks for `build.sbt` existence and RISCV toolchain binaries in the detected Chipyard path
**Plans**: 2 plans

Plans:
- [x] 18-01-PLAN.md -- Extend detect-env.sh with Chipyard/RISCV detection, can_chipyard capability, and JSON/stdout output
- [x] 18-02-PLAN.md -- Extend initialize SKILL.md with Chipyard/RISCV status display and install guidance

### Phase 19: Chipyard RTL Generation Command
**Goal**: Users can generate Verilog RTL from any Chipyard config via a single slash command, with output ready for PnR
**Depends on**: Phase 18
**Requirements**: CYR-01, CYR-02, CYR-03, CYR-04, CYR-05, CYR-06
**Success Criteria** (what must be TRUE):
  1. Running `/chip-agent:chipyard tinyrocket` auto-maps the shorthand to `TinyRocketConfig` and generates Verilog RTL via Chipyard's make flow
  2. The skill validates the environment (sbt, firtool, Java, RISCV) and config class existence before starting generation, with clear error messages for missing prerequisites
  3. Generated Verilog files are concatenated into a single `.v` file saved to `MyDesign/<Config>/workspace/generated/<Config>.v` for ORFS compatibility
  4. User sees a generation summary showing config name, output path, file count, top module, and mems.conf contents
  5. Generation handles 10-30 minute timeout gracefully with progress feedback
**Plans**: TBD
**UI hint**: yes

Plans:
- [ ] 19-01: TBD
- [ ] 19-02: TBD
