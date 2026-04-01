# Phase 9: Environment + SDC Foundation - Research

**Researched:** 2026-03-31
**Domain:** PnR tool detection, PDK validation, SDC constraint generation
**Confidence:** HIGH

## Summary

Phase 9 extends the existing `/chip-agent:initialize` environment detection to cover Yosys, OpenROAD, KLayout, and the nangate45 PDK, adds a pre-flight PDK validation script, and implements automatic SDC constraint generation from Chisel-generated Verilog. This phase is foundational -- all downstream phases (synthesis, PnR, GDS export) depend on correct tool paths, validated PDK files, and appropriate SDC constraints.

The existing `detect-env.sh` script (145 lines) already has a well-structured `detect_tool` function and JSON output pattern. Extending it for three new tools (yosys, openroad, klayout) and PDK path detection is straightforward. The SDC generation is the intellectually harder piece: Chisel's `Module` base class always emits `clock` and `reset` ports even for combinational logic, so detection must look for actual register usage (`always @(posedge`) rather than just clock port presence. All three tools are verified installed on this machine: Yosys 0.53+26, OpenROAD 26Q1, KLayout 0.30.7.

**Primary recommendation:** Extend `detect-env.sh` with yosys/openroad/klayout detection and nangate45 PDK path discovery, create `scripts/validate-pdk.sh` for pre-flight checks, and create `scripts/generate_sdc.sh` for clock-aware SDC generation using Verilog register analysis.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| ENV-01 | `/chip-agent:initialize` detects Yosys, OpenROAD, KLayout versions and nangate45 PDK path in env.json | Extend existing `detect-env.sh` with 3 new `detect_tool` calls + PDK path search; update `initialize` skill SKILL.md to reflect new fields |
| ENV-02 | Pre-flight PDK validation script checks liberty, LEF, and GDS files exist before running PnR | New `scripts/validate-pdk.sh` that reads PDK path from env.json and checks 5 required files; exits non-zero with clear message on missing file |
| SYN-02 | SDC auto-generation detects clock ports from Verilog, creates `create_clock` for sequential or virtual clock + `set_max_delay` for combinational modules | New `scripts/generate_sdc.sh` with Verilog register analysis (`always @(posedge`), sequential/combinational SDC templates, 2.0ns default period |
</phase_requirements>

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Yosys | 0.53+26 | Logic synthesis (detected, not invoked in this phase) | Already installed at `/usr/local/bin/yosys` |
| OpenROAD | 26Q1 | Place-and-route (detected, not invoked in this phase) | Already installed at `/usr/bin/openroad` |
| KLayout | 0.30.7 | GDS export (detected, not invoked in this phase) | Already installed at `/usr/bin/klayout` |
| nangate45 PDK | ORFS bundled | Standard cell library, LEF, GDS | At `/home/mingzhenjia/OpenROAD-flow-scripts/flow/platforms/nangate45/` |

### Supporting

| Tool | Purpose | When to Use |
|------|---------|-------------|
| bash/grep | SDC generation from Verilog analysis | Clock detection heuristic |
| jq | JSON output in detect-env.sh | Already used in existing detect-env.sh |

### No New Dependencies

This phase adds no new software dependencies. It uses only bash, grep, and the existing script infrastructure.

## Architecture Patterns

### Recommended Project Structure Changes

```
scripts/
  detect-env.sh          # MODIFIED: add yosys, openroad, klayout, nangate45 detection
  validate-pdk.sh        # NEW: pre-flight PDK file validation
  generate_sdc.sh        # NEW: auto-generate SDC from Verilog analysis
skills/
  initialize/SKILL.md    # MODIFIED: document new env.json fields in output
```

### Pattern 1: Extend detect-env.sh (Not Replace)

**What:** Add three new `detect_tool` calls and a PDK path search to the existing `detect-env.sh`. Add new JSON fields to `env.json` output.
**When to use:** ENV-01 implementation.
**Why:** The existing script already has the `detect_tool` function, JSON output with jq, and human-readable summary. Adding fields follows the established pattern exactly.

