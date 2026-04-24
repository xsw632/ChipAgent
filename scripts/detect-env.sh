#!/usr/bin/env bash
# Environment detection for ChipAgent
# Detects installed tool versions and writes .chipagent/env.json
# Do NOT use set -e -- missing tools produce "installed: false", not crashes

# Use shared path resolution (non-fatal: continues with empty PLUGIN_ROOT if unavailable)
source "$(dirname "$0")/_common.sh" 2>/dev/null || true
PLUGIN_ROOT="${PLUGIN_ROOT:-}"
OUTPUT_DIR="$PLUGIN_ROOT/.chipagent"
OUTPUT_FILE="$OUTPUT_DIR/env.json"

mkdir -p "$OUTPUT_DIR"

# get_version_output: Retrieve version string for a tool (no eval, dispatch pattern)
# Args: command_name
# Output: raw version output (first line)
get_version_output() {
  local cmd="$1"
  case "$cmd" in
    java)      java -version 2>&1 | head -1 ;;
    sbt)       sbt --batch --version 2>&1 | tail -1 ;;
    scala)     scala -version 2>&1 | head -1 ;;
    verilator) verilator --version 2>&1 | head -1 ;;
    make)      make --version 2>&1 | head -1 ;;
    g++)       g++ --version 2>&1 | head -1 ;;
    yosys)     yosys --version 2>&1 | head -1 ;;
    openroad)  openroad -version 2>&1 | head -1 ;;
    klayout)   klayout -v 2>&1 | head -1 ;;
    *) echo "" ;;
  esac
}

# detect_tool: Check if a tool is installed, extract version and path
# Args: tool_name command_name version_regex
# Output: Sets TOOL_INSTALLED, TOOL_VERSION, TOOL_PATH variables
detect_tool() {
  local tool_name="$1"
  local command_name="$2"
  local version_regex="$3"

  local tool_path
  tool_path=$(command -v "$command_name" 2>/dev/null || true)

  if [ -n "$tool_path" ]; then
    local version_output
    version_output=$(get_version_output "$command_name" 2>&1 || true)
    local version
    version=$(echo "$version_output" | grep -oE "$version_regex" | head -1 || true)

    TOOL_INSTALLED="true"
    TOOL_VERSION="${version:-unknown}"
    TOOL_PATH="$tool_path"
  else
    TOOL_INSTALLED="false"
    TOOL_VERSION=""
    TOOL_PATH=""
  fi
}

# Detect all 9 tools
detect_tool "java" "java" '[0-9]+\.[0-9]+\.[0-9]+([_\.][0-9]+)?'
JAVA_INSTALLED="$TOOL_INSTALLED"
JAVA_VERSION="$TOOL_VERSION"
JAVA_PATH="$TOOL_PATH"

detect_tool "sbt" "sbt" '[0-9]+\.[0-9]+\.[0-9]+'
SBT_INSTALLED="$TOOL_INSTALLED"
SBT_VERSION="$TOOL_VERSION"
SBT_PATH="$TOOL_PATH"

detect_tool "scala" "scala" '[0-9]+\.[0-9]+\.[0-9]+'
SCALA_INSTALLED="$TOOL_INSTALLED"
SCALA_VERSION="$TOOL_VERSION"
SCALA_PATH="$TOOL_PATH"

detect_tool "verilator" "verilator" '[0-9]+\.[0-9]+'
VERILATOR_INSTALLED="$TOOL_INSTALLED"
VERILATOR_VERSION="$TOOL_VERSION"
VERILATOR_PATH="$TOOL_PATH"

detect_tool "make" "make" '[0-9]+\.[0-9]+'
MAKE_INSTALLED="$TOOL_INSTALLED"
MAKE_VERSION="$TOOL_VERSION"
MAKE_PATH="$TOOL_PATH"

