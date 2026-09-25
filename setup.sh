#!/bin/bash
# One-shot setup: local AI in VS Code on Apple Silicon, with working auto-compaction.
#
# What it does, in order:
#   1. Installs the LM Studio headless engine + `lms` CLI (no admin, into ~/.lmstudio).
#   2. Downloads one MLX model (Qwen 3.8 27B 4-bit, ~16 GB) unless SKIP_MODEL=1.
#   3. Installs the two VS Code extensions (LM Studio Code panel + Cline).
#   4. Writes VS Code settings so the panel auto-compacts before the context limit.
#   5. Loads the model and starts the local API server.
#
# Usage:
#   ./setup.sh                 # full setup
#   SKIP_MODEL=1 ./setup.sh    # everything except the 16 GB model download
#   MODEL_REPO=owner/repo ./setup.sh   # use a different MLX repo
#
# Target: Apple Silicon Mac with >=32 GB unified memory. Tested on M5 Max, 36 GB.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MODEL_REPO="${MODEL_REPO:-lmstudio-community/Qwen3.8-27B-MLX-4bit}"
MODEL_KEY="${MODEL_KEY:-qwen3.8-27b-mlx}"
LMS="$HOME/.lmstudio/bin/lms"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# --- 0. sanity -------------------------------------------------------------
if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
  echo "This setup targets Apple Silicon macOS. Aborting." >&2; exit 1
fi

# --- 1. LM Studio engine + lms CLI ----------------------------------------
if [ -x "$LMS" ]; then
  say "lms already installed ($("$LMS" version 2>/dev/null | head -1 || echo present))"
else
  say "Installing the LM Studio engine + lms CLI (no admin needed)"
  curl -fsSL https://lmstudio.ai/install.sh | sh
fi
export PATH="$HOME/.lmstudio/bin:$PATH"
lms daemon up >/dev/null 2>&1 || true

# --- 2. model --------------------------------------------------------------
if [ "${SKIP_MODEL:-0}" = "1" ]; then
  say "SKIP_MODEL=1 set; not downloading a model"
elif lms ls 2>/dev/null | grep -q "$MODEL_KEY"; then
  say "Model $MODEL_KEY already present"
else
  say "Downloading $MODEL_REPO (~16 GB). This takes a while on a slow link."
  "$HERE/scripts/hf-fast-download.sh" "$MODEL_REPO"
fi

# --- 3. VS Code extensions -------------------------------------------------
CODE=""
for c in "$(command -v code || true)" \
         "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" \
         "$HOME/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"; do
  [ -n "$c" ] && [ -x "$c" ] && { CODE="$c"; break; }
done
if [ -n "$CODE" ]; then
  say "Installing VS Code extensions"
  "$CODE" --install-extension cgaspard.lmstudio-code --force || true
  "$CODE" --install-extension saoudrizwan.claude-dev --force || true
else
  say "VS Code 'code' CLI not found. Install these two extensions by hand:"
  echo "   - cgaspard.lmstudio-code   (LM Studio Code panel)"
  echo "   - saoudrizwan.claude-dev   (Cline)"
fi

# --- 4. VS Code settings for auto-compaction ------------------------------
# The panel must be told the REAL context window LM Studio grants, or it never
# compacts before the limit and the session jams. 65536 suits a 32-36 GB Mac.
say "Writing VS Code settings for auto-compaction"
SETTINGS="$HOME/Library/Application Support/Code/User/settings.json"
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
python3 - "$SETTINGS" <<'PY'
import json,sys
p=sys.argv[1]
try: d=json.load(open(p))
except Exception: d={}
d["lmstudioCode.minContextLength"]=65536   # panel compacts ~52K, under the real limit
d["lmstudioCode.gpuOffload"]="max"
json.dump(d,open(p,"w"),indent=4)
print("updated",p)
PY

# --- 5. load + serve -------------------------------------------------------
if [ "${SKIP_MODEL:-0}" != "1" ]; then
  say "Loading $MODEL_KEY and starting the local server on http://localhost:1234"
  lms load "$MODEL_KEY" --gpu max -y >/dev/null 2>&1 || true
  lms server start >/dev/null 2>&1 || true
  lms ps 2>/dev/null | grep -i "$MODEL_KEY" || true
fi

say "Done."
cat <<EOF

Next steps:
  * Open VS Code, open the LM Studio Code panel, pick "$MODEL_KEY".
    In its model picker set "Context on load" to 64K (matches auto-compaction).
  * Or run Claude Code on the local model:  scripts/local-claude.sh
  * Or use Cline: provider "LM Studio", base URL http://localhost:1234, model $MODEL_KEY.

Read README.md for how auto-compaction works and the habits that keep it smooth.
EOF
