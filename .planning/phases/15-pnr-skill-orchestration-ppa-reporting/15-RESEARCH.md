# Phase 15: PnR Skill Orchestration + PPA Reporting - Research

**Researched:** 2026-04-02
**Domain:** Claude Code skill orchestration via MCP tools, ORFS stage sequencing, PPA report formatting
**Confidence:** HIGH

## Summary

Phase 15 rewrites the `/chip-agent:pnr` skill (currently calling defunct `synth.sh` and `pnr.sh` scripts) to orchestrate the ORFS flow through the MCP tools built in Phases 13-14. The existing MCP server already provides four tools: `check_environment` (ORFS/PDK detection), `generate_config` (config.mk + constraint.sdc), `run_stage` (execute ORFS make targets), and `get_report` (extract stage metrics). The skill must call these tools in sequence, present per-stage metrics to the user, and after the final stage produce a formatted PPA summary report.

The current `skills/pnr/SKILL.md` references `scripts/synth.sh` and `scripts/pnr.sh`, which are now migration stubs that exit with error. The skill also references an `agents/pnr-report-formatter.md` agent that expects report files at `MyDesign/<Module>/workspace/pnr/reports/` -- but ORFS produces reports at `{ORFS_FLOW}/reports/sky130hd/{DESIGN_NAME}/base/`. The skill rewrite must bridge this gap: either copy ORFS outputs to the workspace, or direct the report formatter to read from ORFS paths directly.

**Primary recommendation:** Rewrite `skills/pnr/SKILL.md` to use MCP tool calls (`check_environment` -> `generate_config` -> `run_stage` x6 with `get_report` after each -> formatted PPA summary). Add `mcp__chipagent-backend__*` to the skill's `allowed-tools`. Update the `pnr-report-formatter.md` agent to accept ORFS report paths and parse the 6_finish.rpt power table (which the existing `get_report` tool does not fully extract).

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| FLOW-01 | /chip-agent:pnr skill rewritten to orchestrate via MCP tools instead of direct bash script invocation | Skill currently calls synth.sh/pnr.sh (stubs); rewrite to call check_environment, generate_config, run_stage, get_report MCP tools |
| FLOW-02 | Skill auto-advances through 6 ORFS stages sequentially (synth -> floorplan -> place -> cts -> route -> finish) | run_stage tool accepts stage name; skill calls in order with get_report after each |
| FLOW-03 | Per-stage metric extraction after each ORFS stage (cell count, design area, WNS, TNS, DRC violations) | get_report tool already parses synth_stat.txt (cell count), 6_finish.rpt (WNS/TNS), 6_report.log (area), 5_route_drc.rpt (DRC); per-stage .rpt files also contain WNS/TNS |
| RPT-01 | PPA summary report combining timing (WNS/TNS/clock period), power, and area metrics in formatted output | 6_finish.rpt contains report_power section with Internal/Switching/Leakage/Total; existing pnr-report-formatter.md defines exact output format |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| @modelcontextprotocol/sdk | 1.29.0 | MCP server framework | Already in use, provides tool call interface |
| zod | ^3.25 | Input validation | Already in mcp-server/package.json |
| Claude Code Plugin Skills | 0.1.0 | Skill definition and slash command routing | Skills are markdown-defined orchestration layers |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| node:fs | built-in | File operations | Reading ORFS reports, writing workspace copies |
| node:path | built-in | Path construction | Joining ORFS output paths |

No new dependencies needed. Phase 15 is purely a skill rewrite + minor MCP tool enhancement. All infrastructure exists from Phases 13-14.

## Architecture Patterns

### Recommended Project Structure
```
skills/
  pnr/SKILL.md              # REWRITE: MCP-based orchestration (Phase 15)
agents/
  pnr-report-formatter.md   # UPDATE: parse ORFS report paths, add power parsing from 6_finish.rpt
mcp-server/
  tools/
    get-report.ts            # ENHANCE: add power extraction from 6_finish.rpt report_power section
  tests/
    get-report.test.ts       # UPDATE: add power parsing tests
```

