---
phase: 5
slug: workspace-foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-20
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bash scripts (manual verification) |
| **Config file** | none — shell script tests |
| **Quick run command** | `scripts/compile.sh workspace/TrivialModule && ls workspace/TrivialModule/generated/` |
| **Full suite command** | `scripts/compile.sh workspace/TrivialModule && scripts/lint.sh workspace/TrivialModule && scripts/simulate.sh workspace/TrivialModule` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `scripts/compile.sh workspace/TrivialModule && ls workspace/TrivialModule/generated/TrivialModule.v`
- **After every plan wave:** Run full suite: compile + lint + simulate in both workspace and flat modes
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 5-01-01 | 01 | 1 | WKSP-03 | unit | `grep -q 'workspace/' .gitignore` | ❌ W0 | ⬜ pending |
| 5-01-02 | 01 | 1 | WKSP-01 | smoke | `scripts/compile.sh workspace/TrivialModule && test -d workspace/TrivialModule/generated && test -d workspace/TrivialModule/sim/logs` | ❌ W0 | ⬜ pending |
| 5-01-03 | 01 | 1 | WKSP-02 | smoke | `scripts/compile.sh workspace/TrivialModule && scripts/compile.sh` (both must succeed) | ❌ W0 | ⬜ pending |
| 5-02-01 | 02 | 1 | WKSP-02 | smoke | `scripts/lint.sh workspace/TrivialModule && scripts/simulate.sh workspace/TrivialModule` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/test-phase5.sh` — verification script that tests workspace creation, backward compatibility, and gitignore coverage
- [ ] No framework install needed — bash is the test tool

*Existing infrastructure covers test execution; only a verification script is needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `git status` shows no untracked workspace files | WKSP-03 | Requires actual git state | Run `scripts/compile.sh workspace/TrivialModule`, then `git status` — no untracked files under `workspace/` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
