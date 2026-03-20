# Phase 7: Orchestrator + Initialize - Research

**Researched:** 2026-03-20
**Domain:** Claude Code skill orchestration, environment detection, SKILL.md pipeline coordination
**Confidence:** HIGH

## Summary

Phase 7 has two distinct deliverables: (1) refactoring `/chip-agent:generate` from a monolithic pipeline into an orchestrator that sequentially invokes the sub-skills created in Phase 6, and (2) creating a new `/chip-agent:initialize` command that detects local toolchain versions and writes machine-readable capability data.

The orchestrator must coordinate six sub-skills in sequence: requirement-parser, chisel-generate (agent-backed, inline), compile, lint, testbench, simulate, then report results. The critical architectural insight from research is that Claude Code skills **cannot directly invoke other skills** from within a forked context -- the Task/Agent tool is not available in forked contexts. However, the generate skill runs **inline** (not forked), meaning the main Claude instance executes its instructions and can freely use the Skill tool to invoke sub-skills, or simply follow sub-skill patterns directly by reading agents and calling scripts. The existing `skills/generate.md` already orchestrates agents and scripts inline -- the refactoring simply replaces inline agent calls with calls to the matching sub-skills where they exist.

The initialize command is a new skill that runs bash detection commands, assembles a JSON capability file at `.chipagent/env.json`, and patches the CLAUDE.md Tech Stack table with detected versions. The existing `scripts/setup.sh` already has partial detection logic for Java, sbt, and Verilator that can be referenced, but the new initialize skill needs to also detect Scala, Make, and g++, and must produce a structured JSON output rather than just pass/fail.

**Primary recommendation:** Keep `/chip-agent:generate` as an inline skill (no `context: fork`) that directly orchestrates the pipeline by using agent definitions and script calls. For sub-steps that have dedicated skills (compile, lint, simulate, testbench, requirement-parser), reference their patterns but call scripts/agents directly rather than using the Skill tool -- this avoids nested context overhead and maintains the same end-to-end behavior as v1.0. Create `/chip-agent:initialize` as a new script-backed skill that runs `scripts/detect-env.sh` and writes `.chipagent/env.json` plus patches CLAUDE.md.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SKILL-06 | `/chip-agent:generate` (refactored) orchestrates full pipeline by sequentially invoking sub-skills: requirement-parser, chisel-generate, compile, lint, testbench, simulate, report | Generate skill already exists as `skills/generate.md` (178 lines). Migrate to `skills/generate/SKILL.md` with frontmatter. Rewrite pipeline steps to reference sub-skill patterns. Chisel-generate step has no dedicated skill -- it uses the chisel-generator agent directly. |
| INIT-01 | `/chip-agent:initialize` detects local tool versions (Java, sbt, Scala, Verilator, Make, g++) | New skill + script. Detection commands verified: `java -version`, `sbt --version`, `scala -version`, `verilator --version`, `make --version`, `g++ --version`. All output to stderr or stdout with parseable formats. |
| INIT-02 | Initialize writes `.chipagent/env.json` with tool versions, paths, capability flags | New JSON file. Schema defined below in Architecture Patterns. Capability flags derived from tool presence: can_compile (Java + sbt), can_lint (Verilator), can_simulate (Verilator + Make + g++). |
| INIT-03 | Initialize updates CLAUDE.md Tech Stack table with detected local versions | Requires parsing and patching the markdown table in CLAUDE.md. The table has a fixed structure (Component, Version, Purpose columns). Use sed or skill-level Edit tool to update version cells. |
</phase_requirements>

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Claude Code Skills | Agent Skills v1.0 | Slash command framework for plugin | Official plugin skill system; `SKILL.md` with YAML frontmatter |
| YAML frontmatter | - | Skill metadata (name, description, allowed-tools) | Required by modern skill format; enables tool restriction and discovery control |
| Bash scripts | - | Environment detection, script execution | All existing pipeline scripts are bash; consistent with project conventions |
| JSON | - | `.chipagent/env.json` structured output | Machine-readable, matches spec.json pattern already used for inter-stage communication |

### Supporting

| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| `scripts/compile.sh` | v1.1 | Workspace-aware Chisel compilation | Called by orchestrator compile step |
| `scripts/lint.sh` | v1.1 | Workspace-aware Verilator lint | Called by orchestrator lint step |
| `scripts/simulate.sh` | v1.1 | Workspace-aware Verilator simulation | Called by orchestrator simulate step |
| `agents/requirement-parser.md` | v1.0 | NL-to-JSON parsing | Called by orchestrator parse step |
| `agents/chisel-generator.md` | v1.0 | Spec-to-Chisel code generation | Called by orchestrator generate step |
| `agents/testbench-generator.md` | v1.0 | C++ testbench generation | Called by orchestrator testbench step |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Inline orchestration (direct script/agent calls) | Skill tool to invoke sub-skills | Skill tool adds context overhead per invocation and sub-skills cannot spawn further subagents. Inline calls are simpler and match v1.0 behavior. |
| `context: fork` on generate skill | Inline execution (no fork) | Forked context cannot use the Skill/Agent tool to delegate further. Generate must orchestrate 6+ steps so it must run inline. |
| Bash script for env detection | Pure skill-level detection (Claude runs commands) | Bash script is testable independently, reusable by setup.sh, and produces deterministic output. Recommended. |
| sed for CLAUDE.md patching | Skill-level Edit tool | Edit tool is more reliable for markdown table updates and handles edge cases better than sed. Let the skill use the Edit tool. |

## Architecture Patterns

### Recommended Project Structure (Post Phase 7)

```
skills/
  generate/
    SKILL.md              # REFACTORED: orchestrator that calls agents + scripts
  compile/
    SKILL.md              # Phase 6 (unchanged)
  lint/
    SKILL.md              # Phase 6 (unchanged)
  simulate/
    SKILL.md              # Phase 6 (unchanged)
  testbench/
    SKILL.md              # Phase 6 (unchanged)
  requirement-parser/
    SKILL.md              # Phase 6 (unchanged)
  initialize/
    SKILL.md              # NEW: environment detection and capability mapping

scripts/
  detect-env.sh           # NEW: tool detection script producing JSON
  compile.sh              # Existing (unchanged)
  lint.sh                 # Existing (unchanged)
  simulate.sh             # Existing (unchanged)
  setup.sh                # Existing (unchanged)

.chipagent/
  env.json                # NEW: machine-readable environment capabilities
```

### Pattern 1: Inline Orchestrator Skill

**What:** The generate skill runs inline (not forked) and sequentially executes pipeline steps by reading agent definitions and calling scripts via Bash. It does NOT use `context: fork` because forked skills cannot delegate further.
**When to use:** For SKILL-06 -- the refactored generate pipeline.

The orchestrator skill:
1. Accepts `$ARGUMENTS` (hardware description) from user
2. Calls requirement-parser agent (reads `agents/requirement-parser.md`, follows its rules, writes `workspace/<Module>/spec.json`)
3. Presents spec to user for approval (Step 1.5 from current generate.md)
4. Calls chisel-generator agent (reads `agents/chisel-generator.md`, follows its rules, writes Scala files)
5. Runs `scripts/compile.sh workspace/<Module>` via Bash
6. Runs `scripts/lint.sh workspace/<Module>` via Bash
7. Calls testbench-generator agent (reads `agents/testbench-generator.md`, reads `workspace/<Module>/spec.json`, writes testbench)
8. Runs `scripts/simulate.sh workspace/<Module>` via Bash
9. Reads `workspace/<Module>/sim/logs/sim_result.log` and formats verification report

Key: Each step's error handling (retry up to 3 times) is preserved from the current generate.md.

```yaml
---
name: generate
description: Turn a natural language hardware description into simulation-verified Verilog. Orchestrates the full pipeline: parse, generate, compile, lint, testbench, simulate, report.
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---
```

### Pattern 2: Script-Backed Detection Skill

**What:** A skill that runs a detection script, reads its JSON output, and then uses the Edit tool to patch CLAUDE.md.
**When to use:** For INIT-01 through INIT-03.

```yaml
---
name: initialize
description: Detect local toolchain versions and capability. Writes .chipagent/env.json and updates CLAUDE.md with detected versions.
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
---
```

### Pattern 3: env.json Schema

**What:** Machine-readable JSON describing the local development environment.
**When to use:** Written by `/chip-agent:initialize`, read by other skills and scripts.

