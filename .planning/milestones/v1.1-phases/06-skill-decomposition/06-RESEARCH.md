# Phase 6: Skill Decomposition - Research

**Researched:** 2026-03-20
**Domain:** Claude Code plugin skills system, workspace-aware CLI commands, spec.json inter-stage communication
**Confidence:** HIGH

## Summary

Phase 6 decomposes the monolithic `/chip-agent:generate` pipeline into five standalone slash commands -- `/chip-agent:compile`, `/chip-agent:lint`, `/chip-agent:simulate`, `/chip-agent:testbench`, and `/chip-agent:requirement-parser` -- each reading/writing artifacts from workspace directories. This phase also introduces `spec.json` as the structured communication format between pipeline stages (replacing conversation-context dependency).

The project currently uses a **legacy flat-file skill format** (`skills/generate.md` -- no frontmatter, no subdirectory). The modern Claude Code plugin skill format uses `skills/<name>/SKILL.md` with YAML frontmatter. Phase 6 should migrate to the modern format for all new skills, and optionally migrate the existing `generate.md` as well. The plugin namespace means all commands are invoked as `/chip-agent:<skill-name>`.

**Primary recommendation:** Create five new skill directories under `skills/` using the modern `SKILL.md` format with YAML frontmatter. Three skills (compile, lint, simulate) are thin wrappers that call existing workspace-aware scripts. Two skills (requirement-parser, testbench) are agent-backed -- they invoke existing subagents and additionally read/write `spec.json` from the workspace. The `spec.json` format must match the JSON schema already defined in the requirement-parser agent.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SKILL-01 | `/chip-agent:compile` compiles a named module's Chisel source to Verilog, outputting to `workspace/<Module>/generated/` | Wraps existing `scripts/compile.sh workspace/<Module>` which already supports workspace paths (Phase 5). Needs SKILL.md in `skills/compile/` with `disable-model-invocation: true`. |
| SKILL-02 | `/chip-agent:lint` runs Verilator lint-only on a named module's generated Verilog | Wraps existing `scripts/lint.sh workspace/<Module>` which already supports workspace paths (Phase 5). Needs SKILL.md in `skills/lint/`. |
| SKILL-03 | `/chip-agent:simulate` runs Verilator simulation for a named module, producing `sim_result.log` in `workspace/<Module>/sim/logs/` | Wraps existing `scripts/simulate.sh workspace/<Module>` which already supports workspace paths (Phase 5). Needs SKILL.md in `skills/simulate/`. |
| SKILL-04 | `/chip-agent:testbench` generates a C++ testbench for a named module using the testbench-generator agent | Agent-backed skill that reads `workspace/<Module>/spec.json` and invokes testbench-generator agent. Output goes to `workspace/<Module>/sim/tb_<Module>.cpp`. Needs SKILL.md in `skills/testbench/`. |
| SKILL-05 | `/chip-agent:requirement-parser` parses a natural language hardware description into a structured `spec.json` | Agent-backed skill that invokes requirement-parser agent, creates `workspace/<Module>/` directory, and writes `spec.json`. Needs SKILL.md in `skills/requirement-parser/`. |
| SPEC-01 | Requirement parser writes a structured JSON spec file to `workspace/<Module>/spec.json` | The JSON schema is already fully defined in `agents/requirement-parser.md` (simple and complex schemas). The skill wrapper must write the agent's JSON output to `workspace/<Module>/spec.json`. |
| SPEC-02 | Downstream stages read spec.json from workspace rather than depending on conversation context | The testbench skill must read `workspace/<Module>/spec.json` and pass it to the testbench-generator agent. No conversation context dependency. |
</phase_requirements>

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Claude Code Skills | Agent Skills v1.0 | Slash command framework for plugin | Official plugin skill system; supports YAML frontmatter, `$ARGUMENTS`, progressive disclosure |
| YAML frontmatter | - | Skill metadata (name, description, allowed-tools) | Required by modern skill format; enables auto-discovery and tool restriction |
| JSON | - | spec.json inter-stage communication | Already chosen as inter-agent contract (PROJECT.md Key Decisions: "JSON spec as inter-agent contract") |

### Supporting

| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| `scripts/compile.sh` | v1.1 (Phase 5) | Workspace-aware Chisel compilation | Called by compile skill |
| `scripts/lint.sh` | v1.1 (Phase 5) | Workspace-aware Verilator lint | Called by lint skill |
| `scripts/simulate.sh` | v1.1 (Phase 5) | Workspace-aware Verilator simulation | Called by simulate skill |
| `agents/requirement-parser.md` | v1.0 | NL-to-JSON parsing agent | Invoked by requirement-parser skill |
| `agents/testbench-generator.md` | v1.0 | C++ testbench generation agent | Invoked by testbench skill |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Modern `SKILL.md` format | Legacy flat `.md` in `skills/` | Legacy still works but lacks frontmatter, auto-discovery, and bundled resources. Modern format is the recommended path. |
| spec.json file on disk | Conversation context passing | File-based is the locked decision (Option C). Enables standalone skill invocation without prior pipeline stages in same conversation. |

## Architecture Patterns

### Recommended Project Structure (Post Phase 6)

```
skills/
├── generate/
│   └── SKILL.md              # Existing generate pipeline (migrated from generate.md)
├── compile/
│   └── SKILL.md              # Script wrapper: calls scripts/compile.sh
├── lint/
│   └── SKILL.md              # Script wrapper: calls scripts/lint.sh
├── simulate/
│   └── SKILL.md              # Script wrapper: calls scripts/simulate.sh
├── testbench/
│   └── SKILL.md              # Agent-backed: reads spec.json, invokes testbench-generator
└── requirement-parser/
    └── SKILL.md              # Agent-backed: invokes requirement-parser, writes spec.json

workspace/
└── <ModuleName>/
    ├── spec.json              # NEW: structured spec from requirement-parser
    ├── generated/
    │   ├── <Module>.v
    │   ├── <Module>.sv
    │   └── lint-warnings.log
    └── sim/
        ├── tb_<Module>.cpp
        ├── logs/
        │   └── sim_result.log
        └── obj_dir/
```

### Pattern 1: Script-Wrapper Skill

**What:** A skill that takes `$ARGUMENTS` (module name), resolves the workspace path, runs an existing script via Bash, and reports results.
**When to use:** For SKILL-01 (compile), SKILL-02 (lint), SKILL-03 (simulate).

```markdown
---
name: compile
description: "Compiles a named module's Chisel source to Verilog. Accepts a module name as argument and outputs to workspace/<Module>/generated/. Use when the user wants to compile a specific module without running the full pipeline."
disable-model-invocation: true
allowed-tools: Bash, Read
---
# chip-agent:compile

Compile a named module's Chisel source to Verilog, writing output to the module's workspace directory.

## Usage

`/chip-agent:compile <ModuleName>`

## Instructions

1. Extract the module name from `$ARGUMENTS`. If empty, ask the user for a module name.
2. Set the workspace path: `workspace/$ARGUMENTS`
3. Run the compilation script:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/compile.sh workspace/<ModuleName>
   ```
4. Report the result:
   - On success: list generated files in `workspace/<ModuleName>/generated/`
   - On failure: show the build error output and suggest fixes

## Input

$ARGUMENTS — The module name (PascalCase, e.g., ALU, Decoder3to8)

## Output

Generated Verilog files in `workspace/<ModuleName>/generated/`
```

### Pattern 2: Agent-Backed Skill

**What:** A skill that invokes a subagent, captures its output, and writes structured artifacts to workspace.
**When to use:** For SKILL-04 (testbench), SKILL-05 (requirement-parser).

```markdown
---
name: requirement-parser
description: "Parses a natural language hardware description into a structured spec.json file. Writes the spec to workspace/<Module>/spec.json. Use when the user wants to create a module specification without running the full pipeline."
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Grep, Glob
---
# chip-agent:requirement-parser

Parse a natural language hardware description into a structured JSON specification file.

## Usage

`/chip-agent:requirement-parser <hardware description>`

## Instructions

1. Use the requirement-parser agent with the user's description ($ARGUMENTS)
2. The agent returns a JSON spec. Validate it:
   - `moduleName` is present and PascalCase
   - `type` is "simple" or "complex"
   - All ports have direction, type, and width
