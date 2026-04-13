# ChipAgent

A Claude Code plugin that turns natural language hardware descriptions into simulation-verified Verilog. One slash command runs the full pipeline: parse requirements → generate Chisel → compile to Verilog → lint → testbench → simulate → report.

## Install

```
npx chip-agent
```

This installs:
- `/chip-agent:*` slash commands into `~/.claude/commands/chip-agent`
- plugin support files into `~/.claude/plugins/chip-agent`
- the persistent `chipagent-backend` MCP server and its runtime dependencies

For normal use, you do not need the repo-local `.mcp.json`; that file is only for local development of this repository.

## Usage

In Claude Code, common slash commands include:

| Command | What it does |
|---------|-------------|
| `/chip-agent:workflow <desc>` | Full pipeline: parse → generate → compile → lint → testbench → simulate → report |
| `/chip-agent:generate <desc>` | Chisel source generation only (no compilation or verification) |
| `/chip-agent:debug` | Analyze simulation failures using spec, source, logs, and VCD waveforms |
| `/chip-agent:pnr` | Run place-and-route helpers through the installed MCP backend |

### Example

```
/chip-agent:workflow 4-bit ALU with add, subtract, AND, OR operations
```

This will:
1. Parse the natural language spec into structured `spec.json`
2. Generate Chisel (Scala) source code
3. Compile to Verilog via sbt + FIRRTL
4. Lint with Verilator
5. Generate a C++ testbench with test vectors
6. Simulate and collect pass/fail results
7. Report a verification summary

## Tech Stack

| Component | Purpose |
|-----------|---------|
| [Chisel](https://github.com/chipsalliance/chisel) 3.6.1 | Hardware construction language (Scala DSL) |
| Scala 2.13.10 | JVM host language (managed by sbt) |
| sbt 1.10.7 | Scala build tool |
| FIRRTL + firtool | Chisel IR → Verilog compiler (auto-managed) |
| [Verilator](https://www.veripool.org/verilator/) 5.008+ | Verilog lint + simulation |

## Project Structure

```
ChipAgent/
├── skills/                    # Slash command definitions
│   ├── workflow/SKILL.md      #   /chip-agent:workflow (full pipeline)
│   ├── generate/SKILL.md      #   /chip-agent:generate (Chisel only)
│   └── debug/SKILL.md         #   /chip-agent:debug (failure analysis)
├── agents/                    # Subagent definitions
│   ├── requirement-parser.md  #   NL → structured spec
│   ├── chisel-generator.md    #   Spec → Chisel source
│   ├── testbench-generator.md #   Spec → C++ testbench
│   └── debug-analyzer.md      #   Cross-reference failure artifacts
├── scripts/
│   ├── setup.sh               # First-use environment init
│   ├── compile.sh             # sbt compilation wrapper
│   ├── lint.sh                # Verilator lint check
│   ├── simulate.sh            # Verilator simulation (with VCD trace)
│   └── parse_vcd.py           # VCD waveform parser for debug
├── chisel-project/            # sbt project root
│   └── src/main/scala/chipagent/
│       └── Generate.scala     # Verilog emission entry point
├── generated/                 # Emitted Verilog (gitignored)
├── sim/logs/                  # Simulation logs and reports
├── .claude-plugin/plugin.json # Plugin manifest
└── package.json               # npm package for npx install
```

## License

MIT
