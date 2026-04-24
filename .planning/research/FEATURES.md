# Feature Landscape

**Domain:** Smart retry, error diagnosis, and QoR optimization for ORFS-based PnR pipeline
**Researched:** 2026-04-02
**Milestone:** v1.2.0 Smart Retry & QoR Optimization
**Target level:** task2 满分要求 (failure diagnosis, parameter retry, multi-round QoR comparison)

## Context: What Exists vs What Is New

The existing v1.1.5 PnR pipeline provides:
- 6-stage ORFS flow (synth -> floorplan -> place -> cts -> route -> finish) via MCP tools
- Per-stage metric extraction (cell_count, synth_area, WNS, TNS, DRC violations, power, area, utilization)
- PPA summary report via pnr-report-formatter agent
- Simple clock period relaxation retry (50% increase, 3 attempts) -- **currently described in PROJECT.md key decisions but NOT implemented in v1.1.5 pnr SKILL.md** (the skill stops on failure)

**Existing MCP tools (already built):**
- `check_environment` -- verifies ORFS + sky130hd installation
- `generate_config` -- creates config.mk + constraint.sdc (accepts `clock_period_ns`, `core_utilization`)
- `run_stage` -- executes ORFS make target, returns stdout/stderr/exit_code
- `get_report` -- extracts structured metrics from ORFS report files

**What v1.2.0 adds on top:**
1. Error classification from stage failure outputs (stderr + metrics)
2. Error-type-specific parameter adjustment strategies
3. Regenerate config and re-run from the failed stage
4. Multi-round run tracking with configuration comparison table

**Key constraint:** All new features build on existing MCP tools. No new MCP tools are strictly required -- the skill layer (orchestration) handles diagnosis, retry decisions, and comparison logic. However, a `clean_stage` MCP tool would simplify re-running from a specific stage.

---

## Table Stakes

Features the task2 满分要求 rubric explicitly requires. Missing = not reaching 满分 tier.

| # | Feature | Why Expected | Complexity | Dependencies | Notes |
|---|---------|-------------|------------|--------------|-------|
| T1 | **Error type classification** | 满分要求: "流程失败自动诊断错误类型（时序违例、拥塞、DRC 等）" | Med | Existing `run_stage` stderr + `get_report` metrics | Parse stage failure output to classify into: timing violation (WNS < 0), routing congestion (`[ERROR GRT-0118]` or high overflow), DRC violations (violation count > 0), synthesis failure (yosys error), setup/hold violation (negative slack in specific paths), max slew/cap/fanout violations. Must handle both exit-code failures AND "succeeded but with violations" cases. |
| T2 | **Error-type-specific parameter retry** | 满分要求: "按错误类型实施参数重试（调整 PLACE_DENSITY、CLOCK_PERIOD）" | High | T1 (diagnosis), existing `generate_config` tool | Each error type maps to specific parameter adjustments. Regenerate config.mk/SDC with new parameters, clean affected stages, re-run from the earliest affected stage. Max 3 retry rounds per error type. Must avoid infinite loops. |
| T3 | **Multi-round QoR comparison** | 满分要求: "支持多轮 QoR 优化，对比不同配置结果" | Med | T2 (multiple successful runs) | Track each run's configuration + PPA results. Display side-by-side comparison table showing run number, parameters changed, and resulting metrics. Highlight best run for each metric category. |

---

## Table Stakes -- Detailed Specification

### T1: Error Type Classification

**Error taxonomy for ORFS stages:**

