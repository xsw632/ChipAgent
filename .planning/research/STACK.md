# Stack Research

**Domain:** Automated Chisel-to-Verified-Verilog Pipeline (Claude Code Plugin)
**Researched:** 2026-03-16
**Confidence:** HIGH (most versions verified against installed system and official sources)

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Chisel (Scala HDL) | 7.2.0+ (latest 7.x) | Hardware description language for RTL generation | Course requirement; de facto standard for parameterized RTL generation in the RISC-V ecosystem; used by Rocket Chip, Google TPUs; Chisel 7 is the current stable line with semantic versioning since 5.0 |
| Scala | 2.13.16 | Host language for Chisel | Required by Chisel 7.x; Scala 2.13 is the stable target (Chisel also cross-builds to Scala 3, but 2.13 has the most tested ecosystem support) |
| sbt | 1.10.7 (installed) | Scala build tool | Already installed on target machine; sbt 2.0 is RC-only and requires JDK 17+ (which we have), but 1.10.x is stable and well-tested with Chisel templates |
| firtool (CIRCT) | Auto-managed by Chisel 7.x | FIRRTL-to-Verilog compiler | Since Chisel 6.0, firtool is auto-resolved and downloaded by the Chisel build; no separate install needed. The chisel-plugin + firtool-resolver handles version matching automatically |
| Verilator | 5.008 (installed) | Verilog lint checker and cycle-accurate simulator | Already installed; used for `--lint-only` checks and C++ testbench simulation; v5.008 is older but sufficient for basic lint and simulation of single-module designs |
| Node.js | 24.14.0 (installed) | Runtime for Claude Code plugin installer and hook scripts | Required for npm packaging; already installed via nvm |
| Java (OpenJDK) | 17.0.18 (installed) | JVM runtime for Scala/sbt/Chisel | JDK 17 is the current LTS; required by sbt and Chisel |

### Plugin Infrastructure

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Claude Code Plugin System | 2.1.76+ | Plugin packaging and distribution | Official plugin architecture with skills, hooks, agents, and MCP servers; supports namespace-scoped slash commands (e.g., `/chip:generate`) |
| plugin.json manifest | 1.0 schema | Plugin metadata and component paths | Required by Claude Code; defines name, version, component locations |
| skills/ with SKILL.md | Current spec | Slash command definitions | Skills are the modern replacement for commands/; support $ARGUMENTS, frontmatter metadata, and auto-invocation |
| hooks/hooks.json | Current spec | Event-driven automation (compile, lint, fix) | PostToolUse hooks can trigger sbt compilation, firtool conversion, and Verilator lint after file writes |
| agents/ (Markdown) | Current spec | Specialized subagents for pipeline stages | Agents handle requirement parsing, code generation, testbench creation, and fix iteration |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| chisel-plugin (Scalac) | Same as Chisel (7.2.0+) | Compiler plugin for Chisel DSL | Always; required for Chisel compilation -- added via `addCompilerPlugin` in build.sbt |
| svsim (bundled with Chisel) | Bundled | Low-level SystemVerilog simulation control | For programmatic Verilator/VCS simulation from Scala tests; targets Verilator backend |
| ScalaTest | 3.2.x | Scala testing framework | For sbt-based unit tests of Chisel generators; included in chisel-template |
| circt.stage.ChiselStage | Part of Chisel | Programmatic Verilog emission API | For emitting SystemVerilog from Chisel modules via `emitSystemVerilog` and `emitSystemVerilogFile` |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| sbt | Build, compile, run Chisel projects | Use `sbt runMain` to invoke Verilog generation; `sbt test` for ChiselSim tests |
| verilator --lint-only | Fast syntax and lint checking | Use `-Wall` for comprehensive warnings; `--bbox-sys` and `--bbox-unsup` for partial designs |
| verilator --cc / --binary | C++ testbench compilation | Generate standalone simulation executables from Verilog + C++ testbench |
| jq | JSON parsing in hook scripts | Hooks receive JSON on stdin; jq extracts fields like file paths |
| bash / shell scripts | Hook and automation scripts | Hooks execute shell commands; scripts in `scripts/` directory |

## Installation

### Chisel Project Setup (build.sbt)

