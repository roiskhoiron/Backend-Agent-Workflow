#!/bin/bash
# Claude Code PreToolUse guard (Backend workflow). stdin = hook JSON. exit 0 = allow, exit 2 + stderr = block.
# One check_<tool> function per tool; unknown tools and unparseable input are allowed.
# Same git/worktree/Orca/audit/Jira rules as the Mobile workflow, without device checks, plus:
# production databases and environments (check_prod) and the user's docker data (check_docker).
# shortcut: the guard reads command TEXT only; a prod URL hidden in .env or a variable is not seen,
# so rules.md still forbids it and test-db.sh/migration-check.sh refuse non-local databases.
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
PROTECTED='main|master|develop'
VTAG='v[0-9]+\.[0-9]+\.[0-9]+'

block() { echo "DIBLOKIR oleh guard: $*" >&2; exit 2; }

JQ=$(command -v jq) || block "jq tidak ditemukan, guard tidak bisa memeriksa perintah. Install jq (brew install jq / apt install jq)."
PY=$(command -v python3)

# resolve $1 against $2 (dir); pure string, python normalizes later
join_path() { case $1 in /*) echo "$1";; *) echo "$2/$1";; esac; }

# expand leading ~ / $HOME / ${HOME}; leaves other $vars untouched
expand_home() {
  case $1 in
    '~') echo "$HOME";;
    '~/'*) echo "$HOME/${1#\~/}";;
    '$HOME'|'${HOME}') echo "$HOME";;
    '$HOME/'*) echo "$HOME/${1#\$HOME/}";;
    '${HOME}/'*) echo "$HOME/${1#\$\{HOME\}/}";;
    *) echo "$1";;
  esac
}

# every ref is a version tag vX.Y.Z (name, refs/tags/name, or name:refs/tags/name) and not a local branch
version_tags_only() { # dir ref...
  local d=$1 r s; shift
  for r; do
    s=${r%%:*}; s=${s#refs/tags/}
    case $r in *:*) [ "${r#*:}" = "refs/tags/$s" ] || return 1;; esac
    echo "$s" | grep -Eqx "$VTAG" || return 1
    case ${r%%:*} in refs/tags/*) ;; *) ! git -C "$d" show-ref -q --verify "refs/heads/$s" 2>/dev/null || return 1;; esac
  done
}

# git [global opts] push ...   ($d = directory git runs in)
# Sets GSUB_OFF = index of git's subcommand among the args (so `git rm` isn't checked as rm).
check_git() {
  local d=$wd n=$# unk=''
  while [ $# -gt 0 ]; do
    case $1 in
      -C) d=$(join_path "$(expand_home "$2")" "$wd"); shift 2;;
      -c|--git-dir|--work-tree|--namespace|--super-prefix|--config-env) shift 2;;
      --*=*|-p|-P|--paginate|--no-pager|--bare|--no-replace-objects|--no-optional-locks|--*-pathspecs) shift;;
      -*) unk=1; shift;;
      *) break;;
    esac
  done
  GSUB_OFF=$((n - $#))
  [ -n "$AUDIT" ] && check_git_audit "$@"
  [ "$1" = worktree ] && case ${2:-} in add|remove|move) check_worktree "$d" "${@:2}";; esac
  # unknown global option may have swallowed a value: if `push` appears anywhere, treat as push
  if [ "$1" != push ] && [ -n "$unk" ]; then
    while [ $# -gt 0 ] && [ "$1" != push ]; do shift; done
  fi
  [ "$1" = push ] || return 0
  shift
  local remote='' repo='' destructive='' bulk='' refs=() r dst br
  while [ $# -gt 0 ]; do
    case $1 in
      --repo=*) repo=${1#--repo=};;
      --repo) repo=$2; shift;;
      -o|--push-option|--receive-pack|--exec) shift;;
      --force*|--mirror|--delete) destructive=1;;
      --tags|--follow-tags|--all|--branches) bulk=1;;
      --*) ;;
      -*[fd]*) destructive=1;;
      -*) ;;
      *) if [ -z "$remote" ]; then remote=$1; else refs+=("$1"); fi;;
    esac
    shift
  done
  [ -n "$remote" ] || remote=$repo  # positional remote wins over --repo
  # Release pushes version tags to origin and upstream; explicit refs only, never force/delete/bulk
  [ -z "$destructive$bulk" ] && [ ${#refs[@]} -gt 0 ] && version_tags_only "$d" "${refs[@]}" && return 0

  br=$(git -C "$d" symbolic-ref --short -q HEAD 2>/dev/null)
  if [ -z "$remote" ]; then
    remote=$(git -C "$d" config "branch.$br.pushRemote" 2>/dev/null ||
             git -C "$d" config remote.pushDefault 2>/dev/null ||
             git -C "$d" config "branch.$br.remote" 2>/dev/null)
    [ -n "$remote" ] || block "remote untuk 'git push' tidak bisa dipastikan. Tulis eksplisit: git push origin <branch>."
  fi
  if [ "$remote" != origin ]; then
    local ou ru
    ou=$(git -C "$d" remote get-url --push origin 2>/dev/null)
    ru=$(git -C "$d" remote get-url --push "$remote" 2>/dev/null || echo "$remote")
    [ -n "$ou" ] && [ "$ru" = "$ou" ] ||
      block "push ke remote '$remote' dilarang; hanya boleh ke origin (fork). Gunakan: git push origin <branch>, lalu buat PR."
  fi

  [ ${#refs[@]} -eq 0 ] && refs=(HEAD)
  for r in "${refs[@]}"; do
    dst=${r#+}; dst=${dst##*:}; dst=${dst#refs/heads/}
    [ "$dst" = HEAD ] && dst=$br
    case $r in +*|:*) ;; *) [ -n "$destructive" ] || continue;; esac
    if echo "$dst" | grep -Eqx "$PROTECTED"; then
      block "force-push/hapus branch terlindungi '$dst' dilarang. Push tanpa --force/+, atau ke branch fitur."
    fi
  done
}

audit_block() { block "$1 dilarang: mode audit hanya-baca (/audit-issue). Catat temuan di laporan, jangan ubah repo/Jira."; }

# audit mode: only read-only git subcommands; branch/tag only list, never create/delete
check_git_audit() {
  local s=${1:-} a list='' skip=''
  shift
  case $s in
    ''|show|log|grep|blame|diff|status|ls-files|ls-tree|rev-parse|rev-list|describe|cat-file|for-each-ref|show-ref|shortlog|name-rev|merge-base|help|version|--version|--help) return 0;;
    fetch) for a; do case $a in *:*) audit_block "git fetch $a (refspec menulis branch lokal)";; esac; done;;
    reflog) case ${1:-} in expire|delete) audit_block "git reflog $1";; esac;;
    branch|tag)
      for a; do
        [ -n "$skip" ] && { skip=''; continue; }
        case $a in
          -l|--list) list=1;;
          --contains|--no-contains|--merged|--no-merged|--points-at|--sort|--format) skip=1;;
          -a) [ "$s" = tag ] && audit_block "git tag -a";;
          -d|-D|-m|-M|-c|-C|-f|-u|-s|-F|-e|--delete|--move|--copy|--force|--annotate|--sign|--edit-description|--unset-upstream|--set-upstream-to*|--track*|--file*|--message*) audit_block "git $s $a";;
          -*) ;;
          *) [ -n "$list" ] || audit_block "git $s $a";;
        esac
      done;;
    remote)
      case ${1:-} in -v|--verbose) shift;; esac
      case ${1:-} in ''|get-url|show) ;; *) audit_block "git remote $1";; esac;;
    config) for a; do case $a in --get|--get-all|--get-regexp|--list|-l) return 0;; esac; done; audit_block "git config";;
    worktree) [ "${1:-}" = list ] || audit_block "git worktree ${1:-}";;
    stash) case ${1:-} in list|show) ;; *) audit_block "git stash ${1:-}";; esac;;
    *) audit_block "git $s";;
  esac
  return 0
}

# audit mode: glab read-only (gh is never blocked, user decision 2026-11-11): read verbs only (view/list/...), api GET without fields
check_forge() {
  local a prev=''
  case ${1:-} in
    ''|search|status|help|version|--version|--help|-h) ;;
    auth) [ "${2:-}" = status ] || audit_block "gh/glab auth ${2:-}";;
    api)
      for a; do
        case $a in -f*|-F*|--field*|--raw-field*|--input*) audit_block "gh/glab api $a";; esac
        case $prev in -X|--method) [ "$a" = GET ] || audit_block "gh/glab api $prev $a";; esac
        case $a in --method=*) [ "${a#*=}" = GET ] || audit_block "gh/glab api $a";; -X?*) [ "${a#-X}" = GET ] || audit_block "gh/glab api $a";; esac
        prev=$a
      done;;
    *) case ${2:-} in view|list|ls|status|diff|checks|show|watch|-h|--help) ;; *) audit_block "gh/glab $1 ${2:-}";; esac;;
  esac
  return 0
}

# true when $1 resolves inside ${TMPDIR:-/tmp}/audit or /tmp/audit (symlinks like /tmp -> /private/tmp resolved)
in_audit_dir() {
  "$PY" -c '
import os, sys
def rp(p):
    head, tail = p, ""
    while not os.path.exists(head) and head != "/":
        head, t = os.path.split(head); tail = os.path.join(t, tail) if tail else t
    return os.path.normpath(os.path.join(os.path.realpath(head), tail))
f = rp(sys.argv[1])
sys.exit(0 if any(f.startswith(rp(r).rstrip("/") + "/") for r in sys.argv[2:]) else 1)
' "$1" "${TMPDIR:-/tmp}/audit" /tmp/audit
}

# git worktree add/remove: only a sibling of the current checkout; remove only ticket
# worktrees (<repo>-<number>) and never forced, so dirty work can't be lost (rules.md, Workspace & worktree)
check_worktree() {
  local d=$1 op=$2 p='' top
  shift 2
  [ "$op" = move ] && block "git worktree move dilarang: jangan memindah worktree. Minta user."
  while [ $# -gt 0 ]; do
    case $1 in
      -b|-B|--reason) shift 2;;
      -f|--force) [ "$op" = remove ] && block "git worktree remove --force dilarang: worktree yang masih ada perubahan tidak boleh dipaksa hapus. Commit + push dulu, atau minta user."; shift;;
      -*) shift;;
      *) [ -n "$p" ] || p=$1; shift;;
    esac
  done
  [ -n "$p" ] || return 0
  [ -n "$PY" ] || block "python3 tidak ditemukan, guard tidak bisa memeriksa path worktree."
  top=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null) || block "git worktree $op: repo tidak dikenali di $d."
  p=$("$PY" -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$(join_path "$(expand_home "$p")" "$d")")
  top=$("$PY" -c 'import os,sys; print(os.path.dirname(os.path.realpath(sys.argv[1])))' "$top")
  [ "${p%/*}" = "$top" ] || block "git worktree $op hanya untuk folder sejajar checkout ini ($top/<repo>-<nomor tiket>), tulis path apa adanya tanpa variabel: $p (rules.md, Workspace & worktree)."
  [ "$op" = remove ] && ! [[ ${p##*/} =~ -[0-9]+$|-rilis-v[0-9][0-9.]*$ ]] && block "git worktree remove hanya untuk worktree tiket <repo>-<nomor tiket> atau worktree rilis sementara <repo>-rilis-vX.Y.Z: ${p##*/} bukan worktree agen (worktree domain/milik user tidak dihapus agen)."
  return 0
}

