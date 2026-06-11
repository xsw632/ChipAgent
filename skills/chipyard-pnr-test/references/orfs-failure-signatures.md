# ORFS Failure Signatures for Chipyard All-Mock PnR

Use this reference after a failed round or a DRC/timing-dirty round. Match the
first strong signal, then choose a small parameter change.

Signal names below refer to `get_stage_metrics` output (`signals.*`,
`congestion.*`, `critical_path.*`) and `diagnose_failure` error types.

## Triage Order

1. Identify the failed or dirty stage: synth, floorplan, place, CTS, route, finish.
2. Check whether All-Mock variables are present if synth memory/OOM behavior appears.
3. Check `signals.drc_errors` before comparing final QoR.
4. Check `signals.setup_ws` / `signals.setup_tns` after route/finish.
5. Run `diagnose_failure` with `stage_metrics` and `congestion` — its `error_type` maps directly to the sections below.
6. Change only the knobs tied to the dominant failure.

## Synthesis Failures

### OOM, timeout, or very slow Yosys

Likely causes:

- Memories were expanded instead of mocked.
- Hierarchy was flattened too aggressively.
- Clock/repair target caused excessive optimization.

Check:

- `SYNTH_MEMORY_MAX_BITS = 1`
- `SYNTH_MOCK_LARGE_MEMORIES = 1`
- `SYNTH_KEEP_MOCKED_MEMORIES = 1`
- `SYNTH_HIERARCHICAL = 1`
- No physical SRAM macro variables are mixed in.

Action:

- Restore the All-Mock memory trio.
- Keep hierarchy enabled.
- Relax the clock target before retrying.
- Restart from synth.

### Module or blackbox confusion

Likely causes:

- Mixed All-Mock and physical-SRAM approaches.
- Included `*.mems.v` wrappers or SRAM override files when All-Mock should generate mocks.

Action:

- Remove physical SRAM override/macro variables from this flow.
- Confirm `nosram.sv` skipped `mems.v` files.
- Restart from synth after config cleanup.

## Floorplan and Placement Failures

### Placement overflow / not enough sites / cannot place

Likely causes:

- `CORE_UTILIZATION` too high for post-repair cell area.
- Timing repair inserted too many buffers.
- Padding or density settings reduced effective placeable capacity.

Check:

- Reported instance utilization if available.
- Timing-repair buffer count if available.
- Whether clock target was much tighter than the previous viable round.

Action:

- Reduce `CORE_UTILIZATION` by 5-10.
- Reduce `PLACE_DENSITY` by 0.05-0.10.
- Relax clock if timing repair pressure is clearly causing utilization growth.
- Restart from floorplan, or synth if synthesis variables changed.

### Detailed placement legalization failure

Likely causes:

- Core utilization too high.
- Global padding insufficient for routability.
- Detail padding too high for legal placement.
- Macro/blockages if any are present.

Action:

- If congestion signs exist, reduce density first.
- If legalization capacity is the issue, reduce utilization.
- Do not increase padding and utilization together.

## Routing and DRC Failures

### Global-route congestion / overflow (`global_congestion` / `layer_congestion`)

Signals:

- `congestion.total_overflow > 0` from route stage metrics.
- `congestion.hotspot_layers` lists layers at >=80% usage or with overflow.

Likely causes:

- Too little whitespace.
- Placement too dense around high-fanout or timing-critical regions.
- Clock target caused extra buffering.

Action:

- If overflow is concentrated on 1-2 layers (`layer_congestion`): small density cut (-0.05); a routing-layer resource adjustment is a secondary option.
- If overflow is spread across layers (`global_congestion`): reduce `PLACE_DENSITY` by 0.05-0.10 and `CORE_UTILIZATION` by 5.
- Keep `GPL_ROUTABILITY_DRIVEN=1`.
- Do not tighten clock in the same retry.

### Detailed-route DRC violations (`drc`)

Signals:

- `signals.drc_errors > 0` after route.
- `signals.drc_errors_by_iter` shows the per-iteration trend: converging to 0 is healthy; a plateau means structural congestion that more iterations cannot fix.

Likely causes:

- Global routing guides are too congested for detailed routing.
- Pin access or local routing resources are insufficient.
- One-site gaps or dense local placement patterns can contribute.

Interpretation:

- OpenROAD DRC here primarily checks signal routing rules from LEF after routing guides exist.
- Nonzero DRC invalidates final QoR selection.

Action:

- Reduce density first.
- Reduce utilization if DRC persists.
- Keep routability-driven placement enabled.
- If repeated with low density, preserve the best diagnostic artifacts and report that the floorplan/placement is not routable under current constraints.

## Timing Failures

### Wire-dominated timing (`wire_dominated_timing`)

Signals:

- `signals.setup_ws < 0` AND `critical_path.wire_delay_pct > 60`.

Meaning: the critical path is dominated by interconnect delay. Relaxing the
clock hides the symptom without fixing the cause.

Action:

- Lower `PLACE_DENSITY` by 0.05 and/or `CORE_UTILIZATION` by 5 to give the router and repair engine whitespace.
- Keep `GPL_TIMING_DRIVEN=1`.
- Only relax the clock if a whitespace round fails to improve WNS.
- Restart from place.

### Logic-dominated timing (`logic_dominated_timing`)

Signals:

