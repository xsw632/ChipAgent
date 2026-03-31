# Requirements: ChipAgent

**Defined:** 2026-03-31
**Core Value:** A single slash command turns a natural language hardware description into lint-clean, simulation-verified Verilog with a complete test report — and now extends through physical implementation to GDS.

## v1.1.2 Requirements

Requirements for RTL-to-GDS milestone. Each maps to roadmap phases.

### Environment

- [ ] **ENV-01**: `/chip-agent:initialize` detects Yosys, OpenROAD, KLayout versions and nangate45 PDK path in env.json
- [ ] **ENV-02**: Pre-flight PDK validation script checks liberty, LEF, and GDS files exist before running PnR

### Synthesis

- [ ] **SYN-01**: `scripts/synth.sh <ModuleName>` runs Yosys with nangate45 liberty, produces gate-level netlist in `workspace/pnr/`
- [ ] **SYN-02**: SDC auto-generation detects clock ports from Verilog, creates `create_clock` for sequential or virtual clock + `set_max_delay` for combinational modules
- [ ] **SYN-03**: Synthesis report (gate count, cell usage, area) written to `workspace/pnr/reports/synth_stat.txt`

### Place and Route

- [ ] **PNR-01**: `scripts/pnr.sh <ModuleName>` runs full OpenROAD flow (floorplan → place → CTS → route) in single session, outputs routed DEF
- [ ] **PNR-02**: Timing (WNS/TNS), power (internal/switching/leakage), and area reports in `workspace/pnr/reports/`
- [ ] **PNR-03**: Smart defaults: auto-size die area from synthesis cell count, skip CTS for combinational modules

### GDS Export

- [ ] **GDS-01**: KLayout DEF→GDS merge produces final `<Module>.gds` in `workspace/pnr/`

### Command

- [ ] **CMD-01**: `/chip-agent:pnr <ModuleName>` slash command runs synth + PnR + GDS, produces formatted report
- [ ] **CMD-02**: PnR report agent formats raw reports into human-readable verification summary
- [ ] **CMD-03**: Auto-fix retry loop (up to 3 attempts) for synthesis and PnR errors

## Future Requirements

### Multi-PDK Support

- **PDK-01**: Support sky130 PDK as alternative target
- **PDK-02**: PDK selection via command flag or spec.json

### Advanced Analysis

- **ADV-01**: Multi-corner STA (best/typical/worst)
- **ADV-02**: DRC/LVS verification via KLayout ruledecks
- **ADV-03**: Congestion heatmap visualization

### Pipeline Extension

- **PIPE-01**: Extend `/chip-agent:workflow` to auto-run PnR after simulation passes

## Out of Scope

| Feature | Reason |
|---------|--------|
| FPGA synthesis | Pipeline targets ASIC flow via OpenROAD, not FPGA |
| Multi-corner STA | Single typical corner sufficient for v1.1.2 |
| DRC/LVS | Requires KLayout ruledecks and Magic — defer to future |
| Hierarchical synthesis | Chisel modules are small enough for flat synthesis |
| Macro placement | No SRAM or hard macros in current module scope |
| GUI visualization | CLI-only through Claude Code |
| Workflow auto-PnR | Keep PnR as explicit opt-in command for now |
| Non-nangate45 PDKs | Single PDK simplifies v1.1.2; multi-PDK later |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| ENV-01 | — | Pending |
| ENV-02 | — | Pending |
| SYN-01 | — | Pending |
| SYN-02 | — | Pending |
| SYN-03 | — | Pending |
| PNR-01 | — | Pending |
| PNR-02 | — | Pending |
| PNR-03 | — | Pending |
| GDS-01 | — | Pending |
| CMD-01 | — | Pending |
| CMD-02 | — | Pending |
| CMD-03 | — | Pending |

**Coverage:**
- v1.1.2 requirements: 12 total
- Mapped to phases: 0
- Unmapped: 12 ⚠️

---
*Requirements defined: 2026-03-31*
*Last updated: 2026-03-31 after initial definition*