# orca: no new projects/repos or workspaces outside the user's domain (rules.md, Workspace & worktree)
check_orca() {
  local a
  case "$1 ${2:-}" in
    'repo add'|'project setup-'*) block "orca $1 $2 dilarang: agen tidak membuat project/repo Orca baru. Minta user.";;
    'worktree create') [ -n "$AUDIT" ] && audit_block "orca worktree create";;
    'terminal split') block "orca terminal split dilarang: agen tambahan = teammate (tool Agent dengan name \"<Nama>-<Label><n>\"); panelnya dibuka Claude Code otomatis (rules.md, Orkestrasi).";;
    'terminal create'|'agent launch') block "orca $1 $2 dilarang: membuka tab baru. Agen tambahan = teammate (tool Agent dengan name), tampil sebagai panel split (rules.md, Orkestrasi).";;
    'orchestration worker-start') case " $* " in *' --agent '*|*' --agent='*) block "worker-start --agent dilarang: membuka tab baru. Agen tambahan = teammate (tool Agent dengan name) (rules.md, Orkestrasi).";; esac;;
  esac
  for a; do
    case $a in
      --no-parent|new-child|new-top-level|--worktree=new-child|--worktree=new-top-level)
        block "orca $a dilarang: semua agen bekerja di workspace domain (teammate di workspace ini). Lihat rules.md.";;
    esac
  done
}