| Error Type | Detection Method | Affected Stages | Confidence |
|-----------|-----------------|-----------------|------------|
| **Timing violation (setup)** | WNS < 0 in finish/route get_report metrics | route, finish | HIGH -- WNS is directly reported |
| **Timing violation (hold)** | Hold slack < 0 in timing report | cts, route | MEDIUM -- requires parsing raw report text |
| **Routing congestion** | stderr contains `[ERROR GRT-0118]` or `Routing congestion too high` | route | HIGH -- distinctive error message |
| **DRC violations** | `violations > 0` in route get_report metrics | route, finish | HIGH -- directly reported |
| **Synthesis failure** | `run_stage` returns `success: false` for synth stage | synth | HIGH -- exit code based |
| **Max slew/cap/fanout** | stderr contains `max slew violation` / `max capacitance violation` / `max fanout violation` | place, cts, route | MEDIUM -- log pattern matching |
| **Placement density overflow** | stderr contains `placement overflow` or `not enough sites` | place | MEDIUM -- log pattern matching |
| **Timeout** | `run_stage` returns stderr `"Process timed out"` | any | HIGH -- existing timeout detection |

**Implementation approach:** Parse both `run_stage` stderr AND `get_report` metrics after each stage. Return a structured diagnosis object:

```typescript
interface Diagnosis {
  error_type: 'timing_setup' | 'timing_hold' | 'congestion' | 'drc' | 'synthesis' | 'slew_cap_fanout' | 'placement_overflow' | 'timeout' | 'unknown';
  stage: string;
  severity: 'critical' | 'warning';
  details: string;       // human-readable description
  suggested_action: string; // what parameter to adjust
}
```

**"Succeeded but with violations" handling:** Even when `run_stage` returns `success: true`, check metrics:
- After route: if `violations > 0`, classify as DRC warning
- After finish: if `WNS < 0`, classify as timing violation (the flow "completed" but timing is not met)
- This is the most common case -- ORFS does not always fail on timing violations, it completes and reports them

### T2: Error-Type-Specific Parameter Retry

**Parameter adjustment strategies per error type:**

| Error Type | Parameter to Adjust | Adjustment Strategy | Restart From Stage | Max Retries |
|-----------|-------------------|--------------------|--------------------|-------------|
| **Timing (setup)** | `clock_period_ns` | Increase by 50% per attempt (existing pattern) | synth (clock period affects synthesis) | 3 |
| **Timing (hold)** | `HOLD_SLACK_MARGIN` | Set to 0.1ns, then 0.2ns, then 0.3ns | cts (hold repair happens post-CTS) | 3 |
| **Routing congestion** | `PLACE_DENSITY` | Decrease by 0.1 per attempt (e.g., 0.6 -> 0.5 -> 0.4) | place (density affects placement) | 3 |
| **Routing congestion (severe)** | `CORE_UTILIZATION` | Decrease by 10 per attempt (e.g., 40 -> 30 -> 20) | floorplan (changes die size) | 3 |
| **DRC violations** | `DETAILED_ROUTE_END_ITERATION` | Increase from 64 to 128, then 256 | route | 2 |
| **Max slew/cap** | `SETUP_SLACK_MARGIN` | Set to -0.1ns (allow more repair iterations) | place | 2 |
| **Placement overflow** | `CORE_UTILIZATION` | Decrease by 10 per attempt | floorplan | 3 |

**Retry workflow:**
1. Diagnose error type (T1)
2. Look up adjustment strategy for that error type
3. Call `generate_config` with adjusted parameters (existing MCP tool already accepts `clock_period_ns` and `core_utilization`)
4. For parameters not in `generate_config` (PLACE_DENSITY, HOLD_SLACK_MARGIN, etc.): append to config.mk directly via Write tool
5. Clean stages from restart point onward (call `make clean_<stage>` via Bash or new MCP tool)
6. Re-run stages from restart point
7. Re-diagnose; if same error persists after max retries, report failure with all attempts

**Key insight:** The existing `generate_config` MCP tool only accepts `clock_period_ns` and `core_utilization`. Additional parameters (PLACE_DENSITY, HOLD_SLACK_MARGIN, DETAILED_ROUTE_END_ITERATION) need to be either:
- Option A: Added as optional parameters to `generate_config` (requires MCP tool update)
- Option B: Appended to config.mk after generation via file editing (no MCP change needed)

**Recommendation: Option A** -- extend `generate_config` to accept additional optional parameters. Keeps all config generation in one place. The config.mk template already uses `?=` for some values (like TNS_END_PERCENT), so adding more is straightforward.

