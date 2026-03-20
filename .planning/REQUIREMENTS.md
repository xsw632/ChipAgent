# Requirements: ChipAgent v1.1 Refine

**Defined:** 2026-03-20
**Core Value:** A single slash command turns a natural language hardware description into lint-clean, simulation-verified Verilog with a complete test report.

## v1.1 Requirements

### Workspace Isolation

- [ ] **WKSP-01**: Each generated module gets its own `workspace/<ModuleName>/` directory containing spec, generated Verilog, and simulation artifacts
- [x] **WKSP-02**: Scripts (compile.sh, lint.sh, simulate.sh) accept optional workspace path arguments while defaulting to v1.0 flat directory layout
- [x] **WKSP-03**: `workspace/` directory and per-module `obj_dir/` artifacts are gitignored

### Modular Commands — Script Wrappers

- [x] **SKILL-01**: `/chip-agent:compile` compiles a named module's Chisel source to Verilog, outputting to `workspace/<Module>/generated/`
- [x] **SKILL-02**: `/chip-agent:lint` runs Verilator lint-only on a named module's generated Verilog
- [x] **SKILL-03**: `/chip-agent:simulate` runs Verilator simulation for a named module, producing `sim_result.log` in `workspace/<Module>/sim/logs/`
- [ ] **SKILL-04**: `/chip-agent:testbench` generates a C++ testbench for a named module using the testbench-generator agent

### Modular Commands — Agent-Backed

- [ ] **SKILL-05**: `/chip-agent:requirement-parser` parses a natural language hardware description into a structured `spec.json` written to `workspace/<Module>/spec.json`
- [ ] **SKILL-06**: `/chip-agent:generate` (refactored) orchestrates the full pipeline by sequentially invoking sub-skills: requirement-parser → chisel-generate → compile → lint → testbench → simulate → report
- [ ] **SKILL-07**: `/chip-agent:debug` analyzes simulation failures by cross-referencing spec.json, Chisel source, and sim_result.log to suggest targeted fixes

### Inter-Stage Communication

- [ ] **SPEC-01**: Requirement parser writes a structured JSON spec file to `workspace/<Module>/spec.json` containing module name, ports, operations, and test vectors
- [ ] **SPEC-02**: Downstream stages (chisel-generate, testbench) read spec.json from workspace rather than depending on conversation context

### Environment Detection

- [ ] **INIT-01**: `/chip-agent:initialize` detects local tool versions (Java, sbt, Scala, Verilator, Make, g++)
- [ ] **INIT-02**: Initialize writes a machine-readable `.chipagent/env.json` with tool versions, paths, and capability flags (can_compile, can_lint, can_simulate)
- [ ] **INIT-03**: Initialize updates the CLAUDE.md Tech Stack table with actually detected local versions

## v1.2 Requirements (Deferred)

### Module Management

- **LIST-01**: `/chip-agent:list` shows all modules in workspace with their verification status
- **CLEAN-01**: `/chip-agent:clean` removes workspace artifacts for a named module

### Build Optimization

- **INCR-01**: Skip sbt compilation when Scala source is unchanged (mtime comparison)
- **ROUTE-01**: Intelligent module name routing — resolve partial names to workspace paths

## Out of Scope

| Feature | Reason |
|---------|--------|
| Per-module sbt projects | sbt startup cost multiplied; modules share dependencies |
| Moving Scala sources into workspace/ | sbt requires sources in chisel-project/src/; breaking this requires build.sbt reconfiguration |
| Parallel multi-module compilation | Adds complexity for marginal benefit at current scale |
| Cross-module dependency tracking | Build system feature (FuseSoC territory); ChipAgent generates standalone modules |
| Watch mode / file watcher | Creates infinite loops (PostToolUse hook already nearly caused this in v1.0) |
| Persistent workspace state machine | Use filesystem presence as state: spec.json exists = parsed, *.v exists = compiled |
| Custom help system | Claude Code already provides `/` autocomplete and skill descriptions |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| WKSP-01 | Phase 5 | In Progress |
| WKSP-02 | Phase 5 | In Progress |
| WKSP-03 | Phase 5 | Complete |
| SKILL-01 | Phase 6 | Complete |
| SKILL-02 | Phase 6 | Complete |
| SKILL-03 | Phase 6 | Complete |
| SKILL-04 | Phase 6 | Pending |
| SKILL-05 | Phase 6 | Pending |
| SKILL-06 | Phase 7 | Pending |
| SKILL-07 | Phase 8 | Pending |
| SPEC-01 | Phase 6 | Pending |
| SPEC-02 | Phase 6 | Pending |
| INIT-01 | Phase 7 | Pending |
| INIT-02 | Phase 7 | Pending |
| INIT-03 | Phase 7 | Pending |

**Coverage:**
- v1.1 requirements: 15 total
- Mapped to phases: 15
- Unmapped: 0

---
*Requirements defined: 2026-03-20*
*Last updated: 2026-03-20 after roadmap creation*
