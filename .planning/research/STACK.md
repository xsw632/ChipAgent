# Technology Stack: v1.1 Modular Commands & Workspace Isolation

**Project:** ChipAgent
**Milestone:** v1.1 Refine (Modular Slash Commands + Workspace Isolation)
**Researched:** 2026-03-19
**Confidence:** HIGH (plugin architecture verified against official Claude Code docs; env detection verified on target machine)

## Scope

This document covers ONLY the stack additions/changes needed for v1.1. The existing validated stack (Chisel 3.6.1, Scala 2.13.10, sbt 1.10.7, Verilator 5.008, npm packaging) is not re-researched.

v1.1 introduces four new capabilities:
1. Multiple slash commands in a single plugin (modular pipeline)
2. JSON spec-file schema for inter-agent communication
3. Environment detection via `/chip-agent:initialize`
4. Per-module workspace directory management

---

## 1. Multi-Skill Plugin Architecture

### Current State

ChipAgent v1.0 uses a single skill file at `skills/generate.md` (legacy `commands/`-style flat file). This creates the `/chip-agent:generate` slash command. The `hooks/hooks.json` triggers compilation on every Write/Edit event.

### What Changes for v1.1

Migrate from a single flat skill file to the modern `skills/<name>/SKILL.md` directory structure. Each pipeline stage becomes its own skill, namespaced under `chip-agent:`.

### Recommended Plugin Directory Structure

```
ChipAgent/
  .claude-plugin/
    plugin.json                          # Updated manifest (see schema below)
  skills/
    generate/
      SKILL.md                           # /chip-agent:generate (orchestrator)
    initialize/
      SKILL.md                           # /chip-agent:initialize (env detection)
    parse/
      SKILL.md                           # /chip-agent:parse (requirement parsing)
    lint/
      SKILL.md                           # /chip-agent:lint (Verilator lint)
    testbench/
      SKILL.md                           # /chip-agent:testbench (testbench gen)
    simulate/
      SKILL.md                           # /chip-agent:simulate (run simulation)
    debug/
      SKILL.md                           # /chip-agent:debug (debug failures)
      reference.md                       # Debug patterns reference
  agents/
    requirement-parser.md                # Existing (unchanged)
    chisel-generator.md                  # Existing (unchanged)
    testbench-generator.md               # Existing (unchanged)
  hooks/
    hooks.json                           # Updated (workspace-aware compile)
  scripts/
    compile.sh                           # Updated (workspace-aware)
    lint.sh                              # Updated (workspace-aware)
    simulate.sh                          # Updated (workspace-aware)
    setup.sh                             # Replaced by /chip-agent:initialize
    detect-env.sh                        # NEW: environment detection script
    validate-spec.sh                     # NEW: JSON spec validation
  schemas/
    spec-simple.schema.json              # NEW: JSON Schema for simple specs
    spec-complex.schema.json             # NEW: JSON Schema for complex specs
    environment.schema.json              # NEW: JSON Schema for env report
```

### Updated plugin.json Manifest

```json
{
  "name": "chip-agent",
  "version": "1.1.0",
  "description": "Turns NL hardware descriptions into simulation-verified Verilog",
  "author": {
    "name": "ChipAgent Team"
  },
  "keywords": ["claude-code", "plugin", "chisel", "verilog", "hardware", "hdl"]
}
```

**Why no custom component paths:** Claude Code auto-discovers `skills/`, `agents/`, `hooks/`, and `commands/` at the plugin root. Custom path overrides in plugin.json are only needed for non-standard locations. Keeping defaults is simpler and matches all documentation examples.

**Confidence:** HIGH -- verified against official Claude Code plugin docs at code.claude.com/docs/en/plugins-reference.

### SKILL.md Frontmatter Pattern

Each skill uses YAML frontmatter to control invocation:

```yaml
# For pipeline stage skills (manual-only, user invokes explicitly):
---
name: lint
description: Run Verilator lint checks on generated Verilog for a specific module
disable-model-invocation: true
---

# For the orchestrator (manual-only, since it triggers the full pipeline):
---
name: generate
description: Turn a natural language hardware description into simulation-verified Verilog
disable-model-invocation: true
---

# For background knowledge skills (Claude invokes when relevant):
---
name: debug
description: Debug hardware generation pipeline failures. Use when compilation, lint, or simulation fails.
user-invocable: true
---
```

