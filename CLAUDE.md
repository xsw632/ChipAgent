# ChipAgent

Claude Code plugin that turns natural language hardware descriptions into simulation-verified Verilog.

- `/chip-agent:generate` -- Chisel-only: parse requirements, confirm spec, generate Scala source
- `/chip-agent:workflow` -- Full pipeline: parse, generate, compile, lint, testbench, simulate, report

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
  .claude-plugin/plugin.json
  skills/
    generate/SKILL.md          # /chip-agent:generate (Chisel-only)
    workflow/SKILL.md          # /chip-agent:workflow (full pipeline)
  agents/
  scripts/
    compile.sh, setup.sh, lint.sh, simulate.sh
  chisel-project/
    build.sbt
    src/main/scala/chipagent/
      Generate.scala
  generated/                   # Emitted Verilog (gitignored)
  sim/logs/
  package.json
```

## Build Commands

| Command                                          | Purpose                              |
|--------------------------------------------------|--------------------------------------|
| `scripts/compile.sh`                             | Compile Chisel to Verilog            |
| `sbt --batch "runMain chipagent.Generate"`       | Direct sbt compilation               |
| `scripts/setup.sh`                               | First-use environment initialization |

## Chisel API Rules

1. **Emission API:** Use `(new chisel3.stage.ChiselStage).emitVerilog`. Do NOT use `circt.stage.ChiselStage` or `emitSystemVerilogFile`.
2. **Dependency coordinates:** Use `"edu.berkeley.cs" %% "chisel3"`. NOT `"org.chipsalliance" %% "chisel"` (that's Chisel 5.x).
3. **firtool is auto-managed:** Do NOT manually install or set `CHISEL_FIRTOOL_PATH`.
4. **sbt batch mode:** Always pass `--batch` to sbt to prevent interactive mode hangs.
5. **Scala version:** Use 2.13.10 exactly (`chisel3-plugin` requires `CrossVersion.full` match).
6. **Verilog port naming:** Chisel `io.portName` becomes `io_portName` in generated Verilog.

## Context7

Query Context7 (`/chipsalliance/chisel`) for up-to-date Chisel API usage before generating code.

## Commands

- `/chip-agent:generate <description>` -- Produces Chisel source files only (steps 1-2). No compilation or verification.
- `/chip-agent:workflow <description>` -- Runs the full 7-step pipeline: parse, generate, compile, lint, testbench, simulate, report. Each stage feeds into the next; failures stop the pipeline with context for debugging.
