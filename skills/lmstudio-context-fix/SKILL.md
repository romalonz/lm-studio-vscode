---
name: lmstudio-context-fix
description: Diagnose and fix a local LM Studio session in VS Code that jams, freezes, or errors as the context window fills, and make auto-compaction work. Covers the "context overflow" / "TruncateMiddle not supported for prompts with images" error, the LM Studio Code panel getting stuck near 60K, recovering a dead panel, and the habits that keep a local 27B session smooth. Use when a local LM Studio coding session stops responding, errors on long context, or when setting up reliable auto-compaction.
metadata:
  origin: lm-studio-vscode
---

# Fix LM Studio context jams and make auto-compaction work

Field-tested on an M5 Max, 36 GB, with `qwen3.8-27b-mlx` in the LM Studio Code
VS Code panel. The root cause and fixes below are the payoff of this plugin.

## The root cause

LM Studio's MLX engine fits the context window to Metal's recommended working set,
not to the number you request. On a 36 GB Mac a 27B 4-bit model lands at about
**61,700 tokens** and silently ignores larger requests (`lms load -c 131072` still
loads 61,696; confirm with `lms ps` or the REST field
`GET http://localhost:1234/api/v1/models` -> `loaded_instances[].config.context_length`).
Raising it needs `sysctl iogpu.wired_limit_mb`, which requires admin.

So any client that thinks the window is 128K/256K will let the conversation grow
past the real limit, and then break.

## Symptom 1: panel gets stuck / "context overflow" near 60K

The LM Studio Code panel passes the *requested* context to its OpenCode backend, so
it never compacts before LM Studio's real limit and the request is rejected.

**Fix:** tell the panel the real window. In VS Code settings.json:

```jsonc
{ "lmstudioCode.minContextLength": 65536, "lmstudioCode.gpuOffload": "max" }
```

Now it auto-compacts around the low-50s K. Also set the model picker's
"Context on load" to 64K (not Max) and Eject/Load so it applies. Verify the fix by
watching the token meter cross ~50K on a long task and drop with "Compacting…".

## Symptom 2: hard error with an image in the session

Exact text:

```
Context overflow policy error: TruncateMiddle context overflow policy is not
currently supported for prompts with images.
```

LM Studio cannot trim a conversation that contains an image, so once such a session
grows past the window it errors instead of shortening, and it keeps erroring on
every send to that session. **You cannot rescue that session** — start a new one.
Prevention: keep screenshots in short throwaway chats; do long coding text-only.

## Symptom 3: the panel/chat won't open at all

The panel extension can get removed or crash (e.g. after the image error above).
Check and reinstall:

```sh
ls ~/.vscode/extensions | grep -i lmstudio-code   # is cgaspard.lmstudio-code present?
"/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" \
  --install-extension cgaspard.lmstudio-code --force
```

Its sessions are not persisted to a file you must clear; a fresh install opens a
clean chat. Confirm the model server is up: `lms server start`, then
`curl -s http://localhost:1234/v1/models`.

## Claude Code on the local model

Use `scripts/local-claude.sh`. It reads the *real* loaded window from LM Studio and
sets `CLAUDE_CODE_MAX_CONTEXT_TOKENS` to 85% of it, so Claude Code's own auto-compact
fires with room for the summary. It also drops MCP servers and the skills catalog
(`--strict-mcp-config --mcp-config '{"mcpServers":{}}' --disable-slash-commands`)
so the fixed part of every turn stays small.

## Symptom 4: replies are very slow, or cut off mid-sentence

Two causes, often together:

1. **Thinking effort too high.** Qwen 3.8 defaults to `xhigh` reasoning, so it thinks
   for a long time before writing, and that reasoning counts against the output
   budget, so long answers get truncated ("Response was cut off — it reached the
   output token limit"). Measured on an M5 Max, same trivial prompt: default 70s vs
   `medium` 8s vs `low` 7s, all correct. Fix with the panel setting:

   ```jsonc
   { "lmstudioCode.defaultThinkingEffort": "medium" }
   ```

   Values `auto`/`off`/`low`/`medium`/`high`. Use `off` for quick edits, `medium` for
   everyday coding, `high` only for hard problems. It is an effort dial, not a hard
   thinking-token cap.
2. **A genuinely long single answer.** Reply "continue" to resume from the cut point,
   or ask for less at once ("under 300 words", "just the code"). Lower thinking effort
   also frees budget for the actual answer.

## The habit that matters most: work file-first

Compaction on a 27B produces a **lower-fidelity summary** than a frontier model. In
testing, after a compaction the model claimed "25 files" when there were 10 and cited
wrong line numbers. It recovered only because the real answers were in files on disk
and it re-read them. So:

- After you see "Compacting…", do not trust the model's memory of earlier steps.
  Have it re-verify against the actual files, configs, or command output.
- Keep plans, state, and results in files, not only in the chat.
- One task per chat, so compaction happens rarely.

## Don't chase 128K on this hardware

GGUF via LM Studio's llama.cpp engine has no context auto-fit cap, but measured
9.7 tok/s vs ~24 tok/s on MLX and ~32 GB at 128K on a 36 GB Mac. Not worth it. Stay
on MLX at ~60K and rely on compaction plus file-first working.
