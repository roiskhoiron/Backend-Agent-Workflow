#!/usr/bin/env bash
# every shell script parses; every bin/ script and the guard are executable
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
for f in "$REPO"/bin/* "$REPO"/hooks/guard.sh "$REPO"/install.sh "$REPO"/tests/*.sh; do
  assert_exit 0 "bash -n ${f#$REPO/}" -- bash -n "$f"
done
for f in "$REPO"/bin/* "$REPO"/hooks/guard.sh "$REPO"/install.sh; do
  assert_eq yes "$([ -x "$f" ] && echo yes || echo no)" "executable ${f#$REPO/}"
done
exit $((FAILS > 0))
