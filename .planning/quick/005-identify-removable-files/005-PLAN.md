---
phase: quick-005
plan: 1
type: execute
wave: 1
depends_on: []
files_modified:
  - .gitignore
  - .planning/STATE.md
autonomous: false
must_haves:
  truths:
    - "All definitely-removable files are deleted from disk and untracked from git"
    - ".gitignore updated to prevent re-accumulation of build artifacts and backups"
    - "User has confirmed disposition of ambiguous items (ALU/, Counter8/, hooks, etc.)"
  artifacts:
    - path: ".gitignore"
      provides: "Updated ignore rules for target/, generated/, sim/, *.backup-*/"
      contains: "target/"
  key_links: []

user_setup: []
---

<objective>
Clean up the ChipAgent repository by removing definitely-unnecessary files/directories and presenting ambiguous items for user decision.

Purpose: Reduce repo bloat (50M backup, 332K duplicate source, 1.2G gitlink). Remove artifacts from pre-MyDesign architecture. Update .gitignore to prevent re-accumulation.

Output: Clean working tree, updated .gitignore, user decisions recorded for ambiguous items.
</objective>

<execution_context>
@/home/mingzhenjia/.claude/get-shit-done/workflows/execute-plan.md
@/home/mingzhenjia/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Remove definitely-removable files and update .gitignore</name>
  <files>.gitignore, (removed files)</files>
  <action>
Remove the following items from both disk AND git tracking. Use `git rm -r --cached` for tracked items, then `rm -rf` from disk.

**Tracked in git (use `git rm -r --cached` then `rm -rf`):**
1. `mcp-server.local-backup-20260412/` -- 50M backup of MCP server, current `mcp-server/` works fine. Staged in index with `A` status.
2. `ChipAgent-main/` -- 332K duplicate of the repo itself. Completely redundant.
3. `generated/ALU.anno.json`, `generated/ALU.fir`, `generated/Decoder3to8.anno.json`, `generated/Decoder3to8.fir`, `generated/TrivialModule.anno.json`, `generated/TrivialModule.fir`, `generated/chisel-warnings.vlt`, `generated/lint-warnings.log` -- Pre-MyDesign FIRRTL artifacts. All modules now generate under `MyDesign/`.
4. `sim/tb_ALU.cpp`, `sim/tb_Decoder3to8.cpp`, `sim/tb_TrivialModule.cpp`, `sim/cpu_test_template.h`, `sim/logs/` -- Pre-MyDesign testbenches. All modules now have testbenches under `MyDesign/<module>/workspace/sim/`.
5. `daily.txt` -- Personal log (3.25-3.27), not project code.
6. `.planning/debug/` -- Debug session notes for resolved issues.

**Not tracked (just `rm -rf`):**
7. `target/` -- Root-level sbt build artifacts (12K). Not tracked but should be gitignored.

**After removal, update `.gitignore` to prevent re-accumulation. Add these entries:**
```
# Root-level sbt build artifacts
/target/

# Root-level generated/sim (pre-MyDesign legacy, now under MyDesign/)
/generated/*.fir
/generated/*.anno.json
/generated/*.vlt
/generated/*.log
/sim/tb_*.cpp
/sim/*.h
/sim/logs/

# MCP server backups
mcp-server.local-backup-*/

# Debug planning notes (transient)
.planning/debug/
```

Keep the existing entries intact. The new entries extend the existing generated/sim patterns to cover root-level artifacts.

IMPORTANT: Do NOT delete `generated/.gitkeep` if it exists -- it may be needed to preserve the directory structure.
  </action>
  <verify>
    <automated>test ! -d mcp-server.local-backup-20260412 && test ! -d ChipAgent-main && test ! -f daily.txt && test ! -d target && echo "All removable items cleaned" || echo "FAILED: some items remain"</automated>
  </verify>
  <done>Seven definitely-removable items deleted from disk and untracked from git. .gitignore updated with preventive rules.</done>
</task>

<task type="checkpoint:decision" gate="blocking">
  <name>Task 2: User decides disposition of ambiguous files</name>
  <files>(depends on user choices)</files>
  <action>
Present the following 5 decisions to the user and apply their choices after confirmation.
  </action>
  <decision>Disposition of OpenROAD-flow-scripts (1.2G gitlink) and ambiguous tracked files</decision>
  <context>
The following items are tracked in git and need your decision before removal:

**1. `OpenROAD-flow-scripts/` (1.2G on disk)**
Currently tracked as a gitlink (submodule reference without .gitmodules). Used by MCP server for PnR flow. The 1.2G directory itself is NOT in git (just the reference), but the gitlink clutters `git status`.
Options:
- A: Convert to proper git submodule (recommended for long-term)
- B: Remove gitlink, add to .gitignore, keep on disk as local dependency
- C: Leave as-is (accept the gitlink in status)

**2. `hooks.json` + `hooks/hooks.json` (root level)**
Root `hooks.json` has a PostToolUse hook for simulation failure detection. `hooks/` dir contains only another `hooks.json` (18 bytes).
- A: Keep root `hooks.json` (actively useful for simulation workflow), remove redundant `hooks/hooks.json`
- B: Remove both (no longer needed)
- C: Keep both as-is

**3. `MyDesign/ALU/` (40K) and `MyDesign/Counter8/` (276K)**
Early test modules created during v1.0 development. Not referenced by any current code or config.
- A: Remove both (historical, not needed)
- B: Keep both (useful as examples/references)

**4. `image.png` (44K)**
Not referenced by README.md or any markdown file. Likely leftover from early development.
- A: Remove (no references found)
- B: Keep (might be used somewhere not checked)

**5. `TODO.md`**
Old TODO list with items partially completed. Different from the planning system now in use.
- A: Remove (superseded by .planning/ system)
- B: Keep as historical reference
  </context>
  <resume-signal>For each item, reply with the option letter (e.g., "1B 2A 3A 4A 5A")</resume-signal>
  <verify>User has provided decisions for all 5 ambiguous items</verify>
  <done>User choices recorded and applied for all ambiguous files.</done>
</task>

</tasks>

<verification>
1. `git status` shows clean removal of items from Task 1
2. `.gitignore` contains new preventive entries
3. User decisions recorded for ambiguous items (Task 2 checkpoint)
</verification>

<success_criteria>
- All 7 definitely-removable items deleted from disk and git
- .gitignore updated to prevent re-accumulation
- User has decided on all 5 ambiguous items
- Repo is measurably cleaner (at least 50M+ freed from backup removal)
</success_criteria>

<output>
After completion, create `.planning/quick/005-identify-removable-files/005-SUMMARY.md`
</output>
