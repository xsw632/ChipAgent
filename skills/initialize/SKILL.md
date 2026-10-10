---
name: initialize
description: Detect local toolchain versions and write .chipagent/env.json with capability flags. Updates CLAUDE.md Tech Stack table with detected versions.
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
---

# chip-agent:initialize

Detect the local toolchain environment and report which ChipAgent capabilities are available on this machine.

## Usage

```
/chip-agent:initialize
```

## Instructions

1. **Determine the project root directory** from the user's current working project (the directory containing `scripts/` and `chisel-project/`; `MyDesign/` is created on first use), not from the skill's installation location. Use that directory as the base for all paths below.

2. **Run the environment detection script** via Bash:
   ```
   <project-root>/scripts/detect-env.sh
   ```
   This script detects installed versions of Java, sbt, Scala, Verilator, Make, g++, Yosys, OpenROAD, and KLayout, detects the sky130hd PDK, ORFS installation, Docker availability, Chipyard installation, and RISCV toolchain, computes capability flags, and writes the results to `.chipagent/env.json`. The script output includes a human-readable summary.

3. **Read the detection results** using the Read tool:
   ```
   <project-root>/.chipagent/env.json
   ```
   Parse the JSON to extract tool versions and capability flags.

4. **Update the CLAUDE.md Tech Stack table** using the Edit tool. Update ONLY these rows with detected versions:
   - **Scala**: Update the Version column with the detected scala version. Note: the project pins Scala 2.13.10 in `build.sbt` regardless of the system Scala version -- add a note if they differ.
   - **sbt**: Update the Version column with the detected sbt version.
   - **Verilator**: Update the Version column with the detected verilator version.

   If a tool is not installed, leave the row unchanged (keep the existing placeholder version).
   Do NOT modify the Chisel, FIRRTL, or Claude Code Plugin rows -- those versions are pinned in project configuration files.

5. **Present a summary** to the user showing:
   - Each tool's status (installed with version, or missing)
   - Capability flags:
     - **Can Compile** (requires Java + sbt): whether Chisel-to-Verilog compilation is possible
     - **Can Lint** (requires Verilator): whether Verilog lint checking is possible
     - **Can Simulate** (requires Verilator + Make + g++): whether full simulation is possible
     - **Can Synthesize** (requires Yosys + sky130hd PDK + ORFS): whether RTL synthesis is possible
     - **Can PnR** (requires OpenROAD + sky130hd PDK): whether place-and-route is possible
     - **Can GDS** (requires KLayout + sky130hd PDK + GDS cell library): whether GDS export is possible
     - **Can Chipyard** (requires Chipyard + RISCV toolchain): whether Chipyard RTL generation is possible
   - For any missing tools, provide install instructions:
     - Java: Install JDK 11+ (`apt install default-jdk` or download from https://adoptium.net)
     - sbt: Install from https://www.scala-sbt.org/download
     - Scala: Install from https://www.scala-lang.org/download/ (optional -- sbt manages Scala for compilation)
     - Verilator: Install from https://verilator.org or `apt install verilator`
     - Make: Install via `apt install make` or Xcode Command Line Tools
     - g++: Install via `apt install g++` or Xcode Command Line Tools
     - Yosys: Install via `apt install yosys`
     - OpenROAD: Install via `apt install openroad`
     - KLayout: Install via `apt install klayout`
   - sky130hd PDK: detected automatically from OpenROAD-flow-scripts installation at flow/platforms/sky130hd/
   - ORFS: detected automatically from OpenROAD-flow-scripts installation (flow/Makefile)
   - Docker: detected if available, determines backend_mode (local/docker)
   - Chipyard: Clone from https://github.com/ucb-bar/chipyard and follow setup instructions at https://chipyard.readthedocs.io
   - RISCV: Install via Chipyard's `scripts/setup-tools.sh` or set `RISCV` env var to toolchain path
   - Note that the Scala version in `build.sbt` (2.13.10) is independent of the system Scala version

## Input

`$ARGUMENTS` -- none expected. This command takes no arguments.

## Output

- `.chipagent/env.json` -- Machine-readable environment detection results (tools, PDK, Chipyard, RISCV, capabilities)
- Updated CLAUDE.md Tech Stack table with detected local versions
