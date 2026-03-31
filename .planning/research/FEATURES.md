# Feature Landscape: RTL-to-GDS

**Domain:** EDA physical design automation (synthesis + place-and-route)
**Project:** ChipAgent v1.1.2
**Researched:** 2026-03-31
**Confidence:** HIGH -- features derived from verified ORFS GCD flow on nangate45, existing codebase analysis, and ASIC design workflow knowledge

## Scope

Features required for a `/chip-agent:pnr` slash command that takes verified RTL Verilog (output of the existing pipeline) through Yosys synthesis and OpenROAD place-and-route to produce DEF, gate-level Verilog, and timing/power/area reports on nangate45.

---

## Table Stakes

Features users expect. Missing any of these and the PnR command feels broken or unusable.

| # | Feature | Why Expected | Complexity | Depends On |
|---|---------|-------------|------------|------------|
| TS-01 | **SDC auto-generation from Verilog** | Users (NL-to-Verilog users) do not know SDC format. The pipeline must generate constraints automatically by detecting clock ports in the compiled Verilog. Sequential modules get `create_clock`; combinational modules get `set_max_delay` with a virtual clock. | Low | Existing `workspace/generated/<Module>.v` |
| TS-02 | **Yosys synthesis to gate-level netlist** | The core value: RTL to gates. Must read liberty, read Verilog, run `synth -top -flatten`, `dfflibmap` (sequential), `abc`, tie/buffer insertion, and write `synth.v`. | Med | TS-01 (SDC for ABC timing-driven synthesis) |
| TS-03 | **Synthesis report parsing** | Users need to know if synthesis succeeded and what it produced. Parse `synth_stat.txt` for cell count, area estimate, and `synth_check.txt` for warnings/errors. Display in Claude-readable summary. | Low | TS-02 |
| TS-04 | **OpenROAD floorplan initialization** | Physical design starts here. `initialize_floorplan` with utilization (default 55%), aspect ratio 1.0, site name, track definitions. | Med | TS-02 (needs synth.v) |
| TS-05 | **IO pin placement** | Pins must be placed on routing layers for the design to be routable. `place_pins` on metal5 (horizontal) and metal6 (vertical) per nangate45 convention. | Low | TS-04 |
| TS-06 | **Power distribution network** | Design is non-functional without VDD/VSS. Source the platform's `grid_strategy-M1-M4-M7.tcl` and run `pdngen`. | Low | TS-04 |
| TS-07 | **Global + detailed placement** | Core PnR. `global_placement` with density control, parasitic estimation, buffer/timing repair, then `detailed_placement` with violation check. | Med | TS-06 |
| TS-08 | **CTS for sequential modules** | Any module with a real clock needs clock tree synthesis. Skip automatically for combinational modules (zero propagated clocks). Buffer list from nangate45. | Med | TS-07 |
| TS-09 | **Global + detailed routing** | Completes physical implementation. Layer constraints from `fastroute.tcl`, DRC report from detailed routing. | Med | TS-08 |
| TS-10 | **Filler cell insertion** | Required for DRC-clean layout. Insert fill cells (X1 through X32) after routing. | Low | TS-09 |
| TS-11 | **Timing report (STA)** | The primary PPA metric. `report_checks` with min/max paths, plus WNS and TNS summaries. Users need to know if timing is met. | Low | TS-09 |
| TS-12 | **Power report** | Second PPA metric. `report_power` showing internal, switching, and leakage breakdown. | Low | TS-09 |
| TS-13 | **Area report** | Third PPA metric. `report_design_area` for total and utilization. | Low | TS-09 |
| TS-14 | **DEF + gate-level Verilog export** | The primary output artifacts. `write_def` and `write_verilog` to `workspace/pnr/results/`. | Low | TS-09 |
| TS-15 | **Workspace directory structure** | All PnR artifacts in `workspace/pnr/` with `results/` and `reports/` subdirs. Follows existing workspace isolation pattern. | Low | Existing workspace convention |
| TS-16 | **Pre-flight validation** | Before running PnR, verify: (a) `workspace/generated/<Module>.v` exists, (b) Yosys is installed, (c) OpenROAD is installed, (d) nangate45 PDK is locatable. Fail fast with actionable error if any missing. | Low | Existing env detection |
| TS-17 | **Stage-level error handling** | Each stage (SDC gen, synthesis, floorplan, placement, CTS, routing, reports) must capture stderr/stdout, detect failure, and report which stage failed with diagnostic context. Pipeline stops on first failure. | Med | All stages |
| TS-18 | **PnR summary report** | Final formatted report analogous to the simulation verification report. Shows: module name, synthesis stats (cells, area), timing (WNS/TNS, met/violated), power, area, output file paths. | Low | TS-11, TS-12, TS-13 |
| TS-19 | **`/chip-agent:pnr` slash command** | The entry point. Skill definition with `SKILL.md`, accepted arguments (`<ModuleName>`), pipeline steps, allowed tools. Follows existing skill conventions. | Med | All above |

