# Architecture Patterns

**Domain:** Automated Chisel-to-Verified-Verilog Pipeline (Claude Code Plugin)
**Researched:** 2026-03-16

## Recommended Architecture

The system is a **Claude Code plugin** that orchestrates a multi-stage hardware generation pipeline. It is NOT a traditional application -- it is a collection of markdown skills, JSON hook configurations, shell scripts, and a Chisel/sbt project template that Claude Code's agent infrastructure executes.

### Architecture Diagram

```
User invokes /chip:generate "RV32I ALU with ADD/SUB/AND/OR/XOR/SLT and zero flag"
    |
    v
[Skill: generate]  ---- reads SKILL.md, parses $ARGUMENTS
    |
    v
[Agent: requirement-parser]  ---- extracts module spec from NL
    |
    v
[Agent: chisel-generator]  ---- generates Chisel Scala source
    |
    v
[Script: compile.sh]  ---- sbt runMain => emitSystemVerilogFile
    |
    v
[Script: lint.sh]  ---- verilator --lint-only -Wall
    |                      |
    |              (errors found?)
    |                  yes |  no
    |                  v       v
    |     [Agent: lint-fixer]  (continue)
    |         (retry <= 3)
    |              |
    v              v
[Agent: testbench-generator]  ---- generates C++ testbench
    |
    v
[Script: simulate.sh]  ---- verilator --cc --exe --build && run
    |
    v
[Agent: report-generator]  ---- formats sim_result.log
    |
    v
Pipeline Complete -- outputs in generated/ and reports/
```

### Component Boundaries

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| `skills/generate/SKILL.md` | Entry point slash command; captures user NL description via $ARGUMENTS | Invokes agents sequentially |
| `agents/requirement-parser.md` | Parses NL into structured module spec (name, ports, operations, constraints) | Reads $ARGUMENTS, writes spec to `.planning/` or passes to next agent |
| `agents/chisel-generator.md` | Generates valid Chisel 7.x Scala source code from module spec | Reads spec, writes to `src/main/scala/` |
| `agents/lint-fixer.md` | Reads Verilator lint errors, determines fixes, regenerates Chisel | Reads lint output, modifies Chisel source, triggers recompilation |
| `agents/testbench-generator.md` | Generates C++ testbench with test vectors for the module | Reads module spec + generated Verilog ports, writes `testbench/tb_*.cpp` |
| `agents/report-generator.md` | Formats simulation output into prescribed sim_result.log format | Reads simulation stdout, writes `reports/sim_result.log` |
| `scripts/compile.sh` | Runs `sbt runMain` to compile Chisel and emit Verilog | Called by skill/hook; reads Chisel source, writes Verilog to `generated/` |
| `scripts/lint.sh` | Runs `verilator --lint-only` and captures output | Called by skill/hook; reads Verilog, writes lint report |
| `scripts/simulate.sh` | Compiles and runs Verilator simulation | Called by skill/hook; reads Verilog + testbench, produces simulation output |
| `hooks/hooks.json` | Event-driven automation triggers | PostToolUse on Write/Edit can trigger compile and lint scripts |
| Chisel sbt project | Template project for Chisel compilation | Contains build.sbt, src/, project/ |

### Data Flow

```
Natural Language Description
    |
    v
Module Specification (structured: name, ports[], operations[], constraints[])
    |
    v
Chisel Source (src/main/scala/chipagent/modules/<ModuleName>.scala)
    |
    v
Verilog Generator (src/main/scala/chipagent/Generate.scala -- uses ChiselStage.emitSystemVerilogFile)
    |
    v
FIRRTL (intermediate, handled by firtool internally)
    |
    v
Verilog Output (generated/<ModuleName>.v)
    |
    v
Lint Report (reports/lint_report.txt)
    |
    v
C++ Testbench (testbench/tb_<ModuleName>.cpp)
    |
    v
Simulation Binary (obj_dir/V<ModuleName>)
    |
    v
Simulation Output (stdout captured)
    |
    v
Verification Report (reports/sim_result.log)
```

## Project Directory Structure

```
chip-agent/                          # Plugin root
  .claude-plugin/
    plugin.json                      # Plugin manifest
  skills/
    generate/
      SKILL.md                       # /chip:generate entry point
  agents/
    requirement-parser.md            # NL -> module spec
    chisel-generator.md              # Module spec -> Chisel code
    lint-fixer.md                    # Lint error -> fix
    testbench-generator.md           # Module spec -> C++ testbench
    report-generator.md              # Sim output -> sim_result.log
  hooks/
    hooks.json                       # PostToolUse automation
  scripts/
    compile.sh                       # sbt runMain wrapper
    lint.sh                          # verilator --lint-only wrapper
    simulate.sh                      # verilator --cc --exe wrapper
  chisel-project/                    # Chisel/sbt project template
    build.sbt
    project/
      build.properties
    src/
      main/scala/chipagent/
        Generate.scala               # Verilog emission entry point
        modules/                     # Generated Chisel modules go here
      test/scala/chipagent/          # Optional: ChiselSim tests
  generated/                         # Verilog output directory
  testbench/                         # C++ testbench directory
  reports/                           # Lint reports and sim_result.log
  obj_dir/                           # Verilator build artifacts (gitignored)
```

## Patterns to Follow

### Pattern 1: Skill-Driven Pipeline Orchestration

**What:** The `/chip:generate` skill contains the full pipeline orchestration prompt. It describes the sequence of operations Claude should perform, referencing agents and scripts.

