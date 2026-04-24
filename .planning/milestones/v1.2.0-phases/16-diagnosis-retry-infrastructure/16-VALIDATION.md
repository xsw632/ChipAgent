---
phase: 16
slug: diagnosis-retry-infrastructure
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-02
---

# Phase 16 — Validation Strategy

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
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 16-01-01 | 01 | 1 | DIAG-01 | unit | `cd mcp-server && node --test tests/diagnose-failure.test.ts` | ❌ W0 | ⬜ pending |
| 16-01-02 | 01 | 1 | DIAG-02 | unit | `cd mcp-server && node --test tests/diagnose-failure.test.ts` | ❌ W0 | ⬜ pending |
| 16-01-03 | 01 | 1 | RETRY-01 | unit | `cd mcp-server && node --test tests/diagnose-failure.test.ts` | ❌ W0 | ⬜ pending |
| 16-02-01 | 02 | 1 | DIAG-03 | unit | `cd mcp-server && node --test tests/clean-design.test.ts` | ❌ W0 | ⬜ pending |
| 16-02-02 | 02 | 1 | DIAG-04 | unit | `cd mcp-server && node --test tests/generate-config.test.ts` | ✅ (extend) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `mcp-server/tests/diagnose-failure.test.ts` — stubs for DIAG-01, DIAG-02, RETRY-01
- [ ] `mcp-server/tests/clean-design.test.ts` — stubs for DIAG-03
- [ ] Extend `mcp-server/tests/generate-config.test.ts` — new test cases for DIAG-04

*Existing infrastructure (node:test framework, tsconfig.json) covers framework needs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| clean_design actually removes ORFS cached files | DIAG-03 | Requires ORFS installation with real cached artifacts | Run a design through synth, then call clean_design, verify results/ directory is empty |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