```scala
// build.sbt
scalaVersion := "2.13.16"
val chiselVersion = "7.2.0"
addCompilerPlugin("org.chipsalliance" % "chisel-plugin" % chiselVersion cross CrossVersion.full)
libraryDependencies += "org.chipsalliance" %% "chisel" % chiselVersion
libraryDependencies += "org.scalatest" %% "scalatest" % "3.2.19" % "test"
```

```properties
# project/build.properties
sbt.version=1.10.7
```

### Plugin Package Setup

```bash
# No npm dependencies needed for the plugin itself.
# The plugin is a directory of markdown, JSON, and shell scripts.
# npm is used only for distribution packaging.

# Plugin structure (no npm install required for runtime):
mkdir -p chip-agent/.claude-plugin
mkdir -p chip-agent/skills
mkdir -p chip-agent/agents
mkdir -p chip-agent/hooks
mkdir -p chip-agent/scripts
```

### Verilog Generation Command

```bash
# From within the Chisel sbt project:
sbt "runMain chipagent.GenerateVerilog"

# Lint the generated Verilog:
verilator --lint-only -Wall generated/*.v

# Simulate with C++ testbench:
verilator --cc --exe --build -Wall generated/ALU.v testbench/tb_ALU.cpp -o sim_ALU
./obj_dir/sim_ALU
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Chisel 7.x (Scala 2.13) | Chisel on Scala 3 | When Scala 3 ecosystem matures further for Chisel; currently 2.13 has more community examples and stability |
| sbt 1.10.x | Mill | Mill has simpler syntax and is recommended by Chisel team; use when starting fresh without existing sbt infrastructure. We use sbt because it is already installed and the course environment expects it |
| sbt 1.10.x | sbt 2.0.0-RC | When sbt 2.0 reaches stable release; currently RC stage, not suitable for coursework |
| Verilator C++ testbench | ChiselSim (svsim) | For Scala-level simulation tests that don't need external C++ testbench files; better for unit testing within sbt. We use Verilator directly because the project requires explicit testbench generation and sim_result.log output |
| Verilator | Icarus Verilog | When Verilator is not available; Icarus is simpler but 100x slower. Verilator is already installed |
| Claude Code native plugin | npm installer (GSD pattern) | GSD uses a custom npx installer that copies files to ~/.claude/. Claude Code's native plugin system is now mature (public beta) and supports direct installation via `/plugin install` from marketplaces or `--plugin-dir` for development. Use the native plugin system |
| skills/ directory | commands/ directory | commands/ is legacy; skills/ is the modern approach with SKILL.md frontmatter, auto-invocation, and better agent integration |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| chiseltest (Chisel 6 and below) | Deprecated in favor of svsim/ChiselSim for Chisel 7 | svsim (bundled with Chisel) or direct Verilator C++ testbenches |
| Old Scala FIRRTL compiler | Replaced by CIRCT/firtool since Chisel 3.6; the old Scala FIRRTL compiler is vestigial | firtool via CIRCT (auto-managed by Chisel 6+) |
| chisel3 artifact name | Since Chisel 5.0, the Maven artifact changed from `edu.berkeley.cs::chisel3` to `org.chipsalliance::chisel` | Use `org.chipsalliance::chisel` |
| emitVerilog API | Removed in recent Chisel; causes "not a member" errors | Use `emitSystemVerilog` or `emitSystemVerilogFile` from `circt.stage.ChiselStage` |
| Manual firtool installation | Chisel 6+ auto-manages firtool binary download and version matching | Let Chisel's firtool-resolver handle it; override only with `CHISEL_FIRTOOL_PATH` if needed |
| npm runtime dependencies | Claude Code plugins are static files (markdown, JSON, shell scripts), not Node.js programs | Plugin is a directory of config files; npm is only for distribution packaging |
| Interactive sbt shell | Claude Code hooks run non-interactive commands; sbt shell requires stdin | Use `sbt --batch "runMain ..."` or `sbt "runMain ..."` for non-interactive execution |

## Stack Patterns by Variant

**If distributing via Claude Code marketplace:**
- Use native plugin system with `.claude-plugin/plugin.json` manifest
- Register in a `marketplace.json` Git repository
- Users install via `/plugin install chip-agent@marketplace-name`
- Because this is the officially supported distribution path

**If distributing via npm (like GSD):**
- Use `npx chip-agent@latest` with a custom installer script
- Installer copies files to `~/.claude/commands/`, `~/.claude/agents/`, etc.
- Commands get short names like `/chip:generate` instead of namespaced plugin names
- Because npm distribution predates the plugin system and allows more custom installation logic

**If the user wants Scala-level simulation tests:**
- Use ChiselSim/svsim within `sbt test`
- Write ScalaTest specs that poke/peek/step Chisel modules
- Because it integrates directly with sbt and avoids external C++ testbench files

**If the user wants external C++ testbenches (our case):**
- Generate Verilog with `sbt runMain`, then verilate with `verilator --cc --exe`
- Write C++ testbenches that eval() the design and produce structured output
- Because the project requires explicit sim_result.log output formatting

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| Chisel 7.2.0 | Scala 2.13.16 | Cross-builds to 2.13 and 3.x; 2.13 recommended for stability |
| Chisel 7.2.0 | firtool auto-managed | Chisel resolves the correct firtool version automatically via firtool-resolver |
| Chisel 7.2.0 | sbt 1.10.7 | Fully compatible; uses standard sbt plugin mechanism |
| sbt 1.10.7 | JDK 17+ | JDK 17 LTS is installed and meets all requirements |
| Verilator 5.008 | Verilog output from firtool | Older but handles standard Verilog from Chisel/firtool; no SystemVerilog-2023 features needed for RV32I modules |
| Claude Code 2.1.76 | Plugin system (public beta) | Supports skills, hooks, agents, MCP servers, and LSP servers |
| Node.js 24.14.0 | npm 11.9.0 | Current LTS; fully supports modern npm packaging |

## Environment Status (Verified on Target Machine)

| Tool | Status | Path | Version |
|------|--------|------|---------|
| sbt | Installed | /usr/bin/sbt | 1.10.7 |
| Scala | Installed | /usr/bin/scala | 2.13.13 (sbt will use 2.13.16 per build.sbt) |
| Java | Installed | system | OpenJDK 17.0.18 |
| firtool | NOT installed (auto-managed by Chisel) | -- | Auto-resolved by Chisel build |
| Verilator | Installed | /usr/local/bin/verilator | 5.008 (2023-03-04) |
| Node.js | Installed | ~/.nvm/versions/node/v24.14.0/bin/node | 24.14.0 |
| npm | Installed | -- | 11.9.0 |
| Claude Code | Installed | -- | 2.1.76 |

### IMPORTANT: Verilator Version Note

The installed Verilator (5.008) is from March 2023 -- roughly 3 years old. The latest is 5.046 (Feb 2026). For this project (single RV32I modules, basic lint, simple simulation), 5.008 is sufficient. However, some newer lint warnings and SystemVerilog features will not be available. This is acceptable for the course assignment scope.

## Sources

- [Chisel GitHub releases](https://github.com/chipsalliance/chisel/releases) -- Chisel 7.9.0 latest, 7.2.0 stable (HIGH confidence)
- [Chisel official site](https://www.chisel-lang.org/) -- Installation and API docs (HIGH confidence)
- [Scaladex - Chisel](https://index.scala-lang.org/chipsalliance/chisel) -- Confirmed Scala 2.13.16 + Chisel 7.2.0 build.sbt (HIGH confidence)
- [CIRCT/firtool releases](https://github.com/llvm/circt/releases) -- firtool-1.142.0 latest (HIGH confidence)
- [Chisel installation docs](https://www.chisel-lang.org/docs/installation) -- firtool auto-management since Chisel 6.0 (HIGH confidence)
- [Verilator documentation](https://verilator.org/guide/latest/) -- v5.046, --lint-only usage (HIGH confidence)
- [Claude Code plugin docs](https://code.claude.com/docs/en/plugins) -- Plugin structure, skills, hooks, agents (HIGH confidence)
- [Claude Code plugins reference](https://code.claude.com/docs/en/plugins-reference) -- Full manifest schema, hook events (HIGH confidence)
- [sbt official site](https://www.scala-sbt.org/) -- sbt 1.10.x stable, 2.0.0-RC (MEDIUM confidence)
- [chipsalliance/chisel-template](https://github.com/chipsalliance/chisel-template) -- Reference build.sbt configuration (HIGH confidence)
- Installed tool versions verified via local CLI commands (HIGH confidence)

---
*Stack research for: ChipAgent -- Automated Chisel-to-Verified-Verilog Pipeline*
*Researched: 2026-03-16*
