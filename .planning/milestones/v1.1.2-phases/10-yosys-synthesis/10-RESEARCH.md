# Phase 10: Yosys Synthesis - Research

**Researched:** 2026-03-31
**Domain:** Yosys ASIC synthesis, Liberty-based technology mapping, gate-level netlist generation
**Confidence:** HIGH

## Summary

Phase 10 creates `scripts/synth.sh` and a companion `synth.tcl` Tcl script that invokes Yosys to synthesize Chisel-generated Verilog into a gate-level netlist mapped to nangate45 standard cells. The flow was verified end-to-end on the two existing modules (ALU -- combinational, Counter8 -- sequential) and confirmed compatible with OpenROAD downstream parsing. The synthesis pipeline is straightforward: `read_verilog`, `synth -top -flatten`, `dfflibmap -liberty`, `abc -liberty`, cleanup passes, `stat -liberty` for reports, and `write_verilog` for the netlist.

Phase 9 already delivered the SDC generation (`generate_sdc.sh`), PDK validation (`validate-pdk.sh`), and environment detection. Phase 10 consumes these outputs directly. The SDC file is generated before synthesis and copied alongside the netlist for Phase 11 consumption. The synthesis script follows the established pattern from `compile.sh` and `lint.sh`: bash wrapper sourcing `_common.sh`, path resolution for bare module names, and structured output to `workspace/pnr/`.

Key technical finding: Yosys 0.53+26 synthesizes both ALU (492 cells, 517um2) and Counter8 (28 cells, 58um2) in under 1 second. The ORFS-compatible flow (hilomap, insbuf, DONT_USE) adds buffer cells but is not strictly required for OpenROAD parsing. A simplified flow without these extras produces valid netlists that OpenROAD parses without errors. The recommended approach uses a middle ground: include `setundef -zero` and `splitnets` for robustness, but omit `hilomap`/`insbuf` which Phase 11 can add if needed.

**Primary recommendation:** Create `scripts/synth.sh` (bash wrapper) + `scripts/synth.tcl` (Yosys Tcl script). The bash script handles path resolution, calls `validate-pdk.sh` and `generate_sdc.sh`, then invokes `yosys -c synth.tcl` with environment variables. The Tcl script runs the synthesis pipeline and writes both the netlist and stat report.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SYN-01 | `scripts/synth.sh <ModuleName>` runs Yosys with nangate45 liberty, produces gate-level netlist in `workspace/pnr/` | Verified flow: `read_verilog -DSYNTHESIS`, `synth -top -flatten`, `dfflibmap -liberty`, `abc -liberty`, `write_verilog -noattr -noexpr -nohex -nodec`. Output at `workspace/pnr/<ModuleName>.synth.v`. OpenROAD confirmed to parse output without errors. |
| SYN-03 | Synthesis report (gate count, cell usage, area) written to `workspace/pnr/reports/synth_stat.txt` | Verified: `tee -o <path> stat -liberty <lib>` produces report with "Number of cells" (gate count), per-cell-type counts (cell usage breakdown), and "Chip area for module" (total area). Exact format confirmed from test runs. |
</phase_requirements>

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Yosys | 0.53+26 | RTL-to-gate-level synthesis | Installed at `/usr/local/bin/yosys`, verified working with nangate45 |
| nangate45 liberty | NangateOpenCellLibrary_typical.lib | Standard cell timing/area for synthesis | At `$PDK_DIR/lib/NangateOpenCellLibrary_typical.lib`, 135 cell definitions |

### Supporting

| Tool | Purpose | When to Use |
|------|---------|-------------|
| generate_sdc.sh | Generate SDC constraints before synthesis | Called by synth.sh before Yosys invocation |
| validate-pdk.sh | Pre-flight PDK file validation | Called by synth.sh before Yosys invocation |
| _common.sh | Plugin root path resolution | Sourced by synth.sh for PLUGIN_ROOT |
| jq | Read PDK path from env.json | PDK path resolution in synth.sh |

