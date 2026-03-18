# ChipAgent

ChipAgent is a Claude Code plugin that turns natural language hardware descriptions into simulation-verified Verilog. A single slash command (`/chip-agent:generate`) orchestrates the full pipeline: parse requirements, generate Chisel source, compile to SystemVerilog, lint, generate testbench, simulate, and report results.

## Tech Stack

| Component          | Version   | Purpose                                      |
|--------------------|-----------|----------------------------------------------|
| Chisel             | 3.6.1     | Hardware construction language (Scala DSL)    |
| Scala              | 2.13.10   | JVM language hosting Chisel (managed by sbt)  |
| sbt                | 1.10.7    | Scala build tool (pinned in build.properties) |
| FIRRTL             | built-in  | Chisel IR compiler (+ auto-managed firtool)   |
| Verilator          | 5.008+    | Verilog simulation and lint checking          |
| Claude Code Plugin | 0.1.0     | Plugin packaging and slash command framework  |

## Directory Structure

```
ChipAgent/
  .claude-plugin/
    plugin.json              # Plugin manifest (name, version, metadata)
  skills/
    generate.md              # /chip-agent:generate slash command entry point
  agents/                    # Subagent definitions (future phases)
  hooks/                     # PostToolUse automation hooks
  scripts/
    compile.sh               # sbt compilation wrapper
    setup.sh                 # First-use environment initialization
    lint.sh                  # Verilator lint checking (future)
    simulate.sh              # Verilator simulation runner (future)
  chisel-project/            # sbt project root
    build.sbt                # Project definition and dependencies
    project/
      plugins.sbt            # sbt plugins
    src/main/scala/chipagent/
      Generate.scala         # Verilog emission entry point
      TrivialModule.scala    # Verification module (Phase 1)
  generated/                 # Emitted SystemVerilog output
  sim/
    logs/                    # Simulation logs and verification reports
  CLAUDE.md                  # This file -- project rules for Claude
  package.json               # npm package definition for npx install
```

## File Path Conventions

- **Chisel source:** `chisel-project/src/main/scala/chipagent/` -- all Scala sources use `package chipagent`
- **Generated output:** `generated/` -- Verilog files emitted by `(new ChiselStage).emitVerilog`
- **Simulation logs:** `sim/logs/` -- Verilator simulation output and test reports
- **Build scripts:** `scripts/` -- bash scripts for compile, setup, lint, simulate
- **Plugin config:** `.claude-plugin/` -- plugin manifest and metadata

All generated `.sv` and `.v` files are gitignored. They are reproducible via `scripts/compile.sh`.

## Interface Specs

Query Context7 (`/chipsalliance/chisel`) for Chisel IO bundle syntax, port types, and directions.

**Verilog port naming:** Chisel wraps all ports in the `io` bundle, so Verilog ports become `io_<portName>`. For example, `io.inputPort` in Chisel becomes `io_inputPort` in the generated Verilog. This matters for testbench generation.

## Build Commands

| Command                                          | Purpose                              |
|--------------------------------------------------|--------------------------------------|
| `scripts/compile.sh`                             | Compile Chisel to Verilog            |
| `sbt --batch "runMain chipagent.Generate"`       | Direct sbt compilation               |
| `scripts/setup.sh`                               | First-use environment initialization |

**Important:** Always use the `--batch` flag with sbt in scripts to prevent interactive mode hangs.

## Context7 Documentation Lookup

When writing or modifying Chisel code, **always** query Context7 for up-to-date API usage before generating code:

```
Library ID: /chipsalliance/chisel
```

Use `mcp__plugin_context7_context7__query-docs` with this library ID to look up modules, IO bundles, operators, emission APIs, and any Chisel construct you are unsure about. This ensures generated code matches the actual Chisel 3.6.x API rather than relying on stale training data.

## Chisel API Rules (Pitfalls)

These are project-specific constraints that Context7 docs won't tell you. Violating them causes compilation failures.

1. **Emission API:** Use `(new chisel3.stage.ChiselStage).emitVerilog` (`import chisel3.stage.ChiselStage`). Do NOT use `circt.stage.ChiselStage` or `emitSystemVerilogFile` -- those require firtool/CIRCT which is not available with Chisel 3.x. Query Context7 for exact usage.

2. **Dependency coordinates:** The correct dependency is `"edu.berkeley.cs" %% "chisel3"`. Do NOT use `"org.chipsalliance" %% "chisel"` -- that is for Chisel 5.x+ which is a different version line.

3. **firtool is auto-managed:** Chisel 3.6.x auto-downloads firtool via firtool-resolver. Do NOT manually install or set `CHISEL_FIRTOOL_PATH`. The `emitVerilog` call produces both `.v` (FIRRTL backend) and `.sv` (firtool/CIRCT backend) files.

4. **sbt batch mode:** Always pass `--batch` to sbt in scripts. Without it, sbt enters interactive mode and scripts hang indefinitely.

5. **Scala version pinning:** Use Scala 2.13.10 exactly. The `chisel3-plugin` requires a `CrossVersion.full` match, so only specific Scala patch versions have published plugin artifacts. 2.13.10 is the recommended version for Chisel 3.6.x.

## Pipeline Overview

The `/chip-agent:generate` command executes these stages:

1. **Parse Requirements** -- Extract module name, ports, operations, and constraints from natural language input
2. **Generate Chisel** -- Produce Chisel source code from the structured specification
3. **Compile to Verilog** -- Run sbt to compile Chisel through FIRRTL/firtool into Verilog
4. **Lint** -- Run Verilator lint-only checks on the generated Verilog
5. **Generate Testbench** -- Create a C++ testbench with test vectors for Verilator
6. **Simulate** -- Compile and run the testbench, collecting pass/fail results
7. **Report** -- Format simulation results into a verification report

Each stage feeds into the next. If any stage fails, the pipeline stops and reports the error with context for debugging.
