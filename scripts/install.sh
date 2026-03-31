#!/usr/bin/env bash
# =============================================================================
# install.sh — Master installer for the Mac Mini LLM Agent
#
# Run this script once after cloning the repository.  It will:
#   1. Set up Ollama (LLM runtime) with Metal GPU acceleration
#   2. Set up Open WebUI (browser-based chat interface)
#   3. Set up Nginx as a WireGuard-only reverse proxy
#   4. Register all three services with launchd so they start on login
#
# Usage:
#   chmod +x scripts/*.sh
#   ./scripts/install.sh
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="${REPO_DIR}/scripts"

echo "============================================================"
echo " Mac Mini LLM Agent — Master Installer"
echo " Repo: ${REPO_DIR}"
echo "============================================================"
echo ""

# ── Step 1: Ollama ─────────────────────────────────────────────────────────
echo "▶ Step 1/3 — Setting up Ollama …"
bash "${SCRIPTS_DIR}/setup_ollama.sh"
echo ""

# ── Step 2: Open WebUI ─────────────────────────────────────────────────────
echo "▶ Step 2/3 — Setting up Open WebUI …"
bash "${SCRIPTS_DIR}/setup_openwebui.sh"
echo ""

# ── Step 3: Nginx reverse proxy ────────────────────────────────────────────
echo "▶ Step 3/3 — Setting up Nginx reverse proxy …"
bash "${SCRIPTS_DIR}/setup_nginx.sh"
echo ""

# ── Done ───────────────────────────────────────────────────────────────────
echo "============================================================"
echo " Installation complete!"
echo ""
echo " Services are running as launchd user agents and will"
echo " restart automatically on login."
echo ""
echo " Quick health check:"
echo "   curl http://127.0.0.1:11434/api/tags   # Ollama"
echo "   curl -I http://127.0.0.1:3000          # Open WebUI"
echo ""

# Detect WireGuard IP for display purposes
WG_IP=$(bash "${SCRIPTS_DIR}/setup_nginx.sh" --print-wg-ip 2>/dev/null || true)
if [[ -n "${WG_IP}" ]]; then
  echo " From any WireGuard-connected device:"
  echo "   http://${WG_IP}:8080              # Open WebUI (chat)"
  echo "   http://${WG_IP}:8080/api/tags     # Ollama API"
fi

echo ""
echo " See README.md and docs/ for full documentation."
echo "============================================================"
