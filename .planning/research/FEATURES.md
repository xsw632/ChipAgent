# Feature Landscape

**Domain:** Automated Chisel-to-Verified-Verilog Pipeline (Claude Code Plugin)
**Researched:** 2026-03-16

## Table Stakes

Features users expect. Missing = pipeline feels broken.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Natural language to module specification parsing | Core promise of the tool -- users describe hardware in English | Medium | Claude handles NL parsing natively; the skill needs structured output format (module name, ports, operations) |
| Chisel source code generation from specification | Primary pipeline output -- no code generation means no pipeline | High | Must produce valid Chisel 7.x code using `circt.stage.ChiselStage`; template-based generation for RV32I modules |
| Automatic FIRRTL-to-Verilog compilation | Users expect seamless compilation, not manual sbt invocation | Medium | `sbt runMain` triggers `ChiselStage.emitSystemVerilogFile`; firtool auto-managed |
| Verilator lint checking with error reporting | Lint is the minimum quality gate before simulation | Low | `verilator --lint-only -Wall generated/*.v`; parse stdout/stderr for ERRORS vs WARNINGS |
| Auto-fix loop for lint errors (up to 3 attempts) | Stated requirement; differentiates from manual workflow | High | Agent reads lint errors, modifies Chisel source, recompiles, re-lints; needs structured error parsing |
| Testbench generation | Simulation requires test vectors; manual creation defeats purpose | High | Generate C++ testbench with comprehensive test cases based on module functionality |
| Simulation execution | End-to-end verification requires actual simulation runs | Medium | `verilator --cc --exe --build` then execute binary; capture stdout |
| Verification report (sim_result.log) | Prescribed output format; acceptance criterion | Low | Format: `[TEST N] OP: a=X b=Y \| expect=Z got=W \| PASS/FAIL` |
| Slash command entry point | Explicit trigger mechanism required by project spec | Low | `/chip:generate` skill in `skills/generate/SKILL.md` |
| Zero human intervention after invocation | Core value proposition -- fully automatic pipeline | High | Skills chain through agents; hooks automate compilation steps |

## Differentiators

Features that set product apart. Not expected, but valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Multiple RV32I module support | Generic pipeline, not just ALU | Medium | Decoder, register file, control unit, immediate generator |
| Waveform generation (VCD) | Debugging aid for failed tests | Low | `verilator --trace` flag; produces VCD files viewable in GTKWave |
| Configurable module parameters | Parameterized Chisel generators (e.g., data width, register count) | Medium | Leverage Chisel's Scala parameterization; parse from NL description |
| Structured error reporting | Clear feedback when pipeline fails at any stage | Low | JSON or formatted log output at each pipeline stage |
| Pipeline stage timing report | Shows how long each stage took (compilation, lint, simulation) | Low | Timestamp each stage in hook scripts |
| Test coverage reporting | Quantify how many operations/edge cases are tested | Medium | Count test vectors, track pass/fail ratios in sim_result.log |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Full CPU core generation | Out of scope; pipeline targets individual functional modules | Support individual modules that could compose into a CPU later |
| FPGA synthesis flow | Pipeline ends at functional simulation; no place-and-route | Stop at simulation-verified Verilog; document the boundary clearly |
| Non-RISC-V architectures | Scoped to RV32I ISA per project spec | Validate generated code against RV32I standard only |
| GUI/web interface | CLI-only through Claude Code per project spec | Use slash commands and structured terminal output |
| Real-time interactive simulation | Overkill for module-level verification | Batch simulation with complete test vectors |
| Multi-file module generation | Complexity explosion; single-file modules are sufficient for RV32I | Generate one .scala file per module, one .v output |
| SystemVerilog assertions (SVA) | Verilator 5.008 has limited SVA support; adds complexity | Use C++ testbench assertions with clear pass/fail output |

## Feature Dependencies

```
NL Parsing -> Module Specification -> Chisel Generation -> FIRRTL Compilation -> Verilog Output
                                                                                      |
                                                                                      v
                                                                              Verilator Lint
                                                                                      |
                                                                              (auto-fix loop)
                                                                                      |
                                                                                      v
                                                                           Testbench Generation
                                                                                      |
                                                                                      v
                                                                              Simulation Run
                                                                                      |
                                                                                      v
                                                                          Verification Report
```

Key dependencies:
- Chisel Generation requires a valid Module Specification (ports, operations, constraints)
- FIRRTL Compilation requires valid Chisel source AND sbt project setup
- Lint checking requires Verilog output from firtool
- Auto-fix requires both lint error parsing AND Chisel regeneration capability
- Testbench generation requires knowledge of module ports AND expected behavior
- Simulation requires both compiled Verilog AND compiled C++ testbench

## MVP Recommendation

Prioritize for acceptance test (ALU with ADD/SUB/AND/OR/XOR/SLT + zero flag):

1. **Plugin scaffolding** -- plugin.json, skills, hooks, agents directory structure
2. **Chisel project template** -- build.sbt, source directories, generation entry point
3. **ALU Chisel generation** -- Hardcoded for RV32I ALU as proof of concept
4. **sbt compilation + Verilog emission** -- Automated via hook or script
5. **Verilator lint** -- `--lint-only` check with error parsing
6. **Auto-fix loop** -- Parse lint errors, regenerate, retry up to 3 times
7. **C++ testbench generation** -- Test vectors for all ALU operations
8. **Simulation + report** -- Run simulation, produce sim_result.log

Defer:
- **Multiple module types**: After ALU acceptance test passes; same pipeline, different Chisel templates
- **Parameterized modules**: After basic generation works; add width/depth parameters
- **Waveform generation**: Nice-to-have; add `--trace` flag to Verilator call
- **Test coverage reporting**: After basic sim_result.log works

## Sources

- [ChipAgent PROJECT.md](/home/mingzhenjia/ChipAgent/.planning/PROJECT.md) -- Project requirements and constraints
- [Chisel testing docs](https://www.chisel-lang.org/docs/explanations/testing) -- svsim and ChiselSim patterns
- [Verilator documentation](https://verilator.org/guide/latest/verilating.html) -- Lint and simulation workflow
- [Claude Code plugin docs](https://code.claude.com/docs/en/plugins) -- Plugin component capabilities

---
*Feature landscape for: ChipAgent -- Automated Chisel-to-Verified-Verilog Pipeline*
*Researched: 2026-03-16*