**New detect_tool calls:**
```bash
# Yosys
detect_tool "yosys" "yosys" "yosys --version 2>&1 | head -1" '[0-9]+\.[0-9]+(\+[0-9]+)?'

# OpenROAD
detect_tool "openroad" "openroad" "openroad -version 2>&1 | head -1" '[0-9]+Q[0-9](-[0-9]+-g[a-f0-9]+)?'

# KLayout
detect_tool "klayout" "klayout" "klayout -v 2>&1 | head -1" '[0-9]+\.[0-9]+\.[0-9]+'
```

**New PDK detection:**
```bash
NANGATE45_DIR=""
NANGATE45_INSTALLED="false"
for candidate in \
    "${NANGATE45_DIR:-}" \
    "${ORFS_DIR:-}/flow/platforms/nangate45" \
    "$HOME/OpenROAD-flow-scripts/flow/platforms/nangate45" \
    "/opt/OpenROAD-flow-scripts/flow/platforms/nangate45"; do
  if [ -n "$candidate" ] && [ -f "${candidate}/lib/NangateOpenCellLibrary_typical.lib" ]; then
    NANGATE45_DIR="$candidate"
    NANGATE45_INSTALLED="true"
    break
  fi
done
```

**New env.json fields (extend existing JSON):**
```json
{
  "tools": {
    "yosys":    { "installed": true,  "version": "0.53+26", "path": "/usr/local/bin/yosys" },
    "openroad": { "installed": true,  "version": "26Q1",    "path": "/usr/bin/openroad" },
    "klayout":  { "installed": true,  "version": "0.30.7",  "path": "/usr/bin/klayout" }
  },
  "pdk": {
    "nangate45": {
      "installed": true,
      "path": "/home/mingzhenjia/OpenROAD-flow-scripts/flow/platforms/nangate45",
      "liberty": "lib/NangateOpenCellLibrary_typical.lib",
      "tech_lef": "lef/NangateOpenCellLibrary.tech.lef",
      "cell_lef": "lef/NangateOpenCellLibrary.macro.mod.lef",
      "gds": "gds/NangateOpenCellLibrary.gds"
    }
  },
  "capabilities": {
    "can_synthesize": true,
    "can_pnr": true,
    "can_gds": true
  }
}
```

**Capability logic:**
- `can_synthesize` = yosys installed AND nangate45 liberty exists
- `can_pnr` = openroad installed AND nangate45 LEF + liberty exist
- `can_gds` = klayout installed AND nangate45 GDS exists

### Pattern 2: Pre-Flight PDK Validation Script

**What:** `scripts/validate-pdk.sh` reads the nangate45 path from `.chipagent/env.json` (or env var override) and verifies 5 required files exist. Exits non-zero with a clear, file-specific error message if any are missing.
**When to use:** Called at the start of synth.sh, pnr.sh, or the future `/chip-agent:pnr` skill before any tool invocation.

**Required files to validate:**
1. `lib/NangateOpenCellLibrary_typical.lib` (liberty -- timing/power for synthesis + STA)
2. `lef/NangateOpenCellLibrary.tech.lef` (technology LEF -- metal layers, routing rules)
3. `lef/NangateOpenCellLibrary.macro.mod.lef` (cell LEF -- standard cell geometries)
4. `gds/NangateOpenCellLibrary.gds` (cell GDS -- for stream-out)
5. `rcx_patterns.rules` (parasitic extraction rules)

