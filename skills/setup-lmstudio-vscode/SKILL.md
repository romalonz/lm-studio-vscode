---
name: setup-lmstudio-vscode
description: Set up a fully local coding model in VS Code on an Apple Silicon Mac using LM Studio's MLX engine, with auto-compaction configured so long sessions do not jam. Installs the lms CLI (no admin), downloads an MLX model, installs the LM Studio Code and Cline extensions, and writes the VS Code settings that make the context window behave. Use when the user wants local/offline AI coding in VS Code, an LM Studio + VS Code setup, or a private on-device coding assistant on a Mac.
metadata:
  origin: lm-studio-vscode
---

# Set up LM Studio + VS Code (local coding model, working auto-compaction)

Guide the user through this interactively. Confirm before the big download and
before loading a model, since it may run on a memory-constrained machine. The
scripts referenced live at `${CLAUDE_PLUGIN_ROOT}` (this plugin's root).

## When this applies

Apple Silicon Mac (M-series), ideally 32 GB unified memory or more. On less than
24 GB, steer the user to a smaller model (a 12-14B MLX 4-bit) instead of the 27B.

## Step 0: Check the machine

- `uname -m` must be `arm64`. If not, stop — this setup is Apple-Silicon only.
- `sysctl -n hw.memsize | awk '{print $1/1073741824" GB"}'` — note the RAM.
- `sw_vers -productVersion` — macOS version.
- Is VS Code installed? Look for `/Applications/Visual Studio Code.app`.

## Step 1: Install the LM Studio engine + `lms` CLI (no admin)

If `~/.lmstudio/bin/lms` is absent:

```sh
curl -fsSL https://lmstudio.ai/install.sh | sh
```

This installs the headless `llmster` engine and the `lms` CLI into `~/.lmstudio`
and adds it to PATH. No admin rights are needed. Then `lms daemon up`.

Explain: this is the headless engine, not the LM Studio desktop app. The desktop
app is a separate `.dmg` and is not required.

## Step 2: Download one MLX model

Downloads over `lms get` are single-connection and slow. Use the bundled parallel
downloader, which fills the link, verifies each shard's SHA-256, drops the model
where LM Studio sees it, and resumes if re-run:

```sh
"${CLAUDE_PLUGIN_ROOT}/scripts/hf-fast-download.sh" lmstudio-community/Qwen3.8-27B-MLX-4bit
```

Default pick: `lmstudio-community/Qwen3.8-27B-MLX-4bit` (~16 GB), an all-in-one for
planning, coding, tool use, vision, and thinking. Confirm the download with the
user first; it is large and can take 20+ minutes on a slow link. For <24 GB RAM,
use a 12-14B MLX 4-bit repo instead.

## Step 3: Install the VS Code extensions

Find the `code` CLI (`command -v code`, else
`/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code`), then:

```sh
code --install-extension cgaspard.lmstudio-code --force   # the LM Studio Code chat panel
code --install-extension saoudrizwan.claude-dev --force   # Cline (optional)
```

## Step 4: Write the auto-compaction setting (the crucial part)

LM Studio's MLX engine fits the context window to GPU memory (about 61,700 tokens
on a 36 GB Mac) and ignores requests for more. The LM Studio Code panel, left
alone, believes the window is whatever it asked for (128K/256K), so it never
compacts before the real limit and the session jams. Fix it by telling the panel
the real size. Edit the user's VS Code settings.json
(`~/Library/Application Support/Code/User/settings.json`), backing it up first:

```jsonc
{
    "lmstudioCode.minContextLength": 65536,
    "lmstudioCode.gpuOffload": "max"
}
```

65536 makes the panel compact around the low-50s K, safely under the real limit.
On a machine with much more or less RAM, set this near the window LM Studio actually
grants (see `lms ps`, or the panel's model picker after loading).

## Step 5: Load, serve, verify

```sh
lms load qwen3.8-27b-mlx --gpu max -y
lms server start                      # OpenAI + Anthropic API on http://localhost:1234
lms ps                                # confirm loaded, note the context length
```

## Step 6: Show the user the three ways to use it

1. **LM Studio Code panel** — open it, pick the model, set "Context on load" to a
   value at or below the real window (64K here), start a task.
2. **Claude Code on the local model** — `"${CLAUDE_PLUGIN_ROOT}/scripts/local-claude.sh"`
   from a project folder. It loads the model, tells Claude Code the real window at
   85% for compaction headroom, and trims MCP/skills to keep turns small.
3. **Cline** — provider "LM Studio", base URL `http://localhost:1234`, the model key.

## One-shot alternative

Everything above is also in `"${CLAUDE_PLUGIN_ROOT}/setup.sh"`. Offer it if the user
prefers one command, but walk through what it does first (it downloads ~16 GB and
edits their VS Code settings).

## After setup

Point the user at the [[lmstudio-context-fix]] skill for the habits that keep it
smooth (one task per chat, no screenshots in long sessions, work file-first after a
compaction) and for recovering a jammed panel.
