# ORFS Parameter Guide for Chipyard All-Mock PnR

Use this reference before changing `config.mk` or `constraint.sdc` between rounds.
It is tuned for the `chipyard-pnr-docker-test` All-Mock flow on large Chipyard
designs such as SmallBOOM.

## Baseline Policy

- Start from the casebook warm-start when a similar past design exists (`casebook(action="query")`); otherwise use the proven SmallBOOM baseline: `clock_period_ns=18.5`, `CORE_UTILIZATION=40`, `PLACE_DENSITY=0.45`, `SETUP_SLACK_MARGIN=0.5`, `HOLD_SLACK_MARGIN=0.1`, timing/routability driven placement enabled. This point closed setup AND hold (WNS +0.357 / +0.034) at 54 MHz on SmallBOOM with 384k cells.
- `PLACE_DENSITY=0.50` caused routing congestion (GRT-0116) on SmallBOOM — 0.45 is the safe starting point for BOOM-class designs.
- Change only one or two knobs per round.
- Treat clock, utilization, and density as sensitive knobs:
  - Clock: initial changes of 0.25-2 ns are usually enough.
  - Utilization: changes above 5-10 percentage points are large.
  - Density: changes of 0.05 are meaningful; 0.10 is large.
- Record the reason for every changed knob.
- If two rounds show no meaningful WNS improvement, stop broad churn and report the best clean point.

## Structured Signals → Knob Selection

`get_stage_metrics` returns normalized signals per stage. Use them to pick the
RIGHT knob instead of guessing:

| Signal | Where | What it tells you | Knob response |
| --- | --- | --- | --- |
| `setup_ws` / `setup_tns` | every stage | Setup timing health; ECP = clock - WS | Negative and logic-dominated → clock; negative and wire-dominated → whitespace |
| `hold_violation_count` with clean setup | cts/route/finish | CTS/skew problem, NOT a clock-target problem | CTS_CLUSTER_SIZE/DIAMETER; never relax clock for this |
| `critical_path.wire_delay_pct` | finish | >60%: wires dominate → physical fix; <40%: logic dominates → clock/synthesis fix | Wire: lower density/utilization. Logic: relax clock toward ECP |
| `congestion.hotspot_layers` | route | Overflow on 1-2 layers = layer-local; spread wide = global whitespace shortage | Local: small density cut, consider layer adjust. Global: density -0.05..-0.10 and utilization -5 |
| `drc_errors_by_iter` | route | DRC trend across detailed-route iterations. Converging to 0 = healthy; plateauing = structural congestion | Plateau → density/utilization, not more route iterations |
| `utilization` (actual) | place/finish | Post-repair real utilization vs your CORE_UTILIZATION target | Actual >> target = repair pressure → lower CORE_UTILIZATION |
| `repair_buffer_count` / `instance_count` | finish | Buffer ratio > ~15% = timing repair fighting the floorplan | Lower utilization; possibly relax clock |
| `clock_skew_setup` / `clock_skew_hold` | cts/route/finish | Large skew amplifies both setup and hold problems | CTS knobs; check SDC clock definitions |

`diagnose_failure(stage_metrics=..., congestion=...)` applies these rules
automatically and returns `error_type` + `suggested_params` + `restart_from`.
Treat its output as the starting point; override with judgment and this guide.

## Main Knobs