**Script pattern:**
```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

# Read PDK path from env.json or env var
PDK_DIR="${NANGATE45_DIR:-}"
if [ -z "$PDK_DIR" ] && [ -f "$PLUGIN_ROOT/.chipagent/env.json" ]; then
  PDK_DIR=$(jq -r '.pdk.nangate45.path // empty' "$PLUGIN_ROOT/.chipagent/env.json")
fi

if [ -z "$PDK_DIR" ]; then
  echo "ERROR: nangate45 PDK path not configured."
  echo "Run /chip-agent:initialize to detect PDK location."
  exit 1
fi

MISSING=0
for file in \
    "lib/NangateOpenCellLibrary_typical.lib" \
    "lef/NangateOpenCellLibrary.tech.lef" \
    "lef/NangateOpenCellLibrary.macro.mod.lef" \
    "gds/NangateOpenCellLibrary.gds" \
    "rcx_patterns.rules"; do
  if [ ! -f "$PDK_DIR/$file" ]; then
    echo "ERROR: Required PDK file missing: $PDK_DIR/$file"
    MISSING=1
  fi
done

if [ "$MISSING" -ne 0 ]; then
  echo ""
  echo "PDK validation failed. Ensure nangate45 PDK is complete."
  exit 1
fi

echo "PDK validation passed: $PDK_DIR"
```

### Pattern 3: SDC Generation from Verilog Analysis

**What:** `scripts/generate_sdc.sh <ModuleName>` analyzes `workspace/generated/<Module>.v` to determine if the module is sequential or combinational, then writes the appropriate SDC to `workspace/pnr/constraint.sdc`.
**When to use:** SYN-02 implementation. Called before synthesis.

**Critical design decision -- clock detection heuristic:**

Chisel `Module` always generates `clock` and `reset` ports, even for purely combinational logic (ALU, Decoder3to8). Checking for a `clock` port is NOT sufficient to determine sequentiality. Instead, check for actual register usage:

```bash
# Check for actual register usage (posedge-triggered always blocks)
if grep -qE 'always @\(posedge' "$VERILOG_FILE"; then
  IS_SEQUENTIAL=1
else
  IS_SEQUENTIAL=0
fi
```

This is reliable because:
- Chisel 3.6.1 with built-in FIRRTL emits `always @(posedge clock)` for any `Reg` usage
- Combinational-only modules have only `assign` statements and `always @(*)` blocks
- The `clock` port exists but connects to nothing in combinational modules

**Module name extraction:**
```bash
# Extract exact module name from Verilog (never derive from filename)
MODULE_NAME=$(grep -m1 '^module ' "$VERILOG_FILE" | sed 's/^module \([A-Za-z_][A-Za-z0-9_]*\).*/\1/')
```

**Sequential SDC template (2.0ns default):**
```sdc
current_design <MODULE_NAME>

set clk_name  core_clock
set clk_port  [get_ports clock]
set clk_period <PERIOD>

create_clock -name $clk_name -period $clk_period $clk_port

set_input_delay  [expr $clk_period * 0.2] -clock $clk_name [all_inputs]
set_output_delay [expr $clk_period * 0.2] -clock $clk_name [all_outputs]
```

Note: Using `[all_inputs]` instead of filtering out clock. The `create_clock` on the clock port takes precedence, so input delay on it is harmless and avoids complex `lsearch` filtering.

**Combinational SDC template:**
```sdc
current_design <MODULE_NAME>

set clk_period <PERIOD>

create_clock -name virtual_clk -period $clk_period

set_input_delay  0.0 -clock virtual_clk [all_inputs]
set_output_delay 0.0 -clock virtual_clk [all_outputs]
set_max_delay $clk_period -from [all_inputs] -to [all_outputs]
```

**Clock period resolution (in order):**
1. `spec.json` field `clock_period_ns` (if present)
2. Default: 2.0ns

### Anti-Patterns to Avoid

