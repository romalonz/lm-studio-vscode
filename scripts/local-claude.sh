#!/bin/bash
# Run Claude Code as a full agent harness on the LOCAL Qwen model in LM Studio.
# It can read/edit files, run commands, browse, and use subagents, asking before
# risky actions exactly as Claude Code normally does. Any extra arguments are
# passed straight to claude (for example -p "task" for a one-shot run).
# Usage:  scripts/local-claude.sh                 # LEAN: fast, no MCP/skills catalog
#         scripts/local-claude.sh -p "do X"       # one-shot task
#         FULL=1 scripts/local-claude.sh          # FULL kit: hooks, plugins, skills,
#                                                 #   subagents, MCP (ovrworked included).
#                                                 #   Heavier on a 27B/60K window: slower.
export PATH="$HOME/.lmstudio/bin:$HOME/.local/bin:$PATH"
MODEL="${MODEL:-qwen3.8-27b-mlx}"
CTX="${CTX:-131072}"   # LM Studio auto-fits this down to what RAM allows (61,696 here)

lms daemon up >/dev/null 2>&1
lms server start >/dev/null 2>&1
if ! lms ps 2>/dev/null | grep -q "$MODEL"; then
  echo "loading $MODEL with a ${CTX}-token context..." >&2
  lms load "$MODEL" --gpu max --context-length "$CTX" -y >/dev/null 2>&1 || { echo "could not load $MODEL" >&2; exit 1; }
fi

export ANTHROPIC_BASE_URL="http://localhost:1234"
export ANTHROPIC_AUTH_TOKEN="lmstudio"
export ANTHROPIC_API_KEY=""
export ANTHROPIC_MODEL="$MODEL"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
# tell Claude Code the context window the model was ACTUALLY loaded with
REAL_CTX=$(curl -s http://localhost:1234/api/v1/models | python3 -c "
import json,sys
for m in json.load(sys.stdin)['models']:
    if m['key']=='$MODEL' and m['loaded_instances']:
        print(m['loaded_instances'][0]['config']['context_length'])" 2>/dev/null)
# Tell Claude Code a window ~15% smaller than the real one so auto-compact fires
# with room left for the summary itself (compaction sends the whole context).
export CLAUDE_CODE_MAX_CONTEXT_TOKENS=$(( ${REAL_CTX:-$CTX} * 85 / 100 ))
if [ "${FULL:-0}" = "1" ]; then
  # FULL kit: hooks, plugins, skills, subagents, and MCP all load, exactly like your
  # normal Claude Code (the ovrworked plugin included, if installed). This is the same
  # harness — only the model differs. Expect slower, more cramped turns: every skill
  # description, MCP tool schema, and hook output competes for the ~60K window.
  exec claude --model "$MODEL" "$@"
else
  # LEAN (default): no MCP servers, no skills catalog, so the fixed part of every turn
  # stays small and fast. Each tool schema/skill costs context on every request, which
  # a 27B re-reads whenever the cache is invalidated.
  exec claude --model "$MODEL" --strict-mcp-config --mcp-config '{"mcpServers":{}}' --disable-slash-commands "$@"
fi
