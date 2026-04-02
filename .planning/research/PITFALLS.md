# Domain Pitfalls: v1.2.0 Smart Retry & QoR Optimization

**Domain:** Adding intelligent failure diagnosis, error-type-based parameter retry, and multi-round QoR optimization to existing ChipAgent ORFS-based PnR pipeline
**Researched:** 2026-04-02
**Confidence:** HIGH (ORFS Makefile behavior verified from documentation and local codebase, parameter interactions verified from OpenROAD docs and ORFS-agent paper, existing MCP server source code analyzed)
**Supersedes:** v1.1.5 PITFALLS.md for retry/QoR topics only. v1.1.5 pitfalls about Docker, MCP protocol, sky130hd PDK remain valid and are not repeated here.

---

## Critical Pitfalls

Mistakes that cause infinite retry loops, silent wrong results, or architectural rework.

### Pitfall 1: ORFS Make Caches Stale Results -- Retry Without Clean Produces Ghost Metrics

**What goes wrong:** ORFS uses Make-based dependency tracking. When you change `CLOCK_PERIOD` or `PLACE_DENSITY` in config.mk and re-run `make synth`, Make checks timestamps: if the cached `results/sky130hd/<DESIGN>/base/1_synth.v` is newer than the Makefile target's prerequisites, Make skips the stage entirely. The retry appears to succeed instantly, but the reports still reflect the OLD parameter values. The QoR comparison table then compares identical results with different labels, producing a meaningless "optimization" that looks like it tried different configs but actually never re-ran anything.

**Why it happens:** ORFS's Makefile tracks file timestamps, not config.mk content. Editing config.mk does not update the timestamp of intermediate `.odb` files. Furthermore, the Makefile does NOT invalidate downstream stages when upstream config changes -- if you only change `PLACE_DENSITY` (a placement parameter), Make considers the synthesis output still valid, but it ALSO considers the placement output valid because the `.odb` file is newer than the Makefile target.

**Consequences:** All retry iterations report identical metrics. The QoR comparison table shows the same WNS/TNS/area across all configurations. The user believes the tool tried different parameters when it actually did nothing. This is the single most likely pitfall to ship undetected because the flow "succeeds" every time.

**Prevention:**
- Before EVERY retry iteration, run `make clean_all DESIGN_CONFIG=<path>` in the ORFS flow directory. This is non-negotiable.
- The MCP server needs a new `clean_stage` tool (or extend `run_stage` with a `clean_first` boolean parameter). Currently, `run-stage.ts` calls `make <stage>` directly with NO clean.
- Alternatively, add `make clean_all` as the first `make` arg in every retry: `make clean_all <stage> DESIGN_CONFIG=...`
- For QoR optimization specifically, each round should clean ALL stages, not just the modified one, because ORFS does not track cross-stage parameter dependencies.
- After each run, verify that the report timestamp is newer than the config.mk timestamp as a sanity check.

**Detection:** Retry completes in <1 second (real runs take minutes). Report metrics are byte-identical across iterations. `ls -la` on ORFS result files shows unchanged timestamps.

**Phase:** Must be addressed in the very first task that implements retry. Every other feature depends on this working correctly.

---

### Pitfall 2: Parameter Interaction Makes Independent Adjustment Counterproductive

**What goes wrong:** Adjusting parameters one at a time (e.g., relax CLOCK_PERIOD for timing, then reduce PLACE_DENSITY for congestion) can produce oscillating results. Relaxing clock period may fix timing but the next round tightens density causing congestion, which degrades timing again, triggering another clock relaxation. The retry loop never converges.

**Key parameter interactions (verified from OpenROAD docs and ORFS-agent paper):**

