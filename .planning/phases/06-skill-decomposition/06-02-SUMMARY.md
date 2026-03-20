---
phase: 06-skill-decomposition
plan: 02
subsystem: plugin
tags: [claude-code-skills, slash-commands, spec-json, requirement-parser, testbench, verilator]

requires:
  - phase: 06-skill-decomposition
    provides: Script-wrapper skills (compile, lint, simulate) and test-phase6.sh scaffold
provides:
  - /chip-agent:requirement-parser slash command (skills/requirement-parser/SKILL.md)
  - /chip-agent:testbench slash command (skills/testbench/SKILL.md)
  - Complete Phase 6 structural verification (12 checks in test-phase6.sh)
affects: [07-orchestrator]

tech-stack:
  added: []
  patterns: [agent-backed skill pattern, spec-file communication via workspace/<Module>/spec.json]

key-files:
  created:
    - skills/requirement-parser/SKILL.md
    - skills/testbench/SKILL.md
  modified:
    - scripts/test-phase6.sh

key-decisions:
  - "Requirement-parser skill explicitly writes spec.json to disk (agent returns JSON to conversation only)"
  - "Testbench skill reads spec.json from workspace disk path, enabling standalone invocation without conversation context"
  - "Testbench output path overridden to workspace/<Module>/sim/ (not flat-mode sim/ default)"

patterns-established:
  - "Agent-backed skill: skill reads agent definition from agents/, follows instructions, handles file I/O that agent cannot"
  - "Spec-file communication: requirement-parser writes workspace/<Module>/spec.json, testbench reads it"

requirements-completed: [SKILL-04, SKILL-05, SPEC-01, SPEC-02]

duration: 5min
completed: 2026-03-20
---

# Phase 6 Plan 2: Agent-Backed Skills Summary

**Two agent-backed slash commands (requirement-parser, testbench) with spec-file communication via workspace/<Module>/spec.json**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-20T06:02:15Z
- **Completed:** 2026-03-20T06:07:22Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created requirement-parser skill that wraps agents/requirement-parser.md and writes spec.json to workspace
- Created testbench skill that reads spec.json from workspace and overrides output path to workspace/<Module>/sim/
- Extended test-phase6.sh from 6 to 12 checks, all passing

## Task Commits

Each task was committed atomically:

1. **Task 1: Create agent-backed SKILL.md files** - `5972166` (feat)
2. **Task 2: Extend test-phase6.sh with checks 7-12** - `994216f` (test)

## Files Created/Modified
- `skills/requirement-parser/SKILL.md` - Requirement parser slash command wrapping agents/requirement-parser.md
- `skills/testbench/SKILL.md` - Testbench generator slash command wrapping agents/testbench-generator.md
- `scripts/test-phase6.sh` - Extended from 6 to 12 structural checks

## Decisions Made
- Requirement-parser skill explicitly captures agent JSON output and writes to disk (agent returns JSON to conversation only, does not write files)
- Testbench skill reads spec.json from workspace path on disk, not from conversation context, enabling standalone invocation in fresh sessions
- Testbench output path overridden to workspace/<Module>/sim/tb_<Module>.cpp (agent defaults to flat sim/ path)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All 5 Phase 6 skills complete: compile, lint, simulate, requirement-parser, testbench
- test-phase6.sh passes 12/12 structural checks
- Ready for Phase 7 (Orchestrator) which wires skills into the /chip-agent:generate pipeline

---
*Phase: 06-skill-decomposition*
*Completed: 2026-03-20*
