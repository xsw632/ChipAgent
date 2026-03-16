# ChipAgent

## What This Is

An npm-installable Claude Code plugin that provides a fully automated pipeline from natural language hardware descriptions to verified RTL. Users describe a RISC-V module in plain language, invoke a slash command, and the agent generates Chisel source code, compiles it to Verilog via FIRRTL/firtool, runs Verilator lint checks (with auto-fix up to 3 attempts), generates testbenches, executes simulation, and produces a verification report — all without human intervention.

## Core Value

A single slash command turns a natural language hardware description into lint-clean, simulation-verified Verilog with a complete test report.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Parse natural language hardware descriptions into structured module specifications
- [ ] Generate Chisel source code conforming to RV32I standards from parsed specifications
- [ ] Compile Chisel to FIRRTL and convert to Verilog via firtool automatically
- [ ] Run Verilator lint checks and auto-fix errors (up to 3 attempts)
- [ ] Generate testbenches with comprehensive test cases based on module functionality
- [ ] Execute simulation and produce formatted verification reports (sim_result.log)
- [ ] Package as npm-installable plugin with Skills, Hooks, Rules, and Subagents
- [ ] Provide slash command entry point (e.g., /chip:generate) for triggering the pipeline
- [ ] Support generic RV32I module generation (ALU, decoder, register file, etc.)

### Out of Scope

- Full CPU core generation — pipeline targets individual functional modules, not complete processor designs
- FPGA synthesis — pipeline ends at functional simulation, no synthesis or place-and-route
- Non-RISC-V architectures — scoped to RV32I ISA
- GUI/web interface — CLI-only through Claude Code

## Context

This is a course assignment requiring construction of an automated RTL generation and verification pipeline using Claude Code's agent infrastructure. The acceptance test is generating an ALU supporting ADD/SUB/AND/OR/XOR/SLT with a zero flag, where the entire flow runs without human intervention.

The pipeline leverages three Claude Code configuration mechanisms:
- **Rules (CLAUDE.md)**: Global behavior rules, project description, tech stack, interface specs, file path conventions, pipeline description
- **Skills**: Reusable task templates for requirement parsing, Chisel code generation, testbench generation, iteration/fix loops
- **Hooks**: Event-triggered automation scripts for compilation, FIRRTL-to-Verilog conversion, Verilator lint checks

The Chisel/Scala/sbt/firtool/Verilator toolchain is already installed on the target machine.

## Constraints

- **Tech Stack**: Chisel (Scala) for HDL, sbt for build, firtool for FIRRTL-to-Verilog, Verilator for linting and simulation
- **ISA**: RV32I standard compliance required
- **Package Format**: npm package (like get-shit-done) — installable via `npm install chip-agent`
- **Automation**: Fully automatic pipeline — no human intervention after slash command invocation
- **Fix Iterations**: Maximum 3 auto-fix attempts for lint errors before reporting failure
- **Output Format**: sim_result.log must follow prescribed format: `[TEST N] OP: a=X b=Y | expect=Z got=W | PASS/FAIL`
- **Lint Standard**: `verilator --lint-only generated/*.v` must produce no ERROR output; WARNINGs allowed but must be documented

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Chisel as HDL | Course requirement; generates clean Verilog via FIRRTL | — Pending |
| npm packaging | Enables distribution and reuse; follows get-shit-done pattern | — Pending |
| Slash command entry | Explicit trigger rather than ambient NL detection; clearer UX | — Pending |
| 3-attempt auto-fix | Balances automation with avoiding infinite loops | — Pending |
| Generic pipeline | ALU is acceptance test but pipeline should handle any RV32I module | — Pending |

---
*Last updated: 2026-03-16 after initialization*
