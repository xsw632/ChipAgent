# Architecture Patterns

**Domain:** Modular Slash Commands + Workspace Isolation for ChipAgent v1.1
**Researched:** 2026-03-19
**Confidence:** HIGH (based on official Claude Code docs, existing codebase analysis, verified plugin mechanics)

## Current Architecture (v1.0 Baseline)

Before defining the target architecture, here is what exists today and what each component does.

### Current Component Map

```
ChipAgent/                         (PLUGIN_ROOT)
  .claude-plugin/plugin.json       Plugin manifest (name: chip-agent)
  skills/
    generate.md                    Monolithic skill = /chip-agent:generate
  agents/
    requirement-parser.md          NL -> JSON spec
    chisel-generator.md            JSON spec -> Chisel Scala source
    testbench-generator.md         JSON spec -> C++ testbench
  hooks/
    hooks.json                     PostToolUse: Write|Edit -> compile.sh
  scripts/
    compile.sh                     sbt -> generated/ (flat)
    lint.sh                        verilator --lint-only on generated/*.v
    simulate.sh                    verilator --cc --exe -> sim/obj_dir/
    setup.sh                       Check prerequisites, pre-download deps
  chisel-project/
    build.sbt                      Chisel 3.6.1, Scala 2.13.10
    src/main/scala/chipagent/
      Generate.scala               Match on module name, emit to --target-dir
      ALU.scala                    Example module
      Decoder3to8.scala            Example module
      TrivialModule.scala          Verification module
  generated/                       FLAT -- all .v, .fir, .anno.json files
  sim/
    tb_ALU.cpp                     FLAT -- all testbenches
    tb_Decoder3to8.cpp
    obj_dir/                       Verilator build artifacts (shared)
    logs/
      sim_result.log               SINGLE file -- last module's results only
```

### Current Problems Driving v1.1

| Problem | Impact | Root Cause |
|---------|--------|------------|
| Monolithic generate.md (170 lines) | All 7 pipeline stages in one prompt; wastes context on stages not currently executing | No skill decomposition |
| Flat generated/ directory | ALU.v and Decoder3to8.v collide; lint-warnings.log is overwritten per run | No per-module output isolation |
| Single sim_result.log | Only records last module's simulation; no history | No per-module sim isolation |
| shared obj_dir/ | Verilator build artifacts from Module A pollute Module B's build | Single obj_dir path |
| Generate.scala hardcodes modules | match statement requires manual editing for each new module | No dynamic module discovery |
| No environment detection | setup.sh checks versions but results are not persisted or used by skills | No /initialize command |
| Hook triggers compile on ALL writes | Writing a testbench .cpp triggers sbt compile (wasteful) | Matcher too broad (Write\|Edit) |

## Recommended Architecture (v1.1 Target)

### Architecture Diagram

```
User invokes /chip-agent:generate "8-bit ALU with ADD, SUB"
    |
    v
[Skill: generate/SKILL.md]  (orchestrator -- thin, spawns subagents)
    |
    |--- spawns ---> [Skill: requirement-parser] --- returns JSON spec
    |                     |
    |      (spec written to workspace/<Module>/spec.json)
    |
    |--- user confirms spec (AskUserQuestion) ---
    |
    |--- spawns ---> [Skill: chisel-generate]
    |                     |
    |      (reads workspace/<Module>/spec.json)
    |      (writes chisel-project/src/main/scala/chipagent/<Module>.scala)
    |      (updates Generate.scala)
    |
    |--- hook auto-triggers compile.sh --module <Module> --target-dir workspace/<Module>/generated/
    |
    |--- invokes ---> /chip-agent:lint <Module>
    |                     |
    |      (reads workspace/<Module>/generated/*.v)
    |      (writes workspace/<Module>/lint-warnings.log)
    |
    |--- invokes ---> /chip-agent:testbench <Module>
    |                     |
    |      (reads workspace/<Module>/spec.json + generated/<Module>.v)
    |      (writes workspace/<Module>/sim/tb_<Module>.cpp)
    |
    |--- invokes ---> /chip-agent:simulate <Module>
    |                     |
    |      (writes workspace/<Module>/sim/obj_dir/, sim_result.log)
    |
    v
Report (reads workspace/<Module>/sim/sim_result.log)
```

