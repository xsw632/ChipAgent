# Phase 18: Chipyard Environment Detection - Context

**Gathered:** 2026-04-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Extend the existing `detect-env.sh` environment detection script and `/chip-agent:initialize` skill to discover Chipyard installation and RISCV toolchain availability. Users can run `/chip-agent:initialize` to see whether their environment supports Chipyard RTL generation.

</domain>

<decisions>
## Implementation Decisions

### Chipyard Directory Discovery
- Candidate directory chain: `CHIPYARD_DIR` env var → `~/chipyard` → `/opt/chipyard` — consistent with existing sky130hd/ORFS detection pattern
- Validate installation by checking for `build.sbt` + Chipyard marker (`generators/src/main/scala` exists)
- Docker-based Chipyard deferred to DCK-01/DCK-02 per REQUIREMENTS.md
- Report path only (no version — Chipyard has no single version command)

### RISCV Toolchain Detection
- Candidate chain: `RISCV` env var → `<chipyard>/.conda-env/` → `<chipyard>/riscv-tools` → `/opt/riscv`
- Validate via `riscv64-unknown-elf-gcc` binary presence (primary cross-compiler)
- No separate firtool detection (already auto-managed by Chisel)
- Report installed/path only (no version — varies across toolchain builds)
- Note: Chipyard's RISCV toolchain is typically in `.conda-env/` directory within Chipyard installation

### Capability Integration
- `can_chipyard` = Chipyard found AND RISCV found (both required for RTL generation)
- New top-level `chipyard` section in env.json (path, installed, riscv_path, riscv_installed) + add `can_chipyard` to capabilities
- Initialize skill presents brief Chipyard install guidance when missing (link to Chipyard docs)
- detect-env.sh summary follows existing `[OK]/[MISSING]` pattern for Chipyard and RISCV lines

### Claude's Discretion
- Exact jq/heredoc JSON formatting for new chipyard section
- Specific stdout summary formatting for Chipyard/RISCV lines
- Install guidance wording and link placement

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `detect_tool()` function in detect-env.sh — reusable pattern for tool detection (binary presence + version extraction)
- Candidate directory chain pattern (sky130hd, ORFS) — directly reusable for Chipyard
- jq-based JSON assembly in detect-env.sh — extend with chipyard section
- Initialize skill (`skills/initialize/SKILL.md`) — extend step 5 summary with Chipyard info

### Established Patterns
- Tool detection: `detect_tool` function with TOOL_INSTALLED/TOOL_VERSION/TOOL_PATH variables
- PDK/ORFS detection: candidate array with `for` loop, validation via specific file check
- Capability flags: boolean computed from tool presence combinations
- JSON output: dual-path (jq if available, heredoc fallback)
- Summary output: `[OK]`/`[MISSING]` pattern with version/path info

### Integration Points
- `scripts/detect-env.sh` — add Chipyard and RISCV detection blocks before capability computation
- `scripts/_common.sh` — shared PLUGIN_ROOT resolution
- `skills/initialize/SKILL.md` — extend step 5 summary and install guidance
- `.chipagent/env.json` — add chipyard section and can_chipyard capability
- Future Phase 19 (`/chip-agent:chipyard`) will consume `can_chipyard` flag and chipyard path from env.json

</code_context>

<specifics>
## Specific Ideas

- RISCV toolchain is typically installed in `.conda-env/` directory within Chipyard installation (user feedback)
- Follow the existing sky130hd/ORFS detection pattern closely for consistency
- Keep can_chipyard as a combined flag (requires both Chipyard AND RISCV) to match Phase 19's prerequisites

</specifics>

<deferred>
## Deferred Ideas

- Docker-based Chipyard execution (DCK-01, DCK-02)
- Chipyard version reporting (no standard version command available)
- RISCV toolchain version reporting (varies across builds)
- Separate firtool detection for Chipyard (auto-managed)

</deferred>