**Key frontmatter fields used:**

| Field | Value | Purpose |
|-------|-------|---------|
| `name` | skill name | Creates `/chip-agent:<name>` command |
| `description` | natural language | Claude uses this for auto-invocation decisions |
| `disable-model-invocation` | `true` | Prevents Claude from auto-triggering pipeline stages |
| `allowed-tools` | tool list | Restricts what Claude can do within the skill |
| `context` | `fork` | Runs skill in isolated subagent (for parallel stages) |
| `agent` | agent name | Specifies which agent config to use with `context: fork` |

### Skill Argument Passing

Skills receive arguments via `$ARGUMENTS` substitution:

```yaml
---
name: lint
description: Run Verilator lint on a module's generated Verilog
disable-model-invocation: true
---

## Lint Module

Run Verilator lint checks on the module specified by $ARGUMENTS.

Workspace: workspace/$ARGUMENTS/
```

Invocation: `/chip-agent:lint ALU` replaces `$ARGUMENTS` with `ALU`.

For positional arguments: `$ARGUMENTS[0]` or shorthand `$0`, `$1`, etc.

### Plugin Environment Variables

Two variables are available in skill content, hook commands, and MCP/LSP configs:

| Variable | Value | Use |
|----------|-------|-----|
| `${CLAUDE_PLUGIN_ROOT}` | Absolute path to plugin directory | Reference scripts, schemas, templates |
| `${CLAUDE_PLUGIN_DATA}` | Persistent data directory (~/.claude/plugins/data/chip-agent/) | Cache env detection results, workspace state |
| `${CLAUDE_SKILL_DIR}` | Directory containing the skill's SKILL.md | Reference supporting files within a skill |

### Migration Path from v1.0

The existing `skills/generate.md` (flat file) needs to move to `skills/generate/SKILL.md` (directory format). The `commands/` directory is legacy but still works -- Claude Code checks both. Since ChipAgent currently uses `skills/generate.md` as a flat file, it must be restructured:

1. Create `skills/generate/SKILL.md` with the existing content plus frontmatter
2. Delete `skills/generate.md`
3. Add new skill directories for each pipeline stage
4. Keep `agents/` and `hooks/` at plugin root (already correct)

**Confidence:** HIGH -- verified against official Claude Code skills docs and plugins reference.

---

## 2. JSON Spec Schema for Inter-Agent Communication

### Current State

The requirement-parser agent outputs a JSON spec (simple or complex type) that the chisel-generator and testbench-generator agents consume. The spec format is defined only in the agents' SKILL.md documentation as examples. There is no machine-readable schema or validation.

### Recommended Approach: JSON Schema (Draft 2020-12) + jq Validation

**Use JSON Schema files** stored in `schemas/` as the authoritative contract between agents. Validate using `jq` (already needed by hooks) for lightweight checking, with a fallback to Python `jsonschema` for full schema validation if available.

**Why JSON Schema over alternatives:**
- JSON Schema is a well-established standard for describing JSON structure
- It serves as both documentation and machine-checkable contract
- The schemas live in the plugin directory and are always available
- `jq` can perform structural validation (field presence, type checks) without external dependencies
- Python `jsonschema` provides full validation when available (Python is pre-installed for most dev environments)

**Why NOT use ajv-cli or other Node tools:** ChipAgent's plugin runtime is static files (markdown, JSON, bash). Adding Node.js runtime dependencies for validation contradicts the plugin's zero-dependency design. Use jq for basic checks and optionally Python for full schema validation.

### Schema Files

