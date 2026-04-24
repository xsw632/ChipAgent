# Retrospective

## Milestone: v1.2.0 — Smart Retry & QoR Optimization

**Shipped:** 2026-04-02
**Phases:** 2 | **Plans:** 4

### What Was Built
- diagnose_failure MCP tool classifying 5 ORFS error types with bounded parameter suggestions and restart-from stage mapping
- clean_design MCP tool wrapping make clean_all with 30s timeout for ORFS cache reset
- generate_config extended with placeDensity, gplTimingDriven, gplRoutabilityDriven tuning parameters
- compare_runs MCP tool with JSON persistence (qor_history.json), save/load/recommend/clear actions, deterministic best-run selection
- PnR skill rewritten with 3-round retry loop, stage-aware restart, QoR comparison table, and best-run recommendation

### What Worked
- Pure function extraction (classifyError, suggestParams, buildCleanArgs, recommendBest) made each tool independently testable -- 47 new tests with zero regressions
- Error classification priority chain handled overlapping patterns cleanly (synthesis_error checked first, unknown as fallback)
- Deterministic best-run selection (filter+sort) rather than LLM judgment made recommendation reliable and predictable
- Skill-layer retry orchestration kept MCP tools simple and composable -- each tool does one thing
- Mutable param accumulation across retry rounds prevented parameter drift without complex state management

### What Was Inefficient
- ROADMAP.md progress table still had column misalignment (phases 16-17 milestone column was missing)
- No end-to-end testing against actual ORFS installation -- regex patterns for error classification are untested against real sky130hd logs

### Patterns Established
- Error classification via regex priority chain with structured return type (DiagnosisResult)
- Parameter suggestion with min/max clamping to prevent unreasonable values
- Stage-aware restart via STAGE_ORDER array slicing from diagnosis restart_from
- QoR comparison table as standard post-pipeline output format
- Read-append-write pattern for atomic JSON persistence (qor_history.json)
- Retry orchestration in Skill layer (diagnose -> clean -> regenerate -> re-run)

### Key Lessons
1. Tool composability pays off: 3 new MCP tools + 1 extension enabled a complete retry loop with minimal skill-layer code
2. Deterministic algorithms (filter+sort) are preferable to LLM judgment for selection tasks where criteria are well-defined
3. Flat file JSON is sufficient for small datasets (<10 runs) -- no need for SQLite or database dependencies
4. Critical error classification (abort immediately for synthesis/combinational timing) saves retry rounds from being wasted

### Cost Observations
- Sessions: ~2
- Notable: 4 plans in a single day; fastest milestone per plan (avg ~5min/plan for implementation)

---

## Milestone: v1.1.2 — RTL-to-GDS

**Shipped:** 2026-04-01
**Phases:** 4 | **Plans:** 5

### What Was Built
- nangate45 PDK auto-detection and pre-flight validation (5 required PDK files)
- SDC auto-generation classifying modules as sequential or combinational from Verilog analysis
- Yosys ASIC synthesis pipeline (Tcl recipe + bash wrapper) producing gate-level netlists
- OpenROAD PnR flow with auto-die-sizing, conditional CTS skip, and KLayout GDS export
- `/chip-agent:pnr` slash command with formatted timing/power/area report and timing auto-fix retry

### What Worked
- Two-file architecture (bash wrapper + Tcl recipe) for synth.sh and pnr.sh kept concerns clean — bash handles paths/validation, Tcl handles tool logic
- Marker-based report extraction from OpenROAD `-log` output reliably captured timing/power/area sections
- Conditional CTS skip (IS_SEQUENTIAL flag) correctly handled both ALU (combinational) and Counter8 (sequential)
- Auto-die-sizing heuristic (<100 cells → 70x70um, ≥100 cells → 30% utilization) worked for all test modules
- Research phase identifying report file formats upfront (timing.rpt, power.rpt, area.rpt patterns) prevented parsing rework

### What Was Inefficient
- Phase 9 plan checkboxes (09-01, 09-02) and Phase 11 (11-01) still showed `[ ]` in ROADMAP.md despite completion — checkbox sync remains a persistent issue
- Progress table formatting drifted across phases (some rows missing milestone column, inconsistent column alignment)

### Patterns Established
- PnR output convention: `workspace/pnr/` for artifacts, `workspace/pnr/reports/` for report files
- Three-file architecture for PnR: pnr.sh (bash), pnr.tcl (OpenROAD), def2gds.py (KLayout)
- Auto-fix retry: 50% clock period increase per attempt, max 3 attempts, re-run both synth and PnR
- No synthesis retry in PnR command — synthesis failures require RTL changes
- Power always reported in microwatts (uW), never raw Watts

