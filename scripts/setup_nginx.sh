#!/usr/bin/env bash
# =============================================================================
# setup_nginx.sh — Install and configure the Nginx reverse proxy
#
# What this script does:
#   • Installs `nginx` via Homebrew if not present
#   • Detects the WireGuard interface IP (the IP assigned to this Mac Mini
#     inside the VPN mesh)
#   • Writes /opt/homebrew/etc/nginx/servers/llm-agent.conf from the template
#     in config/nginx/llm-agent.conf, substituting the actual WireGuard IP
#   • Starts/reloads Nginx via launchd
#
# Usage:
#   ./scripts/setup_nginx.sh               # normal install
#   ./scripts/setup_nginx.sh --print-wg-ip # just print the detected WG IP
#
# Motivation:
#   Nginx acts as the single, security-hardened entry point into the LLM stack.
#   By binding ONLY to the WireGuard interface IP the services are invisible to
#   the local LAN and to the public internet.  Rate limiting at the Nginx layer
#   protects against runaway API clients before they can saturate the CPU/GPU.
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF_SRC="${REPO_DIR}/config/nginx/llm-agent.conf"

# ── Detect WireGuard IP ────────────────────────────────────────────────────
# WireGuard on macOS appears as a utun* interface (kernel) or as a named
# interface if using the official WireGuard app.  We look for an interface
# that has an address in a common private VPN range (10.x.x.x or 192.168.x.x)
# and is NOT the LAN adapter.
#
# Adjust WG_INTERFACE below if your setup uses a different interface name.
WG_INTERFACE=""
WG_IP=""

# Try common WireGuard interface names first
for iface in wg0 utun3 utun4 utun5 utun6; do
  if ifconfig "${iface}" &>/dev/null 2>&1; then
    ADDR=$(ifconfig "${iface}" 2>/dev/null | awk '/inet /{print $2}' | head -1)
    if [[ -n "${ADDR}" ]]; then
      WG_INTERFACE="${iface}"
      WG_IP="${ADDR}"
      break
    fi
  fi
done

# Fallback: scan all utun* interfaces
if [[ -z "${WG_IP}" ]]; then
  while IFS= read -r iface; do
    ADDR=$(ifconfig "${iface}" 2>/dev/null | awk '/inet /{print $2}' | head -1)
    if [[ -n "${ADDR}" ]]; then
      WG_INTERFACE="${iface}"
      WG_IP="${ADDR}"
      break
    fi
  done < <(ifconfig -l | tr ' ' '\n' | grep '^utun')
fi

if [[ -z "${WG_IP}" ]]; then
  echo "  ⚠  Could not detect WireGuard interface IP." >&2
  echo "  Set WG_IP manually at the top of this script or in the Nginx config." >&2
  # Fall back to a sensible default so the script does not abort
  WG_IP="10.8.0.1"
fi

# --print-wg-ip mode (called by install.sh for display purposes)
if [[ "${1:-}" == "--print-wg-ip" ]]; then
  echo "${WG_IP}"
  exit 0
fi

echo "  Detected WireGuard interface: ${WG_INTERFACE:-unknown} / ${WG_IP}"

# ── Install Nginx ──────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if brew list --formula | grep -q "^nginx$"; then
  echo "  Nginx already installed — skipping."
else
  echo "  Installing Nginx via Homebrew …"
  brew install nginx
fi

NGINX_SERVERS_DIR="$(brew --prefix)/etc/nginx/servers"
mkdir -p "${NGINX_SERVERS_DIR}"

# ── Write site config ─────────────────────────────────────────────────────
echo "  Writing Nginx site config …"
sed "s|__WG_IP__|${WG_IP}|g" "${CONF_SRC}" \
  > "${NGINX_SERVERS_DIR}/llm-agent.conf"

# ── Validate config ───────────────────────────────────────────────────────
echo "  Validating Nginx config …"
nginx -t

# ── Start / reload Nginx via launchd ──────────────────────────────────────
NGINX_PLIST="$(brew --prefix)/opt/nginx/homebrew.mxcl.nginx.plist"
LAUNCHAGENTS_DIR="${HOME}/Library/LaunchAgents"
PLIST_DST="${LAUNCHAGENTS_DIR}/homebrew.mxcl.nginx.plist"

if launchctl list | grep -q "homebrew.mxcl.nginx"; then
  echo "  Reloading Nginx …"
  nginx -s reload
else
  echo "  Starting Nginx via launchd …"
  mkdir -p "${LAUNCHAGENTS_DIR}"
  if [[ -f "${NGINX_PLIST}" ]]; then
    cp "${NGINX_PLIST}" "${PLIST_DST}"
    launchctl load -w "${PLIST_DST}"
  else
    # Fallback: start directly (Nginx will be running but not auto-restarted)
    nginx
  fi
fi

echo "  ✓ Nginx setup complete."
echo "    Listening on ${WG_IP}:8080"
echo "      /       → Open WebUI   (http://127.0.0.1:3000)"
echo "      /api/   → Ollama API   (http://127.0.0.1:11434)"
