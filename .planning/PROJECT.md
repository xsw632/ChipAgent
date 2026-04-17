# ChipAgent

## What This Is

An npm-installable Claude Code plugin that provides a fully automated pipeline from natural language hardware descriptions to physical GDS layout with intelligent failure handling. Users describe a hardware module in plain language, invoke `/chip-agent:workflow` for RTL generation and verification, then `/chip-agent:pnr` for physical implementation -- covering requirement parsing, Chisel generation, compilation, linting, testbench generation, simulation, ORFS synthesis, place-and-route, and GDS export with automatic failure diagnosis, parameter retry, and multi-round QoR optimization.

## Core Value

A single slash command turns a natural language hardware description into lint-clean, simulation-verified Verilog -- and a second command extends it through synthesis, PnR, and GDS export with intelligent failure diagnosis, automatic parameter retry, and multi-round QoR optimization.

## Requirements

### Validated

- v1.0: Parse natural language hardware descriptions into structured module specifications
- v1.0: Generate Chisel source code conforming to RV32I standards from parsed specifications
- v1.0: Compile Chisel to FIRRTL and convert to Verilog via firtool automatically
- v1.0: Run Verilator lint checks and auto-fix errors (up to 3 attempts)
- v1.0: Generate testbenches with comprehensive test cases based on module functionality
- v1.0: Execute simulation and produce formatted verification reports (sim_result.log)
- v1.0: Package as npm-installable plugin with Skills, Hooks, Rules, and Subagents
- v1.0: Provide slash command entry point (`/chip-agent:generate`) for triggering the pipeline
- v1.0: Support generic RV32I module generation (ALU acceptance test passing)
- v1.1: Per-module workspace isolation (`workspace/<Module>/`) with artifact subdirectories
- v1.1: Workspace-aware scripts (compile, lint, simulate) with backward-compatible flat mode
- v1.1: Modular slash commands: compile, lint, simulate, requirement-parser, testbench
- v1.1: Spec-file communication (`spec.json`) between pipeline stages instead of conversation context
- v1.1: Refactored generate orchestrator calling sub-skills with workspace paths
- v1.1: Environment detection via `/chip-agent:initialize` writing `.chipagent/env.json`
- v1.1: VCD waveform trace generation for simulation debug
- v1.1: `/chip-agent:debug` for structured failure diagnosis with VCD analysis
- v1.1.2: nangate45 PDK detection and pre-flight validation in environment initialization
- v1.1.2: SDC auto-generation: sequential modules get `create_clock`, combinational get virtual clock + `set_max_delay`
- v1.1.2: Yosys synthesis producing gate-level netlist with synthesis statistics report
- v1.1.2: OpenROAD PnR flow (floorplan -> place -> CTS -> route) with auto-die-sizing and conditional CTS skip
- v1.1.2: KLayout DEF->GDS merge producing final layout
- v1.1.2: `/chip-agent:pnr` slash command with formatted timing/power/area reports and auto-fix retry
- v1.1.5: MCP Server wrapping ORFS make targets for full backend flow
- v1.1.5: sky130hd PDK support (replacing nangate45)
- v1.1.5: ORFS-based PnR flow (replacing standalone Tcl scripts)
- v1.1.5: Per-stage metric extraction and PPA summary report
- v1.2.0: Auto-diagnose flow failure error types (timing violation, congestion, DRC, placement overflow, synthesis error)
- v1.2.0: Error-type-specific parameter retry (PLACE_DENSITY, CLOCK_PERIOD, CORE_UTILIZATION adjustment)
- v1.2.0: Multi-round QoR optimization with configuration comparison table and best-run recommendation

## Current Milestone: v1.3 Chipyard Integration & Full-Flow Automation

**Goal:** Integrate Chipyard RTL generation with SRAM analysis and ORFS PnR for tinyRocket processor end-to-end flow.

**Target features:**
- Chipyard environment detection in `/chip-agent:initialize` (local path vs Docker, RISCV toolchain)
- `/chip-agent:chipyard <config>` generating Verilog RTL from Chipyard (e.g. TinyRocketConfig)
- `/chip-agent:sram-mapping` analyzing RTL for SRAM macro instances and sky130hd mapping strategy
- Seamless handoff: chipyard output → workspace → `/chip-agent:pnr` picks up for backend flow
- End-to-end validation: tinyRocket from spec to PPA report

**Flow:** ① User Spec → ② Chipyard RTL → ③ SRAM Mapping → (handoff) → ④ ORFS Synth → ⑤ Place → ⑥ CTS+Route → ⑦ PPA Report

### Active

- CY-01: Chipyard environment detection in initialize skill (local/Docker, RISCV toolchain validation)
- CY-02: `/chip-agent:chipyard` command for Chipyard RTL generation with config parameter
- CY-03: `/chip-agent:sram-mapping` analysis of generated RTL for memory instances
- CY-04: Workspace integration -- chipyard output saved to MyDesign for pnr handoff
- CY-05: End-to-end tinyRocket validation through full pipeline

### Out of Scope