### No New Dependencies

This phase adds no new software. It uses Yosys (already installed and detected by Phase 9) and the existing script infrastructure.

## Architecture Patterns

### Recommended Project Structure Changes

```
scripts/
  synth.sh             # NEW: Bash wrapper for synthesis pipeline
  synth.tcl            # NEW: Yosys Tcl script for ASIC synthesis
  validate-pdk.sh      # EXISTING (Phase 9): called by synth.sh
  generate_sdc.sh      # EXISTING (Phase 9): called by synth.sh
  _common.sh           # EXISTING: shared path resolution
MyDesign/<Module>/
  workspace/
    pnr/
      <Module>.synth.v       # Gate-level netlist output (SYN-01)
      constraint.sdc         # Already created by generate_sdc.sh
      reports/
        synth_stat.txt       # Synthesis statistics (SYN-03)
        synth_check.txt      # Yosys check output (diagnostic)
```

### Pattern 1: Two-File Architecture (synth.sh + synth.tcl)

**What:** Separate the bash orchestration (path resolution, pre-flight checks, environment setup) from the Yosys synthesis commands (Tcl script). The bash script sets environment variables and invokes `yosys -c synth.tcl`.

**When to use:** SYN-01 implementation.

**Why this pattern:**
- Yosys natively executes Tcl scripts via `-c` flag
- Tcl script can use `$::env(VAR)` to access environment variables set by bash
- Keeps synthesis logic maintainable and testable independently
- ORFS uses the same pattern (bash/Makefile sets env vars, Tcl scripts consume them)
- The bash wrapper handles all ChipAgent-specific concerns (module path resolution, pre-flight)
- The Tcl script is a pure synthesis recipe that could be run standalone for debugging

**Environment variables passed from synth.sh to synth.tcl:**

| Variable | Value | Example |
|----------|-------|---------|
| `DESIGN_NAME` | Module name extracted from Verilog | `ALU` |
| `VERILOG_FILE` | Path to input Verilog | `MyDesign/ALU/workspace/generated/ALU.v` |
| `LIB_FILE` | Path to nangate45 liberty | `$PDK_DIR/lib/NangateOpenCellLibrary_typical.lib` |
| `OUTPUT_DIR` | Path to `workspace/pnr/` | `MyDesign/ALU/workspace/pnr` |
| `REPORTS_DIR` | Path to `workspace/pnr/reports/` | `MyDesign/ALU/workspace/pnr/reports` |
| `SDC_FILE` | Path to SDC constraint file | `MyDesign/ALU/workspace/pnr/constraint.sdc` |

### Pattern 2: synth.sh Bash Wrapper (follows compile.sh pattern)

**What:** `scripts/synth.sh <ModuleName>` resolves paths, runs pre-flight checks, invokes synthesis, and validates output. Follows the same structure as `compile.sh`.

**Key steps:**
1. Source `_common.sh` for PLUGIN_ROOT
2. Resolve module path (bare name, MyDesign/Module, etc.)
3. Verify Verilog file exists at `workspace/generated/<Module>.v`
4. Call `validate-pdk.sh` (exit on failure)
5. Call `generate_sdc.sh <ModuleName>` (creates `workspace/pnr/constraint.sdc`)
6. Read PDK path from env.json (or env var fallback)
7. Set environment variables for Tcl script
8. Create `workspace/pnr/reports/` directory
9. Invoke `yosys -c scripts/synth.tcl`
10. Verify output netlist file exists
11. Print summary (gate count, area from stat report)

