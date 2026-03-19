# ChipAgent

## What This Is

An npm-installable Claude Code plugin that provides a fully automated pipeline from natural language hardware descriptions to simulation-verified Verilog. Users describe a RISC-V module in plain language, invoke `/chip-agent:generate`, and the agent parses requirements, generates Chisel source, compiles to Verilog, lints with auto-fix, generates testbenches, simulates, and produces a verification report — all without human intervention.

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

### Active

## Current Milestone: v1.1 Refine

**Goal:** Decompose the monolithic generate pipeline into modular slash commands with per-module workspace isolation and environment detection.

**Target features:**
- Modular slash commands: requirement-parser, lint, testbench, simulate, debug, initialize
- Per-module `workspace/` isolation (spec, generated Verilog, sim logs per module)
- Hybrid spec-file communication between pipeline stages (Option C)
- Environment detection via `/chip-agent:initialize` (sbt, Scala, Verilator versions)
- Refactored `/chip-agent:generate` as orchestrator spawning subagents

### Out of Scope

- Full CPU core generation — pipeline targets individual functional modules, not complete processor designs
- FPGA synthesis — pipeline ends at functional simulation, no synthesis or place-and-route
- Non-RISC-V architectures — scoped to RV32I ISA
- GUI/web interface — CLI-only through Claude Code
- RTL optimization/PPA — beyond functional verification

## Context

Shipped v1.0 MVP with ~2,453 LOC across Scala, C++, Bash, and JSON.
Tech stack: Chisel 3.6.1, Scala 2.13.10, sbt 1.10.7, FIRRTL/firtool, Verilator 5.008+.
Acceptance test: ALU with ADD/SUB/AND/OR/XOR/SLT + zero flag passes all 12 test cases end-to-end.

## Constraints

- **Tech Stack**: Chisel (Scala) for HDL, sbt for build, firtool for FIRRTL-to-Verilog, Verilator for linting and simulation
- **ISA**: RV32I standard compliance required
- **Package Format**: npm package — installable via `npm install chip-agent`
- **Automation**: Fully automatic pipeline — no human intervention after slash command invocation
- **Fix Iterations**: Maximum 3 auto-fix attempts for lint errors before reporting failure
- **Output Format**: sim_result.log must follow prescribed format

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Chisel as HDL | Course requirement; generates clean Verilog via FIRRTL | ✓ Good |
| npm packaging | Enables distribution and reuse; follows get-shit-done pattern | ✓ Good |
| Slash command entry | Explicit trigger rather than ambient NL detection; clearer UX | ✓ Good |
| 3-attempt auto-fix | Balances automation with avoiding infinite loops | ✓ Good |
| Per-file linting | Avoids MULTITOP warnings from Verilator | ✓ Good |
| Skill-orchestrated lint (no hooks) | Prevents infinite loop from hook-triggered lint | ✓ Good |
| JSON spec as inter-agent contract | Clean boundary between parser and generator agents | ✓ Good |
| Combinational eval pattern | ALU is combinational; single eval() call, no clock cycling | ✓ Good |

---
*Last updated: 2026-03-19 after v1.1 milestone start*
