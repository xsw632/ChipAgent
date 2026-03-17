# ChipAgent

ChipAgent is a Claude Code plugin that turns natural language hardware descriptions into simulation-verified Verilog. A single slash command (`/chip-agent:generate`) orchestrates the full pipeline: parse requirements, generate Chisel source, compile to SystemVerilog, lint, generate testbench, simulate, and report results.

## Tech Stack

| Component          | Version   | Purpose                                      |
|--------------------|-----------|----------------------------------------------|
| Chisel             | 7.2.0     | Hardware construction language (Scala DSL)    |
| Scala              | 2.13.17   | JVM language hosting Chisel                   |
| sbt                | latest    | Scala build tool                              |
| firtool            | auto      | FIRRTL-to-Verilog compiler (auto-managed)     |
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
- **Generated output:** `generated/` -- SystemVerilog files emitted by `ChiselStage.emitSystemVerilogFile`
- **Simulation logs:** `sim/logs/` -- Verilator simulation output and test reports
- **Build scripts:** `scripts/` -- bash scripts for compile, setup, lint, simulate
- **Plugin config:** `.claude-plugin/` -- plugin manifest and metadata

All generated `.sv` and `.v` files are gitignored. They are reproducible via `scripts/compile.sh`.

## Interface Specs

Query Context7 (`/chipsalliance/chisel`) for Chisel IO bundle syntax, port types, and directions.

**Verilog port naming:** Chisel wraps all ports in the `io` bundle, so Verilog ports become `io_<portName>`. For example, `io.inputPort` in Chisel becomes `io_inputPort` in the generated SystemVerilog. This matters for testbench generation.

## Build Commands

| Command                                          | Purpose                              |
|--------------------------------------------------|--------------------------------------|
| `scripts/compile.sh`                             | Compile Chisel to SystemVerilog      |
| `sbt --batch "runMain chipagent.Generate"`       | Direct sbt compilation               |
| `scripts/setup.sh`                               | First-use environment initialization |

**Important:** Always use the `--batch` flag with sbt in scripts to prevent interactive mode hangs.

## Context7 Documentation Lookup

When writing or modifying Chisel code, **always** query Context7 for up-to-date API usage before generating code:

```
Library ID: /chipsalliance/chisel
```

Use `mcp__plugin_context7_context7__query-docs` with this library ID to look up modules, IO bundles, operators, emission APIs, and any Chisel construct you are unsure about. This ensures generated code matches the actual Chisel 7.x API rather than relying on stale training data.

## Chisel API Rules (Pitfalls)

These are project-specific constraints that Context7 docs won't tell you. Violating them causes compilation failures.

1. **Emission API:** Use `ChiselStage.emitSystemVerilogFile` (`import circt.stage.ChiselStage`). Do NOT use `emitVerilog` -- it is deprecated and removed in Chisel 7.x. Query Context7 for exact usage.

2. **Dependency coordinates:** The correct dependency is `"org.chipsalliance" %% "chisel"`. Do NOT use `"edu.berkeley.cs" %% "chisel3"` -- that is the old, unmaintained package.

3. **firtool management:** Do NOT set `CHISEL_FIRTOOL_PATH`. The firtool binary is auto-managed by chisel's firtool-resolver. Setting this variable causes version conflicts and potential segfaults.

4. **sbt batch mode:** Always pass `--batch` to sbt in scripts. Without it, sbt enters interactive mode and scripts hang indefinitely.

## Pipeline Overview

The `/chip-agent:generate` command executes these stages:

1. **Parse Requirements** -- Extract module name, ports, operations, and constraints from natural language input
2. **Generate Chisel** -- Produce Chisel source code from the structured specification
3. **Compile to Verilog** -- Run sbt to compile Chisel through firtool into SystemVerilog
4. **Lint** -- Run Verilator lint-only checks on the generated Verilog
5. **Generate Testbench** -- Create a C++ testbench with test vectors for Verilator
6. **Simulate** -- Compile and run the testbench, collecting pass/fail results
7. **Report** -- Format simulation results into a verification report

Each stage feeds into the next. If any stage fails, the pipeline stops and reports the error with context for debugging.
