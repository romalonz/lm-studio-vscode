---
name: local-model-setup-mac
description: The reliable, reboot-free way to run local coding models on a 32-36 GB Apple Silicon Mac and use them from another machine (Cline over Tailscale). Two small models served on demand with no reboots, plus an optional heavier model as a sparingly-used power option. Use when setting up local LLM serving on a memory-constrained Mac, when a larger model keeps rebooting/hanging the machine, or when choosing a model size that actually fits.
metadata:
  origin: lm-studio-vscode
---

# Local model setup that actually holds on a 32-36 GB Mac

Hard-won conclusion from a long debugging session on a 36 GB M-Max: a 27-30B model
cannot run *reliably* on 36 GB. Every path fails one way (LM Studio reboots via the
Apple GPU driver bug mlx#3186; the no-reboot mlx_lm server hangs or pages badly on big
models). The setup that works is **two ~14B models served on demand via mlx_lm with the
wired-limit disabled**, plus the big model kept only as an occasional power option.

See also [[mlx-no-reboot]] (the wired-limit fix) and [[lmstudio-context-fix]].

## The reliable tier: two 14B models, one on-demand server

- **Qwen2.5-Coder-14B-Instruct** — best 14B pure coder (~89% HumanEval), non-reasoning,
  fast. For Act-mode coding.
- **Qwen3-14B** — best 14B all-rounder: hybrid reasoning, strong tool/function calling,
  128K context, rivals a 32B on STEM/code at half the size. For Plan-mode reasoning.

Both are ~8 GB at 4-bit, so on a 36 GB Mac either one runs with huge headroom. They are
served by ONE `mlx_lm` server on port 1234 that loads a model **on demand by name** and
swaps to the other when you request it (one resident at a time; swap ~3-4s). Requests
use the standard OpenAI `model` field, and the server advertises both names on
`/v1/models` so they show in Cline's dropdown.

Serve them with `scripts/mlx-serve.py` via `scripts/mlx-serve.sh`, driven by a KeepAlive
LaunchAgent (`agents/com.romeo.mlx-serve.plist`) whose env sets:

```
MODEL=<coder path>   PORT=1234
MLX_SERVE_MODELS="qwen2.5-coder-14b=<coder path>;qwen3-14b=<qwen3-14b path>"
```

Cline (over Tailscale): base URL `http://<mac-tailscale-ip>:1234/v1`, pick either model
in the dropdown. Set a different model per Cline mode (Plan=qwen3-14b, Act=coder) and
Shift+Tab auto-switches.

## The power option: the big model, used sparingly

The bigger model (e.g. Qwen 3.8-27B, a `qwen3_5` VLM) can ONLY be served by LM Studio,
which is the reboot-bug engine. Keep it as an on-demand extra, not the default:
`scripts/power-27b.sh` loads it via LM Studio on port 1236 with a 30-min idle TTL
(auto-unloads to free ~16 GB). Cline: base URL `...:1236/v1`.

**Known risk, stated plainly:** the 27B (16 GB) plus ONE 14B both loaded drops free RAM
to ~18% on a 36 GB Mac — the reboot-risk zone (only one 14B loads at a time, so the max
concurrent is one 14B + the 27B). Use the 27B sparingly, ideally not while hammering a
14B, and keep the Mac on AC. It is NOT auto-started on boot, so the default state stays
the reliable 14Bs.

## The full protection stack (all no-admin LaunchAgents)

- `com.romeo.mlx-serve` (KeepAlive): the 14B on-demand server; restarts if the process dies.
- `com.romeo.mlx-watchdog` (KeepAlive): pings `/health` (swap-free); restarts the server
  after ~3 min of no response (catches mlx_lm inference deadlocks).
- `com.romeo.caffeinate` (KeepAlive): keeps the Mac awake (lid open) so it serves 24/7.
- The 27B is manual/on-demand (no agent) with a TTL, by design.

## Why not just run the 27/30B

Because on 36 GB it either reboots the whole machine (Apple GPU driver bug, no crash log)
or, on the no-reboot server, hangs and pages the 17 GB of weights on every idle. The 14B
tier removes the memory edge entirely: fast, no reboots, and the Mac keeps its RAM when
idle. A 14B here rivals a 32B on many tasks, so it is not a big capability sacrifice.
