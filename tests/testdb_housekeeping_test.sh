#!/usr/bin/env bash
# test-db.sh + housekeeping.sh against a fake docker (records calls, keeps container state in files)
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
TD="$REPO/bin/test-db.sh" S="$REPO/bin/env-slot.sh" HK="$REPO/bin/housekeeping.sh"
T=$(mktemp -d)
sleep 300 & LIVE=$!
trap 'kill $LIVE 2>/dev/null; rm -rf "$T"' EXIT
export AGENT_LOCK_DIR="$T/locks" AGENT_WORKFLOW_STATE="$T/st" SLOT_BASE_PORT=$((20000 + RANDOM % 20000)) TESTDB_WAIT=3
export FAKE="$T/docker"; mkdir -p "$FAKE"
cat > "$T/fake-docker" <<'F'
#!/usr/bin/env bash
echo "$*" >> "$FAKE/calls"
case $1 in
  info) exit 0;;
  inspect)
    n=${@: -1}; [ -f "$FAKE/$n" ] || exit 1
    case $3 in *Running*) sed -n 1p "$FAKE/$n";; *) sed -n 2p "$FAKE/$n";; esac;;
  run)
    name=''; img=''; port=''; prev=''
    for a; do
      case $prev in --name) name=$a;; -p) port=${a#127.0.0.1:}; port=${port%%:*};; esac; prev=$a
    done
    img=${@: -1}; printf 'true\n%s %s\n' "$img" "$port" > "$FAKE/$name";;
  start) sed -i.bak 1s/false/true/ "$FAKE/$2";;
  exec) [ -f "$FAKE/ready" ];;
  rm) for n; do case $n in rm|-f) ;; *) rm -f "$FAKE/$n";; esac; done;;
  ps) for f in "$FAKE"/agentdb-* "$FAKE"/userdb; do [ -f "$f" ] && printf '%s\t%s\n' "${f##*/}" "$(cat "$f.wt" 2>/dev/null)"; done; exit 0;;
  image|builder) exit 0;;
esac
F
chmod +x "$T/fake-docker"; export DOCKER="$T/fake-docker"

mkdir -p "$T/svc-12"
assert_exit 1 "no slot yet" -- "$TD" up "$T/svc-12" postgres
AGENT_LOCK_PID=$LIVE "$S" acquire "$T/svc-12" PROJ-12-spv1 >/dev/null
DBP=$((SLOT_BASE_PORT + 11))
touch "$FAKE/ready"
out=$("$TD" up "$T/svc-12" postgres); rc=$?
assert_eq 0 "$rc" "up postgres"
assert_eq "postgresql://agent:agent@127.0.0.1:$DBP/agent_svc_12" "$(printf '%s\n' "$out" | sed -n 's/^DATABASE_URL=//p')" "DATABASE_URL on slot port"
assert_eq yes "$(grep -q -- "--tmpfs /var/lib/postgresql/data" "$FAKE/calls" && grep -q -- "-p 127.0.0.1:$DBP:5432" "$FAKE/calls" && grep -q -- "--label agent-workflow=1" "$FAKE/calls" && echo yes || echo no)" "run: tmpfs, local port, label"
assert_eq running "$("$TD" status "$T/svc-12")" "status running"
n=$(grep -c '^run ' "$FAKE/calls")
"$TD" up "$T/svc-12" postgres >/dev/null
assert_eq "$n" "$(grep -c '^run ' "$FAKE/calls")" "second up reuses running container"
printf 'false\npostgres:16-alpine %s\n' "$DBP" > "$FAKE/agentdb-svc-12"
"$TD" up "$T/svc-12" postgres >/dev/null
assert_eq yes "$(grep -q '^start agentdb-svc-12' "$FAKE/calls" && echo yes || echo no)" "stopped container is started"
"$TD" up "$T/svc-12" mysql >/dev/null
assert_eq $((n + 1)) "$(grep -c '^run ' "$FAKE/calls")" "other engine/image -> recreated"
assert_eq "mysql:8.4 $DBP" "$(sed -n 2p "$FAKE/agentdb-svc-12")" "now mysql"
rm -f "$FAKE/ready"
assert_exit 1 "not ready -> exit 1" -- "$TD" up "$T/svc-12" mysql
touch "$FAKE/ready"
assert_exit 2 "unknown engine" -- "$TD" up "$T/svc-12" oracle
"$TD" down "$T/svc-12"
assert_eq absent "$("$TD" status "$T/svc-12")" "down removes"

# housekeeping: orphan agentdb removed, live one and user's container kept
"$TD" up "$T/svc-12" postgres >/dev/null; echo "$T/svc-12" > "$FAKE/agentdb-svc-12.wt"
printf 'true\nx 1\n' > "$FAKE/agentdb-old-7"; echo "$T/gone" > "$FAKE/agentdb-old-7.wt"
printf 'true\nx 1\n' > "$FAKE/userdb"
"$HK"; rc=$?
assert_eq 0 "$rc" "housekeeping exit 0"
assert_eq yes "$([ -f "$FAKE/agentdb-svc-12" ] && echo yes || echo no)" "container with live slot kept"
assert_eq no "$([ -f "$FAKE/agentdb-old-7" ] && echo yes || echo no)" "orphan agentdb removed"
assert_eq yes "$([ -f "$FAKE/userdb" ] && echo yes || echo no)" "user container never touched"
assert_eq yes "$(grep -q 'builder prune -f --filter until=168h' "$FAKE/calls" && echo yes || echo no)" "builder prune with age filter"
assert_eq yes "$(grep -q 'hapus container agentdb-old-7' "$AGENT_WORKFLOW_STATE/logs/housekeeping.log" && echo yes || echo no)" "logged"
"$S" release "$T/svc-12" PROJ-12-spv1
"$HK"
assert_eq no "$([ -f "$FAKE/agentdb-svc-12" ] && echo yes || echo no)" "slot released -> container removed"
DOCKER=/nonexistent/docker assert_exit 0 "no docker: skip quietly" -- env DOCKER=/nonexistent/docker "$HK"

exit $((FAILS > 0))