| Parameter A | Parameter B | Interaction |
|-------------|-------------|-------------|
| CLOCK_PERIOD (SDC) | PLACE_DENSITY | Tighter clock drives timing-driven placement to pack critical paths closer (effectively increasing local density). Relaxing clock may allow lower density. |
| PLACE_DENSITY | Routing congestion | Higher density = shorter wires = better timing BUT more routing congestion on sky130hd's 5 metal layers. |
| CORE_UTILIZATION | PLACE_DENSITY | Utilization sets the die area; density sets how tightly cells fill that area. Lowering utilization without adjusting density creates wasted space. |
| SETUP_SLACK_MARGIN | HOLD_SLACK_MARGIN | Fixing setup by inserting buffers can break hold (longer paths). Fixing hold by adding delay cells can break setup (added load). These MUST be adjusted together. |
| ABC_AREA vs ABC_SPEED | CLOCK_PERIOD | Area-optimized synthesis produces smaller but slower netlists. Switching to speed-optimized synthesis for timing retry changes cell count AND timing simultaneously. |
| PLACE_DENSITY | CTS_CLUSTER_SIZE | Dense placement clusters sinks closer, but if CTS clustering is too aggressive it increases clock skew, which eats into setup margin. |

**Consequences:** Retry loop oscillates between configurations without converging. Each "fix" for one error type introduces another. After max retries, the final result may be worse than the first attempt.

**Prevention:**
- Define parameter adjustment as BUNDLES, not individual tweaks. Example: "timing violation bundle" = relax CLOCK_PERIOD by 25% AND reduce CORE_UTILIZATION by 10% AND set SETUP_SLACK_MARGIN to 0.2. Apply the full bundle atomically.
- Never adjust SETUP_SLACK_MARGIN without also adjusting HOLD_SLACK_MARGIN.
- For QoR optimization rounds, change at most ONE bundle per iteration and track the direction of change for each metric. If a metric oscillates (improves then worsens then improves), stop optimizing that axis.
- The ORFS-agent paper uses 375-600 iterations with 25 parallel runs to converge. ChipAgent's 3-attempt retry is orders of magnitude less. Do not expect convergence -- aim for "best of N" selection instead.
- Keep a history of all (config, metrics) pairs and select the Pareto-best result at the end, rather than always using the last iteration.

**Phase:** Error diagnosis phase must define the bundles. Retry logic must enforce bundle-based adjustment.

---

### Pitfall 3: Retry Loop Without a Convergence Guard Runs Forever (or Until Token Limit)

**What goes wrong:** The skill instructs Claude to retry on failure. Claude, being a language model, follows instructions literally. If the retry condition is "retry if WNS < 0" and the parameter adjustment is insufficient (e.g., 10% clock relaxation on a design with -5ns WNS), every retry fails, and the loop continues until Claude hits its output token limit or the user kills the session. Unlike the v1.0 lint fix loop (capped at 3 attempts), PnR retry has no built-in cap in the current skill.

**Why it happens:** The v1.1.2 skill had "50% clock period increase per retry" with a vague mention of maximum attempts. The v1.2.0 task adds multi-round QoR optimization, which is inherently open-ended. Without explicit bounds, the skill's natural language instructions let Claude decide how many rounds are "enough" -- and Claude tends to keep trying.

**Consequences:** Multi-hour sessions that produce 10+ ORFS runs. Each full ORFS flow takes 2-10 minutes on sky130hd. 10 retries = 20-100 minutes of compute. Token usage explodes. The user sees an endlessly scrolling conversation with no conclusion.

**Prevention:**
- Hard cap: MAX_RETRY_ATTEMPTS = 3 for error recovery, MAX_QOR_ROUNDS = 3 for optimization. Write these as literal numbers in the SKILL.md, not as "a few attempts."
- Each retry must check: did the target metric IMPROVE compared to the previous attempt? If not, stop immediately -- the parameter adjustment direction is wrong.
- Define a "good enough" threshold: if WNS >= -0.1ns, accept it as timing MET (within tool noise). If DRC violations <= 2, accept as clean. Do not chase perfection.
- The skill must track attempt count as an explicit variable that increments, not rely on Claude's memory of how many times it has retried.
- For QoR optimization: require a minimum improvement delta (e.g., 5% better area or 0.5ns better WNS) to justify another round. If improvement is below threshold, stop.

**Detection:** Conversation exceeds 10 tool calls for a single PnR run. Same error message repeats across iterations. Clock period has been relaxed more than 4x from the original value.

**Phase:** Retry loop implementation. Must be the FIRST thing defined before any retry logic.

---

### Pitfall 4: Error Type Misdiagnosis Due to Fragile Log Parsing

