#!/bin/bash
# Fast Hugging Face repo download using many parallel HTTP range requests.
# Why: on this network each connection is capped around 3 MB/s, but 32+ connections
# reach 80+ MB/s. `lms get` and `hf download` use few connections and crawl.
#
# Usage: hf-fast-download.sh <owner/repo> [dest-dir] [connections]
#   dest-dir defaults to ~/.lmstudio/models/<owner/repo> so LM Studio sees the model.
# Verifies every large file's size and SHA-256 against Hugging Face's metadata.
# Safe to re-run: complete files are skipped.
set -u
REPO="$1"
DEST="${2:-$HOME/.lmstudio/models/$REPO}"
N="${3:-40}"
BIG=$((64*1024*1024))     # files above 64 MB are split into $N ranges
mkdir -p "$DEST"
TMP="$DEST/.parts"; mkdir -p "$TMP"

log() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*"; }

# file list: "size<TAB>name"
FILES=$(curl -sfL "https://huggingface.co/api/models/$REPO?blobs=true" | python3 -c '
import json,sys
for s in json.load(sys.stdin)["siblings"]:
    print("%d\t%s" % (s.get("size",0), s["rfilename"]))') || { log "cannot read repo listing for $REPO"; exit 1; }

fail=0
while IFS=$'\t' read -r size name; do
  [ -z "$name" ] && continue
  out="$DEST/$name"; mkdir -p "$(dirname "$out")"
  url="https://huggingface.co/$REPO/resolve/main/$name"
  if [ -f "$out" ] && [ "$(stat -f %z "$out")" = "$size" ]; then log "skip (complete) $name"; continue; fi

  if [ "$size" -lt "$BIG" ]; then
    curl -sfL --retry 3 -o "$out" "$url" && log "ok    $name ($size B)" || { log "FAIL  $name"; fail=1; }
    continue
  fi

  # resolve the CDN URL once, and fetch the expected sha256 from x-linked-etag
  hdr=$(curl -sIL "$url")
  cdn=$(printf '%s' "$hdr" | grep -i '^location:' | tail -1 | awk '{print $2}' | tr -d '\r'); [ -z "$cdn" ] && cdn="$url"
  sha=$(printf '%s' "$hdr" | grep -i '^x-linked-etag:' | tail -1 | tr -d '\r"' | awk '{print $2}')
  part=$(( (size + N - 1) / N ))
  log "start $name ($((size/1000000)) MB, $N connections)"
  t0=$(date +%s)
  for i in $(seq 0 $((N-1))); do
    s=$((i*part)); e=$((s+part-1)); [ "$e" -ge "$size" ] && e=$((size-1))
    [ "$s" -gt "$e" ] && continue
    want=$((e-s+1)); p="$TMP/$(basename "$name").$i"
    ( for try in 1 2 3 4; do
        curl -sf --retry 2 -r "$s-$e" -o "$p" "$cdn" && [ "$(stat -f %z "$p" 2>/dev/null || echo 0)" = "$want" ] && exit 0
        rm -f "$p"; sleep 2
      done; echo "part $i failed" >&2; exit 1 ) &
  done
  wait
  # assemble in order
  : > "$out.tmp"
  ok=1
  for i in $(seq 0 $((N-1))); do
    p="$TMP/$(basename "$name").$i"; [ -f "$p" ] || { [ $((i*part)) -ge "$size" ] && continue; ok=0; break; }
    cat "$p" >> "$out.tmp" && rm -f "$p"
  done
  got=$(stat -f %z "$out.tmp" 2>/dev/null || echo 0)
  if [ "$ok" = 1 ] && [ "$got" = "$size" ]; then
    if [ -n "$sha" ]; then
      calc=$(shasum -a 256 "$out.tmp" | awk '{print $1}')
      if [ "$calc" != "$sha" ]; then log "FAIL  $name sha256 mismatch"; rm -f "$out.tmp"; fail=1; continue; fi
    fi
    mv "$out.tmp" "$out"
    t1=$(date +%s); log "ok    $name  $(( size/1000000/((t1-t0)>0?(t1-t0):1) )) MB/s, sha256 verified"
  else
    log "FAIL  $name (got $got of $size bytes)"; rm -f "$out.tmp"; fail=1
  fi
done <<< "$FILES"
rmdir "$TMP" 2>/dev/null
[ "$fail" = 0 ] && log "DONE  $REPO -> $DEST ($(du -sh "$DEST" | cut -f1))" || log "FINISHED WITH ERRORS  $REPO"
exit $fail
