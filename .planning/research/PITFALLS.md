# Domain Pitfalls: RTL-to-GDS via Yosys + OpenROAD

**Domain:** ChipAgent v1.1.2 -- Adding Yosys synthesis + OpenROAD PnR to Chisel pipeline
**Researched:** 2026-03-31
**Confidence:** HIGH (7 pitfalls verified from running ORFS GCD; remainder from codebase analysis, ORFS script reading, and issue trackers)
**Supersedes:** Earlier pitfalls draft from same date (adds verified issues, deeper ORFS script analysis, Chisel-specific gotchas)

---

## Critical Pitfalls

Mistakes that cause flow aborts, silent wrong results, or require architectural rework.

### Pitfall 1: Chisel `Module` Always Emits `clock` and `reset` Ports -- Even for Combinational Logic

**What goes wrong:** Every Chisel class extending `Module` generates `clock` and `reset` top-level ports in Verilog, even for purely combinational logic like ALU or Decoder3to8. The SDC must account for these ports. If the SDC references `clock` with `create_clock`, OpenROAD will attempt CTS on a design with no flip-flops, causing CTS to insert buffers on a clock net that drives nothing, wasting area and potentially triggering placement errors.

**Why it happens:** Chisel's `Module` base class unconditionally adds implicit `clock` and `reset` ports. The ALU module (`ALU.scala`) extends `Module` but uses no registers -- it is purely combinational. The generated FIRRTL confirms: `input clock : Clock` and `input reset : UInt<1>` appear even though neither is used internally. After Verilog emission, these ports exist but connect to nothing.

**Consequences:** CTS inserts unnecessary clock buffers. If `create_clock` is applied to a clock port that connects to no sequential elements, OpenROAD may still try to build a clock tree, adding cells and consuming routing resources for nothing. Alternatively, if SDC omits the clock entirely, OpenROAD may warn about unconstrained ports.

**Prevention:**
- The SDC generator must detect whether the module actually uses registers (not just whether it has a clock port)
- Heuristic: grep the generated Verilog for `always @(posedge` -- if absent, treat as combinational despite the clock port existing
- For combinational modules: use virtual clock in SDC, `set_false_path` on clock/reset inputs, and guard CTS with `if { [llength [all_clocks]] > 0 }` (already in STACK.md)
- Consider adding `set_dont_touch` on the clock/reset ports so they pass through without buffering

**Detection:** CTS log shows "0 sinks" but still inserts buffers. Area report shows clock buffer cells in a combinational design.

**Phase:** Phase 1 (SDC generation). The clock-detection heuristic is the very first thing to get right.

---

### Pitfall 2: Chisel `io_` Port Prefix Mismatch in SDC and Synthesis

**What goes wrong:** Chisel generates port names with `io_` prefix (e.g., `io_a`, `io_b`, `io_result`, `io_zero`). SDC constraints or synthesis scripts that reference ports by their Chisel/spec names (`a`, `b`, `result`) will silently match nothing. OpenROAD will report unconstrained I/O or fail to apply timing constraints.

**Why it happens:** Chisel's `io` bundle naming convention: `io.portName` in Scala becomes `io_portName` in Verilog. This is documented in CLAUDE.md but easy to forget when auto-generating SDC from spec.json (which uses the un-prefixed names). The `clock` and `reset` ports are exceptions -- they are implicit and NOT prefixed with `io_`.

**Consequences:** `set_input_delay` and `set_output_delay` silently do nothing if port names don't match. STA reports show unconstrained paths. Synthesis may not optimize critical paths because ABC sees no timing budget.

**Prevention:**
- SDC generator must use `[all_inputs]` and `[all_outputs]` wildcards instead of named ports where possible
- When excluding clock from input delay constraints, filter by actual port name: `lsearch -all -inline -not [all_inputs] clock`
- When specific port references are needed, always prepend `io_` to spec.json port names
- Add a validation step: after `read_sdc`, check for warnings about ports not found

**Detection:** STA report shows "No constrained paths" or "unconstrained endpoints." Yosys `stat` shows the same cell count regardless of clock period changes (meaning ABC timing constraints had no effect).