**What goes wrong:** The error diagnosis system must classify failures into types (timing violation, routing congestion, DRC, synthesis failure). The classification depends on parsing ORFS stdout/stderr and report files. ORFS output format is not stable across versions -- OpenROAD regularly changes log message wording, report table formats, and error codes. A regex that works on ORFS v2024 may break on v2025.

**Specific fragility examples:**

| What to detect | Fragile approach | What breaks |
|----------------|-----------------|-------------|
| Timing violation | Grep for "VIOLATED" in stdout | OpenROAD also prints "slack (VIOLATED)" for hold paths that are expected to fail pre-CTS |
| Routing congestion | Parse "overflow" count from GRT log | ORFS moved overflow reporting between log files across versions |
| DRC violations | Count "violation type:" in 5_route_drc.rpt | Format changed to "Violation:" in some builds |
| Synthesis failure | Check for "Error" in yosys stderr | Yosys prints "Warning" for recoverable errors and "Error" for different severity levels |
| CTS failure | Parse CTS log for skew values | CTS log format differs between TritonCTS versions |

**Additionally:** The current `get-report.ts` parsers use regex patterns like `/report_tns\n-+\ntns max ([\d.-]+)/` which depend on exact whitespace and line break patterns. If ORFS adds a blank line or changes "tns max" to "TNS max", the parser returns null and the error diagnosis gets no data to work with.

**Consequences:** Timing violation misdiagnosed as congestion -> wrong parameter adjustment (reduce density instead of relaxing clock) -> wasted retry. Synthesis failure misdiagnosed as PnR failure -> retry re-runs PnR when the RTL needs to change. Silent diagnosis failure (returns "unknown error") -> generic retry strategy that does not help.

**Prevention:**
- Use MULTIPLE signals for each error type, not a single regex. Timing violation = (WNS < 0 in parsed report) OR ("VIOLATED" in finish stage stdout) OR (TNS < 0 in parsed report). Require at least 2 signals to agree.
- Parse structured data when available: ORFS generates `metadata.json` at flow completion with machine-readable metrics. Use this as the primary source, with log parsing as fallback.
- For the existing `get-report.ts` parsers: add fallback patterns. If the primary regex fails, try a broader match. Return confidence level with each parsed value (exact match vs fuzzy match vs not found).
- Add version detection: read ORFS version at startup and select parser patterns accordingly.
- Test parsers against ACTUAL report files from the local ORFS installation, not against hardcoded fixtures from documentation examples. The fixtures should be generated by running ORFS, not hand-written.

**Detection:** Error diagnosis returns "unknown" for a failure that has clear error messages in the log. Parsed metric values are null when the report file clearly contains data (visible by reading the raw file).

**Phase:** Error diagnosis implementation. Parsers must be robust before retry logic depends on them.

---

### Pitfall 5: Regenerating config.mk Without Updating SDC Creates Inconsistent State

**What goes wrong:** When retrying with a different CLOCK_PERIOD, the system must update BOTH config.mk AND constraint.sdc. The current `generate_config` MCP tool generates both files together, but a naive retry implementation might only regenerate config.mk (since that is where ORFS variables live) and forget that the clock period is defined in the SDC file, not in config.mk. ORFS reads the clock period from the SDC file via the synthesis step, not from a config.mk variable.

**Why it happens:** In ORFS, `CLOCK_PERIOD` is not a standard config.mk variable. The clock constraint is in the SDC file (`create_clock -period <ns>`). Some ORFS designs define `_SDC_CLK_PERIOD` in config.mk which is then substituted into the SDC template, but ChipAgent's `generate-config.ts` writes the period directly into constraint.sdc. A retry that only changes config.mk leaves the SDC untouched.

**Consequences:** The retry claims to use a 15ns clock period but the SDC still says 10ns. Synthesis optimizes for 10ns (the old constraint). Timing analysis uses 10ns. The retry is identical to the original run. This compounds with Pitfall 1 (stale cache) -- the stale results look correct because the SDC never changed.

**Prevention:**
- The retry mechanism must call `generate_config` MCP tool with the new clock period, which regenerates BOTH config.mk and constraint.sdc.
- Never manually edit config.mk for retry -- always go through the `generate_config` tool to ensure consistency.
- After regeneration, validate: read both files and verify the clock period appears correctly in the SDC `create_clock` line AND that config.mk's SDC_FILE path points to the freshly written file.
- Add the clock period as a field in config.mk as a comment for debugging: `# CLOCK_PERIOD_NS = 15.0 (for reference only, actual constraint in SDC)`