### Pattern 1: Skill Orchestration via MCP Tools
**What:** The skill SKILL.md instructs Claude to call MCP tools by name, not bash scripts
**When to use:** All Phase 15 skill steps
**Example flow in SKILL.md:**
```markdown
### Step 1 -- Check Environment
Call `mcp__chipagent-backend__check_environment` with no arguments.
Verify `orfs.installed === true` and `sky130hd.installed === true`.
If either is false, STOP with instructions to install ORFS and sky130hd PDK.
Extract `orfs.flow_path` for later use.

### Step 2 -- Generate Config
Call `mcp__chipagent-backend__generate_config` with:
- module_name: $MODULE
- verilog_path: absolute path to MyDesign/$MODULE/workspace/generated/$MODULE.v
- workspace_dir: absolute path to MyDesign/$MODULE/workspace
- clock_port: "clock" (or from spec.json if present)
- clock_period_ns: 10 (or from spec.json if present)
Extract config_mk and design_name from the response.

### Step 3 -- Run All 6 Stages Sequentially
For each stage in [synth, floorplan, place, cts, route, finish]:
  1. Call `mcp__chipagent-backend__run_stage` with stage, config_mk_path, orfs_flow_path
  2. If run_stage returns success === false, STOP with error
  3. Call `mcp__chipagent-backend__get_report` with design_name, stage, orfs_flow_path
  4. Present extracted metrics to user before advancing
```

### Pattern 2: Per-Stage Metric Presentation
**What:** After each stage, show relevant metrics to the user
**When to use:** Every run_stage + get_report cycle
**Stage-specific metrics from ORFS reports:**

| Stage | Report File | Key Metrics |
|-------|-------------|-------------|
| synth | synth_stat.txt | Cell count |
| floorplan | 2_floorplan_final.rpt | WNS, TNS (early estimates) |
| place | 3_detailed_place.rpt | WNS, TNS (post-placement) |
| cts | 4_cts_final.rpt | WNS, TNS (post-CTS) |
| route | 5_route_drc.rpt | DRC violations |
| finish | 6_finish.rpt + 6_report.log | WNS, TNS, power (Internal/Switching/Leakage/Total), area, utilization |

### Pattern 3: PPA Summary Report Format
**What:** Final report combining all PPA metrics after the finish stage
**Format from existing pnr-report-formatter.md agent:**
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
  Synthesis:   XXX um^2
  Post-PnR:    XXX um^2 (XX% utilization)
  Cell Count:  XXX

DRC:         Clean (0 violations)

Artifacts:
  Netlist:     MyDesign/<Module>/workspace/pnr/<Module>.synth.v
  Routed DEF:  MyDesign/<Module>/workspace/pnr/<Module>.routed.def
  GDS:         MyDesign/<Module>/workspace/pnr/<Module>.gds
  Reports:     MyDesign/<Module>/workspace/pnr/reports/
```

### Pattern 4: Power Extraction from 6_finish.rpt
**What:** The `report_power` section in 6_finish.rpt has a table format
**Verified format from actual ORFS output (nangate45/gcd):**
```
finish report_power
--------------------------------------------------------------------------
Group                  Internal  Switching    Leakage      Total
                          Power      Power      Power      Power (Watts)
----------------------------------------------------------------
Sequential             4.78e-04   1.12e-04   2.80e-06   5.93e-04  16.6%
Combinational          1.30e-03   1.35e-03   2.24e-05   2.67e-03  74.9%
Clock                  1.32e-04   1.72e-04   2.07e-07   3.04e-04   8.5%
Macro                  0.00e+00   0.00e+00   0.00e+00   0.00e+00   0.0%
Pad                    0.00e+00   0.00e+00   0.00e+00   0.00e+00   0.0%
----------------------------------------------------------------
Total                  1.91e-03   1.64e-03   2.55e-05   3.57e-03 100.0%
                          53.4%      45.9%       0.7%