detect_tool "gpp" "g++" '[0-9]+\.[0-9]+\.[0-9]+'
GPP_INSTALLED="$TOOL_INSTALLED"
GPP_VERSION="$TOOL_VERSION"
GPP_PATH="$TOOL_PATH"

detect_tool "yosys" "yosys" '[0-9]+\.[0-9]+(\+[0-9]+)?'
YOSYS_INSTALLED="$TOOL_INSTALLED"
YOSYS_VERSION="$TOOL_VERSION"
YOSYS_PATH="$TOOL_PATH"

detect_tool "openroad" "openroad" '[0-9]+Q[0-9]'
OPENROAD_INSTALLED="$TOOL_INSTALLED"
OPENROAD_VERSION="$TOOL_VERSION"
OPENROAD_PATH="$TOOL_PATH"

detect_tool "klayout" "klayout" '[0-9]+\.[0-9]+\.[0-9]+'
KLAYOUT_INSTALLED="$TOOL_INSTALLED"
KLAYOUT_VERSION="$TOOL_VERSION"
KLAYOUT_PATH="$TOOL_PATH"

# Detect sky130hd PDK
SKY130HD_INSTALLED="false"
SKY130HD_DIR=""
SKY130HD_CANDIDATES=(
  "${SKY130HD_DIR_OVERRIDE:-}"
  "${ORFS_DIR:-}/flow/platforms/sky130hd"
  "$HOME/OpenROAD-flow-scripts/flow/platforms/sky130hd"
  "/opt/OpenROAD-flow-scripts/flow/platforms/sky130hd"
)
for candidate in "${SKY130HD_CANDIDATES[@]}"; do
  if [ -n "$candidate" ] && [ -f "$candidate/lib/sky130_fd_sc_hd__tt_025C_1v80.lib" ]; then
    SKY130HD_INSTALLED="true"
    SKY130HD_DIR="$candidate"
    break
  fi
done

# Detect ORFS root
ORFS_INSTALLED="false"
ORFS_DIR_DETECTED=""
ORFS_FLOW_PATH=""
ORFS_CANDIDATES=(
  "${ORFS_DIR:-}"
  "$HOME/OpenROAD-flow-scripts"
  "/opt/OpenROAD-flow-scripts"
)
for candidate in "${ORFS_CANDIDATES[@]}"; do
  if [ -n "$candidate" ] && [ -f "$candidate/flow/Makefile" ]; then
    ORFS_INSTALLED="true"
    ORFS_DIR_DETECTED="$candidate"
    ORFS_FLOW_PATH="$candidate/flow"
    break
  fi
done

# Detect Docker
DOCKER_INSTALLED="false"
DOCKER_VERSION=""
if command -v docker >/dev/null 2>&1; then
  DOCKER_VERSION=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
  if [ -n "$DOCKER_VERSION" ]; then
    DOCKER_INSTALLED="true"
  fi
fi
if [ -n "${CHIPAGENT_BACKEND_MODE:-}" ]; then
  BACKEND_MODE="$CHIPAGENT_BACKEND_MODE"
elif [ "$DOCKER_INSTALLED" = "true" ]; then
  BACKEND_MODE="docker"
else
  BACKEND_MODE="local"
fi

# Detect Chipyard
CHIPYARD_INSTALLED="false"
CHIPYARD_DIR_DETECTED=""
CHIPYARD_CANDIDATES=(
  "${CHIPYARD_DIR:-}"
  "$HOME/chipyard"
  "$HOME/Desktop/chipyard"
  "/opt/chipyard"
)
for candidate in "${CHIPYARD_CANDIDATES[@]}"; do
  if [ -n "$candidate" ] && [ -f "$candidate/build.sbt" ] && [ -d "$candidate/generators/chipyard/src/main/scala" ]; then
    CHIPYARD_INSTALLED="true"
    CHIPYARD_DIR_DETECTED="$candidate"
    break
  fi
done

