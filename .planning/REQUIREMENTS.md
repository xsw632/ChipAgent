# Requirements: ChipAgent v1.3

**Defined:** 2026-04-14
**Core Value:** A single slash command turns a natural language hardware description into lint-clean, simulation-verified Verilog -- and a second command extends it through synthesis, PnR, and GDS export with intelligent failure handling. v1.3 adds Chipyard integration for complete processor RTL generation.

## v1.3 Requirements

### Environment & Initialization (ENV)

- [ ] **ENV-01**: `/chip-agent:initialize` detects Chipyard installation (local path vs Docker), validates `build.sbt` and RISCV toolchain existence
- [ ] **ENV-02**: Environment detection results written to `.chipagent/env.json` including Chipyard path, RISCV path, and `can_chipyard` capability flag
- [ ] **ENV-03**: `detect-env.sh` script extended with Chipyard directory and RISCV toolchain detection logic

### Chipyard RTL Generation (CYR)

- [ ] **CYR-01**: `/chip-agent:chipyard <config>` accepts config name argument (e.g. `tinyrocket`), auto-maps to `TinyRocketConfig` class name
- [ ] **CYR-02**: Skill resolves Chipyard path from env.json or `--chipyard` flag, validates environment (sbt, firtool, Java, RISCV) and config class existence
- [ ] **CYR-03**: Runs `make verilog CONFIG=<ConfigName>` in Chipyard to generate Verilog RTL, with 10-30 minute timeout handling
- [ ] **CYR-04**: Locates generated artifacts (gen-collateral directory), counts Verilog files, identifies key modules (ChipTop, Rocket, RocketTile, ICache, DCache)
- [ ] **CYR-05**: Concatenates split SV files into single .v file, saves to `MyDesign/<Config>/workspace/generated/<Config>.v` for ORFS compatibility
- [ ] **CYR-06**: Displays generation summary: config name, output path, file count, top module, mems.conf contents

### SRAM Mapping Analysis (SRM)

- [ ] **SRM-01**: `/chip-agent:sram-mapping <verilog_path>` scans Verilog for SRAM macro instances (reg arrays, mems.conf, rf_combMem, ram_combMem)
- [ ] **SRM-02**: Traces instantiation hierarchy for each memory module (leaf to ChipTop)
- [ ] **SRM-03**: Enumerates available sky130hd SRAM macros, computes best mapping strategy per memory
- [ ] **SRM-04**: Generates formatted mapping report and `sram_mapping.json` for downstream reference

### End-to-End Integration (E2E)

- [ ] **E2E-01**: tinyRocket end-to-end validation: `/chip-agent:chipyard tinyrocket` produces Verilog that `/chip-agent:pnr TinyRocketConfig` can process through full ORFS flow
- [ ] **E2E-02**: `/chip-agent:chipyard` completion prompts user to run SRAM mapping and PnR as next steps

## Deferred Requirements

### SRAM Macro Integration

- **SMI-01**: Black-box SRAM wrapper generation for macro instances
- **SMI-02**: LEF/Liberty integration for sky130 SRAM macros in ORFS flow
- **SMI-03**: Multi-macro tiling with address decode and data mux wrappers

### Docker Chipyard

- **DCK-01**: Docker-based Chipyard execution with container orchestration
- **DCK-02**: Docker image build and management for Chipyard environment

### Advanced Features

- **ADV-01**: Multi-config batch generation (generate multiple configs in sequence)
- **ADV-02**: Chipyard config auto-discovery and suggestion based on user requirements
- **ADV-03**: Verilator lint on generated Chipyard RTL

## Out of Scope

| Feature | Reason |
|---------|--------|
| Chipyard source modification | Only use existing configs to generate RTL, no custom Chisel |
| Verilator lint/simulation on Chipyard RTL | Generated RTL is too large for Verilator lint; Chipyard has its own verification |
| SRAM macro instantiation | Requires LEF/Liberty integration beyond current ORFS setup |
| Non-sky130hd SRAM mapping | Single PDK scope; other processes deferred |
| Custom Rocket Chip configurations | Only support pre-defined configs (TinyRocketConfig, etc.) |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| ENV-01 | Phase 18 | Pending |
| ENV-02 | Phase 18 | Pending |
| ENV-03 | Phase 18 | Pending |
| CYR-01 | Phase 19 | Pending |
| CYR-02 | Phase 19 | Pending |
| CYR-03 | Phase 19 | Pending |
| CYR-04 | Phase 19 | Pending |
| CYR-05 | Phase 19 | Pending |
| CYR-06 | Phase 19 | Pending |
| SRM-01 | Phase 20 | Pending |
| SRM-02 | Phase 20 | Pending |
| SRM-03 | Phase 20 | Pending |
| SRM-04 | Phase 20 | Pending |
| E2E-01 | Phase 21 | Pending |
| E2E-02 | Phase 21 | Pending |

**Coverage:**
- v1.3 requirements: 15 total
- Mapped to phases: 15
- Unmapped: 0 ✓

---
*Requirements defined: 2026-04-14*
*Last updated: 2026-04-14 after initial definition*
