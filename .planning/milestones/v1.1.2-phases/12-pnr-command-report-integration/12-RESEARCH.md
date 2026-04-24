# Phase 12: PnR Command + Report Integration - Research

**Researched:** 2026-04-01
**Domain:** Claude Code plugin skill authoring, PnR report parsing, auto-fix retry loops
**Confidence:** HIGH

## Summary

Phase 12 creates the `/chip-agent:pnr` slash command that orchestrates the existing synthesis, PnR, and GDS export scripts (from Phases 9-11) into a single user-facing pipeline, adds a PnR report formatting agent that turns raw report files into a human-readable verification summary, and implements an auto-fix retry loop for synthesis and PnR failures. This is the final phase of the v1.1.2 milestone and completes the RTL-to-GDS capability.

The implementation follows the established skill pattern (YAML frontmatter + markdown instructions in `skills/<name>/SKILL.md`) and the auto-fix retry pattern already proven in the `/chip-agent:workflow` command (Steps 3-6). The key new artifact is a PnR report agent definition (`agents/pnr-report-formatter.md`) that parses the raw timing/power/area/synthesis reports into a formatted summary table. The skill orchestrator calls `scripts/synth.sh`, `scripts/pnr.sh` in sequence, with a retry loop around each that reads error output, applies diagnostic adjustments, and retries up to 3 times before stopping with context.

All underlying scripts are complete and verified from Phase 11. This phase is purely orchestration and presentation -- no new scripts, Tcl recipes, or Python tools are needed. The main technical concern is defining what "diagnostic adjustments" the auto-fix loop can actually make for synthesis/PnR failures (as opposed to Chisel source fixes in the workflow command). For PnR, the most common fixable failures are timing violations (adjustable via clock period) and PDN failures (adjustable via die area), while synthesis failures from Yosys are typically unfixable without changing the RTL.

**Primary recommendation:** Create `skills/pnr/SKILL.md` (slash command), `agents/pnr-report-formatter.md` (report agent), and update `CLAUDE.md` to document the new command. Follow the workflow skill pattern exactly for the pipeline structure and retry loops. Keep the auto-fix scope narrow: adjust SDC clock period for timing violations, log-and-report for structural errors.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CMD-01 | `/chip-agent:pnr <ModuleName>` slash command runs synth + PnR + GDS, produces formatted report | Skill pattern verified from 8 existing skills; pipeline is synth.sh then pnr.sh (which includes GDS); report formatting via dedicated agent |
| CMD-02 | PnR report agent formats raw reports into human-readable verification summary | Raw report formats analyzed from ALU and Counter8 outputs; timing (WNS/TNS/slack), power (group table), area (single line), synth (cell count/area) all have parseable structure |
| CMD-03 | Auto-fix retry loop (up to 3 attempts) for synthesis and PnR errors | Retry pattern proven in workflow skill Steps 3-6; for PnR domain: timing violations fixable via SDC period relaxation, PDN failures potentially fixable via die area adjustment, structural errors logged-and-reported |
</phase_requirements>

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Claude Code Plugin Skills | 0.1.0 | Slash command definition via SKILL.md | Established pattern across 8 existing skills |
| scripts/synth.sh | Phase 10 | Yosys synthesis producing gate-level netlist | Already tested, called as first pipeline stage |
| scripts/pnr.sh | Phase 11 | OpenROAD PnR + KLayout GDS export | Already tested, called as second pipeline stage |

### Supporting

| Component | Purpose | When to Use |
|-----------|---------|-------------|
| scripts/validate-pdk.sh | Pre-flight PDK validation | Called by synth.sh and pnr.sh internally |
| scripts/generate_sdc.sh | SDC constraint generation | Called by synth.sh internally; may be re-invoked by auto-fix for clock period adjustment |
| .chipagent/env.json | Tool version and PDK path data | Referenced for environment checks in skill |

### No New Dependencies

This phase adds no new tools, libraries, or external dependencies. All infrastructure exists from Phases 9-11. The new artifacts are pure markdown files (SKILL.md, agent definition).

## Architecture Patterns

### Recommended Project Structure Changes