---

## Differentiators

Features that elevate ChipAgent beyond "just runs scripts." Not expected, but meaningfully valuable.

| # | Feature | Value Proposition | Complexity | Depends On |
|---|---------|-------------------|------------|------------|
| DF-01 | **spec.json-driven SDC enrichment** | If `spec.json` contains `clock_period_ns`, use it instead of the 2.0ns default. Lets users influence timing targets through the natural language spec ("500MHz clock") without touching SDC directly. | Low | TS-01, existing spec.json |
| DF-02 | **Combinational vs sequential auto-detection** | Automatically detect whether the module has a clock port and adjust the entire flow: SDC template, `dfflibmap` inclusion, CTS skip. Zero user configuration needed. This is already baked into the table stakes but explicitly calling it out as a differentiator because most EDA flows require the user to specify this. | Low | TS-01, TS-02, TS-08 |
| DF-03 | **Timing failure diagnosis** | When WNS is negative (timing violated), parse the critical path from `timing.rpt` and present it in plain English: "Timing violated by X ns on path from port A through N cells to port B. Consider relaxing the clock period or reducing combinational depth." | Med | TS-11 |
| DF-04 | **DRC violation summary** | Parse `route_drc.rpt` and summarize violations by type (short, spacing, width). If zero violations, say so explicitly. If violations exist, flag as warning (common for academic PDKs). | Low | TS-09 |
| DF-05 | **Cell usage analysis** | Parse `cell_usage.rpt` to show the most-used standard cells and total cell count. Gives users insight into what the synthesizer chose. | Low | TS-09 |
| DF-06 | **Congestion reporting** | Parse `congestion.rpt` and flag if any region exceeds density threshold. Useful for understanding routing difficulty. | Low | TS-09 |
| DF-07 | **Environment detection for PnR tools** | Extend `detect-env.sh` and `env.json` with Yosys, OpenROAD, KLayout presence/version and nangate45 PDK path. Add `can_synthesize` and `can_pnr` capability flags. `/chip-agent:initialize` gains PnR awareness. | Med | Existing detect-env.sh |
| DF-08 | **SPEF parasitic extraction** | Run OpenRCX to extract parasitics, write SPEF, and use it for final STA. Makes timing reports more accurate (post-route vs estimated). Already in the Tcl flow but calling it out as a differentiator because many quick flows skip this. | Low | TS-09 |
| DF-09 | **Synthesis auto-retry on failure** | If Yosys synthesis fails (e.g., undefined module, unsupported construct), parse the error, attempt to diagnose (common: Chisel generates `$` prefixed internal signals, `FIRRTL_RAND` macros), and suggest fixes. Up to 3 attempts, matching the existing lint auto-fix pattern. | High | TS-02 |

---

## Anti-Features