- Full CPU core generation -- pipeline targets individual functional modules, not complete processor designs
- Non-RISC-V architectures -- scoped to RV32I ISA
- GUI/web interface -- CLI-only through Claude Code
- Per-module sbt projects -- sbt startup cost multiplied; modules share dependencies
- Watch mode / file watcher -- creates infinite loops (PostToolUse hook lesson from v1.0)
- FPGA synthesis -- pipeline targets ASIC flow via OpenROAD, not FPGA
- Multi-corner STA -- single typical corner sufficient for current scope
- DRC/LVS -- requires KLayout ruledecks and Magic; defer to future
- Hierarchical synthesis -- Chisel modules are small enough for flat synthesis
- Non-sky130hd PDKs -- single PDK (sky130hd) per task2 requirement; multi-PDK later
- AutoTuner / Ray Tune integration -- heavy ML framework, overkill for rule-based retry
- RTL modification for timing closure -- crosses RTL/backend boundary, outside PnR scope
- Parallel multi-config exploration -- sequential retry is simpler and sufficient
- Exhaustive parameter sweep -- combinatorial explosion; error-directed adjustment is targeted

## Context

Shipped v1.2.0 Smart Retry & QoR Optimization. Full NL-to-GDS pipeline with intelligent failure handling.
Tech stack: Chisel 3.6.1, Scala 2.13.10, sbt 1.10.7, FIRRTL/firtool, Verilator 5.046, ORFS (Yosys + OpenROAD), sky130hd PDK, MCP Server (TypeScript), Chipyard.
7 MCP tools: run_stage, generate_config, get_report, diagnose_failure, clean_design, compare_runs + environment detection.
3 slash commands: `/chip-agent:generate`, `/chip-agent:workflow`, `/chip-agent:pnr` + 2 new: `/chip-agent:chipyard`, `/chip-agent:sram-mapping`.
PnR pipeline: 6-stage ORFS flow with 3-round retry loop, stage-aware restart, QoR comparison table, and best-run recommendation.
73 unit tests across MCP server, zero regressions.

## Constraints

- **Tech Stack**: Chisel (Scala) for HDL, sbt for build, firtool for FIRRTL-to-Verilog, Verilator for linting and simulation
- **ISA**: RV32I standard compliance required
- **Package Format**: npm package -- installable via `npm install chip-agent`
- **Automation**: Fully automatic pipeline -- no human intervention after slash command invocation
- **Fix Iterations**: Maximum 3 auto-fix attempts for lint errors; maximum 3 retry rounds for PnR failures
- **Output Format**: sim_result.log must follow prescribed format
- **Workspace Convention**: `MyDesign/<Module>/workspace/` with `generated/`, `sim/logs/`, `pnr/` subdirectories
- **Script Compatibility**: All scripts support both workspace mode and v1.0 flat mode
- **PnR Backend**: ORFS make flow on sky130hd via MCP Server

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Chisel as HDL | Course requirement; generates clean Verilog via FIRRTL | Good |
| npm packaging | Enables distribution and reuse; follows plugin pattern | Good |
| Slash command entry | Explicit trigger rather than ambient NL detection; clearer UX | Good |
| 3-attempt auto-fix | Balances automation with avoiding infinite loops | Good |
| Per-file linting | Avoids MULTITOP warnings from Verilator | Good |
| JSON spec as inter-agent contract | Clean boundary between parser and generator agents | Good |
| Spec-file communication (Option C) | Decouples pipeline stages from conversation context | Good |
| Skills wrap agents | agents = "how", skills = "when/where"; clean separation | Good |
| Removed PostToolUse hook | Orchestrator calls scripts explicitly; hook env vars unreliable | Good |
| Runtime plugin root detection | .claude-plugin/plugin.json ancestor search avoids broken env var | Good |
| VCD parser uses stdlib only | Zero-install portability across all Python 3 environments | Good |
| Debug is diagnostic-only | Never auto-applies fixes; prevents runaway modification loops | Good |
| SDC: sequential vs combinational detection | Grep for `always @(posedge` in Verilog to classify modules | Good |
| 2.0ns default clock period | Conservative default avoids timing failures on small modules | Good |
| PDK candidate directory chain | env override -> ORFS_DIR -> ~/OpenROAD-flow-scripts -> /opt | Good |
| Auto-size die area | <100 cells -> 70x70um floor; >=100 cells -> 30% utilization | Good |
| Conditional CTS skip | Combinational modules skip clock tree synthesis | Good |
| KLayout LEF via layoutOptions | Load LEF files through layoutOptions, not .lyt tech file | Good |
| No synthesis retry in PnR | Synthesis failures require RTL changes outside PnR scope | Good |
| 50% clock period increase per retry | Auto-fix timing violations by relaxing clock constraint | Good |
| Power in microwatts | Always report power in uW, never raw Watts | Good |
| MCP Server for ORFS flow | Wraps make targets; cleaner than shell scripts; extensible | Good |
| sky130hd over nangate45 | Task2 requirement; more realistic open-source PDK | Good |
| ORFS make flow over standalone Tcl | Leverages ORFS infrastructure; more maintainable | Good |
| Error classification priority chain | synthesis > placement_overflow > congestion > drc > timing > unknown | Good |
| Deterministic best-run selection | Filter+sort over LLM judgment for reliability | Good |
| 4 actions in single compare_runs tool | Cohesion over separate tools; simpler MCP registration | Good |
| Flat JSON for QoR history | Sufficient for <10 runs; zero dependencies; human-readable | Good |
| Mutable param accumulation in retry | Prevents parameter drift by never resetting between rounds | Good |
| Critical errors abort retry | Synthesis/combinational timing not parameter-fixable; saves time | Good |
| Mandatory clean_design before retry | Prevents ORFS stale cache issues | Good |
| Two-step split: chipyard + pnr | Chipyard handles RTL+SRAM analysis, pnr handles backend; cleaner separation | Good |
| SV concatenation for ORFS | Merge Chipyard's split SV files into single .v for ORFS compatibility | Good |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-14 starting v1.3 milestone*
