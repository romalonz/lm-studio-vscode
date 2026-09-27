#!/bin/bash
# Health watchdog for mlx-serve. mlx_lm.server is single-threaded: if one request
# ever hangs, every later request queues behind it and times out (looks like the
# whole model died). This pings the server; if it's unresponsive for ~2 min straight,
# it kills mlx-serve so the KeepAlive LaunchAgent relaunches it clean. Self-healing.
export PATH="$HOME/.lmstudio/bin:$PATH"
LOG="$HOME/.lmstudio/mlx-watchdog.log"
fails=0
while true; do
  if curl -s -m 60 http://127.0.0.1:1234/v1/models >/dev/null 2>&1; then
    fails=0
  else
    fails=$((fails+1))
    echo "$(date '+%F %T') health check failed ($fails)" >> "$LOG"
    if [ "$fails" -ge 2 ]; then
      echo "$(date '+%F %T') server unresponsive ~2min -> restarting mlx-serve" >> "$LOG"
      pkill -f mlx-serve.py
      fails=0
      sleep 20   # give KeepAlive time to relaunch + load before next check
    fi
  fi
  sleep 45
done
