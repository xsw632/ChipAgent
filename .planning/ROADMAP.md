# Roadmap: ChipAgent

## Milestones

- ✅ **v1.0 MVP** -- Phases 1-4 (shipped 2026-03-18)
- ✅ **v1.1 Refine** -- Phases 5-8 (shipped 2026-03-23)
- ✅ **v1.1.2 RTL-to-GDS** -- Phases 9-12 (shipped 2026-04-01)
- **v1.1.5 sky130hd MCP Backend** -- Phases 13-15 (in progress)

## Phases

<details>
<summary>v1.0 MVP (Phases 1-4) -- SHIPPED 2026-03-18</summary>

- [x] Phase 1: Plugin Scaffold + Build Foundation (2/2 plans) -- completed 2026-03-17
- [x] Phase 2: NL Parsing + Chisel Generation (2/2 plans) -- completed 2026-03-17
- [x] Phase 3: Lint, Auto-Fix + Hooks (3/3 plans) -- completed 2026-03-17
- [x] Phase 4: Testbench, Simulation + Verification (2/2 plans) -- completed 2026-03-18

</details>

<details>
<summary>v1.1 Refine (Phases 5-8) -- SHIPPED 2026-03-23</summary>

- [x] Phase 5: Workspace Foundation (2/2 plans) -- completed 2026-03-20
- [x] Phase 6: Skill Decomposition (2/2 plans) -- completed 2026-03-20
- [x] Phase 7: Orchestrator + Initialize (2/2 plans) -- completed 2026-03-20
- [x] Phase 8: Debug Command (2/2 plans) -- completed 2026-03-20

</details>

<details>
<summary>v1.1.2 RTL-to-GDS (Phases 9-12) -- SHIPPED 2026-04-01</summary>

- [x] Phase 9: Environment + SDC Foundation (2/2 plans) -- completed 2026-03-31
- [x] Phase 10: Yosys Synthesis (1/1 plan) -- completed 2026-03-31
- [x] Phase 11: OpenROAD PnR + GDS Export (1/1 plan) -- completed 2026-04-01
- [x] Phase 12: PnR Command + Report Integration (1/1 plan) -- completed 2026-04-01

</details>

### v1.1.5 sky130hd MCP Backend (In Progress)

**Milestone Goal:** Replace standalone nangate45 Tcl scripts with MCP Server-driven ORFS make flow on sky130hd, reaching task2 advanced requirements.

- [x] **Phase 13: MCP Server + Environment Foundation** - MCP scaffold with environment detection, sky130hd PDK validation, and nangate45 cleanup (completed 2026-04-02)
- [ ] **Phase 14: Config Generation + ORFS Stage Execution** - Config.mk/SDC generation and ORFS make target execution with metric extraction
- [ ] **Phase 15: PnR Skill Orchestration + PPA Reporting** - /chip-agent:pnr rewrite orchestrating full 6-stage flow with formatted PPA summary

## Phase Details

### Phase 13: MCP Server + Environment Foundation
**Goal**: Users have a working MCP server registered with Claude Code that validates sky130hd/ORFS environment readiness
**Depends on**: Phase 12 (v1.1.2 complete)
**Requirements**: MCP-01, MCP-02, ENV-01, ENV-02, ENV-03, CLN-01, CLN-02
**Success Criteria** (what must be TRUE):
  1. MCP server starts via stdio transport and Claude Code discovers its tools through .mcp.json registration
  2. `check_environment` tool returns structured JSON reporting ORFS path, sky130hd PDK presence, and Docker availability
  3. `/chip-agent:initialize` detects sky130hd PDK (not nangate45) and writes correct paths to env.json with backend_mode field
  4. Old nangate45 scripts (synth.tcl, pnr.tcl, validate-pdk.sh, def2gds.py) are removed and CLAUDE.md reflects the new sky130hd + MCP architecture
**Plans**: 2 plans

