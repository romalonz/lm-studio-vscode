#!/bin/bash
# Watchdog for the on-demand mlx-serve. Uses GET /health (does NOT load/swap a model)
# so it never disturbs the current session. /health is served on the same thread, so a
# deadlocked inference also blocks it -> detects true hangs. 3 stuck checks -> restart.
export PATH="$HOME/.lmstudio/bin:$PATH"; LOG="$HOME/.lmstudio/mlx-watchdog.log"; fails=0
while true; do
  if curl -s -m 90 http://127.0.0.1:1234/health >/dev/null 2>&1; then fails=0
  else
    fails=$((fails+1)); echo "$(date '+%F %T') /health failed ($fails)" >> "$LOG"
    if [ "$fails" -ge 3 ]; then
      echo "$(date '+%F %T') server hung -> restart" >> "$LOG"; pkill -f mlx-serve.py; fails=0; sleep 25
    fi
  fi
  sleep 60
done