### New Component Map

```
ChipAgent/                                (PLUGIN_ROOT)
  .claude-plugin/plugin.json              Plugin manifest
  skills/
    generate/
      SKILL.md                            /chip-agent:generate -- orchestrator
    requirement-parser/
      SKILL.md                            /chip-agent:requirement-parser
    chisel-generate/
      SKILL.md                            /chip-agent:chisel-generate
    lint/
      SKILL.md                            /chip-agent:lint
    testbench/
      SKILL.md                            /chip-agent:testbench
    simulate/
      SKILL.md                            /chip-agent:simulate
    initialize/
      SKILL.md                            /chip-agent:initialize
  agents/
    requirement-parser.md                 (UNCHANGED -- subagent definition)
    chisel-generator.md                   (UNCHANGED -- subagent definition)
    testbench-generator.md                (UNCHANGED -- subagent definition)
  hooks/
    hooks.json                            (MODIFIED -- narrower matcher)
  scripts/
    compile.sh                            (MODIFIED -- accepts --module flag)
    lint.sh                               (MODIFIED -- accepts module workspace path)
    simulate.sh                           (MODIFIED -- accepts module workspace path)
    setup.sh                              (UNCHANGED)
    initialize.sh                         (NEW -- writes env.json)
  chisel-project/                         (build.sbt and project/ UNCHANGED)
    src/main/scala/chipagent/
      Generate.scala                      (MODIFIED -- dynamic module, target-dir)
      ALU.scala                           (UNCHANGED -- existing modules stay)
      Decoder3to8.scala                   (UNCHANGED)
      TrivialModule.scala                 (UNCHANGED)
  workspace/                              (NEW -- per-module isolation root)
    <ModuleName>/
      spec.json                           Parsed requirement spec
      generated/                          Module's Verilog output
        <ModuleName>.v
        <ModuleName>.fir
      sim/
        tb_<ModuleName>.cpp               Module's testbench
        obj_dir/                           Module's Verilator build
      logs/
        sim_result.log                    Module's simulation results
        lint-warnings.log                 Module's lint warnings
  generated/                              (KEPT for backward compat, gitignored)
  sim/                                    (KEPT for backward compat)
```

### Component Boundaries

| Component | Type | Status | Responsibility | Communicates With |
|-----------|------|--------|---------------|-------------------|
| `skills/generate/SKILL.md` | Skill | MODIFIED | Thin orchestrator: captures NL description, invokes sub-skills in sequence, handles error/retry logic | All other skills via invocation |
| `skills/requirement-parser/SKILL.md` | Skill | NEW | Accepts NL description, delegates to requirement-parser agent, writes spec.json to workspace | requirement-parser agent, workspace/ |
| `skills/chisel-generate/SKILL.md` | Skill | NEW | Reads spec.json, delegates to chisel-generator agent, writes .scala files | chisel-generator agent, workspace/ |
| `skills/lint/SKILL.md` | Skill | NEW | Runs lint.sh on module's generated/ dir, reports results | scripts/lint.sh, workspace/ |
| `skills/testbench/SKILL.md` | Skill | NEW | Reads spec.json + .v file, delegates to testbench-generator agent | testbench-generator agent, workspace/ |
| `skills/simulate/SKILL.md` | Skill | NEW | Runs simulate.sh on module's workspace, reports results | scripts/simulate.sh, workspace/ |
| `skills/initialize/SKILL.md` | Skill | NEW | Detects tool versions, writes workspace/env.json | scripts/initialize.sh |
| `agents/requirement-parser.md` | Agent | UNCHANGED | Parses NL into JSON spec | Invoked by requirement-parser skill |
| `agents/chisel-generator.md` | Agent | UNCHANGED | Generates Chisel source from JSON spec | Invoked by chisel-generate skill |
| `agents/testbench-generator.md` | Agent | UNCHANGED | Generates C++ testbench from spec + Verilog | Invoked by testbench skill |
| `hooks/hooks.json` | Hook | MODIFIED | PostToolUse on .scala Write/Edit only | scripts/compile.sh |
| `scripts/compile.sh` | Script | MODIFIED | Accepts --module and --target-dir flags | sbt, Generate.scala |
| `scripts/lint.sh` | Script | MODIFIED | Accepts path to module's generated/ dir | verilator |
| `scripts/simulate.sh` | Script | MODIFIED | Accepts path to module's workspace/ | verilator |
| `scripts/initialize.sh` | Script | NEW | Checks sbt, Scala, Java, Verilator versions; writes JSON | Invoked by initialize skill |
| `chisel-project/.../Generate.scala` | Scala | MODIFIED | Accepts --module and --target-dir from CLI args | sbt runMain |
| `workspace/<Module>/spec.json` | Data | NEW | Spec file as inter-stage communication contract | Read by all downstream skills |
| `workspace/<Module>/` | Directory | NEW | Per-module isolation boundary | All pipeline stages |

