# Local AI in VS Code, with auto-compaction that actually works

Run a capable coding model **entirely on your own Apple Silicon Mac**, inside VS Code,
with no admin rights and no API bills. This repo packages a setup that another person
can reproduce in one command, plus the fix for the one thing that trips everyone up:
the context window filling and the session getting stuck.

Tested on an M5 Max, 36 GB. Should work on any Apple Silicon Mac with 32 GB or more.

## What you get

- **LM Studio headless engine + `lms` CLI**, installed into `~/.lmstudio` with no admin.
- **One MLX model**: Qwen 3.8 27B (4-bit, ~16 GB). All-in-one for planning, coding,
  tool use, vision, and thinking. Swap in any MLX model you like.
- **Two ways to use it in VS Code**: the LM Studio Code panel (a Claude-Code-style
  chat) and Cline. Plus Claude Code itself pointed at the local model.
- **Working auto-compaction**, so a long session summarizes itself instead of jamming.

## Install as a Claude Code plugin (recommended)

This repo is a Claude Code plugin marketplace. Inside Claude Code:

```
/plugin marketplace add romalonz/lm-studio-vscode
/plugin install lm-studio-vscode@lm-studio-vscode
```

Then just ask Claude, on your Mac: **"set up local LM Studio in VS Code."** It runs
the `setup-lmstudio-vscode` skill, walks the install interactively, and knows the
gotchas. When a session later jams or freezes, the `lmstudio-context-fix` skill
diagnoses and fixes it. There is also a `/setup-lmstudio-vscode` slash command.

## Or run it directly (no Claude Code needed)

```sh
git clone https://github.com/romalonz/lm-studio-vscode.git
cd lm-studio-vscode
./setup.sh
```

`./setup.sh` installs `lms`, downloads the model, installs the VS Code extensions,
and writes the settings that make auto-compaction fire. Flags:

```sh
SKIP_MODEL=1 ./setup.sh                       # skip the 16 GB download
MODEL_REPO=owner/repo MODEL_KEY=key ./setup.sh # use a different MLX model
```

Then open VS Code, open the **LM Studio Code** panel, pick `qwen3.8-27b-mlx`, and in
its model picker set **Context on load** to **64K**.

## Why the context window "gets stuck", and the fix

LM Studio's MLX engine fits the context window to your GPU memory. On a 36 GB Mac it
lands near **61,700 tokens** and ignores requests for more. The LM Studio Code panel,
left alone, tells its agent backend the window is 128K or 256K (what you *asked* for),
so it never compacts before the real limit. The request is then rejected and the chat
appears frozen. If the session contains an image, LM Studio cannot trim it at all and
returns a hard error.

The fix, applied by `setup.sh`, is one VS Code setting:

```jsonc
// .vscode/settings.json  (also written to your User settings)
{
    "lmstudioCode.minContextLength": 65536,  // panel compacts ~52K, safely under the real limit
    "lmstudioCode.gpuOffload": "max"
}
```

With this, the panel summarizes older turns on its own around the low-50s K and keeps
going. A compaction costs one re-read of the conversation (a minute or two on a 27B).

## Qwen "thinks too much": lower the thinking effort

Qwen 3.8 defaults to maximum reasoning effort (`xhigh`), so even simple replies crawl,
and the long thinking pass eats the output budget, which truncates answers. Measured
on an M5 Max, same trivial question:

| Thinking effort | Time to answer |
|---|---|
| default (xhigh) | 70s |
| medium | 8s |
| low | 7s |

`setup.sh` sets a sane default. To change it, edit the VS Code setting:

```jsonc
{ "lmstudioCode.defaultThinkingEffort": "medium" }  // auto | off | low | medium | high
```

Use `off` for quick edits and chat, `medium` for everyday coding, `high` only for hard
problems. It is an effort dial, not a hard thinking-token cap. Applies on the next
message.

**Two habits keep it smooth:**

1. **One task per chat.** Fewer compactions, fewer chances for a weak summary.
2. **No screenshots in a long coding session.** An image blocks LM Studio's trimming,
   which is the usual cause of a hard freeze. Keep images in short throwaway chats.

