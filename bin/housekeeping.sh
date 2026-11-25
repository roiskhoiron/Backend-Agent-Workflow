#!/usr/bin/env bash
# Usage: housekeeping.sh            (cron/launchd, e.g. hourly; see docs/alat.md)
# Removes what parallel backend agents leave behind, without touching anything of the user's:
#   1. test DB containers (label agent-workflow=1) whose worktree is gone or whose slot is no longer held;
#   2. dangling images;
#   3. build cache older than HK_CACHE_DAYS (default 7), skipped while a docker build runs.
# Containers/volumes without the agent-workflow label are never touched.
# Log: ~/.agent-workflow/logs/housekeeping.log. Exit 0, or 1 when a step failed (logged).
# Overrides (tests): DOCKER, HK_CACHE_DAYS, AGENT_WORKFLOW_STATE, AGENT_LOCK_DIR
set -u
[ -n "${HOME:-}" ] || { echo "housekeeping: HOME is empty" >&2; exit 1; }
DOCKER=${DOCKER:-docker}
BIN=$(cd "$(dirname "$0")" && pwd -P)
LOG=${AGENT_WORKFLOW_STATE:-$HOME/.agent-workflow}/logs/housekeeping.log
mkdir -p "$(dirname "$LOG")"
FAILS=0
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
fail() { log "ERROR $*"; FAILS=$((FAILS + 1)); }

command -v "$DOCKER" >/dev/null 2>&1 || { log "docker tidak ada, lewati"; exit 0; }
"$DOCKER" info >/dev/null 2>&1 || { log "docker daemon tidak jalan, lewati"; exit 0; }

# 1. orphan test DB containers
while IFS=$'\t' read -r name wt; do
  [ -n "$name" ] || continue
  case $name in agentdb-*) ;; *) continue;; esac   # label alone is not enough: name must be ours too
  if [ -n "$wt" ] && [ -d "$wt" ] && "$BIN/env-slot.sh" show "$wt" >/dev/null 2>&1; then continue; fi
  if "$DOCKER" rm -f "$name" >/dev/null 2>&1; then log "hapus container $name (worktree ${wt:-?} tidak punya slot aktif)"
  else fail "gagal hapus container $name"; fi
done < <("$DOCKER" ps -a --filter label=agent-workflow=1 --format '{{.Names}}	{{.Label "agent-workflow.worktree"}}' 2>/dev/null)

# 2. dangling images
"$DOCKER" image prune -f >/dev/null 2>&1 && log "image prune (dangling)" || fail "image prune"

# 3. old build cache, not while a build runs
if pgrep -f 'docker(-buildx)? (buildx )?build|docker compose .*build' >/dev/null 2>&1; then
  log "build berjalan, cache build tidak dibersihkan"
else
  "$DOCKER" builder prune -f --filter "until=$(( ${HK_CACHE_DAYS:-7} * 24 ))h" >/dev/null 2>&1 && log "builder prune > ${HK_CACHE_DAYS:-7} hari" || fail "builder prune"
fi
[ "$FAILS" -eq 0 ]
