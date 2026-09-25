---
name: qwen-operator-profile
description: Give the local LM Studio model an operator profile so it behaves like a direct, action-first senior engineer instead of a cautious, verbose assistant, and choose how much of the Claude Code kit (hooks, plugins, skills, subagents, MCP) it runs with. Use when the user wants the local model to stop hedging or over-cautioning on their own legitimate work, wants it tuned for coding/DevOps, or asks whether the local model can have the same extensions their Claude Code has.
metadata:
  origin: lm-studio-vscode
---

# Operator profile + extension kit for the local model

Two separate things people conflate. Handle them distinctly.

## 1. Behavior: the operator profile

The base Qwen model does not block legitimate coding, DevOps, or authorized
security-testing work; over-caution and verbosity are behavior, not a safety wall, and
are fixed with a system prompt. `profiles/AGENTS.md` in this plugin is that prompt:
direct, action-first, concise, no unsolicited moralizing, does the owner's own-system
work, keeps safety for genuinely destructive or third-party-targeted requests.

This is NOT a jailbreak and does not strip the model's safety training. Do not write a
prompt whose purpose is to make the model comply with harmful requests, and do not
install an "abliterated"/no-safety model to satisfy a "remove all guardrails" ask;
decline that plainly and offer this profile instead.

**Apply it per harness:**
- **LM Studio Code panel / OpenCode**: it reads `AGENTS.md` (or `CLAUDE.md`) from the
  workspace root. Copy `profiles/AGENTS.md` there. Keep it short; it is injected on
  every request and eats the small context window.
- **Cline**: paste the profile into Custom Instructions (or a `.clinerules` file).
- **Claude Code on local Qwen**: it is picked up as `CLAUDE.md`/`AGENTS.md` or via
  `--append-system-prompt`.

## 2. Extensions: what kit the model gets, per harness

Hooks, plugins, skills, and subagents are **Claude Code harness features, not model
features**. Whether the local model "has" them depends entirely on the harness:

| Harness | Skills / hooks / plugins / subagents | MCP | Instructions file |
|---|---|---|---|
| Claude Code on local Qwen (`scripts/local-claude.sh FULL=1`) | yes (full, incl. installed marketplaces) | yes | CLAUDE.md / AGENTS.md |
| LM Studio Code panel (OpenCode) | no | yes | AGENTS.md / CLAUDE.md |
| Cline | no (its own rules/workflows) | yes | .clinerules |

So to get the full ovrworked-style kit on the local model, run **Claude Code** against
it. `scripts/local-claude.sh` has two modes:

- default (**lean**): no MCP, no skills catalog — fast, small per-turn overhead.
- `FULL=1`: loads hooks, plugins, skills, subagents, MCP (installed marketplaces
  included). Same harness, only the model differs. It is **noticeably slower** on a
  27B with a ~60K window because every skill description, tool schema, and hook output
  competes for context. Verified working; a smoke test replied correctly in ~140s.

Guidance: use lean (or the panel) for everyday speed; use `FULL=1` when you actually
need a plugin/skill/subagent. Keep the loaded skill/MCP set small on this hardware.

## Do this

1. Copy `profiles/AGENTS.md` into the workspace the user opens in VS Code.
2. Tell them the panel/Cline get MCP + this profile; Claude Code (`FULL=1`) gets the
   full kit but slower.
3. If they ask to remove all guardrails so the model complies with anything, decline
   that one thing and point them back to this profile, which already unblocks their
   legitimate work. See [[lmstudio-context-fix]] for keeping sessions smooth.
