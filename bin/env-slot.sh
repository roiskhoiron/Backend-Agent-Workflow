#!/usr/bin/env bash
# Usage: env-slot.sh acquire <worktree> <owner>   -> prints the slot's env lines (KEY=value), exit 0
#        env-slot.sh show <worktree>              -> same lines for a slot already held, exit 1 if none
#        env-slot.sh release <worktree> <owner>   -> frees the slot (container: test-db.sh down first)
#        env-slot.sh list                         -> one line per slot: n <TAB> owner <TAB> worktree
# One slot per worktree = its own service port range + test database, so parallel agents never collide.
# Slot n (1..SLOT_MAX) owns ports SLOT_BASE_PORT + n*10 .. +9: APP_PORT = +0, DB_PORT = +1, the rest spare.
# The slot is a lock (lock.sh, resource slot:<n>) held by AGENT_LOCK_PID (default $PPID): free once that pid dies.
# Exit: 0 ok; 1 no free slot / none held; 2 usage.
# Env: SLOT_BASE_PORT (default 18000), SLOT_MAX (default 50), AGENT_WORKFLOW_STATE, AGENT_LOCK_DIR, AGENT_LOCK_PID.
cmd=${1:-} wt=${2:-} owner=${3:-}
LOCK="$(dirname "$0")/lock.sh"
STATE=${AGENT_WORKFLOW_STATE:-$HOME/.agent-workflow}/slots
BASE=${SLOT_BASE_PORT:-18000} MAX=${SLOT_MAX:-50}
export AGENT_LOCK_PID=${AGENT_LOCK_PID:-$PPID}
usage() { echo "usage: $0 acquire <worktree> <owner> | show <worktree> | release <worktree> <owner> | list" >&2; exit 2; }

real() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
port_busy() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
slug() { basename "$1" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'; }
emit() { # n worktree
  local n=$1 s; s=$(slug "$2")
  printf 'SLOT=%s\nWORKTREE=%s\nAPP_PORT=%s\nDB_PORT=%s\nSPARE_PORTS=%s-%s\nDB_NAME=%s\nDB_CONTAINER=agentdb-%s\nCOMPOSE_PROJECT_NAME=agent-%s\n' \
    "$n" "$2" $((BASE + n*10)) $((BASE + n*10 + 1)) $((BASE + n*10 + 2)) $((BASE + n*10 + 9)) \
    "agent_$(printf '%s' "$s" | tr '-' '_')" "$s" "$s"
}
# slot number held for this worktree by a live lock, else empty
held() {
  local f n
  for f in "$STATE"/*.wt; do
    [ -e "$f" ] || continue
    [ "$(cat "$f")" = "$1" ] || continue
    n=$(basename "$f" .wt)
    "$LOCK" alive "slot:$n" || { rm -f "$f"; continue; }   # holder died: mapping is stale
    echo "$n"; return 0
  done
}

case $cmd in
  acquire)
    [ -n "$wt" ] && [ -n "$owner" ] || usage
    [ -d "$wt" ] || { echo "worktree tidak ada: $wt" >&2; exit 2; }
    wt=$(real "$wt"); mkdir -p "$STATE"
    n=$(held "$wt")
    if [ -n "$n" ]; then
      "$LOCK" acquire "slot:$n" "$owner" >/dev/null || { echo "slot $n untuk $wt dipegang $("$LOCK" who "slot:$n")" >&2; exit 1; }
      emit "$n" "$wt"; exit 0
    fi
    for ((n = 1; n <= MAX; n++)); do
      port_busy $((BASE + n*10)) && continue
      port_busy $((BASE + n*10 + 1)) && continue
      "$LOCK" acquire "slot:$n" "$owner" >/dev/null || continue
      echo "$wt" > "$STATE/$n.wt"
      emit "$n" "$wt"; exit 0
    done
    echo "tidak ada slot bebas (1..$MAX): tunggu atau lepas slot worktree lain" >&2; exit 1 ;;
  show)
    [ -n "$wt" ] || usage
    wt=$(real "$wt"); n=$(held "$wt"); [ -n "$n" ] || exit 1
    emit "$n" "$wt" ;;
  release)
    [ -n "$wt" ] && [ -n "$owner" ] || usage
    wt=$(real "$wt"); n=$(held "$wt"); [ -n "$n" ] || exit 0
    [ "$("$LOCK" who "slot:$n")" = "$owner" ] || { echo "slot $n dipegang $("$LOCK" who "slot:$n"), bukan $owner" >&2; exit 1; }
    "$LOCK" release "slot:$n" "$owner"; rm -f "$STATE/$n.wt" ;;
  list)
    for f in "$STATE"/*.wt; do
      [ -e "$f" ] || continue
      n=$(basename "$f" .wt); o=$("$LOCK" who "slot:$n")
      "$LOCK" alive "slot:$n" && printf '%s\t%s\t%s\n' "$n" "$o" "$(cat "$f")"
    done | sort -n ;;
  *) usage ;;
esac