| Skill knob | ORFS variable | Meaning | Safe direction |
| --- | --- | --- | --- |
| `clock_period_ns` | SDC `create_clock -period` | Timing target. ECP is `clock_period - WNS`. | Relax when WNS/TNS is poor; tighten only after DRC == 0 and WNS >= 0. |
| `core_utilization` | `CORE_UTILIZATION` | Initial synthesized-netlist floorplan target. Later optimization may raise real utilization. | Lower for overflow/congestion/timing repair pressure; raise only after clean rounds. |
| `place_density` | `PLACE_DENSITY` | Placement spread target. 1.0 is dense, 0.0 is spread. | Lower for DRC/congestion; raise only for area compaction after route is clean. |
| timing-driven placement | `GPL_TIMING_DRIVEN` | Runs timing-aware global placement. | Keep enabled for large timed designs. |
| routability-driven placement | `GPL_ROUTABILITY_DRIVEN` | Uses global routing congestion during placement. | Keep enabled for congestion/DRC-prone rounds. |
| setup margin | `SETUP_SLACK_MARGIN` | Extra setup repair margin. | Start relaxed and tighten only when timing is close or clean. |
| hold margin | `HOLD_SLACK_MARGIN` | Hold repair margin; makes the tool insert hold buffers at CTS/route. | Keep at 0.1 for BOOM-class designs (clock skew ~1 ns causes hold violations). Hold is frequency-independent — never fix hold by changing the clock. |

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
| First run | Casebook warm-start if a similar design exists; else 18.5 ns, util 40, density 0.45, hold margin 0.1, timing/routability driven on, setup margin 0.5. |
| Severe timing failure, route clean | Relax clock toward ECP: new period ≈ old − WNS + 0.3-0.5 margin (setup WNS moves ~1:1 with clock). |
| Slight timing failure, route clean | Relax clock by 0.25-0.5 ns or keep clock and increase timing effort/margin. |
| Hold violations, setup clean | Add/keep `HOLD_SLACK_MARGIN = 0.1`; restart from cts. Never touch the clock for hold. |
| DRC/congestion, timing also bad | Lower density by 0.05-0.10; optionally lower util by 5; do not tighten clock. |
| Placement overflow | Lower util by 5-10 and density by 0.05-0.10. |
| Clean with large positive slack | Save result, then tighten clock by 0.5-1 ns. |
| Clean with target met | Try one area cleanup round: util +5 or density +0.03-0.05, not both. |

## Candidate Set Design (Parallel Exploration)

When the diagnosis gives a clear direction but the magnitude is unknown,
run 2-3 candidates in parallel instead of one sequential guess:

- **One knob, one direction.** Sweep a single knob along the diagnosed direction with the other knobs frozen. Example for global congestion at density 0.55: candidates {0.45, 0.50} or {0.45, 0.50, 0.55-as-control}.
- **No full-factorial.** Never cross two knobs in one candidate set — attribution becomes impossible.
- **Spacing.** Use meaningful steps: density 0.05 apart, utilization 5 apart, clock 0.5-1 ns apart. Candidates closer than that waste a run.
- **Anchor.** When unsure, keep one candidate at the previous round's values as a control point.
- **Isolation.** Each candidate needs its own `DESIGN_NICKNAME` (own config.mk + SDC copy) so ORFS artifact directories do not collide. Parallel candidates always run the full flow from synth.
- **Resources.** Each BOOM-class run peaks ~20 GB. Check free memory before spawning; fall back to sequential when short.
- **Selection.** After all candidates finish, apply the validity-first rules from `orfs-metrics-and-objectives.md` and continue from the winner only.

## Restart Levels (Staged Restart)

Re-running everything from synth wastes hours when only late-stage knobs
changed. Use `clean_design(from_stage=...)` + executor `restart_from`:

| Changed knob | Restart from | Rationale |
| --- | --- | --- |
| Clock period (SDC), any SYNTH_* variable | synth (`from_stage="all"`) | Synthesis timing targets derive from the SDC; ORFS does not re-propagate a changed SDC into cached results |
| CORE_UTILIZATION | floorplan | Floorplan consumes utilization; synth netlist unchanged |
| PLACE_DENSITY, GPL_*, SETUP_SLACK_MARGIN | place | Placement and later consume these |
| HOLD_SLACK_MARGIN, CTS_CLUSTER_SIZE, CTS_CLUSTER_DIAMETER | cts | Hold buffers are inserted at CTS/route; clock tree reads CTS knobs |

When multiple knobs change, restart from the EARLIEST affected stage.
Never use a staged restart after a clock or synthesis change.
