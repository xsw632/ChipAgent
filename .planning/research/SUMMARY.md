# Research Summary: ChipAgent v1.2.0 Smart Retry & QoR Optimization

**Domain:** EDA Backend Flow Automation -- error diagnosis, parameter retry, QoR optimization
**Researched:** 2026-04-02
**Overall confidence:** HIGH

## Executive Summary

v1.2.0 adds intelligent failure diagnosis, error-type-based parameter retry, and multi-round QoR optimization to the existing v1.1.5 MCP-driven PnR pipeline. The core architectural decision is to add three new MCP tools (`diagnose_failure`, `clean_stage`, `qor_history`) and extend one existing tool (`generate_config`) while keeping all retry orchestration in the Skill layer. This preserves the existing separation of concerns: MCP tools are stateless data extractors/executors, the Skill (LLM) makes decisions.

The most important finding is that ORFS timing violations are NOT stage failures -- all 6 stages complete successfully even when WNS is negative. The Skill must perform a post-completion check on finish-stage WNS to detect timing violations. This is the most common "failure" mode for small Chisel modules on sky130hd and drives the retry loop design.

Error-type-specific parameter adjustment follows a simple rule-based strategy: timing violations increase clock period by 50%, congestion decreases PLACE_DENSITY by 0.1, DRC decreases PLACE_DENSITY by 0.05, placement overflow decreases CORE_UTILIZATION by 10-15. These adjustments are computed deterministically by the `diagnose_failure` MCP tool and applied by the Skill via `generate_config` with override parameters. No ML, no AutoTuner, no additional dependencies needed.

## Key Findings

**Stack:** No new dependencies. Extend existing MCP server with 3 new tools + modify 1 existing tool. All implemented in TypeScript with existing zod + MCP SDK.

**Architecture:** 3 new MCP tools (`diagnose_failure`, `clean_stage`, `qor_history`), 1 modified tool (`generate_config` with optional `place_density`, `gpl_timing_driven`, `gpl_routability_driven` params). Retry loop lives in Skill, not MCP server.

**Critical pitfall:** Timing violations are silent successes -- ORFS completes all stages, WNS < 0 only visible in finish report. Must check post-completion, not just on stage failure.

## Implications for Roadmap

Based on research, suggested phase structure:

1. **Infrastructure tools (clean_stage + generate_config extension)** - Enables retry mechanics
   - Addresses: Stage cleanup for re-runs, parameter override in config.mk
   - Avoids: Full clean on every retry (saves 30-60s per round)

2. **Diagnosis tool (diagnose_failure)** - Error classification engine
   - Addresses: Automated error type detection from logs/reports/stderr
   - Avoids: LLM parsing raw ORFS logs (token waste, inconsistent results)

3. **QoR persistence (qor_history)** - Run tracking
   - Addresses: Cross-round comparison data storage
   - Avoids: Loss of run data across sessions

4. **Skill retry loop** - Wires everything together
   - Addresses: Automated retry with diagnosis-driven parameter adjustment
   - Avoids: Infinite loops (max 3 rounds), unnecessary re-runs (stage-aware restart)

5. **QoR comparison + report update** - User-facing output
   - Addresses: Multi-round comparison table, best-run recommendation
   - Avoids: Raw data dump (formatted table with highlighted best metrics)

**Phase ordering rationale:**
- Phases 1-3 are independent MCP tools (can be built in parallel)
- Phase 4 depends on all three tool phases
- Phase 5 depends on Phase 4 producing multiple rounds of data

**Research flags for phases:**
- Phase 2 (diagnose_failure): Regex patterns for ORFS errors need validation against actual sky130hd log output. Flag for integration testing.
- Phase 4 (Skill retry loop): Timing violation detection (WNS check after successful completion) is the trickiest part -- must handle both stage failures AND silent violations.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | No new dependencies, extending proven patterns |
| Features | HIGH | task2 requirements explicit, ORFS parameters documented |
| Architecture | HIGH | Clean separation: MCP tools = data, Skill = decisions. Verified against existing code patterns. |
| Pitfalls | HIGH | ORFS error patterns documented in GitHub issues/discussions. Silent timing violation behavior verified from existing get_report code. |

## Gaps to Address

- ORFS error regex patterns need validation against actual sky130hd ALU log output (Phase 2 integration test)
- `GRT-0118` vs `GRT-0119` error codes for congestion -- need to check which code appears on current ORFS version
- Hold violation detection: finish report parsing for hold slack not yet implemented in existing `get_report` -- may need extension
- metadata.json: ORFS generates this at flow end with comprehensive metrics; could be an alternative data source for diagnosis but format needs verification

## Sources

- [ORFS Flow Variables](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/master/docs/user/FlowVariables.md)
- [ORFS Tutorial](https://openroad-flow-scripts.readthedocs.io/en/latest/tutorials/FlowTutorial.html)
- [OpenROAD Timing Discussions](https://github.com/The-OpenROAD-Project/OpenROAD/discussions/3608)
- [OpenROAD DRC Discussions](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/discussions/745)
- [ORFS Adding New Designs](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/master/docs/user/AddingNewDesign.md)
- Existing codebase (verified 2026-04-02): mcp-server/tools/*.ts, skills/pnr/SKILL.md, agents/pnr-report-formatter.md

---

*Research completed: 2026-04-02*
*Ready for roadmap: yes*