# Detect RISCV toolchain
RISCV_INSTALLED="false"
RISCV_PATH=""
RISCV_CANDIDATES=(
  "${RISCV:-}"
  "${CHIPYARD_DIR_DETECTED:+$CHIPYARD_DIR_DETECTED/.conda-env/riscv-tools}"
  "${CHIPYARD_DIR_DETECTED:+$CHIPYARD_DIR_DETECTED/riscv-tools}"
  "/opt/riscv"
)
for candidate in "${RISCV_CANDIDATES[@]}"; do
  if [ -n "$candidate" ] && [ -f "$candidate/bin/riscv64-unknown-elf-gcc" ]; then
    RISCV_INSTALLED="true"
    RISCV_PATH="$candidate"
    break
  fi
done

# Docker fallback for Chipyard/RISCV: only runs when host probe missed AND
# backend_mode=docker AND docker is available. Host-mode users are unaffected.
CHIPYARD_IN_DOCKER="false"
CHIPYARD_DOCKER_IMAGE_OUT=""
if [ "$CHIPYARD_INSTALLED" != "true" ] && [ "$BACKEND_MODE" = "docker" ] && [ "$DOCKER_INSTALLED" = "true" ]; then
  CHIPYARD_DOCKER_IMAGE="${CHIPAGENT_CHIPYARD_IMAGE:-}"
  CHIPYARD_DOCKER_WORKDIR="${CHIPAGENT_CHIPYARD_WORKDIR:-}"
  CHIPYARD_DOCKER_RISCV="${CHIPAGENT_CHIPYARD_RISCV_PATH:-}"

  WORKSPACE_JSON="$HOME/.chipagent/workspace.json"
  if command -v jq >/dev/null 2>&1 && [ -f "$WORKSPACE_JSON" ]; then
    [ -z "$CHIPYARD_DOCKER_IMAGE"   ] && CHIPYARD_DOCKER_IMAGE=$(jq -r '.chipyard_docker_image // empty'   "$WORKSPACE_JSON" 2>/dev/null || true)
    [ -z "$CHIPYARD_DOCKER_WORKDIR" ] && CHIPYARD_DOCKER_WORKDIR=$(jq -r '.chipyard_docker_workdir // empty' "$WORKSPACE_JSON" 2>/dev/null || true)
    [ -z "$CHIPYARD_DOCKER_RISCV"   ] && CHIPYARD_DOCKER_RISCV=$(jq -r '.chipyard_riscv_path // empty'      "$WORKSPACE_JSON" 2>/dev/null || true)
  fi
  CHIPYARD_DOCKER_IMAGE="${CHIPYARD_DOCKER_IMAGE:-ucbbar/chipyard-image:latest}"
  CHIPYARD_DOCKER_WORKDIR="${CHIPYARD_DOCKER_WORKDIR:-/chipyard}"
  CHIPYARD_DOCKER_RISCV="${CHIPYARD_DOCKER_RISCV:-${CHIPYARD_DOCKER_WORKDIR}/.conda-env/riscv-tools}"

  if docker image inspect "$CHIPYARD_DOCKER_IMAGE" >/dev/null 2>&1; then
    PROBE_OUT=$(docker run --rm --entrypoint=/bin/bash "$CHIPYARD_DOCKER_IMAGE" -c "
      [ -f '$CHIPYARD_DOCKER_WORKDIR/build.sbt' ] && \
      [ -d '$CHIPYARD_DOCKER_WORKDIR/generators/chipyard/src/main/scala' ] && echo 'CHIPYARD_OK'
      [ -f '$CHIPYARD_DOCKER_RISCV/bin/riscv64-unknown-elf-gcc' ] && echo 'RISCV_OK'
    " 2>/dev/null || true)
    if echo "$PROBE_OUT" | grep -q '^CHIPYARD_OK$'; then
      CHIPYARD_INSTALLED="true"
      CHIPYARD_DIR_DETECTED="$CHIPYARD_DOCKER_WORKDIR"
      CHIPYARD_IN_DOCKER="true"
      CHIPYARD_DOCKER_IMAGE_OUT="$CHIPYARD_DOCKER_IMAGE"
    fi
    if [ "$RISCV_INSTALLED" != "true" ] && echo "$PROBE_OUT" | grep -q '^RISCV_OK$'; then
      RISCV_INSTALLED="true"
      RISCV_PATH="$CHIPYARD_DOCKER_RISCV"
    fi
  else
    echo "Chipyard docker image '$CHIPYARD_DOCKER_IMAGE' not found locally. Hint: docker pull $CHIPYARD_DOCKER_IMAGE" >&2
  fi
fi

# Compute capability flags
CAN_COMPILE="false"
CAN_LINT="false"
CAN_SIMULATE="false"

if [ "$JAVA_INSTALLED" = "true" ] && [ "$SBT_INSTALLED" = "true" ]; then
  CAN_COMPILE="true"
fi

if [ "$VERILATOR_INSTALLED" = "true" ]; then
  CAN_LINT="true"
fi

if [ "$VERILATOR_INSTALLED" = "true" ] && [ "$MAKE_INSTALLED" = "true" ] && [ "$GPP_INSTALLED" = "true" ]; then
  CAN_SIMULATE="true"
fi

CAN_SYNTHESIZE="false"
CAN_PNR="false"
CAN_GDS="false"

if [ "$YOSYS_INSTALLED" = "true" ] && [ "$SKY130HD_INSTALLED" = "true" ]; then
  CAN_SYNTHESIZE="true"
fi

if [ "$OPENROAD_INSTALLED" = "true" ] && [ "$SKY130HD_INSTALLED" = "true" ]; then
  CAN_PNR="true"
fi

if [ "$KLAYOUT_INSTALLED" = "true" ] && [ "$SKY130HD_INSTALLED" = "true" ] && [ -n "$SKY130HD_DIR" ] && [ -f "$SKY130HD_DIR/gds/sky130_fd_sc_hd.gds" ]; then
  CAN_GDS="true"
fi

CAN_CHIPYARD="false"
if [ "$CHIPYARD_INSTALLED" = "true" ] && [ "$RISCV_INSTALLED" = "true" ]; then
  CAN_CHIPYARD="true"
fi

# json_escape: Escape strings for safe embedding in JSON heredoc output
# Handles backslashes and double quotes that would break JSON syntax
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Get timestamp
DETECTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Assemble and write JSON
# Use jq if available for proper formatting, otherwise use heredoc
if command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg detected_at "$DETECTED_AT" \
    --argjson java_installed "$JAVA_INSTALLED" \
    --arg java_version "$JAVA_VERSION" \
    --arg java_path "$JAVA_PATH" \
    --argjson sbt_installed "$SBT_INSTALLED" \
    --arg sbt_version "$SBT_VERSION" \
    --arg sbt_path "$SBT_PATH" \
    --argjson scala_installed "$SCALA_INSTALLED" \
    --arg scala_version "$SCALA_VERSION" \
    --arg scala_path "$SCALA_PATH" \
    --argjson verilator_installed "$VERILATOR_INSTALLED" \
    --arg verilator_version "$VERILATOR_VERSION" \
    --arg verilator_path "$VERILATOR_PATH" \
    --argjson make_installed "$MAKE_INSTALLED" \
    --arg make_version "$MAKE_VERSION" \
    --arg make_path "$MAKE_PATH" \
    --argjson gpp_installed "$GPP_INSTALLED" \
    --arg gpp_version "$GPP_VERSION" \
    --arg gpp_path "$GPP_PATH" \
    --argjson can_compile "$CAN_COMPILE" \
    --argjson can_lint "$CAN_LINT" \
    --argjson can_simulate "$CAN_SIMULATE" \
    --argjson yosys_installed "$YOSYS_INSTALLED" \
    --arg yosys_version "$YOSYS_VERSION" \
    --arg yosys_path "$YOSYS_PATH" \
    --argjson openroad_installed "$OPENROAD_INSTALLED" \
    --arg openroad_version "$OPENROAD_VERSION" \
    --arg openroad_path "$OPENROAD_PATH" \
    --argjson klayout_installed "$KLAYOUT_INSTALLED" \
    --arg klayout_version "$KLAYOUT_VERSION" \
    --arg klayout_path "$KLAYOUT_PATH" \
    --argjson sky130hd_installed "$SKY130HD_INSTALLED" \
    --arg sky130hd_path "$SKY130HD_DIR" \
    --argjson orfs_installed "$ORFS_INSTALLED" \
    --arg orfs_path "$ORFS_DIR_DETECTED" \
    --arg orfs_flow_path "$ORFS_FLOW_PATH" \
    --argjson docker_installed "$DOCKER_INSTALLED" \
    --arg docker_version "$DOCKER_VERSION" \
    --arg backend_mode "$BACKEND_MODE" \
    --argjson can_synthesize "$CAN_SYNTHESIZE" \
    --argjson can_pnr "$CAN_PNR" \
    --argjson can_gds "$CAN_GDS" \
    --argjson chipyard_installed "$CHIPYARD_INSTALLED" \
    --arg chipyard_path "$CHIPYARD_DIR_DETECTED" \
    --argjson riscv_installed "$RISCV_INSTALLED" \
    --arg riscv_path "$RISCV_PATH" \
    --argjson can_chipyard "$CAN_CHIPYARD" \
    --argjson chipyard_in_docker "$CHIPYARD_IN_DOCKER" \
    --arg chipyard_docker_image "$CHIPYARD_DOCKER_IMAGE_OUT" \
    '{
      detected_at: $detected_at,
      tools: {
        java:      { installed: $java_installed,      version: $java_version,      path: $java_path },
        sbt:       { installed: $sbt_installed,       version: $sbt_version,       path: $sbt_path },
        scala:     { installed: $scala_installed,     version: $scala_version,     path: $scala_path },
        verilator: { installed: $verilator_installed, version: $verilator_version, path: $verilator_path },
        make:      { installed: $make_installed,      version: $make_version,      path: $make_path },
        gpp:       { installed: $gpp_installed,       version: $gpp_version,       path: $gpp_path },
        yosys:     { installed: $yosys_installed,     version: $yosys_version,     path: $yosys_path },
        openroad:  { installed: $openroad_installed,  version: $openroad_version,  path: $openroad_path },
        klayout:   { installed: $klayout_installed,   version: $klayout_version,   path: $klayout_path }
      },
      pdk: {
        sky130hd: {
          installed: $sky130hd_installed,
          path: $sky130hd_path,
          liberty: "lib/sky130_fd_sc_hd__tt_025C_1v80.lib",
          tech_lef: "lef/sky130_fd_sc_hd.tlef",
          cell_lef: "lef/sky130_fd_sc_hd_merged.lef",
          gds: "gds/sky130_fd_sc_hd.gds"
        }
      },
      orfs: {
        installed: $orfs_installed,
        path: $orfs_path,
        flow_path: $orfs_flow_path
      },
      docker: {
        installed: $docker_installed,
        version: $docker_version
      },
      chipyard: {
        installed: $chipyard_installed,
        path: $chipyard_path,
        riscv_installed: $riscv_installed,
        riscv_path: $riscv_path,
        in_docker: $chipyard_in_docker,
        docker_image: $chipyard_docker_image
      },
      backend_mode: $backend_mode,
      capabilities: {
        can_compile:    $can_compile,
        can_lint:       $can_lint,
        can_simulate:   $can_simulate,
        can_synthesize: $can_synthesize,
        can_pnr:        $can_pnr,
        can_gds:        $can_gds,
        can_chipyard:   $can_chipyard
      }
    }' > "$OUTPUT_FILE"
