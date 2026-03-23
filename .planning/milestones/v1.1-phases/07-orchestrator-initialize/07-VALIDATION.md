---
phase: 7
slug: orchestrator-initialize
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-20
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bash test scripts (project convention from Phases 1-6) |
| **Config file** | none — self-contained scripts |
| **Quick run command** | `bash scripts/test-phase7.sh` |
| **Full suite command** | `bash scripts/test-phase7.sh` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash scripts/test-phase7.sh`
- **After every plan wave:** Run `bash scripts/test-phase7.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 07-01-01 | 01 | 1 | SKILL-06 | smoke | `bash scripts/test-phase7.sh` (checks 1-3) | ❌ W0 | ⬜ pending |
| 07-01-02 | 01 | 1 | SKILL-06 | smoke | `bash scripts/test-phase7.sh` (checks 4-5) | ❌ W0 | ⬜ pending |
| 07-02-01 | 02 | 1 | INIT-01 | smoke | `bash scripts/test-phase7.sh` (check 6) | ❌ W0 | ⬜ pending |
| 07-02-02 | 02 | 1 | INIT-01 | unit | `bash scripts/test-phase7.sh` (checks 7-8) | ❌ W0 | ⬜ pending |
| 07-02-03 | 02 | 1 | INIT-02 | unit | `bash scripts/test-phase7.sh` (checks 9-11) | ❌ W0 | ⬜ pending |
| 07-02-04 | 02 | 1 | INIT-03 | smoke | `bash scripts/test-phase7.sh` (check 12) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/test-phase7.sh` — structural verification for orchestrator + initialize
- [ ] `scripts/detect-env.sh` — environment detection script producing JSON
- [ ] `.chipagent/` added to `.gitignore`

*Wave 0 creates test infrastructure and detection scripts before main plan execution.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Full pipeline E2E via `/chip-agent:generate` | SKILL-06 | Requires interactive Claude Code session with hardware prompt | Run `/chip-agent:generate "4-bit adder"` and verify complete pipeline produces simulation results |
| `/chip-agent:initialize` updates CLAUDE.md | INIT-03 | Requires Claude's Edit tool in interactive session | Run `/chip-agent:initialize` and verify Tech Stack table versions match `env.json` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