```

**Parsing approach:**
1. Find "Total" row in the power table: `Total\s+([\d.e+-]+)\s+([\d.e+-]+)\s+([\d.e+-]+)\s+([\d.e+-]+)`
2. Extract: internal_W, switching_W, leakage_W, total_W
3. Find percentage line: `([\d.]+)%\s+([\d.]+)%\s+([\d.]+)%`
4. Convert all values to microwatts (multiply by 1e6)

### Pattern 5: MCP Tool Names in Skill allowed-tools
**What:** Skills must declare MCP tool names in their `allowed-tools` frontmatter
**Format:** MCP tools are available as `mcp__<server-name>__<tool-name>` in Claude Code
```yaml
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - mcp__chipagent-backend__check_environment
  - mcp__chipagent-backend__generate_config
  - mcp__chipagent-backend__run_stage
  - mcp__chipagent-backend__get_report
```

### Pattern 6: ORFS Artifact Paths vs Workspace Paths
**What:** ORFS writes outputs to its own directory tree, not to the module workspace
**ORFS output structure:**
```
{ORFS_FLOW}/results/sky130hd/{DESIGN_NAME}/base/
  1_2_yosys.v          # synthesized netlist
  6_1_merged.gds       # final GDS
  6_final.odb          # final database
{ORFS_FLOW}/reports/sky130hd/{DESIGN_NAME}/base/
  synth_stat.txt       # synthesis statistics
  6_finish.rpt         # final timing, power
{ORFS_FLOW}/logs/sky130hd/{DESIGN_NAME}/base/
  6_report.log         # area/utilization
```

**Workspace expectation (from pnr-report-formatter.md):**
```
MyDesign/<Module>/workspace/pnr/
  <Module>.synth.v     # synthesized netlist (copy from ORFS)
  <Module>.gds         # final GDS (copy from ORFS)
  reports/             # reports (copy from ORFS or read directly)
