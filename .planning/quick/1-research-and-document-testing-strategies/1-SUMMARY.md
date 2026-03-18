---
phase: quick-1
plan: 01
subsystem: testing
tags: [verilator, c++, rv32i, reference-model, cpu-verification]

requires:
  - phase: 04-testbench-simulation-verification
    provides: simple struct-based testbench pattern (tb_ALU.cpp, simulate.sh)
provides:
  - C++ CPU test template with RV32I instruction encoding helpers and reference emulator
  - Debug port convention for complex CPU modules
  - Verification schema in requirement-parser for CPU/processor specs
  - Conditional Step 5 in generate skill for reference-model testbenches
affects: [chisel-generator, requirement-parser, generate-skill, cpu-testbench-generation]

tech-stack:
  added: []
  patterns: [embedded-reference-model, debug-port-observation, instruction-encoding-helpers]

key-files:
  created:
    - sim/cpu_test_template.h
    - .planning/quick/1-research-and-document-testing-strategies/1-RESEARCH.md
  modified:
    - agents/chisel-generator.md
    - agents/requirement-parser.md
    - skills/generate.md

key-decisions:
  - "Embedded C++ reference model over external ISA simulator (self-contained, no external deps)"
  - "Debug ports (debug_pc, debug_reg_addr, debug_reg_data) mandatory for all CPU modules"
  - "LLM composes test sequences via helper functions, never encodes raw instruction bits"

patterns-established:
  - "Reference-model testbench: include cpu_test_template.h, use rv_add/rv_addi helpers, compare DUT vs emulator"
  - "Debug port convention: Output debug_pc (32-bit), Input debug_reg_addr (5-bit), Output debug_reg_data (32-bit)"
  - "Three-tier verification: simple-struct for combinational, reference-model for CPU, formal for future"

requirements-completed: [RESEARCH-1, TEMPLATE-1, AGENT-UPDATE-1]

duration: 11min
completed: 2026-03-18
---

# Quick Task 1: CPU Testing Strategy Summary

**RV32I reference emulator template with instruction encoding helpers, debug port convention, and three-tier verification strategy for CPU modules**

## Performance

- **Duration:** 11 min
- **Started:** 2026-03-18T08:33:50Z
- **Completed:** 2026-03-18T08:45:04Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments
- Created header-only C++ CPU test template with 6 encoding functions, 16 convenience aliases, and a ~150-line RV32I reference emulator
- Updated all three agent/skill files to support complex CPU module verification with debug ports and reference-model testbenches
- Documented the three-tier verification approach with research findings and decision rationale

## Task Commits

Each task was committed atomically:

1. **Task 1: Create C++ CPU test template header** - `13a1e08` (feat)
2. **Task 2: Update agents and skill for complex module testing** - `a2b5eef` (docs)
3. **Task 3: Write research summary document** - `41ea2f7` (docs)

## Files Created/Modified
- `sim/cpu_test_template.h` - Header-only template: RV32I encoding helpers, reference emulator, comparison logic (319 lines)
- `agents/chisel-generator.md` - Added debug port rules and checklist item for CPU modules
- `agents/requirement-parser.md` - Added verification schema (isa, tier, debugPorts, testCategories) and Rule 19
- `skills/generate.md` - Added conditional Step 5 path for reference-model testbench generation
- `.planning/quick/1-research-and-document-testing-strategies/1-RESEARCH.md` - Research summary (126 lines)

## Decisions Made
- Chose embedded C++ reference model over external ISA simulator (Spike) -- self-contained, no external dependencies, portable
- Debug ports are mandatory for CPU modules (can be stripped for synthesis but required for verification)
- LLM generates test sequences via helper function calls, never raw hex encoding -- eliminates the most common error class

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- CPU test template is ready for use when a complex CPU module is generated via `/chip-agent:generate`
- The three agent/skill files now have the conditional paths to detect CPU specs and use reference-model testbenches
- Actual end-to-end CPU generation+verification will be tested when a user requests a CPU module

## Self-Check: PASSED

All 6 files verified present. All 3 task commits verified in git log.

---
*Phase: quick-1*
*Completed: 2026-03-18*