```json
{
  "detected_at": "2026-03-20T12:00:00Z",
  "tools": {
    "java": {
      "installed": true,
      "version": "17.0.18",
      "path": "/usr/bin/java"
    },
    "sbt": {
      "installed": true,
      "version": "1.10.7",
      "path": "/usr/bin/sbt"
    },
    "scala": {
      "installed": true,
      "version": "2.13.13",
      "path": "/usr/bin/scala"
    },
    "verilator": {
      "installed": true,
      "version": "5.008",
      "path": "/usr/local/bin/verilator"
    },
    "make": {
      "installed": true,
      "version": "4.3",
      "path": "/usr/bin/make"
    },
    "gpp": {
      "installed": true,
      "version": "12.3.0",
      "path": "/usr/bin/g++"
    }
  },
  "capabilities": {
    "can_compile": true,
    "can_lint": true,
    "can_simulate": true
  }
}
```

Capability flag logic:
- `can_compile`: `java.installed && sbt.installed` (Chisel compilation requires JDK + sbt)
- `can_lint`: `verilator.installed` (Verilator lint-only mode)
- `can_simulate`: `verilator.installed && make.installed && gpp.installed` (Verilator simulation requires Make + g++ for building)

### Pattern 4: CLAUDE.md Tech Stack Table Patching

**What:** After detecting tool versions, the initialize skill updates the Tech Stack table in CLAUDE.md with actually detected local versions.
**When to use:** As the final step of `/chip-agent:initialize` (INIT-03).

The current table format:
```markdown
| Component          | Version   | Purpose                                      |
|--------------------|-----------|----------------------------------------------|
| Chisel             | 3.6.1     | Hardware construction language (Scala DSL)    |
| Scala              | 2.13.10   | JVM language hosting Chisel (managed by sbt)  |
| sbt                | 1.10.7    | Scala build tool (pinned in build.properties) |
| FIRRTL             | built-in  | Chisel IR compiler (+ auto-managed firtool)   |
| Verilator          | 5.008+    | Verilog simulation and lint checking          |
| Claude Code Plugin | 0.1.0     | Plugin packaging and slash command framework  |
```

The initialize skill should update the Version column for rows: Scala, sbt, Verilator. Chisel and FIRRTL versions are pinned in build.sbt (not detectable from the CLI). Claude Code Plugin version is in plugin.json.

Use the Edit tool (not sed) to update individual rows. This is safer than regex replacement on markdown tables.

### Anti-Patterns to Avoid

- **Using `context: fork` on the generate skill:** Forked contexts cannot use the Agent/Task tool, which means the orchestrator cannot delegate. The generate skill MUST run inline.
- **Invoking sub-skills via the Skill tool for each pipeline step:** This creates unnecessary context overhead (each Skill invocation loads the full SKILL.md into context). Since the orchestrator already knows the pipeline, it should call agents/scripts directly.
- **Modifying sub-skill SKILL.md files from Phase 6:** Phase 7 should not change compile, lint, simulate, testbench, or requirement-parser skills. They remain standalone.
- **Running detect-env.sh with `set -e` and no error trapping for missing tools:** Missing tools (e.g., no Verilator) should produce `"installed": false` in env.json, not a script crash.
- **Hardcoding version parsing regex that breaks across OS variants:** Use defensive parsing. Java version format differs between OpenJDK and Oracle. sbt version output varies by installation method.
- **Writing env.json to `generated/` or `workspace/`:** The `.chipagent/` directory is project-level metadata, not a generated artifact. It should NOT be in the workspace or generated directories.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Pipeline orchestration framework | Custom state machine, pipeline runner class | Inline skill instructions with sequential steps | The pipeline is 7 well-defined steps. A framework adds complexity without value. |
| Version string parsing library | Custom parser for each tool's output | Simple bash: `tool --version 2>&1 \| head -1 \| grep -oP 'pattern'` | Each tool has a unique output format, but they are all simple one-liners |
| JSON generation in bash | Complex echo/printf JSON construction | `jq` or heredoc with variable interpolation | `jq` handles escaping and formatting correctly; heredoc is a fallback if jq is unavailable |
| Markdown table editor | Custom markdown parser | Claude's Edit tool | The Edit tool understands markdown structure; regex-based sed replacement is fragile |
| Capability flag computation | Complex logic with dependency trees | Three simple boolean checks (see env.json schema) | Only three flags, each with 2-3 boolean inputs. No graph traversal needed. |