### T3: Multi-Round QoR Comparison

**Run tracking data structure:**

```typescript
interface RunRecord {
  run_number: number;
  config: {
    clock_period_ns: number;
    core_utilization: number;
    place_density: number;
    // any other adjusted parameters
  };
  trigger: string;  // 'initial' | 'timing_retry' | 'congestion_retry' | etc.
  metrics: {
    wns: number;
    tns: number;
    total_power_uw: number;
    area_um2: number;
    cell_count: number;
    drc_violations: number;
    utilization_pct: number;
  };
  timing_met: boolean;
  drc_clean: boolean;
}
```

**Comparison table format:**

```
=== QoR Comparison: ALU8 (3 runs) ===

| # | Trigger       | Clock(ns) | Density | Util | WNS(ns) | TNS(ns) | Power(uW) | Area(um2) | DRC | Status |
|---|---------------|-----------|---------|------|---------|---------|-----------|-----------|-----|--------|
| 1 | initial       | 10.0      | 0.60    | 40%  | -0.23   | -1.45   | 45.2      | 1234      |  0  | TIMING |
| 2 | timing_retry  | 15.0      | 0.60    | 40%  |  0.15   |  0.00   | 38.1      | 1234      |  0  | PASS   |
| 3 | timing_retry  | 22.5      | 0.60    | 40%  |  2.34   |  0.00   | 32.5      | 1234      |  0  | PASS   |

Best timing:  Run 3 (WNS = 2.34 ns)
Best power:   Run 3 (32.5 uW)
Best area:    Run 1 (1234 um2)
Recommended:  Run 2 (timing met with tightest clock period)
```

**Selection heuristic:** Recommend the run with the tightest clock period that still meets timing (WNS >= 0) and has zero DRC violations. This maximizes performance while ensuring design closure.

---

## Differentiators

Features that go beyond the rubric requirements. Not required for 满分 but demonstrate deeper understanding.

| # | Feature | Value Proposition | Complexity | Dependencies | Notes |
|---|---------|-------------------|------------|--------------|-------|
| D1 | **MCP `clean_stage` tool** | Clean specific stage outputs to enable selective re-run without full `clean_all` | Low | Existing MCP server | `make clean_<stage>` via ORFS. Without this, retry must re-run ALL stages from scratch, wasting 5-10 min per attempt. Critical for efficient retry. |
| D2 | **Cascading stage clean** | When retrying from stage N, automatically clean stages N through finish | Low | D1 | ORFS stages are dependent -- cleaning "place" requires also cleaning cts, route, finish. Automate this cascade. |
| D3 | **Extend `generate_config` with tuning params** | Add PLACE_DENSITY, HOLD_SLACK_MARGIN, SETUP_SLACK_MARGIN, DETAILED_ROUTE_END_ITERATION as optional params | Low | Existing `generate_config` tool | Keeps all config generation in MCP tool instead of file-editing workarounds. |
| D4 | **Run history persistence** | Save run records to `workspace/pnr/run_history.json` for cross-session comparison | Low | T3 | Enables comparing runs across separate `/chip-agent:pnr` invocations, not just within one session. |
| D5 | **metadata.json extraction** | Read ORFS-generated metadata.json for comprehensive metrics instead of individual report parsing | Low | Existing MCP tools | ORFS generates `metadata-<design>-base.json` after finish stage with ALL metrics in METRICS2.1 JSON format. More reliable than individual report file parsing. |
| D6 | **Congestion heatmap reference** | After routing, note the path to `final_congestion.webp` visualization in the report | Low | Finish stage complete | ORFS auto-generates visualization images. Referencing them helps users understand congestion issues. |
| D7 | **Pareto-optimal run selection** | Identify Pareto-optimal runs across power/performance/area tradeoff space | Med | T3 (multiple runs) | Instead of simple "best per metric", identify runs that are not dominated on any axis. More sophisticated recommendation. |

---

## Anti-Features

