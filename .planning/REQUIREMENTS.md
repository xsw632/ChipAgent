# Requirements: ChipAgent v1.2.0

**Defined:** 2026-04-02
**Core Value:** A single slash command turns a natural language hardware description into lint-clean, simulation-verified Verilog — and a second command extends it through synthesis, PnR, and GDS export with intelligent failure diagnosis, automatic parameter retry, and multi-round QoR optimization.

## v1.2.0 Requirements

Requirements for 满分要求 tier. Each maps to roadmap phases.

### Error Diagnosis

- [x] **DIAG-01**: Agent auto-classifies flow failures into error types (timing_violation, congestion, drc, placement_overflow, synthesis_error) from ORFS logs, reports, and stderr
- [x] **DIAG-02**: Agent detects "silent" timing violations where all stages succeed but WNS < 0 in finish report
- [x] **DIAG-03**: New `clean_design` MCP tool runs `make clean_all` to reset ORFS cached artifacts before retry
- [x] **DIAG-04**: Existing `generate_config` MCP tool extended with optional tuning parameters (place_density, gpl_timing_driven, gpl_routability_driven)

### Parameter Retry

- [x] **RETRY-01**: New `diagnose_failure` MCP tool parses ORFS output and returns structured error classification with suggested parameter adjustments
- [ ] **RETRY-02**: PnR skill implements retry loop: diagnose failure → adjust parameters → clean → regenerate config → re-run (max 3 rounds)
- [ ] **RETRY-03**: Retry adjusts parameters based on error type: timing → increase clock_period, congestion → decrease place_density, placement overflow → decrease core_utilization
- [ ] **RETRY-04**: Retry uses stage-aware restart: only re-run from the earliest affected stage (skip synth when only placement params change)

### QoR Optimization

- [x] **QOR-01**: New `compare_runs` MCP tool saves and retrieves run configs+metrics as JSON in workspace (qor_history.json)
- [ ] **QOR-02**: After all retry rounds, PnR skill displays comparison table with per-run config, metrics, and status
- [x] **QOR-03**: Agent recommends best run: tightest clock period that meets timing (WNS >= 0) with zero DRC violations

## Future Requirements

Deferred beyond v1.2.0. Tracked but not in current roadmap.

### Advanced Optimization

- **OPT-01**: Pareto-optimal run selection across power/performance/area tradeoff space
- **OPT-02**: metadata.json extraction as alternative/fallback data source for metrics
- **OPT-03**: Congestion heatmap visualization reference in reports
- **OPT-04**: Docker mode support for ORFS execution

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| AutoTuner / Ray Tune integration | Heavy ML framework, overkill for rule-based retry on small designs |
| RTL modification for timing closure | Crosses RTL/backend boundary, outside PnR scope |
| Multi-corner STA | Single typical corner sufficient per PROJECT.md |
| Parallel multi-config exploration | Sequential retry is simpler and sufficient |
| User-interactive parameter selection | Breaks "no human in the loop" automation principle |
| Exhaustive parameter sweep | Combinatorial explosion (27+ runs); error-directed adjustment is targeted |
| Custom Tcl script injection | Breaks ORFS make flow abstraction |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| DIAG-01 | Phase 16 | Complete |
| DIAG-02 | Phase 16 | Complete |
| DIAG-03 | Phase 16 | Complete |
| DIAG-04 | Phase 16 | Complete |
| RETRY-01 | Phase 16 | Complete |
| RETRY-02 | Phase 17 | Pending |
| RETRY-03 | Phase 17 | Pending |
| RETRY-04 | Phase 17 | Pending |
| QOR-01 | Phase 17 | Complete |
| QOR-02 | Phase 17 | Pending |
| QOR-03 | Phase 17 | Complete |

**Coverage:**
- v1.2.0 requirements: 11 total
- Mapped to phases: 11
- Unmapped: 0

---
*Requirements defined: 2026-04-02*
*Last updated: 2026-04-02 after roadmap creation*