```
skills/
  pnr/
    SKILL.md              # NEW: /chip-agent:pnr slash command definition
agents/
  pnr-report-formatter.md # NEW: Report formatting agent
CLAUDE.md                  # MODIFIED: Add /chip-agent:pnr to Commands section
```

### Pattern 1: Skill File Structure (from existing skills)

**What:** Every Claude Code plugin slash command is defined as `skills/<name>/SKILL.md` with YAML frontmatter specifying name, description, tools, and flags.

**Verified structure from 8 existing skills:**

```yaml
---
name: pnr
description: "Run Yosys synthesis + OpenROAD PnR + KLayout GDS on compiled Verilog, with formatted report and auto-fix retry."
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

**Key conventions:**
- `disable-model-invocation: true` is set on ALL existing skills (prevents ambient invocation)
- `allowed-tools` lists only the tools the skill needs
- The `workflow` and `generate` skills use all 6 tools (Bash, Read, Write, Edit, Grep, Glob) because they orchestrate multi-step pipelines with file generation
- The `pnr` skill needs the same 6 tools: Bash (run scripts), Read (read reports/agents/specs), Write (write report), Edit (adjust SDC for auto-fix), Grep/Glob (search workspace)

### Pattern 2: Pipeline Orchestration (from workflow skill)

**What:** The workflow skill defines a numbered sequence of steps, each calling a script or agent, with auto-fix retry loops and error reporting. The PnR skill follows the same pattern but with different stages.

**Workflow pipeline (Steps 0-7) vs PnR pipeline:**

| Workflow Step | PnR Equivalent | Script/Agent |
|---------------|----------------|--------------|
| Step 0: Init project | Step 0: Verify prerequisites | Check module exists, Verilog compiled |
| Step 1: Parse requirements | -- | Not needed (module already exists) |
| Step 3: Compile | Step 1: Synthesize | `scripts/synth.sh <ModuleName>` |
| Step 4: Lint | Step 2: Place and Route | `scripts/pnr.sh <ModuleName>` |
| Step 6: Simulate | -- | PnR is the final processing step |
| Step 7: Report | Step 3: Report | PnR report formatting agent |

**Key difference:** The PnR pipeline does NOT parse requirements, generate code, or create testbenches. It takes already-compiled Verilog as input. This means the auto-fix scope is different -- the workflow fixes Chisel source, while the PnR command fixes synthesis/PnR parameters (SDC clock period, die area).

### Pattern 3: Auto-Fix Retry Loop (from workflow Steps 3-6)

**What:** The workflow skill wraps each failure-prone step in a retry loop: run script -> on failure, read error -> apply fix -> retry. Maximum 3 attempts. On final failure, stop with full error context.

**Verified pattern from workflow skill:**

```
If <step> fails:
1. Read the error output
2. Identify the root cause
3. Apply targeted fix
4. Re-run the step
5. Maximum 3 fix attempts. After 3 failures, STOP and report:
   <STEP> AUTO-FIX FAILED after 3 attempts.
   Remaining errors:
   <paste error output>
