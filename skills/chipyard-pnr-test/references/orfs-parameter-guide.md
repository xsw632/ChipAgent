# ORFS Parameter Guide for Chipyard All-Mock PnR

Use this reference before changing `config.mk` or `constraint.sdc` between rounds.
It is tuned for the `chipyard-pnr-docker-test` All-Mock flow on large Chipyard
designs such as SmallBOOM.

## Baseline Policy

- Start conservative: `clock_period_ns=20`, `CORE_UTILIZATION=40`, `PLACE_DENSITY=0.55`, timing/routability driven placement enabled.
- Change only one or two knobs per round.
- Treat clock, utilization, and density as sensitive knobs:
  - Clock: initial changes of 0.25-2 ns are usually enough.
  - Utilization: changes above 5-10 percentage points are large.
  - Density: changes of 0.05 are meaningful; 0.10 is large.
- Record the reason for every changed knob.
- If two rounds show no meaningful WNS improvement, stop broad churn and report the best clean point.

## Main Knobs

| Skill knob | ORFS variable | Meaning | Safe direction |
| --- | --- | --- | --- |
| `clock_period_ns` | SDC `create_clock -period` | Timing target. ECP is `clock_period - WNS`. | Relax when WNS/TNS is poor; tighten only after DRC == 0 and WNS >= 0. |
| `core_utilization` | `CORE_UTILIZATION` | Initial synthesized-netlist floorplan target. Later optimization may raise real utilization. | Lower for overflow/congestion/timing repair pressure; raise only after clean rounds. |
| `place_density` | `PLACE_DENSITY` | Placement spread target. 1.0 is dense, 0.0 is spread. | Lower for DRC/congestion; raise only for area compaction after route is clean. |
| timing-driven placement | `GPL_TIMING_DRIVEN` | Runs timing-aware global placement. | Keep enabled for large timed designs. |
| routability-driven placement | `GPL_ROUTABILITY_DRIVEN` | Uses global routing congestion during placement. | Keep enabled for congestion/DRC-prone rounds. |
| setup margin | `SETUP_SLACK_MARGIN` | Extra timing repair margin. | Start relaxed and tighten only when timing is close or clean. |

## Secondary Knobs Worth Knowing

| Variable | What it means | When to touch it |
| --- | --- | --- |
| `TNS_END_PERCENT` | Percent of violating endpoints timing repair tries to fix. Higher values spend more runtime/area on timing. | Keep near 100 for closure. Lower only for wirelength/area experiments after clean feasibility exists. |
| `SYNTH_HIERARCHICAL` | Enables hierarchical synthesis instead of flat synthesis. | Keep enabled for large generated designs and All-Mock memory handling unless synth specifically fails due to hierarchy. |
| `ABC_AREA` | Biases synthesis toward area. | Keep for feasibility/area rounds; do not use it as the first response to timing failure. |
| `ABC_CLOCK_PERIOD_IN_PS` | Synthesis timing period; defaults from SDC when not set. | Usually leave derived from SDC to avoid mismatch. |
| `CELL_PAD_IN_SITES_GLOBAL_PLACEMENT` | Global-placement cell padding in site widths. | Useful for congestion, but too much padding lowers effective placeable capacity. |
| `CELL_PAD_IN_SITES_DETAIL_PLACEMENT` | Detailed-placement padding in site widths. | Use carefully; too much detail padding can cause legalization problems. |
| `ENABLE_DPO` | Enables detail placement optimization. | Can improve timing/placement QoR at runtime cost. |
| `PIN_LAYER_ADJUST` / `UP_LAYER_ADJUST` | Global-routing layer resource adjustments for lower and upper routing layers. | More relevant to custom FastRoute TCL experiments than this default skill. |
| `CTS_CLUSTER_SIZE` | Target number of clock sinks per CTS cluster. | Change only for CTS-specific QoR/failure. Common exploration range is 10-40. |
| `CTS_CLUSTER_DIAMETER` | CTS cluster diameter in microns. | Change only for CTS-specific QoR/failure. Common exploration range is 80-120. |

## Objective-Driven Direction

### Timing/ECP Closure

- Goal: reduce `clock_period_ns - WNS`, not just reduce the clock number.
- If WNS is strongly negative, tightening clock usually worsens ECP.
- Prefer:
  - relax clock until WNS is near 0,
  - lower utilization 5-10 points if repair/congestion pressure is high,
  - keep `TNS_END_PERCENT` high,
  - keep timing-driven placement enabled,
  - add whitespace before adding density.

### Wirelength/Area Cleanup

- Only do this after at least one DRC-clean round exists.
- Prefer:
  - avoid tightening clock in the same round,
  - cautiously raise utilization or density,
  - avoid high timing-repair effort if timing has large positive slack,
  - compare only DRC-clean detailed-route wirelength.

### Balanced Feasibility

- First target DRC == 0 and WNS close to 0.
- If timing dominates the loss: small clock relax plus small utilization/density drop.
- If wirelength/area dominates and timing has slack: small utilization/density increase.
- Do not change clock, utilization, and density all in the same round unless recovering from a clearly broken run.

## Parameter Interactions

- `CORE_UTILIZATION` is not final utilization. Timing repair can insert buffers and resize cells, raising real utilization later.
- Padding does not change logical area, but it makes cells appear wider to placement and can reduce placeable capacity.
- High utilization plus high padding is risky.
- Very high density margin with low timing-repair effort is contradictory: one spreads/guards placement while the other avoids fixing timing.
- Large CTS cluster size with small cluster diameter is risky because many sinks are forced into tight clusters.
- Lower density can improve routing and timing but may increase wirelength/area.
- Higher utilization can reduce wirelength but often hurts timing, DRC, and repair headroom.

## All-Mock-Specific Knobs

These must stay together:

```make
export SYNTH_MEMORY_MAX_BITS = 1
export SYNTH_MOCK_LARGE_MEMORIES = 1
export SYNTH_KEEP_MOCKED_MEMORIES = 1
```

Do not add these in the All-Mock flow:

- `SYNTH_BLACKBOXES`
- `ADDITIONAL_LEFS`
- `ADDITIONAL_LIBS`
- `ADDITIONAL_GDS`
- `sram_override.v`
- `sram_mapping.json`

Those belong to the physical SRAM flow, not this skill.

## Suggested Round Recipes

| Situation | Next-round recipe |
| --- | --- |
| First run | 20 ns, util 40, density 0.55, timing/routability driven on, slack margin 0.5. |
| Severe timing failure, route clean | Relax clock by 1-2 ns; keep density/util unchanged unless utilization is high. |
| Slight timing failure, route clean | Relax clock by 0.25-0.5 ns or keep clock and increase timing effort/margin. |
| DRC/congestion, timing also bad | Lower density by 0.05-0.10; optionally lower util by 5; do not tighten clock. |
| Placement overflow | Lower util by 5-10 and density by 0.05-0.10. |
| Clean with large positive slack | Save result, then tighten clock by 0.5-1 ns. |
| Clean with target met | Try one area cleanup round: util +5 or density +0.03-0.05, not both. |
