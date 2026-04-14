---
phase: 18-chipyard-environment-detection
plan: 02
subsystem: infra
tags: [chipyard, riscv, initialize-skill, env-json, capability-flag]

# Dependency graph
requires:
  - phase: 18-01
    provides: Chipyard/RISCV detection in detect-env.sh, chipyard section and can_chipyard in env.json
provides:
  - Initialize skill step 5 includes Chipyard/RISCV status display and install guidance
  - can_chipyard capability documented in user-facing initialize command
  - Chipyard install guidance with GitHub clone URL and ReadTheDocs link
  - RISCV install guidance referencing Chipyard scripts/setup-tools.sh
affects: [19-chipyard-rtl-generation, initialize-skill]

# Tech tracking
tech-stack:
  added: []
  patterns: [capability-documentation-in-skill, install-guidance-links]

key-files:
  created: []
  modified:
    - skills/initialize/SKILL.md

key-decisions:
  - "Install guidance kept brief (one line + link) matching existing tool install entry style"
  - "Can Chipyard uses same display pattern as other capabilities (Can Compile, Can Lint, etc.)"

patterns-established:
  - "Capability flag documentation: prerequisite description in parentheses followed by capability explanation"

requirements-completed: [ENV-01]

# Metrics
duration: 4min
completed: 2026-04-14
---

# Phase 18 Plan 02: Initialize Skill Chipyard/RISCV Status Summary

**Extended initialize skill with Can Chipyard capability flag, Chipyard/RISCV detection in step 2, install guidance with GitHub and ReadTheDocs links, and RISCV setup-tools.sh reference**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-14T09:07:53Z
- **Completed:** 2026-04-14T09:12:23Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Initialize skill step 2 now mentions Chipyard installation and RISCV toolchain detection
- Step 5 capabilities list includes Can Chipyard entry with prerequisites (Chipyard + RISCV toolchain)
- Step 5 install guidance includes Chipyard clone URL (github.com/ucb-bar/chipyard), ReadTheDocs link, and RISCV setup-tools.sh reference
- Output section updated to mention Chipyard and RISCV in env.json description
- All four changes verified against env.json schema -- can_chipyard, chipyard.installed, chipyard.path, chipyard.riscv_installed, chipyard.riscv_path all consistent

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend initialize SKILL.md with Chipyard/RISCV status and install guidance** - `fcb14ff` (feat)
2. **Task 2: Validate end-to-end initialize flow** - verification-only, no code changes

## Files Created/Modified
- `skills/initialize/SKILL.md` - Added Chipyard/RISCV to step 2 description, Can Chipyard capability to step 5, install guidance for Chipyard and RISCV, updated Output section

## Decisions Made
- Install guidance kept brief (one line + link) matching existing tool install entry style
- Can Chipyard follows same display pattern as other capabilities (Can Compile, Can Lint, etc.)
- No Docker-based Chipyard guidance added (deferred per DCK-01/DCK-02)
- No version reporting guidance for Chipyard or RISCV (explicitly deferred)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Initialize skill presents Chipyard/RISCV status to users via /chip-agent:initialize
- Install guidance provides actionable steps when Chipyard or RISCV is missing
- Phase 19 can reference can_chipyard capability and chipyard path from env.json
- SKILL.md descriptions are consistent with env.json schema from Plan 01

---
*Phase: 18-chipyard-environment-detection*
*Completed: 2026-04-14*

## Self-Check: PASSED

- FOUND: skills/initialize/SKILL.md
- FOUND: 18-02-SUMMARY.md
- FOUND: commit fcb14ff
