# Model Recommendations for Mac Mini M1 8 GB

This document helps you choose the right language model for the available
hardware.  All sizes and speeds are approximate and vary with context length
and system load.

---

## Hardware constraints

| Resource | Amount | Notes |
|----------|--------|-------|
| Unified RAM | 8 GB | Shared between CPU and GPU |
| Available for model | ~6–6.5 GB | macOS uses ~1.5 GB at idle |
| Storage | 256 GB SSD | Fast NVMe — model loading is quick |
| GPU | M1 10-core GPU | Metal acceleration via Ollama |

**Rule of thumb**: A model's RAM requirement is roughly `(num_parameters × bits_per_weight) / 8`.
For a 7B model at Q4 quantisation: `7 × 10⁹ × 4 / 8 ≈ 3.5 GB`.
Add ~1 GB for the KV cache and framework overhead → ~4.5–5 GB total.

> **Warning**: Do NOT run two large models simultaneously.  Ollama loads one
> model at a time and will evict the previous one.  The `OLLAMA_KEEP_ALIVE=30m`
> setting in `config/ollama.plist` controls how long the loaded model stays
> resident after the last request.

---

## Recommended models

### Tier 1 — Best general-purpose models for 8 GB M1

| Model | Pull command | Disk | RAM at inference | Speed (tok/s) | Best for |
|-------|-------------|------|-----------------|---------------|----------|
| `llama3.2:3b` | `ollama pull llama3.2:3b` | 2.0 GB | ~2.2 GB | ~55–70 | Fast everyday chat, quick Q&A |
| `mistral:7b-instruct-q4_K_M` | `ollama pull mistral:7b-instruct-q4_K_M` | 4.1 GB | ~4.8 GB | ~25–35 | High-quality chat, reasoning |
| `phi3:mini` | `ollama pull phi3:mini` | 2.3 GB | ~2.5 GB | ~50–65 | Efficient instruction following |
| `gemma2:2b` | `ollama pull gemma2:2b` | 1.6 GB | ~1.9 GB | ~70–90 | Ultra-fast simple tasks |

### Tier 2 — Coding assistants

| Model | Pull command | Disk | RAM at inference | Best for |
|-------|-------------|------|-----------------|----------|
| `deepseek-coder:6.7b-instruct-q4_K_M` | `ollama pull deepseek-coder:6.7b-instruct-q4_K_M` | 3.8 GB | ~4.3 GB | Code generation, debugging |
| `codellama:7b-instruct-q4_K_M` | `ollama pull codellama:7b-instruct-q4_K_M` | 3.8 GB | ~4.3 GB | Code completion (FIM support) |
| `qwen2.5-coder:3b` | `ollama pull qwen2.5-coder:3b` | 2.0 GB | ~2.3 GB | Fast code tasks |

### Tier 3 — Specialised / experimental

| Model | Pull command | Disk | RAM at inference | Best for |
|-------|-------------|------|-----------------|----------|
| `llava:7b-v1.6-mistral-q4_K_M` | `ollama pull llava:7b-v1.6-mistral-q4_K_M` | 4.5 GB | ~5.0 GB | Multimodal (image + text) |
| `nomic-embed-text` | `ollama pull nomic-embed-text` | 274 MB | ~0.5 GB | Text embeddings (RAG pipelines) |

---

## Which model should I start with?

```
Do you mainly want to chat / ask questions?
  └─ Yes → Start with llama3.2:3b.
            If answers feel shallow, try mistral:7b-instruct-q4_K_M.

Do you mainly want coding help?
  └─ Yes → Start with deepseek-coder:6.7b-instruct-q4_K_M.
            For FIM (fill-in-the-middle) completions: codellama:7b-instruct-q4_K_M.

Do you need to send images to the model?
  └─ Yes → Use llava:7b-v1.6-mistral-q4_K_M (only if you accept ~5 GB RAM usage).

Do you want the absolute fastest responses?
  └─ Yes → gemma2:2b or llama3.2:1b.
```

---

## Quantisation guide

Ollama model names ending in `_K_M` use GGUF k-quant schemes:

| Suffix | Bits/weight | RAM vs. full precision | Quality loss |
|--------|------------|----------------------|--------------|
| `q8_0` | 8-bit | ~50% | Negligible |
| `q6_K` | 6-bit | ~38% | Very small |
| `q5_K_M` | 5-bit | ~31% | Small |
| `q4_K_M` | 4-bit | ~25% | Acceptable |
| `q4_0` | 4-bit | ~25% | Slightly worse than q4_K_M |
| `q3_K_M` | 3-bit | ~19% | Noticeable but usable |
| `q2_K` | 2-bit | ~13% | Significant — avoid unless necessary |

**Recommendation for 8 GB M1**: `q4_K_M` is the sweet spot — it halves RAM
usage versus `q8_0` with only a small quality drop, enabling 7B models to fit
comfortably alongside macOS system overhead.

---

## Changing the default model in Open WebUI

1. Log into Open WebUI at `http://10.8.0.1:8080`.
2. Click your username → **Settings** → **General**.
3. Set **Default Model**.

Alternatively, set it per conversation using the model selector in the chat
header.

---

## Pulling additional models

```bash
# Example: pull the Mistral 7B instruct model
ollama pull mistral:7b-instruct-q4_K_M

# List all available models on this machine
ollama list

# Remove a model you no longer need (frees disk space)
ollama rm codellama:7b-instruct-q4_K_M

# Show model details (context window, parameters, etc.)
ollama show mistral:7b-instruct-q4_K_M
```

---

## Context window notes

Most 7B models have a 4 096-token context window by default.  Some newer
models (Mistral v0.3, Llama 3.2) support 32 768+ tokens.  On 8 GB of RAM,
long contexts consume proportionally more KV-cache memory.  If you receive
out-of-memory errors, reduce the context by setting a lower `num_ctx` in the
Ollama `Modelfile` or via the Open WebUI model settings.

```bash
# Example: create a Modelfile that caps context to 2048 tokens
cat > /tmp/Modelfile <<'EOF'
FROM mistral:7b-instruct-q4_K_M
PARAMETER num_ctx 2048
EOF
ollama create mistral-short -f /tmp/Modelfile
```