```

**For PnR domain, the fixable failures are:**

| Failure Type | Error Signature | Auto-Fix Action |
|--------------|-----------------|-----------------|
| Yosys synthesis error | `ERROR:` in Yosys output | Log and report -- synthesis errors are typically RTL issues requiring Chisel source changes, which is out of scope for the PnR command |
| Timing violation (WNS < 0) | `slack (VIOLATED)` in timing.rpt, negative WNS | Relax clock period in SDC: re-run generate_sdc.sh with a longer period, then re-run synth + PnR |
| PDN failure on small module | `PDN-0185: Insufficient width` | Increase die area floor -- but this is already handled by pnr.tcl auto-sizing (70um minimum). If it still fails, report |
| Placement failure | `detailed_placement failed` | Report -- typically means the design is too large for the die area at current utilization |
| Routing congestion | `Routing failed` | Report -- would require utilization reduction, which is a design-level change |
| KLayout GDS empty cells | `[ERROR] Empty cell` in def2gds.py output | Report -- indicates PDK/LEF mismatch, not auto-fixable |

**Practical auto-fix scope:** The most actionable auto-fix for the PnR domain is timing violation recovery via clock period relaxation. Synthesis structural errors and placement/routing failures typically require design changes beyond what the command can auto-fix. The skill should:
1. Attempt synth. On failure: read error, report to user, stop.
2. Attempt PnR. On failure:
   a. If timing violation: increase clock period by 50%, re-run synth + PnR
   b. If other failure: read error context, report to user, stop.
3. Attempt GDS. On failure: report (GDS failures are rare with clean PnR).

### Pattern 4: PnR Report Format (CMD-02)

**What:** A PnR report agent reads the raw report files produced by synth.sh and pnr.sh, then formats them into a human-readable verification summary.

**Raw report files to parse (verified from ALU and Counter8 outputs):**

1. **`workspace/pnr/reports/synth_stat.txt`** -- Yosys synthesis statistics
   - Parse: `Number of cells:` line for total gate count
   - Parse: `Chip area for module` line for synthesis area
   - Parse: individual cell type lines for cell breakdown

2. **`workspace/pnr/reports/timing.rpt`** -- OpenROAD timing report
   - Parse: final `slack (MET)` or `slack (VIOLATED)` line for pass/fail
   - Parse: slack value (floating point number before "slack")
   - Startpoint/Endpoint available but optional for summary

3. **`workspace/pnr/reports/power.rpt`** -- OpenROAD power report
   - Parse: `Total` row for aggregate power
   - Parse: Individual group rows (Sequential, Combinational, Clock) for breakdown
   - Parse: Bottom percentage line for internal/switching/leakage split

4. **`workspace/pnr/reports/area.rpt`** -- OpenROAD area report
   - Parse: `Design area` line for total area in um^2 and utilization percentage

5. **WNS/TNS** -- Extracted by pnr.sh from OpenROAD log
   - Available in pnr.sh summary output or re-extractable from timing.rpt slack line

**Target report format:**

```
=== PnR Verification Report: <ModuleName> ===

Timing:     PASSED (MET)
  WNS:      0.46 ns
  TNS:      0.00 ns

Power:
  Internal:    83.6 uW  (45.8%)
  Switching:   86.0 uW  (47.1%)
  Leakage:     12.9 uW  (7.1%)
  Total:       182.0 uW

Area:
  Synthesis:   517 um^2
  Post-PnR:    517 um^2 (31% utilization)
  Cell Count:  492

Artifacts:
  Netlist:     MyDesign/<Module>/workspace/pnr/<Module>.synth.v
  Routed DEF:  MyDesign/<Module>/workspace/pnr/<Module>.routed.def
  GDS:         MyDesign/<Module>/workspace/pnr/<Module>.gds
  Reports:     MyDesign/<Module>/workspace/pnr/reports/