# rm -r/-R/--recursive: every target must be strictly inside the project root
check_rm() {
  local rec='' endopt='' paths=() a bad py wts
  for a; do
    if [ -z "$endopt" ]; then
      case $a in
        --) endopt=1; continue;;
        --recursive) rec=1; continue;;
        --*) continue;;
        -*[rR]*) rec=1; continue;;
        -*) continue;;
      esac
    fi
    paths+=("$(expand_home "$a")")
  done
  [ -n "$rec" ] || return 0
  for a in ${paths[@]+"${paths[@]}"}; do
    case $a in *'$'*|*'`'*|'~'*|*'{}'*) block "rm -r dengan variabel/path tak pasti ('$a') dilarang. Tulis path literal di dalam proyek.";; esac
  done
  [ ${#paths[@]} -gt 0 ] || block "rm -r tanpa path literal (mis. lewat xargs) dilarang. Tulis path di dalam proyek secara eksplisit."
  # other worktrees of this repo + project folders the user listed in build-roots.txt: only rebuildable build artifacts
  wts=$(git -C "$root" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p'; sed -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' "$HOME/.agent-workflow/build-roots.txt" 2>/dev/null)
  bad=$(WTS="$wts" "$PY" -c '
import os, sys
ART = {"build", "dist", "target", "out", ".gradle", "node_modules", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".tox", ".venv", "coverage"}
c, root = sys.argv[1], os.path.realpath(sys.argv[2])
wts = [os.path.realpath(w) for w in os.environ.get("WTS", "").splitlines() if w]
def artifact(r):
    for t in {"/tmp", os.environ.get("TMPDIR") or "/tmp"}:  # temporary agent work folders
        for sub in ("qa", "validate", "audit"):
            if r.startswith(os.path.realpath(os.path.join(t, sub)) + os.sep):
                return True
    for w in wts:
        if r.startswith(w + os.sep) and ART & set(os.path.relpath(r, w).split(os.sep)):
            return True
    return False
for p in sys.argv[3:]:
    n = os.path.normpath(os.path.join(c, p))
    # trailing slash makes rm follow a symlink, so check its target
    r = os.path.realpath(n) if p.endswith("/") else os.path.join(os.path.realpath(os.path.dirname(n)), os.path.basename(n))
    if not r.startswith(root + os.sep) and not artifact(r):
        print(p); break
' "$wd" "$root" "${paths[@]}" 2>/dev/null) || block "path rm -r tidak bisa diverifikasi (python3 gagal)."
  [ -z "$bad" ] || block "rm -r di luar proyek ($root) dilarang: '$bad'. Hapus hanya path di dalam proyek, atau artefak build (build, dist, target, out, .gradle, node_modules, __pycache__, .pytest_cache, .venv, coverage, ...) di worktree lain repo ini atau di folder project dari ~/.agent-workflow/build-roots.txt; isi \${TMPDIR:-/tmp}/{qa,validate,audit} bebas."
}

# Tokenize like a shell (quotes kept together); one line per simple command, tokens joined by \x1f.
# Strings run by `sh -c`/`eval`, and $(...)/`...` contents, are tokenized again as extra lines.
TOKENIZER='
import json, re, shlex, sys
SEP = set("();<>|&\n")
def toks(c):
    c = re.sub(r"(?<!\\)((?:\\\\)*)\\\n", r"\1", c)  # line continuation = odd backslash run + newline (also inside single quotes: at worst over-blocks)
    try:
        l = shlex.shlex(c, posix=True, punctuation_chars="();<>|&\n")
        l.whitespace = " \t\r"  # unquoted newline separates commands
        l.whitespace_split = True; l.commenters = ""
        return list(l)
    except ValueError:  # unbalanced quotes: crude split, fail closed
        return [t.strip("\"\x27") for t in re.findall(r"[();<>|&\n]+|[^\s();<>|&]+", c)]
def segs(c, depth=0):
    out, cur, prev = [], [], ""
    for t in toks(c):
        if t and all(ch in SEP for ch in t):
            out.append(cur); cur = []; prev = t; continue
        if not t.strip(): continue  # stray escaped whitespace
        if depth < 3 and ("$(" in t or "`" in t or (re.search(r"\s", t) and (re.fullmatch(r"-\w*c", prev) or prev == "eval"))):
            out += segs(t.replace("`", " "), depth + 1)
        t = t.replace("`", "").replace("\n", " ").replace("\x1f", " ")
        cur.append(t)
        if t != "--": prev = t  # sh -c -- "cmd"
    return out + [cur]
cmd = (json.load(sys.stdin).get("tool_input") or {}).get("command") or ""
for s in segs(cmd):
    if s: print("\x1f".join(s))
'

# --- backend: production databases/environments and the user's docker data ---
# prod-hosts.txt (user-filled, one host per line, '#' comments): production DB/API hosts. Subdomains match too.
PROD_HOSTS=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "${AGENT_WORKFLOW_STATE:-$HOME/.agent-workflow}/prod-hosts.txt" 2>/dev/null | tr 'A-Z' 'a-z')
DBCLI='psql|pg_dump|pg_dumpall|pg_restore|mysql|mysqldump|mariadb|mariadb-dump|mongo|mongosh|mongodump|mongorestore|mongoimport|redis-cli|sqlcmd|cqlsh|clickhouse-client|sqlite3'
MIGRATE='migrate|migration|migrations|migrate:latest|migrate:up|migrate:down|migrate:rollback|migration:run|migration:revert|db:migrate|db:rollback|db:seed|db:drop|db:reset|db:setup|db:push|upgrade|downgrade|flyway|liquibase|alembic|goose|dbmate|sqlx|atlas|knex|sequelize|typeorm|prisma|diesel|rake|artisan'
# env markers that point a tool at production
PRODENV='(^|_)(NODE|RAILS|RACK|APP|MIX|FLASK|ASPNETCORE|GO|SPRING_PROFILES|ENV|ENVIRONMENT|STAGE)(_ENV|_ACTIVE)?=(prod|production|live)$|^--(env|environment|stage|profile)=(prod|production|live)$|^DJANGO_SETTINGS_MODULE=.*prod'

# token names a production host (whole hostname, or a subdomain of it)
prod_host_in() {
  local h e
  [ -n "$PROD_HOSTS" ] || return 1
  while IFS= read -r h; do
    e=$(printf '%s' "$h" | sed 's/[.[\*^$()+?{|]/\\&/g')
    [[ ${1,,} =~ (^|[^a-z0-9-])([a-z0-9-]+\.)*$e($|[^a-z0-9.-]) ]] && return 0
  done <<< "$PROD_HOSTS"
  return 1
}

# one simple command (all its tokens): DB client or migration tool aimed at production -> block
check_prod() {
  local t c db='' mig='' prod='' host='' prev='' http='' write=''
  for t; do
    c=${t##*/}
    [[ $c =~ ^($DBCLI)$ ]] && db=$c
    [[ $c =~ ^(curl|wget|http|https|xh)$ ]] && http=$c
    # write intent: explicit method, request body, upload; httpie/xh: method word
    case $t in
      -d|--data*|-F|--form*|--json|-T|--upload-file|--post-data*|--post-file*|--body-data*|--body-file*) write=$t;;
      -X?*|--request=*|--method=*) [[ ${t#*[X=]} =~ ^(POST|PUT|PATCH|DELETE)$ ]] && write=$t;;
      POST|PUT|PATCH|DELETE) case $prev in -X|--request|--method) write="$prev $t";; *) [[ $prev =~ ^(http|https|xh)$ ]] && write=$t;; esac;;
    esac
    [[ ${t,,} =~ ^($MIGRATE)$ ]] && mig=$t
    [[ $t =~ $PRODENV ]] && prod=$t
    case $prev in --env|--environment|--stage|-e|--profile) [[ ${t,,} =~ ^(prod|production|live)$ ]] && prod="$prev $t";; esac
    prod_host_in "$t" && host=$t
    prev=$t
  done
  [ -n "$host" ] && [ -n "$http" ] && [ -n "$write" ] && block "$http dengan '$write' ke host production dilarang: di live/production hanya GET/HEAD/OPTIONS tanpa menulis data (http-evidence.sh --safe)."
  [ -n "$host" ] && [ -n "$db$mig" ] && block "akses database production dilarang ('${db:-$mig}' ke host production di prod-hosts.txt). Agen hanya memakai database uji (test-db.sh) dan server dev; migrasi production dijalankan manusia atau pipeline."
  [ -n "$prod" ] && [ -n "$mig$db" ] && block "migrasi/akses database dengan env production ('$prod') dilarang. Uji migrasi di database uji (migration-check.sh); migrasi production dijalankan manusia atau pipeline."
  return 0
}

