# Requirements: ChipAgent

**Defined:** 2026-03-16
**Core Value:** A single slash command turns a natural language hardware description into lint-clean, simulation-verified Verilog with a complete test report.

## v1 Requirements

### Plugin Infrastructure

- [ ] **PLUG-01**: Plugin has valid `.claude-plugin/plugin.json` manifest with name "chip-agent"
- [ ] **PLUG-02**: Plugin provides `/chip-agent:generate` slash command as pipeline entry point
- [ ] **PLUG-03**: Plugin is installable via `npx chip-agent` or `claude --plugin-dir`
- [ ] **PLUG-04**: CLAUDE.md defines project rules, tech stack, interface specs, file path conventions
- [x] **PLUG-05**: Plugin includes setup script that initializes sbt project skeleton on first use

### Requirement Parsing

- [x] **PARSE-01**: User can describe a hardware module in natural language and get a structured spec
- [x] **PARSE-02**: Parser extracts module name, port list, operations, and constraints from NL
- [x] **PARSE-03**: Parser handles RV32I ALU descriptions (ADD/SUB/AND/OR/XOR/SLT + zero flag)

### Chisel Generation

- [x] **GEN-01**: Agent generates valid Chisel 6.x+ Scala source from parsed module spec
- [x] **GEN-02**: Generated Chisel follows project conventions (package, imports, IO bundle)
- [ ] **GEN-03**: Generator creates Verilog emission entry point (Generate.scala with ChiselStage)
- [ ] **GEN-04**: Generated code compiles successfully with sbt on first attempt (or auto-fixes)

### Build Automation

- [x] **BUILD-01**: `scripts/compile.sh` runs sbt compilation and emits Verilog to `generated/`
- [x] **BUILD-02**: Compilation is triggered automatically after Chisel source is written
- [x] **BUILD-03**: Build errors are captured and reported with context for auto-fix

### Lint & Auto-Fix

- [ ] **LINT-01**: `scripts/lint.sh` runs `verilator --lint-only` on generated Verilog
- [ ] **LINT-02**: Lint errors trigger auto-fix loop (max 3 attempts)
- [ ] **LINT-03**: After 3 failed attempts, pipeline stops and reports remaining errors
- [ ] **LINT-04**: `verilator --lint-only generated/*.v` produces no ERROR output on success
- [ ] **LINT-05**: Warnings are documented in verification report with explanations

### Testbench Generation

- [ ] **TB-01**: Agent generates C++ testbench with test vectors matching module operations
- [ ] **TB-02**: Testbench includes clock handling, input driving, and output checking
- [ ] **TB-03**: ALU testbench covers all 6 operations with at least 10 test cases
- [ ] **TB-04**: Testbench outputs formatted log: `[TEST N] OP: a=X b=Y | expect=Z got=W | PASS/FAIL`

### Simulation

- [ ] **SIM-01**: `scripts/simulate.sh` compiles testbench with Verilator and runs simulation
- [ ] **SIM-02**: Simulation produces `sim/logs/sim_result.log` in prescribed format
- [ ] **SIM-03**: Final line of sim_result.log shows `RESULT: PASSED X/Y tests` or `RESULT: FAILED`

### Hooks

- [ ] **HOOK-01**: `hooks/hooks.json` defines PostToolUse hooks for pipeline automation
- [ ] **HOOK-02**: Hooks use `${CLAUDE_PLUGIN_ROOT}` for all script paths
- [ ] **HOOK-03**: Hook matchers are precise (no infinite loops)

## v2 Requirements

### Extended Modules
- **EXT-01**: Support for sequential modules (register file, pipeline registers)
- **EXT-02**: Support for multi-module designs with inter-module wiring

### Enhanced Testing
- **TEST-01**: Automatic waveform generation (VCD) for debugging
- **TEST-02**: Coverage reporting for generated testbenches

### Distribution
- **DIST-01**: Published to npm registry as `chip-agent`
- **DIST-02**: Marketplace submission for Claude Code official marketplace

## Out of Scope

| Feature | Reason |
|---------|--------|
| FPGA synthesis | Beyond functional verification scope |
| Full CPU core generation | Pipeline targets individual modules |
| Non-RISC-V architectures | Scoped to RV32I ISA |
| GUI/web interface | CLI-only through Claude Code |
| RTL optimization/PPA | Beyond functional verification |
| ChiselSim/svsim testing path | Using external C++ testbench for prescribed output format |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| PLUG-01 | Phase 1 | Pending |
| PLUG-02 | Phase 1 | Pending |
| PLUG-03 | Phase 1 | Pending |
| PLUG-04 | Phase 1 | Pending |
| PLUG-05 | Phase 1 | Complete |
| BUILD-01 | Phase 1 | Complete |
| BUILD-02 | Phase 1 | Complete |
| BUILD-03 | Phase 1 | Complete |
| PARSE-01 | Phase 2 | Complete |
| PARSE-02 | Phase 2 | Complete |
| PARSE-03 | Phase 2 | Complete |
| GEN-01 | Phase 2 | Complete |
| GEN-02 | Phase 2 | Complete |
| GEN-03 | Phase 2 | Pending |
| GEN-04 | Phase 2 | Pending |
| LINT-01 | Phase 3 | Pending |
| LINT-02 | Phase 3 | Pending |
| LINT-03 | Phase 3 | Pending |
| LINT-04 | Phase 3 | Pending |
| LINT-05 | Phase 3 | Pending |
| HOOK-01 | Phase 3 | Pending |
| HOOK-02 | Phase 3 | Pending |
| HOOK-03 | Phase 3 | Pending |
| TB-01 | Phase 4 | Pending |
| TB-02 | Phase 4 | Pending |
| TB-03 | Phase 4 | Pending |
| TB-04 | Phase 4 | Pending |
| SIM-01 | Phase 4 | Pending |
| SIM-02 | Phase 4 | Pending |
| SIM-03 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 30 total
- Mapped to phases: 30
- Unmapped: 0

---
*Requirements defined: 2026-03-16*
*Last updated: 2026-03-16 after roadmap creation*
