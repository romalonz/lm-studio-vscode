#!/bin/bash
# Serve the local MLX model with the wired-limit panic trigger disabled (mlx#3186).
# OpenAI-compatible API at http://<host>:<port>/v1  (use with Cline / any OpenAI client).
export PATH="$HOME/Library/Python/3.9/bin:$PATH"
MODEL="${MODEL:-$HOME/.lmstudio/models/lmstudio-community/Qwen3-Coder-30B-A3B-Instruct-MLX-4bit}"
HOST="${HOST:-0.0.0.0}"; PORT="${PORT:-1234}"
echo "$(date '+%F %T') mlx-serve starting: $MODEL on $HOST:$PORT (wired-limit disabled)" >> "$HOME/.lmstudio/mlx-serve.log"
exec python3 "$HOME/lm-workspace/scripts/mlx-serve.py" --model "$MODEL" --host "$HOST" --port "$PORT" --trust-remote-code >> "$HOME/.lmstudio/mlx-serve.log" 2>&1