Features to explicitly NOT build. These would waste time or cause problems.

| # | Anti-Feature | Why Avoid | What to Do Instead |
|---|-------------|-----------|-------------------|
| A1 | **AutoTuner integration** | ORFS AutoTuner (Ray-based hyperparameter tuning) is a heavy ML framework requiring Ray, NEVERGRAD, etc. Massive dependency for marginal benefit on small designs. | Use simple rule-based parameter adjustment (T2). For ALU-class designs, 3 retry rounds are sufficient. |
| A2 | **RTL modification for timing closure** | Synthesis failures or deep timing violations may require RTL changes. This crosses the RTL/backend boundary and is explicitly out of scope (PROJECT.md: "No synthesis retry"). | Report synthesis failures as unrecoverable. Suggest user modify RTL and re-run. |
| A3 | **Multi-corner STA** | Out of scope per PROJECT.md. Single typical corner is sufficient. | Use single corner (sky130hd typical lib). |
| A4 | **Parallel multi-config exploration** | Running multiple ORFS flows simultaneously with different configs. Requires container orchestration complexity. | Run configs sequentially, track results, compare after all complete. |
| A5 | **User-interactive parameter selection** | Prompting user mid-flow to choose retry parameters. Breaks "no human in the loop" principle. | Fully automatic diagnosis and retry. Present comparison table only at the end. |
| A6 | **Exhaustive parameter sweep** | Trying all combinations of clock period, density, utilization, etc. Combinatorial explosion (3^3 = 27 runs at ~5 min each = 2+ hours). | Use error-type-directed single-parameter adjustment. Only change the parameter relevant to the diagnosed error. |
| A7 | **Custom Tcl script injection** | Allowing users to inject custom OpenROAD Tcl commands for optimization. Breaks the ORFS make flow abstraction. | All tuning via config.mk variables only, which ORFS Makefile respects. |

---

## Feature Dependencies

```
Existing v1.1.5 pipeline
    |
    v
T1 (error classification) -----> T2 (parameter retry)
    |                                  |
    |                                  v
    |                          D1 (clean_stage tool)
    |                          D2 (cascading clean)
    |                          D3 (extend generate_config)
    |                                  |
    |                                  v
    +------------------------------> T3 (QoR comparison)
                                       |
                                       v
                                D4 (run history persistence)
                                D7 (Pareto selection)
```

Key ordering constraints:
- T1 (diagnosis) must exist before T2 (retry) can make informed parameter decisions
- T2 (retry) produces multiple runs, which T3 (comparison) needs
- D1 (clean_stage) is highly desirable before T2, otherwise retry re-runs all 6 stages
- D3 (extend generate_config) is highly desirable before T2, otherwise config editing is awkward
- T3 can display results even from a single run (comparison with "no change" baseline)

**Critical path for implementation:** D1 + D3 -> T1 -> T2 -> T3

---

## Error Type Detail: ORFS Stage Failure Signatures

**These are the specific patterns to match in `run_stage` stderr and `get_report` metrics.**

### Synthesis Stage (synth)
| Pattern | Meaning |
|---------|---------|
| `ERROR: .*can't open file` | Missing Verilog input |
| `ERROR: .*syntax error` | RTL syntax error (unrecoverable) |
| exit_code != 0 | General synthesis failure (unrecoverable -- needs RTL fix) |

### Floorplan Stage
| Pattern | Meaning |
|---------|---------|
| `not enough sites` | Die area too small for cell count -- decrease CORE_UTILIZATION |
| `No valid sites` | Floorplan impossible -- decrease CORE_UTILIZATION significantly |

### Placement Stage (place)
| Pattern | Meaning |
|---------|---------|
| `Placement overflow` | Cells don't fit -- decrease PLACE_DENSITY or CORE_UTILIZATION |
| `cannot place` | Hard placement failure |

### CTS Stage (cts)
| Pattern | Meaning |
|---------|---------|
| `no clock found` | Design has no clock (should have been detected earlier as combinational) |
| hold slack violations in report | Hold timing issues -- adjust HOLD_SLACK_MARGIN |

