#!/usr/bin/env bash
# Usage: test-db.sh up <worktree> <postgres|mysql|mariadb|mongo> [image]  -> start the slot's test DB, print env lines
#        test-db.sh down <worktree>                                       -> remove the slot's test DB container
#        test-db.sh status <worktree>                                     -> running|stopped|absent (exit 0|1|1)
# The test DB is a throwaway container per worktree (data on tmpfs, nothing to clean), named
# agentdb-<worktree slug>, published on the slot's DB_PORT (env-slot.sh acquire first).
# Credentials are fixed local test values (agent/agent), never real ones: the container lives only on 127.0.0.1.
# Exit: 0 ok; 1 not ready / no slot; 2 usage. Env: DOCKER (default docker), TESTDB_WAIT (s, default 60).
cmd=${1:-} wt=${2:-} engine=${3:-} image=${4:-}
DOCKER=${DOCKER:-docker}
usage() { echo "usage: $0 up <worktree> <postgres|mysql|mariadb|mongo> [image] | down <worktree> | status <worktree>" >&2; exit 2; }
[ -n "$wt" ] || usage
slot=$("$(dirname "$0")/env-slot.sh" show "$wt") || { echo "worktree belum punya slot: jalankan env-slot.sh acquire dulu" >&2; exit 1; }
val() { printf '%s\n' "$slot" | sed -n "s/^$1=//p"; }
NAME=$(val DB_CONTAINER) PORT=$(val DB_PORT) DB=$(val DB_NAME)
state() { "$DOCKER" inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null; }

case $cmd in
  up)
    case $engine in
      postgres) img=${image:-postgres:16-alpine} inner=5432 data=/var/lib/postgresql/data
                envs=(-e POSTGRES_USER=agent -e POSTGRES_PASSWORD=agent -e "POSTGRES_DB=$DB")
                ready=(pg_isready -U agent -d "$DB") url="postgresql://agent:agent@127.0.0.1:$PORT/$DB" ;;
      mysql|mariadb)
                [ "$engine" = mysql ] && img=${image:-mysql:8.4} || img=${image:-mariadb:11}
                inner=3306 data=/var/lib/mysql
                envs=(-e MYSQL_ROOT_PASSWORD=agent -e MYSQL_USER=agent -e MYSQL_PASSWORD=agent -e "MYSQL_DATABASE=$DB"
                      -e MARIADB_ROOT_PASSWORD=agent -e MARIADB_USER=agent -e MARIADB_PASSWORD=agent -e "MARIADB_DATABASE=$DB")
                # mariadb images ship mariadb-admin; mysql images ship mysqladmin
                ready=(sh -c 'mysqladmin ping -h127.0.0.1 -uagent -pagent --silent 2>/dev/null || mariadb-admin ping -h127.0.0.1 -uagent -pagent --silent')
                url="mysql://agent:agent@127.0.0.1:$PORT/$DB" ;;
      mongo)    img=${image:-mongo:7} inner=27017 data=/data/db envs=()
                ready=(mongosh --quiet --eval 'db.runCommand({ping:1}).ok') url="mongodb://127.0.0.1:$PORT/$DB" ;;
      *) usage ;;
    esac
    # existing container on another port (slot changed) or another image -> recreate
    if [ -n "$(state)" ]; then
      have=$("$DOCKER" inspect -f '{{.Config.Image}} {{(index (index .HostConfig.PortBindings "'"$inner"'/tcp") 0).HostPort}}' "$NAME" 2>/dev/null)
      [ "$have" = "$img $PORT" ] || "$DOCKER" rm -f "$NAME" >/dev/null
    fi
    case $(state) in
      true) ;;
      false) "$DOCKER" start "$NAME" >/dev/null || exit 1 ;;
      *) "$DOCKER" run -d --name "$NAME" --label agent-workflow=1 --label "agent-workflow.worktree=$wt" \
           -p "127.0.0.1:$PORT:$inner" --tmpfs "$data" "${envs[@]}" "$img" >/dev/null || exit 1 ;;
    esac
    for ((i = 0; i < ${TESTDB_WAIT:-60}; i++)); do
      if "$DOCKER" exec "$NAME" "${ready[@]}" >/dev/null 2>&1; then
        printf 'DB_ENGINE=%s\nDB_CONTAINER=%s\nDB_PORT=%s\nDB_NAME=%s\nDATABASE_URL=%s\n' "$engine" "$NAME" "$PORT" "$DB" "$url"
        exit 0
      fi
      sleep 1
    done
    echo "database uji $NAME belum siap setelah ${TESTDB_WAIT:-60} detik (cek: $DOCKER logs $NAME)" >&2; exit 1 ;;
  down) "$DOCKER" rm -f "$NAME" >/dev/null 2>&1; exit 0 ;;
  status) case $(state) in true) echo running;; false) echo stopped; exit 1;; *) echo absent; exit 1;; esac ;;
  *) usage ;;
esac
