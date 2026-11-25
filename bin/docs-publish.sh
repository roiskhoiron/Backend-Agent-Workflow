#!/usr/bin/env bash
# Usage: docs-publish.sh init <checkout>                              -> create/find the docs worktree, print its path
#        docs-publish.sh put <docs-worktree> <dest-path> <src-file> [message]  -> commit + push, print the web link
#        docs-publish.sh link <remote-url> <dest-path>                       -> the web link only (no git)
# Documentation platform "repo" (skills/_shared/report-format.md): agent documents (validation, plan, test,
# audit and release reports) live as Markdown on branch DOCS_BRANCH (default agent-docs) of origin (the fork),
# in a docs worktree <repo>-docs next to the checkout. They never enter ticket PRs or the release sha.
# put: serialised with lock checkout:<docs-worktree>; pulls first (rebase), commits only when changed,
# pushes to origin only, retries once after a rejected push.
# Exit: 0 ok (stdout = path / link); 1 git or lock failure; 2 usage.
cmd=${1:-}
BR=${DOCS_BRANCH:-agent-docs}
LOCK="$(dirname "$0")/lock.sh"
export AGENT_LOCK_PID=${AGENT_LOCK_PID:-$PPID}
usage() { echo "usage: $0 init <checkout> | put <docs-worktree> <dest-path> <src-file> [message] | link <remote-url> <dest-path>" >&2; exit 2; }
g() { git -C "$wt" "$@"; }

weblink() { # remote-url path -> browsable link to the file on $BR
  python3 -I - "$1" "$BR" "$2" <<'PY'
import re, sys, urllib.parse as u
url, br, path = sys.argv[1:]
m = re.match(r"^(?:ssh://)?[\w.-]+@([\w.-]+)[:/](?:\d+/)?(.+?)(?:\.git)?/?$", url) or re.match(r"^https?://(?:[^@/]+@)?([\w.:-]+)/(.+?)(?:\.git)?/?$", url)
if not m:
    print(f"{url}#{br}:{path}"); sys.exit()
host, repo = m.group(1), m.group(2)
sep = "/-/blob/" if "gitlab" in host else "/blob/"
print(f"https://{host}/{repo}{sep}{u.quote(br)}/{u.quote(path)}")
PY
}

case $cmd in
  init)
    co=${2:-}; [ -d "$co" ] || usage
    top=$(git -C "$co" rev-parse --show-toplevel) || exit 1
    # name after the main checkout (<repo>-docs), next to it
    main=$(git -C "$co" worktree list --porcelain | sed -n '1s/^worktree //p')
    wt="$(dirname "$top")/$(basename "$main")-docs"
    if [ -d "$wt" ]; then
      [ "$(git -C "$wt" symbolic-ref --short -q HEAD)" = "$BR" ] || { echo "$wt ada tapi bukan di branch $BR" >&2; exit 1; }
      echo "$wt"; exit 0
    fi
    git -C "$co" fetch -q origin "$BR" 2>/dev/null
    if git -C "$co" show-ref -q --verify "refs/heads/$BR"; then
      git -C "$co" worktree add -q "$wt" "$BR" || exit 1
    elif git -C "$co" show-ref -q --verify "refs/remotes/origin/$BR"; then
      git -C "$co" worktree add -q -b "$BR" "$wt" "origin/$BR" || exit 1
    else
      # first use: empty orphan branch with only a README
      git -C "$co" worktree add -q --detach "$wt" || exit 1
      git -C "$wt" switch -q --orphan "$BR" || exit 1
      printf '# Dokumen agen\n\nLaporan validasi, rencana, uji, audit, dan rilis yang ditulis agen workflow Backend.\nBranch ini terpisah dari kode: tidak pernah di-merge.\n' > "$wt/README.md"
      git -C "$wt" add README.md && git -C "$wt" commit -q -m "docs: mulai branch $BR" || exit 1
      git -C "$wt" push -q -u origin "$BR" || exit 1
    fi
    echo "$wt" ;;
  put)
    wt=${2:-} dest=${3:-} src=${4:-} msg=${5:-}
    [ -n "$wt" ] && [ -n "$dest" ] && [ -f "$src" ] || usage
    case $dest in /*|*..*) echo "dest-path harus relatif di dalam worktree dokumen: $dest" >&2; exit 2;; esac
    [ "$(g symbolic-ref --short -q HEAD)" = "$BR" ] || { echo "$wt bukan worktree branch $BR (jalankan init)" >&2; exit 1; }
    owner="docs-publish-$AGENT_LOCK_PID"
    for _ in $(seq 1 30); do "$LOCK" acquire "checkout:$wt" "$owner" >/dev/null && break; sleep 2; done
    [ "$("$LOCK" who "checkout:$wt")" = "$owner" ] || { echo "worktree dokumen dikunci $("$LOCK" who "checkout:$wt")" >&2; exit 1; }
    trap '"$LOCK" release "checkout:$wt" "$owner"' EXIT
    if g ls-remote -q --exit-code origin "refs/heads/$BR" >/dev/null 2>&1; then g pull -q --rebase origin "$BR" || exit 1; fi
    mkdir -p "$wt/$(dirname "$dest")" && cp "$src" "$wt/$dest" || exit 1
    g add -- "$dest" || exit 1
    g diff --cached --quiet || g commit -q -m "${msg:-docs: perbarui $dest}" || exit 1
    if ! g push -q origin "$BR" 2>/dev/null; then
      g pull -q --rebase origin "$BR" && g push -q origin "$BR" || exit 1
    fi
    weblink "$(g remote get-url origin)" "$dest" ;;
  link) [ -n "${2:-}" ] && [ -n "${3:-}" ] || usage; weblink "$2" "$3" ;;
  *) usage ;;
esac
