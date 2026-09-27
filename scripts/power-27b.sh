#!/bin/bash
# Bring up the 27B "power option" (Qwen 3.8-27B, moderate thinking) via LM Studio on
# port 1236, ON DEMAND. It auto-unloads after 30 min idle (frees ~16GB). Use it when
# you want max capability; the reliable 14Bs stay on port 1234 the whole time.
# CAUTION: running the 27B while a 14B is also active drops free RAM to ~18% on this
# 36GB Mac (reboot-risk zone). Prefer using the 27B alone; keep the Mac on AC power.
export PATH="$HOME/.lmstudio/bin:$PATH"
lms daemon up >/dev/null 2>&1
echo "loading 27B (moderate thinking, 30-min idle auto-unload)..."
lms load qwen3.8-27b-mlx --gpu max --ttl 1800 -y >/dev/null 2>&1 && \
lms server start --port 1236 --bind 0.0.0.0 --cors >/dev/null 2>&1 && \
echo "27B ready:  http://100.96.67.68:1236/v1   model: qwen3.8-27b-mlx" || echo "failed to start 27B"