3. Create the workspace directory: `workspace/<moduleName>/`
4. Write the spec to: `workspace/<moduleName>/spec.json`
5. Present the parsed spec summary to the user

## Input

$ARGUMENTS — Natural language hardware description

## Output

- `workspace/<ModuleName>/spec.json` — Structured specification file
```

### Pattern 3: Spec-File Communication

**What:** Downstream skills read `spec.json` from workspace instead of depending on conversation context.
**When to use:** For testbench skill (reads spec.json written by requirement-parser skill).

Key principle: each skill must be independently invocable. The testbench skill reads `workspace/<Module>/spec.json` -- it does NOT require the requirement-parser to have run in the same conversation session.

### Anti-Patterns to Avoid

- **Conversation context dependency:** Skills must NOT rely on conversation history for spec data. Always read from `spec.json` on disk.
- **Hardcoded paths:** Never use absolute paths in skills. Always use `${CLAUDE_PLUGIN_ROOT}` for intra-plugin references and `workspace/<Module>/` for artifact paths.
- **Missing workspace validation:** Always check that `workspace/<Module>/` exists before attempting to read artifacts. Report clear errors if prerequisites are missing (e.g., "No spec.json found -- run `/chip-agent:requirement-parser` first").
- **Flat file skills:** Do not create new skills as flat `.md` files in `skills/`. Use the modern `skills/<name>/SKILL.md` subdirectory format.
- **Overloaded skills:** Each skill does ONE thing. The compile skill compiles. It does not lint or simulate. The testbench skill generates a testbench. It does not simulate.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Workspace path resolution | Custom path logic in each skill | Existing `scripts/*.sh` workspace resolution | Scripts already handle flat vs workspace mode, absolute vs relative paths, edge cases |
| JSON spec validation | Custom validation code | Inline validation in skill instructions | The spec schema is small enough to validate by checking key presence. Full JSON schema validation would be overengineering. |
| Testbench generation | Inline C++ generation in skill | Existing `agents/testbench-generator.md` agent | Agent already has comprehensive templates, anti-patterns, test vector rules |
| NL parsing | Inline parsing logic | Existing `agents/requirement-parser.md` agent | Agent already handles simple vs complex detection, all field extraction, schema compliance |
| Module name extraction | Complex argument parsing | `$ARGUMENTS` string substitution | Claude Code natively provides `$ARGUMENTS` containing everything after the slash command |

**Key insight:** Phase 6 is a **thin-wrapper phase**. The heavy lifting (compilation, linting, simulation, parsing, testbench generation) already exists in scripts and agents. Skills are glue that connects user intent to existing infrastructure via workspace paths.

## Common Pitfalls

### Pitfall 1: `$ARGUMENTS` is the raw string, not parsed

**What goes wrong:** Assuming `$ARGUMENTS` is pre-parsed or structured. It is the raw string the user typed after the command.
**Why it happens:** Misunderstanding skill variable substitution.
**How to avoid:** Skills must instruct Claude to parse `$ARGUMENTS` themselves -- extract module name, validate it's PascalCase, handle empty input gracefully.
**Warning signs:** Skills that silently pass empty strings to scripts.

### Pitfall 2: `${CLAUDE_PLUGIN_ROOT}` only works in hooks/JSON, not in skill markdown content

**What goes wrong:** Using `${CLAUDE_PLUGIN_ROOT}` in SKILL.md instructions and expecting it to be interpolated.
**Why it happens:** Known limitation documented in GitHub issue #9354 -- the variable works in hooks.json but not in command/skill markdown files.
**How to avoid:** In SKILL.md, instruct Claude to determine the plugin root itself (e.g., "Find the plugin root by locating the `.claude-plugin/plugin.json` file") or use the Bash tool to access the environment variable at runtime.
**Warning signs:** Skills that reference `${CLAUDE_PLUGIN_ROOT}` directly in their text expecting string interpolation.

### Pitfall 3: PostToolUse hook triggers on ALL Write/Edit operations

**What goes wrong:** The existing PostToolUse hook runs `compile.sh` on every Write/Edit, including non-Scala files. Writing a testbench (.cpp) triggers compilation. Writing spec.json triggers compilation.
**Why it happens:** The hook matcher is `Write|Edit` with no file extension filter.
**How to avoid:** This is a known issue noted in STATE.md ("PostToolUse hook fires on .cpp writes, triggering unnecessary sbt compilation (fix in Phase 7)"). For Phase 6, skills must be aware that writing testbenches or spec.json files may trigger unnecessary compilations. The hook itself should not be modified in Phase 6 (scheduled for Phase 7).
**Warning signs:** Slow skill execution due to spurious sbt compilations.

### Pitfall 4: Testbench path mismatch between flat and workspace modes

**What goes wrong:** The testbench skill writes to `workspace/<Module>/sim/tb_<Module>.cpp`, but the testbench-generator agent's instructions say to write to `sim/tb_<Module>.cpp` (flat mode).
**Why it happens:** The testbench-generator agent was written for v1.0 flat mode.
**How to avoid:** The testbench skill must override the agent's default output path by instructing Claude to write the testbench to `workspace/<Module>/sim/tb_<Module>.cpp` instead of `sim/tb_<Module>.cpp`. The skill instructions take precedence over agent defaults.
**Warning signs:** Testbench written to flat `sim/` directory instead of workspace.

### Pitfall 5: spec.json written but not read correctly by downstream skills

**What goes wrong:** The requirement-parser agent returns JSON to the conversation, but the spec is not actually saved to disk, or the testbench skill tries to read from the wrong path.
**Why it happens:** The requirement-parser agent's output instructions say "Return ONLY the JSON specification" -- this means the agent returns it as conversation output, not as a file write. The skill wrapper must capture this and write it to disk.
**How to avoid:** The requirement-parser skill must explicitly capture the agent's JSON output and write it to `workspace/<Module>/spec.json` using the Write tool. The testbench skill must read spec.json using the Read tool.
**Warning signs:** Testbench skill fails with "spec.json not found".

### Pitfall 6: Skill name must match directory name

**What goes wrong:** The YAML `name` field in SKILL.md doesn't match the directory name, causing discovery issues.
**Why it happens:** SKILL.md format sensitivity -- the folder name determines the slash command name.
**How to avoid:** Ensure directory name matches the `name` field in frontmatter. For plugin skills, the command becomes `/chip-agent:<name>`.
**Warning signs:** Skill not appearing in `/` autocomplete.

## Code Examples

### SKILL.md for a Script-Wrapper Skill (compile)

```yaml
---
name: compile
description: "Compiles a named module's Chisel source to Verilog, writing output to the module's workspace directory. Use when the user wants to compile a specific module without running the full pipeline."
disable-model-invocation: true
allowed-tools: Bash, Read
---
```

### SKILL.md for an Agent-Backed Skill (testbench)

```yaml
---
name: testbench
description: "Generates a C++ Verilator testbench for a named module by reading its spec.json from workspace. Use when the user wants to create a testbench without running the full pipeline."
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Grep, Glob
---
```

### spec.json (Simple Module Example -- ALU)

This is the exact same schema produced by the requirement-parser agent. The only change is that it is written to disk at `workspace/ALU/spec.json`:

```json
{
  "moduleName": "ALU",
  "description": "32-bit ALU with arithmetic and logic operations plus zero flag",
  "type": "simple",
  "bitWidth": 32,
  "ports": [
    { "name": "inputA", "direction": "input", "type": "UInt", "width": 32 },
    { "name": "inputB", "direction": "input", "type": "UInt", "width": 32 },
    { "name": "op", "direction": "input", "type": "UInt", "width": 3 },
    { "name": "result", "direction": "output", "type": "UInt", "width": 32 },
    { "name": "zero", "direction": "output", "type": "Bool", "width": 1 }
  ],
  "operations": [
    { "opcode": 0, "name": "ADD", "expression": "io.inputA + io.inputB" },
    { "opcode": 1, "name": "SUB", "expression": "io.inputA - io.inputB" },
    { "opcode": 2, "name": "AND", "expression": "io.inputA & io.inputB" },
    { "opcode": 3, "name": "OR",  "expression": "io.inputA | io.inputB" },
    { "opcode": 4, "name": "XOR", "expression": "io.inputA ^ io.inputB" },
    { "opcode": 5, "name": "SLT", "expression": "(io.inputA.asSInt < io.inputB.asSInt).asUInt" }
  ],
  "flags": [
    { "name": "zero", "condition": "io.result === 0.U" }
  ],
  "constraints": [
    "op port width is ceil(log2(6)) = 3 bits",
    "SLT uses signed comparison via .asSInt",
    "Zero flag derived from result output"
  ]
}
```

### Workspace Directory Creation

Each skill that writes to workspace must ensure the directory exists:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
MODULE="$1"
WORKSPACE_DIR="$PLUGIN_ROOT/workspace/$MODULE"
mkdir -p "$WORKSPACE_DIR/generated" "$WORKSPACE_DIR/sim/logs"
```

### Testbench Skill Reading spec.json

The testbench skill's key instruction pattern:

```markdown
1. Read the spec from workspace:
   - Read `workspace/<ModuleName>/spec.json`
   - If the file does not exist, STOP and tell the user:
     "No spec.json found for <ModuleName>. Run `/chip-agent:requirement-parser` first."
2. Use the testbench-generator agent with the spec JSON content
3. Write the testbench to `workspace/<ModuleName>/sim/tb_<ModuleName>.cpp`
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Flat `.md` in `skills/` or `commands/` | `skills/<name>/SKILL.md` with YAML frontmatter | Oct 2025 (Agent Skills release) | Enables auto-discovery, tool restriction, progressive disclosure |
| Conversation context passing | spec.json file on disk | v1.1 design decision | Enables independent skill invocation, reproducibility, debugging |
| Monolithic generate pipeline | Decomposed individual skills | Phase 6 (this phase) | Users can run individual stages, better error isolation |

**Deprecated/outdated:**
- Flat `.md` files in `commands/`: Still work but are the legacy format. The project currently uses this for `skills/generate.md`.

## Existing generate.md Migration

The current `skills/generate.md` is 178 lines, has no YAML frontmatter, and uses the legacy flat-file format. Two options:

1. **Migrate now (recommended):** Move to `skills/generate/SKILL.md`, add frontmatter. This is consistent with all new skills and takes minimal effort.
2. **Defer migration:** Leave `generate.md` in place. It still works. Migrate in Phase 7 when the generate command is refactored to orchestrate sub-skills.

Option 2 is safer since Phase 7 will rewrite the generate skill anyway (SKILL-06). Migrating the file format now and rewriting the content in Phase 7 means two touches. Deferring means one touch in Phase 7.

**Recommendation:** Defer the generate.md migration to Phase 7. Create all new Phase 6 skills in the modern format.

## Open Questions

1. **PostToolUse hook interference**
   - What we know: The hook triggers `compile.sh` on ALL Write/Edit operations. Writing spec.json or testbench .cpp files will trigger unnecessary sbt compilations.
   - What's unclear: Whether this causes actual failures or just slowness.
   - Recommendation: Accept the overhead for Phase 6. The hook fix is scheduled for Phase 7. Skills documentation should note this behavior.

2. **Testbench output path for workspace mode**
   - What we know: The testbench-generator agent writes to `sim/tb_<Module>.cpp` (flat mode). The simulate.sh script in workspace mode expects `workspace/<Module>/sim/tb_<Module>.cpp`.
   - What's unclear: Whether the existing agent will correctly write to workspace paths when instructed by the skill.
   - Recommendation: The skill must explicitly instruct the Write tool to target `workspace/<Module>/sim/tb_<Module>.cpp`. The agent's default path suggestion is overridden by the skill's explicit instruction.

3. **Skill description budget**
   - What we know: Skill descriptions are loaded into context. Budget scales at 2% of context window with 16K character fallback. Adding 5 new skills increases the description footprint.
   - What's unclear: Whether 6 total skills (generate + 5 new) will exceed the budget.
   - Recommendation: Keep descriptions concise (1-2 sentences each). With 6 skills at ~200 chars each, total is ~1.2K characters -- well within budget.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Bash test scripts (project convention from Phases 1-5) |
| Config file | None -- self-contained scripts |
| Quick run command | `bash scripts/test-phase6.sh` |
| Full suite command | `bash scripts/test-phase6.sh` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SKILL-01 | compile skill creates workspace Verilog | smoke | `bash scripts/test-phase6.sh` (check 1) | Wave 0 |
| SKILL-02 | lint skill runs Verilator lint on workspace | smoke | `bash scripts/test-phase6.sh` (check 2) | Wave 0 |
| SKILL-03 | simulate skill produces sim_result.log | smoke | `bash scripts/test-phase6.sh` (check 3) | Wave 0 |
| SKILL-04 | testbench skill reads spec.json and writes tb | smoke | `bash scripts/test-phase6.sh` (check 4) | Wave 0 |
| SKILL-05 | requirement-parser skill writes spec.json | smoke | `bash scripts/test-phase6.sh` (check 5) | Wave 0 |
| SPEC-01 | spec.json written to workspace with valid schema | unit | `bash scripts/test-phase6.sh` (check 6) | Wave 0 |
| SPEC-02 | testbench reads spec.json, not conversation context | manual-only | Manual: invoke testbench in fresh session with existing spec.json | N/A |

Note: Skills are Claude Code slash commands -- they cannot be automatically tested by running scripts because they require the Claude Code runtime environment. The test script can verify that:
- SKILL.md files exist with correct frontmatter
- Directory structure matches expected layout
- spec.json schema matches requirement-parser output format
- Scripts are callable with workspace arguments

Full end-to-end skill invocation tests require human verification by running the actual slash commands in Claude Code.

### Sampling Rate

- **Per task commit:** `bash scripts/test-phase6.sh`
- **Per wave merge:** `bash scripts/test-phase6.sh`
- **Phase gate:** Full suite green + manual skill invocation before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `scripts/test-phase6.sh` -- covers structural verification for all skills
- [ ] `skills/compile/SKILL.md` -- SKILL-01
- [ ] `skills/lint/SKILL.md` -- SKILL-02
- [ ] `skills/simulate/SKILL.md` -- SKILL-03
- [ ] `skills/testbench/SKILL.md` -- SKILL-04
- [ ] `skills/requirement-parser/SKILL.md` -- SKILL-05

## Sources

### Primary (HIGH confidence)
- `skills/generate.md` -- existing skill file, verified format and content (178 lines, no frontmatter)
- `agents/requirement-parser.md` -- JSON spec schema definition (verified, 410 lines)
- `agents/testbench-generator.md` -- testbench generation agent (verified, 440 lines)
- `agents/chisel-generator.md` -- Chisel generation agent (verified, 346 lines)
- `scripts/compile.sh` -- workspace-aware compilation (verified, 76 lines, Phase 5)
- `scripts/lint.sh` -- workspace-aware linting (verified, 86 lines, Phase 5)
- `scripts/simulate.sh` -- workspace-aware simulation (verified, 80 lines, Phase 5)
- `hooks/hooks.json` -- PostToolUse hook definition (verified, 17 lines)
- `.claude-plugin/plugin.json` -- plugin manifest (verified, plugin name "chip-agent")
- `.planning/REQUIREMENTS.md` -- requirement definitions SKILL-01 through SPEC-02

### Secondary (MEDIUM confidence)
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills) -- SKILL.md format, frontmatter fields, discovery mechanism
- [Claude Code Plugins README](https://github.com/anthropics/claude-code/blob/main/plugins/README.md) -- plugin directory structure, namespace convention
- [Anthropic Skills Deep Dive](https://leehanchung.github.io/blogs/2025/10/26/claude-skills-deep-dive/) -- progressive disclosure design, skill lifecycle
- [Claude Code Skills Structure](https://mikhail.io/2025/10/claude-code-skills/) -- SKILL.md internal structure analysis
- [CLAUDE_PLUGIN_ROOT Issue #9354](https://github.com/anthropics/claude-code/issues/9354) -- known limitation on variable interpolation in skill files

### Tertiary (LOW confidence)
- None -- all findings verified against official sources or project files

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- All components are existing project infrastructure or well-documented Claude Code features
- Architecture: HIGH -- Skills directory pattern is well-documented; spec.json schema already defined in agents
- Pitfalls: HIGH -- Identified from project STATE.md (hook issue), known GitHub issues (CLAUDE_PLUGIN_ROOT), and direct code inspection

**Research date:** 2026-03-20
**Valid until:** 2026-04-20 (stable -- based on project infrastructure and Claude Code stable features)
