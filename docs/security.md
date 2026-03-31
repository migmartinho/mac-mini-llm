# Security Design

This document describes the security architecture of the Mac Mini LLM agent,
the threat model it is designed against, and a hardening checklist.

---

## Threat model

| Threat | Severity | Mitigation |
|--------|----------|------------|
| Attacker on the public internet reaches the LLM API | Critical | Nginx binds to WireGuard IP only; the port is unreachable without a valid WG key |
| Attacker on the local LAN reaches the LLM API | High | Same — WireGuard IP is not the LAN IP; LAN neighbours cannot reach port 8080 |
| Stolen/compromised WireGuard client key | High | Revoke the peer key immediately (see `docs/remote-access.md`); each client has a unique key |
| Unauthenticated LLM usage by a VPN peer | Medium | Open WebUI enforces user accounts; admin must approve new sign-ups |
| Runaway API client saturates GPU/CPU | Medium | Nginx rate-limiting (10 r/s general, 2 r/s inference) blocks abusive clients |
| Session hijacking via XSS in Open WebUI | Low | CSP, X-Frame-Options, and X-XSS-Protection headers restrict script execution |
| Prompt-injection attack via crafted user input | Low-Medium | Mitigated by model isolation (no tool use / code execution by default); review Open WebUI's system prompt settings |
| Sensitive data in model responses cached on disk | Low | Open WebUI stores chat history in `~/.local/openwebui-data` — full-disk encryption (FileVault) is recommended |

---

## Defence-in-depth layers

```
Layer 0: WireGuard VPN  ─── cryptographic mutual authentication + encryption
Layer 1: Nginx          ─── rate limiting, security headers, WG-IP binding
Layer 2: Open WebUI     ─── user accounts, session management, API keys
Layer 3: Ollama         ─── localhost-only binding (127.0.0.1)
Layer 4: macOS sandbox  ─── launchd user agents (no root); FileVault; Gatekeeper
```

An attacker must defeat all four layers simultaneously to reach the model —
compared with a typical "bind to 0.0.0.0" deployment that has zero layers.

---

## WireGuard security notes

WireGuard uses:
- **Curve25519** for Diffie–Hellman key exchange
- **ChaCha20-Poly1305** for authenticated encryption
- **BLAKE2s** for hashing
- **SipHash24** for hashtable keys
- **HKDF** for key derivation

These are modern, audited primitives.  WireGuard has a much smaller attack
surface than OpenVPN or IPsec because the codebase is ~4 000 lines vs.
~100 000+ lines for OpenVPN.

**Recommendations:**
- Rotate client key pairs every 6–12 months.
- Use `PersistentKeepalive = 25` on mobile clients to keep NAT mappings alive
  without creating an always-on power drain.
- Keep the Mac Mini's WireGuard `ListenPort` (default 51820) open in the router
  — do NOT additionally expose ports 8080, 11434, or 3000.

---

## Nginx security configuration

The Nginx config (`config/nginx/llm-agent.conf`) enforces:

### Binding
```nginx
listen __WG_IP__:8080;   # WireGuard IP only, never 0.0.0.0
```

### Rate limiting
```nginx
limit_req_zone $binary_remote_addr zone=llm_general:10m   rate=10r/s;
limit_req_zone $binary_remote_addr zone=llm_inference:10m rate=2r/s;
```

- The **general** zone (10 r/s) applies to all routes.
- The **inference** zone (2 r/s) applies to `/api/generate` and `/api/chat`
  — the endpoints that trigger GPU work.

### Security response headers
| Header | Value | Protects against |
|--------|-------|-----------------|
| `X-Frame-Options` | `SAMEORIGIN` | Clickjacking |
| `X-Content-Type-Options` | `nosniff` | MIME-type sniffing attacks |
| `X-XSS-Protection` | `1; mode=block` | Reflected XSS (legacy browsers) |
| `Referrer-Policy` | `strict-origin` | Referrer leakage |
| `Content-Security-Policy` | (see config) | XSS, data injection |
| `server_tokens off` | — | Hides Nginx version |