**Key insight:** Phase 7 is a **glue phase**. The heavy lifting (agents, scripts, skill definitions) was done in Phases 1-6. The orchestrator just sequences existing pieces. The initializer just runs version commands and writes JSON.

## Common Pitfalls

### Pitfall 1: PostToolUse Hook Fires on Non-Scala Writes

**What goes wrong:** The existing `hooks.json` triggers `compile.sh` on ALL Write/Edit operations. The orchestrator writes spec.json, testbench .cpp, and env.json -- each triggering unnecessary sbt compilation.
**Why it happens:** The hook matcher is `Write|Edit` with no file extension filter. This was noted in STATE.md as a known issue to fix in Phase 7.
**How to avoid:** Fix the PostToolUse hook to filter on `.scala` file extensions only. Update `hooks.json` to include a file path filter, or add a guard in `compile.sh` that checks if the written file is a `.scala` file before running sbt. The guard approach is more robust since `hooks.json` currently does not support file path matchers.
**Warning signs:** Each pipeline step taking 60+ seconds due to spurious sbt invocations.

### Pitfall 2: Forked Context Cannot Orchestrate

**What goes wrong:** If `context: fork` is added to the generate skill, the forked subagent cannot use the Agent/Skill tool to delegate to further subagents.
**Why it happens:** Claude Code explicitly prevents nested subagent spawning -- "Subagents cannot spawn other subagents."
**How to avoid:** The generate skill MUST run inline (no `context: fork`). This means it runs in the main conversation context with full tool access.
**Warning signs:** Skills erroring with "Agent tool not available" or silently failing to delegate.

### Pitfall 3: Missing chisel-generate Sub-Skill

**What goes wrong:** The orchestrator tries to invoke a `/chip-agent:chisel-generate` skill that does not exist.
**Why it happens:** Phase 6 created skills for requirement-parser, compile, lint, simulate, and testbench -- but NOT for chisel-generate. The chisel-generator agent exists (`agents/chisel-generator.md`) but has no corresponding skill wrapper.
**How to avoid:** The orchestrator must handle the chisel-generate step differently from other steps. It reads the `agents/chisel-generator.md` agent definition directly and follows its instructions inline, just as the current generate.md does in Step 2.
**Warning signs:** Orchestrator failing at the "Generate Chisel" step.

### Pitfall 4: detect-env.sh Crashes on Missing Tools

**What goes wrong:** `set -euo pipefail` causes the script to exit on the first missing tool (e.g., `verilator --version` returns non-zero when Verilator is not installed).
**Why it happens:** Standard bash strict mode treats any non-zero exit as fatal.
**How to avoid:** Use `command -v tool 2>/dev/null` to check tool existence before running `tool --version`. Wrap each detection in a function that returns a JSON fragment with `"installed": false` when the tool is not found, rather than crashing.
**Warning signs:** Script exiting with error on machines that lack Verilator but have Java/sbt (valid for compile-only use).

### Pitfall 5: Version Parsing Inconsistency Across Platforms

**What goes wrong:** Version output differs across platforms. `java -version` outputs to stderr (not stdout). `sbt --version` may include ANSI color codes. `scala -version` on Scala 3 says "Scala code runner version 3.x" vs Scala 2 which says "Scala code runner version 2.x".
**Why it happens:** Each tool has its own output conventions.
**How to avoid:** Use defensive parsing:
- `java -version 2>&1 | head -1` (redirect stderr)
- `sbt --version 2>&1 | tail -1` (skip sbt banner/splash)
- `verilator --version 2>&1 | head -1` (simple one-liner)
- `make --version 2>&1 | head -1`
- `g++ --version 2>&1 | head -1`
- `scala -version 2>&1 | head -1`
**Warning signs:** Empty or malformed version strings in env.json.

### Pitfall 6: CLAUDE.md Table Row Matching