else
  cat > "$OUTPUT_FILE" <<ENDJSON
{
  "detected_at": "$(json_escape "$DETECTED_AT")",
  "tools": {
    "java":      { "installed": $JAVA_INSTALLED, "version": "$(json_escape "$JAVA_VERSION")", "path": "$(json_escape "$JAVA_PATH")" },
    "sbt":       { "installed": $SBT_INSTALLED, "version": "$(json_escape "$SBT_VERSION")", "path": "$(json_escape "$SBT_PATH")" },
    "scala":     { "installed": $SCALA_INSTALLED, "version": "$(json_escape "$SCALA_VERSION")", "path": "$(json_escape "$SCALA_PATH")" },
    "verilator": { "installed": $VERILATOR_INSTALLED, "version": "$(json_escape "$VERILATOR_VERSION")", "path": "$(json_escape "$VERILATOR_PATH")" },
    "make":      { "installed": $MAKE_INSTALLED, "version": "$(json_escape "$MAKE_VERSION")", "path": "$(json_escape "$MAKE_PATH")" },
    "gpp":       { "installed": $GPP_INSTALLED, "version": "$(json_escape "$GPP_VERSION")", "path": "$(json_escape "$GPP_PATH")" },
    "yosys":     { "installed": $YOSYS_INSTALLED, "version": "$(json_escape "$YOSYS_VERSION")", "path": "$(json_escape "$YOSYS_PATH")" },
    "openroad":  { "installed": $OPENROAD_INSTALLED, "version": "$(json_escape "$OPENROAD_VERSION")", "path": "$(json_escape "$OPENROAD_PATH")" },
    "klayout":   { "installed": $KLAYOUT_INSTALLED, "version": "$(json_escape "$KLAYOUT_VERSION")", "path": "$(json_escape "$KLAYOUT_PATH")" }
  },
  "pdk": {
    "sky130hd": {
      "installed": $SKY130HD_INSTALLED,
      "path": "$(json_escape "$SKY130HD_DIR")",
      "liberty": "lib/sky130_fd_sc_hd__tt_025C_1v80.lib",
      "tech_lef": "lef/sky130_fd_sc_hd.tlef",
      "cell_lef": "lef/sky130_fd_sc_hd_merged.lef",
      "gds": "gds/sky130_fd_sc_hd.gds"
    }
  },
  "orfs": {
    "installed": $ORFS_INSTALLED,
    "path": "$(json_escape "$ORFS_DIR_DETECTED")",
    "flow_path": "$(json_escape "$ORFS_FLOW_PATH")"
  },
  "docker": {
    "installed": $DOCKER_INSTALLED,
    "version": "$(json_escape "$DOCKER_VERSION")"
  },
  "chipyard": {
    "installed": $CHIPYARD_INSTALLED,
    "path": "$(json_escape "$CHIPYARD_DIR_DETECTED")",
    "riscv_installed": $RISCV_INSTALLED,
    "riscv_path": "$(json_escape "$RISCV_PATH")",
    "in_docker": $CHIPYARD_IN_DOCKER,
    "docker_image": "$(json_escape "$CHIPYARD_DOCKER_IMAGE_OUT")"
  },
  "backend_mode": "$(json_escape "$BACKEND_MODE")",
  "capabilities": {
    "can_compile":    $CAN_COMPILE,
    "can_lint":       $CAN_LINT,
    "can_simulate":   $CAN_SIMULATE,
    "can_synthesize": $CAN_SYNTHESIZE,
    "can_pnr":        $CAN_PNR,
    "can_gds":        $CAN_GDS,
    "can_chipyard":   $CAN_CHIPYARD
  }
}
ENDJSON
fi

