#!/usr/bin/env bash
# lock.sh + env-slot.sh
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
L="$REPO/bin/lock.sh" S="$REPO/bin/env-slot.sh"
T=$(mktemp -d)
sleep 300 & LIVE=$!; sleep 300 & LIVE2=$!
trap 'kill $LIVE $LIVE2 2>/dev/null; rm -rf "$T"' EXIT
export AGENT_LOCK_DIR="$T/locks" AGENT_WORKFLOW_STATE="$T/st" SLOT_BASE_PORT=$((20000 + RANDOM % 20000))

# lock.sh
assert_exit 0 "acquire free" -- env AGENT_LOCK_PID=$LIVE "$L" acquire deploy:dev PROJ-1-release1
assert_eq "PROJ-1-release1" "$("$L" who deploy:dev)" "who = owner"
assert_exit 0 "alive" -- "$L" alive deploy:dev
assert_exit 1 "held by live pid" -- env AGENT_LOCK_PID=$LIVE2 "$L" acquire deploy:dev PROJ-2-release1
assert_eq "PROJ-1-release1" "$(AGENT_LOCK_PID=$LIVE2 "$L" acquire deploy:dev PROJ-2-release1)" "busy prints owner"
assert_exit 0 "same owner re-acquire" -- env AGENT_LOCK_PID=$LIVE "$L" acquire deploy:dev PROJ-1-release1
"$L" release deploy:dev PROJ-2-release1
assert_eq "PROJ-1-release1" "$("$L" who deploy:dev)" "release by non-owner ignored"
assert_exit 0 "move" -- env AGENT_LOCK_PID=$LIVE "$L" move deploy:dev PROJ-1-release1 PROJ-1-qa1
assert_eq "PROJ-1-qa1" "$("$L" who deploy:dev)" "moved owner"
assert_exit 1 "move from wrong owner" -- "$L" move deploy:dev nobody x
"$L" release deploy:dev PROJ-1-qa1
assert_eq "" "$("$L" who deploy:dev)" "released"
assert_exit 1 "alive after release" -- "$L" alive deploy:dev
assert_exit 0 "dead pid lock is reclaimed" -- env AGENT_LOCK_PID=999999 "$L" acquire account:qa.user1 a
assert_exit 0 "...by another owner" -- env AGENT_LOCK_PID=$LIVE "$L" acquire account:qa.user1 b
assert_eq "b" "$("$L" who account:qa.user1)" "reclaimed owner"
assert_exit 2 "usage" -- "$L" nope
assert_exit 2 "acquire without owner" -- "$L" acquire x

# env-slot.sh
mkdir -p "$T/svc-12" "$T/svc-13" "$T/Svc 14"
out=$(AGENT_LOCK_PID=$LIVE "$S" acquire "$T/svc-12" PROJ-12-spv1); rc=$?
assert_eq 0 "$rc" "slot acquire"
v() { printf '%s\n' "$out" | sed -n "s/^$1=//p"; }
assert_eq 1 "$(v SLOT)" "first slot = 1"
assert_eq $((SLOT_BASE_PORT + 10)) "$(v APP_PORT)" "APP_PORT"
assert_eq $((SLOT_BASE_PORT + 11)) "$(v DB_PORT)" "DB_PORT"
assert_eq agent_svc_12 "$(v DB_NAME)" "DB_NAME"
assert_eq agentdb-svc-12 "$(v DB_CONTAINER)" "DB_CONTAINER"
assert_eq agent-svc-12 "$(v COMPOSE_PROJECT_NAME)" "COMPOSE_PROJECT_NAME"
assert_eq "$out" "$(AGENT_LOCK_PID=$LIVE "$S" acquire "$T/svc-12" PROJ-12-spv1)" "re-acquire same worktree = same slot"
assert_eq "$out" "$("$S" show "$T/svc-12/../svc-12")" "show (path normalised)"
assert_exit 1 "other owner cannot take a held slot" -- env AGENT_LOCK_PID=$LIVE2 "$S" acquire "$T/svc-12" PROJ-99-spv1
out2=$(AGENT_LOCK_PID=$LIVE2 "$S" acquire "$T/svc-13" PROJ-13-spv1)
assert_eq 2 "$(printf '%s\n' "$out2" | sed -n 's/^SLOT=//p')" "second worktree = slot 2"
out3=$(AGENT_LOCK_PID=$LIVE2 "$S" acquire "$T/Svc 14" PROJ-14-spv1)
assert_eq agent_svc_14 "$(printf '%s\n' "$out3" | sed -n 's/^DB_NAME=//p')" "slug from name with space/caps"
assert_eq 3 "$("$S" list | wc -l | tr -d ' ')" "list = 3 slots"
assert_exit 1 "release by wrong owner" -- "$S" release "$T/svc-13" PROJ-12-spv1
"$S" release "$T/svc-13" PROJ-13-spv1
assert_exit 1 "show after release" -- "$S" show "$T/svc-13"
out4=$(AGENT_LOCK_PID=$LIVE "$S" acquire "$T/svc-13" PROJ-13-spv1)
assert_eq 2 "$(printf '%s\n' "$out4" | sed -n 's/^SLOT=//p')" "freed slot reused"
# a busy port skips the slot
python3 -c 'import socket,sys,time; s=socket.socket(); s.bind(("127.0.0.1",int(sys.argv[1]))); s.listen(); time.sleep(20)' $((SLOT_BASE_PORT + 40)) & PY=$!
sleep 0.5
mkdir -p "$T/svc-15"
out5=$(AGENT_LOCK_PID=$LIVE "$S" acquire "$T/svc-15" PROJ-15-spv1)
assert_eq 5 "$(printf '%s\n' "$out5" | sed -n 's/^SLOT=//p')" "slot 4 skipped: its APP_PORT is in use"
kill $PY 2>/dev/null
# holder died -> mapping stale, slot free again
mkdir -p "$T/svc-16"
sleep 300 & DIE=$!
AGENT_LOCK_PID=$DIE "$S" acquire "$T/svc-16" PROJ-16-spv1 >/dev/null
kill $DIE; wait $DIE 2>/dev/null
assert_exit 1 "dead holder: no slot" -- "$S" show "$T/svc-16"
SLOT_MAX=1 assert_exit 1 "no free slot" -- env SLOT_MAX=1 AGENT_LOCK_PID=$LIVE "$S" acquire "$T/svc-16" x
assert_exit 2 "missing worktree" -- "$S" acquire "$T/nope" x
assert_exit 2 "usage" -- "$S" acquire

exit $((FAILS > 0))