**What goes wrong:** The Edit tool (or sed) matches the wrong row when updating the Tech Stack table, corrupting other entries.
**Why it happens:** Simple pattern matching on pipe-delimited rows can be fragile if descriptions contain the same keywords.
**How to avoid:** Match on the first column (Component name) which is unique: `Scala`, `sbt`, `Verilator`. Use the Edit tool with explicit before/after context to ensure correct row identification.
**Warning signs:** Wrong row updated, or table structure broken after patching.

### Pitfall 7: Workspace Path Not Set in Orchestrator

**What goes wrong:** The orchestrator runs scripts without the workspace path argument, causing output to go to the flat-mode `generated/` directory instead of `workspace/<Module>/generated/`.
**Why it happens:** The old `generate.md` was written before workspace support existed. The refactored orchestrator must consistently use `workspace/<ModuleName>` paths.
**How to avoid:** The orchestrator must extract the module name from the requirement-parser output, then use `workspace/<ModuleName>` as the path argument for ALL subsequent script calls (compile.sh, lint.sh, simulate.sh). The testbench must also be written to `workspace/<ModuleName>/sim/tb_<ModuleName>.cpp`.
**Warning signs:** Files appearing in flat `generated/` or `sim/` instead of workspace subdirectories.

## Code Examples

### detect-env.sh Script Structure

```bash
#!/usr/bin/env bash
# Do NOT use set -e -- missing tools should produce "installed: false", not crashes

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
OUTPUT_DIR="$PLUGIN_ROOT/.chipagent"
OUTPUT_FILE="$OUTPUT_DIR/env.json"

mkdir -p "$OUTPUT_DIR"

detect_tool() {
  local name="$1"
  local cmd="$2"
  local version_cmd="$3"
  local version_regex="$4"

  local path version installed
  path=$(command -v "$cmd" 2>/dev/null || echo "")

  if [ -n "$path" ]; then
    installed=true
    version=$(eval "$version_cmd" 2>&1 | head -1 | grep -oP "$version_regex" || echo "unknown")
  else
    installed=false
    version=""
    path=""
  fi

  printf '{"installed":%s,"version":"%s","path":"%s"}' "$installed" "$version" "$path"
}

JAVA=$(detect_tool "java" "java" "java -version" '[0-9]+\.[0-9]+\.[0-9]+')
SBT=$(detect_tool "sbt" "sbt" "sbt --version 2>&1 | tail -1" '[0-9]+\.[0-9]+\.[0-9]+')
# ... (similar for scala, verilator, make, g++)

# Compute capabilities
JAVA_INSTALLED=$(echo "$JAVA" | grep -o '"installed":true' | wc -l)
SBT_INSTALLED=$(echo "$SBT" | grep -o '"installed":true' | wc -l)
# ... capability flag logic

# Write JSON (use jq if available, heredoc fallback)
```

### Orchestrator SKILL.md Step Pattern (Workspace-Aware)

Each pipeline step in the orchestrator must use workspace paths:

```markdown
### Step 3 -- Compile

Run the compilation script with the workspace path:

```
<plugin-root>/scripts/compile.sh workspace/<ModuleName>
```

If compilation fails:
1. Read the error output
2. Follow the chisel-generator agent rules to fix the Scala source
3. Maximum 3 fix attempts. After 3 failures, stop and report.
```

### Initialize SKILL.md Structure

```yaml
---
name: initialize
description: Detect local toolchain versions and write .chipagent/env.json with capability flags. Updates CLAUDE.md Tech Stack table with detected versions.
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
---

# chip-agent:initialize

Detect your local development environment and report tool availability.

## Instructions

1. Determine the plugin root directory (find .claude-plugin/plugin.json ancestor)
2. Run the detection script: <plugin-root>/scripts/detect-env.sh
3. Read the generated .chipagent/env.json
4. Update the CLAUDE.md Tech Stack table with detected versions
5. Present a summary to the user showing tool status and capabilities
```

### hooks.json Fix for PostToolUse Filtering

The current hooks.json triggers compile.sh on ALL Write/Edit operations. Fix by adding a guard in compile.sh:

```bash
# At the top of compile.sh, add early-exit guard for non-Scala files
# (hooks pass the file path as context but hooks.json doesn't support
#  file-path matchers, so the guard must be in the script itself)
if [ -n "${HOOK_FILE:-}" ]; then
  case "$HOOK_FILE" in
    *.scala) ;; # Continue with compilation
    *) exit 0 ;; # Skip non-Scala files
  esac
fi
```