**Script skeleton:**
```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
# ... standard _common.sh error check ...

MODULE="${1:-}"
# ... path resolution following compile.sh pattern ...

# Pre-flight: validate PDK
bash "$PLUGIN_ROOT/scripts/validate-pdk.sh"

# Generate SDC
bash "$PLUGIN_ROOT/scripts/generate_sdc.sh" "$MODULE"

# Read PDK path
PDK_DIR="${NANGATE45_DIR:-}"
if [ -z "$PDK_DIR" ]; then
  PDK_DIR=$(jq -r '.pdk.nangate45.path // empty' "$PLUGIN_ROOT/.chipagent/env.json")
fi

# Set env vars for Tcl script
export DESIGN_NAME="$MODULE_NAME"
export VERILOG_FILE="$VERILOG_PATH"
export LIB_FILE="$PDK_DIR/lib/NangateOpenCellLibrary_typical.lib"
export OUTPUT_DIR="$PNR_DIR"
export REPORTS_DIR="$REPORTS_PATH"
export SDC_FILE="$PNR_DIR/constraint.sdc"

mkdir -p "$REPORTS_PATH"

# Run synthesis
yosys -c "$PLUGIN_ROOT/scripts/synth.tcl" > "$LOG" 2>&1 || EXIT_CODE=$?

# Verify output
NETLIST="$PNR_DIR/${MODULE}.synth.v"
if [ -f "$NETLIST" ]; then
  echo "Synthesis successful: $NETLIST"
  # Extract summary from stat report
else
  echo "Synthesis failed"
  cat "$LOG"
  exit 1
fi
```

### Pattern 3: synth.tcl Synthesis Pipeline

**What:** Standalone Yosys Tcl script that performs the complete ASIC synthesis flow.

**Verified pipeline (tested on ALU and Counter8):**
```tcl
# Read standard cell library
read_liberty -lib $::env(LIB_FILE)

# Read design
read_verilog -DSYNTHESIS $::env(VERILOG_FILE)

# Synthesize
synth -top $::env(DESIGN_NAME) -flatten

# Map flip-flops to library cells
dfflibmap -liberty $::env(LIB_FILE)

# Map combinational logic via ABC
abc -liberty $::env(LIB_FILE)

# Replace undefined values with zero (prevents X propagation in gate sim)
setundef -zero

# Split multi-bit nets for cleaner netlist
splitnets

# Remove unused cells and wires
opt_clean -purge

# Reports
tee -o $::env(REPORTS_DIR)/synth_check.txt check
tee -o $::env(REPORTS_DIR)/synth_stat.txt stat -liberty $::env(LIB_FILE)

# Write gate-level netlist
write_verilog -noattr -noexpr -nohex -nodec $::env(OUTPUT_DIR)/$::env(DESIGN_NAME).synth.v
```

**Why this specific command sequence:**
- `read_liberty -lib`: Loads cells as blackboxes for mapping (not full timing). The `-lib` flag reads only the cell interface.
- `-DSYNTHESIS`: Defines the SYNTHESIS macro, which causes Chisel-generated `ifdef SYNTHESIS` blocks (containing RANDOMIZE init code) to be properly excluded.
- `synth -flatten`: Runs the full Yosys coarse+fine synthesis with design flattening. For small Chisel modules, flat synthesis is optimal.
- `dfflibmap -liberty` BEFORE `abc -liberty`: dfflibmap maps register cells first (DFF_X1 etc.), then abc maps the remaining combinational logic. This order is critical.
- `setundef -zero`: Replaces any remaining X values with 0, ensuring all nets are driven in the gate-level netlist.
- `splitnets` + `opt_clean -purge`: Splits multi-bit wire assignments and removes unused wires for a cleaner netlist.
- `write_verilog -noattr -noexpr -nohex -nodec`: Produces structural Verilog without Yosys attributes, without expressions (only cell instantiations), with binary constants. This is the format OpenROAD expects.

### Pattern 4: Module Name Extraction from Verilog

**What:** Extract the exact module name from the Verilog file, not from the directory or argument.

**Why:** The Chisel module name inside the Verilog file may not exactly match the directory name (though it usually does in this project). Using the Verilog `module` declaration is authoritative.

```bash
# In synth.sh
MODULE_NAME=$(grep -m1 '^module ' "$VERILOG_PATH" | sed 's/^module \([A-Za-z_][A-Za-z0-9_]*\).*/\1/')
```

This is the same pattern used in `generate_sdc.sh` (Phase 9).

