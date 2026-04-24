# Phase 19: Chipyard RTL Generation Command - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-14
**Phase:** 19-chipyard-rtl-generation-command
**Areas discussed:** User entry and skill reuse, flow shape and handoff, SRAM mapping integration

---

## User entry and skill reuse

| Option | Description | Selected |
|--------|-------------|----------|
| Separate `/chip-agent:chipyard-rtl` primary UX | Users run RTL generation directly, then other commands manually | |
| Unified `/chip-agent:chipyard` orchestrator | One user command orchestrates generation, SRAM mapping, and handoff | ✓ |
| Separate SRAM mapping top-level flow | Users run a second top-level command after generation | |

**User's choice:** Use `/chip-agent:chipyard tinyrocket` as the roadmap UX.
**Notes:** Existing `chipyard-rtl` and `sram-mapping` skills should be reused internally instead of becoming the main user-facing flow.

---

## Flow shape and handoff

| Option | Description | Selected |
|--------|-------------|----------|
| Generate RTL only, manual staging later | User organizes artifacts before PnR | |
| Integrated generate → map → stage flow | Chipyard flow produces staged `MyDesign/<Config>/workspace/` artifacts automatically | ✓ |
| Keep outputs in Chipyard tree only | Downstream steps read directly from Chipyard generated-src paths | |

**User's choice:** Automatically move/copy relevant Chipyard artifacts into `MyDesign` before PnR.
**Notes:** The staged MyDesign workspace should become the canonical downstream location.

---

## SRAM mapping integration

| Option | Description | Selected |
|--------|-------------|----------|
| Separate user-invoked SRAM mapping command | User manually runs mapping after generation | |
| Internal pipeline step in `/chip-agent:chipyard` | Mapping runs automatically after RTL generation | ✓ |
| Defer mapping entirely to later phases | No mapping in initial Chipyard flow | |

**User's choice:** SRAM mapping should run automatically inside `/chip-agent:chipyard`.
**Notes:** Phase 20 should refine this same integrated flow rather than introducing another top-level UX.

---

## Claude's Discretion

- Internal implementation structure between orchestrating skill and reused helper skills.
- Exact staged file layout beyond the required downstream compatibility points.
- Progress display format during long Chipyard generation.

## Deferred Ideas

- Promoting `chipyard-rtl` to the main end-user command.
- Requiring users to separately run `sram-mapping` as part of the normal roadmap flow.
