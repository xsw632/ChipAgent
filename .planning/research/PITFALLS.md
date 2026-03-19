# Domain Pitfalls

**Domain:** ChipAgent v1.1 -- Modular Slash Commands + Workspace Isolation
**Researched:** 2026-03-19
**Supersedes:** v1.0 pitfalls from 2026-03-16 (those remain valid; this adds v1.1-specific pitfalls)

## Critical Pitfalls

Mistakes that cause rewrites or major issues during the v1.1 refactoring.

### Pitfall 1: Breaking the Working Pipeline During Decomposition

**What goes wrong:** While splitting generate.md into separate skills, the end-to-end pipeline stops working. The ALU acceptance test fails because a data flow between stages is broken.

**Why it happens:** The monolithic generate.md carries state in conversation context between stages (e.g., the JSON spec from the parser feeds into the generator). When stages become separate skills, this implicit context passing breaks. If the spec.json write/read convention is not implemented before the orchestrator is rewritten, the pipeline has no inter-stage communication.

**Consequences:** Regression from v1.0 working state. Users who depended on `/chip-agent:generate` have a broken tool. Debugging is difficult because the failure could be in any of 7 newly separated stages.

**Prevention:**
- Build workspace foundation (scripts, spec.json) BEFORE decomposing skills
- Keep old generate.md until the orchestrator is fully tested
- Run the ALU acceptance test after each major change
- Implement spec-file communication first, then decompose skills
- The old generate.md and new skills can coexist temporarily (different names)

**Detection:** ALU acceptance test fails; `workspace/<Module>/logs/sim_result.log` is empty or missing; stages report "spec.json not found."

### Pitfall 2: Hook Triggers on Non-Scala Writes

**What goes wrong:** The current PostToolUse hook fires on ALL Write|Edit operations. When a testbench .cpp file is written, sbt compile is triggered unnecessarily, wasting 10-30 seconds of JVM startup.

**Why it happens:** Claude Code hook matchers match tool names (Write, Edit), not file paths. The current matcher `"Write|Edit"` catches every file type. The hook command receives the file path via stdin JSON, but the current compile.sh does not read stdin -- it just compiles unconditionally.

**Consequences:** Every testbench write triggers a 10-30 second sbt invocation that does nothing useful. Worse, if the testbench write happens during a skill that expects compile output, the timing can cause confusion.

**Prevention:**
- Replace direct compile.sh invocation in hooks with an auto-compile.sh wrapper
- auto-compile.sh reads the hook's stdin JSON, extracts `tool_input.file_path`, and only invokes compile.sh for `.scala` files
- Alternative: remove the PostToolUse hook entirely and have skills call compile.sh explicitly at the right time

**Detection:** sbt compilation log appears after writing non-Scala files; `Compiling Chisel to Verilog...` message after writing a .cpp testbench.

### Pitfall 3: Workspace Path Not Passed to Generate.scala

**What goes wrong:** compile.sh is updated to accept a target directory argument, but the argument is not correctly forwarded to sbt's `runMain` command with the `--target-dir` flag. Verilog files end up in the default `generated/` directory instead of `workspace/<Module>/generated/`.

**Why it happens:** Shell variable quoting issues when passing paths through `sbt --batch "runMain chipagent.Generate --target-dir $OUTPUT_DIR"`. Paths with spaces or special characters break. The current compile.sh hardcodes `OUTPUT_DIR="$PLUGIN_ROOT/generated"`.

**Consequences:** Per-module workspace isolation silently fails. Files accumulate in the flat generated/ directory. Multiple modules overwrite each other's output.

**Prevention:**
- Quote all paths in sbt invocations: `--target-dir \"$OUTPUT_DIR\"`
- Verify by checking that Verilog files appear in `workspace/<Module>/generated/` NOT in `generated/`
- Add a validation check in compile.sh: if target-dir is specified, verify the output file exists there after compilation
- Test with module names containing no spaces (PascalCase convention ensures this)

