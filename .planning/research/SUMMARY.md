# Research Summary: ChipAgent

**Domain:** Automated Chisel-to-Verified-Verilog Pipeline (Claude Code Plugin)
**Researched:** 2026-03-16
**Overall confidence:** HIGH

## Executive Summary

ChipAgent is a Claude Code plugin that automates the full pipeline from natural language hardware descriptions to simulation-verified Verilog. The technology stack is well-established: Chisel 7.x (Scala 2.13) for hardware description, sbt for building, CIRCT/firtool for FIRRTL-to-Verilog compilation, and Verilator for linting and simulation. All core tools are either already installed on the target machine (sbt 1.10.7, Verilator 5.008, JDK 17, Node.js 24) or auto-managed (firtool is downloaded by Chisel's firtool-resolver on first build).

The Claude Code plugin ecosystem is mature enough for this use case. The plugin system (public beta since 2025) supports all the primitives we need: skills for slash commands (`/chip:generate`), agents for specialized LLM tasks (requirement parsing, code generation, testbench creation), hooks for deterministic automation (compilation, lint, simulation), and shell scripts for wrapping external tools. The plugin directory structure is straightforward: `.claude-plugin/plugin.json` for metadata, `skills/` for entry points, `agents/` for subagents, `hooks/hooks.json` for event handlers, and `scripts/` for build automation.

The primary technical risk is not the individual tools but the integration between pipeline stages. Port naming mismatches between Chisel's `io_` prefix convention and C++ testbench expectations, firtool-generated Verilog patterns that trigger unfixable Verilator warnings, and sbt cold start latency are the most likely pain points. These are all addressable with careful prompting of the LLM agents and defensive scripting.

The acceptance test (RV32I ALU with ADD/SUB/AND/OR/XOR/SLT and zero flag) is a well-scoped target. The ALU is a combinational module with clearly defined inputs, outputs, and expected behavior -- ideal for proving the pipeline works end-to-end before expanding to more complex modules.

## Key Findings

**Stack:** Chisel 7.2.0 + Scala 2.13.16 + sbt 1.10.7 + auto-managed firtool + Verilator 5.008, packaged as a Claude Code native plugin with skills, agents, hooks, and scripts.

**Architecture:** Skill-driven pipeline orchestration where a single `/chip:generate` skill chains through specialized agents (requirement-parser, chisel-generator, lint-fixer, testbench-generator, report-generator) with deterministic shell scripts for build/lint/simulation steps.

**Critical pitfall:** LLM-generated Chisel code using deprecated APIs (`emitVerilog` instead of `emitSystemVerilog`, old artifact names). Must pin correct API patterns in agent system prompts and include reference code in the chisel-project template.

## Implications for Roadmap

Based on research, suggested phase structure:

1. **Plugin Scaffold + Chisel Project Template** - Foundation first
   - Addresses: Plugin structure, sbt project, build.sbt, Generate.scala entry point
   - Avoids: sbt cold start surprise by pre-downloading dependencies; establishes correct Chisel 7.x API patterns from the start
   - Rationale: Everything else depends on a working build pipeline

2. **Skills and Agents for Code Generation** - Core LLM pipeline
   - Addresses: `/chip:generate` skill, requirement-parser agent, chisel-generator agent
   - Avoids: Wrong Chisel API pitfall by embedding correct patterns in agent prompts
   - Rationale: Code generation is the highest-value, highest-risk component; needs iteration

3. **Lint, Auto-Fix, and Compilation Automation** - Quality gate
   - Addresses: lint.sh, compile.sh, lint-fixer agent, 3-attempt retry loop
   - Avoids: Hook event storms by using skill-driven orchestration rather than PostToolUse hooks for the main pipeline flow
   - Rationale: Lint errors are the most common pipeline failure; auto-fix is a key differentiator

4. **Testbench Generation + Simulation + Reporting** - End-to-end verification
   - Addresses: testbench-generator agent, simulate.sh, report-generator agent, sim_result.log
   - Avoids: Port name mismatch by having testbench generator read generated Verilog ports
   - Rationale: Depends on working Verilog output from Phase 3; produces the acceptance test deliverable

**Phase ordering rationale:**
- Phase 1 must come first because all subsequent phases depend on a working sbt project and plugin structure
- Phase 2 before Phase 3 because lint checking requires generated Verilog, which requires code generation
- Phase 3 before Phase 4 because testbench generation needs lint-clean Verilog to avoid generating tests for broken modules
- Each phase produces independently testable deliverables

**Research flags for phases:**
- Phase 1: Standard patterns, unlikely to need deeper research. Chisel template is well-documented
- Phase 2: May need deeper research on Chisel 7.x idioms for specific RV32I modules beyond ALU
- Phase 3: Likely needs deeper research on firtool-generated Verilog patterns and which Verilator warnings to suppress vs fix
- Phase 4: May need research on Verilator 5.008-specific C++ API (older version)

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All versions verified against installed tools and official docs; Chisel 7.x and plugin system both well-documented |
| Features | HIGH | Requirements are explicit in PROJECT.md; feature landscape is clearly bounded by RV32I scope |
| Architecture | HIGH | Claude Code plugin structure is officially documented; pipeline flow follows standard Chisel workflow |
| Pitfalls | MEDIUM | Most pitfalls identified from official docs and issue trackers; real integration issues may surface during implementation that research cannot predict |

## Gaps to Address

- Exact Verilator 5.008 C++ API differences vs newer versions (may need phase-specific research during testbench generation)
- Chisel 7.x idioms for specific RV32I modules beyond ALU (decoder, register file) -- defer to Phase 2 research
- Hook vs skill-driven orchestration tradeoffs in practice (may need experimentation during Phase 3)
- Whether the Claude Code plugin system properly handles long-running sbt processes (120s+ first compile) in hooks

---
*Research summary for: ChipAgent -- Automated Chisel-to-Verified-Verilog Pipeline*
*Researched: 2026-03-16*