### Data Flow Between Separate Commands

When pipeline stages are separate slash commands, they need a shared communication mechanism. The spec.json file in `workspace/<Module>/` serves as this contract.

```
/chip-agent:requirement-parser "8-bit ALU..."
    |
    | WRITES: workspace/ALU/spec.json
    |
    v
/chip-agent:chisel-generate ALU
    |
    | READS:  workspace/ALU/spec.json
    | WRITES: chisel-project/src/main/scala/chipagent/ALU.scala
    |         chisel-project/src/main/scala/chipagent/Generate.scala
    |
    | HOOK TRIGGERS: compile.sh --module ALU --target-dir workspace/ALU/generated
    |
    | PRODUCES: workspace/ALU/generated/ALU.v
    |
    v
/chip-agent:lint ALU
    |
    | READS:  workspace/ALU/generated/ALU.v
    | WRITES: workspace/ALU/logs/lint-warnings.log
    |
    v
/chip-agent:testbench ALU
    |
    | READS:  workspace/ALU/spec.json
    |         workspace/ALU/generated/ALU.v
    | WRITES: workspace/ALU/sim/tb_ALU.cpp
    |
    v
/chip-agent:simulate ALU
    |
    | READS:  workspace/ALU/generated/ALU.v
    |         workspace/ALU/sim/tb_ALU.cpp
    | WRITES: workspace/ALU/sim/obj_dir/ (build artifacts)
    |         workspace/ALU/logs/sim_result.log
    |
    v
Report (inline in generate orchestrator)
    |
    | READS:  workspace/ALU/logs/sim_result.log
    |         workspace/ALU/logs/lint-warnings.log
```

**Key principle:** Each skill reads from workspace/, writes to workspace/. The module name is the partition key. No skill needs to know where other skills' output goes -- they all follow the `workspace/<Module>/` convention.

## Detailed Design Decisions

### 1. How to Split generate.md Into Multiple Skill Files

**Decision:** Convert skills/ from flat files to skill directories with SKILL.md.

**Current state:** `skills/generate.md` is a flat command file (170 lines), which is the legacy format. Claude Code merged commands and skills into a unified system where `skills/<name>/SKILL.md` is the canonical format.

**Target state:** Seven skill directories, each with a SKILL.md file.

**Sharing common logic:** Skills do NOT share code the way traditional software modules do. Instead:

1. **Agents provide reusable capability.** The requirement-parser, chisel-generator, and testbench-generator agents remain unchanged in `agents/`. Multiple skills can invoke the same agent.
2. **Scripts provide reusable operations.** compile.sh, lint.sh, simulate.sh are invoked by multiple skills. Scripts are the "shared library" equivalent.
3. **Workspace conventions provide shared state.** All skills read/write from `workspace/<Module>/` using the same directory structure. The spec.json schema IS the interface contract.
4. **The generate skill is a thin orchestrator.** It invokes sub-skills in sequence but does not contain their logic. It handles retry counts, error aggregation, and user confirmation.

**Skill decomposition table:**