# Print summary to stdout
echo ""
echo "=== ChipAgent Environment Detection ==="

if [ "$JAVA_INSTALLED" = "true" ]; then
  echo "Java:       [OK] $JAVA_VERSION"
else
  echo "Java:       [MISSING]"
fi

if [ "$SBT_INSTALLED" = "true" ]; then
  echo "sbt:        [OK] $SBT_VERSION"
else
  echo "sbt:        [MISSING]"
fi

if [ "$SCALA_INSTALLED" = "true" ]; then
  echo "Scala:      [OK] $SCALA_VERSION"
else
  echo "Scala:      [MISSING]"
fi

if [ "$VERILATOR_INSTALLED" = "true" ]; then
  echo "Verilator:  [OK] $VERILATOR_VERSION"
else
  echo "Verilator:  [MISSING]"
fi

if [ "$MAKE_INSTALLED" = "true" ]; then
  echo "Make:       [OK] $MAKE_VERSION"
else
  echo "Make:       [MISSING]"
fi

if [ "$GPP_INSTALLED" = "true" ]; then
  echo "g++:        [OK] $GPP_VERSION"
else
  echo "g++:        [MISSING]"
fi

if [ "$YOSYS_INSTALLED" = "true" ]; then
  echo "Yosys:      [OK] $YOSYS_VERSION"
