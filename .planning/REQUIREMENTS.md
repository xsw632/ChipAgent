# Requirements: ChipAgent

**Defined:** 2026-04-01
**Core Value:** A single slash command turns a natural language hardware description into lint-clean, simulation-verified Verilog -- and a second command extends it through synthesis, PnR, and GDS export.

## v1.1.5 Requirements

Requirements for sky130hd MCP Backend milestone. Each maps to roadmap phases.

### MCP Server

- [ ] **MCP-01**: MCP Server scaffold with stdio transport, TypeScript source, and .mcp.json plugin registration
- [ ] **MCP-02**: `check_environment` tool verifying ORFS path, sky130hd PDK presence, and Docker availability
- [ ] **MCP-03**: `generate_config` tool creating config.mk and constraint.sdc from module name, Verilog path, and clock info
- [ ] **MCP-04**: `run_stage` tool executing individual ORFS make targets (synth/floorplan/place/cts/route/finish) with output capture
- [ ] **MCP-05**: `get_report` tool extracting stage report files and key metrics from ORFS output directories

### Config Generation

- [ ] **CFG-01**: Auto-generate config.mk with correct ORFS variables (DESIGN_NAME, PLATFORM, VERILOG_FILES, SDC_FILE, CORE_UTILIZATION)
- [ ] **CFG-02**: Auto-generate ORFS-compatible constraint.sdc with sky130hd timing defaults (10ns clock for sequential, virtual clock for combinational)

### PnR Flow Orchestration

- [ ] **FLOW-01**: /chip-agent:pnr skill rewritten to orchestrate via MCP tools instead of direct bash script invocation
- [ ] **FLOW-02**: Skill auto-advances through 6 ORFS stages sequentially (synth -> floorplan -> place -> cts -> route -> finish)
- [ ] **FLOW-03**: Per-stage metric extraction after each ORFS stage (cell count, design area, WNS, TNS, DRC violations)

### Reporting

- [ ] **RPT-01**: PPA summary report combining timing (WNS/TNS/clock period), power, and area metrics in formatted output

### Environment Detection

- [ ] **ENV-01**: sky130hd PDK detection in /chip-agent:initialize replacing nangate45 detection
- [ ] **ENV-02**: Docker availability detection with backend_mode field (local/docker) in env.json
- [ ] **ENV-03**: ORFS installation detection and path resolution in env.json

### Cleanup

- [ ] **CLN-01**: Remove nangate45-specific scripts (synth.tcl, pnr.tcl, validate-pdk.sh, def2gds.py) and replace with ORFS-based flow
- [ ] **CLN-02**: Update CLAUDE.md tech stack table and documentation for sky130hd + MCP architecture

## v1.2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Auto-Recovery

- **RECV-01**: Auto-retry on timing violation with clock period relaxation
- **RECV-02**: Auto-retry on congestion with PLACE_DENSITY adjustment
- **RECV-03**: Error diagnosis by type (timing/congestion/DRC) with suggested fixes

### QoR Optimization

- **QOR-01**: Multi-run QoR comparison across different configurations
- **QOR-02**: Parameter sweep for optimal PPA tradeoffs

### Docker

- **DOCK-01**: Full Docker mode implementation (docker exec wrapping for all MCP tools)
- **DOCK-02**: Docker container lifecycle management (start/stop/cleanup)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Non-sky130hd PDKs | task2 mandates sky130hd exclusively |
| DRC/LVS verification | Requires KLayout ruledecks; defer to future |
| Multi-corner STA | Single typical corner sufficient for current scope |
| GUI/web interface | CLI-only through Claude Code |
| FPGA synthesis | Pipeline targets ASIC flow via ORFS |
| Docker full implementation | Pre-reserved interface only; Docker pull not yet done |
| Hierarchical synthesis | Chisel modules small enough for flat synthesis |
| Full Docker mode | Only local execution mode implemented; Docker interface pre-reserved |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| MCP-01 | Phase 13 | Pending |
| MCP-02 | Phase 13 | Pending |
| MCP-03 | Phase 14 | Pending |
| MCP-04 | Phase 14 | Pending |
| MCP-05 | Phase 14 | Pending |
| CFG-01 | Phase 14 | Pending |
| CFG-02 | Phase 14 | Pending |
| FLOW-01 | Phase 15 | Pending |
| FLOW-02 | Phase 15 | Pending |
| FLOW-03 | Phase 15 | Pending |
| RPT-01 | Phase 15 | Pending |
| ENV-01 | Phase 13 | Pending |
| ENV-02 | Phase 13 | Pending |
| ENV-03 | Phase 13 | Pending |
| CLN-01 | Phase 13 | Pending |
| CLN-02 | Phase 13 | Pending |

**Coverage:**
- v1.1.5 requirements: 16 total
- Mapped to phases: 16
- Unmapped: 0

---
*Requirements defined: 2026-04-01*
*Last updated: 2026-04-01 after roadmap creation*