**Detection:** `ls workspace/<Module>/generated/` returns empty; `ls generated/` contains unexpected files from the current module.

### Pitfall 4: Skill-to-Skill Invocation Semantics

**What goes wrong:** The generate orchestrator skill tries to invoke sub-skills (e.g., `/chip-agent:lint ALU`) but the invocation does not work as expected. Claude may interpret the slash command literally instead of executing it, or the invocation may not pass arguments correctly.

**Why it happens:** Claude Code skills are designed for user invocation (typing `/skill-name`) or model invocation (Claude deciding to use a skill based on context). A skill invoking another skill programmatically is not the same as a user typing a command. The exact mechanics depend on whether Claude treats the slash command in the skill prompt as an instruction to invoke the skill tool.

**Consequences:** The orchestrator skill fails silently or generates output as if it ran the stage without actually running it. The pipeline appears to complete but produces no artifacts.

**Prevention:**
- Test skill-to-skill invocation early in development
- The orchestrator skill should instruct Claude to "use the Skill tool to invoke /chip-agent:lint" rather than just writing the slash command as text
- Alternative: the orchestrator skill can directly invoke the bash scripts and agents, bypassing sub-skill invocation entirely (this is simpler but loses the benefit of skill encapsulation)
- Monitor Claude's tool usage during orchestration to verify actual skill invocations

**Detection:** The orchestrator completes but `workspace/<Module>/logs/` is empty; Claude's tool usage log shows no Skill tool invocations during the pipeline.

### Pitfall 5: Moving Chisel Source Into Workspace

**What goes wrong:** A developer attempts to put ALU.scala into `workspace/ALU/src/` for "better isolation." sbt cannot find the source because its sourceDirectory is configured for `chisel-project/src/main/scala/chipagent/`.

**Why it happens:** Natural instinct to co-locate all module files in one directory. The sbt build system is not obvious to non-Scala developers.

**Consequences:** Compilation fails with "object ALU is not a member of package chipagent." Must reconfigure build.sbt or move files back.

**Prevention:**
- Document clearly: Chisel source stays in `chisel-project/src/main/scala/chipagent/`. Workspace is for OUTPUTS only.
- Add a comment in the workspace directory convention documentation
- ARCHITECTURE.md anti-pattern section explicitly addresses this

**Detection:** `sbt compile` error: "not found: type ALU" or "object ALU is not a member of package chipagent."

## Moderate Pitfalls

### Pitfall 1: spec.json Schema Drift Between Parser and Consumer

**What goes wrong:** The requirement-parser agent writes spec.json with a slightly different schema than what the chisel-generator agent expects. For example, parser uses `"type": "UInt"` but generator expects `"dataType": "UInt"`.

**Prevention:**
- The spec.json schema is already defined in the requirement-parser agent (see agents/requirement-parser.md). All downstream agents must use the SAME schema.
- Do not create a "v2" spec format without updating all consumers
- Validate spec.json in each skill before passing to the agent

### Pitfall 2: obj_dir Contamination Between Modules

**What goes wrong:** Without per-module obj_dir isolation, Verilator build artifacts from Module A remain in `sim/obj_dir/` when Module B is compiled. The stale `.mk` file may cause build failures or link the wrong module.

**Prevention:**
- Use `--Mdir workspace/<Module>/sim/obj_dir/` in simulate.sh to isolate build artifacts per module
- Clean obj_dir before each Verilator invocation if workspace isolation is not yet implemented
- The `make -C` command must reference the module-specific obj_dir

### Pitfall 3: Skills Directory vs Legacy Command File Format

**What goes wrong:** The existing `skills/generate.md` is a flat command file (legacy format). New skills are created as `skills/<name>/SKILL.md` (modern format). If both exist for the same command name, behavior is undefined.

**Prevention:**
- Delete `skills/generate.md` AFTER creating `skills/generate/SKILL.md`
- Do not have both formats for the same command name simultaneously
- Test with `/reload-plugins` after the transition

