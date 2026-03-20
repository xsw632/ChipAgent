---
phase: quick
plan: 3
type: execute
wave: 1
depends_on: []
files_modified:
  - skills/generate/SKILL.md
  - skills/workflow/SKILL.md
  - CLAUDE.md
autonomous: true
requirements: []
must_haves:
  truths:
    - "/chip-agent:generate only produces Chisel code (steps 1-2), does not compile/lint/simulate"
    - "/chip-agent:workflow runs the full pipeline (parse, generate, compile, lint, testbench, simulate, report)"
    - "CLAUDE.md is noticeably shorter and easier to scan"
  artifacts:
    - path: "skills/generate/SKILL.md"
      provides: "Chisel-only generation skill (steps 1, 1.5, 2)"
    - path: "skills/workflow/SKILL.md"
      provides: "Full auto-toolchain pipeline skill (all 7 steps)"
    - path: "CLAUDE.md"
      provides: "Simplified project instructions"
  key_links:
    - from: "skills/workflow/SKILL.md"
      to: "skills/generate/SKILL.md"
      via: "workflow step 2 references generate skill"
      pattern: "chip-agent:generate"
---

<objective>
Split the current /chip-agent:generate skill into two commands: a Chisel-only /chip-agent:generate (steps 1-2) and a full-pipeline /chip-agent:workflow (all 7 steps). Simplify CLAUDE.md.

Purpose: generate should be a focused Chisel code generator; workflow should be the auto-toolchain that runs the full verification pipeline.
Output: Two skill files and a simplified CLAUDE.md.
</objective>

<execution_context>
@/home/mingzhenjia/.claude/get-shit-done/workflows/execute-plan.md
@/home/mingzhenjia/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@skills/generate/SKILL.md
@CLAUDE.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Split generate into chisel-only and create workflow skill</name>
  <files>skills/generate/SKILL.md, skills/workflow/SKILL.md</files>
  <action>
1. Rewrite `skills/generate/SKILL.md`:
   - Keep only Steps 1 (Parse Requirements), 1.5 (Confirm Spec), and 2 (Generate Chisel)
   - Update the description/header to say it produces Chisel source files only (no compile/lint/sim)
   - Update the Output section to list only spec.json and the Chisel .scala files
   - Remove all references to compile, lint, testbench, simulate, report steps
   - Keep the same frontmatter structure (name: generate, disable-model-invocation: true, same allowed-tools)

2. Create `skills/workflow/SKILL.md` as the full auto-toolchain:
   - Copy the full pipeline from the current generate SKILL.md (all 7 steps + step 1.5)
   - Change name to "workflow", update description to "Full auto-toolchain: parse, generate Chisel, compile, lint, testbench, simulate, report"
   - In Step 2, note that this runs the chisel-generator agent inline (same as before) -- do NOT reference /chip-agent:generate as a sub-skill (keep it self-contained to avoid circular invocation)
   - Keep all retry logic, workspace paths, error handling exactly as-is
   - Same frontmatter allowed-tools list
   - Usage: `/chip-agent:workflow <hardware description>`

3. Create the skill directory: `mkdir -p skills/workflow`
  </action>
  <verify>
    <automated>grep -q "compile\|lint\|simulate" skills/generate/SKILL.md && echo "FAIL: generate still has pipeline steps" || echo "PASS: generate is chisel-only"; test -f skills/workflow/SKILL.md && grep -q "Step 7" skills/workflow/SKILL.md && echo "PASS: workflow has full pipeline" || echo "FAIL: workflow missing"</automated>
  </verify>
  <done>generate skill contains only parse+confirm+chisel-generate steps; workflow skill contains the full 7-step pipeline</done>
</task>

<task type="auto">
  <name>Task 2: Simplify CLAUDE.md</name>
  <files>CLAUDE.md</files>
  <action>
Rewrite CLAUDE.md to be concise. Target roughly half the current length. Keep these sections but make them tighter:

1. **Header** -- one-line project description
2. **Tech Stack** -- keep table as-is (already concise)
3. **Directory Structure** -- keep but remove inline comments that are obvious; add `skills/workflow/` entry
4. **Build Commands** -- keep table as-is
5. **Chisel API Rules** -- keep all 5 rules (these prevent real bugs) but shorten prose
6. **Pipeline Overview** -- update to reference two commands: `/chip-agent:generate` (chisel-only) and `/chip-agent:workflow` (full pipeline). Replace the 7-step table with a brief summary
7. **Context7** -- keep the library ID and the one-liner about querying it; remove the verbose explanation
8. **Verilog port naming** -- keep (one line)

Remove or merge:
- "File Path Conventions" section -- redundant with directory structure
- "Interface Specs" section -- merge the port naming note into Chisel API Rules
- Verbose paragraphs that repeat information already in the directory structure
  </action>
  <verify>
    <automated>wc -l CLAUDE.md | awk '{if ($1 < 120) print "PASS: CLAUDE.md is", $1, "lines"; else print "WARN: CLAUDE.md is", $1, "lines (target < 120)"}'</automated>
  </verify>
  <done>CLAUDE.md is noticeably shorter, references both /chip-agent:generate and /chip-agent:workflow, retains all critical API rules</done>
</task>

</tasks>

<verification>
- `skills/generate/SKILL.md` exists and contains NO references to compile/lint/simulate/testbench/report steps
- `skills/workflow/SKILL.md` exists and contains the full 7-step pipeline
- `CLAUDE.md` references both `/chip-agent:generate` and `/chip-agent:workflow`
- `CLAUDE.md` is significantly shorter than the original (~200 lines -> ~100 lines)
</verification>

<success_criteria>
- Two distinct skills: generate (chisel-only) and workflow (full pipeline)
- CLAUDE.md simplified to under 120 lines while retaining all critical build/API rules
- No broken references between files
</success_criteria>

<output>
After completion, create `.planning/quick/3-refactor-generate-to-chisel-only-rename-/3-SUMMARY.md`
</output>