### Key Lessons
1. ROADMAP checkbox sync is still the #1 process debt — plan completion should auto-update the `[ ]` to `[x]`
2. Standalone scripts (not ORFS Makefile) proved correct for portability — no ORFS installation dependency
3. Yosys Tcl mode requires `yosys` prefix on all commands — discovered during Phase 10, would have been caught by research if Yosys Tcl docs were checked more carefully
4. KLayout LEF loading uses `layoutOptions` (not `.lyt` tech files) — important for future PDK support

### Cost Observations
- Sessions: ~2
- Notable: 5 plans across 4 phases in 2 days; smaller plans (1 plan per phase for 10-12) executed faster than multi-plan phases

---

## Milestone: v1.1 — Refine

**Shipped:** 2026-03-23
**Phases:** 4 | **Plans:** 8

### What Was Built
- Per-module workspace isolation (`workspace/<Module>/`) with compile, lint, simulate scripts accepting workspace paths
- Five modular slash commands decomposing the monolithic pipeline into standalone stages
- Refactored `/chip-agent:generate` orchestrator wiring sub-skills with workspace-aware paths
- Environment detection (`/chip-agent:initialize`) producing `.chipagent/env.json` with tool versions and capability flags
- VCD waveform trace generation integrated into simulation pipeline
- `/chip-agent:debug` command with Python VCD parser and debug-analyzer agent

### What Worked
- Spec-file communication (Option C) cleanly decoupled pipeline stages from conversation context
- Runtime plugin root detection via `.claude-plugin/plugin.json` ancestor search solved env var interpolation issues
- Single-responsibility skill design (compile ≠ lint ≠ simulate) made orchestrator composition straightforward
- Removing PostToolUse hook eliminated spurious sbt compilations and infinite loop risk
- Python stdlib-only VCD parser ensured zero-install portability

### What Was Inefficient
- ROADMAP.md plan checkboxes still fell out of sync (phases 5, 6, 8 showed `[ ]` despite having SUMMARY files)
- REQUIREMENTS.md traceability table showed "In Progress" for WKSP-01/02 despite being complete in the checkbox list
- Phase 7 Plan 01 took 34min (outlier) due to PostToolUse hook removal requiring careful analysis of hook interactions

### Patterns Established
- Workspace convention: `workspace/<Module>/generated/`, `workspace/<Module>/sim/logs/`
- Script backward compatibility: no args = v1.0 flat mode, positional arg = workspace mode
- Agent-backed skills: skill handles file I/O that agent cannot do directly
- Waiver file fallback chain: per-module → global → empty
- VCD lifecycle: traceEverOn → trace(tfp,99) → open → dump per eval → close

### Key Lessons
- Traceability tracking remains the weakest part of the workflow — plan/requirement checkboxes drift
- PostToolUse hooks with broad triggers are dangerous in automated pipelines (removed, not fixed)
- jq-with-heredoc-fallback is a reliable portable JSON assembly pattern

### Cost Observations
- Sessions: ~3
- Notable: All 8 plans executed in a single day (2026-03-20); 77 min total execution

---

## Milestone: v1.0 — MVP

**Shipped:** 2026-03-18
**Phases:** 4 | **Plans:** 9

### What Was Built
- Claude Code plugin scaffold with `/chip-agent:generate` slash command
- sbt/Chisel build pipeline compiling to SystemVerilog via FIRRTL/firtool
- NL-to-Chisel subagents (requirement-parser + chisel-generator) with JSON spec contract
- Verilator lint script with waiver files and 3-attempt auto-fix loop
- C++ testbench generation and simulation with formatted verification reports
- End-to-end acceptance test: ALU with 6 operations passing all 12 test cases

### What Worked
- Coarse 4-phase structure kept planning overhead low while covering all 30 requirements
- JSON spec as inter-agent contract gave clean separation between parser and generator
- Per-file linting pattern avoided Verilator MULTITOP issues
- Skill-orchestrated lint (instead of hooks) prevented infinite loop problems
- Waiver file approach for Chisel-generated clock/reset warnings

### What Was Inefficient
- PLUG-01 through PLUG-04 requirements were delivered but never checked off in traceability table
- Phase 3 plan checkboxes in ROADMAP.md were not updated despite summaries existing
- Phase 4 progress row showed "0/2 Not started" even after completion

### Patterns Established
- Combinational modules use single eval() call, no clock cycling
- Testbenches use struct array pattern for test cases
- simulate.sh passes waiver file to Verilator during verilation
- Pipeline stages follow 3-attempt auto-fix pattern consistently

### Key Lessons
- Keep traceability table in sync with actual completion status
- Update ROADMAP progress table as part of plan completion workflow
- Waiver files are essential for Chisel-generated Verilog (clock/reset warnings are ubiquitous)

### Cost Observations
- Sessions: ~5
- Notable: Fast execution — 2 days from project init to full pipeline working