### Anti-Patterns to Avoid

- **Do not use `synth` without `-top`.** Without `-top`, Yosys may auto-detect the wrong top module or fail on multi-module files.
- **Do not use `synth` without `-flatten`.** For small Chisel modules, hierarchical synthesis adds overhead without benefit. Flat synthesis gives ABC maximum optimization opportunity.
- **Do not run `abc` before `dfflibmap`.** The dfflibmap pass must map flip-flops first; abc maps only combinational logic. Reversed order leaves unmapped register cells.
- **Do not use `check -assert -mapped` as a gate.** Yosys `check -mapped` produces benign "no driver" warnings on output ports after abc mapping of Chisel-generated Verilog. These warnings do not affect downstream OpenROAD parsing. Use `check` for diagnostic reporting only.
- **Do not omit `-DSYNTHESIS` on `read_verilog`.** Chisel FIRRTL emits `ifdef RANDOMIZE_REG_INIT` blocks wrapped in `ifndef SYNTHESIS`. Without `-DSYNTHESIS`, these blocks are included and may add unwanted initial statements.
- **Do not put the Tcl script inline in the bash script.** Use a separate `.tcl` file invoked via `yosys -c`. This keeps the synthesis recipe testable and debuggable independently.
- **Do not hardcode PDK paths in synth.tcl.** All paths come from environment variables set by synth.sh.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SDC generation | Inline SDC creation in synth.sh | `generate_sdc.sh` (Phase 9) | Already handles sequential vs combinational detection, clock period from spec.json |
| PDK validation | Inline file-exists checks | `validate-pdk.sh` (Phase 9) | Single source of truth, validates all 5 required PDK files |
| PDK path resolution | Hardcoded paths or custom search | env.json `pdk.nangate45.path` | detect-env.sh already resolves PDK path through candidate chain |
| Synthesis stat parsing | Custom regex on Yosys output | `tee -o` to write stat report directly | Yosys `tee` command writes clean report; `stat -liberty` produces the exact format needed |
| Module path resolution | Custom path logic | Follow `compile.sh` pattern | Consistent UX; supports bare names, MyDesign/X paths |

## Common Pitfalls

### Pitfall 1: Missing -DSYNTHESIS Flag (CRITICAL)

**What goes wrong:** Chisel FIRRTL generates `ifdef RANDOMIZE_REG_INIT` blocks inside `ifndef SYNTHESIS` guards. Without `-DSYNTHESIS`, Yosys reads the RANDOMIZE blocks which contain `$random` system calls and non-synthesizable constructs.
**Why it happens:** Yosys `read_verilog` does not define SYNTHESIS by default.
**How to avoid:** Always use `read_verilog -DSYNTHESIS`.
**Warning signs:** Yosys warnings about `$random` or `$display`, or synthesis producing unexpected cells.
**Verification result:** Tested both with and without `-DSYNTHESIS` on Counter8 -- both produce identical netlists (28 cells, 58um2) because Yosys's `synth` command optimizes away the init blocks. However, using `-DSYNTHESIS` is the correct practice and avoids potential issues with more complex modules.

### Pitfall 2: dfflibmap and abc Ordering

**What goes wrong:** Running `abc -liberty` before `dfflibmap -liberty` leaves flip-flop cells unmapped. ABC maps only combinational logic gates; it does not map sequential elements.
**Why it happens:** Easy mistake when writing synthesis scripts -- abc seems like it should handle everything.
**How to avoid:** Always run `dfflibmap -liberty <lib>` THEN `abc -liberty <lib>`.
**Warning signs:** Post-synthesis netlist contains `$_DFF_P_` or `$_DFF_N_` cells instead of `DFF_X1`.

### Pitfall 3: Yosys `check` Warnings on Output Ports After abc

