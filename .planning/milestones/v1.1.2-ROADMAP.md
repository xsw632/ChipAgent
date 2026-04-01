# Roadmap: ChipAgent

## Milestones

- ✅ **v1.0 MVP** — Phases 1-4 (shipped 2026-03-18)
- ✅ **v1.1 Refine** — Phases 5-8 (shipped 2026-03-23)
- **v1.1.2 RTL-to-GDS** — Phases 9-12 (in progress)

## Phases

<details>
<summary>v1.0 MVP (Phases 1-4) — SHIPPED 2026-03-18</summary>

- [x] Phase 1: Plugin Scaffold + Build Foundation (2/2 plans) — completed 2026-03-17
- [x] Phase 2: NL Parsing + Chisel Generation (2/2 plans) — completed 2026-03-17
- [x] Phase 3: Lint, Auto-Fix + Hooks (3/3 plans) — completed 2026-03-17
- [x] Phase 4: Testbench, Simulation + Verification (2/2 plans) — completed 2026-03-18

</details>

<details>
<summary>v1.1 Refine (Phases 5-8) — SHIPPED 2026-03-23</summary>

- [x] Phase 5: Workspace Foundation (2/2 plans) — completed 2026-03-20
- [x] Phase 6: Skill Decomposition (2/2 plans) — completed 2026-03-20
- [x] Phase 7: Orchestrator + Initialize (2/2 plans) — completed 2026-03-20
- [x] Phase 8: Debug Command (2/2 plans) — completed 2026-03-20

</details>

### v1.1.2 RTL-to-GDS (In Progress)

**Milestone Goal:** Add `/chip-agent:pnr` command that runs Yosys synthesis + OpenROAD place-and-route on verified Verilog to produce GDS, DEF, and timing/power/area reports using nangate45 PDK.

- [x] **Phase 9: Environment + SDC Foundation** - Extend env detection for PnR tools and generate SDC constraints from Verilog (completed 2026-03-31)
- [x] **Phase 10: Yosys Synthesis** - Produce gate-level netlist from RTL Verilog via standalone Yosys with generated Tcl (completed 2026-03-31)
- [x] **Phase 11: OpenROAD PnR + GDS Export** - Run full physical design flow and export final layout (completed 2026-04-01)
- [x] **Phase 12: PnR Command + Report Integration** - Wire scripts into slash command with formatted reports and auto-fix (completed 2026-04-01)

## Phase Details

### Phase 9: Environment + SDC Foundation
**Goal**: PnR tool availability is validated at init time, and any module's Verilog can be analyzed to produce correct SDC constraints
**Depends on**: Phase 8 (existing `/chip-agent:initialize` and workspace structure)
**Requirements**: ENV-01, ENV-02, SYN-02
**Success Criteria** (what must be TRUE):
  1. Running `/chip-agent:initialize` produces env.json entries for Yosys version, OpenROAD version, KLayout version, and nangate45 PDK path
  2. A pre-flight validation script exits non-zero with a clear message when any required PDK file (liberty, LEF, GDS) is missing
  3. Given a sequential Chisel module's Verilog (contains `clock` port), SDC generation produces `create_clock` on that port with a configurable period
  4. Given a combinational module's Verilog (no clock port), SDC generation produces a virtual clock with `set_max_delay` constraints
**Plans**: 2 plans
Plans:
- [ ] 09-01-PLAN.md -- Extend env detection for PnR tools + PDK validation script
- [ ] 09-02-PLAN.md -- SDC constraint auto-generation from Verilog analysis

### Phase 10: Yosys Synthesis
**Goal**: Any verified Verilog module can be synthesized to a gate-level netlist with nangate45 cells, producing a synthesis statistics report
**Depends on**: Phase 9 (needs SDC file and validated PDK paths)
**Requirements**: SYN-01, SYN-03
**Success Criteria** (what must be TRUE):
  1. Running `scripts/synth.sh <ModuleName>` produces a gate-level Verilog netlist at `workspace/pnr/<ModuleName>.synth.v` that OpenROAD can parse without errors
  2. Synthesis statistics report at `workspace/pnr/reports/synth_stat.txt` contains gate count, cell usage breakdown, and total area
  3. Synthesis works for both combinational modules (e.g., ALU) and sequential modules with the appropriate SDC applied
**Plans**: 1 plan
Plans:
- [x] 10-01-PLAN.md -- Yosys synthesis pipeline (synth.sh + synth.tcl)

### Phase 11: OpenROAD PnR + GDS Export
**Goal**: A synthesized netlist is physically implemented through floorplan, placement, CTS, and routing, producing a routed DEF, GDS, and physical design reports
**Depends on**: Phase 10 (needs synthesized netlist)
**Requirements**: PNR-01, PNR-02, PNR-03, GDS-01
**Success Criteria** (what must be TRUE):
  1. Running `scripts/pnr.sh <ModuleName>` produces a routed DEF file at `workspace/pnr/<ModuleName>.routed.def`
  2. Timing report in `workspace/pnr/reports/` shows WNS and TNS values; power report shows internal, switching, and leakage power; area report shows cell and total area
  3. Die area is automatically sized from synthesis cell count without manual configuration
  4. Combinational modules skip CTS (no clock tree inserted), while sequential modules get full CTS
  5. KLayout merges routed DEF with nangate45 GDS to produce `<ModuleName>.gds` in `workspace/pnr/`
**Plans**: 1 plan
Plans:
- [ ] 11-01-PLAN.md -- OpenROAD PnR pipeline (pnr.sh + pnr.tcl + def2gds.py)

### Phase 12: PnR Command + Report Integration
**Goal**: Users invoke a single slash command to run the entire RTL-to-GDS flow with human-readable results and automatic error recovery
**Depends on**: Phase 11 (needs working synth, PnR, and GDS scripts)
**Requirements**: CMD-01, CMD-02, CMD-03
**Success Criteria** (what must be TRUE):
  1. Running `/chip-agent:pnr <ModuleName>` executes synthesis, PnR, and GDS export in sequence, stopping on failure with context
  2. A formatted PnR report summarizes timing (pass/fail with WNS/TNS), power breakdown, area, and cell count in a human-readable table
  3. When synthesis or PnR fails, the auto-fix loop retries up to 3 times with diagnostic adjustments before reporting failure
**Plans**: 1 plan
Plans:
- [ ] 12-01-PLAN.md -- PnR slash command skill + report formatting agent + CLAUDE.md update

## Progress

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
| 9. Environment + SDC Foundation | 2/2 | Complete   | 2026-03-31 | - |
| 10. Yosys Synthesis | v1.1.2 | Complete    | 2026-03-31 | 2026-03-31 |
| 11. OpenROAD PnR + GDS Export | 1/1 | Complete    | 2026-04-01 | - |
| 12. PnR Command + Report Integration | 1/1 | Complete    | 2026-04-01 | - |

---
*Full v1.0 details archived to `.planning/milestones/v1.0-ROADMAP.md`*
*Full v1.1 details archived to `.planning/milestones/v1.1-ROADMAP.md`*
