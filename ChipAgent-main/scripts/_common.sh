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