### Streaming proxying
`proxy_buffering off` is set so that streamed LLM tokens reach the client
immediately without being buffered on disk.  This also means Nginx cannot
inadvertently cache sensitive model outputs.

---

## Ollama security notes

- **localhost-only**: `OLLAMA_HOST=127.0.0.1:11434` in `config/ollama.plist`.
- **No authentication** at the Ollama layer: Ollama does not currently ship
  with built-in auth.  Authentication is delegated to Open WebUI + Nginx.
- **No tool use / code execution** by default.  If you enable Ollama's function-
  calling features in the future, review what tools the model can access.
- **Model files** are stored in `~/.ollama/models/` — these are plain GGUF
  binary files and do not execute; they cannot exfiltrate data on their own.

---

## Open WebUI security notes

- **Authentication enabled**: `WEBUI_AUTH=True` in the launchd plist.
- **Admin approval**: New user sign-ups require admin approval by default.
  To enforce this: **Admin Panel → Settings → Users → Default User Role → pending**.
- **API keys**: Users can generate API keys in their profile for programmatic
  access.  These keys are scoped to the user's account.
- **Secret key**: `WEBUI_SECRET_KEY` is a 256-bit random hex string generated
  once by `setup_openwebui.sh` and stored in `~/.local/openwebui.env`
  (mode 600).  It is never committed to git.
- **Chat history** is stored locally at `~/.local/openwebui-data/`.  Enable
  FileVault on the Mac Mini to encrypt this data at rest.

---

## macOS host hardening checklist

- [ ] **FileVault enabled**: System Settings → Privacy & Security → FileVault
- [ ] **Firewall enabled**: System Settings → Network → Firewall → Turn On
      (the LLM services bind to localhost/WG IP so are already not accessible
       externally, but the firewall adds a defence-in-depth layer)
- [ ] **Automatic security updates**: System Settings → General → Software Update
      → enable "Install Security Responses and System Files"
- [ ] **Screen lock**: Require password immediately after sleep/screen saver
- [ ] **SSH key-only login** (if SSH is enabled): disable password authentication
      in `/etc/ssh/sshd_config` (`PasswordAuthentication no`)
- [ ] **Remote Login scoped to known IPs**: System Settings → Sharing →
      Remote Login → Allow access for: specific users; additionally restrict
      via `/etc/hosts.allow` or the macOS firewall to WireGuard range only
- [ ] **Disable unnecessary sharing services**: AirDrop, Screen Sharing,
      Printer Sharing — all off unless actively needed
- [ ] **Rotate WireGuard client keys** every 6–12 months

---

## Secrets management

| Secret | Location | Mode | Committed to git? |
|--------|----------|------|-------------------|
| WireGuard private key | Managed by WireGuard app or `/opt/homebrew/etc/wireguard/` | 600 | No |
| `WEBUI_SECRET_KEY` | `~/.local/openwebui.env` | 600 | No |
| Open WebUI user passwords | `~/.local/openwebui-data/` (SQLite, bcrypt hashed) | 700 | No |

The `.gitignore` in this repository explicitly excludes `.env` and `secrets/`
to prevent accidental commits.

---

## Incident response

If you suspect a VPN key has been compromised:

```bash
# 1. Immediately revoke the peer
sudo wg set wg0 peer <compromised_pubkey> remove

# 2. Save the change permanently
# Edit wg0.conf and remove the [Peer] block, then:
sudo wg-quick down wg0 && sudo wg-quick up wg0

# 3. Rotate: generate a new key pair for the legitimate owner and re-add
#    following docs/remote-access.md Step 1–2

# 4. Review Open WebUI logs for unusual activity
cat ~/Library/Logs/openwebui.log | grep -E "(login|ERROR)"
```