**`schemas/spec-simple.schema.json`** -- validates simple module specs:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "chip-agent/spec-simple",
  "title": "Simple Module Specification",
  "type": "object",
  "required": ["moduleName", "description", "type", "bitWidth", "ports"],
  "properties": {
    "moduleName": {
      "type": "string",
      "pattern": "^[A-Z][A-Za-z0-9]+$",
      "description": "PascalCase module name"
    },
    "description": { "type": "string" },
    "type": { "const": "simple" },
    "bitWidth": { "type": "integer", "minimum": 1 },
    "ports": {
      "type": "array",
      "minItems": 2,
      "items": {
        "type": "object",
        "required": ["name", "direction", "type", "width"],
        "properties": {
          "name": { "type": "string", "pattern": "^[a-z][A-Za-z0-9]*$" },
          "direction": { "enum": ["input", "output"] },
          "type": { "enum": ["UInt", "SInt", "Bool"] },
          "width": { "type": "integer", "minimum": 1 }
        }
      }
    },
    "operations": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["opcode", "name", "expression"],
        "properties": {
          "opcode": { "type": "integer", "minimum": 0 },
          "name": { "type": "string", "pattern": "^[A-Z][A-Z0-9_]*$" },
          "expression": { "type": "string" }
        }
      }
    },
    "flags": { "type": "array" },
    "constraints": { "type": "array", "items": { "type": "string" } }
  }
}
```

**`schemas/spec-complex.schema.json`** -- validates complex (multi-module) specs with the same pattern but requiring `modules[]` and `topModule`.

### Validation Script Pattern

**`scripts/validate-spec.sh`** -- lightweight jq-based validation:

```bash
#!/usr/bin/env bash
set -euo pipefail

SPEC_FILE="$1"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# Basic JSON syntax check
if ! jq empty "$SPEC_FILE" 2>/dev/null; then
  echo "VALIDATION ERROR: Invalid JSON syntax in $SPEC_FILE"
  exit 1
fi

# Extract type and validate required fields
TYPE=$(jq -r '.type // empty' "$SPEC_FILE")
MODULE_NAME=$(jq -r '.moduleName // empty' "$SPEC_FILE")

if [ -z "$TYPE" ] || [ -z "$MODULE_NAME" ]; then
  echo "VALIDATION ERROR: Missing required fields 'type' and/or 'moduleName'"
  exit 1
fi

# Type-specific structural checks
case "$TYPE" in
  simple)
    # Check required fields for simple spec
    jq -e '.ports | length >= 2' "$SPEC_FILE" >/dev/null 2>&1 || {
      echo "VALIDATION ERROR: Simple spec requires at least 2 ports"
      exit 1
    }
    # Verify at least one input and one output port
    jq -e '[.ports[] | select(.direction == "input")] | length > 0' "$SPEC_FILE" >/dev/null 2>&1 || {
      echo "VALIDATION ERROR: Simple spec requires at least one input port"
      exit 1
    }
    jq -e '[.ports[] | select(.direction == "output")] | length > 0' "$SPEC_FILE" >/dev/null 2>&1 || {
      echo "VALIDATION ERROR: Simple spec requires at least one output port"
      exit 1
    }
    ;;
  complex)
    # Check required fields for complex spec
    jq -e '.modules | length >= 2' "$SPEC_FILE" >/dev/null 2>&1 || {
      echo "VALIDATION ERROR: Complex spec requires at least 2 sub-modules"
      exit 1
    }
    jq -e '.topModule.submodules | length >= 2' "$SPEC_FILE" >/dev/null 2>&1 || {
      echo "VALIDATION ERROR: Complex spec topModule must list at least 2 submodules"
      exit 1
    }
    ;;
  *)
    echo "VALIDATION ERROR: Unknown spec type '$TYPE' (expected 'simple' or 'complex')"
    exit 1
    ;;
esac

echo "VALIDATION PASSED: $MODULE_NAME ($TYPE)"
exit 0
```

**Full schema validation (optional, when Python is available):**

```bash
# If python3 and jsonschema are available, do full validation:
if command -v python3 >/dev/null 2>&1 && python3 -c "import jsonschema" 2>/dev/null; then
  SCHEMA_FILE="$PLUGIN_ROOT/schemas/spec-${TYPE}.schema.json"
  python3 -c "
import json, jsonschema, sys
with open('$SCHEMA_FILE') as f: schema = json.load(f)
with open('$SPEC_FILE') as f: spec = json.load(f)
try:
    jsonschema.validate(spec, schema)
    print('FULL SCHEMA VALIDATION PASSED')
except jsonschema.ValidationError as e:
    print(f'SCHEMA ERROR: {e.message}')
    sys.exit(1)
