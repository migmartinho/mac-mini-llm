#!/usr/bin/env bash
# =============================================================================
# start.sh — Start all LLM agent services
#
# Loads the launchd user agents for Ollama, Open WebUI, and Nginx if they are
# not already running.  Safe to run multiple times (idempotent).
#
# Usage:
#   ./scripts/start.sh
# =============================================================================

set -euo pipefail

LAUNCHAGENTS_DIR="${HOME}/Library/LaunchAgents"

start_agent() {
  local label="$1"
  local plist="${LAUNCHAGENTS_DIR}/$2"

  if ! launchctl list | grep -q "${label}"; then
    if [[ -f "${plist}" ]]; then
      echo "  Starting ${label} …"
      launchctl load -w "${plist}"
    else
      echo "  ⚠  Plist not found: ${plist}"
      echo "     Run ./scripts/install.sh first."
    fi
  else
    echo "  ${label} is already running — skipping."
  fi
}

echo "Starting LLM agent services …"
start_agent "com.ollama.server"   "com.ollama.server.plist"
start_agent "com.openwebui.server" "com.openwebui.server.plist"
start_agent "homebrew.mxcl.nginx" "homebrew.mxcl.nginx.plist"
echo "Done."
