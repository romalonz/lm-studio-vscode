#!/bin/sh
# One-shot prompt against the LM Studio server. Usage: scripts/chat.sh "your prompt"
MODEL="${MODEL:-qwen3.8-27b-mlx}"
curl -s http://localhost:1234/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "$(printf '{"model":"%s","messages":[{"role":"user","content":%s}]}' "$MODEL" "$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["choices"][0]["message"]["content"])'
