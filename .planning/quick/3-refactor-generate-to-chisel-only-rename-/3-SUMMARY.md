---
phase: quick
plan: 3
subsystem: skills
tags: [refactor, skills, documentation]
key-files:
  created:
    - skills/workflow/SKILL.md
  modified:
    - skills/generate/SKILL.md
    - CLAUDE.md
decisions:
  - "generate skill is Chisel-only (steps 1-2); workflow skill has full 7-step pipeline"
  - "Merged Verilog port naming into Chisel API Rules section"
metrics:
  duration: 4min
  completed: 2026-03-20
---

# Quick Task 3: Refactor Generate to Chisel-Only + Rename Summary

Split generate skill into focused Chisel-only generator and full-pipeline workflow skill; simplified CLAUDE.md from 108 to 63 lines.

## Deviations from Plan

None - plan executed exactly as written.

## Task Results

### Task 1: Split generate into chisel-only and create workflow skill

**Commit:** 6370d26

- Rewrote `skills/generate/SKILL.md` to contain only Steps 1 (Parse), 1.5 (Confirm), and 2 (Generate Chisel)
- Created `skills/workflow/SKILL.md` with the full 7-step pipeline (self-contained, no circular sub-skill references)
- Both skills share the same frontmatter structure and allowed-tools list

### Task 2: Simplify CLAUDE.md

**Commit:** 7af147d

- Reduced from 108 lines to 63 lines (42% reduction)
- Removed "File Path Conventions" and "Interface Specs" sections (redundant)
- Merged Verilog port naming note into Chisel API Rules as rule 6
- Added Commands section referencing both `/chip-agent:generate` and `/chip-agent:workflow`
- Condensed Context7 section to two lines
- Simplified directory structure by removing inline comments

## Verification

- `skills/generate/SKILL.md` contains no compile/lint/simulate pipeline steps (only references them to say "use workflow instead")
- `skills/workflow/SKILL.md` contains the full 7-step pipeline including Step 7
- `CLAUDE.md` references both `/chip-agent:generate` and `/chip-agent:workflow`
- `CLAUDE.md` is 63 lines (target was under 120)

## Self-Check: PASSED
