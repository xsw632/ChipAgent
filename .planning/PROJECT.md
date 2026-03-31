# ChipAgent

## What This Is

An npm-installable Claude Code plugin that provides a fully automated, modular pipeline from natural language hardware descriptions to simulation-verified Verilog. Users describe a RISC-V module in plain language, invoke `/chip-agent:generate`, and the orchestrator sequentially runs requirement parsing, Chisel generation, compilation, linting, testbench generation, simulation, and verification reporting — all with per-module workspace isolation and VCD-based debug support.

## Core Value

A single slash command turns a natural language hardware description into lint-clean, simulation-verified Verilog with a complete test report.

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

### Active

## Current Milestone: v1.1.2 RTL-to-GDS

**Goal:** Add a `/chip-agent:pnr` command that runs Yosys synthesis + OpenROAD place-and-route on verified Verilog to produce GDS, DEF, and timing/power/area reports using nangate45 PDK.

**Target features:**
- nangate45 PDK setup and detection in environment initialization
- Yosys synthesis script producing gate-level netlist from RTL Verilog
- OpenROAD PnR flow (floorplan → placement → CTS → routing → export)
- GDS and routed DEF output artifacts
- Timing (STA), power, and area reports
- `/chip-agent:pnr <ModuleName>` slash command

### Out of Scope

- Full CPU core generation — pipeline targets individual functional modules, not complete processor designs
- FPGA synthesis — pipeline ends at functional simulation, no synthesis or place-and-route
- Non-RISC-V architectures — scoped to RV32I ISA
- GUI/web interface — CLI-only through Claude Code
- RTL optimization/PPA — beyond functional verification
- Per-module sbt projects — sbt startup cost multiplied; modules share dependencies
- Moving Scala sources into workspace/ — sbt requires sources in chisel-project/src/
- Watch mode / file watcher — creates infinite loops (PostToolUse hook lesson from v1.0)

## Context

Shipped v1.1 Refine with modular pipeline decomposition.
~4,500 LOC across Scala, C++, Bash, Python, and JSON.
Tech stack: Chisel 3.6.1, Scala 2.13.10, sbt 1.10.7, FIRRTL/firtool, Verilator 5.008+, Yosys 0.53+, OpenROAD 26Q1, Python 3 (stdlib VCD parser).
8 slash commands: generate, compile, lint, simulate, requirement-parser, testbench, initialize, debug.
Acceptance test: ALU with ADD/SUB/AND/OR/XOR/SLT + zero flag passes all 12 test cases end-to-end.
Starting v1.1.2: RTL-to-GDS via Yosys + OpenROAD with nangate45 PDK.

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

---
*Last updated: 2026-03-31 after v1.1.2 milestone start*
