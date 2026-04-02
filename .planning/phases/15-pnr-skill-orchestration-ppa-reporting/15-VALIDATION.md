---
phase: 15
slug: pnr-skill-orchestration-ppa-reporting
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-02
---

# Phase 15 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Node.js built-in test runner (node --test) |
| **Config file** | none |
| **Quick run command** | `node --test mcp-server/tests/*.test.ts` |
| **Full suite command** | `node --test mcp-server/tests/*.test.ts` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `node --test mcp-server/tests/*.test.ts`
- **After every plan wave:** Run `node --test mcp-server/tests/*.test.ts`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 15-01-01 | 01 | 1 | FLOW-03 | unit | `node --test mcp-server/tests/get-report.test.ts` | Yes (update needed) | ⬜ pending |
| 15-01-02 | 01 | 1 | RPT-01 | unit | `node --test mcp-server/tests/get-report.test.ts` | Yes (update needed) | ⬜ pending |
| 15-02-01 | 02 | 1 | FLOW-01 | manual | Invoke `/chip-agent:pnr ALU8` and verify no synth.sh/pnr.sh calls | manual-only | ⬜ pending |
| 15-02-02 | 02 | 1 | FLOW-02 | manual | Invoke `/chip-agent:pnr ALU8` and verify all 6 stages run | manual-only | ⬜ pending |
| 15-02-03 | 02 | 1 | RPT-01 | manual | Invoke `/chip-agent:pnr ALU8` and verify PPA summary report | manual-only | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `mcp-server/tests/get-report.test.ts` — add tests for power parsing (parsePower) and synthesis area parsing (parseSynthArea)
- [ ] Test fixtures: sample 6_finish.rpt with report_power section, sample synth_stat.txt with Chip area line

*Existing test infrastructure covers framework setup.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Skill uses MCP tools not scripts | FLOW-01 | Skills are markdown files instructing Claude — cannot be unit-tested | Invoke `/chip-agent:pnr ALU8`, verify no synth.sh/pnr.sh calls in output |
| Sequential 6-stage execution | FLOW-02 | Requires full skill invocation to validate orchestration flow | Invoke `/chip-agent:pnr ALU8`, verify all 6 stages run sequentially |
| PPA summary after final stage | RPT-01 | Report formatting is part of skill presentation layer | Invoke `/chip-agent:pnr ALU8`, verify formatted PPA summary appears |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
