# ChipAgent

Claude Code plugin that turns natural language hardware descriptions into simulation-verified Verilog.

## Tech Stack

| Component          | Version   | Purpose                                      |
|--------------------|-----------|----------------------------------------------|
| Chisel             | 3.6.1     | Hardware construction language (Scala DSL)    |
| Scala              | 2.13.10 (pinned in build.sbt) | JVM language hosting Chisel (managed by sbt) |
| sbt                | 1.10.7    | Scala build tool (pinned in build.properties) |
| FIRRTL             | built-in  | Chisel 3.6 IR compiler   |
| Verilator          | detected     | Verilog simulation and lint checking          |
| sky130hd PDK       | -         | Open-source standard cell library (SkyWater)  |
| MCP Server         | 0.1.0     | Backend tool server for ORFS flow             |
| @modelcontextprotocol/sdk | 1.29.0 | MCP protocol SDK for TypeScript            |
| Claude Code Plugin | 0.1.0     | Plugin packaging and slash command framework  |

## Directory Structure

```
  chisel-project/              # Shared: all module Scala source lives here
  MyDesign/                    # Project container (all generated modules)
  ├── ALU8/                    # Per-module project folder (example)
  │   ├── chisel-project/      
  │   └── workspace/
  │       ├── generated/       # compiled Verilog output
  │       ├── sim/
  │       │   ├── tb_ALU8.cpp
  │       │   └── logs/
  │       │       ├── sim_result.log
  │       │       └── ALU8.vcd
  │       └── spec.json
  ├── ALU4/
  │   ├── chisel-project/      # symlink → ../../chisel-project
  │   └── workspace/
  └── PriorityEncoder4/
      ├── chisel-project/
      └── workspace/
```

**Per-module project structure:** All modules live inside the `MyDesign/` container folder. Each module gets its own sub-folder (PascalCase, e.g. `MyDesign/ALU8/`). Inside, `chisel-project/` is a symlink to `../../chisel-project`, keeping all Scala source in one shared directory. The `workspace/` subdirectory holds generated artifacts unique to that module.

## Build Commands

| Command                                          | Purpose                              |
|--------------------------------------------------|--------------------------------------|
| `scripts/compile.sh <ModuleName>`                 | Compile Chisel to Verilog            |
| `sbt --batch "runMain chipagent.Generate --module ALU"`        | Direct sbt compilation               |
| `scripts/setup.sh`                               | First-use environment initialization  |

## Chisel API Rules

1. **Emission API:** Use `(new chisel3.stage.ChiselStage).emitVerilog`. Do NOT use `circt.stage.ChiselStage` or `emitSystemVerilogFile`.
2. **Dependency coordinates:** Use `"edu.berkeley.cs" %% "chisel3"`. NOT `"org.chipsalliance" %% "chisel"` (that's Chisel 5.x).
3. **sbt batch mode:** Always pass `--batch` to sbt to prevent interactive mode hangs.
4. **Scala version:** Use 2.13.10 exactly (`chisel3-plugin` requires `CrossVersion.full` match).
5. **Verilog port naming:** Chisel `io.portName` becomes `io_portName` in generated Verilog.

## Context7

Query Context7 (`/chipsalliance/chisel`) for up-to-date Chisel API usage before generating code.