- **Do not check for `clock` port to determine sequentiality.** Chisel always emits `clock`/`reset` ports. Use `always @(posedge` pattern matching instead.
- **Do not derive module name from directory or filename.** Extract from `module <Name>` declaration in the Verilog file itself.
- **Do not hardcode the nangate45 path in scripts.** Read from env.json or env var with a fallback search order.
- **Do not duplicate the PDK path in multiple places.** Store once in env.json during `/chip-agent:initialize`, read in all scripts.
- **Do not create `workspace/pnr/` in this phase.** The `pnr/` directory will be created by the scripts that need it (synth.sh, pnr.sh) or by updating project-init.md in a later phase. This phase only creates the SDC file, which should go into the pnr directory that the generate_sdc.sh script creates via `mkdir -p`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON output | Manual echo/heredoc JSON | jq (already in detect-env.sh) | jq handles escaping, formatting; fallback heredoc already exists |
| Tool version parsing | Custom regex per tool | Existing `detect_tool` function | Already handles installed/version/path extraction |
| PDK file validation | Inline checks in every script | Standalone `validate-pdk.sh` | Single source of truth; called from synth.sh, pnr.sh, skill |

## Common Pitfalls

### Pitfall 1: Chisel `Module` Always Emits Clock/Reset Ports (CRITICAL)

**What goes wrong:** Every Chisel class extending `Module` generates `clock` and `reset` top-level Verilog ports, even for purely combinational logic like ALU or Decoder3to8. If SDC generation checks for `clock` port presence and applies `create_clock`, it will create a real clock constraint on a port that drives nothing, causing CTS to insert unnecessary buffers later.
**Why it happens:** Chisel's `Module` base class unconditionally adds implicit `clock` and `reset` ports.
**How to avoid:** Check for `always @(posedge` in Verilog to detect actual register usage, not clock port presence.
**Warning signs:** CTS log shows "0 sinks" but still inserts buffers; combinational module gets classified as sequential.

### Pitfall 2: Chisel `io_` Port Prefix in SDC

**What goes wrong:** Chisel generates ports with `io_` prefix (`io_a`, `io_b`, `io_result`). SDC constraints referencing bare port names silently match nothing.
**How to avoid:** Use `[all_inputs]` and `[all_outputs]` wildcards in SDC instead of named ports. The `clock` and `reset` ports are exceptions (NOT prefixed with `io_`).
**Warning signs:** STA shows "No constrained paths" or unconstrained endpoints.

### Pitfall 3: OpenROAD Version String Format

**What goes wrong:** OpenROAD `-version` outputs a format like `26Q1-951-g6975124cf2` which doesn't match simple `X.Y.Z` version regex.
**How to avoid:** Use regex `'[0-9]+Q[0-9]'` to capture the quarterly release identifier (e.g., `26Q1`). The full git hash suffix is informational.

### Pitfall 4: KLayout Version Detection

**What goes wrong:** KLayout `-v` outputs `KLayout 0.30.7` with the tool name prefix. The `detect_tool` function's version_regex should extract just the version number.
**How to avoid:** Use regex `'[0-9]+\.[0-9]+\.[0-9]+'` which correctly extracts `0.30.7` from the output.

### Pitfall 5: env.json Backward Compatibility

**What goes wrong:** Existing env.json has a flat `tools` object. Adding `pdk` and new `capabilities` could break consumers expecting the old schema.
**How to avoid:** Only ADD new fields. Never remove or rename existing fields. New capability flags (`can_synthesize`, `can_pnr`, `can_gds`) are additive alongside existing `can_compile`, `can_lint`, `can_simulate`.

## Code Examples

### detect-env.sh Extension (verified pattern from existing code)

