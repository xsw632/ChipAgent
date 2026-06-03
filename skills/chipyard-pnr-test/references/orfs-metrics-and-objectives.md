# ORFS Metrics and Objectives

Use this reference when comparing PnR rounds or deciding whether a round is valid.
It is distilled from ORFS-Agent objective handling and EDA-Corpus OpenROAD/ORFS
knowledge.

## Validity First

- A round is not a final QoR candidate unless it reaches the relevant end stage and has `DRC == 0`.
- Treat any nonzero detailed-route DRC count as invalid for final selection, even if timing and area look good.
- Prefer final-stage metrics over CTS/global-route surrogate metrics when final metrics exist.
- Use CTS/global-route metrics only to guide the next retry when finish/route failed.
- For this All-Mock flow, timing excludes real SRAM timing. A clean round means PnR feasibility and optimistic timing, not signoff.

## Core Objective Definitions

| Objective | Metric | Lower is better | Use in this skill |
| --- | --- | --- | --- |
| Timing feasibility | WNS/TNS | WNS higher is better; TNS closer to 0 is better | Primary closure gate. Require WNS >= 0 for a timing-clean round. |
| Effective clock period (ECP) | `clock_period_ns - WNS` | Yes | Useful for comparing timing across different clock periods. Negative WNS increases ECP. |
| Detailed wirelength | detailed-route wirelength | Yes | Compare only among DRC-clean rounds. |
| Area | final design/core area | Usually lower | Secondary after DRC and timing. Do not optimize area from failed rounds. |
| Power | final total power | Usually lower | Secondary after DRC and timing; tight timing can increase buffers and power. |
| Runtime/resources | stage runtime, OOM, timeout | Lower/fewer is better | Use to decide whether to relax targets or reduce density. |

## Metrics to Record per Round

Record these fields in `compare_runs` history whenever available:

- Config: `clock_period_ns`, `core_utilization`, `place_density`, `gpl_timing_driven`, `gpl_routability_driven`, `setup_slack_margin`, `SYNTH_HIERARCHICAL`, All-Mock memory variables.
- Stage result: last completed stage, failed stage, timeout/OOM flag, route/finish status.
- Timing: final WNS, final TNS, setup violation count, hold violation count if available.
- Routing: detailed-route DRC count, detailed-route wirelength, vias if available.
- Physical QoR: area/core area, instance utilization, power.
- Optimization side effects: timing-repair buffer count if available.

## How to Interpret WNS/TNS

- `WNS >= 0` means the single worst setup path meets the current constraint.
- `TNS == 0` means no accumulated negative setup slack remains.
- `WNS < 0` with small-magnitude TNS means a small number of near-critical paths remain.
- `WNS < 0` with large negative TNS means many paths violate or timing repair is underpowered.
- If WNS is clean but DRC is nonzero, fix routing legality before tightening the clock.
- If DRC is clean but WNS is slightly negative, adjust clock or timing effort before changing area-oriented knobs.

## Comparing Rounds

1. Partition rounds into valid and invalid. Valid means no stage failure and DRC == 0.
2. Among valid rounds, first prefer WNS >= 0 if timing feasibility is the user's goal.
3. If several rounds are timing-clean, pick the smallest clock period that remains clean.
4. If several rounds meet the same timing target, compare area/power/wirelength.
5. Keep invalid rounds for diagnosis only; never choose them as best QoR.
6. If no round is valid, report the furthest stage reached and the most actionable blocker.

## Surrogate Metrics

- CTS WNS and estimated wirelength are useful early predictors but can diverge from final route.
- Detailed-route wirelength is the wirelength metric to trust for final comparison.
- Finish timing is the timing metric to trust when available.
- If CTS is clean but route/finish is dirty, prioritize routing/DRC fixes over further timing tightening.

## All-Mock Interpretation

- Mocked SRAMs have no physical macro shape and no real memory timing arc.
- Area is useful as a rough standard-cell plus mock feasibility signal, not final macro-inclusive area.
- Timing is optimistic relative to a real SRAM macro flow.
- DRC/routing success still matters because standard-cell routing and top-level connectivity are exercised.
- Do not mix All-Mock metrics with physical-SRAM rounds in the same final QoR table unless clearly labeled.