Features to explicitly NOT build in v1.1.2.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **GDS export** | KLayout is not installed. Adding a KLayout dependency changes the install story significantly. DEF + reports deliver the core PPA value. | Scope to DEF output. Document GDS as a follow-up requiring KLayout. |
| **Multi-PDK support** | Only nangate45 is available and verified. Adding sky130 or ASAP7 requires testing each platform's config files, liberty models, and Tcl scripts. | Hardcode nangate45. Design scripts so PDK path is a variable (future-proofing), but only support one PDK now. |
| **Clock period optimization loop** | Automatically binary-searching for the best achievable clock period is computationally expensive (each PnR run takes 30-120 seconds) and adds complexity. | Use a conservative default (2.0ns). Let users specify via spec.json if they want tighter timing. |
| **Floorplan GUI or visual feedback** | No GUI in Claude Code. Visual floorplan/placement feedback requires an image renderer or external viewer. | Report numeric area/utilization. DEF files can be opened in external viewers (OpenROAD GUI, KLayout) by the user. |
| **Incremental PnR / ECO flow** | Engineering change orders require design database persistence between sessions, which is out of scope for a stateless slash command. | Always run full flow from scratch. Each PnR invocation is idempotent. |
| **Custom floorplan constraints** | Macro placement, blockages, pin assignment constraints are advanced features that require domain expertise. | Use auto-floorplan with utilization-based sizing. Pin placement is automatic. |
| **Multi-corner STA** | nangate45 only ships typical corner. Multi-corner analysis requires additional liberty files (fast, slow) which are not available. | Single-corner (typical) STA only. |
| **Power intent (UPF/CPF)** | Power domains, voltage islands, and retention are SoC-level concerns beyond single-module scope. | Single power domain (VDD/VSS) only. |
| **Formal equivalence checking** | Verifying gate-level netlist matches RTL requires a formal tool (e.g., Conformal, Formality). Out of scope. | Rely on Yosys synthesis correctness. Users can run their own verification. |
| **Extending `/chip-agent:workflow` with PnR** | PnR is slow (30-120s), optional, and conceptually separate from verification. Bolting it onto workflow makes the existing fast path slower and more fragile. | Separate `/chip-agent:pnr` command. Users run it after verification passes. |
| **Hierarchical synthesis** | ChipAgent modules are small (under 10K gates typically). Hierarchy adds complexity for no benefit at this scale. | Always flatten with `synth -flatten`. |
| **Macro support (SRAMs, hard IPs)** | Generated modules are standard-cell-only combinational/sequential blocks. No memory compilers or hard IP. | Skip macro placement entirely. |
| **Interactive OpenROAD GUI** | CLI-only plugin with no display server assumption. | Text reports only. Users open DEF in external viewers if needed. |
| **IR drop analysis** | Requires additional power grid analysis setup. Not critical for academic/demonstration flow. | Omit `analyze_power_grid`. PDN generation is sufficient. |

---

## Feature Dependencies

```
Pre-flight validation (TS-16)
    |
    v
SDC auto-generation (TS-01)
    |
    +-- spec.json clock enrichment (DF-01)
    |
    v
Yosys synthesis (TS-02)
    |
    +-- Synth report parsing (TS-03)
    +-- Synth auto-retry (DF-09)
    |
    v
Floorplan init (TS-04)
    |
    +-- IO pin placement (TS-05)
    +-- PDN (TS-06)
    |
    v
Placement (TS-07)
    |
    v
CTS (TS-08) -- skipped if combinational
    |
    v
Routing (TS-09)
    |
    +-- Filler cells (TS-10)
    +-- SPEF extraction (DF-08)
    +-- DRC summary (DF-04)
    +-- Congestion report (DF-06)
    |
    v
Reports (TS-11 timing, TS-12 power, TS-13 area)
    |
    +-- Timing failure diagnosis (DF-03)
    +-- Cell usage analysis (DF-05)
    |
    v
Export (TS-14 DEF + Verilog)
    |
    v
PnR summary report (TS-18)
    |
    v
Slash command (TS-19)

Parallel/independent:
  - Workspace structure (TS-15) -- created at pipeline start
  - Stage-level error handling (TS-17) -- cross-cutting, built into each script
  - Environment detection (DF-07) -- can be built independently
```

All PnR stages are strictly sequential: each stage requires the previous stage's output in memory (single OpenROAD session). Synthesis must complete before PnR begins. SDC must exist before synthesis.

---

## MVP Recommendation

### Must have for v1.1.2 launch (19 features):

All 19 table stakes features (TS-01 through TS-19). These form the minimal complete pipeline from verified Verilog to DEF + reports. Omitting any single one leaves the pipeline broken or unusable:
- Without SDC (TS-01): synthesis has no timing target
- Without any PnR stage (TS-04 through TS-10): no physical implementation
- Without reports (TS-11 through TS-13): users get artifacts but no insight
- Without error handling (TS-17): failures are silent or cryptic
- Without pre-flight (TS-16): users hit confusing tool-not-found errors deep in the flow

