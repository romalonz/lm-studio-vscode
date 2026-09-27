---
name: mlx-no-reboot
description: Stop an Apple Silicon Mac from randomly rebooting or freezing (often with screen glitching, no crash log) while serving a large MLX model in LM Studio. This is a known Apple GPU-driver kernel-panic bug, not a misconfiguration. Use when a Mac hard-reboots during local LLM inference (LM Studio / MLX / mlx_lm), when a 27-30B+ MLX model on a 32-64GB Mac crashes the whole machine under load, or when someone wants a serving setup that does not panic. The fix: serve via mlx_lm.server with the wired-memory limit disabled.
metadata:
  origin: lm-studio-vscode
---

# Stop the Mac rebooting while serving a large MLX model

## The symptom

An Apple Silicon Mac (commonly 32-64 GB) running a 27-30B+ MLX model in LM Studio
**hard-reboots or freezes** under load, sometimes with screen glitching / color
blocks. There is usually **no kernel panic file and no OOM/jetsam log** the user can
find, because the failure is in Apple's GPU driver, below the app.

## The root cause (this is NOT the user's fault)

It is a known bug in Apple's `IOGPUFamily` GPU driver, tracked upstream:
- `ml-explore/mlx#3186` (IOGPUMemory prepare-count underflow)
- `ml-explore/mlx-lm#883` (mlx_lm.server kernel panic)
- LM Studio bug-tracker `#1504` (36 GB M-Max, qwen3-coder-30b: crash + screen glitch)

MLX calls `mx.set_wired_limit(~75% of RAM)`. Wired memory can't be paged out, and its
per-buffer residency-set traffic (plus KV cache growing with context) trips the driver
bug, which panics and reboots the whole machine. A single-variable test
(ronm92130 gist, 20 runs / 9 h) showed neutralizing `set_wired_limit` takes a machine
from "panics in ~100 s" to no panic. Memory pressure alone only causes a clean error;
**the wired limit is what reboots you.** LM Studio's engine forces the wired limit and
gives no way to disable it, so capping context in LM Studio only reduces the odds.

## The fix: serve via mlx_lm.server with the wired limit disabled

Serve the same model through `mlx_lm` instead of LM Studio's server, with
`mx.set_wired_limit` monkey-patched to a no-op. No admin needed. Same model files
(standard MLX safetensors), same Cline-over-network usage. Measured on a 36 GB M-Max:
no reboots, and **faster** than LM Studio (112 vs 57 tok/s), memory grows naturally,
worst case is a clean HTTP error instead of a reboot.

```sh
# 1. install mlx-lm (no admin)
python3 -m pip install --user --upgrade mlx-lm

# 2. serve with the panic trigger disabled (scripts/mlx-serve.py patches set_wired_limit)
MODEL="$HOME/.lmstudio/models/lmstudio-community/Qwen3-Coder-30B-A3B-Instruct-MLX-4bit" \
  scripts/mlx-serve.sh          # OpenAI API on http://0.0.0.0:1234/v1
```

`scripts/mlx-serve.py` is the whole trick: it sets `mx.set_wired_limit = lambda *a,**k: 0`
before starting `mlx_lm.server`. That one line is the fix.

## Point clients at it

- **Cline / any OpenAI client:** base URL `http://<host>:1234/v1`, model name
  `default_model` (mlx_lm.server names the loaded model that), API key anything.
- Over Tailscale, use the host's tailnet IP. mlx_lm.server is **OpenAI-only**; it does
  NOT serve the Anthropic `/v1/messages` endpoint, so the Claude-Code-on-local path
  won't work against it (use Cline, or keep LM Studio for that).

## Make it survive reboots (KeepAlive LaunchAgent, no admin)

`~/Library/LaunchAgents/com.romeo.mlx-serve.plist` with `RunAtLoad` + `KeepAlive`
running `scripts/mlx-serve.sh` restarts the server on boot and if it ever dies:

```xml
<key>ProgramArguments</key>
<array><string>/bin/bash</string><string>/Users/USER/lm-workspace/scripts/mlx-serve.sh</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
```
`launchctl bootstrap gui/$UID <plist>` to load. Stop LM Studio's own server first so it
doesn't fight for port 1234 (`lms server stop`).

## Layer 2: make it seamless, not just non-fatal

Disabling the wired limit removes the *reboot*. To also avoid the *clean error*, keep
each request inside the memory budget:
- **Short subtasks / bounded context** (a browser-automation batch = many short fresh
  requests, not one giant context). Requests then never approach the ceiling.
- **parallel = 1** for the LM Studio path; for mlx_lm.server, one request at a time.
- Keep the Mac on **AC power** (heavy inference on battery drains and auto-shuts-off).

The physics: on a 36 GB Mac with a ~17 GB model you cannot have unlimited context AND
zero errors AND no reboots — something must be bounded, and context is the free lever
because the workload does not need a huge one. Bound it and the experience is seamless.

## If admin is available (strongest system-level mitigation)

```sh
sudo sysctl iogpu.wired_limit_mb=<a value below total RAM, leaving OS headroom>
sudo sysctl iogpu.disable_wired_collector=1
```
Make persistent via a /Library/LaunchDaemons plist. Without admin, the mlx-serve fix
above is the route.

## References
mlx#3186, mlx-lm#883, LM Studio bug-tracker #1504, the ronm92130 test-report gist,
Harperbot/metal-guard (a Python safety layer that also lowers the trigger rate).
