---
phase: 13
slug: mcp-server-environment-foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-01
---

# Phase 13 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Node.js built-in test runner + bash integration tests |
| **Config file** | none — Wave 0 installs |
| **Quick run command** | `bash scripts/test-phase13.sh` |
| **Full suite command** | `bash scripts/test-phase13.sh` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash scripts/test-phase13.sh`
- **After every plan wave:** Run `bash scripts/test-phase13.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 13-01-01 | 01 | 0 | MCP-01 | integration | `bash scripts/test-phase13.sh mcp-start` | ❌ W0 | ⬜ pending |
| 13-01-02 | 01 | 0 | MCP-02 | integration | `bash scripts/test-phase13.sh check-env` | ❌ W0 | ⬜ pending |
| 13-01-03 | 01 | 0 | ENV-01 | unit | `bash scripts/test-phase13.sh detect-sky130` | ❌ W0 | ⬜ pending |
| 13-01-04 | 01 | 0 | ENV-02 | unit | `bash scripts/test-phase13.sh backend-mode` | ❌ W0 | ⬜ pending |
| 13-01-05 | 01 | 0 | ENV-03 | unit | `bash scripts/test-phase13.sh orfs-path` | ❌ W0 | ⬜ pending |
| 13-01-06 | 01 | 0 | CLN-01 | smoke | `! test -f scripts/synth.tcl` | ❌ W0 | ⬜ pending |
| 13-01-07 | 01 | 0 | CLN-02 | smoke | `grep -q sky130hd CLAUDE.md && ! grep -q nangate45 CLAUDE.md` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/test-phase13.sh` — integration test script covering all requirements
- [ ] `mcp-server/test/check-environment.test.ts` — unit test for environment detection logic

*If none: "Existing infrastructure covers all phase requirements."*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Claude Code discovers MCP tools | MCP-01 | Requires live Claude Code session | Start Claude Code, verify tools listed in /mcp |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
