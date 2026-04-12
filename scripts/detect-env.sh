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

# detect_tool: Check if a tool is installed, extract version and path
# Args: tool_name command_name version_command version_regex
# Output: Sets TOOL_INSTALLED, TOOL_VERSION, TOOL_PATH variables
detect_tool() {
  local tool_name="$1"
  local command_name="$2"
  local version_command="$3"
  local version_regex="$4"

  local tool_path
  tool_path=$(command -v "$command_name" 2>/dev/null || true)

  if [ -n "$tool_path" ]; then
    local version_output
    version_output=$(eval "$version_command" 2>&1 || true)
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

# Detect all 6 tools
detect_tool "java" "java" "java -version 2>&1 | head -1" '[0-9]+\.[0-9]+\.[0-9]+([_\.][0-9]+)?'
JAVA_INSTALLED="$TOOL_INSTALLED"
JAVA_VERSION="$TOOL_VERSION"
JAVA_PATH="$TOOL_PATH"

detect_tool "sbt" "sbt" "sbt --batch --version 2>&1 | tail -1" '[0-9]+\.[0-9]+\.[0-9]+'
SBT_INSTALLED="$TOOL_INSTALLED"
SBT_VERSION="$TOOL_VERSION"
SBT_PATH="$TOOL_PATH"

detect_tool "scala" "scala" "scala -version 2>&1 | head -1" '[0-9]+\.[0-9]+\.[0-9]+'
SCALA_INSTALLED="$TOOL_INSTALLED"
SCALA_VERSION="$TOOL_VERSION"
SCALA_PATH="$TOOL_PATH"

detect_tool "verilator" "verilator" "verilator --version 2>&1 | head -1" '[0-9]+\.[0-9]+'
VERILATOR_INSTALLED="$TOOL_INSTALLED"
VERILATOR_VERSION="$TOOL_VERSION"
VERILATOR_PATH="$TOOL_PATH"

detect_tool "make" "make" "make --version 2>&1 | head -1" '[0-9]+\.[0-9]+'
MAKE_INSTALLED="$TOOL_INSTALLED"
MAKE_VERSION="$TOOL_VERSION"
MAKE_PATH="$TOOL_PATH"

detect_tool "gpp" "g++" "g++ --version 2>&1 | head -1" '[0-9]+\.[0-9]+\.[0-9]+'
GPP_INSTALLED="$TOOL_INSTALLED"
GPP_VERSION="$TOOL_VERSION"
GPP_PATH="$TOOL_PATH"

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
    '{
      detected_at: $detected_at,
      tools: {
        java:      { installed: $java_installed,      version: $java_version,      path: $java_path },
        sbt:       { installed: $sbt_installed,       version: $sbt_version,       path: $sbt_path },
        scala:     { installed: $scala_installed,     version: $scala_version,     path: $scala_path },
        verilator: { installed: $verilator_installed, version: $verilator_version, path: $verilator_path },
        make:      { installed: $make_installed,      version: $make_version,      path: $make_path },
        gpp:       { installed: $gpp_installed,       version: $gpp_version,       path: $gpp_path }
      },
      capabilities: {
        can_compile:  $can_compile,
        can_lint:     $can_lint,
        can_simulate: $can_simulate
      }
    }' > "$OUTPUT_FILE"
else
  cat > "$OUTPUT_FILE" <<ENDJSON
{
  "detected_at": "$DETECTED_AT",
  "tools": {
    "java":      { "installed": $JAVA_INSTALLED, "version": "$JAVA_VERSION", "path": "$JAVA_PATH" },
    "sbt":       { "installed": $SBT_INSTALLED, "version": "$SBT_VERSION", "path": "$SBT_PATH" },
    "scala":     { "installed": $SCALA_INSTALLED, "version": "$SCALA_VERSION", "path": "$SCALA_PATH" },
    "verilator": { "installed": $VERILATOR_INSTALLED, "version": "$VERILATOR_VERSION", "path": "$VERILATOR_PATH" },
    "make":      { "installed": $MAKE_INSTALLED, "version": "$MAKE_VERSION", "path": "$MAKE_PATH" },
    "gpp":       { "installed": $GPP_INSTALLED, "version": "$GPP_VERSION", "path": "$GPP_PATH" }
  },
  "capabilities": {
    "can_compile":  $CAN_COMPILE,
    "can_lint":     $CAN_LINT,
    "can_simulate": $CAN_SIMULATE
  }
}
ENDJSON
fi

# Print summary to stdout
status_label() {
  if [ "$1" = "true" ]; then
    printf "[OK] %-10s" "$2"
  else
    printf "[MISSING] %s" ""
  fi
}

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
  echo "  Simulate: YES"
else
  echo "  Simulate: NO"
fi

echo ""
echo "Written: .chipagent/env.json"
