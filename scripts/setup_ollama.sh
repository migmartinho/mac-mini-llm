#!/usr/bin/env bash
# =============================================================================
# setup_ollama.sh — Install Ollama and pull the default model set
#
# What this script does:
#   • Installs Homebrew if not already present
#   • Installs (or upgrades) the `ollama` Homebrew formula
#   • Copies the launchd plist so Ollama starts on login
#   • Starts the Ollama daemon (listens on 127.0.0.1:11434)
#   • Pulls the recommended starter models for an 8 GB M1 Mac
#
# Motivation:
#   Ollama ships pre-built Apple Silicon Metal GPU kernels, meaning the M1 GPU
#   (with its 8 GB unified memory) is used automatically.  The OLLAMA_HOST
#   variable restricts the server to localhost — Nginx is the only public-facing
#   entry point.
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHAGENTS_DIR="${HOME}/Library/LaunchAgents"
PLIST_SRC="${REPO_DIR}/config/ollama.plist"
PLIST_DST="${LAUNCHAGENTS_DIR}/com.ollama.server.plist"

# Default models to pull on a fresh install.
# These fit comfortably within 8 GB unified memory when loaded one at a time.
DEFAULT_MODELS=(
  "llama3.2:3b"         # ~2.0 GB — fast, capable general chat
  "mistral:7b-instruct-q4_K_M"  # ~4.1 GB — highest-quality single model that fits
)

# ── 1. Homebrew ────────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  echo "  Installing Homebrew …"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add Homebrew to PATH for the rest of this script
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  echo "  Homebrew already installed — skipping."
fi

# ── 2. Ollama ──────────────────────────────────────────────────────────────
if brew list --formula | grep -q "^ollama$"; then
  echo "  Ollama already installed — upgrading …"
  brew upgrade ollama || true   # non-fatal: already at latest is fine
else
  echo "  Installing Ollama via Homebrew …"
  brew install ollama
fi

# ── 3. launchd plist ───────────────────────────────────────────────────────
mkdir -p "${LAUNCHAGENTS_DIR}"

if [[ -f "${PLIST_DST}" ]]; then
  echo "  Unloading existing Ollama launchd agent …"
  launchctl unload "${PLIST_DST}" 2>/dev/null || true
fi

echo "  Installing Ollama launchd plist …"
# Substitute the home directory path into the plist before copying
sed "s|__HOME__|${HOME}|g" "${PLIST_SRC}" > "${PLIST_DST}"
launchctl load -w "${PLIST_DST}"

# ── 4. Wait for daemon to be ready ─────────────────────────────────────────
echo "  Waiting for Ollama to start …"
for i in {1..15}; do
  if curl -sf http://127.0.0.1:11434/api/tags &>/dev/null; then
    echo "  Ollama is up."
    break
  fi
  sleep 2
done

if ! curl -sf http://127.0.0.1:11434/api/tags &>/dev/null; then
  echo "  ⚠  Ollama did not respond in time — check ~/Library/Logs/ollama.log"
  exit 1
fi

# ── 5. Pull default models ─────────────────────────────────────────────────
echo "  Pulling default models (this may take several minutes) …"
for model in "${DEFAULT_MODELS[@]}"; do
  echo "    ollama pull ${model}"
  ollama pull "${model}"
done

echo "  ✓ Ollama setup complete."
echo "    Endpoint : http://127.0.0.1:11434"
echo "    Models   : $(ollama list | tail -n +2 | awk '{print $1}' | tr '\n' ' ')"