| Skill | Frontmatter | Content Focus |
|-------|-------------|---------------|
| generate | `disable-model-invocation: true` | Sequential invocation of sub-skills, retry logic, user confirmation |
| requirement-parser | `disable-model-invocation: true` | Accept NL, spawn parser agent, validate JSON, write spec.json |
| chisel-generate | `disable-model-invocation: true` | Read spec.json, spawn generator agent, validate Scala output |
| lint | `disable-model-invocation: true` | Run lint.sh with workspace path, report results |
| testbench | `disable-model-invocation: true` | Read spec.json, spawn testbench agent, validate output |
| simulate | `disable-model-invocation: true` | Run simulate.sh with workspace path, report results |
| initialize | `disable-model-invocation: true` | Run initialize.sh, report tool versions |

All skills use `disable-model-invocation: true` because they are pipeline actions with side effects -- Claude should not auto-trigger them based on conversation context.

### 2. How workspace/ Relates to chisel-project/src/ and generated/ and sim/

**Decision:** workspace/ is the per-module isolation layer AROUND the existing directories.

```
workspace/<Module>/
    spec.json              NEW -- parsed requirements
    generated/             REPLACES generated/ (per-module)
      <Module>.v
      <Module>.fir
      <Module>.anno.json
    sim/
      tb_<Module>.cpp      REPLACES sim/tb_*.cpp (per-module)
      obj_dir/             REPLACES sim/obj_dir/ (per-module)
    logs/
      sim_result.log       REPLACES sim/logs/sim_result.log (per-module)
      lint-warnings.log    REPLACES generated/lint-warnings.log (per-module)
```

**What stays in original locations:**

| Location | Contents | Why |
|----------|----------|-----|
| `chisel-project/src/main/scala/chipagent/*.scala` | Chisel source files | sbt requires them here. Cannot move without restructuring build.sbt |
| `chisel-project/build.sbt` | Build config | sbt convention |
| `generated/` (top-level) | Kept but gitignored | Backward compatibility for manual `scripts/compile.sh` runs without --target-dir |
| `sim/` (top-level) | Kept but gitignored | Backward compatibility for manual simulation runs |

**Critical constraint:** Chisel source files MUST remain in `chisel-project/src/main/scala/chipagent/` because sbt's source root is configured there. The workspace/ directory does NOT hold source code -- it holds compilation outputs and spec metadata.

**Relationship diagram:**

```
chisel-project/src/.../chipagent/ALU.scala
         |
         | (sbt compile, --target-dir workspace/ALU/generated)
         v
workspace/ALU/generated/ALU.v
         |
         | (verilator --cc)
         v
workspace/ALU/sim/obj_dir/VALU
         |
         | (run binary)
         v
workspace/ALU/logs/sim_result.log
```

### 3. How Generate.scala Must Change

**Current state:** Generate.scala uses a `match` statement to map module names to classes. Each new module requires manually adding a case to this match.

```scala
// CURRENT
val module: () => Module = moduleName match {
  case "TrivialModule" => () => new TrivialModule
  case "ALU"           => () => new ALU
  case "Decoder3to8"   => () => new Decoder3to8
  case other => throw new IllegalArgumentException(...)
}
```

**Target state:** Generate.scala already accepts `--module` and `--target-dir` flags. The main change needed is making the module registry extensible without manual editing.

**Approach: Keep the match statement, but have the chisel-generator agent update it.**

This is already how the system works -- the chisel-generator agent rewrites Generate.scala with the new module added to the match statement. The only actual change is ensuring `--target-dir` points to the workspace directory.

The compile.sh script currently hardcodes `OUTPUT_DIR="$PLUGIN_ROOT/generated"`. It must be changed to accept an optional `--target-dir` argument:

```bash
# MODIFIED compile.sh
MODULE="${1:-TrivialModule}"
OUTPUT_DIR="${2:-$PLUGIN_ROOT/generated}"

# ... rest of script ...
$TIMEOUT_CMD sbt --batch "runMain chipagent.Generate --module $MODULE --target-dir $OUTPUT_DIR"
```