```

### Pattern 5: Agent Definition Structure (from existing agents)

**What:** Agent definitions in `agents/` are markdown files with YAML frontmatter specifying name, description, tools, and model. The body contains structured instructions.

**Verified from 4 existing agents (requirement-parser, chisel-generator, testbench-generator, debug-analyzer):**

```yaml
---
name: pnr-report-formatter
description: "Formats raw PnR reports (timing, power, area, synthesis stats) into a human-readable verification summary"
tools: [Read, Bash]
model: inherit
---
```

**Key convention:** Agents are called inline by skills (the skill reads the agent definition and follows its instructions). There is no automatic agent invocation. The skill MUST explicitly say "Read agent definition at `agents/<name>.md` and follow its rules."

### Pattern 6: Plugin Root Detection (from all skills)

**What:** Every skill starts with "Determine the plugin root directory by finding the nearest ancestor directory of this skill file that contains `.claude-plugin/plugin.json`."

This MUST be included in the PnR skill. It provides the base path for all script invocations and file references.

### Anti-Patterns to Avoid

- **Do not create a new bash script for the PnR pipeline.** The skill orchestrator (Claude) calls existing scripts directly. The skill definition IS the orchestration logic.
- **Do not try to auto-fix Yosys synthesis errors from within the PnR command.** Synthesis errors require Chisel source changes, which is the domain of `/chip-agent:workflow`. The PnR command should report synthesis errors and suggest the user fix the source.
- **Do not hardcode report parsing logic in the skill.** Use a separate agent definition for report formatting, following the pattern of debug-analyzer.md.
- **Do not create a new skill that duplicates the workflow's steps.** The PnR skill starts AFTER compilation -- it assumes Verilog already exists in `workspace/generated/`.
- **Do not omit the prerequisite check.** The skill MUST verify that compiled Verilog exists before running synthesis. If missing, direct user to run `/chip-agent:compile` or `/chip-agent:workflow` first.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Synthesis pipeline | New synthesis script | `scripts/synth.sh` (Phase 10) | Already tested and verified |
| PnR + GDS pipeline | New PnR orchestration | `scripts/pnr.sh` (Phase 11) | Already includes OpenROAD + KLayout + report extraction |
| SDC generation | Manual SDC creation | `scripts/generate_sdc.sh` (Phase 9) | Handles sequential/combinational detection automatically |
| PDK validation | Inline file checks | `scripts/validate-pdk.sh` (Phase 9) | Called internally by synth.sh and pnr.sh |
| Retry loop pattern | New retry mechanism | Follow workflow SKILL.md pattern | Proven across 4 pipeline stages in workflow |
| Report parsing regex | Custom parser script | Inline parsing in agent definition | Reports have simple, stable formats verified from live output |
| Module path resolution | Custom path logic | Pass bare module name to scripts | All scripts handle bare name, MyDesign/Module, and workspace/Module |

**Key insight:** Phase 12 creates zero new scripts or tools. Everything is markdown-based skill and agent definitions that orchestrate existing Phase 9-11 infrastructure. The implementation effort is in correctly structuring the SKILL.md pipeline stages, the report formatting agent, and the auto-fix decision logic.

## Common Pitfalls

### Pitfall 1: Trying to Auto-Fix RTL-Level Synthesis Errors

**What goes wrong:** The PnR command tries to fix Yosys errors by modifying Chisel source, duplicating the workflow's compile auto-fix logic.
**Why it happens:** Synthesis errors look similar to compile errors and suggest code changes.
**How to avoid:** The PnR command operates on already-compiled Verilog. It should NOT modify Chisel source or generated Verilog. If synthesis fails due to RTL issues, report the error and suggest the user fix the source via `/chip-agent:workflow` or manual editing. The PnR auto-fix loop is ONLY for PnR-domain parameters (clock period, die area).
**Warning signs:** The skill definition references `agents/chisel-generator.md` or modifies `.scala` files.

### Pitfall 2: Missing Prerequisite Check for Compiled Verilog

**What goes wrong:** The PnR command runs `synth.sh` on a module that has never been compiled, resulting in a confusing "Verilog file not found" error from synth.sh.
**Why it happens:** The user runs `/chip-agent:pnr ALU` before `/chip-agent:compile ALU` or `/chip-agent:workflow ALU`.
**How to avoid:** The skill's Step 0 MUST check that `MyDesign/<ModuleName>/workspace/generated/<ModuleName>.v` exists. If missing, provide a clear message: "No compiled Verilog found for <ModuleName>. Run `/chip-agent:compile <ModuleName>` or `/chip-agent:workflow <description>` first."
**Warning signs:** The skill jumps straight to synthesis without a Verilog existence check.

### Pitfall 3: Auto-Fix Loop Runs PnR Without Re-Running Synthesis

**What goes wrong:** When a timing violation is detected after PnR, the auto-fix adjusts the SDC clock period but only re-runs PnR (skipping synthesis re-run). The old netlist with the old SDC is used, so the timing constraint change has no effect.
**Why it happens:** The SDC is used by both synth.sh (for Yosys timing-driven optimization) and pnr.sh (for OpenROAD STA). Changing the SDC requires re-running BOTH stages.
**How to avoid:** When the auto-fix loop adjusts the clock period, it must re-run the FULL pipeline: `generate_sdc.sh` -> `synth.sh` -> `pnr.sh`. The generate_sdc.sh script is called automatically by synth.sh, so re-running synth.sh with the updated SDC file is sufficient.
**Warning signs:** The auto-fix modifies the SDC but only re-runs pnr.sh.

### Pitfall 4: Report Parsing Fails on Missing Reports

**What goes wrong:** The report formatting agent tries to read timing.rpt, power.rpt, or area.rpt but the files are empty or missing (because PnR failed partway through).
**Why it happens:** If OpenROAD crashes before producing all reports, some files may be empty or contain only the marker text.
**How to avoid:** The report agent must check each file exists and is non-empty before parsing. For missing reports, output "N/A" rather than crashing. The skill should only call the report agent on pipeline SUCCESS.
**Warning signs:** Report agent assumes all files exist without checking.

### Pitfall 5: PnR Skill Duplicates Workflow Init Steps

**What goes wrong:** The PnR skill creates project folders, writes spec.json, or runs requirement parsing -- duplicating Steps 0-2 of the workflow skill.
**Why it happens:** Copy-pasting from the workflow skill without trimming.
**How to avoid:** The PnR skill takes a ModuleName that MUST already have a project folder with compiled Verilog. It does NOT initialize projects, parse requirements, or generate code. Its scope starts at "Verilog exists, now synthesize and physically implement it."
**Warning signs:** The skill references `agents/requirement-parser.md` or creates `workspace/` directories.

### Pitfall 6: Reporting Power in Watts Instead of Readable Units

**What goes wrong:** The raw power report uses scientific notation (e.g., `8.36e-05 W`), which is hard to read.
**Why it happens:** OpenROAD report_power outputs in Watts.
**How to avoid:** The report formatting agent should convert to microwatts (uW) or milliwatts (mW) for readability. For ChipAgent's small modules, microwatts is typically the right unit (values range from ~50 uW to ~200 uW).

## Code Examples

### PnR Skill YAML Frontmatter

```yaml
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
```

### PnR Pipeline Stages

```
Step 0: Verify Prerequisites
  - Check MyDesign/<ModuleName>/workspace/generated/<ModuleName>.v exists
  - If missing: STOP with clear message

