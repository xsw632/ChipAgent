---
phase: 18
slug: chipyard-environment-detection
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-14
---

# Phase 18 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash + jq (no test framework — bash scripts) |
| **Config file** | none |
| **Quick run command** | `bash scripts/detect-env.sh 2>&1` |
| **Full suite command** | `bash scripts/detect-env.sh && cat .chipagent/env.json | jq .chipyard && cat .chipagent/env.json | jq .capabilities.can_chipyard` |
| **Estimated runtime** | ~2 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash scripts/detect-env.sh`
- **After every plan wave:** Verify env.json contains chipyard section
- **Before `/gsd-verify-work`:** Full detection output correct
- **Max feedback latency:** 2 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 18-01-01 | 01 | 1 | ENV-03 | — | N/A | manual | `grep -c 'CHIPYARD' scripts/detect-env.sh` | ❌ W0 | ⬜ pending |
| 18-01-02 | 01 | 1 | ENV-03 | — | N/A | manual | `grep -c 'RISCV' scripts/detect-env.sh` | ❌ W0 | ⬜ pending |
| 18-02-01 | 02 | 1 | ENV-01, ENV-02 | — | N/A | manual | `grep -c 'can_chipyard' scripts/detect-env.sh` | ❌ W0 | ⬜ pending |
| 18-02-02 | 02 | 1 | ENV-01 | — | N/A | manual | `grep -c 'chipyard' skills/initialize/SKILL.md` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements. No new test framework needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Chipyard detection writes can_chipyard: true | ENV-01 | Requires actual Chipyard installation | 1. Run `/chip-agent:initialize` on machine with Chipyard 2. Check `.chipagent/env.json` has `chipyard.installed: true` and `capabilities.can_chipyard: true` |
| Missing Chipyard writes can_chipyard: false without errors | ENV-02 | Requires environment without Chipyard | 1. Set `CHIPYARD_DIR=/nonexistent` 2. Run `detect-env.sh` 3. Verify no errors and `can_chipyard: false` |
| RISCV toolchain detection | ENV-03 | Requires actual RISCV installation | 1. Run `detect-env.sh` 2. Check env.json has `chipyard.riscv_installed` field with correct path |

---

## Validation Sign-Off

- [x] All tasks have verification mapped
- [x] Sampling continuity: no 3 consecutive tasks without verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