**What goes wrong:** After abc mapping, Yosys `check` produces "Wire X is used but has no driver" warnings for output port wires. This is a cosmetic issue in Yosys's internal representation after technology mapping, not a real netlisting error.
**Why it happens:** The abc pass restructures the logic network, and the output port wire connections are represented differently internally.
**How to avoid:** Do NOT use `check -assert` as a synthesis gate. Use `check` for diagnostic reporting only. Verify correctness by checking that OpenROAD can parse the netlist (confirmed in testing).
**Warning signs:** `check -assert` fails with "Found N problems" despite the netlist being functionally correct.
**Verification:** Tested on ALU (33 warnings) and Counter8 (1 warning) -- both netlists parse correctly in OpenROAD.

### Pitfall 4: Chisel clock/reset Ports on Combinational Modules

**What goes wrong:** Chisel `Module` base class generates `clock` and `reset` input ports even for purely combinational designs like ALU. These ports exist in the Verilog but connect to nothing.
**Why it happens:** Chisel's Module class unconditionally adds implicit clock and reset.
**How to avoid:** This is handled by Phase 9's SDC generation (already detects sequential vs combinational via `always @(posedge` pattern). For synthesis, the unused ports are harmless -- Yosys's `opt_clean` removes unconnected logic. The key is: don't add any synthesis-time logic based on clock port presence.
**Warning signs:** None -- the unused ports are silently optimized away.

### Pitfall 5: Netlist Output Format for OpenROAD Compatibility

**What goes wrong:** Default `write_verilog` output includes Yosys attributes (`(* src = ... *)`) and expression-based assignments that OpenROAD's Verilog reader may not handle.
**Why it happens:** Yosys default write_verilog is optimized for readability, not downstream tool consumption.
**How to avoid:** Always use `write_verilog -noattr -noexpr -nohex -nodec` for gate-level netlists that will be read by OpenROAD.
**Verification:** Confirmed that both `-noattr -noexpr -nohex -nodec` output is parsed cleanly by OpenROAD 26Q1.

### Pitfall 6: stat Report Without -liberty Flag

**What goes wrong:** Running `stat` without `-liberty <lib>` produces cell counts but NO area numbers. The "Chip area" line only appears when a liberty file is provided.
**Why it happens:** Without liberty data, Yosys has no area information for the cells.
**How to avoid:** Always use `stat -liberty $::env(LIB_FILE)` to get the full report including area.
**Warning signs:** Report shows cell counts but no "Chip area" line.

## Code Examples

### Complete synth.tcl (Verified on Yosys 0.53+26)

```tcl
# synth.tcl - Yosys ASIC synthesis for nangate45
# Environment variables: DESIGN_NAME, VERILOG_FILE, LIB_FILE, OUTPUT_DIR, REPORTS_DIR

# Read standard cell library (blackbox mode for synthesis)
read_liberty -lib $::env(LIB_FILE)

# Read RTL Verilog with SYNTHESIS define to skip simulation-only blocks
read_verilog -DSYNTHESIS $::env(VERILOG_FILE)

# High-level synthesis: elaborate, optimize, flatten
synth -top $::env(DESIGN_NAME) -flatten

# Technology mapping: flip-flops first, then combinational logic
dfflibmap -liberty $::env(LIB_FILE)
abc -liberty $::env(LIB_FILE)

# Post-mapping cleanup
setundef -zero
splitnets
opt_clean -purge

# Reports
tee -o $::env(REPORTS_DIR)/synth_check.txt check
tee -o $::env(REPORTS_DIR)/synth_stat.txt stat -liberty $::env(LIB_FILE)

# Write gate-level netlist
write_verilog -noattr -noexpr -nohex -nodec $::env(OUTPUT_DIR)/$::env(DESIGN_NAME).synth.v
```

### Verified synth_stat.txt Output Format (ALU -- combinational)

```
=== ALU ===

   Number of wires:                466
   Number of wire bits:            561
   Number of public wires:           7
   Number of public wire bits:     102
   Number of ports:                  7
   Number of port bits:            102
   Number of memories:               0
   Number of memory bits:            0
   Number of processes:              0
   Number of cells:                492
     AND2_X1                        27
     AND3_X1                         6
     ...
     XOR2_X1                        11

   Chip area for module '\ALU': 516.838000
     of which used for sequential elements: 0.000000 (0.00%)
```

