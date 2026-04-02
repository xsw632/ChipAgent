# Roadmap: ChipAgent

## Milestones

- ✅ **v1.0 MVP** -- Phases 1-4 (shipped 2026-03-18)
- ✅ **v1.1 Refine** -- Phases 5-8 (shipped 2026-03-23)
- ✅ **v1.1.2 RTL-to-GDS** -- Phases 9-12 (shipped 2026-04-01)
- ✅ **v1.1.5 sky130hd MCP Backend** -- Phases 13-15 (shipped 2026-04-02)
- 🚧 **v1.2.0 Smart Retry & QoR Optimization** -- Phases 16-17 (in progress)

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

<details>
<summary>v1.1.5 sky130hd MCP Backend (Phases 13-15) -- SHIPPED 2026-04-02</summary>

- [x] Phase 13: MCP Server + Environment Foundation (2/2 plans) -- completed 2026-04-02
- [x] Phase 14: Config Generation + ORFS Stage Execution (2/2 plans) -- completed 2026-04-02
- [x] Phase 15: PnR Skill Orchestration + PPA Reporting (2/2 plans) -- completed 2026-04-02

</details>

### v1.2.0 Smart Retry & QoR Optimization (In Progress)

**Milestone Goal:** Add intelligent failure diagnosis, error-type-based parameter retry, and multi-round QoR optimization to the MCP-driven PnR pipeline.

- [ ] **Phase 16: Diagnosis & Retry Infrastructure** - MCP tools for error classification, design cleanup, config tuning, and failure diagnosis
- [ ] **Phase 17: Retry Orchestration & QoR Optimization** - Skill-level retry loop with stage-aware restart, QoR history tracking, comparison table, and best-run recommendation

## Phase Details

### Phase 16: Diagnosis & Retry Infrastructure
**Goal**: MCP server provides all tools needed to diagnose failures, clean cached state, and regenerate configs with tuned parameters
**Depends on**: Phase 15 (existing MCP server and ORFS pipeline)
**Requirements**: DIAG-01, DIAG-02, DIAG-03, DIAG-04, RETRY-01
**Success Criteria** (what must be TRUE):
  1. Calling `diagnose_failure` on ORFS output with a timing violation returns structured JSON classifying the error type as `timing_violation` with suggested parameter adjustments (e.g., increase clock_period)
  2. Calling `diagnose_failure` on a successful run where WNS < 0 in finish report still detects the silent timing violation (not reported as success)
  3. Calling `clean_design` resets ORFS cached artifacts so a subsequent `run_stage` starts fresh (no stale results)
  4. Calling `generate_config` with optional `place_density` or other tuning parameters produces a config.mk that includes those overrides
  5. `diagnose_failure` returns different suggested adjustments for different error types: timing -> clock_period, congestion -> place_density, placement overflow -> core_utilization
**Plans**: 2 plans

Plans:
- [ ] 16-01-PLAN.md -- diagnose_failure MCP tool: error classification, silent timing detection, parameter suggestions
- [ ] 16-02-PLAN.md -- clean_design tool, generate_config tuning extension, MCP server registration

### Phase 17: Retry Orchestration & QoR Optimization
**Goal**: PnR skill automatically retries failed flows with diagnosed parameter adjustments and presents multi-round QoR comparison with best-run recommendation
**Depends on**: Phase 16 (diagnosis and retry tools available)
**Requirements**: RETRY-02, RETRY-03, RETRY-04, QOR-01, QOR-02, QOR-03
**Success Criteria** (what must be TRUE):
  1. When a PnR flow fails with a timing violation, the skill automatically diagnoses the failure, adjusts parameters, cleans, and re-runs -- up to 3 rounds total without user intervention
  2. When only placement parameters change (not synthesis-affecting params), retry skips synthesis and restarts from floorplan stage (stage-aware restart)
  3. After all retry rounds complete, the user sees a comparison table showing each round's configuration, metrics (WNS, TNS, area, power), and pass/fail status
  4. The agent recommends the best run: tightest clock period with WNS >= 0 and zero DRC violations
  5. Run configurations and metrics are persisted to qor_history.json in the workspace, surviving across sessions
**Plans**: TBD

Plans:
- [ ] 17-01: TBD
- [ ] 17-02: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 16 -> 17

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
| 13. MCP Server + Environment Foundation | v1.1.5 | 2/2 | Complete | 2026-04-02 |
| 14. Config Generation + ORFS Stage Execution | v1.1.5 | 2/2 | Complete | 2026-04-02 |
| 15. PnR Skill Orchestration + PPA Reporting | v1.1.5 | 2/2 | Complete | 2026-04-02 |
| 16. Diagnosis & Retry Infrastructure | 1/2 | In Progress|  | - |
| 17. Retry Orchestration & QoR Optimization | v1.2.0 | 0/? | Not started | - |

---
*Full v1.0 details archived to `.planning/milestones/v1.0-ROADMAP.md`*
*Full v1.1 details archived to `.planning/milestones/v1.1-ROADMAP.md`*
*Full v1.1.2 details archived to `.planning/milestones/v1.1.2-ROADMAP.md`*
*Full v1.1.5 details archived to `.planning/milestones/v1.1.5-ROADMAP.md`*
