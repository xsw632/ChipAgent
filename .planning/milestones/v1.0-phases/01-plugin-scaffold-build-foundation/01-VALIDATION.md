---
phase: 1
slug: plugin-scaffold-build-foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-16
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Shell scripts + sbt compilation (no unit test framework needed for Phase 1) |
| **Config file** | none — build.sbt is the config |
| **Quick run command** | `scripts/compile.sh` |
| **Full suite command** | `scripts/compile.sh && test -f generated/TrivialModule.sv` |
| **Estimated runtime** | ~30 seconds (after first run) |

---

## Sampling Rate

- **After every task commit:** Run `scripts/compile.sh`
- **After every plan wave:** Run `scripts/compile.sh && test -f generated/TrivialModule.sv`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 1-01-01 | 01 | 1 | PLUG-01 | manual | `test -f .claude-plugin/plugin.json` | ❌ W0 | ⬜ pending |
| 1-01-02 | 01 | 1 | PLUG-02 | manual | `grep "chip-agent:generate" skills/*.md` | ❌ W0 | ⬜ pending |
| 1-01-03 | 01 | 1 | PLUG-04 | manual | `test -f CLAUDE.md` | ❌ W0 | ⬜ pending |
| 1-01-04 | 01 | 1 | PLUG-03 | manual | `test -f package.json && node -e "require('./package.json')"` | ❌ W0 | ⬜ pending |
| 1-02-01 | 02 | 1 | BUILD-01 | script | `scripts/compile.sh` | ❌ W0 | ⬜ pending |
| 1-02-02 | 02 | 1 | BUILD-02 | manual | Verify hook triggers compilation on .scala write | ❌ W0 | ⬜ pending |
| 1-02-03 | 02 | 1 | BUILD-03 | script | Introduce error in .scala, run compile.sh, check stderr | ❌ W0 | ⬜ pending |
| 1-02-04 | 02 | 1 | PLUG-05 | script | `scripts/setup.sh && test -d chisel-project` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/compile.sh` — build automation entry point
- [ ] `scripts/setup.sh` — first-use initialization
- [ ] `.claude-plugin/plugin.json` — plugin manifest
- [ ] `chisel-project/build.sbt` — sbt project configuration

*Existing infrastructure: None — this is the first phase, everything is built from scratch.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Plugin loads in Claude Code | PLUG-01, PLUG-02 | Requires Claude Code runtime | Run `claude --plugin-dir .` and check `/chip-agent:generate` appears |
| Hook triggers auto-compile | BUILD-02 | Requires Claude Code hook runtime | Write a .scala file via Claude, verify compile.sh runs |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