Generate.scala already handles `--target-dir` correctly. The change is in how compile.sh passes it.

### 4. How Scripts Must Change for Workspace Paths

**compile.sh changes:**

```bash
# Accept: compile.sh [MODULE_NAME] [TARGET_DIR]
# Default: compile.sh TrivialModule $PLUGIN_ROOT/generated
MODULE="${1:-TrivialModule}"
OUTPUT_DIR="${2:-$PLUGIN_ROOT/generated}"
mkdir -p "$OUTPUT_DIR"
sbt --batch "runMain chipagent.Generate --module $MODULE --target-dir $OUTPUT_DIR"
```

**lint.sh changes:**

```bash
# Accept: lint.sh [GENERATED_DIR]
# Default: lint.sh $PLUGIN_ROOT/generated
GENERATED_DIR="${1:-$PLUGIN_ROOT/generated}"
# Rest of script uses GENERATED_DIR instead of hardcoded path
# Also writes lint-warnings.log TO the generated dir's parent /logs/
WARNINGS_LOG="$(dirname "$GENERATED_DIR")/logs/lint-warnings.log"
```

**simulate.sh changes:**

```bash
# Accept: simulate.sh <MODULE_NAME> [WORKSPACE_DIR]
# Default: simulate.sh ALU (uses legacy paths)
MODULE="${1:-ALU}"
WORKSPACE_DIR="${2:-}"

if [ -n "$WORKSPACE_DIR" ]; then
  GENERATED_DIR="$WORKSPACE_DIR/generated"
  SIM_DIR="$WORKSPACE_DIR/sim"
  LOG_DIR="$WORKSPACE_DIR/logs"
else
  # Legacy mode -- use flat directories
  GENERATED_DIR="$PLUGIN_ROOT/generated"
  SIM_DIR="$PLUGIN_ROOT/sim"
  LOG_DIR="$SIM_DIR/logs"
fi
```

**Backward compatibility:** All scripts default to the original flat directory paths when called without workspace arguments. This preserves the ability to run `scripts/compile.sh` manually.

### 5. Hook Refinement

**Current problem:** The PostToolUse hook fires on ANY Write|Edit, including testbench .cpp files. This triggers sbt compilation unnecessarily when writing testbenches.

**Solution:** Narrow the hook matcher OR use a validation script.

Claude Code hooks do not support file-path-based matchers -- the matcher field matches tool names, not file paths. However, the hook command receives the tool input as JSON via stdin, which includes the file path. A wrapper script can check the file extension:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/auto-compile.sh",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

Where `auto-compile.sh` checks the file path from stdin:

```bash
#!/usr/bin/env bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only compile if a Scala file was modified
if [[ "$FILE_PATH" == *.scala ]]; then
  exec "${CLAUDE_PLUGIN_ROOT}/scripts/compile.sh"
fi
# Silently exit for non-Scala files
exit 0
```

This prevents wasteful sbt invocations when writing testbenches or spec files.

## Patterns to Follow

### Pattern 1: Workspace as Isolation Boundary

**What:** Every module gets its own directory under `workspace/`. All pipeline artifacts for that module live within that boundary.

**When:** Always -- for every pipeline run.

**Why:** Prevents cross-module contamination. Module A's lint-warnings.log does not overwrite Module B's. Each module's sim_result.log is preserved for later comparison.

```
workspace/ALU/
  spec.json
  generated/ALU.v
  sim/tb_ALU.cpp
  sim/obj_dir/
  logs/sim_result.log
  logs/lint-warnings.log

workspace/Decoder3to8/
  spec.json
  generated/Decoder3to8.v
  sim/tb_Decoder3to8.cpp
  sim/obj_dir/
  logs/sim_result.log
  logs/lint-warnings.log
```

### Pattern 2: Spec-File as Inter-Stage Contract

**What:** The JSON spec file (`workspace/<Module>/spec.json`) is the communication medium between pipeline stages when they are separate slash commands.

**When:** Between requirement-parser output and all downstream consumers (chisel-generate, testbench, simulate).