else
  echo "Yosys:      [MISSING]"
fi

if [ "$OPENROAD_INSTALLED" = "true" ]; then
  echo "OpenROAD:   [OK] $OPENROAD_VERSION"
else
  echo "OpenROAD:   [MISSING]"
fi

if [ "$KLAYOUT_INSTALLED" = "true" ]; then
  echo "KLayout:    [OK] $KLAYOUT_VERSION"
else
  echo "KLayout:    [MISSING]"
fi

if [ "$SKY130HD_INSTALLED" = "true" ]; then
  echo "PDK:        [OK] sky130hd ($SKY130HD_DIR)"
else
  echo "PDK:        [MISSING] sky130hd"
fi

if [ "$ORFS_INSTALLED" = "true" ]; then
  echo "ORFS:       [OK] $ORFS_DIR_DETECTED"
else
  echo "ORFS:       [MISSING]"
fi

if [ "$DOCKER_INSTALLED" = "true" ]; then
  echo "Docker:     [OK] $DOCKER_VERSION"
else
  echo "Docker:     [MISSING]"
fi

if [ "$CHIPYARD_INSTALLED" = "true" ]; then
  if [ "$CHIPYARD_IN_DOCKER" = "true" ]; then
    echo "Chipyard:   [OK] $CHIPYARD_DOCKER_IMAGE_OUT (docker)"
  else
    echo "Chipyard:   [OK] $CHIPYARD_DIR_DETECTED"
  fi