```

**Recommendation:** The skill should read reports directly from ORFS paths (returned by get_report tool). For artifact references in the final report, either copy key files to workspace or report ORFS paths. Copying is cleaner for the user.

### Anti-Patterns to Avoid
- **Calling synth.sh or pnr.sh directly:** These are migration stubs that exit(1). Use MCP tools only.
- **Assuming report files exist at workspace paths:** ORFS writes to its own directory. The get_report tool already handles ORFS paths.
- **Running stages out of order:** ORFS make targets depend on prior stage outputs. Must run in strict sequence: synth -> floorplan -> place -> cts -> route -> finish.
- **Parsing power in raw Watts:** Project convention is microwatts (uW). Always convert.
- **Skipping per-stage metric display:** FLOW-03 requires showing metrics after EACH stage, not just at the end.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ORFS environment detection | New detection logic | `check_environment` MCP tool | Already implemented in Phase 13 |
| Config.mk/SDC generation | New generator | `generate_config` MCP tool | Already implemented in Phase 14 |
| ORFS make execution | Direct bash spawn | `run_stage` MCP tool | Already implemented in Phase 14 with timeout, error handling |
| Report file reading/parsing | File reads in skill | `get_report` MCP tool | Already implemented in Phase 14 with parsers |
| PPA report formatting | Raw string manipulation | `pnr-report-formatter.md` agent | Already defines exact output format |

**Key insight:** Every building block for Phase 15 exists from Phases 13-14. This phase is purely orchestration (skill rewrite) and formatting (PPA report), not new tool development. The only MCP enhancement needed is adding power metrics extraction to get_report.

## Common Pitfalls

### Pitfall 1: ORFS Reports Not at Workspace Paths
**What goes wrong:** The old pnr-report-formatter.md agent expects files at `MyDesign/<Module>/workspace/pnr/reports/`. ORFS produces them at `{ORFS_FLOW}/reports/sky130hd/{DESIGN_NAME}/base/`.
**Why it happens:** The v1.1.2 scripts copied outputs to workspace; ORFS make does not.
**How to avoid:** Update the pnr-report-formatter.md agent to accept an ORFS report path parameter OR have the skill copy key report files to workspace after finish stage completes. The latter is simpler for user artifact management.
**Warning signs:** Agent reports "N/A" for all metrics despite successful ORFS run.

### Pitfall 2: Power Metrics Not Extracted by get_report
**What goes wrong:** The current `get_report` tool parses WNS/TNS (from 6_finish.rpt) and area (from 6_report.log), but does NOT extract power metrics from the report_power table in 6_finish.rpt.
**Why it happens:** Phase 14 scope was metric extraction basics; power parsing was deferred.
**How to avoid:** Enhance `parseFinishReport` in `get-report.ts` to also extract the Total power row and percentage breakdown from the `report_power` section.
**Warning signs:** PPA report shows power as "N/A" despite 6_finish.rpt containing power data.

### Pitfall 3: Timing MET/VIOLATED Detection from 6_finish.rpt
**What goes wrong:** The 6_finish.rpt contains multiple `slack (MET)` and `slack (VIOLATED)` lines for different path groups (min path, max path, reg-to-reg). The overall timing status depends on the `report_wns` section, not individual path slack lines.
**Why it happens:** Naive parsing of "slack (VIOLATED)" anywhere in the file.
**How to avoid:** Use the `wns` value from `parseFinishReport` (already extracted from `report_wns` section). If WNS is negative, timing is VIOLATED. If WNS >= 0, timing is MET.
**Warning signs:** Reporting timing violation when only hold paths are violated but setup passes.

### Pitfall 4: MCP Tool Name Format in Skills
**What goes wrong:** Skill uses wrong tool name format and Claude cannot find the MCP tool.
**Why it happens:** MCP tools in Claude Code use `mcp__<server>__<tool>` format, which is not obvious.
**How to avoid:** Use exact format: `mcp__chipagent-backend__run_stage`. The server name comes from `.mcp.json` key `chipagent-backend`.
**Warning signs:** "Tool not found" errors when skill attempts MCP calls.

### Pitfall 5: Clock Period Not Read from spec.json
**What goes wrong:** Skill hardcodes 10ns clock period instead of reading from module's spec.json.
**Why it happens:** Previous skill read spec.json; new skill might skip this.
**How to avoid:** Skill should read `MyDesign/<Module>/workspace/spec.json` and use `clock_period_ns` if present, falling back to 10ns default.
**Warning signs:** All modules get same clock period regardless of their spec.

### Pitfall 6: Missing Synthesis Area in PPA Report
**What goes wrong:** The PPA report has "Synthesis area" as a field, but `synth_stat.txt` contains `Chip area for module '\\<Module>': XXX.XXX` which is not parsed by current `parseSynthStat`.
**Why it happens:** `parseSynthStat` only extracts cell count.
**How to avoid:** Enhance `parseSynthStat` to also extract chip area from the `Chip area for module` line.
**Warning signs:** Synthesis area shows "N/A" in PPA report.

## Code Examples

### Power Parsing Enhancement for get-report.ts
```typescript
// Source: ORFS 6_finish.rpt verified format (nangate45/gcd run)
export function parsePower(content: string): {
  total_w: number | null;
  internal_pct: number | null;
  switching_pct: number | null;
  leakage_pct: number | null;
} {
  const totalMatch = content.match(
    /^Total\s+([\d.e+-]+)\s+([\d.e+-]+)\s+([\d.e+-]+)\s+([\d.e+-]+)/m
  );
  const pctMatch = content.match(
    /^\s+([\d.]+)%\s+([\d.]+)%\s+([\d.]+)%\s*$/m
  );

  if (!totalMatch) {
    return { total_w: null, internal_pct: null, switching_pct: null, leakage_pct: null };
  }

  return {
    total_w: parseFloat(totalMatch[4]),
    internal_pct: pctMatch ? parseFloat(pctMatch[1]) : null,
    switching_pct: pctMatch ? parseFloat(pctMatch[2]) : null,
    leakage_pct: pctMatch ? parseFloat(pctMatch[3]) : null,
  };
}
```

### Synthesis Area Parsing Enhancement
```typescript
// Source: ORFS synth_stat.txt verified format
export function parseSynthArea(content: string): { synth_area: number | null } {
  const match = content.match(/Chip area for module '\\?\w+':\s+([\d.]+)/);
  return { synth_area: match ? parseFloat(match[1]) : null };
}
```

### Skill MCP Tool Call Pattern
```markdown
### Step 3.1 -- Run Synthesis
Call `mcp__chipagent-backend__run_stage` with:
- stage: "synth"
- config_mk_path: (from Step 2 response)
- orfs_flow_path: (from Step 1 response)