**Detection:** Timing report shows a different clock period than what the retry intended. SDC file has an older timestamp than config.mk.

**Phase:** Retry logic implementation. Must regenerate both files atomically.

---

## Moderate Pitfalls

### Pitfall 6: QoR Comparison Table Compares Apples to Oranges If Design Changes

**What goes wrong:** The multi-round QoR optimization should compare different PnR configurations of the SAME design. But if the user modifies the RTL between rounds (e.g., fixes a Chisel module and re-runs workflow then pnr), the comparison table may include results from the old RTL alongside the new RTL. The metrics are not comparable because the design changed.

**Prevention:**
- Each QoR comparison session must record a "design fingerprint" -- hash of the input Verilog file. If the hash changes between rounds, start a new comparison table.
- Store the comparison data in a structured file (e.g., `MyDesign/<Module>/workspace/pnr/qor_history.json`) rather than relying on conversation context, which is lost between sessions.
- Include the Verilog hash in each comparison row so it is visible if designs differ.

**Detection:** Cell count varies wildly between comparison rows (suggesting different RTL, not just different PnR params). Verilog file modification time is more recent than the first comparison run.

**Phase:** QoR comparison implementation.

---

### Pitfall 7: Adjusting PLACE_DENSITY Outside Valid Range Crashes OpenROAD

**What goes wrong:** PLACE_DENSITY must be between 0.0 and 1.0 (exclusive of extremes). Too low (< 0.3 for sky130hd) and the placer cannot find legal positions for all cells. Too high (> 0.95) and the placer runs for hours or segfaults. The retry logic might blindly increase or decrease density by a fixed delta without bounds checking.

**Specific ranges for sky130hd:**
- Minimum practical: ~0.30 (below this, cells cannot be placed due to site constraints)
- Default: 0.60 (from sky130hd platform config.mk)
- Maximum practical: ~0.85 (above this, placement timeouts are likely)
- Hard limits: 0.0 < PLACE_DENSITY < 1.0

Similarly for CORE_UTILIZATION:
- Minimum practical: ~20% (wastes die area but always works)
- Default: 40% (from sky130hd GCD example)
- Maximum practical: ~70% (above this, routing congestion becomes severe on 5-metal-layer sky130hd)
- Hard limits: 0 < CORE_UTILIZATION < 100

**Consequences:** OpenROAD crashes with segfault (no useful error message). Or placement runs for 30+ minutes until the MCP timeout kills it. The retry loop wastes an entire iteration on a known-bad parameter.

**Prevention:**
- Define hard bounds for every tunable parameter. Clamp values before writing to config.mk:
  ```
  PLACE_DENSITY: [0.30, 0.85]
  CORE_UTILIZATION: [20, 70]
  CLOCK_PERIOD: [1.0, 100.0]  # nanoseconds
  SETUP_SLACK_MARGIN: [-1.0, 2.0]
  HOLD_SLACK_MARGIN: [-1.0, 2.0]
  ```
- The `generate_config` MCP tool should validate parameter ranges and reject out-of-range values with a clear error.
- Log the clamped value if it differs from the requested value so the retry logic knows it hit a bound.

**Detection:** OpenROAD segfault in placement. Placement takes >10 minutes (timeout). Error "Cannot place all cells" from global placement.

**Phase:** Parameter adjustment logic. Bounds checking must be in the `generate_config` tool.

---

### Pitfall 8: Error Diagnosis Confuses CTS-Stage Timing With Final Timing

**What goes wrong:** The PnR flow reports WNS/TNS at every stage (floorplan, place, CTS, route, finish). These are increasingly accurate estimates. The floorplan WNS might be -2.0ns (based on estimated wire delays) but the final WNS after routing might be -0.1ns (after optimization). If the retry logic checks WNS after the PLACE stage and triggers a clock relaxation, it may relax a constraint that would have been met after route optimization.

**Why it happens:** OpenROAD performs timing repair at multiple stages: after placement (`repair_timing`), after CTS (`repair_timing` again), and during routing (`repair_timing` with real parasitics). Each repair can significantly improve timing. Early-stage WNS is pessimistic.

