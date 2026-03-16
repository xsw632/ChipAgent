# Phase 1 Research: Plugin Scaffold + Build Foundation

**Researched:** 2026-03-16
**Confidence:** HIGH
**Scope:** Claude Code plugin structure, sbt/Chisel project setup, build scripts, CLAUDE.md

## 1. Claude Code Plugin Structure

### Directory Layout
```
chip-agent/                    # Plugin root
  .claude-plugin/
    plugin.json                # Manifest (name, version, description)
  skills/
    generate.md                # /chip-agent:generate entry point
  agents/                      # Subagent definitions (future phases)
  hooks/
    hooks.json                 # PostToolUse automation
  scripts/
    compile.sh                 # sbt compilation wrapper
    setup.sh                   # First-use initialization
  chisel-project/              # sbt project lives here
    build.sbt
    project/plugins.sbt
    src/main/scala/chipagent/
      Generate.scala           # Verilog emission entry point
  CLAUDE.md                    # Project rules for Claude
```

### plugin.json Schema
```json
{
  "name": "chip-agent",
  "version": "0.1.0",
  "description": "Automated Chisel-to-Verilog pipeline",
  "metadata": {
    "description": "Turns NL hardware descriptions into simulation-verified Verilog"
  }
}
```

### Plugin Loading
- `claude --plugin-dir .` loads from local directory during development
- `/plugin validate .` checks structure
- `.claude-plugin/plugin.json` is the required manifest
- Skills, agents, hooks, scripts dirs are at plugin root (NOT inside `.claude-plugin/`)

### npx Installation (PLUG-03)
- Standard pattern: `package.json` with `"bin"` field pointing to install script
- Install script copies plugin files to `~/.claude/plugins/chip-agent/`
- Validate with `test -f ~/.claude/plugins/chip-agent/.claude-plugin/plugin.json`
- For dev: `claude --plugin-dir .` is sufficient

## 2. Chisel 7.x + sbt Project Setup

### build.sbt (verified against Chisel 7.2.0)
```scala
val chiselVersion = "7.2.0"

lazy val root = (project in file("."))
  .settings(
    name := "chip-agent-chisel",
    version := "0.1.0",
    scalaVersion := "2.13.16",
    libraryDependencies ++= Seq(
      "org.chipsalliance" %% "chisel" % chiselVersion
    ),
    addCompilerPlugin(
      "org.chipsalliance" % "chisel-plugin" % chiselVersion
        cross CrossVersion.full
    )
  )
```

**Critical:** Dependency is `org.chipsalliance::chisel`, NOT `edu.berkeley.cs::chisel3`.

### Generate.scala (Verilog emission)
```scala
package chipagent

import chisel3._
import circt.stage.ChiselStage

object Generate extends App {
  ChiselStage.emitSystemVerilogFile(
    new TrivialModule,
    Array("--target-dir", "generated"),
    Array("-disable-all-randomization", "-strip-debug-info")
  )
}
```

**Critical API facts:**
- Import: `import chisel3._` (correct for DSL), `import circt.stage.ChiselStage` (for emission)
- Use `emitSystemVerilogFile` (writes files) NOT `emitVerilog` (deprecated/removed)
- `args` parameter: Chisel args like `--target-dir`
- `firtoolOpts` parameter: CIRCT options like `-strip-debug-info`
- firtool is auto-managed by chisel's firtool-resolver — do NOT set `CHISEL_FIRTOOL_PATH`

### Trivial Module for Success Criterion #2
```scala
package chipagent

import chisel3._

class TrivialModule extends Module {
  val io = IO(new Bundle {
    val in  = Input(UInt(8.W))
    val out = Output(UInt(8.W))
  })
  io.out := io.in
}
```

## 3. Build Scripts

### scripts/compile.sh
Key requirements:
- Run `sbt --batch "runMain chipagent.Generate"` (--batch prevents interactive mode)
- Set `SBT_OPTS="-Dsbt.supershell=false"` for clean output
- Unset `CHISEL_FIRTOOL_PATH` to prevent version conflicts
- 120s timeout for first run (dependency download + firtool fetch)
- Capture stderr for error context (BUILD-03)
- Exit non-zero on failure with structured error output
- Check that `generated/*.sv` files exist after successful run

### scripts/setup.sh (PLUG-05)
- Initialize sbt project skeleton if not present
- Run `sbt update` to pre-download dependencies
- Create output directories (`generated/`, `sim/logs/`)
- Verify JDK, sbt, Verilator are available

## 4. Hooks Configuration

### hooks/hooks.json (minimal for Phase 1)
Phase 1 needs minimal hooks. The main hook concern is BUILD-02 (auto-compile after Chisel write):
- Matcher: `Write|Edit` on `src/main/scala/**/*.scala` only
- Use `${CLAUDE_PLUGIN_ROOT}` for script paths
- Script checks stdin JSON for file path; exits 0 early for non-Scala files
- 120s timeout for compilation

**Warning:** Do NOT hook on `generated/` writes or you get infinite loops.

## 5. CLAUDE.md Content (PLUG-04)

Must include:
- Project purpose and tech stack
- File path conventions (`chisel-project/src/...`, `generated/`, `scripts/`)
- Interface specs (module IO bundle conventions, port naming)
- Build commands (`scripts/compile.sh`, `sbt --batch "runMain ..."`)
- Chisel 7.x API rules (correct imports, emission API)
- Plugin structure overview

## 6. Phase 1 Pitfalls (from domain research)

| Risk | Impact | Mitigation |
|------|--------|------------|
| sbt cold start (30-120s) | Users think it's broken | Pre-download deps in setup.sh; 120s timeout |
| Wrong Chisel API in Generate.scala | Compilation fails | Pin `emitSystemVerilogFile` pattern |
| firtool version conflict | Segfaults or FIRRTL errors | Unset CHISEL_FIRTOOL_PATH in scripts |
| sbt interactive mode | Script hangs | Always use `--batch` flag |
| Hook event storms | Infinite loops | Narrow matchers; path checking in scripts |
| plugin.json schema error | Plugin won't load | Validate with `/plugin validate .` |

## 7. Validation Architecture

### Success Criteria Verification
1. **Plugin loads:** `claude --plugin-dir .` shows `/chip-agent:generate`
2. **Chisel compiles:** `scripts/compile.sh` exits 0 and `generated/*.sv` exists
3. **Error reporting:** Force a compilation error, verify `compile.sh` captures and reports it
4. **CLAUDE.md:** File exists with required sections

### Test Strategy
- Manual: Load plugin, run slash command, verify it appears
- Script: `scripts/compile.sh && test -f generated/TrivialModule.sv`
- Error path: Introduce syntax error in Scala, verify compile.sh reports it with context

## Sources

- [Chisel 7.x API - ChiselStage](https://www.chisel-lang.org/api/latest/circt/stage/ChiselStage$.html)
- [Chisel FAQ](https://www.chisel-lang.org/docs/resources/faqs)
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Claude Code Plugins Reference](https://code.claude.com/docs/en/plugins-reference)
- [Plugin Marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)

---
*Phase 1 research for: ChipAgent*
*Researched: 2026-03-16*
