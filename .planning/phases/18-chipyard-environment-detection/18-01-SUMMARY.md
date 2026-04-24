---
phase: 18-chipyard-environment-detection
plan: 01
subsystem: infra
tags: [chipyard, riscv, environment-detection, bash, jq]

# Dependency graph
requires: []
provides:
  - Chipyard directory detection via build.sbt + generators/chipyard/src/main/scala markers
  - RISCV toolchain detection via riscv64-unknown-elf-gcc binary presence
  - can_chipyard capability flag in env.json
  - chipyard section in env.json (installed, path, riscv_installed, riscv_path)
affects: [19-chipyard-rtl-generation, initialize-skill]

# Tech tracking
tech-stack:
  added: []
  patterns: [candidate-directory-chain, empty-string-guard, bash-parameter-expansion-for-conditional-candidates]

key-files:
  created: []
  modified:
    - scripts/detect-env.sh

key-decisions:
  - "build.sbt + generators/chipyard/src/main/scala as Chipyard markers (verified on real installation)"
  - "RISCV candidates reference CHIPYARD_DIR_DETECTED via bash parameter expansion for conditional inclusion"
  - "$HOME/Desktop/chipyard included as candidate (actual install location on this machine)"

patterns-established:
  - "Candidate directory chain pattern: env override -> common locations -> /opt fallback"
  - "Conditional candidate via ${VAR:+path} expansion: skips when dependency not found"

requirements-completed: [ENV-02, ENV-03]

# Metrics
duration: 8min
completed: 2026-04-14
---

# Phase 18 Plan 01: Chipyard + RISCV Environment Detection Summary

**Extended detect-env.sh with Chipyard build.sbt directory detection, RISCV riscv64-unknown-elf-gcc toolchain detection, can_chipyard capability flag, and chipyard section in env.json output**

## Performance

- **Duration:** 8 min
- **Started:** 2026-04-14T08:55:25Z
- **Completed:** 2026-04-14T09:03:38Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Chipyard detection finds installation at ~/Desktop/chipyard via build.sbt + generators/chipyard/src/main/scala markers
- RISCV detection finds toolchain at ~/Desktop/chipyard/.conda-env/riscv-tools via riscv64-unknown-elf-gcc binary
- can_chipyard=true when both Chipyard AND RISCV present, false otherwise
- env.json now includes chipyard section (installed, path, riscv_installed, riscv_path) and can_chipyard in capabilities
- Stdout summary shows Chipyard and RISCV lines with [OK]/[MISSING] pattern
- All existing env.json fields remain unchanged (can_compile, can_lint, can_simulate, can_synthesize, can_pnr, can_gds)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Chipyard and RISCV detection blocks to detect-env.sh** - `005f6f9` (feat)
2. **Task 2: Verify detection with both present and absent scenarios** - verification-only, no code changes

## Files Created/Modified
- `scripts/detect-env.sh` - Added Chipyard detection block, RISCV detection block, can_chipyard capability flag, chipyard section in jq/heredoc JSON output, Chipyard/RISCV stdout summary lines

## Decisions Made
- Used build.sbt + generators/chipyard/src/main/scala as Chipyard markers (NOT generators/src/main/scala which does not exist on real installations)
- RISCV detection placed after Chipyard detection because candidates reference $CHIPYARD_DIR_DETECTED via bash parameter expansion
- $HOME/Desktop/chipyard included as candidate (actual install location per skills/chipyard-rtl/SKILL.md default)
- Verification-only task (Task 2) required no commit since no code changes were needed

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- CHIPYARD_DIR=/nonexistent env override alone does not simulate absent Chipyard because $HOME/Desktop/chipyard is a later candidate that still matches. Used HOME=/tmp/testabsent to fully test the absent scenario. This is expected behavior -- the candidate chain is designed to find Chipyard at any valid location.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- env.json now provides chipyard section and can_chipyard capability for Phase 19 (/chip-agent:chipyard) to gate Chipyard RTL generation
- detect-env.sh is ready for the initialize skill to consume chipyard path and can_chipyard flag
- All existing capabilities and detection blocks remain functional and unchanged

---
*Phase: 18-chipyard-environment-detection*
*Completed: 2026-04-14*

## Self-Check: PASSED

- FOUND: scripts/detect-env.sh
- FOUND: 18-01-SUMMARY.md
- FOUND: commit 005f6f9
