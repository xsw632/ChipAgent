---
phase: 17
slug: retry-orchestration-qor-optimization
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-02
---

# Phase 17 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Node.js built-in `node:test` + `node:assert/strict` |
| **Config file** | None (uses Node.js built-in runner) |
| **Quick run command** | `cd mcp-server && node --test tests/*.test.ts` |
| **Full suite command** | `cd mcp-server && node --test tests/*.test.ts` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd mcp-server && node --test tests/*.test.ts`
- **After every plan wave:** Run `cd mcp-server && node --test tests/*.test.ts`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 17-01-01 | 01 | 1 | QOR-01 | unit | `cd mcp-server && node --test tests/compare-runs.test.ts` | ❌ W0 | ⬜ pending |
| 17-01-02 | 01 | 1 | QOR-03 | unit | `cd mcp-server && node --test tests/compare-runs.test.ts` | ❌ W0 | ⬜ pending |
| 17-02-01 | 02 | 2 | RETRY-02 | manual | N/A -- Skill instructions verified via `/chip-agent:pnr` | N/A | ⬜ pending |
| 17-02-02 | 02 | 2 | RETRY-03 | unit | `cd mcp-server && node --test tests/diagnose-failure.test.ts` | ✅ | ⬜ pending |
| 17-02-03 | 02 | 2 | RETRY-04 | unit | `cd mcp-server && node --test tests/diagnose-failure.test.ts` | ✅ | ⬜ pending |
| 17-02-04 | 02 | 2 | QOR-02 | manual | N/A -- verified by visual inspection | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `mcp-server/tests/compare-runs.test.ts` — stubs for QOR-01, QOR-03

*Existing diagnose-failure tests cover RETRY-03, RETRY-04.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Retry loop runs up to 3 rounds automatically | RETRY-02 | Skill layer LLM orchestration, not testable programmatically | Run `/chip-agent:pnr` on a design with tight clock; observe 3-round retry |
| Comparison table displays correctly | QOR-02 | Output formatting in Skill instructions | Run `/chip-agent:pnr`, verify table has all columns and correct data |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
