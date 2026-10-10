#!/usr/bin/env bash
# Shared path resolution for all chip-agent scripts
# Source this file: source "$(dirname "$0")/_common.sh"
# Sets PLUGIN_ROOT. On failure sets _COMMON_INIT_FAILED=true instead of exiting,
# so callers (e.g. detect-env.sh) can handle errors gracefully.

_COMMON_INIT_FAILED=

_plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# Convert MSYS/Cygwin paths to mixed-mode (C:/...) for JVM compatibility on Windows
if command -v cygpath >/dev/null 2>&1; then
  _plugin_root="$(cygpath -m "$_plugin_root")"
fi
if [ -z "$_plugin_root" ]; then
  _COMMON_INIT_FAILED=true
else
  PLUGIN_ROOT="$_plugin_root"
fi

# Resolve the shared source project and per-module artifacts in one place.
# Legacy workspace/<Module> paths remain accepted for existing callers.
resolve_module_paths() {
  local arg="$1"
  if [[ "$arg" == workspace/* || "$arg" == "$PLUGIN_ROOT/workspace/"* ]]; then
    case "$arg" in
      /*) WORKSPACE_DIR="$arg" ;;
      *)  WORKSPACE_DIR="$PLUGIN_ROOT/$arg" ;;
    esac
    PROJECT_DIR="$PLUGIN_ROOT/chisel-project"
  else
    case "$arg" in
      /*) BASE="$arg" ;;
      */*) BASE="$PLUGIN_ROOT/$arg" ;;
      *) BASE="$PLUGIN_ROOT/MyDesign/$arg" ;;
    esac
    WORKSPACE_DIR="$BASE/workspace"
    PROJECT_DIR="$BASE/chisel-project"
  fi
  MODULE="$(basename "$arg")"
  GENERATED_DIR="$WORKSPACE_DIR/generated"
  OUTPUT_DIR="$GENERATED_DIR"
  SIM_DIR="$WORKSPACE_DIR/sim"
  LOG_DIR="$SIM_DIR/logs"
  OBJ_DIR="$SIM_DIR/obj_dir"
}