**After a compaction, work file-first.** A 27B writes a lower-fidelity summary than a
frontier model, so its memory of earlier steps can be wrong. Keep plans, state, and
results in files on disk and have the agent re-check them. That is what lets it recover.

## The three ways to use it

### 1. LM Studio Code panel (recommended)
A chat panel in VS Code's sidebar. Set "Context on load" to 64K, pick the model, go.
Auto-compaction is handled by the setting above.

### 2. Claude Code on the local model
LM Studio serves an Anthropic-compatible API, so Claude Code can run on the local model:

```sh
cd ~/your-project
/path/to/lm-studio-vscode/scripts/local-claude.sh          # interactive
/path/to/lm-studio-vscode/scripts/local-claude.sh -p "task" # one-shot
```

The launcher loads the model and tells Claude Code the *real* context window at 85% so
auto-compact fires with headroom. It has two modes:

- **lean (default):** drops MCP servers and the skills catalog so each turn stays small
  and fast.
- **`FULL=1 scripts/local-claude.sh`:** loads the whole Claude Code kit — hooks,
  plugins, skills, subagents, MCP, including any marketplaces you have installed. Same
  harness as your normal Claude Code; only the model differs. Noticeably slower on a
  27B/60K window because every skill and tool schema competes for context (a smoke test
  replied correctly in ~140s).

The first reply takes 1-2 minutes (large system prompt on a 27B); later turns reuse the
cache. Append `--dangerously-skip-permissions` yourself if you want it to act without
prompts.

**Hooks/plugins/skills/agents are harness features, not model features.** The local
model only "has" them when you run it inside Claude Code (`FULL=1`). The LM Studio Code
panel and Cline give a lighter kit: MCP servers plus an instructions file, not Claude
Code's skills/hooks/plugins/subagents.

### Operator profile (stop the hedging)

`profiles/AGENTS.md` is a short system prompt that makes the model direct and
action-first for your own work, without stripping its safety. Copy it into the workspace
you open in VS Code (the panel and Claude Code both read `AGENTS.md`/`CLAUDE.md`), or
paste it into Cline's Custom Instructions. See the `qwen-operator-profile` skill. It is
not a jailbreak: this project does not remove a model's safety training or ship a
no-safety model.

### 3. Cline
Provider "LM Studio", base URL `http://localhost:1234`, model `qwen3.8-27b-mlx`.
Cline's Auto-approve settings control the prompts.

## Everyday `lms` commands

```sh
lms daemon up          # start the background engine (once per login)
lms ls                 # list downloaded models
lms load qwen3.8-27b-mlx --gpu max
lms ps                 # what is loaded
lms chat               # terminal chat (text only, no tools/images)
lms server start       # OpenAI + Anthropic compatible API on :1234
lms unload --all       # free the RAM
```

## Adding another model

The included downloader saturates a slow link with many parallel connections and
verifies every shard's SHA-256, then drops the model where LM Studio sees it:

```sh
scripts/hf-fast-download.sh lmstudio-community/Mistral-Small-3.2-24B-Instruct-2506-MLX-4bit
lms ls
```

## Sizing on a 32-36 GB Mac

| Quant | 24B | 27B | Verdict |
|---|---|---|---|
| 4-bit | 14 GB | 16 GB | comfortable, room for context |
| 6-bit | 20 GB | 22 GB | fine, keep context moderate |
| 8-bit | 25 GB | 29 GB | avoid, swaps once context grows |

Stick to 4-bit MLX on 36 GB. It leaves room for the context window and other apps.

## What's in here

```
setup.sh                   one-shot installer
.vscode/settings.json      the auto-compaction settings (also written to User settings)
scripts/local-claude.sh    run Claude Code on the local model
scripts/hf-fast-download.sh parallel, verified model downloader
scripts/chat.py            minimal Python chat client (stdlib only)
scripts/chat.sh            one-shot curl prompt
```

## License

MIT. No warranty; it configures your machine, so read `setup.sh` before running it.
