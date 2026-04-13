---
phase: 4-qor-pnr
plan: 1
type: execute
wave: 1
depends_on: []
files_modified:
  - skills/pnr/SKILL.md
  - mcp-server/tools/compare-runs.ts
  - mcp-server/tests/compare-runs.test.ts
autonomous: true
requirements:
  - QOR-01
  - QOR-02
  - QOR-03

must_haves:
  truths:
    - "SKILL.md Step 3 explicitly forbids early exit and requires all rounds to complete"
    - "SKILL.md Step 2 initializes only baseline round; Steps 3/2.5 dynamically append rounds based on synth cell_count"
    - "compare_runs recommendBest sorts by clock_period_ns > area > total_power_w"
  artifacts:
    - path: "skills/pnr/SKILL.md"
      provides: "PnR pipeline definition with mandatory multi-round QoR comparison"
      contains: "MANDATORY"
    - path: "mcp-server/tools/compare-runs.ts"
      provides: "QoR recommendation with power tiebreaker"
      contains: "total_power_w"
    - path: "mcp-server/tests/compare-runs.test.ts"
      provides: "Test coverage for power-aware recommendation"
      min_lines: 190
  key_links:
    - from: "skills/pnr/SKILL.md"
      to: "mcp-server/tools/compare-runs.ts"
      via: "compare_runs recommend action"
      pattern: "compare_runs.*recommend"
    - from: "mcp-server/tools/compare-runs.ts"
      to: "mcp-server/tests/compare-runs.test.ts"
      via: "unit tests"
      pattern: "recommendBest"
---

<objective>
Modify SKILL.md and compare-runs.ts to implement mandatory multi-round QoR comparison with dynamic parameter generation and power-aware recommendation.

Purpose: Force all QoR rounds to complete (no early exit on first pass), dynamically expand rounds based on design complexity, and add power as a tertiary ranking metric.
Output: Updated SKILL.md pipeline, updated compare-runs.ts with power sorting, updated tests.
</objective>

<execution_context>
@/home/mingzhenjia/.claude/get-shit-done/workflows/execute-plan.md
@/home/mingzhenjia/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/quick/4-qor-pnr/4-CONTEXT.md

<interfaces>
<!-- Key types executor needs from compare-runs.ts -->

From mcp-server/tools/compare-runs.ts:
```typescript
export interface QorRun {
  readonly round: number;
  readonly config: Record<string, unknown>;
  readonly metrics: Record<string, unknown>;
  readonly status: "pass" | "fail";
  readonly error_type?: string;
  readonly timestamp: string;
}

export function recommendBest(runs: readonly QorRun[]): QorRun | null;
```

Existing `recommendBest` sort: clock_period_ns (asc) -> area (asc).
New sort: clock_period_ns (asc) -> area (asc) -> total_power_w (asc).
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Add power tiebreaker to recommendBest and update tests</name>
  <files>mcp-server/tools/compare-runs.ts, mcp-server/tests/compare-runs.test.ts</files>
  <behavior>
    - Existing tests must continue to pass (clock > area still primary/secondary sort)
    - Test: when clock and area are equal, lower total_power_w wins
    - Test: when total_power_w is undefined/null, treat as Infinity (runs with power data win over runs without)
    - Test: when all three metrics are equal for two runs, first in list wins (stable sort)
  </behavior>
  <action>
    **Tests first (RED):**

    Add 3 new test cases to the existing `recommendBest` describe block in `mcp-server/tests/compare-runs.test.ts`:

    1. "breaks area ties by lowest total_power_w" -- two runs with same clock_period_ns and same area, different total_power_w. Assert lower power run wins.

    2. "treats missing total_power_w as Infinity" -- one run with total_power_w defined, one without. Assert the one with power data wins.

    3. "clock_period_ns still takes priority over area and power" -- existing behavior confirmation: run with lower clock but higher area and power should still win.

    Run tests to confirm they fail: `cd /home/mingzhenjia/ChipAgent/mcp-server && npx tsx --test tests/compare-runs.test.ts`

    **Implementation (GREEN):**

    In `mcp-server/tools/compare-runs.ts`, update the `recommendBest` function's sort comparator. After the existing area comparison (`areaA - areaB`), add a third comparison:

    ```typescript
    const powerA = (a.metrics.total_power_w as number | undefined) ?? Infinity;
    const powerB = (b.metrics.total_power_w as number | undefined) ?? Infinity;
    return powerA - powerB;
    ```

    This makes the sort: clock_period_ns (asc) -> area (asc) -> total_power_w (asc). Missing power values are treated as Infinity so runs with actual power data are preferred.

    Also update the `recommend` case in `registerCompareRuns` to include power in the success message. Change the message template to include power:
    `Best run: round ${best.round} (clock=${best.config.clock_period_ns}ns, WNS=${best.metrics.wns}ns, area=${best.metrics.area}, power=${best.metrics.total_power_w ?? 'N/A'}W)`

    Run tests to confirm all pass: `cd /home/mingzhenjia/ChipAgent/mcp-server && npx tsx --test tests/compare-runs.test.ts`
  </action>
  <verify>
    <automated>cd /home/mingzhenjia/ChipAgent/mcp-server && npx tsx --test tests/compare-runs.test.ts</automated>
  </verify>
  <done>All recommendBest tests pass, including new power tiebreaker tests. Sort order is clock_period_ns > area > total_power_w.</done>
</task>

