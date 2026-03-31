#!/usr/bin/env bash
# =============================================================================
# stop.sh — Stop all LLM agent services
#
# Unloads the launchd user agents for Nginx, Open WebUI, and Ollama in
# reverse dependency order.  Safe to run multiple times (idempotent).
#
# Usage:
#   ./scripts/stop.sh
# =============================================================================

set -euo pipefail

LAUNCHAGENTS_DIR="${HOME}/Library/LaunchAgents"

stop_agent() {
  local label="$1"
  local plist="${LAUNCHAGENTS_DIR}/$2"

  if launchctl list | grep -q "${label}"; then
    echo "  Stopping ${label} …"
    launchctl unload "${plist}" 2>/dev/null || launchctl stop "${label}" 2>/dev/null || true
  else
    echo "  ${label} is not running — skipping."
  fi
}

echo "Stopping LLM agent services …"
# Stop in reverse dependency order: proxy first, then backends
stop_agent "homebrew.mxcl.nginx"   "homebrew.mxcl.nginx.plist"
stop_agent "com.openwebui.server"  "com.openwebui.server.plist"
stop_agent "com.ollama.server"     "com.ollama.server.plist"
echo "Done."
