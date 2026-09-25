---
description: Set up a fully local coding model in VS Code on an Apple Silicon Mac (LM Studio MLX engine, no admin), with auto-compaction configured so long sessions do not jam.
---

# Set up LM Studio + VS Code

Invoke the `setup-lmstudio-vscode` skill and walk the user through it interactively.

Confirm before the ~16 GB model download and before editing their VS Code settings.
On a Mac with less than 24 GB of memory, recommend a smaller model (a 12-14B MLX
4-bit) instead of the 27B default.

After setup, mention the `lmstudio-context-fix` skill for keeping sessions smooth and
recovering a jammed panel.