**Why:** Avoids passing large JSON blobs through Claude's conversation context. Each skill reads the file directly using the Read tool. The spec schema is already well-defined by the requirement-parser agent.

```
requirement-parser ----writes---> workspace/ALU/spec.json
chisel-generate    ----reads----> workspace/ALU/spec.json
testbench          ----reads----> workspace/ALU/spec.json
```

### Pattern 3: Thin Orchestrator Skill

**What:** The generate skill becomes a thin orchestrator that invokes sub-skills in sequence, handles retries, and manages user interaction. It does NOT contain pipeline stage logic.

**When:** Always -- this is the main entry point.

**Template:**

```markdown
---
name: generate
description: Turn a natural language hardware description into simulation-verified Verilog
disable-model-invocation: true
---

Given the description "$ARGUMENTS", execute this pipeline:

1. Create workspace directory: workspace/<ModuleName>/
2. Invoke /chip-agent:requirement-parser with the description
   - Writes workspace/<ModuleName>/spec.json
3. Present spec to user for confirmation
4. Invoke /chip-agent:chisel-generate <ModuleName>
   - Reads spec.json, writes Scala source, auto-compiles via hook
5. Invoke /chip-agent:lint <ModuleName>
   - If errors: fix Chisel source, retry (max 3)
6. Invoke /chip-agent:testbench <ModuleName>
7. Invoke /chip-agent:simulate <ModuleName>
   - If errors: fix testbench, retry (max 3)
8. Report results from workspace/<ModuleName>/logs/
```

### Pattern 4: Backward-Compatible Script APIs

**What:** All modified scripts accept optional arguments for workspace paths while defaulting to the original flat directory layout.

**When:** Always -- scripts are called both by skills (with workspace paths) and manually by developers (without).

**Example:**

```bash
# New usage (workspace mode):
scripts/compile.sh ALU workspace/ALU/generated
scripts/lint.sh workspace/ALU/generated
scripts/simulate.sh ALU workspace/ALU

# Legacy usage (still works):
scripts/compile.sh
scripts/lint.sh
scripts/simulate.sh ALU
```

## Anti-Patterns to Avoid

### Anti-Pattern 1: Moving Chisel Source Into workspace/

**What:** Putting ALU.scala inside workspace/ALU/src/.

**Why bad:** sbt expects sources in `chisel-project/src/main/scala/chipagent/`. Moving them requires reconfiguring sbt source roots, adding complexity for no benefit. Chisel source is SHARED (all modules compile together); only outputs need isolation.

**Instead:** Keep all .scala files in `chisel-project/src/main/scala/chipagent/`. Only isolate compilation outputs and simulation artifacts in workspace/.

### Anti-Pattern 2: Skills That Know Internal Paths of Other Skills

**What:** The testbench skill hardcoding `workspace/<Module>/generated/<Module>.v` instead of using the workspace convention.

**Why bad:** Tight coupling. If the generated/ subdirectory structure changes, every skill breaks.

**Instead:** Each skill accepts the module name and derives paths from the workspace convention: `workspace/$MODULE/generated/`, `workspace/$MODULE/sim/`, `workspace/$MODULE/logs/`.

### Anti-Pattern 3: Passing Spec JSON Through Conversation Context

**What:** Having the requirement-parser skill return the full JSON spec in the conversation, then passing it as a string to the chisel-generate skill.

**Why bad:** Wastes context window tokens. A complex spec (CPU with 4 sub-modules) is 100+ lines of JSON. When skills run sequentially, each skill's prompt adds to the cumulative context.

**Instead:** Write spec.json to workspace/. Downstream skills read the file with the Read tool. The conversation only carries the module name.

### Anti-Pattern 4: Separate sbt Projects Per Module

**What:** Creating `workspace/ALU/chisel-project/` with its own build.sbt.

**Why bad:** sbt startup takes 10-30 seconds. Each separate project multiplies this overhead. Chisel modules share dependencies and compiler plugins. Duplicating the build config is wasteful.

**Instead:** Single sbt project, multiple modules. Use `--target-dir` to control where output goes. The `--module` flag selects which module to emit.

