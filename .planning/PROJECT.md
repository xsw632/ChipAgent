# ChipAgent

## Current State

**Shipped:** v1.1.5 sky130hd MCP Backend (2026-04-02)

The plugin now provides a complete NL → RTL → GDS pipeline:
- `/chip-agent:workflow` for RTL generation and verification
- `/chip-agent:pnr` for ORFS-driven physical implementation on sky130hd via MCP server

**Tech stack:** Chisel 3.6.1, Scala 2.13.10, sbt 1.10.7, FIRRTL/firtool, Verilator, MCP Server (TypeScript), ORFS make flow, sky130hd PDK.
**Stats:** ~13,900 LOC across 15 phases, 4 milestones.

## Next Milestone Goals

Not yet defined. Run `/gsd:new-milestone` to start the next milestone cycle.

<details>
<summary>Previous state (v1.1.5 in progress)</summary>

## What This Is

An npm-installable Claude Code plugin that provides a fully automated pipeline from natural language hardware descriptions to physical GDS layout. Users describe a RISC-V module in plain language, invoke `/chip-agent:workflow` for RTL generation and verification, then `/chip-agent:pnr` for physical implementation — covering requirement parsing, Chisel generation, compilation, linting, testbench generation, simulation, Yosys synthesis, OpenROAD place-and-route, and KLayout GDS export with formatted reports and auto-fix retry.

## Core Value

A single slash command turns a natural language hardware description into lint-clean, simulation-verified Verilog with a complete test report — and a second command extends it through synthesis, place-and-route, and GDS export with formatted physical design reports.

## Requirements

### Validated

- ✓ Parse natural language hardware descriptions into structured module specifications — v1.0
- ✓ Generate Chisel source code conforming to RV32I standards from parsed specifications — v1.0
- ✓ Compile Chisel to FIRRTL and convert to Verilog via firtool automatically — v1.0
- ✓ Run Verilator lint checks and auto-fix errors (up to 3 attempts) — v1.0
- ✓ Generate testbenches with comprehensive test cases based on module functionality — v1.0
- ✓ Execute simulation and produce formatted verification reports (sim_result.log) — v1.0
- ✓ Package as npm-installable plugin with Skills, Hooks, Rules, and Subagents — v1.0
- ✓ Provide slash command entry point (`/chip-agent:generate`) for triggering the pipeline — v1.0
- ✓ Support generic RV32I module generation (ALU acceptance test passing) — v1.0
- ✓ Per-module workspace isolation (`workspace/<Module>/`) with artifact subdirectories — v1.1
- ✓ Workspace-aware scripts (compile, lint, simulate) with backward-compatible flat mode — v1.1
- ✓ Modular slash commands: compile, lint, simulate, requirement-parser, testbench — v1.1
- ✓ Spec-file communication (`spec.json`) between pipeline stages instead of conversation context — v1.1
- ✓ Refactored generate orchestrator calling sub-skills with workspace paths — v1.1
- ✓ Environment detection via `/chip-agent:initialize` writing `.chipagent/env.json` — v1.1
- ✓ VCD waveform trace generation for simulation debug — v1.1
- ✓ `/chip-agent:debug` for structured failure diagnosis with VCD analysis — v1.1
- ✓ nangate45 PDK detection and pre-flight validation in environment initialization — v1.1.2
- ✓ SDC auto-generation: sequential modules get `create_clock`, combinational get virtual clock + `set_max_delay` — v1.1.2
- ✓ Yosys synthesis producing gate-level netlist with synthesis statistics report — v1.1.2
- ✓ OpenROAD PnR flow (floorplan → place → CTS → route) with auto-die-sizing and conditional CTS skip — v1.1.2
- ✓ KLayout DEF→GDS merge producing final layout — v1.1.2
- ✓ `/chip-agent:pnr` slash command with formatted timing/power/area reports and auto-fix retry — v1.1.2

### Active

<!-- v1.1.5 sky130hd MCP Backend — see REQUIREMENTS.md for full list -->

- [ ] MCP Server wrapping ORFS make targets for full backend flow
- [ ] sky130hd PDK support (replacing nangate45)
- [ ] ORFS-based PnR flow (replacing standalone Tcl scripts)
- [ ] Docker environment detection in initialize (pre-reserved)
- [ ] Per-stage metric extraction and PPA summary report

## Current Milestone: v1.1.5 sky130hd MCP Backend

**Goal:** Replace standalone nangate45 Tcl scripts with MCP Server-driven ORFS make flow on sky130hd, reaching 进阶要求 level for task2.

**Target features:**
- MCP Server (TypeScript) wrapping ORFS make targets with Docker interface pre-reserved
- sky130hd PDK detection and config.mk/SDC auto-generation
- /chip-agent:pnr rewrite using MCP tools for 6-stage ORFS flow
- Per-stage metric extraction (area, WNS/TNS, DRC) and PPA summary report
- /chip-agent:initialize updated for Docker + sky130hd detection