**ORFS-agent research confirms this:** they use CTS-stage metrics as "surrogates" for final metrics but note that "routed wirelength may not always be available" and CTS metrics are only correlated, not identical, to final metrics.

**Consequences:** Unnecessary clock relaxation, leading to worse QoR (slower design than needed). The QoR optimization then tries to tighten the clock back, wasting iterations.

**Prevention:**
- Only diagnose timing violations from the FINISH stage report, never from intermediate stages.
- Use intermediate stage WNS as informational only (display to user) but never as a retry trigger.
- If a stage fails (non-zero exit code), that IS a valid retry trigger regardless of which stage it is. But metric-based retry decisions should only use final metrics.
- Exception: if routing FAILS (DRC violations prevent completion), use route-stage metrics for diagnosis since finish-stage metrics are unavailable.

**Detection:** Retry triggers after place stage despite the design likely meeting timing after routing. Clock period is relaxed to a value much larger than necessary.

**Phase:** Error diagnosis logic. Must only trigger on finish-stage metrics.

---

### Pitfall 9: Congestion Diagnosis Requires Global Route Overflow, Not Just DRC Count

**What goes wrong:** Routing congestion and DRC violations are related but distinct failure modes. The error diagnosis might classify all routing failures as "DRC" when the root cause is congestion. The fix for DRC (usually: re-route or reduce via count) is different from the fix for congestion (reduce PLACE_DENSITY or CORE_UTILIZATION to free routing resources).

**How to distinguish:**
| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| DRC violations = 0 but WNS < 0 | Timing, not routing | Relax clock or optimize placement |
| DRC violations > 0, all "short" type | Routing congestion | Reduce PLACE_DENSITY, reduce CORE_UTILIZATION |
| DRC violations > 0, "spacing" type | Local congestion or antenna | Reduce density in congested region (hard to automate) |
| Global route overflow > 0 | Congestion before detail route | Reduce CORE_UTILIZATION or increase die area |
| make route returns non-zero | Could be congestion OR timeout | Check if overflow > 0 in GRT log |

**Consequences:** Treating congestion as timing (relaxing clock) does not help. Treating timing as congestion (reducing density) worsens timing. The retry wastes an attempt on the wrong fix.

**Prevention:**
- Parse global route overflow from the GRT log (not just the DRC report). The log contains lines like `[INFO GRT-0018] Total overflow: N` where N > 0 indicates congestion.
- Add a new parser to `get-report.ts` for the route stage that extracts overflow count from `5_route.log` (in addition to DRC from `5_route_drc.rpt`).
- Classification hierarchy:
  1. Exit code non-zero on synthesis -> "synthesis_failure" (no retry in PnR)
  2. Exit code non-zero on route + overflow > 0 -> "congestion" (reduce density/utilization)
  3. Finish stage WNS < 0 -> "timing_violation" (relax clock, adjust margins)
  4. Finish stage DRC > 0 -> "drc_violation" (re-route, reduce density)
  5. Any other failure -> "unknown" (report to user, do not auto-retry)

**Phase:** Error diagnosis implementation. Must parse both DRC report and route log.

---

### Pitfall 10: MCP Tool Response Size Explodes With Multi-Round History

**What goes wrong:** The current `run_stage` tool returns the last 500 lines of stdout and stderr. Over 3 retry rounds x 6 stages, that is 18 tool calls, each returning potentially large text blobs. Claude's context window fills with ORFS log output, leaving less room for reasoning about the QoR comparison. Additionally, the QoR history (all configs and metrics from all rounds) grows linearly.

**Consequences:** Claude starts truncating its reasoning. The comparison table becomes incomplete because earlier rounds' data falls out of the context window. In the worst case, Claude "forgets" the best configuration from round 1 and continues optimizing from a worse round 3 baseline.

**Prevention:**
- The `run_stage` tool should return only a SUMMARY (success/fail, exit code, key error lines) not full stdout. Reduce from 500 lines to 20 lines of stderr on failure, 5 lines on success.
- Store QoR history in a file (`qor_history.json`), not in conversation context. The comparison step reads this file, not conversation memory.
- Add a dedicated MCP tool: `get_qor_history` that returns the structured comparison data.
- The skill should explicitly instruct Claude to NOT include full ORFS log output in its responses -- only extracted metrics.