**When:** Always -- this is the entry point for all pipeline runs.

**Example SKILL.md structure:**
```markdown
---
name: generate
description: Generate verified Verilog from a natural language hardware description. Use when the user wants to create an RV32I module.
---

# Hardware Generation Pipeline

Given the description "$ARGUMENTS", execute this pipeline:

1. Parse the description into a structured module specification
2. Generate Chisel source code for the module
3. Compile Chisel to Verilog via sbt
4. Run Verilator lint checks
5. If lint errors: fix and retry (max 3 attempts)
6. Generate a C++ testbench
7. Run simulation
8. Produce verification report
```

### Pattern 2: Agent Specialization

**What:** Each pipeline stage gets its own agent with a focused system prompt and clear input/output contract.

**When:** For each stage that requires LLM reasoning (not shell scripting).

**Example agent frontmatter:**
```markdown
---
name: chisel-generator
description: Generates Chisel 7.x Scala source code from a structured module specification. Specializes in RV32I modules.
---
```

### Pattern 3: Script Automation via Hooks or Direct Invocation

**What:** Deterministic operations (sbt compile, verilator lint, verilator simulate) are shell scripts, not LLM-generated commands. This prevents non-determinism in build commands.

**When:** For all external tool invocations.

**Example compile.sh:**
```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../chisel-project"
sbt --batch "runMain chipagent.Generate" 2>&1
```

### Pattern 4: Structured Error Parsing for Auto-Fix

**What:** Verilator lint output is parsed into structured error objects (file, line, column, error code, message) that the lint-fixer agent can act on.

**When:** During the lint-fix loop.

**Example lint parsing:**
```bash
# lint.sh captures and formats errors
verilator --lint-only -Wall generated/*.v 2>&1 | grep -E "^%Error" > reports/lint_errors.txt
exit_code=${PIPESTATUS[0]}
```

### Pattern 5: Immutable Pipeline State

**What:** Each pipeline run produces artifacts in timestamped or versioned directories. Previous runs are not overwritten.

**When:** When running multiple pipeline iterations or debugging.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Monolithic Skill

**What:** Putting the entire pipeline logic in a single SKILL.md with 500+ lines.

**Why bad:** Claude's context window fills with instructions instead of actual pipeline data; harder to maintain and debug.

**Instead:** Use SKILL.md as an orchestrator that references specialized agents. Keep each agent focused on one stage.

### Anti-Pattern 2: LLM-Generated Build Commands

**What:** Having Claude generate `sbt runMain ...` or `verilator ...` commands dynamically.

**Why bad:** Non-deterministic; may produce wrong flags, wrong paths, or miss critical options. Build commands should be static.

**Instead:** Use pre-written shell scripts in `scripts/`. The LLM decides WHEN to call them, not HOW.

### Anti-Pattern 3: Inline Hooks for Complex Logic

**What:** Putting multi-line shell scripts directly in hooks.json `command` fields.

**Why bad:** Hard to debug, hard to test independently, character escaping issues.

**Instead:** Hooks call scripts: `"command": "${CLAUDE_PLUGIN_ROOT}/scripts/lint.sh"`.

### Anti-Pattern 4: Unbounded Fix Loop

**What:** Retrying lint fixes without a counter or exit condition.

**Why bad:** Can loop forever on unfixable errors; wastes API calls and time.

**Instead:** Hard limit of 3 attempts. After 3 failures, report the remaining errors and stop.

### Anti-Pattern 5: Verilog String Manipulation

**What:** Having the LLM edit generated Verilog directly to fix lint errors.

**Why bad:** Verilog is an output artifact. Fixing it at the Verilog level means fixes are lost on next compilation. The source of truth is Chisel.

**Instead:** Always fix at the Chisel source level. Regenerate Verilog from fixed Chisel.

## Scalability Considerations

| Concern | At 1 module (ALU) | At 5 modules | At 20+ modules |
|---------|-------------------|--------------|----------------|
| Build time | <30s (sbt incremental) | ~1-2min (sbt recompilation) | Extract modules into separate sbt subprojects |
| Verilator compilation | <5s | ~15s per module | Parallelize with make -j |
| Testbench complexity | ~50 test vectors | ~200 total | Consider test generation framework |
| Plugin size | Small (~20 files) | Medium (~40 files) | Consider breaking into sub-plugins per module type |
| Pipeline orchestration | Single skill | Parameterized skill | May need module-type-specific agents |

## Sources

- [Claude Code plugin structure](https://code.claude.com/docs/en/plugins-reference) -- Plugin directory layout, component types
- [Claude Code hooks guide](https://code.claude.com/docs/en/hooks-guide) -- Hook events, automation patterns
- [Claude Code skills docs](https://code.claude.com/docs/en/skills) -- Skill authoring, $ARGUMENTS, frontmatter
- [Claude Code subagents docs](https://code.claude.com/docs/en/sub-agents) -- Agent configuration
- [Chisel ChiselStage API](https://www.chisel-lang.org/api/latest/circt/stage/ChiselStage$.html) -- emitSystemVerilog, emitSystemVerilogFile
- [Verilator simulation guide](https://verilator.org/guide/latest/verilating.html) -- --lint-only, --cc, --exe, --build flags

---
*Architecture patterns for: ChipAgent -- Automated Chisel-to-Verified-Verilog Pipeline*
*Researched: 2026-03-16*