# docker: never destroy the user's containers/volumes; only agent test DBs (agentdb-*) and agent-* compose projects
check_docker() {
  local a sub='' sub2='' proj=$COMPOSE_ENV rmv='' names=() n skip=''
  for a; do
    if [ -n "$skip" ]; then
      case $skip in proj) proj=$a;; esac; skip=''; continue
    fi
    # options that take a value: docker's global ones before the subcommand, compose's own after `compose`
    if [ -z "$sub" ]; then
      case $a in -H|--host|-c|--context|--config|-l|--log-level) skip=x; continue;; esac
    elif [ "$sub" = compose ]; then
      case $a in
        -p|--project-name) skip=proj; continue;;
        -f|--file|--env-file|--profile|--project-directory|--ansi|--progress) skip=x; continue;;
        --project-name=*) proj=${a#*=}; continue;;
        -v|--volumes) rmv=1; continue;;
      esac
    fi
    case $a in -*) continue;; esac
    if [ -z "$sub" ]; then sub=$a
    elif [ -z "$sub2" ]; then sub2=$a; names+=("$a")
    else names+=("$a"); fi
  done
  if [ -n "$AUDIT" ]; then
    case $sub in ps|logs|inspect|images|version|info|stats|top|''|compose) ;; *) audit_block "docker $sub";; esac
    [ "$sub" = compose ] && case $sub2 in ps|logs|config|ls|images|top|'') ;; *) audit_block "docker compose $sub2";; esac
    return 0
  fi
  case "$sub $sub2" in
    'system prune'|'volume prune'|'container prune'|'network prune') block "docker $sub $sub2 dilarang: bisa menghapus container/volume milik user. Hapus hanya database uji agen: test-db.sh down <worktree>.";;
    'compose down')
      [ -n "$rmv" ] && [[ $proj != agent-* ]] && block "docker compose down -v dilarang untuk project '${proj:-?}': volume data milik user. Hanya project agent-* (COMPOSE_PROJECT_NAME dari env-slot.sh) yang boleh dihapus volumenya.";;
  esac
  case $sub in
    rm|kill) for n in "${names[@]}"; do [[ $n == agentdb-* ]] || block "docker $sub $n dilarang: hanya container agen (agentdb-*). Container lain milik user."; done;;
    volume) [ "$sub2" = rm ] && for n in "${names[@]:1}"; do [[ $n == agentdb-* || $n == agent-* ]] || block "docker volume rm $n dilarang: volume milik user."; done;;
    container) [ "$sub2" = rm ] && for n in "${names[@]:1}"; do [[ $n == agentdb-* ]] || block "docker container rm $n dilarang: hanya container agen (agentdb-*)."; done;;
  esac
  return 0
}

