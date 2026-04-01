---
name: pnr
description: "Run Yosys synthesis + OpenROAD PnR + KLayout GDS export on compiled Verilog. Produces timing, power, area reports and GDS file with auto-retry on failure."
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---

# chip-agent:pnr

Physical implementation pipeline: synthesize compiled Verilog, run place-and-route, export GDS, and produce a formatted PnR verification report.

## Usage

```
/chip-agent:pnr <ModuleName>
```

**Example:**

```
/chip-agent:pnr ALU
```

## Instructions

**Determine the plugin root directory** by finding the nearest ancestor directory of this skill file that contains `.claude-plugin/plugin.json`. Use that directory as the base for all relative paths below.

## Pipeline

### Step 0 -- Verify Prerequisites

Set up variables:

```bash
PLUGIN_ROOT="<plugin-root>"
MODULE="$ARGUMENTS"   # first argument: bare module name (PascalCase)
```

Check that compiled Verilog exists:

```bash
test -f "$PLUGIN_ROOT/MyDesign/$MODULE/workspace/generated/$MODULE.v"
```

- If **missing**: STOP with clear message:
  ```
  No compiled Verilog found for <ModuleName>.
  Run `/chip-agent:compile <ModuleName>` or `/chip-agent:workflow <description>` first.
  ```
- If **exists**: continue to Step 1.

### Step 1 -- Synthesize

Run Yosys synthesis via the synthesis script:

```bash
"$PLUGIN_ROOT/scripts/synth.sh" "$MODULE"
```

- **On success** (exit 0): continue to Step 2.
- **On failure** (non-zero exit): Read error output. Synthesis errors are typically RTL issues not fixable by the PnR command. STOP and report:
  ```
  SYNTHESIS FAILED.
  Error output:
  <paste synth.sh stderr/stdout>

  Synthesis errors usually require fixing the Chisel source.
  Run `/chip-agent:workflow <description>` to regenerate, or manually fix the Verilog.
  ```

Do NOT retry synthesis failures -- they require RTL changes outside PnR scope.

### Step 2 -- Place and Route + GDS Export (with auto-fix retry)

Run OpenROAD PnR and KLayout GDS export:

```bash
"$PLUGIN_ROOT/scripts/pnr.sh" "$MODULE"
```

- **On failure** (non-zero exit -- structural PnR error): Read error output, report to user, STOP.
- **On success** (exit 0): Check timing by reading `MyDesign/$MODULE/workspace/pnr/reports/timing.rpt`:
  - If timing **MET** (line contains `slack (MET)`): continue to Step 3.
  - If timing **VIOLATED** (line contains `slack (VIOLATED)`): enter auto-fix loop.

#### Auto-fix: Timing Violation Recovery

When timing is violated, relax the clock period and re-run the full synthesis + PnR pipeline:

1. Read current clock period from `MyDesign/$MODULE/workspace/spec.json` field `clock_period_ns` (default 2.0 if field absent).
2. Increase period by 50% (e.g., 2.0 -> 3.0, 3.0 -> 4.5).
3. Write updated `clock_period_ns` to `spec.json` using the Edit tool (add field if absent, update if present).
4. Re-run synthesis: `"$PLUGIN_ROOT/scripts/synth.sh" "$MODULE"` (synth.sh calls generate_sdc.sh which reads spec.json).
5. Re-run PnR: `"$PLUGIN_ROOT/scripts/pnr.sh" "$MODULE"`.
6. Check `timing.rpt` again for MET/VIOLATED.

**CRITICAL:** When adjusting clock period, re-run BOTH synth.sh AND pnr.sh. The SDC constraint affects both synthesis optimization and PnR STA. Skipping synthesis re-run makes the clock period change ineffective.

**Maximum 3 total attempts** (initial run + 2 retries). After 3 failures, STOP:

```
PnR AUTO-FIX FAILED after 3 attempts.
Timing still violated at clock period X.X ns.
Final WNS: X.XX ns
The module may need architectural changes to meet timing.
```

### Step 3 -- Format Report

Read the agent definition at `agents/pnr-report-formatter.md` (relative to plugin root) and follow the agent's rules to parse raw PnR report files and produce a formatted human-readable verification summary.

Present the formatted report directly in the conversation.

## Pipeline Stages

| # | Stage | Description |
|---|-------|-------------|
| 0 | Verify Prerequisites | Check compiled Verilog exists for module |
| 1 | Synthesize | Run Yosys synthesis via synth.sh |
| 2 | Place and Route + GDS | Run OpenROAD PnR + KLayout GDS via pnr.sh, with timing auto-fix |
| 3 | Format Report | Parse raw reports into human-readable summary |

## Input

$ARGUMENTS

A module name (PascalCase, e.g., `ALU`, `Counter8`). The module must already have compiled Verilog at `MyDesign/<ModuleName>/workspace/generated/<ModuleName>.v`.

## Output

Upon pipeline completion, the following artifacts are produced in `MyDesign/<ModuleName>/workspace/pnr/`:

- `<Module>.synth.v` -- gate-level netlist from Yosys synthesis
- `<Module>.routed.def` -- routed DEF from OpenROAD place-and-route
- `<Module>.gds` -- final GDS layout from KLayout export
- `reports/` -- directory containing timing.rpt, power.rpt, area.rpt, synth_stat.txt, drc.rpt
- Formatted PnR verification report (displayed in conversation)
