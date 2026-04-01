---
phase: 12
slug: pnr-command-report-integration
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-01
---

# Phase 12 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual skill invocation + bash script verification |
| **Config file** | none — skills are markdown-defined |
| **Quick run command** | `test -f skills/pnr/SKILL.md && test -f agents/pnr-report-formatter.md` |
| **Full suite command** | Manual: invoke `/chip-agent:pnr ALU` and `/chip-agent:pnr Counter8`, verify report output |
| **Estimated runtime** | ~5 seconds (structural checks), ~60 seconds (full invocation) |

---

## Sampling Rate

- **After every task commit:** Run `test -f skills/pnr/SKILL.md && test -f agents/pnr-report-formatter.md`
- **After every plan wave:** Structural checks + grep for key content patterns
- **Before `/gsd:verify-work`:** Full suite must be green (manual invocation of `/chip-agent:pnr ALU`)
- **Max feedback latency:** 5 seconds (structural), 60 seconds (full)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 12-01-01 | 01 | 1 | CMD-01 | unit | `test -f skills/pnr/SKILL.md && grep -q 'synth.sh' skills/pnr/SKILL.md && grep -q 'pnr.sh' skills/pnr/SKILL.md` | ❌ W0 | ⬜ pending |
| 12-01-02 | 01 | 1 | CMD-01 | unit | `grep -q 'generated.*\.v' skills/pnr/SKILL.md` | ❌ W0 | ⬜ pending |
| 12-01-03 | 01 | 1 | CMD-02 | unit | `test -f agents/pnr-report-formatter.md && grep -q 'timing' agents/pnr-report-formatter.md && grep -q 'power' agents/pnr-report-formatter.md` | ❌ W0 | ⬜ pending |
| 12-01-04 | 01 | 1 | CMD-02 | manual | Invoke `/chip-agent:pnr ALU` and visually verify report output | Manual | ⬜ pending |
| 12-01-05 | 01 | 1 | CMD-03 | unit | `grep -q '3' skills/pnr/SKILL.md && grep -q 'retry\|attempt\|auto-fix\|AUTO-FIX' skills/pnr/SKILL.md` | ❌ W0 | ⬜ pending |
| 12-01-06 | 01 | 1 | CMD-03 | unit | `grep -q 'clock.*period\|period.*relax\|period.*increase' skills/pnr/SKILL.md` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `skills/pnr/SKILL.md` — slash command definition (all structural checks depend on this)
- [ ] `agents/pnr-report-formatter.md` — report formatting agent definition
- [ ] `CLAUDE.md` update — add `/chip-agent:pnr` to Commands section

*These are the primary deliverables of Phase 12.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| PnR report renders correctly | CMD-02 | Report format is user-facing markdown produced by Claude following agent rules | Invoke `/chip-agent:pnr ALU`, verify timing/power/area/artifacts sections present with correct values |
| Auto-fix recovers timing violation | CMD-03 | Requires a module with actual timing violation (none in test suite) | Manually create a tight clock constraint, run PnR, verify retry with relaxed period |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
