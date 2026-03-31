# Research Summary: ChipAgent v1.1.2 RTL-to-GDS

**Domain:** RTL-to-GDS physical implementation via Yosys synthesis + OpenROAD PnR
**Researched:** 2026-03-31
**Overall confidence:** HIGH

## Executive Summary

ChipAgent v1.1.2 adds a `/chip-agent:pnr` command that takes verified RTL Verilog (already produced by the existing pipeline) and runs it through Yosys synthesis and OpenROAD place-and-route to produce a routed DEF and timing/power/area reports using the nangate45 PDK. All required tools are already installed: Yosys 0.53+26 at `/usr/local/bin/yosys` and OpenROAD 26Q1 at `/usr/bin/openroad`. The nangate45 PDK is available at `/home/mingzhenjia/OpenROAD-flow-scripts/flow/platforms/nangate45/`.

The key architectural decision is to write standalone shell scripts that invoke Yosys and OpenROAD directly with generated Tcl, rather than using the OpenROAD-flow-scripts (ORFS) Makefile. ORFS requires ~50+ environment variables and a rigid directory structure that conflicts with ChipAgent's per-module workspace isolation. The actual Tcl commands are well-understood -- ORFS complexity is in configurability, not in the core flow. By generating Tcl scripts per-run, ChipAgent can template module names, paths, and clock periods cleanly.

SDC constraint generation is the critical bridge between RTL and physical design. ChipAgent must auto-detect whether a module is combinational or sequential by parsing the Verilog for clock ports (Chisel names them `clock`), then generate appropriate SDC. Sequential modules get `create_clock` on the real port; combinational modules get a virtual clock with `set_max_delay`. A 2.0ns default clock period is conservative enough to avoid timing failures while still driving meaningful synthesis optimization.

One notable gap: KLayout is not installed, so GDS export is not possible in the current environment. The DEF + reports output is the core deliverable for v1.1.2; GDS export can be added later when KLayout is available.

## Key Findings

**Stack:** Yosys 0.53+26 and OpenROAD 26Q1 are installed and verified. nangate45 PDK is complete with liberty, LEF, GDS, and RC extraction rules. KLayout is missing (no GDS export).

**Architecture:** Three new scripts (generate_sdc.sh, synth.sh, pnr.sh) wrapping standalone Yosys/OpenROAD with generated Tcl. Single OpenROAD session runs floorplan through final reports. Output goes to `workspace/pnr/`.

**Critical pitfall:** Chisel-generated Verilog uses `io_` prefix on port names (e.g., `io_a`, `io_result`), but the Chisel module name in Verilog matches the Scala class name exactly. The SDC `current_design` must use the exact module name from the Verilog file, and port references in SDC must use the `io_`-prefixed names.

## Implications for Roadmap

Based on research, suggested phase structure:

1. **Environment + SDC Foundation** - Extend env detection for Yosys/OpenROAD/nangate45, implement SDC generation with clock detection
   - Addresses: Tool availability checking, constraint generation
   - Avoids: Hardcoded paths, missing tool errors at runtime
   - Dependencies: None (existing workspace structure sufficient)

2. **Yosys Synthesis** - Implement synth.sh with Tcl generation, handle combinational vs sequential
   - Addresses: Gate-level netlist production, synthesis reports
   - Avoids: ORFS Makefile dependency
   - Dependencies: Phase 1 (needs SDC file)

3. **OpenROAD PnR** - Implement pnr.sh with full floorplan-to-route Tcl, conditional CTS
   - Addresses: Physical layout, timing/power/area reports, DEF output
   - Avoids: Multi-invocation ODB file juggling
   - Dependencies: Phase 2 (needs synthesized netlist)

4. **Skill + Report Integration** - Create `/chip-agent:pnr` skill, report parsing, pipeline integration
   - Addresses: User-facing command, human-readable report summary
   - Avoids: Raw Tcl output dumped to user
   - Dependencies: Phase 3 (needs working scripts)

**Phase ordering rationale:**
- SDC must exist before synthesis (Yosys reads it for timing-driven ABC)
- Synthesis must complete before PnR (OpenROAD reads the netlist)
- Scripts must work before the skill wraps them
- Environment detection is foundational and fast to implement

**Research flags for phases:**
- Phase 2: May need research on Yosys `write_verilog` flag behavior -- the `-noattr` flag is important to avoid OpenROAD parse errors
- Phase 3: The CTS skip logic for combinational modules needs testing -- verify `[llength [all_clocks]]` returns 0 with virtual clocks
- Phase 4: Report parsing format depends on actual OpenROAD output; build from real output samples

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All tools verified on local machine, PDK files inspected |
| Features | HIGH | Scope well-defined in PROJECT.md, standard EDA flow |
| Architecture | HIGH | ORFS scripts analyzed in detail, standalone approach validated |
| Pitfalls | MEDIUM | Some pitfalls (like CTS skip behavior) need runtime verification |

## Gaps to Address

- KLayout installation status -- needed for GDS export, not currently installed
- Exact `write_verilog` flags needed to produce OpenROAD-compatible netlist (may need `-noattr -noexpr`)
- CTS behavior with virtual clocks on combinational modules -- needs runtime test
- OpenROAD `report_power` output format -- need sample output for report parsing
- Whether nangate45 PDN grid script works for very small designs (< 50 cells) without modification

---
*Research summary for: ChipAgent v1.1.2 -- RTL-to-GDS via Yosys + OpenROAD*
*Researched: 2026-03-31*