If response shows `success: false`:
  Read the `stderr` field for error details.
  STOP with message: "SYNTHESIS FAILED. Error: <stderr>"

On success, call `mcp__chipagent-backend__get_report` with:
- design_name: (from Step 2 response)
- stage: "synth"
- orfs_flow_path: (from Step 1 response)

Present to user:
  Synthesis complete. Cell count: <cell_count>, Synthesis area: <synth_area> um^2
```

### Per-Stage Metric Display Pattern
```markdown
For each stage result, display:

synth:     "Synthesis: <cell_count> cells, <synth_area> um^2"
floorplan: "Floorplan: WNS=<wns>ns, TNS=<tns>ns (early estimate)"
place:     "Placement: WNS=<wns>ns, TNS=<tns>ns"
cts:       "CTS: WNS=<wns>ns, TNS=<tns>ns"
route:     "Routing: <violations> DRC violations"
finish:    "Finish: WNS=<wns>ns, TNS=<tns>ns, Area=<area>um^2, Power=<power>uW"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `scripts/synth.sh` + `scripts/pnr.sh` | MCP tools via run_stage | Phase 13 (stubs), Phase 14 (tools) | Scripts are dead stubs; all flow via ORFS make |
| Skill reads report files via Bash/Read | Skill calls get_report MCP tool | Phase 14 | Structured JSON metrics instead of raw file parsing |
| Report files at workspace/pnr/reports/ | ORFS writes to flow/reports/sky130hd/ | Phase 13 (architecture change) | Must bridge path gap in skill or agent |
| No power extraction | Need power from 6_finish.rpt | Phase 15 (new) | get_report must be enhanced for power metrics |

**Deprecated/outdated:**
- `scripts/synth.sh`: Migration stub, exit(1). DO NOT CALL.
- `scripts/pnr.sh`: Migration stub, exit(1). DO NOT CALL.
- Report paths `MyDesign/<Module>/workspace/pnr/reports/*.rpt`: These are v1.1.2 artifact locations. ORFS produces reports at `{ORFS_FLOW}/reports/sky130hd/{DESIGN_NAME}/base/`.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Node.js built-in test runner (node --test) |
| Config file | none |
| Quick run command | `node --test mcp-server/tests/*.test.ts` |
| Full suite command | `node --test mcp-server/tests/*.test.ts` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FLOW-01 | Skill uses MCP tools not scripts | manual | Invoke `/chip-agent:pnr ALU8` and verify no synth.sh/pnr.sh calls | manual-only |
| FLOW-02 | Sequential 6-stage execution | manual | Invoke `/chip-agent:pnr ALU8` and verify all 6 stages run | manual-only |
| FLOW-03 | Per-stage metric extraction | unit | `node --test mcp-server/tests/get-report.test.ts` | Yes (update needed) |
| RPT-01 | PPA summary with timing/power/area | unit | `node --test mcp-server/tests/get-report.test.ts` | Yes (update needed) |

**Justification for manual-only on FLOW-01 and FLOW-02:** These are skill orchestration requirements. Skills are markdown files that instruct Claude -- they cannot be unit-tested. Verification requires invoking the actual slash command.

### Sampling Rate
- **Per task commit:** `node --test mcp-server/tests/*.test.ts`
- **Per wave merge:** Full suite
- **Phase gate:** Full suite green + manual `/chip-agent:pnr` invocation

