---
phase: 01-plugin-scaffold-build-foundation
plan: 02
subsystem: infra
tags: [chisel, sbt, scala, systemverilog, build-automation, firtool]

# Dependency graph
requires:
  - phase: 01-01
    provides: Plugin scaffold with directory skeleton, .gitignore, CLAUDE.md conventions
provides:
  - Working sbt project compiling Chisel 7.2.0 to SystemVerilog via firtool
  - compile.sh build automation script with error reporting
  - setup.sh prerequisite checker and dependency pre-download
  - PostToolUse hook for auto-compilation on Scala file writes
  - TrivialModule passthrough as build verification artifact
affects: [02-01, 02-02, 03-01, 04-01]

# Tech tracking
tech-stack:
  added: [chisel-7.2.0, scala-2.13.17, sbt-1.10.7, firtool-auto, circt-stage]
  patterns: [sbt-batch-compilation, chisel-stage-emission, plugin-root-resolution, hook-auto-compile]

key-files:
  created:
    - chisel-project/build.sbt
    - chisel-project/project/build.properties
    - chisel-project/project/plugins.sbt
    - chisel-project/src/main/scala/chipagent/TrivialModule.scala
    - chisel-project/src/main/scala/chipagent/Generate.scala
    - scripts/compile.sh
    - scripts/setup.sh
    - hooks/hooks.json
  modified:
    - CLAUDE.md
    - .gitignore

key-decisions:
  - "Scala version bumped from 2.13.16 to 2.13.17 to satisfy Chisel 7.2.0 transitive scala-library dependency"
  - "compile.sh resolves PLUGIN_ROOT from CLAUDE_PLUGIN_ROOT env var or script location for portability"
  - "setup.sh treats missing Verilator as WARNING (not error) since it is not needed until Phase 3"
  - "Hook matcher restricted to src/main/scala/**/*.scala to avoid infinite loop on generated/ files"

patterns-established:
  - "Build script pattern: PLUGIN_ROOT resolution via CLAUDE_PLUGIN_ROOT or dirname fallback"
  - "sbt invocation pattern: --batch flag, SBT_OPTS=-Dsbt.supershell=false, unset CHISEL_FIRTOOL_PATH"
  - "Chisel emission pattern: ChiselStage.emitSystemVerilogFile with --target-dir and firtool opts"

requirements-completed: [PLUG-05, BUILD-01, BUILD-02, BUILD-03]

# Metrics
duration: 8min
completed: 2026-03-17
---

# Phase 1 Plan 02: sbt/Chisel Build Pipeline Summary

**sbt project compiling Chisel 7.2.0 TrivialModule to SystemVerilog via firtool, with compile.sh automation, setup.sh prerequisites, and PostToolUse auto-compilation hook**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-17T01:50:45Z
- **Completed:** 2026-03-17T01:59:10Z
- **Tasks:** 2
- **Files modified:** 10

## Accomplishments
- sbt project with Chisel 7.2.0 compiles TrivialModule and emits TrivialModule.sv to generated/
- compile.sh wraps full build pipeline with error context reporting (BUILD-03) and .sv output validation
- setup.sh checks java/sbt/verilator prerequisites and pre-downloads dependencies (PLUG-05)
- PostToolUse hook auto-triggers compilation when Scala source files are written or edited (BUILD-02)
- Generate.scala accepts --target-dir argument for flexible output directory configuration

## Task Commits

Each task was committed atomically:

1. **Task 1: Create sbt project with Chisel 7.2.0 and trivial module** - `7fa12e2` (feat)
2. **Task 2: Create compile.sh, setup.sh, and hooks.json with live build verification** - `a5d352b` (feat)

## Files Created/Modified
- `chisel-project/build.sbt` - sbt project with Chisel 7.2.0 dependency and compiler plugin
- `chisel-project/project/build.properties` - Pins sbt version to 1.10.7
- `chisel-project/project/plugins.sbt` - Empty placeholder (compiler plugin in build.sbt)
- `chisel-project/src/main/scala/chipagent/TrivialModule.scala` - 8-bit passthrough module for build verification
- `chisel-project/src/main/scala/chipagent/Generate.scala` - Verilog emission entry point using ChiselStage
- `scripts/compile.sh` - Build automation with error reporting and output validation
- `scripts/setup.sh` - Prerequisite checker and dependency pre-download
- `hooks/hooks.json` - PostToolUse hook for auto-compilation on Scala writes
- `CLAUDE.md` - Updated Scala version from 2.13.16 to 2.13.17 in tech stack
- `.gitignore` - Extended to cover firtool-generated artifacts (filelist.f, verification/)

## Decisions Made
- Scala version bumped from 2.13.16 to 2.13.17: Chisel 7.2.0 pulls scala-library 2.13.17, and SIP-51 backward-only compatibility requires the compiler to match or exceed
- compile.sh resolves PLUGIN_ROOT from CLAUDE_PLUGIN_ROOT env var with dirname fallback for portability across plugin and standalone contexts
- setup.sh treats missing Verilator as a warning rather than error since it is only needed in Phase 3+
- Hook matcher restricted to `*/src/main/scala/**/*.scala` to prevent infinite compilation loops from matching generated output

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Scala version incompatible with Chisel 7.2.0 dependency**
- **Found during:** Task 2 (live compilation test)
- **Issue:** Plan specified scalaVersion 2.13.16 but Chisel 7.2.0 pulls scala-library 2.13.17 via transitive deps. SIP-51 requires compiler version >= library version.
- **Fix:** Updated scalaVersion to 2.13.17 in build.sbt and CLAUDE.md tech stack
- **Files modified:** chisel-project/build.sbt, CLAUDE.md
- **Verification:** Compilation succeeds, TrivialModule.sv emitted
- **Committed in:** a5d352b (Task 2 commit)

**2. [Rule 2 - Missing Critical] gitignore incomplete for firtool build artifacts**
- **Found during:** Task 2 (pre-commit file review)
- **Issue:** .gitignore only covered *.sv and *.v in generated/ but firtool also emits filelist.f and verification/ directory
- **Fix:** Added generated/*.f and generated/verification/ to .gitignore
- **Files modified:** .gitignore
- **Verification:** git check-ignore confirms all generated artifacts are ignored
- **Committed in:** a5d352b (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 bug, 1 missing critical)
**Impact on plan:** Both fixes essential for correct builds. No scope creep.

## Issues Encountered
None beyond the auto-fixed deviations above.

## User Setup Required
None - no external service configuration required. Prerequisites (JDK 17+, sbt) are checked by setup.sh.

## Next Phase Readiness
- Build pipeline fully operational: Chisel source -> sbt compile -> firtool -> SystemVerilog
- Ready for Phase 2 code generation: Generate.scala pattern established for emitting any module
- Hook infrastructure in place for auto-compilation during development
- All scripts executable and tested end-to-end

---
*Phase: 01-plugin-scaffold-build-foundation*
*Completed: 2026-03-17*

## Self-Check: PASSED

All 9 created files verified present. Both task commits (7fa12e2, a5d352b) verified in git log.
