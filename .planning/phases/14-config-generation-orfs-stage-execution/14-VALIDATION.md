---
phase: 14
slug: config-generation-orfs-stage-execution
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-02
---

# Phase 14 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Node.js built-in test runner (node --test) |
| **Config file** | none — Wave 0 installs |
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
| 14-01-01 | 01 | 0 | MCP-03, CFG-01, CFG-02 | unit stub | `node --test mcp-server/tests/generate-config.test.ts` | ❌ W0 | ⬜ pending |
| 14-01-02 | 01 | 0 | MCP-04 | integration stub | `node --test mcp-server/tests/run-stage.test.ts` | ❌ W0 | ⬜ pending |
| 14-01-03 | 01 | 0 | MCP-05 | unit stub | `node --test mcp-server/tests/get-report.test.ts` | ❌ W0 | ⬜ pending |
| 14-01-04 | 01 | 1 | MCP-03, CFG-01 | unit | `node --test mcp-server/tests/generate-config.test.ts` | ❌ W0 | ⬜ pending |
| 14-01-05 | 01 | 1 | CFG-02 | unit | `node --test mcp-server/tests/generate-config.test.ts` | ❌ W0 | ⬜ pending |
| 14-02-01 | 02 | 1 | MCP-04 | integration | `node --test mcp-server/tests/run-stage.test.ts` | ❌ W0 | ⬜ pending |
| 14-02-02 | 02 | 1 | MCP-05 | unit | `node --test mcp-server/tests/get-report.test.ts` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `mcp-server/tests/generate-config.test.ts` — stubs for MCP-03, CFG-01, CFG-02
- [ ] `mcp-server/tests/run-stage.test.ts` — stubs for MCP-04
- [ ] `mcp-server/tests/get-report.test.ts` — stubs for MCP-05
- [ ] Test fixtures: sample Verilog files (sequential + combinational), sample ORFS report files

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| run_stage executes real ORFS make | MCP-04 | Requires Docker + ORFS environment | Run `/chip-agent:pnr ALU8` and verify stage output |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
