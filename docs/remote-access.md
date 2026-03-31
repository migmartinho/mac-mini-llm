# Remote Access — Connecting to the LLM Agent via WireGuard

This document walks you through connecting **any device** to the Mac Mini LLM
agent over the existing WireGuard VPN.  You do not need to open any firewall
ports or change any router settings — WireGuard handles everything.

---

## Overview

```
Your device (phone / laptop / desktop)
        │
        │  WireGuard encrypted tunnel (UDP, port 51820)
        ▼
Mac Mini M1 — WireGuard server (10.8.0.1)
        │
        │  Nginx reverse proxy (localhost)
        ▼
  Open WebUI (chat UI)  /  Ollama API
```

All traffic between your device and the Mac Mini is encrypted by WireGuard
using Curve25519 key exchange and ChaCha20-Poly1305 encryption.  No
intermediate server is involved.

---

## Prerequisites on the Mac Mini (server side)

1. WireGuard is already installed and running.
2. The Mac Mini's WireGuard interface (e.g. `wg0`) has IP `10.8.0.1/24`.
3. The LLM agent stack is installed and running (`./scripts/start.sh`).
4. You have shell access to the Mac Mini (locally or via SSH on the LAN).

---

## Step 1 — Generate a key pair for the new client (on the Mac Mini)

```bash
# Install wireguard-tools if not already present
brew install wireguard-tools

# Generate a key pair for the new peer
wg genkey | tee /tmp/client_private.key | wg pubkey > /tmp/client_public.key
cat /tmp/client_private.key   # keep this secret — goes into the client config
cat /tmp/client_public.key    # share this with the server config
```

---

## Step 2 — Add the new peer to the Mac Mini's WireGuard config

Open the Mac Mini's WireGuard config (typically
`/opt/homebrew/etc/wireguard/wg0.conf` or configured via the WireGuard app):

```ini
[Peer]
# Friendly name comment
PublicKey = <paste client_public.key here>
AllowedIPs = 10.8.0.2/32   # assign the next available VPN IP to this client
```

Reload WireGuard to apply the change:

```bash
# If using the WireGuard app: open the app and click "Activate"
# If using wg-quick:
sudo wg syncconf wg0 <(wg-quick strip wg0)
```

---

## Step 3 — Create the client configuration file

Create a file called `mac-mini-llm.conf` on your client device:

```ini
[Interface]
PrivateKey = <paste content of /tmp/client_private.key>
Address    = 10.8.0.2/24         # the IP assigned in Step 2
DNS        = 10.8.0.1            # optional: use Mac Mini as DNS resolver

[Peer]
PublicKey           = <Mac Mini's WireGuard public key>
Endpoint            = <Mac Mini's public IP or DDNS hostname>:51820
AllowedIPs          = 10.8.0.0/24   # route only VPN traffic through tunnel
PersistentKeepalive = 25            # keeps NAT hole open; recommended for mobile
```

**Finding the Mac Mini's public IP:**
```bash
# Run on the Mac Mini
curl -s https://checkip.amazonaws.com
```

**Finding the Mac Mini's WireGuard public key:**
```bash
# Run on the Mac Mini
sudo wg show wg0 public-key
```

> **Tip**: If your home/office IP is dynamic, consider setting up a free DDNS
> service (e.g. DuckDNS) and using the hostname as the `Endpoint`.

---

## Step 4 — Install WireGuard on the client device

| Platform | Install |
|----------|---------|
| macOS | [App Store](https://apps.apple.com/app/wireguard/id1451685025) |
| iOS / iPadOS | [App Store](https://apps.apple.com/app/wireguard/id1441195209) |
| Android | [Play Store](https://play.google.com/store/apps/details?id=com.wireguard.android) |
| Windows | [wireguard.com/install](https://www.wireguard.com/install/) |
| Linux | `sudo apt install wireguard` or `sudo dnf install wireguard-tools` |

---

## Step 5 — Import the config and connect

### macOS / iOS / Android (WireGuard app)
1. Open the WireGuard app.
2. Tap/click **+** → **Create from file or archive** (or scan the QR code
   generated in the optional section below).
3. Select `mac-mini-llm.conf`.
4. Toggle the tunnel **ON**.

### Linux
```bash
sudo cp mac-mini-llm.conf /etc/wireguard/mac-mini-llm.conf
sudo wg-quick up mac-mini-llm
# To connect automatically on boot:
sudo systemctl enable --now wg-quick@mac-mini-llm
```

### Windows
1. Open the WireGuard application.
2. Click **Import tunnel(s) from file** and select `mac-mini-llm.conf`.
3. Click **Activate**.

---

## Step 6 — Access the LLM agent

Once the tunnel is active, open a browser on the client device:

| Service | URL |
|---------|-----|
| Open WebUI (chat) | `http://10.8.0.1:8080` |
| Ollama REST API | `http://10.8.0.1:8080/api` |

On the first visit, create an account on Open WebUI.  The admin (first account)
must approve subsequent sign-ups unless you change the setting in
**Admin Settings → Users**.

---

## Optional — Generate a QR code for mobile devices

Instead of manually entering the config on a phone, generate a QR code:

```bash
# On the Mac Mini, install qrencode
brew install qrencode

# Print the QR code in the terminal (show briefly, then delete)
qrencode -t ansiutf8 < /path/to/mac-mini-llm.conf
```

Scan the QR code with the WireGuard mobile app.

---

## Connecting from a coding IDE or AI assistant

Many IDEs (VS Code + Continue.dev, Cursor, Zed) can use a local Ollama server
as their AI backend.  Configure them with:

| Setting | Value |
|---------|-------|
| **Ollama base URL** | `http://10.8.0.1:8080/api` |
| **Model** | `llama3.2:3b` (or whichever model you pulled) |

Example for **Continue.dev** (`~/.continue/config.json`):

```json
{
  "models": [
    {
      "title": "Mac Mini — Llama 3.2 3B",
      "provider": "ollama",
      "model": "llama3.2:3b",
      "apiBase": "http://10.8.0.1:8080/api"
    }
  ]
}
```

---

## Revoking access for a device

To remove a client from the VPN (e.g. a lost phone):

```bash
# On the Mac Mini — remove the peer by public key
sudo wg set wg0 peer <client_public_key> remove
# Make the change permanent in wg0.conf and reload
```

The device will instantly lose access to the LLM agent and the VPN.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Tunnel activates but can't reach `10.8.0.1` | WireGuard handshake failed | Check `Endpoint` IP/hostname and port 51820 is reachable; check Mac Mini firewall |
| `http://10.8.0.1:8080` times out | Nginx not running | SSH to Mac Mini and run `./scripts/start.sh` |
| Open WebUI login page loads but API calls fail | Ollama not running | Run `ollama list` on Mac Mini; check `~/Library/Logs/ollama.log` |
| Very slow responses | Model too large for RAM | Switch to `llama3.2:3b`; see `docs/models.md` |