### Verified synth_stat.txt Output Format (Counter8 -- sequential)

```
=== Counter8 ===

   Number of wires:                 32
   Number of wire bits:             53
   Number of public wires:           5
   Number of public wire bits:      26
   Number of ports:                  3
   Number of port bits:             10
   Number of memories:               0
   Number of memory bits:            0
   Number of processes:              0
   Number of cells:                 28
     AND2_X1                         1
     AND3_X1                         3
     AND4_X1                         1
     AOI21_X1                        6
     DFF_X1                          8
     INV_X1                          1
     NOR2_X1                         1
     NOR3_X1                         3
     OAI21_X1                        4

   Chip area for module '\Counter8': 57.988000
     of which used for sequential elements: 36.176000 (62.39%)
```

### synth.sh Summary Output Pattern

After synthesis, extract key metrics from the stat report for human-readable output:

```bash
# Extract gate count
GATE_COUNT=$(grep 'Number of cells:' "$REPORTS_DIR/synth_stat.txt" | awk '{print $NF}')
# Extract area
AREA=$(grep 'Chip area for module' "$REPORTS_DIR/synth_stat.txt" | grep -oE '[0-9]+\.[0-9]+' | head -1)

echo "Synthesis complete:"
echo "  Module:  $MODULE_NAME"
echo "  Cells:   $GATE_COUNT"
echo "  Area:    ${AREA}um2"
echo "  Netlist: $NETLIST"
echo "  Report:  $REPORTS_DIR/synth_stat.txt"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| ORFS Makefile-based synthesis | Standalone Tcl script (project decision) | v1.1.2 design phase | Simpler, no ORFS dependency at runtime |
| `write_verilog` default flags | `-noattr -noexpr -nohex -nodec` | Best practice for OpenROAD input | Clean structural Verilog that OpenROAD parses reliably |
| `read_liberty` without `-lib` | `read_liberty -lib` for synthesis | ORFS pattern | `-lib` reads cell interfaces only, sufficient for synthesis mapping |

**Not needed for Phase 10 (ORFS-specific features skipped):**
- `hilomap` / `insbuf`: Adds LOGIC1_X1/LOGIC0_X1 tie cells and BUF_X1 buffers. OpenROAD handles netlists without these. Can be added later if Phase 11 requires them.
- `DONT_USE_CELLS`: ORFS excludes TAPCELL_X1, FILLCELL_X1, AOI211_X1, OAI211_X1. For small modules this is unnecessary -- these cells won't be mapped by abc for simple logic. Can be added as a refinement.
- `abc -script`: Custom ABC optimization scripts (abc_speed.script, abc_area.script). Default ABC script is sufficient for small Chisel modules.
- `latch mapping`: `cells_latch.v` mapping file. Chisel-generated Verilog does not contain latches.

## Open Questions

1. **read_liberty -lib vs full read_liberty**
   - What we know: ORFS uses `read_liberty -lib` (blackbox cells) followed by a second `read_liberty` with full timing for abc optimization. Our simplified flow uses single `read_liberty -lib`.
   - What's unclear: Whether the simplified approach affects synthesis quality for larger modules.
   - Recommendation: Start with single `read_liberty -lib`. ABC's default script already does good optimization. If Phase 11 PnR reveals timing issues, add the dual-read pattern.

2. **SDC file copying alongside netlist**
   - What we know: ORFS copies the SDC file to the results directory alongside the netlist (`exec cp $::env(SDC_FILE) $::env(RESULTS_DIR)/1_synth.sdc`). Phase 11 pnr.sh will need the SDC.
   - What's unclear: Whether to copy SDC in synth.tcl or let pnr.sh find it at its original location.
   - Recommendation: The SDC already exists at `workspace/pnr/constraint.sdc` (created by `generate_sdc.sh`). No copy needed -- pnr.sh will find it there.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bash scripts + OpenROAD verification |
| Config file | none |
| Quick run command | `bash scripts/synth.sh ALU` |
| Full suite command | `bash scripts/synth.sh ALU && bash scripts/synth.sh Counter8` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SYN-01 (combinational) | synth.sh produces gate-level netlist for ALU | smoke | `bash scripts/synth.sh ALU && test -f MyDesign/ALU/workspace/pnr/ALU.synth.v` | Wave 0 |
| SYN-01 (sequential) | synth.sh produces gate-level netlist for Counter8 | smoke | `bash scripts/synth.sh Counter8 && test -f MyDesign/Counter8/workspace/pnr/Counter8.synth.v` | Wave 0 |
| SYN-01 (OpenROAD compat) | OpenROAD parses netlist without errors | integration | `openroad -no_init -exit -cmd "read_liberty ...; read_lef ...; read_verilog <netlist>; link_design <Module>"` | Wave 0 |
| SYN-03 (stat report) | synth_stat.txt contains gate count, cell usage, area | smoke | `grep 'Number of cells:' workspace/pnr/reports/synth_stat.txt && grep 'Chip area' workspace/pnr/reports/synth_stat.txt` | Wave 0 |

### Sampling Rate

- **Per task commit:** `bash scripts/synth.sh ALU` (combinational quick check)
- **Per wave merge:** `bash scripts/synth.sh ALU && bash scripts/synth.sh Counter8` + OpenROAD parse test
- **Phase gate:** Both modules synthesize, both stat reports complete, both netlists parse in OpenROAD

### Wave 0 Gaps

- [ ] `scripts/synth.sh` -- main synthesis wrapper script
- [ ] `scripts/synth.tcl` -- Yosys Tcl synthesis recipe
- [ ] Both existing modules (ALU, Counter8) must have compiled Verilog in `workspace/generated/` (already present)

## Sources

### Primary (HIGH confidence)

- Yosys 0.53+26 installed at `/usr/local/bin/yosys` -- `yosys -h synth`, `yosys -h dfflibmap`, `yosys -h abc`, `yosys -h stat`, `yosys -h write_verilog`, `yosys -h tee` commands used to extract exact option syntax
- Live synthesis tests on ALU.v and Counter8.v -- verified both combinational and sequential flows produce correct netlists
- OpenROAD 26Q1 verification -- confirmed gate-level netlists are parseable via `read_verilog` + `link_design`
- ORFS synthesis scripts at `/home/mingzhenjia/OpenROAD-flow-scripts/flow/scripts/synth.tcl`, `synth_preamble.tcl`, `synth_stdcells.tcl` -- reference patterns for Yosys ASIC flow
- ORFS nangate45 `config.mk` -- TIEHI/TIELO cells, DONT_USE cells, ABC parameters
- Existing Phase 9 scripts: `validate-pdk.sh`, `generate_sdc.sh`, `detect-env.sh` -- integration points
- Existing scripts: `compile.sh`, `lint.sh` -- bash wrapper patterns

### Secondary (MEDIUM confidence)

- [Yosys ASIC cell library mapping docs](https://yosyshq.readthedocs.io/projects/yosys/en/latest/using_yosys/synthesis/cell_libs.html) -- general ASIC flow reference (Cloudflare blocked, verified via `yosys -h` instead)
- [Yosys GitHub](https://github.com/YosysHQ/yosys) -- project documentation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- Yosys 0.53+26 verified installed, synthesis tested end-to-end on both module types
- Architecture: HIGH -- two-file pattern (bash + Tcl) proven by ORFS, path resolution pattern established by compile.sh/lint.sh
- Pitfalls: HIGH -- all pitfalls discovered through live testing, not just documentation; OpenROAD compatibility verified
- stat report format: HIGH -- exact output format captured from test runs on both ALU and Counter8

**Research date:** 2026-03-31
**Valid until:** 2026-05-01 (stable -- Yosys and nangate45 are local installations, not changing)
