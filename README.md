# Mac Mini LLM Agent

A self-hosted LLM agent running on a **Mac Mini M1 (8 GB RAM / 256 GB SSD)** with
**macOS Tahoe 26.4**, accessible exclusively through an existing **WireGuard VPN** so
that no service is ever reachable from the public internet.

---

## Table of Contents

1. [Why this stack?](#why-this-stack)
2. [Architecture overview](#architecture-overview)
3. [Repository layout](#repository-layout)
4. [Prerequisites](#prerequisites)
5. [Quick start](#quick-start)
6. [Connecting to the agent](#connecting-to-the-agent)
   - [From the Mac Mini itself](#from-the-mac-mini-itself)
   - [From a device on the WireGuard VPN](#from-a-device-on-the-wireguard-vpn)
7. [Recommended models](#recommended-models)
8. [Security design](#security-design)
9. [Updating models and services](#updating-models-and-services)
10. [Troubleshooting](#troubleshooting)

---

## Why this stack?

| Component | Choice | Reason |
|-----------|--------|--------|
| **LLM runtime** | [Ollama](https://ollama.com) | Best-in-class Apple Silicon Metal GPU acceleration; OpenAI-compatible REST API; simple model management; actively maintained |
| **Web UI** | [Open WebUI](https://github.com/open-webui/open-webui) | Feature-rich chat interface; built-in user management & API-key system; works natively with Ollama |
| **Reverse proxy** | [Nginx](https://nginx.org) | Binds to the WireGuard interface only; adds rate-limiting, security headers, and a single TLS termination point |
| **VPN transport** | WireGuard (already running) | Zero-trust network layer; no service port is reachable without an active VPN session |
| **Service manager** | macOS `launchd` | Native to macOS; survives reboots; no third-party daemon required |

### Why Ollama over alternatives?

- **LM Studio** – great GUI but not designed for headless/server use.
- **llama.cpp directly** – lower-level, requires manual model file management.
- **GPT4All** – desktop application, no API server mode.
- **Ollama** gives a clean REST API, handles GGUF quantisation transparently, and
  ships optimised Metal kernels for M1/M2/M3 — making it the obvious choice for a
  headless server.

### Why WireGuard-only exposure?

The Mac Mini is on a home/office LAN.  Binding Ollama and Open WebUI to
`127.0.0.1` and then proxying through Nginx on the **WireGuard peer IP only**
means:

* No LLM port is ever reachable from the public internet.
* No LLM port is reachable even from the local LAN unless the device has a valid
  WireGuard key.
* Compromising a VPN client does not automatically expose the host OS — Nginx rate
  limiting and Open WebUI authentication add two further layers.

---

## Architecture overview

```
                   Public internet
                         │
              ╔══════════╧══════════╗
              ║   WireGuard tunnel  ║  ← VPN clients (phone, laptop, etc.)
              ╚══════════╤══════════╝
                         │  wg0  e.g. 10.8.0.1
                  ┌──────┴──────┐
                  │   Nginx     │  :8080 (WireGuard IP only)
                  │  (reverse   │
                  │   proxy)    │
                  └──────┬──────┘
            ┌────────────┴────────────┐
            │                         │
     ┌──────┴──────┐         ┌────────┴────────┐
     │   Ollama    │         │   Open WebUI    │
     │  :11434     │         │    :3000        │
     │ (localhost) │         │  (localhost)    │
     └─────────────┘         └─────────────────┘
```

Nginx listens on the WireGuard interface IP (default `10.8.0.1`) and routes:

| Path prefix | Upstream |
|-------------|----------|
| `/api/`     | Ollama REST API — for programmatic / IDE access |
| `/`         | Open WebUI — for browser-based chat |

---

## Repository layout

```
mac-mini-llm/
├── README.md                    ← This file
├── LICENSE
├── .gitignore
│
├── scripts/
│   ├── install.sh               ← Master installer; runs all setup steps in order
│   ├── setup_ollama.sh          ← Install Homebrew, Ollama; pull default models
│   ├── setup_openwebui.sh       ← Install Python 3 venv + Open WebUI via pip
│   ├── setup_nginx.sh           ← Install Nginx; write config; load launchd plist
│   ├── start.sh                 ← Start Ollama, Open WebUI, and Nginx
│   ├── stop.sh                  ← Stop all three services gracefully
│   └── update_models.sh         ← Pull latest versions of all installed models
│
├── config/
│   ├── ollama.plist             ← launchd user agent for Ollama
│   ├── openwebui.plist          ← launchd user agent for Open WebUI
│   └── nginx/
│       └── llm-agent.conf       ← Nginx virtual-host: rate-limit, headers, routing
│
└── docs/
    ├── remote-access.md         ← Step-by-step: connect a new device via WireGuard
    ├── security.md              ← Threat model, hardening checklist, design notes
    └── models.md                ← Model comparison table; recommendations for 8 GB M1
```

### Script descriptions

| Script | What it does |
|--------|--------------|
| `scripts/install.sh` | Entry point. Sources the three `setup_*.sh` scripts in order, then registers the launchd plists so services auto-start on login. Run once after cloning this repo. |
| `scripts/setup_ollama.sh` | Installs Homebrew if absent; installs the `ollama` formula; copies `config/ollama.plist` to `~/Library/LaunchAgents/`; starts the daemon; pulls the default model bundle. |
| `scripts/setup_openwebui.sh` | Ensures Python ≥ 3.11 is available; creates a dedicated `venv` at `~/.local/openwebui-venv`; installs `open-webui` via pip; copies `config/openwebui.plist`; starts Open WebUI bound to localhost. |
| `scripts/setup_nginx.sh` | Installs `nginx` via Homebrew; detects the WireGuard peer IP; writes `llm-agent.conf` from `config/nginx/`; reloads Nginx. |
| `scripts/start.sh` | Convenience wrapper — loads all three launchd agents if not already running. |
| `scripts/stop.sh` | Unloads all three launchd agents gracefully. |
| `scripts/update_models.sh` | Iterates `ollama list` and calls `ollama pull <model>` for each, then upgrades Open WebUI with `pip install -U open-webui`. |

### Config descriptions

| Config file | Purpose |
|-------------|---------|
| `config/ollama.plist` | Defines the Ollama server as a macOS launchd user agent. Sets `OLLAMA_HOST=127.0.0.1:11434` so it listens on localhost only. |
| `config/openwebui.plist` | Same pattern for Open WebUI — bound to `127.0.0.1:3000`. |
| `config/nginx/llm-agent.conf` | Nginx server block. Listens on `<WG_IP>:8080`. Routes `/api/` → Ollama, `/` → Open WebUI. Adds `X-Frame-Options`, `X-Content-Type-Options`, CSP header, and per-IP rate limiting. |

---

## Prerequisites

- macOS Tahoe 26.4 (arm64 — Apple Silicon)
- WireGuard already installed and running (`wg show` should list an interface)
- Xcode Command Line Tools: `xcode-select --install`
- Internet access during initial setup

---

## Quick start

```bash
# 1. Clone the repository
git clone https://github.com/migmartinho/mac-mini-llm.git
cd mac-mini-llm

# 2. Make scripts executable
chmod +x scripts/*.sh

# 3. Run the master installer (≈ 5–15 minutes depending on model download speed)
./scripts/install.sh

# 4. Verify everything is running
curl http://127.0.0.1:11434/api/tags   # Ollama model list
curl http://127.0.0.1:3000             # Open WebUI (HTML)
```

On first run of Open WebUI, navigate to `http://<WG_IP>:8080` in your browser,
create an **admin account**, and you are ready to chat.

---

## Connecting to the agent

### From the Mac Mini itself

| Service | URL |
|---------|-----|
| Open WebUI (browser) | `http://localhost:3000` |
| Ollama REST API | `http://localhost:11434` |
| Nginx-proxied endpoint | `http://localhost:8080` |

### From a device on the WireGuard VPN

See **[docs/remote-access.md](docs/remote-access.md)** for the full step-by-step
tutorial.  The short version:

1. Install the WireGuard app on the client device.
2. Obtain the WireGuard client config from the Mac Mini admin (see
   `docs/remote-access.md` for how to generate one).
3. Activate the tunnel.
4. Open `http://10.8.0.1:8080` (or whatever WireGuard IP is assigned to the Mac
   Mini) in a browser → Open WebUI login page.
5. Log in and start chatting.

For programmatic / IDE access (e.g. Continue.dev, Cursor, VS Code extensions):

```
Ollama base URL: http://10.8.0.1:8080/api
```

---

## Recommended models

See **[docs/models.md](docs/models.md)** for the full comparison table.

Quick picks for 8 GB M1:

| Use case | Model | RAM usage |
|----------|-------|-----------|
| Fast general chat | `llama3.2:3b` | ~2.0 GB |
| High-quality chat | `mistral:7b-instruct-q4_K_M` | ~4.1 GB |
| Coding assistant | `deepseek-coder:6.7b-instruct-q4_K_M` | ~3.8 GB |
| Tiny / embedded | `phi3:mini` | ~2.3 GB |

```bash
# Pull a model interactively
ollama pull llama3.2:3b
```

---

## Security design

See **[docs/security.md](docs/security.md)** for the full threat model and
hardening checklist.  Key points:

- **No public exposure**: Nginx binds to the WireGuard IP only — TCP port 8080 is
  not reachable from the LAN or internet without a valid WireGuard key.
- **Localhost-only backends**: Ollama and Open WebUI listen on `127.0.0.1` and are
  never directly reachable over the network.
- **Rate limiting**: Nginx limits API calls to 10 req/s per peer IP, preventing
  runaway inference loops from misbehaving clients.
- **Open WebUI authentication**: Every user needs an account; the admin approves
  new sign-ups.
- **No root required**: All services run as the current macOS user via launchd user
  agents.

---

## Updating models and services

```bash
./scripts/update_models.sh
```

This pulls the latest layer checksums for every installed model and upgrades the
Open WebUI Python package.  No restart is needed for model updates; a restart is
needed after Open WebUI upgrades (`./scripts/stop.sh && ./scripts/start.sh`).

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `ollama: command not found` | Run `./scripts/setup_ollama.sh` again or open a new terminal so Homebrew's PATH is active |
| Open WebUI shows blank page | Give it 30 s to start; check `~/Library/Logs/openwebui.log` |
| Can't reach `http://10.8.0.1:8080` from VPN client | Confirm `wg show` is active on the Mac Mini and the client tunnel is up |
| Slow inference | Use a smaller/more-quantised model (see `docs/models.md`) |
| Port 8080 already in use | Edit `WG_PORT` at the top of `config/nginx/llm-agent.conf` and reload Nginx |
