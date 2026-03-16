# Research Summary

**Project:** ChipAgent — Automated Chisel/RTL Pipeline Plugin
**Researched:** 2026-03-16

## Stack Recommendation

- **Chisel 6.x+** with auto-managed firtool (no separate install needed)
- **sbt 1.10.x** for builds, **Verilator 5.008** for lint/sim
- **Claude Code plugin format** with `.claude-plugin/plugin.json` manifest
- **npm package** for distribution (`npx chip-agent`)

## Table Stakes Features

1. NL requirement parsing → structured module spec
2. Chisel source generation from spec
3. Automated sbt compile → firtool → Verilog
4. Verilator lint with auto-fix (3 attempts)
5. C++ testbench generation
6. Simulation + formatted report (`sim_result.log`)
7. Slash command entry (`/chip-agent:generate`)

## Architecture Pattern

- **Skills** drive LLM reasoning (parsing, code gen, TB gen)
- **Hooks** drive deterministic automation (compile, lint, sim)
- **File-based pipeline**: NL → .scala → .v → .cpp → .log
- Build order: scaffold → skills → hooks → integration

## Top Pitfalls to Watch

1. **Verilator WIDTH warnings** on Chisel output — use waiver/pragmas
2. **Hook infinite loops** — precise matcher patterns on `.scala` only
3. **Clock handling in C++ testbench** — explicit toggle + eval()
4. **First-run sbt downloads** — pre-cache dependencies in setup
5. **npm path resolution** — always use `${CLAUDE_PLUGIN_ROOT}`

---
*Summary for: ChipAgent*
*Researched: 2026-03-16*