### Include in v1.1.2 (high-value, low-cost differentiators):

1. **DF-01** (spec.json clock enrichment) -- trivial to add during SDC generation, one `grep` of spec.json
2. **DF-02** (combinational auto-detection) -- already designed into the table stakes, costs nothing extra
3. **DF-04** (DRC violation summary) -- simple file parsing, already generated by detailed_route
4. **DF-07** (environment detection) -- extends existing detect-env.sh pattern, needed for pre-flight anyway
5. **DF-08** (SPEF extraction) -- already in the OpenROAD Tcl flow, just do not remove it

### Defer to v1.2+:

- **DF-03** (timing failure diagnosis) -- valuable but requires OpenSTA report parsing logic; add after core flow is stable
- **DF-05** (cell usage analysis) -- nice-to-have, low priority
- **DF-06** (congestion reporting) -- nice-to-have, low priority
- **DF-09** (synthesis auto-retry) -- high complexity, uncertain failure modes; add after observing real synthesis failures in the wild

---

## Phase Structure Recommendation

Based on feature dependencies, the implementation should follow this order:

**Phase 1: Infrastructure** (TS-15, TS-16, DF-07)
- Workspace directory creation (`pnr/results/`, `pnr/reports/`)
- Extend detect-env.sh for Yosys, OpenROAD, nangate45
- Pre-flight validation function
- Rationale: Everything else depends on directories existing and tools being available

**Phase 2: Synthesis Pipeline** (TS-01, TS-02, TS-03, DF-01)
- SDC generation script with clock auto-detection and spec.json enrichment
- Yosys synthesis script with nangate45 liberty
- Synthesis report parsing
- Rationale: Must work before PnR can begin; independently testable with just Yosys

**Phase 3: Place-and-Route Pipeline** (TS-04 through TS-10, TS-14, DF-08)
- Single OpenROAD Tcl script covering floorplan through routing and export
- Combinational/sequential auto-handling (CTS skip)
- SPEF extraction
- DEF + gate-level Verilog export
- Rationale: Single script, single OpenROAD session; test end-to-end with a known module

**Phase 4: Reports and Command** (TS-11 through TS-13, TS-17, TS-18, TS-19, DF-04)
- Report generation (timing, power, area, DRC)
- Stage-level error handling across all scripts
- PnR summary report formatting
- `/chip-agent:pnr` skill definition and orchestration
- Rationale: Reports and the command tie everything together; error handling is best added once the happy path works

---

## Complexity Budget

| Complexity | Count | Features |
|------------|-------|----------|
| Low | 14 | TS-01, TS-03, TS-05, TS-06, TS-10, TS-11, TS-12, TS-13, TS-14, TS-15, TS-16, DF-01, DF-04, DF-08 |
| Medium | 9 | TS-02, TS-04, TS-07, TS-08, TS-09, TS-17, TS-18, TS-19, DF-07 |
| High | 1 | DF-09 (deferred) |

Total estimated effort: comparable to v1.1 Phase 5+6 (workspace isolation + skill decomposition). The OpenROAD Tcl is largely mechanical -- the complexity is in error handling and the synthesis script's interaction with Chisel-generated Verilog quirks.

---

## Sources

- **ORFS GCD example:** Verified locally on nangate45 (2026-03-31) -- all 7 stages produce expected artifacts
- **Existing codebase:** `scripts/compile.sh`, `scripts/simulate.sh`, `scripts/detect-env.sh`, `skills/workflow/SKILL.md`, `agents/requirement-parser.md` -- patterns for script conventions, error handling, and skill structure
- **STACK.md research:** Concurrent research (2026-03-31) with verified tool versions, PDK file inventory, and Tcl script specifications
- **PROJECT.md:** v1.1.2 milestone definition and constraints
- **ASIC design workflow knowledge:** Standard RTL-to-GDS flow stages, SDC conventions, OpenSTA report format (HIGH confidence -- well-established domain)

---
*Feature research for: ChipAgent v1.1.2 -- RTL-to-GDS via Yosys + OpenROAD*
*Researched: 2026-03-31*
