# Roadmap: ChipAgent

## Overview

ChipAgent delivers a fully automated pipeline from natural language hardware descriptions to simulation-verified Verilog, packaged as an npm-installable Claude Code plugin. The roadmap progresses from plugin scaffold and build foundation, through LLM-driven code generation, to lint automation with auto-fix, culminating in testbench simulation and verification reporting. Each phase produces independently testable deliverables, with the final phase producing the acceptance test: an ALU passing all test cases end-to-end without human intervention.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Plugin Scaffold + Build Foundation** - npm plugin structure with working sbt compilation pipeline
- [x] **Phase 2: NL Parsing + Chisel Generation** - LLM agents that parse hardware descriptions and generate compilable Chisel code (completed 2026-03-17)
- [ ] **Phase 3: Lint, Auto-Fix + Hooks** - Verilator lint checking with 3-attempt auto-fix loop and hook-based automation
- [ ] **Phase 4: Testbench, Simulation + Verification** - C++ testbench generation, simulation execution, and formatted verification reports

## Phase Details

### Phase 1: Plugin Scaffold + Build Foundation
**Goal**: A valid Claude Code plugin with a working sbt project that compiles Chisel to Verilog
**Depends on**: Nothing (first phase)
**Requirements**: PLUG-01, PLUG-02, PLUG-03, PLUG-04, PLUG-05, BUILD-01, BUILD-02, BUILD-03
**Success Criteria** (what must be TRUE):
  1. Running `claude --plugin-dir .` loads the plugin and shows `/chip-agent:generate` as an available command
  2. The sbt project compiles a trivial Chisel module and emits Verilog files into `generated/`
  3. `scripts/compile.sh` runs sbt compilation end-to-end and reports errors with context on failure
  4. CLAUDE.md exists with project rules, tech stack, interface specs, and file path conventions
**Plans:** 2 plans

Plans:
- [x] 01-01-PLAN.md -- Plugin manifest, directory skeleton, .gitignore, CLAUDE.md, slash command skill, and npm package
- [x] 01-02-PLAN.md -- sbt project skeleton (build.sbt, Generate.scala, TrivialModule), compile/setup scripts, and hooks

### Phase 2: NL Parsing + Chisel Generation
**Goal**: Users describe a hardware module in plain language and get valid, compilable Chisel source code
**Depends on**: Phase 1
**Requirements**: PARSE-01, PARSE-02, PARSE-03, GEN-01, GEN-02, GEN-03, GEN-04
**Success Criteria** (what must be TRUE):
  1. User provides a natural language ALU description and receives a structured spec with module name, ports, operations, and constraints
  2. Agent generates Chisel 3.6.1 source code that follows project conventions (correct package, imports, IO bundle)
  3. Generated Chisel compiles via sbt and produces Verilog in `generated/` without manual edits
  4. The generation pipeline handles the acceptance test description (ALU with ADD/SUB/AND/OR/XOR/SLT + zero flag)
**Plans:** 2/2 plans complete

Plans:
- [x] 02-01-PLAN.md -- Requirement-parser and chisel-generator agent definitions with JSON spec schema and Chisel 3.6.1 templates
- [x] 02-02-PLAN.md -- ALU reference implementation, dynamic Generate.scala, pipeline orchestration skill, and integration test script

### Phase 3: Lint, Auto-Fix + Hooks
**Goal**: Generated Verilog passes Verilator lint with automatic error correction and hook-driven automation
**Depends on**: Phase 2
**Requirements**: LINT-01, LINT-02, LINT-03, LINT-04, LINT-05, HOOK-01, HOOK-02, HOOK-03
**Success Criteria** (what must be TRUE):
  1. `verilator --lint-only generated/*.v` produces no ERROR output on lint-clean Verilog
  2. When lint errors are found, the agent auto-fixes and retries up to 3 times without human intervention
  3. After 3 failed fix attempts, the pipeline stops and reports remaining errors clearly
  4. Hooks in `hooks/hooks.json` trigger compilation and lint automatically at the right pipeline stages without infinite loops
  5. Any Verilator warnings that remain are documented with explanations in the verification output
**Plans**: TBD

Plans:
- [ ] 03-01: Lint script, auto-fix loop agent, hooks configuration, and warning documentation

### Phase 4: Testbench, Simulation + Verification
**Goal**: The pipeline produces simulation-verified Verilog with a formatted test report -- the acceptance deliverable
**Depends on**: Phase 3
**Requirements**: TB-01, TB-02, TB-03, TB-04, SIM-01, SIM-02, SIM-03
**Success Criteria** (what must be TRUE):
  1. Agent generates a C++ testbench with clock handling, input driving, and output checking for the target module
  2. ALU testbench covers all 6 operations (ADD/SUB/AND/OR/XOR/SLT) with at least 10 test cases
  3. `scripts/simulate.sh` compiles the testbench with Verilator and runs simulation to completion
  4. `sim/logs/sim_result.log` contains lines in format `[TEST N] OP: a=X b=Y | expect=Z got=W | PASS/FAIL` with a final `RESULT: PASSED X/Y tests` or `RESULT: FAILED` line
**Plans**: TBD

Plans:
- [ ] 04-01: Testbench-generator agent, simulate script, and report formatting
- [ ] 04-02: End-to-end acceptance test (full pipeline from NL description to PASSED report)

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Plugin Scaffold + Build Foundation | 2/2 | Complete | 2026-03-17 |
| 2. NL Parsing + Chisel Generation | 2/2 | Complete   | 2026-03-17 |
| 3. Lint, Auto-Fix + Hooks | 0/1 | Not started | - |
| 4. Testbench, Simulation + Verification | 0/2 | Not started | - |