```bash
# New tool detections (add after existing g++ detection, before capability computation)
detect_tool "yosys" "yosys" "yosys --version 2>&1 | head -1" '[0-9]+\.[0-9]+(\+[0-9]+)?'
YOSYS_INSTALLED="$TOOL_INSTALLED"
YOSYS_VERSION="$TOOL_VERSION"
YOSYS_PATH="$TOOL_PATH"

detect_tool "openroad" "openroad" "openroad -version 2>&1 | head -1" '[0-9]+Q[0-9]'
OPENROAD_INSTALLED="$TOOL_INSTALLED"
OPENROAD_VERSION="$TOOL_VERSION"
OPENROAD_PATH="$TOOL_PATH"

detect_tool "klayout" "klayout" "klayout -v 2>&1 | head -1" '[0-9]+\.[0-9]+\.[0-9]+'
KLAYOUT_INSTALLED="$TOOL_INSTALLED"
KLAYOUT_VERSION="$TOOL_VERSION"
KLAYOUT_PATH="$TOOL_PATH"

# PDK detection
NANGATE45_DIR=""
NANGATE45_INSTALLED="false"
for candidate in \
    "${NANGATE45_DIR_OVERRIDE:-}" \
    "${ORFS_DIR:-}/flow/platforms/nangate45" \
    "$HOME/OpenROAD-flow-scripts/flow/platforms/nangate45" \
    "/opt/OpenROAD-flow-scripts/flow/platforms/nangate45"; do
  if [ -n "$candidate" ] && [ -f "${candidate}/lib/NangateOpenCellLibrary_typical.lib" ]; then
    NANGATE45_DIR="$candidate"
    NANGATE45_INSTALLED="true"
    break
  fi
done

# New capability flags
CAN_SYNTHESIZE="false"
CAN_PNR="false"
CAN_GDS="false"

if [ "$YOSYS_INSTALLED" = "true" ] && [ "$NANGATE45_INSTALLED" = "true" ]; then
  CAN_SYNTHESIZE="true"
fi

if [ "$OPENROAD_INSTALLED" = "true" ] && [ "$NANGATE45_INSTALLED" = "true" ]; then
  CAN_PNR="true"
fi

if [ "$KLAYOUT_INSTALLED" = "true" ] && [ "$NANGATE45_INSTALLED" = "true" ] && \
   [ -f "${NANGATE45_DIR}/gds/NangateOpenCellLibrary.gds" ]; then
  CAN_GDS="true"
fi
```

### generate_sdc.sh Verilog Analysis

```bash
# Extract module name from Verilog (never from filename)
VERILOG_FILE="$WORKSPACE_DIR/generated/${MODULE}.v"
MODULE_NAME=$(grep -m1 '^module ' "$VERILOG_FILE" | sed 's/^module \([A-Za-z_][A-Za-z0-9_]*\).*/\1/')

# Detect sequential vs combinational by register usage
if grep -qE 'always @\(posedge' "$VERILOG_FILE"; then
  IS_SEQUENTIAL=1
else
  IS_SEQUENTIAL=0
fi

# Read clock period from spec.json or use default
CLOCK_PERIOD="2.0"
if [ -f "$WORKSPACE_DIR/spec.json" ]; then
  SPEC_PERIOD=$(jq -r '.clock_period_ns // empty' "$WORKSPACE_DIR/spec.json" 2>/dev/null)
  if [ -n "$SPEC_PERIOD" ]; then
    CLOCK_PERIOD="$SPEC_PERIOD"
  fi
fi
```

### initialize SKILL.md Update (new output fields to document)

The initialize skill currently documents env.json output with 6 tools and 3 capabilities. Phase 9 adds:
- 3 new tools: yosys, openroad, klayout
- 1 new `pdk` section with nangate45 path and file locations
- 3 new capabilities: can_synthesize, can_pnr, can_gds

