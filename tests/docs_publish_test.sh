#!/usr/bin/env bash
# docs-publish.sh: docs worktree on branch agent-docs, commit + push to origin, web link
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
D="$REPO/bin/docs-publish.sh"
T=$(mktemp -d)
sleep 300 & LIVE=$!
trap 'kill $LIVE 2>/dev/null; rm -rf "$T"' EXIT
export AGENT_LOCK_DIR="$T/locks" AGENT_LOCK_PID=$LIVE
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q --bare "$T/origin.git"
git init -q -b main "$T/svc"; git -C "$T/svc" commit -q --allow-empty -m init
git -C "$T/svc" remote add origin "$T/origin.git"; git -C "$T/svc" push -q origin main
git -C "$T/svc" worktree add -q -b fix/PROJ-12 "$T/svc-12"

wt=$("$D" init "$T/svc-12"); rc=$?
assert_eq 0 "$rc" "init (first use: orphan branch)"
assert_eq "$T/svc-docs" "$wt" "docs worktree = <main repo>-docs next to checkouts"
assert_eq agent-docs "$(git -C "$wt" symbolic-ref --short HEAD)" "on agent-docs"
assert_eq "" "$(git -C "$wt" merge-base HEAD main 2>/dev/null)" "orphan: no history shared with code"
assert_eq yes "$(git -C "$T/origin.git" show-ref -q --verify refs/heads/agent-docs && echo yes || echo no)" "pushed to origin"
assert_eq "$wt" "$("$D" init "$T/svc")" "init again returns same worktree"

echo "# Validasi PROJ-12" > "$T/v.md"
link=$("$D" put "$wt" docs/tickets/PROJ-12/validasi.md "$T/v.md" "docs: validasi PROJ-12"); rc=$?
assert_eq 0 "$rc" "put"
assert_eq "$T/origin.git#agent-docs:docs/tickets/PROJ-12/validasi.md" "$link" "local remote: plain link"
assert_eq "# Validasi PROJ-12" "$(git -C "$T/origin.git" show agent-docs:docs/tickets/PROJ-12/validasi.md)" "content on origin"
n=$(git -C "$T/origin.git" rev-list --count agent-docs)
"$D" put "$wt" docs/tickets/PROJ-12/validasi.md "$T/v.md" >/dev/null
assert_eq "$n" "$(git -C "$T/origin.git" rev-list --count agent-docs)" "unchanged file: no new commit"
assert_eq "" "$("$REPO/bin/lock.sh" who "checkout:$wt")" "lock released after put"

# someone else pushed meanwhile (another machine): put rebases
git clone -q -b agent-docs "$T/origin.git" "$T/other"
echo x > "$T/other/other.md"; git -C "$T/other" add other.md; git -C "$T/other" commit -q -m other; git -C "$T/other" push -q origin agent-docs
echo "# Rencana" > "$T/r.md"
assert_exit 0 "put after remote moved" -- "$D" put "$wt" docs/tickets/PROJ-12/rencana.md "$T/r.md"
assert_eq yes "$(git -C "$T/origin.git" show agent-docs:other.md >/dev/null 2>&1 && git -C "$T/origin.git" show agent-docs:docs/tickets/PROJ-12/rencana.md >/dev/null 2>&1 && echo yes || echo no)" "both changes on origin"

# a second checkout finds the remote branch
rm -rf "$T/svc2"; git clone -q "$T/origin.git" "$T/svc2"; git -C "$T/svc2" checkout -q main
assert_eq "$T/svc2-docs" "$("$D" init "$T/svc2")" "init from existing origin/agent-docs"
assert_eq yes "$([ -f "$T/svc2-docs/docs/tickets/PROJ-12/rencana.md" ] && echo yes || echo no)" "existing docs checked out"

# web links
lk() { assert_eq "$1" "$("$D" link "$2" "docs/a b.md")" "link $2"; }
lk "https://github.com/acme/svc/blob/agent-docs/docs/a%20b.md" git@github.com:acme/svc.git
lk "https://github.com/acme/svc/blob/agent-docs/docs/a%20b.md" https://github.com/acme/svc.git
lk "https://github.com/acme/svc/blob/agent-docs/docs/a%20b.md" https://user:tok@github.com/acme/svc
lk "https://gitlab.example.com/grp/sub/svc/-/blob/agent-docs/docs/a%20b.md" ssh://git@gitlab.example.com:2222/grp/sub/svc.git
lk "https://gitlab.com/grp/svc/-/blob/agent-docs/docs/a%20b.md" git@gitlab.com:grp/svc.git

assert_exit 2 "dest outside worktree" -- "$D" put "$wt" ../x.md "$T/r.md"
assert_exit 2 "absolute dest" -- "$D" put "$wt" /tmp/x.md "$T/r.md"
assert_exit 1 "not the docs worktree" -- "$D" put "$T/svc-12" x.md "$T/r.md"
assert_exit 2 "usage" -- "$D" put

exit $((FAILS > 0))