### Wave 0 Gaps
- [ ] `mcp-server/tests/get-report.test.ts` -- add tests for power parsing (parsePower) and synthesis area parsing (parseSynthArea)
- [ ] Test fixtures: sample 6_finish.rpt with report_power section, sample synth_stat.txt with Chip area line

## Open Questions

1. **Artifact copying from ORFS to workspace**
   - What we know: ORFS writes results to `flow/results/sky130hd/{design}/base/` and reports to `flow/reports/sky130hd/{design}/base/`. The existing pnr-report-formatter.md agent and SKILL.md reference workspace paths.
   - What's unclear: Should the skill copy ORFS artifacts (GDS, netlist, reports) to the module workspace, or should we update agents to use ORFS paths directly?
   - Recommendation: Have the skill copy key artifacts (GDS, synthesized netlist, reports) from ORFS to `MyDesign/<Module>/workspace/pnr/` after the finish stage. This keeps the workspace self-contained and matches user expectations from v1.1.2.

2. **Timing violation auto-retry scope**
   - What we know: The old skill had a 3-attempt auto-retry loop that increased clock period by 50% on timing violation. RECV-01 (v1.2 requirement) covers this more formally.
   - What's unclear: Should Phase 15 include basic timing retry (as the old skill had), or defer entirely to v1.2?
   - Recommendation: Include basic timing retry in Phase 15. The old skill already had it, and the MCP tools support re-running stages. However, this is not in the explicit FLOW-01/02/03/RPT-01 requirements, so it can be a stretch goal in the second plan.

3. **get_report enhancement scope**
   - What we know: get_report currently parses WNS/TNS (6_finish.rpt), cell count (synth_stat.txt), area/utilization (6_report.log), DRC violations (5_route_drc.rpt). Missing: power, synthesis area, per-stage WNS/TNS.
   - What's unclear: How much to enhance get_report vs. having the PPA formatter parse raw files.
   - Recommendation: Add power parsing and synthesis area to get_report (small, testable additions). Keep the report formatter focused on presentation, not parsing.

## Sources

### Primary (HIGH confidence)
- `mcp-server/tools/run-stage.ts` -- verified run_stage tool implementation (97 lines)
- `mcp-server/tools/get-report.ts` -- verified get_report tool with 4 parsers (85 lines)
- `mcp-server/tools/generate-config.ts` -- verified generate_config tool (117 lines)
- `mcp-server/tools/check-environment.ts` -- verified check_environment tool (113 lines)
- `mcp-server/index.ts` -- verified server entry with all 4 tools registered
- `skills/pnr/SKILL.md` -- current skill definition (144 lines, references defunct scripts)
- `agents/pnr-report-formatter.md` -- report format definition (107 lines)
- `OpenROAD-flow-scripts/flow/reports/nangate45/gcd/base/6_finish.rpt` -- actual ORFS finish report format (verified power table layout)
- `OpenROAD-flow-scripts/flow/reports/nangate45/gcd/base/synth_stat.txt` -- actual synthesis statistics format (verified cell count + chip area)
- `OpenROAD-flow-scripts/flow/logs/nangate45/gcd/base/6_report.log` -- actual area/utilization format (verified line 63)
- `.mcp.json` -- MCP server configuration (server name: chipagent-backend, stdio transport)
- `.chipagent/env.json` -- environment detection results (ORFS at ~/OpenROAD-flow-scripts/flow)

### Secondary (MEDIUM confidence)
- `skills/workflow/SKILL.md` -- reference pattern for multi-stage skill orchestration
- `.planning/phases/14-config-generation-orfs-stage-execution/14-VERIFICATION.md` -- Phase 14 completion status

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new dependencies, all tools exist from Phases 13-14
- Architecture: HIGH -- skill rewrite pattern clear, MCP tool interfaces verified from source code
- Pitfalls: HIGH -- verified from actual ORFS outputs and existing codebase analysis
- PPA report format: HIGH -- verified from existing pnr-report-formatter.md agent and actual 6_finish.rpt content

**Research date:** 2026-04-02
**Valid until:** 2026-05-02 (stable codebase, ORFS flow unchanged)