The skill summary should also add install instructions for missing PnR tools:
- Yosys: `apt install yosys` or build from source (https://github.com/YosysHQ/yosys)
- OpenROAD: `apt install openroad` or build from ORFS (https://github.com/The-OpenROAD-Project/OpenROAD)
- KLayout: `apt install klayout` or https://www.klayout.de/build.html

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| KLayout not installed (domain research) | KLayout 0.30.7 now installed | Verified 2026-03-31 | `can_gds` capability is TRUE; GDS export viable for Phase 11 |
| Only 6 tools in env.json | 9 tools + PDK section after Phase 9 | This phase | Full PnR stack visibility at init time |

**Update from domain research:** The domain research (STACK.md, SUMMARY.md) stated KLayout was not installed. Verification today shows KLayout 0.30.7 IS installed at `/usr/bin/klayout`. The GDS file exists at `gds/NangateOpenCellLibrary.gds`. This means `can_gds` will be TRUE and Phase 11 GDS export is fully viable.

## Open Questions

1. **spec.json `clock_period_ns` field**
   - What we know: The domain research specifies this as the override mechanism
   - What's unclear: Does the requirement-parser agent currently populate this field in spec.json?
   - Recommendation: Default to 2.0ns; if field is absent, it's fine. Document the field in spec.json schema for future parsers.

2. **RawModule usage for truly portless combinational modules**
   - What we know: Chisel `RawModule` does NOT emit `clock`/`reset` ports
   - What's unclear: Whether any ChipAgent-generated modules use `RawModule` instead of `Module`
   - Recommendation: The `always @(posedge` heuristic handles both cases correctly (RawModule combinational = no posedge = combinational SDC). No special handling needed.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bash scripts + manual verification |
| Config file | none |
| Quick run command | `bash scripts/detect-env.sh && cat .chipagent/env.json` |
| Full suite command | Run detect-env + validate-pdk + generate_sdc on a test module |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ENV-01 | detect-env.sh produces yosys, openroad, klayout, nangate45 entries in env.json | smoke | `bash scripts/detect-env.sh && jq '.tools.yosys.installed, .tools.openroad.installed, .tools.klayout.installed, .pdk.nangate45.installed' .chipagent/env.json` | Wave 0 |
| ENV-02 | validate-pdk.sh exits non-zero when PDK file missing | unit | `bash scripts/validate-pdk.sh && echo PASS` (positive); test with bad path for negative | Wave 0 |
| SYN-02 (sequential) | SDC generation produces create_clock for sequential module | smoke | Requires a compiled sequential module Verilog; manual test with sample file | Wave 0 |
| SYN-02 (combinational) | SDC generation produces virtual clock + set_max_delay for combinational | smoke | `bash scripts/generate_sdc.sh ALU` (after compiling ALU) | Wave 0 |

### Sampling Rate

- **Per task commit:** `bash scripts/detect-env.sh` + verify env.json
- **Per wave merge:** Full detect + validate + SDC generation test
- **Phase gate:** All 4 success criteria from roadmap verified

### Wave 0 Gaps

- [ ] Need a compiled Verilog file to test SDC generation (ALU or similar module must be compiled first via `scripts/compile.sh ALU`)
- [ ] No automated negative test for validate-pdk.sh (test with deliberately missing file)

## Sources

### Primary (HIGH confidence)

- Existing `scripts/detect-env.sh` -- pattern for tool detection, JSON output (read and analyzed line-by-line)
- Existing `skills/initialize/SKILL.md` -- current initialize skill interface
- Local tool verification: `yosys --version` = 0.53+26, `openroad -version` = 26Q1, `klayout -v` = 0.30.7
- nangate45 PDK at `/home/mingzhenjia/OpenROAD-flow-scripts/flow/platforms/nangate45/` -- all file paths verified
- Domain research: `.planning/research/STACK.md`, `.planning/research/PITFALLS.md`, `.planning/research/ARCHITECTURE.md`
- Chisel source: `ALU.scala` -- confirmed `Module` base class with implicit clock/reset

### Secondary (MEDIUM confidence)

- SDC template patterns from ORFS GCD example `constraint.sdc` (verified in domain research)
- `always @(posedge` heuristic for register detection (verified against Chisel 3.6.1 FIRRTL output)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all tools verified installed, paths confirmed
- Architecture: HIGH - extends well-established detect-env.sh pattern, SDC templates from verified ORFS examples
- Pitfalls: HIGH - Chisel clock/reset behavior confirmed from source code analysis, io_ prefix documented in CLAUDE.md

**Research date:** 2026-03-31
**Valid until:** 2026-05-01 (stable -- tools and PDK are local installations)