### Route Stage (route)
| Pattern | Meaning |
|---------|---------|
| `[ERROR GRT-0118]` or `Routing congestion too high` | Congestion -- decrease PLACE_DENSITY |
| `violations > 0` in DRC report | DRC issues -- increase DETAILED_ROUTE_END_ITERATION |

### Finish Stage (finish)
| Pattern | Meaning |
|---------|---------|
| WNS < 0 in metrics | Setup timing violation -- increase clock period |
| TNS < -threshold | Widespread timing issues -- increase clock period more aggressively |

---

## Parameters Available in Existing generate_config Tool

Currently `generate_config` accepts:
- `module_name` (required)
- `verilog_path` (required)
- `workspace_dir` (required)
- `clock_port` (optional, default "clock")
- `clock_period_ns` (optional, default 10)
- `core_utilization` (optional, default 40)

**Parameters to add for retry support:**

| Parameter | Type | Default | What It Controls |
|-----------|------|---------|-----------------|
| `place_density` | number (0.0-1.0) | 0.60 | Cell placement density -- lower = less congestion |
| `setup_slack_margin` | number (ns) | 0 | Margin for setup repair -- negative allows underfixing |
| `hold_slack_margin` | number (ns) | 0 | Margin for hold repair |
| `detailed_route_end_iteration` | number | 64 | Max detail routing iterations -- more = fewer DRC |
| `routing_layer_adjustment` | number (0.0-1.0) | 0.5 | Layer capacity adjustment -- lower = less congestion |

These map directly to ORFS config.mk variables (use `export VAR = value` lines).

---

## MVP Recommendation

Prioritize for 满分要求:

1. **D1** (clean_stage MCP tool) -- enables efficient retry without re-running all stages (15 min)
2. **D3** (extend generate_config) -- adds tuning parameters to MCP tool (15 min)
3. **T1** (error classification) -- parse stderr + metrics into structured diagnosis (1-2 hr)
4. **T2** (parameter retry) -- error-to-parameter mapping + retry loop in pnr skill (2-3 hr)
5. **T3** (QoR comparison) -- run tracking + comparison table formatting (1 hr)

**Total estimated effort:** 5-7 hours

**Defer:** D2 (cascading clean -- can be done inline in skill), D4-D7 (nice-to-haves)

**Implementation order rationale:**
- D1 and D3 are infrastructure that T2 needs -- build them first
- T1 is the diagnostic brain that T2 relies on for decisions
- T2 is the core retry loop that produces multiple runs
- T3 presents results from T2's multiple runs
- All three T-features compose into a single enhanced `/chip-agent:pnr` skill

---

## Sources

- [ORFS Flow Variables (tunable parameters)](https://openroad-flow-scripts.readthedocs.io/en/latest/user/FlowVariables.html)
- [ORFS Flow Variables (GitHub)](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/master/docs/user/FlowVariables.md)
- [ORFS Flow Tutorial](https://openroad-flow-scripts.readthedocs.io/en/latest/tutorials/FlowTutorial.html)
- [ORFS Metrics Documentation](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/master/docs/contrib/Metrics.md)
- [ORFS AutoTuner Instructions](https://openroad-flow-scripts.readthedocs.io/en/latest/user/InstructionsForAutoTuner.html)
- [ORFS Routing Congestion Issue #1655](https://github.com/The-OpenROAD-Project/OpenROAD/issues/1655)
- [METRICS2.1 Paper (IEEE CEDA)](https://vlsicad.ucsd.edu/Publications/Conferences/388/c388.pdf)
- [OpenROAD MCP for AI timing closure](https://dev.to/luarss/openroad-mcp-let-ai-close-your-timing-47h6)
- [ORFS DeepWiki](https://deepwiki.com/The-OpenROAD-Project/OpenROAD-flow-scripts)
- [Automated QoR improvement with coding agents (arXiv)](https://arxiv.org/html/2601.06268)