### Out of Scope

- Full CPU core generation — pipeline targets individual functional modules, not complete processor designs
- Non-RISC-V architectures — scoped to RV32I ISA
- GUI/web interface — CLI-only through Claude Code
- Per-module sbt projects — sbt startup cost multiplied; modules share dependencies
- Watch mode / file watcher — creates infinite loops (PostToolUse hook lesson from v1.0)
- FPGA synthesis — pipeline targets ASIC flow via OpenROAD, not FPGA
- Multi-corner STA — single typical corner sufficient for current scope
- DRC/LVS — requires KLayout ruledecks and Magic; defer to future
- Hierarchical synthesis — Chisel modules are small enough for flat synthesis
- Non-sky130hd PDKs — single PDK (sky130hd) per task2 requirement; multi-PDK later

## Context

Shipped v1.1.2 RTL-to-GDS with full physical implementation pipeline.
~8,700 LOC across Scala, C++, Bash, Python, Tcl, and Markdown.
Tech stack: Chisel 3.6.1, Scala 2.13.10, sbt 1.10.7, FIRRTL/firtool, Verilator 5.008+, Yosys 0.53+, OpenROAD 26Q1, KLayout 0.30.7, Python 3 (stdlib VCD parser + pya for GDS).
10 slash commands: generate, workflow, compile, lint, simulate, requirement-parser, testbench, initialize, debug, pnr.
Acceptance test: ALU with ADD/SUB/AND/OR/XOR/SLT + zero flag passes all 12 test cases end-to-end.
PnR validated: ALU and Counter8 synthesize and route to GDS with timing MET.

## Constraints

- **Tech Stack**: Chisel (Scala) for HDL, sbt for build, firtool for FIRRTL-to-Verilog, Verilator for linting and simulation
- **ISA**: RV32I standard compliance required
- **Package Format**: npm package — installable via `npm install chip-agent`
- **Automation**: Fully automatic pipeline — no human intervention after slash command invocation
- **Fix Iterations**: Maximum 3 auto-fix attempts for lint errors before reporting failure
- **Output Format**: sim_result.log must follow prescribed format
- **Workspace Convention**: `workspace/<Module>/` with `generated/`, `sim/logs/` subdirectories
- **Script Compatibility**: All scripts support both workspace mode and v1.0 flat mode

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Chisel as HDL | Course requirement; generates clean Verilog via FIRRTL | ✓ Good |
| npm packaging | Enables distribution and reuse; follows plugin pattern | ✓ Good |
| Slash command entry | Explicit trigger rather than ambient NL detection; clearer UX | ✓ Good |
| 3-attempt auto-fix | Balances automation with avoiding infinite loops | ✓ Good |
| Per-file linting | Avoids MULTITOP warnings from Verilator | ✓ Good |
| JSON spec as inter-agent contract | Clean boundary between parser and generator agents | ✓ Good |
| Spec-file communication (Option C) | Decouples pipeline stages from conversation context | ✓ Good |
| Skills wrap agents | agents = "how", skills = "when/where"; clean separation | ✓ Good |
| Removed PostToolUse hook | Orchestrator calls scripts explicitly; hook env vars unreliable | ✓ Good |
| Runtime plugin root detection | .claude-plugin/plugin.json ancestor search avoids broken env var | ✓ Good |
| VCD parser uses stdlib only | Zero-install portability across all Python 3 environments | ✓ Good |
| Debug is diagnostic-only | Never auto-applies fixes; prevents runaway modification loops | ✓ Good |
| Standalone Tcl scripts for PnR | Standalone Yosys/OpenROAD Tcl scripts instead of ORFS Makefile; portable | ✓ Good |
| SDC: sequential vs combinational detection | Grep for `always @(posedge` in Verilog to classify modules | ✓ Good |
| 2.0ns default clock period | Conservative default avoids timing failures on small modules | ✓ Good |
| PDK candidate directory chain | env override → ORFS_DIR → ~/OpenROAD-flow-scripts → /opt | ✓ Good |
| Yosys Tcl mode (-c) | Yosys Tcl requires `yosys` prefix on all commands | ✓ Good |
| Auto-size die area | <100 cells → 70x70um floor; ≥100 cells → 30% utilization | ✓ Good |
| Conditional CTS skip | Combinational modules skip clock tree synthesis | ✓ Good |
| KLayout LEF via layoutOptions | Load LEF files through layoutOptions, not .lyt tech file | ✓ Good |
| No synthesis retry in PnR | Synthesis failures require RTL changes outside PnR scope | ✓ Good |
| 50% clock period increase per retry | Auto-fix timing violations by relaxing clock constraint | ✓ Good |
| Power in microwatts | Always report power in uW, never raw Watts | ✓ Good |

---
*Last updated: 2026-04-01 after v1.1.5 milestone start*
</details>