**Phase:** MCP tool design (reduce response size) + QoR comparison design (file-based history).

---

## Minor Pitfalls

### Pitfall 11: Combinational Modules Have No Clock -- "Timing Violation" Retry Is Meaningless

**What goes wrong:** Combinational modules (no `always @(posedge)`) use a virtual clock with `set_max_delay`. The virtual clock's "timing violation" means the combinational path delay exceeds the virtual period. The fix is NOT to relax the clock (that just hides the issue) but to optimize the combinational logic. However, the retry logic treats all timing violations the same.

**Prevention:**
- Detect sequential vs combinational from the SDC (presence of `create_clock ... [get_ports ...]` vs `create_clock -name virtual_clk`). The `generate-config.ts` already has `isSequential()` detection.
- For combinational timing violations: report to user that the design's critical path is too long, suggest RTL optimization. Do NOT auto-retry with relaxed virtual clock.
- For sequential timing violations: auto-retry with relaxed clock period is appropriate.
- Add the `is_sequential` flag to the QoR history so the comparison table can note when a virtual clock was used.

**Phase:** Error diagnosis logic. Must distinguish sequential from combinational before choosing retry strategy.

---

### Pitfall 12: Multiple Config Rounds Overwrite Each Other's config.mk

**What goes wrong:** Each retry calls `generate_config` which writes config.mk to the same path (`MyDesign/<Module>/workspace/pnr/config.mk`). The previous round's config is overwritten. If the user wants to reproduce a specific configuration later, or if the QoR comparison needs to record what parameters each round used, the data is lost.

**Prevention:**
- Before overwriting config.mk, copy the current version to `config.mk.round_N` (where N is the round number).
- Or: write each round's config to `config_round_1.mk`, `config_round_2.mk`, etc., and pass the round-specific path to `run_stage`.
- The simpler approach: log the config parameters in the `qor_history.json` file before regenerating. The actual config.mk file can be overwritten since the history captures the values.

**Phase:** Retry logic implementation.

---

### Pitfall 13: ORFS `make` Holds File Locks During Execution -- Parallel Retries Corrupt State

**What goes wrong:** If a retry is triggered while a previous ORFS `make` is still running (e.g., due to a race condition or timeout mishandling), both Make processes try to write to the same result files. This corrupts the output and may produce unreadable `.odb` files.

**Prevention:**
- The MCP `run_stage` tool must ensure sequential execution: never start a new `make` until the previous one completes or is killed.
- Add a file-based lock (`/tmp/chipagent_orfs.lock`) that the MCP server acquires before any `make` call and releases after.
- The current `run_stage` implementation waits for process completion (`.on('close', ...)`) which is correct, but the skill-level retry must also wait for the full tool response before starting the next round.
- If timeout kills a `make` process, clean ALL results before the next attempt (corrupted `.odb` files cause cryptic failures).

**Phase:** Retry loop implementation. Sequential execution is already handled by the MCP tool's blocking design, but the skill must not try to parallelize retries.

---

## Integration Pitfalls (Unique to Adding These Features to the Existing MCP Server)

### Integration Pitfall 1: Existing `run_stage` Has No `clean_first` Support

**What goes wrong:** The current `run_stage` tool in `mcp-server/tools/run-stage.ts` calls `make <stage>` directly. It has no mechanism to run `make clean_<stage>` or `make clean_all` before execution. Adding retry logic in the skill WITHOUT adding clean support to the MCP server means every retry runs against stale cached results (see Pitfall 1).

**Current code (from run-stage.ts line 9-19):**
```typescript
export function buildMakeArgs(stage, configMkPath, orfsFlowPath) {
  return {
    args: [stage],  // Just the stage target, no clean
    cwd: orfsFlowPath,
    env: { ...process.env, DESIGN_CONFIG: configMkPath },
  };
}
```