check_Bash() {
  local segs w i c t prev gsub dk
  [ -n "$PY" ] || block "python3 tidak ditemukan, guard tidak bisa memeriksa perintah Bash."
  segs=$(printf '%s' "$input" | "$PY" -c "$TOKENIZER" 2>/dev/null) || block "perintah Bash tidak bisa diurai oleh guard."
  root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")
  wd=$cwd   # follows cd/pushd inside the chained command
  while IFS=$'\x1f' read -ra w; do
    gsub=-1; prev=''; COMPOSE_ENV=''
    [ ${#w[@]} -gt 0 ] && check_prod "${w[@]}"
    # any git/rm token starts a command, wherever it sits (sudo -u x, timeout 60, VAR=..., if/then, xargs ...)
    for ((i = 0; i < ${#w[@]}; i++)); do
      c=${w[$i]##*/}
      case $c in
        cd|pushd)  # only in command position, so `echo cd x` doesn't move wd
          case $prev in ''|'!'|'{'|then|do|else|if|while|until|command|builtin)
            t=$(expand_home "${w[$((i+1))]:-~}")
            case $t in *'$'*|-*) wd=/;; *) wd=$(join_path "$t" "$wd");; esac;;
          esac;;
        git) GSUB_OFF=-1; check_git "${w[@]:$((i+1))}"; gsub=$((i + 1 + GSUB_OFF));;
        orca) check_orca "${w[@]:$((i+1))}";;
        glab) [ -n "$AUDIT" ] && check_forge "${w[@]:$((i+1))}";;
        rm) [ $i -eq $gsub ] || check_rm "${w[@]:$((i+1))}";;
        COMPOSE_PROJECT_NAME=*) COMPOSE_ENV=${w[$i]#*=};;
        docker) check_docker "${w[@]:$((i+1))}";;
        docker-compose) check_docker compose "${w[@]:$((i+1))}";;
        test-db.sh|migration-check.sh|docs-publish.sh|env-slot.sh)  # audit: no containers, migrations, or doc pushes
          [ -n "$AUDIT" ] && case "$c ${w[$((i+1))]:-}" in 'test-db.sh status'|'env-slot.sh show'|'env-slot.sh list'|'docs-publish.sh link') ;; *) audit_block "$c ${w[$((i+1))]:-}";; esac;;
      esac
      prev=${w[$i]}
    done
  done <<< "$segs"
  return 0
}