Note: The hooks.json `matcher` field matches on tool name only (Write|Edit), not on file paths. A script-level guard or a wrapper script that checks the file extension is the recommended approach. Alternatively, reconsider whether the PostToolUse hook is still needed now that compile has its own skill -- the orchestrator calls compile.sh explicitly, so the hook may be redundant.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Monolithic `skills/generate.md` (legacy flat file) | `skills/generate/SKILL.md` with frontmatter, calling sub-skills | Phase 7 (this phase) | Users can still run the full pipeline via `/chip-agent:generate`, but implementation is modular |
| No environment detection | `/chip-agent:initialize` with structured env.json | Phase 7 (this phase) | Users can verify their toolchain before first use |
| Hardcoded versions in CLAUDE.md | Dynamically updated from detected local versions | Phase 7 (this phase) | CLAUDE.md always reflects the actual environment |
| PostToolUse hook on ALL writes | Filtered to .scala files only (or removed) | Phase 7 (this phase) | Eliminates spurious sbt compilations on spec.json, .cpp, .json writes |

**Deprecated/outdated:**
- `skills/generate.md` (flat file, no frontmatter): Will be replaced by `skills/generate/SKILL.md`. The old file should be removed after migration.
- `scripts/setup.sh` (partial detection): Still useful for dependency download, but environment detection moves to `scripts/detect-env.sh` and `/chip-agent:initialize`.

## Open Questions

1. **PostToolUse hook: fix or remove?**
   - What we know: The hook triggers compile.sh on ALL Write/Edit. This is documented as a Phase 7 fix target in STATE.md.
   - What's unclear: Whether the hook should be fixed (add file filter) or removed entirely (since compile now has its own skill and the orchestrator calls compile.sh explicitly).
   - Recommendation: Fix the hook by adding a file extension check. Keep the hook for the case where users manually edit Scala files outside the skill pipeline -- auto-compilation is still useful there. But the orchestrator should not rely on the hook; it should call compile.sh explicitly.

2. **Should generate skill use the Skill tool or call agents/scripts directly?**
   - What we know: Both approaches work. The Skill tool loads the full SKILL.md content each time, adding context overhead. Direct agent/script calls are lighter.
   - What's unclear: Whether future phases expect the orchestrator to use the Skill tool for traceability.
   - Recommendation: Call agents and scripts directly. The orchestrator knows the pipeline steps -- indirecting through sub-skills adds overhead without benefit. The sub-skills exist for standalone user invocation, not for orchestrator use.

3. **Should .chipagent/ be gitignored?**
   - What we know: `env.json` contains machine-specific data (paths, versions). It should NOT be committed.
   - What's unclear: Whether other files will go in `.chipagent/` in the future.
   - Recommendation: Add `.chipagent/` to `.gitignore`. The data is local-only and reproducible via `/chip-agent:initialize`.

4. **Scala version detection: CLI vs. sbt?**
   - What we know: `scala -version` reports the system Scala version (e.g., 2.13.13). But Chisel uses the Scala version pinned in build.sbt (2.13.10). These may differ.
   - What's unclear: Which version to report in env.json -- system Scala or project Scala.
   - Recommendation: Report system Scala from `scala -version` in env.json (that is what is installed). Add a note in the initialize summary that the project pins Scala 2.13.10 in build.sbt regardless of system version (sbt manages its own Scala).

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Bash test scripts (project convention from Phases 1-6) |
| Config file | None -- self-contained scripts |
| Quick run command | `bash scripts/test-phase7.sh` |
| Full suite command | `bash scripts/test-phase7.sh` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SKILL-06 | generate skill exists as SKILL.md with frontmatter | smoke | `bash scripts/test-phase7.sh` (check 1-3) | Wave 0 |
| SKILL-06 | generate skill references all pipeline stages | smoke | `bash scripts/test-phase7.sh` (check 4-5) | Wave 0 |
| INIT-01 | initialize skill exists as SKILL.md with frontmatter | smoke | `bash scripts/test-phase7.sh` (check 6) | Wave 0 |
| INIT-01 | detect-env.sh runs and produces JSON output | unit | `bash scripts/test-phase7.sh` (check 7-8) | Wave 0 |
| INIT-02 | env.json has correct schema (tools, capabilities) | unit | `bash scripts/test-phase7.sh` (check 9-11) | Wave 0 |
| INIT-03 | CLAUDE.md update logic present in initialize skill | smoke | `bash scripts/test-phase7.sh` (check 12) | Wave 0 |

