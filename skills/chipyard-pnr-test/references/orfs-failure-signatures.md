# ORFS Failure Signatures for Chipyard All-Mock PnR

Use this reference after a failed round or a DRC/timing-dirty round. Match the
first strong signal, then choose a small parameter change.

## Triage Order

1. Identify the failed or dirty stage: synth, floorplan, place, CTS, route, finish.
2. Check whether All-Mock variables are present if synth memory/OOM behavior appears.
3. Check DRC count before comparing final QoR.
4. Check WNS/TNS after route/finish.
5. Change only the knobs tied to the dominant failure.

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

### Global-route congestion / overflow

Likely causes:

- Too little whitespace.
- Placement too dense around high-fanout or timing-critical regions.
- Clock target caused extra buffering.

Action:

- Keep `GPL_ROUTABILITY_DRIVEN=1`.
- Reduce `PLACE_DENSITY` by 0.05-0.10.
- Reduce `CORE_UTILIZATION` by 5 if repeated.
- Do not tighten clock in the same retry.

### Detailed-route DRC violations

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

### WNS < -2 ns or large negative TNS

Likely causes:

- Clock is too aggressive.
- Timing repair lacks whitespace or effort.
- Congestion is stretching critical paths.

Action:

- Relax clock by 1-2 ns.
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

## Stop Conditions

Stop iterating and report the best available result when:

- A DRC-clean timing-clean round meets the user's target.
- Maximum rounds are reached.
- WNS improvement is below 0.1 ns for two consecutive rounds.
- The same stage fails twice after applying the matching corrective action.
- All-Mock assumptions no longer match the user's desired signoff target.