### Pitfall 4: CLAUDE_PLUGIN_ROOT vs CLAUDE_SKILL_DIR Confusion

**What goes wrong:** Skill content uses `${CLAUDE_SKILL_DIR}` expecting it to resolve to the plugin root, but it actually resolves to the skill's own directory (e.g., `skills/lint/`), not the plugin root.

**Prevention:**
- `${CLAUDE_SKILL_DIR}` resolves to the directory containing SKILL.md (e.g., `<plugin>/skills/lint/`)
- `${CLAUDE_PLUGIN_ROOT}` resolves to the plugin root directory
- Scripts should always use `PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"` for the plugin root
- Skills that need to reference scripts should use `${CLAUDE_PLUGIN_ROOT}/scripts/compile.sh`, NOT `${CLAUDE_SKILL_DIR}/../../scripts/compile.sh`

## Minor Pitfalls

### Pitfall 1: Workspace Directory Not Created Before First Use

**What goes wrong:** A skill tries to write `workspace/ALU/spec.json` but `workspace/ALU/` does not exist yet.

**Prevention:** Each skill should `mkdir -p workspace/<Module>/{generated,sim/obj_dir,logs}` before writing. Or create a shared `ensure-workspace.sh` script.

### Pitfall 2: .gitignore Not Updated for workspace/

**What goes wrong:** workspace/ directory with large obj_dir/ artifacts gets committed to git.

**Prevention:** Add `workspace/*/sim/obj_dir/` and `workspace/*/generated/*.fir` to `.gitignore`. Keep spec.json and sim_result.log trackable if desired.

### Pitfall 3: Argument Parsing Inconsistency Across Scripts

**What goes wrong:** compile.sh uses positional args (`compile.sh MODULE TARGET_DIR`), lint.sh uses a flag (`lint.sh --dir DIR`), simulate.sh uses a different convention. Inconsistency makes skills harder to write.

**Prevention:** Standardize on positional arguments for simplicity: `script.sh MODULE [WORKSPACE_DIR]`. All scripts follow the same pattern. Defaults to legacy behavior when WORKSPACE_DIR is omitted.

## Phase-Specific Warnings (v1.1)

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Workspace Foundation | Paths not correctly quoted in shell scripts | Test with module names like "ALU" (simple) first; avoid spaces in paths |
| Script Parameterization | Breaking backward compatibility | Default arguments match v1.0 behavior when no args given |
| Skill Decomposition | Skills reference wrong paths (CLAUDE_SKILL_DIR vs CLAUDE_PLUGIN_ROOT) | Use CLAUDE_PLUGIN_ROOT for all script references |
| Orchestrator Rewrite | Skill-to-skill invocation fails silently | Test orchestrator with a single simple module before full pipeline |
| Hook Refinement | auto-compile.sh not receiving stdin JSON correctly | Test hook wrapper independently with `echo '{"tool_input":{"file_path":"test.scala"}}' \| ./scripts/auto-compile.sh` |
| Initialize Command | Version parsing fragile across OS variants | Test on target platform; use simple regex for version extraction |
| Migration (generate.md -> generate/SKILL.md) | Both old and new files coexist causing conflicts | Delete old file only after new one is verified working |

## Sources

- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills) -- CLAUDE_SKILL_DIR behavior, skill-to-skill invocation patterns
- [Claude Code Hooks Documentation](https://code.claude.com/docs/en/hooks) -- Hook stdin JSON format, file_path extraction
- [Claude Code Plugins Documentation](https://code.claude.com/docs/en/plugins) -- CLAUDE_PLUGIN_ROOT resolution, plugin directory structure
- Existing codebase analysis: hooks.json, compile.sh, lint.sh, simulate.sh, Generate.scala
- v1.0 ALU acceptance test flow analysis

---
*Domain pitfalls for: ChipAgent v1.1 -- Modular Slash Commands + Workspace Isolation*
*Researched: 2026-03-19*
*Supersedes v1.0 pitfalls (those remain valid for the underlying pipeline; this adds v1.1-specific concerns)*
