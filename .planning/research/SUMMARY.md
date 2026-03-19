# Research Summary: ChipAgent v1.1 Modular Architecture

**Domain:** Modular Slash Commands + Workspace Isolation for Hardware Generation Pipeline
**Researched:** 2026-03-19
**Overall confidence:** HIGH

## Executive Summary

ChipAgent v1.0 ships a working end-to-end pipeline from natural language to simulation-verified Verilog, but the entire pipeline lives in a single monolithic skill file (generate.md, 170 lines) and all artifacts land in flat shared directories. This creates three concrete problems: (1) the full pipeline prompt consumes context window even when only one stage is executing, (2) per-module outputs collide (lint-warnings.log and sim_result.log are overwritten by each new module run), and (3) there is no way to run individual pipeline stages independently for debugging or iterative development.

The v1.1 architecture decomposes generate.md into seven separate skills (generate, requirement-parser, chisel-generate, lint, testbench, simulate, initialize), introduces a `workspace/<Module>/` directory for per-module isolation of all pipeline artifacts, and updates all bash scripts to accept workspace paths while remaining backward-compatible with the original flat layout.

The key architectural insight is that skills and agents serve different roles in Claude Code's plugin system. Agents are reusable capability definitions (system prompts + tool restrictions). Skills are user-invocable actions. The existing agents (requirement-parser, chisel-generator, testbench-generator) remain unchanged -- they are the "how." The new skills wrap these agents with workspace I/O conventions -- they are the "when" and "where." The spec.json file written to `workspace/<Module>/` is the inter-stage communication contract, replacing in-conversation JSON passing.

The sbt constraint is the main architectural boundary: Chisel source files must remain in `chisel-project/src/main/scala/chipagent/` because sbt's source root is configured there. Only compilation outputs and simulation artifacts move into workspace/. Generate.scala already handles `--target-dir` and `--module` flags, so the Scala changes are minimal -- the real work is in script and skill modifications.

## Key Findings

**Stack:** No new dependencies. Same Chisel 3.6.1, sbt 1.10.7, Verilator 5.008+. Only structural changes to skills, scripts, and directory layout.

**Architecture:** Decompose into 7 skills with spec-file communication, workspace/ per-module isolation, backward-compatible scripts. See ARCHITECTURE.md for full details.

**Critical pitfall:** The PostToolUse hook fires on ALL Write|Edit operations, including testbench .cpp files. This triggers unnecessary sbt compilation. Must be fixed with a wrapper script that checks file extension before invoking compile.sh.

## Implications for Roadmap

Based on research, suggested phase structure:

1. **Workspace Foundation** - Modify scripts and Generate.scala to support workspace paths
   - Addresses: Per-module isolation, script backward compatibility
   - Avoids: Breaking existing manual script usage
   - Dependencies: None (can start immediately)

2. **Skill Decomposition** - Create individual skill directories with SKILL.md files
   - Addresses: Modular slash commands, independent stage execution
   - Avoids: Monolithic context window waste
   - Dependencies: Requires Phase 1 scripts to accept workspace paths

3. **Orchestrator + Hooks** - Rewrite generate as thin orchestrator, update hooks
   - Addresses: End-to-end pipeline, hook efficiency
   - Avoids: Hook triggering on non-Scala files
   - Dependencies: Requires Phase 2 skills to exist for invocation

4. **Initialize Command + Cleanup** - Add environment detection, update docs
   - Addresses: First-use experience, documentation accuracy
   - Avoids: Users running pipeline without prerequisites
   - Dependencies: Can run in parallel with Phase 3

**Phase ordering rationale:**
- Scripts must accept workspace paths BEFORE skills can reference them
- Individual skills must exist BEFORE the orchestrator can invoke them
- Initialize is independent and can be built in parallel with later phases
- Hook updates come last to avoid breaking the existing pipeline during development

**Research flags for phases:**
- Phase 1: Standard patterns, unlikely to need additional research
- Phase 2: Verify CLAUDE_SKILL_DIR variable behavior in plugin skills (documented but should be tested)
- Phase 3: The orchestrator skill invoking other skills requires careful testing -- Claude's skill invocation from within a skill needs validation

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | No changes to underlying tech stack; proven in v1.0 |
| Features | HIGH | Feature set is well-defined by PROJECT.md and milestone context |
| Architecture | HIGH | Verified against official Claude Code docs (skills, plugins, subagents, hooks) |
| Pitfalls | HIGH | Based on analysis of existing codebase + official hook documentation |

## Gaps to Address

- How exactly does Claude invoke one skill from within another skill? The official docs show skills as user-invocable or model-invocable, but the pattern of a skill programmatically invoking another skill (orchestrator pattern) needs phase-specific validation.
- Whether `${CLAUDE_SKILL_DIR}` works correctly for plugin skills referencing scripts in sibling directories.
- Testing the hook wrapper pattern (auto-compile.sh reading stdin JSON) in the actual Claude Code hook execution environment.

---
*Research summary for: ChipAgent v1.1 -- Modular Slash Commands + Workspace Isolation*
*Researched: 2026-03-19*