else
  echo "Chipyard:   [MISSING]"
fi

if [ "$RISCV_INSTALLED" = "true" ]; then
  echo "RISCV:      [OK] $RISCV_PATH"
else
  echo "RISCV:      [MISSING]"
fi

echo "backend_mode: $BACKEND_MODE"

echo ""
echo "Capabilities:"
if [ "$CAN_COMPILE" = "true" ]; then
  echo "  Compile:  YES"
else
  echo "  Compile:  NO"
fi
if [ "$CAN_LINT" = "true" ]; then
  echo "  Lint:     YES"
else
  echo "  Lint:     NO"
fi
if [ "$CAN_SIMULATE" = "true" ]; then
  echo "  Simulate:   YES"
else
  echo "  Simulate:   NO"
fi
if [ "$CAN_SYNTHESIZE" = "true" ]; then
  echo "  Synthesize: YES"
else
  echo "  Synthesize: NO"
fi
if [ "$CAN_PNR" = "true" ]; then
  echo "  PnR:        YES"
else
  echo "  PnR:        NO"
fi
if [ "$CAN_GDS" = "true" ]; then
  echo "  GDS:        YES"
else
  echo "  GDS:        NO"
fi
if [ "$CAN_CHIPYARD" = "true" ]; then
  echo "  Chipyard:   YES"
else
  echo "  Chipyard:   NO"
fi

echo ""
echo "Written: .chipagent/env.json"