**Prevention:**
- Option A: Add a `clean_first: boolean` parameter to `run_stage`. When true, prepend `clean_all` to the make args: `args: ["clean_all", stage]`.
- Option B: Add a separate `clean_design` MCP tool that calls `make clean_all DESIGN_CONFIG=<path>`.
- Option C: The skill calls `run_stage` with stage `"clean_all"` before each retry round. This works because `clean_all` is a valid Make target, and the current `VALID_STAGES` validation would need to include it.
- Recommendation: Option B (separate tool) is cleanest. It keeps the interface explicit and avoids ambiguity about what `clean_first` means (clean this stage? all stages? just downstream stages?).

**Phase:** FIRST task of the retry implementation. Must be done before any retry logic is written.

---

### Integration Pitfall 2: `get_report` Parsers May Return Null for Valid Reports

**What goes wrong:** The existing parsers in `get-report.ts` use specific regex patterns. If the report file format varies slightly (extra whitespace, different section ordering), the parser returns null for a metric that is actually present. The error diagnosis system interprets null as "metric not available" and makes a wrong diagnosis.

**Current parser fragility examples:**
- `parseFinishReport`: Expects `report_tns\n-+\ntns max ([\d.-]+)` -- breaks if there is a blank line between the header and the value, or if ORFS changes "tns max" capitalization.
- `parseDrcReport`: Counts occurrences of `violation type:` (lowercase) -- breaks if ORFS capitalizes to `Violation Type:`.
- `parseRouteArea`: Expects `Design area (\d+) um^2 (\d+)% utilization` -- breaks if area is reported as float (e.g., `1234.5 um^2`).

**Consequences:** Error diagnosis receives incomplete data. Timing violation goes undetected because WNS parsing failed. The system reports "no issues found" when there are issues.

**Prevention:**
- Add fallback parsers: if primary regex fails, try a broader/looser pattern.
- Return confidence level with each metric: `{ value: -0.5, confidence: "high" }` for exact match, `{ value: null, confidence: "not_found" }` for parse failure.
- Test ALL parsers against ACTUAL report files from a real sky130hd ORFS run, not hand-crafted fixtures.
- Add `metadata.json` parsing as a backup source. ORFS generates this file at flow completion with machine-readable metrics.

**Phase:** Before error diagnosis depends on parsed metrics. May need parser hardening as a prerequisite task.

---

### Integration Pitfall 3: Skill SKILL.md Grows Too Complex for Claude to Follow Reliably

**What goes wrong:** The current PnR SKILL.md is already 160 lines with 5 steps. Adding error diagnosis (classify error type from metrics and logs), retry logic (adjust parameters based on error type, regenerate config, clean, re-run), and QoR comparison (track history, format comparison table, select best config) could push it to 400+ lines. Claude's ability to follow multi-step procedures degrades with instruction length -- it may skip steps, confuse retry round numbering, or forget to clean before retry.

**Consequences:** Claude follows steps 1-3 correctly but skips the clean step in the retry loop. Or Claude formats the QoR comparison table but forgets to include all rounds. The skill appears to work in simple cases but fails in complex retry scenarios.

**Prevention:**
- Split the skill into sub-skills or delegate to agents:
  - `skills/pnr/SKILL.md` -- main orchestration (unchanged from v1.1.5)
  - `agents/pnr-error-diagnosis.md` -- classifies error type from metrics
  - `agents/pnr-retry-strategy.md` -- decides parameter adjustments based on error type
  - `agents/pnr-qor-comparison.md` -- formats comparison table from history
- The main skill calls agents for complex decisions, keeping the flow simple: run -> check -> if fail, diagnose -> get retry params -> clean -> re-run -> compare.
- Each agent's instructions should be under 100 lines.
- Use structured data (JSON) for inter-agent communication, not conversation context.

**Phase:** Architecture decision before implementation. Must be decided in the first planning task.

---

### Integration Pitfall 4: QoR History Must Survive Across Claude Sessions

**What goes wrong:** The user runs `/chip-agent:pnr ALU8`, gets round 1 results, then the Claude session ends (timeout, crash, new window). They start a new session and run `/chip-agent:pnr ALU8` again. Without persistent QoR history, round 2 starts from scratch with no knowledge of round 1's results. The comparison table only shows round 2.