"
fi
```

### Spec File Naming Convention

Spec files are stored per-module in the workspace directory:

```
workspace/<ModuleName>/spec.json       # The parsed spec
workspace/<ModuleName>/env.json        # Environment detection results (from initialize)
```

**Confidence:** HIGH for jq-based validation (jq is standard and already referenced in Claude Code hook docs). MEDIUM for Python jsonschema (requires checking availability at runtime).

---

## 3. Environment Detection

### Current State

`scripts/setup.sh` does basic tool presence checking (java, sbt, verilator) with manual version parsing. It prints results to stdout but does not produce machine-readable output. It also pre-downloads sbt dependencies.

### Recommended Approach: `scripts/detect-env.sh` Producing JSON

Create a dedicated detection script that produces structured JSON output. The `/chip-agent:initialize` skill invokes this script and saves the result as `workspace/.environment.json` (project-level, shared across modules).

### Environment Detection Commands

Verified on the target machine (2026-03-19):

| Tool | Detection Command | Output Format | Parse Method |
|------|-------------------|---------------|-------------|
| Java | `java -version 2>&1 \| head -1` | `openjdk version "17.0.18" 2026-01-20` | `sed 's/.*"\([^"]*\)".*/\1/'` |
| sbt (binary) | `sbt --version 2>&1 \| tail -1` | `sbt script version: 1.10.7` | `awk '{print $NF}'` |
| sbt (project) | `cat project/build.properties` | `sbt.version=1.10.7` | `grep sbt.version \| cut -d= -f2` |
| Scala (sbt) | `grep scalaVersion build.sbt` | `scalaVersion := "2.13.10"` | `grep -o '"[^"]*"' \| tr -d '"'` |
| Verilator | `verilator --version 2>&1` | `Verilator 5.008 2023-03-04 rev v5.008` | `awk '{print $2}'` |
| Chisel | `grep chiselVersion build.sbt` | `val chiselVersion = "3.6.1"` | `grep -o '"[^"]*"' \| tr -d '"'` |
| firtool | `firtool --version 2>&1` | (auto-managed, may not be in PATH) | Check after first sbt compile |

### detect-env.sh Output Schema

```json
{
  "timestamp": "2026-03-19T23:30:00Z",
  "status": "ready|degraded|missing",
  "tools": {
    "java": {
      "available": true,
      "version": "17.0.18",
      "path": "/usr/bin/java",
      "meets_minimum": true,
      "minimum": "11"
    },
    "sbt": {
      "available": true,
      "version": "1.10.7",
      "path": "/usr/bin/sbt",
      "project_version": "1.10.7",
      "meets_minimum": true,
      "minimum": "1.9.0"
    },
    "scala": {
      "available": true,
      "version": "2.13.10",
      "source": "build.sbt",
      "meets_minimum": true,
      "minimum": "2.13.10"
    },
    "chisel": {
      "available": true,
      "version": "3.6.1",
      "source": "build.sbt",
      "meets_minimum": true,
      "minimum": "3.6.0"
    },
    "verilator": {
      "available": true,
      "version": "5.008",
      "path": "/usr/local/bin/verilator",
      "meets_minimum": true,
      "minimum": "5.000"
    }
  },
  "chisel_project": {
    "path": "chisel-project",
    "build_sbt_exists": true,
    "build_properties_exists": true
  },
  "warnings": [],
  "errors": []
}
```

### Version Comparison Pattern

Use `sort -V` for version comparison in bash (verified available on Linux):

```bash
version_gte() {
  # Returns 0 (true) if $1 >= $2
  [ "$(printf '%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

# Usage:
if version_gte "$VERILATOR_VERSION" "5.000"; then
  echo "Verilator meets minimum"
fi
```

**Why not use semver libraries:** The versions we compare are simple dotted numbers (5.008, 1.10.7, 2.13.10). `sort -V` handles all these correctly. No external dependency needed.

### Status Levels

| Status | Meaning | When |
|--------|---------|------|
| `ready` | All required tools available and meet minimums | Full pipeline can run |
| `degraded` | Required tools present but Verilator missing or below minimum | Compile works, lint/sim will fail |
| `missing` | Java or sbt not found | Cannot compile at all |

**Confidence:** HIGH -- all detection commands verified on the target machine with actual output samples.

---

## 4. Workspace Directory Management

### Current State

v1.0 uses flat directories: `generated/` for all Verilog output, `sim/` for all testbenches, `sim/logs/` for all simulation logs. This means generating a new module overwrites the previous module's artifacts. `Generate.scala` is rewritten each time to point at the new module.

### Recommended Approach: Per-Module `workspace/` Directories

Each module gets its own isolated workspace under `workspace/<ModuleName>/`:

```
workspace/
  .environment.json                    # Shared env detection result
  ALU/
    spec.json                          # Parsed specification
    generated/
      ALU.v                            # Generated Verilog
      ALU.sv                           # Generated SystemVerilog
      lint-warnings.log                # Lint warnings for this module
    sim/
      tb_ALU.cpp                       # Testbench source
      obj_dir/                         # Verilator build artifacts
      logs/
        sim_result.log                 # Simulation results
  Decoder3to8/
    spec.json
    generated/
      Decoder3to8.v
      ...
    sim/
      tb_Decoder3to8.cpp
      ...
```

### Workspace Management Patterns

**Creation:** Create workspace on first use within a pipeline stage:

```bash
ensure_workspace() {
  local MODULE_NAME="$1"
  local WORKSPACE="$PLUGIN_ROOT/workspace/$MODULE_NAME"
  mkdir -p "$WORKSPACE/generated" "$WORKSPACE/sim/logs"
  echo "$WORKSPACE"
}
```

**Isolation:** Each script receives the module name and derives paths from it:

```bash
# In compile.sh:
MODULE="${1:?Module name required}"
WORKSPACE="$PLUGIN_ROOT/workspace/$MODULE"
OUTPUT_DIR="$WORKSPACE/generated"

sbt --batch "runMain chipagent.Generate --target-dir $OUTPUT_DIR --module $MODULE"
```

**Cleanup:** No automatic cleanup. Workspaces persist across sessions so users can inspect artifacts. Add an explicit cleanup skill if needed later.

### Generate.scala Changes

The existing `Generate.scala` already supports `--target-dir` and `--module` arguments. No Scala code changes needed for workspace isolation -- the scripts just pass different `--target-dir` values per module.

Current command:
```bash
sbt --batch "runMain chipagent.Generate --target-dir ../generated"
```

v1.1 command:
```bash
sbt --batch "runMain chipagent.Generate --target-dir $WORKSPACE/generated --module $MODULE"
```

### Updated Script Signatures

All scripts become workspace-aware by accepting a module name:

| Script | v1.0 Signature | v1.1 Signature |
|--------|----------------|----------------|
| `compile.sh` | (no args, uses `generated/`) | `compile.sh <ModuleName>` |
| `lint.sh` | (no args, lints all `generated/*.v`) | `lint.sh <ModuleName>` |
| `simulate.sh` | `simulate.sh <ModuleName>` | `simulate.sh <ModuleName>` (path changes only) |

### Hooks Update

The PostToolUse hook on Write/Edit currently triggers compilation unconditionally. For v1.1, the hook must become workspace-aware. Two options:

**Option A: Remove the auto-compile hook.** Let the orchestrator skill handle compilation explicitly. This is simpler and avoids hook-triggered compiles during non-pipeline file edits.

**Option B: Make the hook workspace-aware** by extracting the module name from the written file path:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/compile-if-chisel.sh"
          }
        ]
      }
    ]
  }
}
```

Where `compile-if-chisel.sh` reads the hook's JSON stdin, extracts the file path, checks if it is a Chisel `.scala` file under `chisel-project/`, and only then runs compilation.

**Recommendation: Option A (remove auto-compile hook).** The v1.1 orchestrator skill explicitly runs `compile.sh <ModuleName>` at the right time. The hook-based auto-compile was useful for v1.0's single-module flow but becomes problematic with multiple modules (which module to compile? which workspace to target?). Removing it also eliminates the infinite-loop risk documented in CLAUDE.md ("Skill-orchestrated lint (no hooks)").

### .gitignore Update

Add `workspace/` to `.gitignore` since all artifacts are reproducible:

```
workspace/
```

Keep the existing `generated/` gitignore for backward compatibility during migration.

**Confidence:** HIGH -- workspace pattern uses standard bash `mkdir -p` and path manipulation. No new dependencies.

---

## Stack Summary: What Changes for v1.1

### New Files to Create

| File | Purpose |
|------|---------|
| `skills/generate/SKILL.md` | Replaces `skills/generate.md` |
| `skills/initialize/SKILL.md` | Environment detection skill |
| `skills/parse/SKILL.md` | Requirement parsing skill |
| `skills/lint/SKILL.md` | Verilator lint skill |
| `skills/testbench/SKILL.md` | Testbench generation skill |
| `skills/simulate/SKILL.md` | Simulation skill |
| `skills/debug/SKILL.md` | Debug assistance skill |
| `scripts/detect-env.sh` | JSON-producing environment detection |
| `scripts/validate-spec.sh` | jq-based spec validation |
| `schemas/spec-simple.schema.json` | Simple module spec schema |
| `schemas/spec-complex.schema.json` | Complex module spec schema |
| `schemas/environment.schema.json` | Environment report schema |

### Files to Modify

| File | Change |
|------|--------|
| `.claude-plugin/plugin.json` | Update version to 1.1.0 |
| `scripts/compile.sh` | Accept `<ModuleName>` arg, workspace-aware output dir |
| `scripts/lint.sh` | Accept `<ModuleName>` arg, lint module-specific Verilog |
| `scripts/simulate.sh` | Update paths to workspace-relative |
| `hooks/hooks.json` | Remove auto-compile hook (orchestrator handles it) |
| `.gitignore` | Add `workspace/` |

### Files to Delete

| File | Reason |
|------|--------|
| `skills/generate.md` | Replaced by `skills/generate/SKILL.md` |
| `scripts/setup.sh` | Replaced by `/chip-agent:initialize` skill + `detect-env.sh` |

### No New Runtime Dependencies

All v1.1 features use existing tools:
- `jq` -- JSON processing in validation and hooks (standard on Linux, already referenced in Claude Code hook docs)
- `bash` -- scripting (already used)
- `mkdir -p` -- workspace creation (POSIX standard)
- `sort -V` -- version comparison (GNU coreutils, already on system)

**Optional:** Python `jsonschema` for full JSON Schema validation. Not required; the jq-based validation handles structural checks.

---

## Alternatives Considered

| Recommended | Alternative | Why Not |
|-------------|-------------|---------|
| `skills/<name>/SKILL.md` directories | `commands/<name>.md` flat files | commands/ is legacy; skills/ supports frontmatter, supporting files, auto-invocation control |
| jq-based spec validation | ajv-cli (Node.js) | Adds Node.js runtime dependency to a static-file plugin; jq is lighter |
| jq-based spec validation | Python jsonschema | Python may not be available; jq handles structural checks; Python is optional fallback |
| Per-module `workspace/` dirs | Flat `generated/` + `sim/` with prefixes | Directory isolation is cleaner; avoids file name collisions; makes cleanup easier |
| Remove auto-compile hook | Workspace-aware auto-compile hook | Simpler; avoids "which module?" ambiguity; eliminates infinite-loop risk |
| `sort -V` for version comparison | semver npm package | No dependency needed; sort -V handles all version formats used in this project |
| JSON files for spec/env | YAML files | JSON is native to the existing spec format; no yaml parser needed |

---

## Sources

- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills) -- SKILL.md format, frontmatter reference, $ARGUMENTS substitution, auto-invocation control (HIGH confidence)
- [Claude Code Plugins Documentation](https://code.claude.com/docs/en/plugins) -- Plugin directory structure, plugin.json manifest, namespacing, installation (HIGH confidence)
- [Claude Code Plugins Reference](https://code.claude.com/docs/en/plugins-reference) -- Complete manifest schema, hook events, environment variables, debugging (HIGH confidence)
- [JSON Schema Specification](https://json-schema.org/draft/2020-12/schema) -- Draft 2020-12 schema standard (HIGH confidence)
- [sbt Command Line Reference](https://www.scala-sbt.org/1.x/docs/Command-Line-Reference.html) -- sbt --batch mode, --version flag (HIGH confidence)
- [Verilator Documentation](https://verilator.org/guide/latest/) -- verilator --version output format (HIGH confidence)
- Target machine tool versions verified via local CLI commands on 2026-03-19 (HIGH confidence)

---
*Stack research for: ChipAgent v1.1 -- Modular Slash Commands + Workspace Isolation*
*Researched: 2026-03-19*
