#!/usr/bin/env bash
# Usage: lock.sh acquire|release|who|alive|move <resource> [owner [new-owner]]
# Generic lock for shared resources: checkout:<path>, deploy:<env>, port:<n>, account:<key>, slot:<path>.
# Locks live in ${AGENT_LOCK_DIR:-$HOME/.agent-workflow/locks} (mkdir-atomic, files pid+owner).
# The recorded pid is AGENT_LOCK_PID (default $PPID): set it to the caller's long-lived
# process; the lock counts as free once that pid is dead (kill -0).
# Exit: 0 ok; 1 held by someone else (stdout = owner); 2 usage.
cmd=${1:-} res=${2:-} owner=${3:-} to=${4:-}
base=${AGENT_LOCK_DIR:-$HOME/.agent-workflow/locks}
[ -n "$res" ] || { echo "usage: $0 acquire|release|who|move <resource> [owner [new-owner]]" >&2; exit 2; }
# percent-encode %, / and : so distinct resources never share a dir
d="$base/$(printf '%s' "$res" | sed 's/%/%25/g; s#/#%2F#g; s/:/%3A/g')"
cur() { cat "$d/owner" 2>/dev/null; }
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }  # GNU, then BSD/macOS
case $cmd in
  acquire)
    [ -n "$owner" ] || { echo "acquire butuh owner" >&2; exit 2; }
    mkdir -p "$base"
    for _ in 1 2; do
      if mkdir "$d" 2>/dev/null; then
        echo "${AGENT_LOCK_PID:-$PPID}" > "$d/pid"; echo "$owner" > "$d/owner"; exit 0
      fi
      if [ "$(cur)" = "$owner" ]; then echo "${AGENT_LOCK_PID:-$PPID}" > "$d/pid"; exit 0; fi
      pid=$(cat "$d/pid" 2>/dev/null)
      # empty pid = holder mid-acquire (or crashed): held only while the dir is <10s old
      if [ -z "$pid" ]; then
        [ $(( $(date +%s) - $(mtime "$d") )) -lt 10 ] && { cur; exit 1; }
      elif kill -0 "$pid" 2>/dev/null; then cur; exit 1; fi
      rm -rf "$d"   # stale: reclaim (small race between two reclaimers accepted)
    done
    cur; exit 1 ;;
  release) [ "$(cur)" = "$owner" ] && rm -rf "$d"; exit 0 ;;
  who) cur ;;
  alive) p=$(cat "$d/pid" 2>/dev/null); [ -n "$p" ] && kill -0 "$p" 2>/dev/null ;;  # exit 0 = held by a live pid
  # move: owner=from, to=new owner; pid first so the lock is never free or half-owned
  move) [ -n "$owner" ] && [ -n "$to" ] && [ "$(cur)" = "$owner" ] && echo "${AGENT_LOCK_PID:-$PPID}" > "$d/pid" && echo "$to" > "$d/owner" && exit 0
        cur; exit 1 ;;
  *) echo "usage: $0 acquire|release|who|move <resource> [owner [new-owner]]" >&2; exit 2 ;;
esac