<task type="auto">
  <name>Task 2: Update SKILL.md with mandatory rounds, dynamic params, and progress indicators</name>
  <files>skills/pnr/SKILL.md</files>
  <action>
    Make the following targeted edits to `skills/pnr/SKILL.md`:

    **Edit A -- Step 2: Replace static round_plans with baseline-only initialization.**

    In Step 2, item 4 ("Initialize comparison state"), replace the `round_plans` definition. Remove the three hardcoded round plans and instead define only:

    ```
    - `round_plans` =
      1. Round 1 baseline: `{ clock_period_ns: <from spec.json or 10>, core_utilization: 40 }`
    ```

    Change `comparison_round_count` from `3` to the comment: `// will be determined dynamically after synth in Step 3`

    Add a new variable: `synth_cell_count` = `null` (populated after Round 1 synth completes)

    **Edit B -- Step 3: Add MANDATORY rule and dynamic round generation.**

    At the very beginning of Step 3 (before "For each round_plan in round_plans"), add a prominent MANDATORY rule block:

    ```
    **MANDATORY: All rounds must run to completion.** Do NOT skip remaining rounds even if an earlier round passes. Every round's result is needed for QoR comparison.
    ```

    Inside the round loop, after the synth stage completes in step 6a (after calling get_report for synth), add logic to capture `synth_cell_count` from the synth report's `cell_count`. Then after Round 1 completes (when `round == 1` and before proceeding to round 2), add a "Dynamic round expansion" sub-step:

    ```
    After Round 1 finishes (pass or exhausts retries), if `round_plans` has only 1 entry, expand based on `synth_cell_count`:

    - Round 2: `{ clock_period_ns: max(1, <baseline clock> * 0.8), core_utilization: 40, gpl_timing_driven: true }`
    - Round 3: `{ clock_period_ns: max(1, <baseline clock> * 0.8), core_utilization: 35, gpl_timing_driven: true, gpl_routability_driven: true }`
    - If `synth_cell_count > 1000`:
      - Round 4: `{ clock_period_ns: max(1, <baseline clock> * 0.8), core_utilization: 35, place_density: 0.55, gpl_routability_driven: true }`
      - Round 5: `{ clock_period_ns: max(1, <baseline clock> * 0.7), core_utilization: 30, gpl_timing_driven: true }`

    Set `comparison_round_count` to the total number of rounds (3 or 5).
    ```

    Note: Use `baseline clock * 0.8` (20% tighter) rather than `baseline clock - 2` to handle arbitrary clock periods proportionally. Use `max(1, ...)` as floor.

    **Edit C -- Step 3: Add round progress indicator.**

    In step 6e, update the pass/fail messages to include total round count:

    - Change `"Round {round} PASSED. Keeping result for QoR comparison."` to `"Round {round}/{comparison_round_count} completed (PASSED). {comparison_round_count - round} rounds remaining."`
    - Change `"Round {round} exhausted retries..."` to `"Round {round}/{comparison_round_count} completed (FAILED, retries exhausted). {comparison_round_count - round} rounds remaining."`
    - Similarly update the critical severity message in step 6g to include round count.

    **Edit D -- Anti-Patterns: Add mandatory rounds anti-pattern.**

    Add to the Anti-Patterns section:

    ```
    - DO NOT skip remaining rounds when an earlier round passes -- all results feed the QoR comparison table
    ```

    **Edit E -- Step 4b: Update comparison table to show power.**

    The comparison table already has Power column -- no change needed there. But verify the column is present.

    **Edit F -- Step 4c: Update recommendation display to include power.**

    Change the recommendation display line from:
    `"Recommendation: Round {N} (clock={X}ns, WNS={Y}ns, area={Z}um2)"`
    to:
    `"Recommendation: Round {N} (clock={X}ns, WNS={Y}ns, area={Z}um2, power={P}uW)"`

    where `{P}` = `best.metrics.total_power_w * 1e6` or `"N/A"` if unavailable.
  </action>
  <verify>
    <automated>grep -c "MANDATORY" /home/mingzhenjia/ChipAgent/skills/pnr/SKILL.md && grep -c "synth_cell_count" /home/mingzhenjia/ChipAgent/skills/pnr/SKILL.md && grep -c "total_power_w" /home/mingzhenjia/ChipAgent/skills/pnr/SKILL.md && echo "All checks passed"</automated>
  </verify>
  <done>SKILL.md has: (1) MANDATORY rule forbidding early exit, (2) baseline-only initialization in Step 2 with dynamic expansion in Step 3 based on synth cell_count, (3) round progress indicators showing X/N, (4) anti-pattern against skipping rounds, (5) power in recommendation display. Minimum 3 rounds, up to 5 for large designs.</done>
</task>

</tasks>

<verification>
1. `cd /home/mingzhenjia/ChipAgent/mcp-server && npx tsx --test tests/compare-runs.test.ts` -- all tests pass including new power tiebreaker tests
2. `grep "MANDATORY" /home/mingzhenjia/ChipAgent/skills/pnr/SKILL.md` -- present
3. `grep "synth_cell_count" /home/mingzhenjia/ChipAgent/skills/pnr/SKILL.md` -- present (dynamic round expansion)
4. `grep "rounds remaining" /home/mingzhenjia/ChipAgent/skills/pnr/SKILL.md` -- present (progress indicators)
5. `grep "total_power_w" /home/mingzhenjia/ChipAgent/mcp-server/tools/compare-runs.ts` -- present (power sorting)
</verification>

<success_criteria>
- recommendBest sorts by clock_period_ns > area > total_power_w with tests proving all three levels
- SKILL.md Step 2 initializes only baseline; Step 3 dynamically expands to 3-5 rounds based on cell_count
- SKILL.md Step 3 has MANDATORY rule and round progress indicators (X/N format)
- Anti-patterns section forbids skipping rounds
- All existing tests continue to pass
</success_criteria>

<output>
After completion, create `.planning/quick/4-qor-pnr/4-SUMMARY.md`
</output>