Step 1: Synthesize (with retry)
  - Run: <plugin-root>/scripts/synth.sh <ModuleName>
  - On failure: Read error output, report to user, STOP
    (synthesis errors require RTL changes -- not auto-fixable)
  - On success: Continue to Step 2

Step 2: Place and Route + GDS (with retry)
  - Run: <plugin-root>/scripts/pnr.sh <ModuleName>
  - On failure: Read error output from OpenROAD log
    - If timing violation: Increase clock period, re-run from Step 1
    - If other failure: Report to user, STOP
  - On success: Continue to Step 3
  - Maximum 3 total attempts for Steps 1+2 combined

Step 3: Format Report
  - Read agent at agents/pnr-report-formatter.md
  - Follow agent rules to parse and format reports
  - Present formatted report to user
```

### Auto-Fix: Timing Violation Recovery

When pnr.sh completes but timing.rpt shows a violation (WNS < 0):

```
1. Read current SDC at MyDesign/<Module>/workspace/pnr/constraint.sdc
2. Extract current clock period
3. Increase period by 50% (e.g., 2.0ns -> 3.0ns)
4. Write updated period to spec.json clock_period_ns field
   (generate_sdc.sh reads this value)
5. Re-run scripts/synth.sh <ModuleName>
   (synth.sh calls generate_sdc.sh which reads the updated spec.json)
6. Re-run scripts/pnr.sh <ModuleName>
7. Check timing again
```

Note: pnr.sh already exits 0 even with timing violations (it only fails on structural errors). The skill must parse the timing report to detect violations after a successful run.

### Report Formatting Agent Output Pattern

```
=== PnR Verification Report: <ModuleName> ===

Timing:     <PASSED|FAILED> (<MET|VIOLATED>)
  WNS:      X.XX ns
  TNS:      X.XX ns
  Clock:    <clock_name> @ <period> ns

Power:
  Internal:    XX.X uW  (XX.X%)
  Switching:   XX.X uW  (XX.X%)
  Leakage:     XX.X uW  (XX.X%)
  Total:       XX.X uW

Area:
  Synthesis:   XXX um^2 (from synth_stat.txt)
  Post-PnR:    XXX um^2 (XX% utilization)
  Cell Count:  XXX