# Edit/Write/MultiEdit: the primary (main) worktree is read-only once the repo has a linked worktree
# (Orca pattern); a plain checkout without linked worktrees is editable.
check_edit() {
  local f d pd gd cd_
  f=$(printf '%s' "$input" | "$JQ" -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
  [ -n "$f" ] || return 0
  [ -n "$PY" ] || block "python3 tidak ditemukan, guard tidak bisa memeriksa path."
  f=$(join_path "$(expand_home "$f")" "$cwd")
  if [ -n "$AUDIT" ]; then
    in_audit_dir "$f" || audit_block "edit file di luar folder kerja audit ${TMPDIR:-/tmp}/audit/ ($f)"
    return 0
  fi
  d=$("$PY" -c 'import os,sys; print(os.path.dirname(os.path.realpath(sys.argv[1])))' "$f") || return 0
  while [ ! -d "$d" ] && [ "$d" != / ]; do d=$(dirname "$d"); done  # new file: nearest existing parent
  pd=$(git -C "$d" rev-parse --absolute-git-dir 2>/dev/null) || return 0  # not in a git repo
  cd_=$(git -C "$d" rev-parse --git-common-dir 2>/dev/null)
  case $cd_ in /*) ;; *) cd_="$d/$cd_";; esac
  gd=$(cd -P "$cd_" 2>/dev/null && pwd -P) || return 0
  pd=$(cd -P "$pd" 2>/dev/null && pwd -P) || return 0
  [ "$pd" = "$gd" ] || return 0
  [ "$(git -C "$d" worktree list --porcelain 2>/dev/null | grep -c '^worktree ')" -gt 1 ] && block "edit file di worktree utama dilarang: $f. Kerjakan di checkout workspace domain (lihat rules.md, Workspace & worktree)."
  return 0
}

# transitionJiraIssue: only transition ids allowed for the project in ${AGENT_WORKFLOW_STATE:-~/.agent-workflow}/jira-transitions.json
check_jira() {
  local cfg=${AGENT_WORKFLOW_STATE:-$HOME/.agent-workflow}/jira-transitions.json
  local key id proj
  key=$(printf '%s' "$input" | "$JQ" -r '.tool_input.issueIdOrKey // empty' 2>/dev/null)
  id=$(printf '%s' "$input" | "$JQ" -r '.tool_input.transition.id // empty' 2>/dev/null)
  proj=$(printf '%s' "$key" | sed -E 's/-[0-9]+$//')
  "$JQ" -e type "$cfg" >/dev/null 2>&1 || block "config transisi Jira tidak ada/rusak ($cfg). Minta user: jalankan setup transisi."
  "$JQ" -e --arg p "$proj" 'has($p)' "$cfg" >/dev/null 2>&1 || block "project '$proj' belum punya daftar transisi. Minta user: jalankan setup transisi."
  "$JQ" -e --arg p "$proj" --arg i "$id" '.[$p].allow // [] | map(tostring) | index($i) != null' "$cfg" >/dev/null 2>&1 ||
    block "transisi id '$id' untuk $proj tidak diizinkan. Done hanya dipindah kolega; pindahkan hanya ke status yang ada di daftar allow."
}

input=$(cat)
tool=$(printf '%s' "$input" | "$JQ" -r '.tool_name // empty' 2>/dev/null) || exit 0
cwd=$(printf '%s' "$input" | "$JQ" -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd=$PWD

# read-only audit mode (/audit-issue): env AGENT_AUDIT=1, or bin/audit-mode.sh marked one of our
# ancestor pids, i.e. the Claude session running this hook (SPV). The SPV's guard records
# session-<session_id> -> pid so its teammates (agent teams, not our descendants; their Claude runs
# with --parent-session-id) are audit too while that pid marker exists.
# shortcut: shell writes (sed -i, > file) are not caught in audit mode; upgrade with a sandbox if agents start writing via shell
AUDIT=''
if [ "${AGENT_AUDIT:-}" = 1 ]; then
  AUDIT=1
else
  mk=${AGENT_WORKFLOW_STATE:-$HOME/.agent-workflow}/audit p=$$
  if [ -d "$mk" ]; then
    for _ in 1 2 3 4 5 6 7 8; do
      if [ -f "$mk/$p" ]; then
        AUDIT=1
        sid=$(printf '%s' "$input" | "$JQ" -r '.session_id // empty' 2>/dev/null)
        [ -n "$sid" ] && echo "$p" > "$mk/session-$sid"
        break
      fi
      read -r pp cmd < <(ps -o ppid=,command= -p "$p" 2>/dev/null)
      case $cmd in *' --parent-session-id '*)
        sid=${cmd#* --parent-session-id }; sid=${sid%% *}
        lead=$(cat "$mk/session-$sid" 2>/dev/null)
        [ -n "$lead" ] && [ -f "$mk/$lead" ] && { AUDIT=1; break; } ;;
      esac
      p=$pp
      [ -n "$p" ] && [ "$p" -gt 1 ] || break
    done
  fi
fi

case $tool in
  Bash) check_Bash;;
  Edit|Write|MultiEdit|NotebookEdit) check_edit;;
  mcp__claude_ai_Atlassian__*)
    if [ -n "$AUDIT" ]; then
      case $tool in *__create*|*__edit*|*__add*|*__update*|*__transition*) audit_block "$tool";; esac
    elif [ "$tool" = mcp__claude_ai_Atlassian__transitionJiraIssue ]; then
      check_jira
    fi;;
esac
exit 0
