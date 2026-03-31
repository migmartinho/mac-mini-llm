#!/usr/bin/env bash
# =============================================================================
# update_models.sh — Update all installed Ollama models and Open WebUI
#
# What this script does:
#   1. Iterates every model returned by `ollama list` and pulls the latest
#      version (only downloads changed layers, so incremental updates are fast)
#   2. Upgrades the open-webui pip package inside the venv
#   3. Prompts to restart Open WebUI if the package was upgraded
#
# Usage:
#   ./scripts/update_models.sh
#
# Schedule via cron for automatic updates, e.g. weekly at 03:00:
#   0 3 * * 0 /path/to/mac-mini-llm/scripts/update_models.sh >> ~/Library/Logs/llm-update.log 2>&1
# =============================================================================

set -euo pipefail

VENV_DIR="${HOME}/.local/openwebui-venv"

# ── 1. Update Ollama models ───────────────────────────────────────────────
if ! command -v ollama &>/dev/null; then
  eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
fi

if ! command -v ollama &>/dev/null; then
  echo "  ⚠  ollama not found — run ./scripts/setup_ollama.sh first."
  exit 1
fi

echo "Pulling latest model layers …"
while IFS= read -r line; do
  # Skip the header line
  [[ "${line}" == NAME* ]] && continue
  model=$(echo "${line}" | awk '{print $1}')
  [[ -z "${model}" ]] && continue
  echo "  ollama pull ${model}"
  ollama pull "${model}"
done < <(ollama list)

echo ""

# ── 2. Update Open WebUI ──────────────────────────────────────────────────
if [[ -d "${VENV_DIR}" ]]; then
  echo "Upgrading Open WebUI …"
  # shellcheck source=/dev/null
  source "${VENV_DIR}/bin/activate"
  OLD_VER=$(pip show open-webui 2>/dev/null | awk '/^Version:/{print $2}')
  pip install --quiet --upgrade open-webui
  NEW_VER=$(pip show open-webui 2>/dev/null | awk '/^Version:/{print $2}')

  if [[ "${OLD_VER}" != "${NEW_VER}" ]]; then
    echo "  Open WebUI upgraded: ${OLD_VER} → ${NEW_VER}"
    echo "  Restarting Open WebUI to apply the new version …"
    LAUNCHAGENTS_DIR="${HOME}/Library/LaunchAgents"
    PLIST="${LAUNCHAGENTS_DIR}/com.openwebui.server.plist"
    if [[ -f "${PLIST}" ]]; then
      launchctl unload "${PLIST}" 2>/dev/null || true
      launchctl load -w "${PLIST}"
      echo "  Open WebUI restarted."
    fi
  else
    echo "  Open WebUI is already up to date (${OLD_VER})."
  fi
else
  echo "  ⚠  Open WebUI venv not found at ${VENV_DIR}"
  echo "     Run ./scripts/setup_openwebui.sh first."
fi

echo ""
echo "✓ Update complete."
