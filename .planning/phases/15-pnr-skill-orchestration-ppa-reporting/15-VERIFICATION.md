---
phase: 15-pnr-skill-orchestration-ppa-reporting
verified: 2026-04-02T05:10:00Z
status: passed
score: 7/7 must-haves verified
---

# Phase 15: PnR Skill Orchestration + PPA Reporting Verification Report

**Phase Goal:** Users invoke `/chip-agent:pnr` and get a complete ORFS-driven backend flow with formatted PPA summary report
**Verified:** 2026-04-02T05:10:00Z
**Status:** passed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | get_report returns power metrics when stage is finish | VERIFIED | `parsePower` exported at line 33 of get-report.ts, called in handler at line 95 for finish stage |
| 2 | get_report returns synthesis area when stage is synth | VERIFIED | `parseSynthArea` exported at line 53, called in handler at line 93 for synth stage |
| 3 | All existing parser tests still pass after enhancement | VERIFIED | 12/12 tests pass (8 existing + 4 new) |
| 4 | Skill calls MCP tools instead of synth.sh/pnr.sh scripts | VERIFIED | SKILL.md references all 4 MCP tools (check_environment, generate_config, run_stage, get_report) in allowed-tools and pipeline steps |
| 5 | Skill sequences 6 ORFS stages in order | VERIFIED | Step 3 lists synth, floorplan, place, cts, route, finish in order |
| 6 | Skill presents per-stage metrics after each stage | VERIFIED | Step 3 metric display table covers all 6 stages with specific format strings |
| 7 | Skill produces formatted PPA summary with timing, power, and area | VERIFIED | Step 4 invokes pnr-report-formatter agent; agent template includes Timing/Power/Area/DRC/Artifacts sections |

**Score:** 7/7 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `mcp-server/tools/get-report.ts` | parsePower and parseSynthArea functions + handler integration | VERIFIED | Both exported, both called in handler |
| `mcp-server/tests/get-report.test.ts` | Tests for power and area parsing | VERIFIED | 4 new tests (happy + missing-data for each) |
| `skills/pnr/SKILL.md` | MCP-based PnR orchestration skill | VERIFIED | 176 lines, 5-step pipeline, 4 MCP tools |
| `agents/pnr-report-formatter.md` | PPA report formatter accepting structured metrics | VERIFIED | 116 lines, metrics input table, report template with power in uW |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| get-report.ts | registerGetReport handler | parsePower called for 6_finish.rpt | WIRED | Line 95: `Object.assign(metrics, parseFinishReport(content), parsePower(content))` |
| get-report.ts | registerGetReport handler | parseSynthArea called for synth_stat.txt | WIRED | Line 93: `Object.assign(metrics, parseSynthStat(content), parseSynthArea(content))` |
| skills/pnr/SKILL.md | check_environment | MCP tool in Step 1 | WIRED | Referenced in allowed-tools and Step 1 instructions |
| skills/pnr/SKILL.md | generate_config | MCP tool in Step 2 | WIRED | Referenced in allowed-tools and Step 2 instructions |
| skills/pnr/SKILL.md | run_stage | MCP tool in Step 3 loop | WIRED | Referenced in allowed-tools and Step 3 instructions |
| skills/pnr/SKILL.md | get_report | MCP tool after each stage | WIRED | Referenced in allowed-tools and Step 3 instructions |
| skills/pnr/SKILL.md | pnr-report-formatter agent | Agent invocation in Step 4 | WIRED | Step 4 reads agents/pnr-report-formatter.md |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| FLOW-01 | 15-02 | Skill rewritten to orchestrate via MCP tools | SATISFIED | SKILL.md calls 4 MCP tools, no synth.sh/pnr.sh references |
| FLOW-02 | 15-02 | Skill auto-advances through 6 ORFS stages sequentially | SATISFIED | Step 3 loops through synth, floorplan, place, cts, route, finish |
| FLOW-03 | 15-01, 15-02 | Per-stage metric extraction | SATISFIED | parsePower/parseSynthArea in get-report.ts + per-stage display in SKILL.md |
| RPT-01 | 15-01, 15-02 | PPA summary report with timing, power, area | SATISFIED | Report template in pnr-report-formatter.md includes all PPA sections |

### Anti-Patterns Found

None found. No TODO/FIXME/PLACEHOLDER comments in any modified files.

### Human Verification Required

### 1. End-to-End PnR Flow

**Test:** Run `/chip-agent:pnr ALU8` on a machine with ORFS and sky130hd installed
**Expected:** All 6 stages complete with per-stage metrics displayed, followed by formatted PPA summary report
**Why human:** Requires actual ORFS installation and runtime execution

---

_Verified: 2026-04-02T05:10:00Z_
_Verifier: Claude (gsd-verifier)_