Plans:
- [ ] 13-01-PLAN.md — MCP server scaffold + check_environment tool
- [ ] 13-02-PLAN.md — Environment detection rewrite + nangate45 cleanup

### Phase 14: Config Generation + ORFS Stage Execution
**Goal**: Users can generate ORFS-ready config files and execute individual ORFS make stages with metric extraction
**Depends on**: Phase 13
**Requirements**: MCP-03, CFG-01, CFG-02, MCP-04, MCP-05
**Success Criteria** (what must be TRUE):
  1. `generate_config` tool produces a valid config.mk with correct ORFS variables (DESIGN_NAME, PLATFORM=sky130hd, VERILOG_FILES, SDC_FILE, CORE_UTILIZATION) and a constraint.sdc with 10ns default clock for sequential modules or virtual clock for combinational
  2. `run_stage` tool executes any of the 6 ORFS make targets (synth/floorplan/place/cts/route/finish) and returns structured output with success/failure status and log path
  3. `get_report` tool extracts stage-specific metrics (cell count, design area, WNS, TNS, DRC violations) from ORFS output directories and returns them as structured JSON
**Plans**: 2 plans

Plans:
- [ ] 14-01: TBD
- [ ] 14-02: TBD

### Phase 15: PnR Skill Orchestration + PPA Reporting
**Goal**: Users invoke `/chip-agent:pnr` and get a complete ORFS-driven backend flow with formatted PPA summary report
**Depends on**: Phase 14
**Requirements**: FLOW-01, FLOW-02, FLOW-03, RPT-01
**Success Criteria** (what must be TRUE):
  1. `/chip-agent:pnr <ModuleName>` orchestrates via MCP tools (not direct bash scripts) through all 6 ORFS stages sequentially
  2. Each stage produces extracted metrics (cell count, area, WNS/TNS, DRC) visible to the user before advancing to the next stage
  3. After the final stage, a formatted PPA summary report combining timing (WNS/TNS/clock period), power, and area metrics is presented to the user
**Plans**: 2 plans

Plans:
- [ ] 15-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 13 -> 14 -> 15

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Plugin Scaffold + Build Foundation | v1.0 | 2/2 | Complete | 2026-03-17 |
| 2. NL Parsing + Chisel Generation | v1.0 | 2/2 | Complete | 2026-03-17 |
| 3. Lint, Auto-Fix + Hooks | v1.0 | 3/3 | Complete | 2026-03-17 |
| 4. Testbench, Simulation + Verification | v1.0 | 2/2 | Complete | 2026-03-18 |
| 5. Workspace Foundation | v1.1 | 2/2 | Complete | 2026-03-20 |
| 6. Skill Decomposition | v1.1 | 2/2 | Complete | 2026-03-20 |
| 7. Orchestrator + Initialize | v1.1 | 2/2 | Complete | 2026-03-20 |
| 8. Debug Command | v1.1 | 2/2 | Complete | 2026-03-20 |
| 9. Environment + SDC Foundation | v1.1.2 | 2/2 | Complete | 2026-03-31 |
| 10. Yosys Synthesis | v1.1.2 | 1/1 | Complete | 2026-03-31 |
| 11. OpenROAD PnR + GDS Export | v1.1.2 | 1/1 | Complete | 2026-04-01 |
| 12. PnR Command + Report Integration | v1.1.2 | 1/1 | Complete | 2026-04-01 |
| 13. MCP Server + Environment Foundation | 2/2 | Complete   | 2026-04-02 | - |
| 14. Config Generation + ORFS Stage Execution | v1.1.5 | 0/? | Not started | - |
| 15. PnR Skill Orchestration + PPA Reporting | v1.1.5 | 0/? | Not started | - |

---
*Full v1.0 details archived to `.planning/milestones/v1.0-ROADMAP.md`*
*Full v1.1 details archived to `.planning/milestones/v1.1-ROADMAP.md`*
*Full v1.1.2 details archived to `.planning/milestones/v1.1.2-ROADMAP.md`*