**Prevention:**
- Write QoR history to a file: `MyDesign/<Module>/workspace/pnr/qor_history.json`
- Structure: `[{ round: 1, config: { clock_period: 10, density: 0.6, ... }, metrics: { wns: -0.5, area: 1234, ... }, timestamp: "..." }, ...]`
- On each PnR run, read existing history, append new round, write back.
- The comparison table reads from this file, not from conversation memory.
- Add a `--fresh` flag (or equivalent) to clear history when the user wants to start over.

**Phase:** QoR comparison implementation.

---

## Phase-Specific Warning Summary

| Phase Topic | Likely Pitfall | Severity | Mitigation |
|-------------|---------------|----------|------------|
| MCP clean support | P1 (stale cache), IP1 (no clean tool) | CRITICAL | Add clean_design MCP tool before any retry logic |
| Error diagnosis | P4 (fragile parsing), P8 (wrong stage metrics), P9 (congestion vs DRC), P11 (combinational) | HIGH | Multi-signal classification, finish-stage only triggers |
| Parameter retry | P2 (interactions), P3 (infinite loop), P5 (config/SDC inconsistency), P7 (range bounds) | HIGH | Bundle-based adjustment, hard caps, generate_config for both files |
| QoR comparison | P6 (design change), P10 (context explosion), P12 (config overwrite), IP4 (session persistence) | MODERATE | File-based history, design fingerprint, compact tool responses |
| Skill architecture | IP3 (skill complexity) | MODERATE | Split into sub-skills/agents |

---

## Sources

### Primary (HIGH confidence)
- `mcp-server/tools/run-stage.ts` -- verified: no clean support, `buildMakeArgs` only includes stage target (line 9-19)
- `mcp-server/tools/get-report.ts` -- verified: parser regex patterns, null return on parse failure (lines 6-55)
- `mcp-server/tools/generate-config.ts` -- verified: generates both config.mk and SDC, isSequential detection (lines 27-66)
- `skills/pnr/SKILL.md` -- verified: 5-step pipeline, no retry logic, no clean support (176 lines)
- `.planning/PROJECT.md` -- verified: v1.2.0 requirements (error diagnosis, parameter retry, QoR optimization)
- `task2.md` -- verified: grading criteria for retry and QoR features
- [ORFS Flow Variables](https://openroad-flow-scripts.readthedocs.io/en/latest/user/FlowVariables.html) -- PLACE_DENSITY, CORE_UTILIZATION, SETUP_SLACK_MARGIN definitions
- [ORFS FlowTutorial](https://openroad-flow-scripts.readthedocs.io/en/latest/tutorials/FlowTutorial.html) -- clean targets: `clean_synth`, `clean_floorplan`, `clean_all`
- [ORFS Walkthrough](https://vlsida.github.io/chip-tutorials/orfs-walkthrough.html) -- stale result behavior confirmed
- [OpenROAD Placement docs](https://openroad.readthedocs.io/en/latest/main/src/gpl/README.html) -- density/timing/congestion tradeoffs

### Secondary (MEDIUM confidence)
- [ORFS-agent paper (arXiv:2506.08332)](https://arxiv.org/abs/2506.08332) -- parameter tuning iterations (375-600 runs), CTS surrogates, timeout failure modes
- [ORFS-agent MLCAD slides](https://vlsicad.ucsd.edu/Publications/Conferences/417/c417_slides.pdf) -- parameter interaction evidence
- [OpenROAD Global Placement DeepWiki](https://deepwiki.com/The-OpenROAD-Project/OpenROAD/4.2.1-global-placement) -- density-timing-congestion gradient tradeoff
- [Tackling Congestion (Design-Reuse)](https://www.design-reuse.com/articles/54881/tackling-congestion-and-shorts-with-practical-approaches-and-pnr-tool-icc2.html) -- setup/hold interaction in retry

### Codebase (HIGH confidence)
- Previous v1.1.5 PITFALLS.md (Pitfall 16: ORFS make clean required between config changes) -- confirmed and expanded here
- `.planning/phases/15-pnr-skill-orchestration-ppa-reporting/15-RESEARCH.md` -- existing parser patterns, ORFS output paths

---
*Domain pitfalls for: ChipAgent v1.2.0 -- Smart Retry & QoR Optimization*
*Researched: 2026-04-02*
*Complements v1.1.5 PITFALLS.md (Docker, MCP protocol, sky130hd PDK pitfalls remain valid)*