**Phase:** Phase 1 (SDC generation) and Phase 2 (synthesis). Must be correct from the start.

---

### Pitfall 3: Floorplan Too Small for PDN Stripes on Small Modules

**What goes wrong:** For tiny modules (e.g., TrivialModule with ~1 cell, Decoder3to8 with ~10 cells), `initialize_floorplan -utilization 55` produces a core area so small that the nangate45 PDN grid cannot fit metal4/metal7 power stripes. OpenROAD aborts with errors like `[ERROR PDN-0085] Pitch specified for layer metal4 is less than 2 x (width + spacing)` or `[ERROR PDN-0185] Insufficient width to add straps`.

**Why it happens:** The nangate45 `grid_strategy-M1-M4-M7.tcl` defines metal4 stripes with pitch=56.0um and metal7 stripes with pitch=30.0um and width=1.40um. A module with 5 cells at 55% utilization might produce a core of only 10x10um -- too small for even one metal4 stripe pitch. This is a well-documented issue (OpenLane #879, #1713, #2053; OpenROAD #2027).

**Consequences:** Flow aborts at PDN generation. No workaround within the existing PDN script -- the entire floorplan must be resized.

**Prevention:**
- Calculate a minimum core area based on PDN pitch requirements: at least 60um x 60um for nangate45 (to accommodate one full metal4 pitch of 56um plus margins)
- After `initialize_floorplan`, check the die area. If smaller than the minimum, override with explicit die/core area coordinates
- Alternative for very small modules: use a simplified PDN with only metal1 followpins (skip metal4/metal7 stripes) -- requires a custom PDN Tcl
- Set a floor on utilization: cap at 30% for modules under 50 cells to ensure adequate area
- Increase `core_space` to 5.0 (from 2.0) for small designs to pad the die

**Detection:** PDN error messages containing "PDN-0085", "PDN-0175", or "PDN-0185". The pnr.sh script must catch these and retry with larger area.

**Phase:** Phase 3 (floorplan). Must implement minimum-area logic before first PnR run.

---

### Pitfall 4: ORFS Platform Tcl Files Reference `$::env()` Variables That ChipAgent Does Not Set

**What goes wrong:** The STACK.md plan calls for sourcing nangate45 platform Tcl files directly (e.g., `source ${PLATFORM_DIR}/fastroute.tcl`, `source ${PLATFORM_DIR}/tapcell.tcl`). These files reference ORFS environment variables that ChipAgent's standalone scripts do not set:
- `fastroute.tcl` needs: `MAX_ROUTING_LAYER`, `MIN_ROUTING_LAYER`, `MIN_CLK_ROUTING_LAYER`
- `tapcell.tcl` needs: `TAP_CELL_NAME`

Missing env vars cause Tcl errors: `can't read "::env(MAX_ROUTING_LAYER)": no such variable`.

**Why it happens:** These Tcl files were written for the ORFS Makefile, which sets 50+ env vars from `config.mk` + `variables.mk` before sourcing them. ChipAgent bypasses the Makefile but still sources the platform Tcl files.

**Consequences:** OpenROAD aborts with Tcl variable-not-found errors. The error message is clear but the root cause (missing env vars for platform scripts) is non-obvious.

**Prevention:** Two options:
1. **Set required env vars in generated Tcl:** Add `set ::env(MAX_ROUTING_LAYER) metal10` etc. at the top of the PnR Tcl script
2. **Inline the commands instead of sourcing:** Replace `source fastroute.tcl` with the actual commands using hardcoded nangate45 values

Recommended: **Option 2 for `fastroute.tcl` and `tapcell.tcl`** (small files with env var deps). Keep `source` for `make_tracks.tcl`, `setRC.tcl`, and `grid_strategy-M1-M4-M7.tcl` (which have no env var dependencies -- verified by grep).

Specifically, inline these:
```tcl
# Instead of: source ${PLATFORM_DIR}/fastroute.tcl
set_global_routing_layer_adjustment metal2-metal3 0.5
set_global_routing_layer_adjustment metal4-metal10 0.25
set_routing_layers -clock metal4-metal10
set_routing_layers -signal metal2-metal10

# Instead of: source ${PLATFORM_DIR}/tapcell.tcl
tapcell -distance 120 -tapcell_master TAPCELL_X1 -endcap_master TAPCELL_X1
```

**Detection:** Tcl error: `can't read "::env(...)": no such variable`.

**Phase:** Phase 3 (PnR script generation). Must be resolved when writing the Tcl template.

---

### Pitfall 5: OpenROAD Tcl Errors Do Not Always Abort the Flow

**What goes wrong:** Some OpenROAD commands issue warnings or non-fatal errors but do not set a non-zero Tcl return code. The script continues past the failure, producing corrupt or incomplete results. For example, `pdngen` may warn about insufficient stripes but still "succeed" with a partial PDN. `repair_timing` may fail to meet timing but returns 0. `global_placement` may diverge and write a failed ODB.

**Why it happens:** OpenROAD uses a mix of `utl::error` (which aborts) and `utl::warn` (which continues). Not all failure modes are hard errors. ORFS wraps many commands in `catch` blocks and checks metrics -- e.g., in `global_place.tcl` lines 60-64:
```tcl
set result [catch { do_placement $global_placement_args } errMsg]
if { $result != 0 } {
    orfs_write_db $::env(RESULTS_DIR)/3_3_place_gp-failed.odb
    error $errMsg
}
```
ChipAgent's standalone scripts lack this infrastructure.

**Consequences:** PnR completes but the design has no power connections (partial PDN), unrouted nets, or massive timing violations. The user sees a "success" message but the DEF/reports are wrong.

**Prevention:**
- Wrap critical commands in `catch` and check return codes:
  ```tcl
  if { [catch { detailed_placement } msg] } {
      puts "ERROR: Placement failed: $msg"
      exit 1
  }
  ```
- After each major stage, add explicit post-condition checks:
  - After `pdngen`: verify power grid existence
  - After `detailed_placement`: `check_placement -verbose`
  - After `detailed_route`: check `[design_is_routed]` returns true (ORFS `detail_route.tcl` line 76)
  - After reports: parse WNS/TNS and flag if beyond threshold
- Exit with non-zero status on any post-condition failure

**Detection:** Reports show anomalous values (zero area, massive negative slack, zero power). DRC report is non-empty. `route_drc.rpt` has violations.

**Phase:** Phase 3 (PnR script). Every stage needs `catch` + post-condition checks.

---

### Pitfall 6: Timing Constraints Too Tight Causing Massive Violations

**What goes wrong:** An aggressive clock period (e.g., 0.46ns like the ORFS GCD example) causes dozens of setup timing violations. The flow "succeeds" but the timing report shows negative slack everywhere. For auto-generated educational modules, this is confusing and makes the reports look like failures.

**Why it happens:** The ORFS GCD example uses 0.46ns as a demonstration of a challenging constraint. ChipAgent users will not know what a reasonable clock period is for their module.

**Consequences:** 34+ setup violations (as observed in GCD with 0.46ns). Confusing reports for users who don't understand that timing closure is a design goal, not a pass/fail gate.

**Prevention:**
- Default clock period: 2.0ns (500MHz). Conservative for nangate45, should achieve timing closure for most educational modules
- Allow override via `spec.json` field `clock_period_ns`
- After STA, parse WNS (worst negative slack). If WNS < -0.5ns, add a note in the report suggesting the user relax the clock period
- For combinational modules, use `set_max_delay` with a generous budget (e.g., 5.0ns)

**Detection:** WNS report shows large negative values. TNS is significantly negative.

**Phase:** Phase 1 (SDC generation). The default constraint must be conservative.

---

## Moderate Pitfalls

### Pitfall 7: FIRRTL/firtool May Emit Yosys-Incompatible SystemVerilog (Future Risk)

**What goes wrong:** Depending on the Chisel/firtool version and lowering options, the generated Verilog may contain SystemVerilog constructs (packed arrays, `automatic` variables inside `always` blocks, `always_comb`, type casts) that Yosys rejects.

**Why it happens:** ChipAgent currently uses Chisel 3.6.1 with the built-in FIRRTL compiler (not CIRCT/firtool). This version emits plain Verilog 2005 with simple `always @(posedge ...)` and `assign` statements. **Current risk is LOW.** However, if upgrading to Chisel 5.x (which uses CIRCT/firtool by default), the output will be SystemVerilog with constructs Yosys cannot handle.

**Known incompatibilities (from CIRCT issue tracker):**
- Packed arrays: `wire [15:0][3:0] foo` -- Yosys error: `unexpected '['`
- Type casts: `OP_CAST` -- Yosys error: `unexpected OP_CAST`
- Automatic variables: `automatic logic` inside `always @(posedge clock)` -- Yosys rejects

**Prevention:**
- **Current stack (Chisel 3.6.1):** No action needed. Verify with a pre-synthesis parse check: `yosys -p "read_verilog ${FILE}; hierarchy -check"` -- this catches any parse errors early
- **If upgrading to Chisel 5.x:** Pass firtool options: `--lowering-options=disallowLocalVariables,disallowPackedArrays,noAlwaysComb`
- Always use `read_verilog` (not `read_verilog -sv`) for Chisel 3.6.1 output

**Detection:** Yosys syntax errors during `read_verilog`.

**Phase:** Phase 2 (synthesis). Add Verilog parse validation as a pre-check. Low risk for current stack but document for future upgrades.

---

### Pitfall 8: Module Name Mismatch Between Yosys `synth -top` and OpenROAD `link_design`

**What goes wrong:** Yosys's `synth -top` uses one name, the SDC uses `current_design` with a different name, and OpenROAD's `link_design` uses yet another. Any mismatch causes "module not found" or "design not linked" errors.

**Why it happens:** The module name flows through four artifacts (Verilog source, SDC, Yosys Tcl, OpenROAD Tcl) and must be identical in all four. Chisel class name `ALU` becomes module name `ALU` in Verilog. But if someone mistakenly uses `chipagent.ALU` (the Scala fully-qualified name) or a filename-derived name, it breaks.

**Prevention:**
- Extract the module name from the Verilog file itself: `grep "^module " <file>.v | awk '{print $2}'` (strip the trailing semicolon or parenthesis)
- Pass this extracted name to ALL downstream scripts and templates as a single `MODULE_NAME` variable
- Never derive the module name from the file path, directory name, or spec.json independently

**Detection:** Yosys: "Can't find top module." OpenROAD: `link_design` error "module X is not part of the design."

**Phase:** Phase 2 (synthesis) and Phase 3 (PnR). Build the extraction into the SDC generation script (Phase 1).

---

### Pitfall 9: Yosys `write_verilog` Flags Affect OpenROAD Compatibility

**What goes wrong:** Yosys's `write_verilog` has many flags. Missing `-noattr` leaves Yosys-internal attributes (`(* src = "..." *)`) in the netlist that OpenROAD cannot parse. Missing `-noexpr` may leave complex expressions. ORFS uses `-nohex -nodec` (verified at `synth.tcl` line 244).

**Prevention:**
- Always use: `write_verilog -noattr -noexpr -nohex -nodec ${OUTPUT_FILE}`
- After writing, optionally validate: `openroad -no_init -exit "read_verilog synth.v; link_design ${MODULE}"`

**Detection:** OpenROAD parse errors when reading the synthesized netlist.

**Phase:** Phase 2 (synthesis). Get the flags right in the Yosys Tcl template from day one.

---

### Pitfall 10: ABC Timing Target in Picoseconds, Not Nanoseconds

**What goes wrong:** ABC's `-D` flag expects clock period in picoseconds. Passing `2.0` (nanoseconds) instead of `2000` (picoseconds) makes ABC optimize for 2ps -- an impossibly tight target. This causes ABC to insert excessive buffering, bloating the netlist by 5-10x.

**Why it happens:** Unit mismatch between SDC (nanoseconds) and ABC (picoseconds). Easy to forget the conversion.

**Prevention:**
- Explicit conversion in the synthesis script: `CLOCK_PERIOD_PS = CLOCK_PERIOD_NS * 1000`
- For 2.0ns default: pass `-D 2000` to ABC
- For combinational modules: omit `-D` entirely (no clock period concept)

**Detection:** Synthesis cell count is unreasonably high (10x expected). `synth_stat.txt` shows a netlist much larger than the RTL would suggest.

**Phase:** Phase 2 (synthesis).

---

### Pitfall 11: `setundef -zero` Missing Causes X-Propagation in Gate-Level Sim

**What goes wrong:** Chisel's FIRRTL compiler may leave undefined values in the netlist for don't-care conditions. If Yosys does not replace these with defined values, the gate-level netlist contains `$undef` assignments. Post-synthesis simulation shows unexpected `X` propagation.

**Why it happens:** ORFS includes `setundef -zero` in its synthesis flow (after technology mapping, before `write_verilog`). This replaces all undefined values with logic-0. Without it, `$undef` cells remain.

**Prevention:**
- Include `setundef -zero` in the Yosys synthesis script after `abc` and before `write_verilog`
- This is safe for all educational designs (don't-care becoming 0 is fine)

**Detection:** Gate-level simulation shows `X` values. Verilator warnings about undriven signals in synthesized netlist.

**Phase:** Phase 2 (synthesis). Already noted in STACK.md template -- do not remove.

---

### Pitfall 12: `global_placement -density` Too Low for Small Designs

**What goes wrong:** Using low placement density (e.g., 0.30) for a small module causes global placement to diverge because cells cannot be spread across the available area. OpenROAD may report "GPL-0301: placement diverged."

**Why it happens:** ORFS uses a `place_density_with_lb_addon` function that dynamically adjusts density. ChipAgent's standalone scripts use a fixed value.

**Prevention:**
- Use placement density 0.70 for modules with fewer than 100 cells
- Use 0.50 for medium modules (100-1000 cells)
- Use 0.30 for larger designs (1000+ cells)
- Read cell count from `synth_stat.txt` to choose density automatically

**Detection:** Global placement error "GPL-0301" or unusually long convergence time.

**Phase:** Phase 3 (PnR). Parameterize density based on cell count from synthesis report.

---

### Pitfall 13: Missing `set_propagated_clock` Before Final Timing Reports

**What goes wrong:** Without `set_propagated_clock [all_clocks]` after CTS, OpenROAD uses ideal clock arrival times for STA. Timing reports show unrealistically optimistic slack because clock tree insertion delay is ignored.

**Prevention:**
- Always call `set_propagated_clock [all_clocks]` after CTS and before final timing reports
- For combinational modules (no CTS), this is a no-op since there are no real clocks
- The STACK.md Tcl template already includes this inside the CTS block -- ensure it stays

**Detection:** Timing reports show suspiciously good slack values. Setup slack improves after CTS (should get worse due to clock insertion delay).

**Phase:** Phase 3 (PnR). Already in template.

---

### Pitfall 14: Parasitic Extraction Requires `rcx_patterns.rules`

**What goes wrong:** The PnR script includes `extract_parasitics -ext_model_file ${PLATFORM_DIR}/rcx_patterns.rules`. If this file is missing or the path is wrong, OpenROAD aborts. Without SPEF, final timing/power reports use estimated parasitics, which can be 2-3x off.

**Prevention:**
- Verify file existence in env detection: `test -f "${PLATFORM_DIR}/rcx_patterns.rules"`
- If missing, fall back to `estimate_parasitics -placement` (less accurate but functional)
- Include the check in `detect-env.sh` additions

**Detection:** OpenROAD error during `extract_parasitics`.

**Phase:** Phase 3 (PnR). Add file existence check in env detection.

---

## Minor Pitfalls

### Pitfall 15: `dfflibmap` Warnings on Combinational Designs

**What goes wrong:** Running `dfflibmap -liberty ${LIB_FILE}` on a purely combinational design is harmless (no flip-flops to map) but may emit warnings that confuse Claude's error detection.

**Prevention:** For combinational modules, omit `dfflibmap`. Detect: if no `always @(posedge` in Verilog, skip it. Or include unconditionally and suppress warnings.

**Phase:** Phase 2 (synthesis). Low priority -- cosmetic.

---

### Pitfall 16: `splitnets` Required Before `write_verilog`

**What goes wrong:** Without `splitnets`, Yosys may write compound assign statements like `assign {a, b, c} = {d, e, f}`. Some versions of OpenROAD's Verilog reader cannot parse compound assignments.

**Prevention:** Always include `splitnets` after `opt_clean` and before `write_verilog` (as ORFS does at line 211 of `synth.tcl`).

**Detection:** OpenROAD parse error with "unexpected '{'" in the netlist.

**Phase:** Phase 2 (synthesis). Already in STACK.md Yosys template.

---

### Pitfall 17: `filler_placement` Must Come After `detailed_route`

**What goes wrong:** If filler cells are inserted before routing, they block routing tracks. If inserted after routing but before parasitic extraction, extraction may not account for filler cell capacitance.

**Prevention:** Correct order: `detailed_route` -> `filler_placement` -> `check_placement` -> `extract_parasitics`. This is already the order in STACK.md -- do not reorder.

**Phase:** Phase 3 (PnR). Follow STACK.md order exactly.

---

### Pitfall 18: `repair_timing` Can Significantly Increase Cell Count

**What goes wrong:** `repair_timing -setup -hold` inserts buffers and resizes cells to meet timing. A 200-cell design might grow to 350+ cells. This is expected but can surprise users.

**Prevention:** Not a bug -- expected behavior. Report pre-repair and post-repair cell counts in the summary for transparency. Do not assert on post-PnR cell count.

**Phase:** Phase 4 (report parsing). Include before/after metrics.

---

### Pitfall 19: Yosys `check -assert -mapped` vs `check` Without Flags

**What goes wrong:** Plain `check` reports warnings about undriven/unused bits that are common in Chisel output (e.g., unused reset bits). If the script treats any `check` output as failure, it aborts unnecessarily. Using `check -assert -mapped` is stricter but only flags real errors (unmapped cells, connectivity issues).

**Prevention:** Use `tee -o ${REPORTS_DIR}/synth_check.txt check` for logging, and `check -assert -mapped` for pass/fail. The `-mapped` flag requires all cells to be technology-mapped (run after `abc`). ORFS uses this pattern (lines 234-241 of `synth.tcl`).

**Phase:** Phase 2 (synthesis).

---

## Verified Issues from ORFS GCD Testing

These were discovered during hands-on testing and are confirmed.

| # | Issue | Impact | Mitigation | Status |
|---|-------|--------|------------|--------|
| V1 | ORFS version must match OpenROAD version (HEAD failed with `sta::endpoint_count`, 26Q1 tag works) | Flow fails to start | ChipAgent uses standalone scripts, not ORFS Makefile -- bypasses entirely | Resolved by architecture |
| V2 | ORFS expects `IN_NIX_SHELL` for system tools, otherwise looks in `tools/install/` -- need explicit EXE vars | Wrong tool paths | Standalone scripts bypass ORFS entirely | Resolved by architecture |
| V3 | GDS merge requires KLayout (not installed) | No GDS output | Scope v1.1.2 to DEF output; GDS is follow-up | Accepted limitation |
| V4 | Chisel generates `io_` prefixed ports (`io_portName`) | SDC/testbench port name mismatch | See Pitfall 2 | Addressed in design |
| V5 | Combinational modules have no clock -- SDC/CTS need special handling | CTS fails or wastes resources | See Pitfall 1 | Addressed in design |
| V6 | nangate45 `PLACE_SITE` is `FreePDK45_38x28_10R_NP_162NW_34O` -- must be exact | Floorplan fails | Hardcode in Tcl template; never derive dynamically | Addressed in STACK.md |
| V7 | Timing constraints too tight (GCD had 34 violations with 0.46ns period) | Confusing reports | See Pitfall 6; default to 2.0ns | Addressed in design |

---

## Phase-Specific Warning Summary

| Phase | Topic | Pitfalls | Aggregate Severity |
|-------|-------|----------|-------------------|
| Phase 1 | SDC Generation | P1 (clock vs combinational), P2 (io_ prefix), P6 (timing too tight), P8 (module name) | CRITICAL -- errors here cascade to all downstream stages |
| Phase 2 | Yosys Synthesis | P7 (SV constructs), P9 (write_verilog flags), P10 (ABC ps units), P11 (setundef), P15 (dfflibmap), P16 (splitnets), P19 (check flags) | HIGH -- most have clear fixes in the Tcl template |
| Phase 3 | OpenROAD PnR | P3 (small floorplan), P4 (env vars in platform Tcl), P5 (silent errors), P12 (density), P13 (propagated clock), P14 (rcx rules), P17 (filler order) | CRITICAL -- PnR has the most failure modes |
| Phase 4 | Report Parsing | P5 (partial success detection), P6 (interpreting violations), P18 (cell count growth) | MODERATE -- cosmetic but affects user trust |
| Future | Chisel Upgrade | P7 (firtool SV output) | LOW now, CRITICAL if upgrading |

---

## Sources

- **Codebase analysis:** `ALU.scala`, `Generate.scala`, `TrivialModule.scala`, `Decoder3to8.scala`, `ALU.fir` -- confirmed Chisel 3.6.1 output format, `io_` port naming, and implicit clock/reset on all modules
- **ORFS script analysis (verified 2026-03-31):**
  - `synth.tcl` lines 211-248: `splitnets`, `setundef -zero`, `write_verilog -nohex -nodec`, `check -assert -mapped`
  - `global_place.tcl` lines 60-64: `catch` + error handling pattern for placement
  - `cts.tcl` lines 47-51: `catch` around `detailed_placement`
  - `detail_route.tcl` line 76: `design_is_routed` post-condition check
  - `floorplan.tcl`: env var sourcing patterns, `PLACE_SITE` usage
- **nangate45 platform files (verified 2026-03-31):**
  - `fastroute.tcl`: references `$::env(MAX_ROUTING_LAYER)`, `$::env(MIN_ROUTING_LAYER)`, `$::env(MIN_CLK_ROUTING_LAYER)`
  - `tapcell.tcl`: references `$::env(TAP_CELL_NAME)`
  - `grid_strategy-M1-M4-M7.tcl`: metal4 pitch=56.0um, metal7 pitch=30.0um (no env var deps)
  - `make_tracks.tcl`, `setRC.tcl`: no env var dependencies
- **ORFS GCD testing:** Direct observation of 7 verified issues (V1-V7)
- [Chisel generates invalid nesting of always blocks (Rocket Chip #3677)](https://github.com/chipsalliance/rocket-chip/issues/3677)
- [CIRCT exported Verilog can't be synthesized with Yosys (LLVM Discourse)](https://discourse.llvm.org/t/circt-exported-verilog-from-mlir-cant-be-synthesized-with-yosys/88967/1)
- [FIRRTL 2D wires in Yosys (CIRCT #1592)](https://github.com/llvm/circt/issues/1592)
- [Detect area too small for PDN earlier (OpenLane #879)](https://github.com/The-OpenROAD-Project/OpenLane/issues/879)
- [PDN pitch error (OpenLane #2053)](https://github.com/The-OpenROAD-Project/OpenLane/issues/2053)
- [PDN insufficient width (OpenROAD #2027)](https://github.com/The-OpenROAD-Project/OpenROAD/issues/2027)
- [8-bit ripple carry adder flow failure (OpenLane #1713)](https://github.com/The-OpenROAD-Project/OpenLane/issues/1713)
- [Yosys notes on Verilog support](https://yosyshq.readthedocs.io/projects/yosys/en/v0.48/yosys_internals/verilog.html)
- [Yosys write_verilog documentation](https://yosyshq.readthedocs.io/projects/yosys/en/0.46/cmd/write_verilog.html)

---
*Domain pitfalls for: ChipAgent v1.1.2 -- RTL-to-GDS via Yosys + OpenROAD*
*Researched: 2026-03-31*
*Complements STACK.md (positive-path scripts) with failure modes and prevention strategies*