Artifacts:
  Netlist:     MyDesign/<Module>/workspace/pnr/<Module>.synth.v
  Routed DEF:  MyDesign/<Module>/workspace/pnr/<Module>.routed.def
  GDS:         MyDesign/<Module>/workspace/pnr/<Module>.gds
  Reports:     MyDesign/<Module>/workspace/pnr/reports/
```

### Verified Raw Report Formats (from Phase 11 Live Output)

**timing.rpt -- Combinational (ALU):**
- Ends with `X.XX   slack (MET)` or `X.XX   slack (VIOLATED)`
- WNS value is the slack number
- Path Group line shows clock name

**timing.rpt -- Sequential (Counter8):**
- Same format, includes clock tree path entries (clkbuf lines)
- Clock name from `Path Group:` line

**power.rpt:**
- Table with columns: Group, Internal Power, Switching Power, Leakage Power, Total Power (Watts)
- `Total` row has aggregate values
- Bottom line has percentage split: `XX.X%  XX.X%  XX.X%`

**area.rpt:**
- Single line: `Design area XXX um^2 XX% utilization.`

**synth_stat.txt:**
- `Number of cells: XXX` line
- `Chip area for module '\<Module>': XXX.XXX` line
- Individual cell type lines with counts

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No PnR command | `/chip-agent:pnr` skill | Phase 12 (new) | Users get single-command RTL-to-GDS |
| Raw report files only | Formatted human-readable summary | Phase 12 (new) | Report accessible without parsing files |
| Manual retry on failure | Auto-fix with clock period relaxation | Phase 12 (new) | Common timing failures self-recover |
| workflow ends at simulation | PnR extends physical implementation | Phase 12 (new) | Pipeline now covers through GDS |

**Relationship to existing commands:**
- `/chip-agent:workflow` -- Full RTL pipeline (NL -> Chisel -> Verilog -> Sim). Ends at simulation verification.
- `/chip-agent:pnr` -- Physical implementation pipeline (Verilog -> Synthesis -> PnR -> GDS). Starts where workflow left off (or after manual compilation).
- They are complementary, not overlapping. A typical flow: `/chip-agent:workflow <description>` then `/chip-agent:pnr <ModuleName>`.

## Open Questions

1. **Should `/chip-agent:pnr` auto-run compilation if Verilog is missing?**
   - What we know: The workflow skill handles Chisel -> Verilog. The PnR skill assumes Verilog exists.
   - What's unclear: Whether users expect `/chip-agent:pnr ALU` to also compile if needed.
   - Recommendation: Do NOT auto-compile. The PnR command's scope is post-compilation. If Verilog is missing, provide a clear error directing to `/chip-agent:compile`. This keeps the command focused and avoids duplicating workflow logic. The roadmap explicitly keeps PnR as "explicit opt-in" (PIPE-01 deferred).

2. **What clock period relaxation factor should the auto-fix use?**
   - What we know: Default clock period is 2.0ns. ALU has 0.46ns slack; Counter8 has 1.44ns slack.
   - What's unclear: For complex modules that violate timing, how much relaxation is needed.
   - Recommendation: Increase by 50% per attempt (2.0 -> 3.0 -> 4.5ns). Three attempts covers a 3.4x relaxation, which should be sufficient for most small Chisel modules. If timing still violates at 4.5ns, the module likely has structural issues.

3. **Should the PnR report also show DRC violations?**
   - What we know: pnr.sh produces `reports/drc.rpt` from detailed routing. Both ALU and Counter8 had clean DRC.
   - What's unclear: Whether complex modules will produce DRC violations.
   - Recommendation: Include DRC in the report if the file is non-empty. Show violation count. Do not auto-fix DRC violations (they require routing-level changes).

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Manual skill invocation + bash script verification |
| Config file | none -- skills are markdown-defined |
| Quick run command | Manual: invoke `/chip-agent:pnr ALU` in Claude Code |
| Full suite command | Manual: invoke `/chip-agent:pnr ALU` and `/chip-agent:pnr Counter8`, verify report output |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CMD-01 | `/chip-agent:pnr ALU` runs synth+PnR+GDS in sequence | smoke | `test -f skills/pnr/SKILL.md && grep -q 'synth.sh' skills/pnr/SKILL.md && grep -q 'pnr.sh' skills/pnr/SKILL.md` | Wave 0 |
| CMD-01 (prereq check) | Skill checks for compiled Verilog before proceeding | unit | `grep -q 'generated.*\.v' skills/pnr/SKILL.md` | Wave 0 |
| CMD-02 (agent exists) | PnR report formatting agent definition exists | unit | `test -f agents/pnr-report-formatter.md && grep -q 'timing' agents/pnr-report-formatter.md && grep -q 'power' agents/pnr-report-formatter.md` | Wave 0 |
| CMD-02 (report format) | Agent produces human-readable timing/power/area table | manual-only | Invoke `/chip-agent:pnr ALU` and visually verify report output | Manual |
| CMD-03 (retry loop) | Skill defines 3-attempt retry for synth/PnR failures | unit | `grep -q '3' skills/pnr/SKILL.md && grep -q 'retry\|attempt\|auto-fix\|AUTO-FIX' skills/pnr/SKILL.md` | Wave 0 |
| CMD-03 (timing fix) | Auto-fix adjusts clock period on timing violation | unit | `grep -q 'clock.*period\|period.*relax\|period.*increase' skills/pnr/SKILL.md` | Wave 0 |

### Sampling Rate

- **Per task commit:** `test -f skills/pnr/SKILL.md && test -f agents/pnr-report-formatter.md` (structural check)
- **Per wave merge:** Structural checks + grep for key content patterns
- **Phase gate:** Manual invocation of `/chip-agent:pnr ALU` and `/chip-agent:pnr Counter8` with visual report verification

### Wave 0 Gaps

- [ ] `skills/pnr/SKILL.md` -- slash command definition
- [ ] `agents/pnr-report-formatter.md` -- report formatting agent
- [ ] `CLAUDE.md` update -- add `/chip-agent:pnr` to Commands section

## Sources

### Primary (HIGH confidence)

- Existing skill definitions (`skills/workflow/SKILL.md`, `skills/generate/SKILL.md`, `skills/compile/SKILL.md`, `skills/simulate/SKILL.md`, `skills/debug/SKILL.md`, `skills/initialize/SKILL.md`) -- analyzed for YAML frontmatter patterns, pipeline structure, auto-fix retry patterns, plugin root detection, and agent invocation conventions
- Existing agent definitions (`agents/requirement-parser.md`, `agents/chisel-generator.md`, `agents/testbench-generator.md`, `agents/debug-analyzer.md`) -- analyzed for agent definition structure, YAML format, and instruction patterns
- Phase 11 live output (`MyDesign/ALU/workspace/pnr/reports/`, `MyDesign/Counter8/workspace/pnr/reports/`) -- actual report file formats verified from completed PnR runs
- Phase 11 scripts (`scripts/synth.sh`, `scripts/pnr.sh`, `scripts/pnr.tcl`, `scripts/def2gds.py`) -- complete pipeline infrastructure verified working
- `.claude-plugin/plugin.json` -- plugin registration structure
- `package.json` -- npm package file list confirms skills/ and agents/ are distributed

### Secondary (MEDIUM confidence)

- Auto-fix strategy for timing violations (clock period relaxation) -- based on understanding of how SDC constraints propagate through synth.sh -> generate_sdc.sh -> pnr.sh chain, verified from script analysis but not tested with actual timing violations (both test modules have positive slack)
- Power unit conversion (Watts to microwatts) -- based on observed power magnitudes in test module reports

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all components are existing, verified Phase 9-11 infrastructure; no new tools or dependencies
- Architecture: HIGH -- skill and agent patterns verified across 8 existing skills and 4 existing agents; pipeline structure directly follows workflow skill pattern
- Pitfalls: HIGH -- all pitfalls derive from verified project conventions and Phase 11 behavior; auto-fix scope based on actual PnR error modes observed during Phase 11 development
- Report format: HIGH -- raw report formats verified from live ALU and Counter8 output files

**Research date:** 2026-04-01
**Valid until:** 2026-05-01 (stable -- all infrastructure is local, no external dependencies changing)