- `signals.setup_ws < 0` AND `critical_path.wire_delay_pct < 40`.

Meaning: logic depth dominates; physical knobs will not help much.

Action:

- Relax clock toward ECP: new period ≈ `(clock_period - WNS) * 1.05`.
- Do not burn rounds on density/utilization changes.
- Restart from synth (the SDC changes).

### Hold violations with clean setup (`hold_violation`)

Signals:

- `signals.hold_violation_count > 0` while `signals.setup_ws >= 0`.
- Often with elevated `signals.clock_skew_hold` (BOOM-class designs commonly show ~1 ns skew).

Meaning: a clock-skew problem. **Hold is frequency-independent** — changing the
clock period (18 ns or 100 ns) does not move hold WNS at all, because hold
checks data stability within the same clock edge.

Action (proven on SmallBOOM: 144 hold violations → 0):

1. **Primary fix: `export HOLD_SLACK_MARGIN = 0.1`** — the tool auto-inserts hold buffers at CTS/route (SmallBOOM: ~9,150 buffers added, area/power essentially unchanged).
2. Secondary: reduce clock skew via CTS knobs (`CTS_CLUSTER_SIZE` 10-40, `CTS_CLUSTER_DIAMETER` 80-120) — the root-cause fix, but large designs rarely get skew low enough.
3. Do NOT relax the clock — it never fixes hold.
4. Restart from cts.

### Timing repair pressure (`repair_pressure`)

Signals:

- Actual `signals.utilization` far above the configured `CORE_UTILIZATION`, or
- `signals.repair_buffer_count / signals.instance_count > ~0.15`.

Meaning: timing repair is consuming all placement headroom; later stages will
congest or fail to legalize.

Action:

- Reduce `CORE_UTILIZATION` by 5-10 to restore repair headroom.
- Consider a modest clock relax if WNS is also negative.
- Restart from floorplan.

### WNS < -2 ns or large negative TNS (no path breakdown available)

Likely causes:

- Clock is too aggressive.
- Timing repair lacks whitespace or effort.
- Congestion is stretching critical paths.

Action:

- Relax clock toward ECP (`clock_period - WNS`), not a blind increment.
- Keep `GPL_TIMING_DRIVEN=1`.
- Keep `TNS_END_PERCENT` high.
- Reduce density/utilization if congestion or overflow is also present.
- Do not pursue area compaction.

### WNS slightly negative

Likely causes:

- Near closure.
- A small set of paths remains critical.

Action:

- Relax clock by 0.25-0.5 ns, or keep clock and slightly improve whitespace.
- Tighten `SETUP_SLACK_MARGIN` only if the previous round was already close.
- Avoid changing more than one physical knob.

### WNS >= 0 but TNS or violation count is inconsistent

Action:

- Trust the structured report if available.
- Re-read finish and route reports.
- If reports disagree, mark the round diagnostic and rerun rather than using it as best QoR.

## Early-Stopped Rounds

The round executor aborts before route when place/CTS signals show the round
cannot recover (`setup_ws < -0.25 × clock_period`, or hold+setup both broken
after CTS). For these rounds:

- The saved metrics are surrogate (place/CTS-stage) metrics — never QoR candidates.
- The early-stop threshold breach itself is the signature: the clock target or whitespace is far off. Apply the matching timing/congestion action above with a LARGER step than usual (the signal is unambiguous).
- An early-stopped round costs ~1-2 h instead of ~7 h; spending its saved budget on one extra exploration round is usually worthwhile.

## Clean but Not Optimal

### DRC == 0 and WNS >= 0, target not met

Action:

- Save the round.
- Tighten clock by 0.5-1 ns.
- Keep utilization/density unchanged unless there is large positive slack.

### DRC == 0 and WNS has large positive slack

Action:

- Save the round.
- If performance is the goal, tighten clock.
- If area/wirelength is the goal, run one compaction experiment: increase utilization by 5 or density by 0.03-0.05.

## Known Pitfalls (verified on SmallBOOM, 2026-06)

| Pitfall | Symptom | Resolution |
| --- | --- | --- |
| SDC not propagated | Changed clock period but WNS unchanged across rounds | ORFS does not re-propagate the SDC into cached results. Staged restart is NOT safe after an SDC change — use `clean_design(from_stage="all")` and restart from synth |
| Routing congestion at density 0.50 | GRT-0116 errors during global route | `PLACE_DENSITY = 0.45` is the proven SmallBOOM point; lower CORE_UTILIZATION if it persists |
| New variant missing synth | `1_synth.odb does not exist` | A new DESIGN_NICKNAME variant starts with empty artifact dirs — parallel candidates must run the full flow from synth |
| Relaxing clock to fix hold | Hold WNS unchanged after clock change | Hold is frequency-independent. Use `HOLD_SLACK_MARGIN = 0.1` instead |
| Setup WNS vs clock relation | — | Setup WNS moves ~1:1 with clock period (+1 ns clock ≈ +1 ns WNS). Use this to compute the exact relax step: new period ≈ old period − WNS + desired margin |

## Stop Conditions

Stop iterating and report the best available result when:

- A DRC-clean timing-clean round meets the user's target.
- Maximum rounds are reached.
- WNS improvement is below 0.1 ns for two consecutive rounds.
- The same stage fails twice after applying the matching corrective action.
- All-Mock assumptions no longer match the user's desired signoff target.