Note: Full end-to-end orchestrator testing requires human verification by running `/chip-agent:generate` in Claude Code. The test script can verify:
- SKILL.md files exist with correct frontmatter and pipeline references
- detect-env.sh produces valid JSON
- env.json schema has required fields
- Old generate.md is removed after migration
- .chipagent/ is gitignored

### Sampling Rate

- **Per task commit:** `bash scripts/test-phase7.sh`
- **Per wave merge:** `bash scripts/test-phase7.sh`
- **Phase gate:** Full suite green + manual `/chip-agent:generate` and `/chip-agent:initialize` invocation before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `scripts/test-phase7.sh` -- covers structural verification for orchestrator + initialize
- [ ] `scripts/detect-env.sh` -- environment detection script
- [ ] `skills/generate/SKILL.md` -- refactored orchestrator (replaces skills/generate.md)
- [ ] `skills/initialize/SKILL.md` -- new environment detection skill
- [ ] `.chipagent/` added to `.gitignore`

## Sources

### Primary (HIGH confidence)
- `skills/generate.md` -- existing monolithic pipeline (178 lines, verified content and structure)
- `skills/compile/SKILL.md` -- Phase 6 script-wrapper skill pattern (verified)
- `skills/lint/SKILL.md` -- Phase 6 script-wrapper skill pattern (verified)
- `skills/simulate/SKILL.md` -- Phase 6 script-wrapper skill pattern (verified)
- `skills/requirement-parser/SKILL.md` -- Phase 6 agent-backed skill pattern (verified)
- `skills/testbench/SKILL.md` -- Phase 6 agent-backed skill pattern (verified)
- `agents/chisel-generator.md` -- Chisel code generation agent (verified, 346 lines)
- `agents/requirement-parser.md` -- NL-to-JSON parsing agent (verified)
- `agents/testbench-generator.md` -- C++ testbench generation agent (verified)
- `scripts/compile.sh` -- workspace-aware compilation (76 lines, verified)
- `scripts/lint.sh` -- workspace-aware linting (86 lines, verified)
- `scripts/simulate.sh` -- workspace-aware simulation (80 lines, verified)
- `scripts/setup.sh` -- existing detection logic for Java/sbt/Verilator (67 lines, verified)
- `hooks/hooks.json` -- PostToolUse hook definition (verified)
- `.planning/REQUIREMENTS.md` -- requirement definitions SKILL-06, INIT-01 through INIT-03
- `.planning/STATE.md` -- "PostToolUse hook fires on .cpp writes" and "How does Claude invoke one skill from within another skill?" noted as Phase 7 concerns

### Secondary (MEDIUM confidence)
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills) -- SKILL.md frontmatter reference, `context: fork` behavior, Skill tool invocation, `$ARGUMENTS` substitution, `${CLAUDE_SKILL_DIR}` variable
- [Claude Code Subagents Documentation](https://code.claude.com/docs/en/sub-agents) -- Subagent spawning constraints ("Subagents cannot spawn other subagents"), chaining pattern, inline vs forked execution
- [GitHub Issue #17283](https://github.com/anthropics/claude-code/issues/17283) -- Feature request confirming Skill tool does not honor `context: fork` and `agent:` fields when invoked programmatically
- Local tool version verification: `java -version`, `sbt --version`, `scala -version`, `verilator --version`, `make --version`, `g++ --version` all tested on this machine

### Tertiary (LOW confidence)
- None -- all findings verified against official docs or direct project inspection

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- All components are existing project infrastructure or well-documented Claude Code features
- Architecture: HIGH -- Orchestrator pattern directly follows existing generate.md structure; environment detection follows standard CLI conventions
- Pitfalls: HIGH -- Identified from project STATE.md (hook issue, skill-to-skill question), official docs (forked context limitations), and direct testing of version detection commands

**Research date:** 2026-03-20
**Valid until:** 2026-04-20 (stable -- based on project infrastructure and Claude Code stable features)