### Anti-Pattern 5: Using context: fork for Pipeline Skills

**What:** Setting `context: fork` on the generate orchestrator skill.

**Why bad:** Forked subagents lose conversation context. The generate skill needs to interact with the user (spec confirmation via AskUserQuestion), which requires the main conversation context.

**Instead:** Run generate in the main conversation. Only individual research or exploration tasks should use `context: fork`.

## Build Order (Dependency-Aware)

Based on dependencies between components, build in this order:

### Phase 1: Workspace Foundation (no dependencies on other changes)
1. Create `workspace/` directory structure convention
2. Modify `scripts/compile.sh` to accept module name and target-dir arguments
3. Modify `scripts/lint.sh` to accept generated directory path
4. Modify `scripts/simulate.sh` to accept workspace directory path
5. Modify `Generate.scala` if needed (already handles --target-dir, may just need validation)

### Phase 2: Skill Decomposition (depends on Phase 1 scripts)
6. Create `skills/initialize/SKILL.md` + `scripts/initialize.sh`
7. Create `skills/requirement-parser/SKILL.md` (wraps existing agent)
8. Create `skills/chisel-generate/SKILL.md` (wraps existing agent)
9. Create `skills/lint/SKILL.md` (wraps modified lint.sh)
10. Create `skills/testbench/SKILL.md` (wraps existing agent)
11. Create `skills/simulate/SKILL.md` (wraps modified simulate.sh)

### Phase 3: Orchestrator + Hooks (depends on Phase 2 skills existing)
12. Rewrite `skills/generate/SKILL.md` as thin orchestrator invoking sub-skills
13. Update `hooks/hooks.json` with auto-compile.sh wrapper for .scala-only filtering
14. Create `scripts/auto-compile.sh` (hook wrapper)

### Phase 4: Migration + Cleanup
15. Delete old `skills/generate.md`
16. Update CLAUDE.md with new directory structure and skill list
17. Update package.json files array if needed

**Rationale for ordering:**
- Scripts must be workspace-aware BEFORE skills reference them
- Individual skills must exist BEFORE the orchestrator can invoke them
- Hooks must be updated AFTER the skill decomposition to avoid breaking the existing pipeline during development

## Scalability Considerations

| Concern | At 1 module | At 10 modules | At 50+ modules |
|---------|-------------|---------------|----------------|
| workspace/ size | ~500KB | ~5MB | ~25MB (gitignore obj_dir/) |
| sbt compile time | <30s | ~30s (incremental) | ~60s (recompiles changed modules only) |
| Verilator build per module | ~5s | 5s each (isolated obj_dir/) | Parallelize with make -j |
| spec.json management | Trivial | Manual navigation | Add workspace/index.json listing all modules |
| Disk cleanup | Not needed | Not needed | Add scripts/clean-workspace.sh |

## Sources

- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills) -- SKILL.md format, frontmatter fields, $ARGUMENTS, disable-model-invocation, CLAUDE_SKILL_DIR
- [Claude Code Plugins Documentation](https://code.claude.com/docs/en/plugins) -- Plugin structure, skills/ directory, plugin namespacing (plugin-name:skill-name)
- [Claude Code Subagents Documentation](https://code.claude.com/docs/en/sub-agents) -- Agent definitions, how skills invoke agents, context: fork behavior
- [Claude Code Hooks Documentation](https://code.claude.com/docs/en/hooks) -- PostToolUse events, hook input JSON format, command execution
- [Inside Claude Code Skills](https://mikhail.io/2025/10/claude-code-skills/) -- Skills architecture deep-dive
- [Claude Code Merges Slash Commands Into Skills](https://medium.com/@joe.njenga/claude-code-merges-slash-commands-into-skills-dont-miss-your-update-8296f3989697) -- Commands -> Skills migration
- Existing codebase analysis: generate.md, hooks.json, compile.sh, lint.sh, simulate.sh, Generate.scala, all agent definitions

---
*Architecture patterns for: ChipAgent v1.1 -- Modular Slash Commands + Workspace Isolation*
*Researched: 2026-03-19*
