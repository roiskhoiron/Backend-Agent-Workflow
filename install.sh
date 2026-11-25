#!/usr/bin/env bash
# Install the Backend agent workflow into one or more AI coding agents, globally or for one project.
#
# Usage: install.sh [--agent LIST] [--scope global|project] [--project DIR] [--home DIR] [--force] [--yes]
#   --agent   comma list of: claude, codex, gemini, cursor, generic   (default: claude)
#   --scope   global = for every project of this user (default); project = only inside --project DIR
#   --project project folder for --scope project (default: current folder)
#   --home    home folder to install into (tests; default $HOME)
#   --force   replace skill/agent links that point into ANOTHER repo (e.g. the Mobile workflow)
#   --yes     never ask; without --agent/--scope and with a terminal, install.sh asks interactively
# Idempotent: run again to update. Every changed config file is backed up once as <file>.bak-backend-workflow.
#
# What each agent gets (G = global path, P = project path):
#   claude : skills G ~/.claude/skills  P .claude/skills; subagents (agents/*.md) .claude/agents;
#            instructions G ~/.claude/CLAUDE.md  P CLAUDE.md; guard hook PreToolUse in .claude/settings.json
#   codex  : skills G ~/.agents/skills  P .agents/skills; instructions G ~/.codex/AGENTS.md  P AGENTS.md;
#            guard hook PreToolUse in G ~/.codex/hooks.json  P .codex/hooks.json (Codex asks you to trust it)
#   gemini : skills G ~/.agents/skills  P .agents/skills; instructions G ~/.gemini/GEMINI.md  P GEMINI.md;
#            guard hook BeforeTool in .gemini/settings.json
#   cursor : skills G ~/.cursor/skills  P .cursor/skills; instructions P AGENTS.md (G: none, Cursor global
#            rules live in its settings); guard hook beforeShellExecution in .cursor/hooks.json
#   generic: skills G ~/.agents/skills  P .agents/skills; instructions P AGENTS.md (G: none); no hook
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd -P)"
DEST="$HOME" FORCE=0 YES=0 AGENTS_ARG='' SCOPE='' PROJ=''
usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
while [ $# -gt 0 ]; do
  case $1 in
    --agent|--agents) AGENTS_ARG="${2:?--agent butuh daftar}"; shift 2;;
    --agent=*|--agents=*) AGENTS_ARG="${1#*=}"; shift;;
    --scope) SCOPE="${2:?--scope butuh global|project}"; shift 2;;
    --scope=*) SCOPE="${1#*=}"; shift;;
    --project) PROJ="${2:?--project butuh folder}"; shift 2;;
    --project=*) PROJ="${1#*=}"; shift;;
    --home) DEST="${2:?--home butuh folder}"; shift 2;;
    --force) FORCE=1; shift;;
    --yes|-y) YES=1; shift;;
    -h|--help) usage;;
    *) echo "argumen tidak dikenal: $1" >&2; usage;;
  esac
done
command -v jq >/dev/null || { echo "jq tidak ditemukan (brew install jq / apt install jq)" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 tidak ditemukan" >&2; exit 1; }

# ---- interactive choice (only with a terminal and nothing given) ----
if [ -z "$AGENTS_ARG$SCOPE" ] && [ "$YES" = 0 ] && [ -t 0 ]; then
  echo "Pasang workflow Backend untuk AI coding agent apa? (boleh lebih dari satu, pisahkan koma)"
  echo "  1) Claude Code   2) Codex CLI   3) Gemini CLI   4) Cursor   5) Agent lain (AGENTS.md: opencode, Copilot, Windsurf, ...)"
  read -r -p "Pilihan [1]: " ans; ans=${ans:-1}
  AGENTS_ARG=$(printf '%s' "$ans" | tr ',' ' ' | xargs -n1 | sed 's/^1$/claude/;s/^2$/codex/;s/^3$/gemini/;s/^4$/cursor/;s/^5$/generic/' | paste -sd, -)
  echo "Cakupan instalasi?"
  echo "  1) global  - berlaku di semua project di komputer ini"
  echo "  2) project - hanya untuk satu project"
  read -r -p "Pilihan [1]: " ans
  case ${ans:-1} in 2|project) SCOPE=project; read -r -p "Folder project [$PWD]: " PROJ; PROJ=${PROJ:-$PWD};; *) SCOPE=global;; esac
fi
AGENTS_ARG=${AGENTS_ARG:-claude}; SCOPE=${SCOPE:-global}
case $SCOPE in global|project) ;; *) echo "--scope harus global atau project" >&2; exit 2;; esac
IFS=, read -ra SEL <<< "$AGENTS_ARG"
for a in "${SEL[@]}"; do case $a in claude|codex|gemini|cursor|generic) ;; *) echo "agent tidak dikenal: $a (claude, codex, gemini, cursor, generic)" >&2; exit 2;; esac; done
if [ "$SCOPE" = project ]; then
  PROJ=${PROJ:-$PWD}
  [ -d "$PROJ" ] || { echo "folder project tidak ada: $PROJ" >&2; exit 2; }
  PROJ=$(cd "$PROJ" && pwd -P)
  case $PROJ in "$REPO"|"$REPO"/*) echo "jangan pasang ke dalam repo workflow ini sendiri" >&2; exit 2;; esac
  ROOT=$PROJ
else
  ROOT=$DEST
fi

# ---- plan: links (source -> link), instruction files, hooks ----
links=() instr=() hooks=() notes=()
add_skills() { # skills dir
  local d n
  for d in "$REPO"/skills/*/; do
    n=$(basename "$d"); [ "$n" = _shared ] && continue   # shared docs are read via $AGENT_WORKFLOW_DIR
    links+=("${d%/}" "$1/$n")
  done
}
for a in "${SEL[@]}"; do
  case $a in
    claude)
      add_skills "$ROOT/.claude/skills"
      for f in "$REPO"/agents/*.md; do links+=("$f" "$ROOT/.claude/agents/$(basename "$f")"); done
      [ "$SCOPE" = global ] && instr+=("$ROOT/.claude/CLAUDE.md" "Claude Code") || instr+=("$ROOT/CLAUDE.md" "Claude Code")
      hooks+=(claude "$ROOT/.claude/settings.json");;
    codex)
      add_skills "$ROOT/.agents/skills"
      [ "$SCOPE" = global ] && instr+=("$ROOT/.codex/AGENTS.md" "Codex CLI") || instr+=("$ROOT/AGENTS.md" "Codex CLI")
      hooks+=(codex "$ROOT/.codex/hooks.json")
      notes+=("Codex: buka Codex dan setujui (trust) hook guard di $ROOT/.codex/hooks.json; hook yang belum di-trust tidak jalan.");;
    gemini)
      add_skills "$ROOT/.agents/skills"
      [ "$SCOPE" = global ] && instr+=("$ROOT/.gemini/GEMINI.md" "Gemini CLI") || instr+=("$ROOT/GEMINI.md" "Gemini CLI")
      hooks+=(gemini "$ROOT/.gemini/settings.json");;
    cursor)
      add_skills "$ROOT/.cursor/skills"
      if [ "$SCOPE" = project ]; then instr+=("$ROOT/AGENTS.md" "Cursor")
      else notes+=("Cursor global: instruksi tidak berupa file. Tambahkan isi templates/agent-instructions.md (dengan path repo ini) di Cursor Settings → Rules, atau pasang juga --scope project."); fi
      hooks+=(cursor "$ROOT/.cursor/hooks.json");;
    generic)
      add_skills "$ROOT/.agents/skills"
      if [ "$SCOPE" = project ]; then instr+=("$ROOT/AGENTS.md" "agent umum (AGENTS.md)")
      else notes+=("Agent lain, global: tidak ada lokasi instruksi global yang standar. Pasang --scope project per project (AGENTS.md), atau salin isi templates/agent-instructions.md ke pengaturan agent itu."); fi
      notes+=("Agent lain: tidak ada hook, pagar keamanan TIDAK aktif otomatis; aturan rules.md tetap berlaku.");;
  esac
done

# de-duplicate links (codex/gemini/generic share .agents/skills)
seen=$'\n' ulinks=()   # (no associative arrays: macOS ships bash 3.2)
for ((i = 0; i < ${#links[@]}; i += 2)); do
  l=${links[$((i + 1))]}; case $seen in *$'\n'"$l"$'\n'*) continue;; esac; seen+="$l"$'\n'; ulinks+=("${links[$i]}" "$l")
done

# ---- conflict check first, so a refused install changes nothing ----
conflicts=()
for ((i = 0; i < ${#ulinks[@]}; i += 2)); do
  l=${ulinks[$((i + 1))]}
  if [ -L "$l" ]; then
    t=$(readlink "$l"); case $t in "$REPO"/*) ;; *) conflicts+=("$l -> $t");; esac
  elif [ -e "$l" ]; then conflicts+=("$l (file/folder biasa, bukan symlink)"); fi
done
if [ ${#conflicts[@]} -gt 0 ] && [ "$FORCE" = 0 ]; then
  echo "Berhenti: nama ini sudah dipakai workflow/skill lain (mis. mobiledev-agent-workflow):" >&2
  printf '  %s\n' "${conflicts[@]}" >&2
  echo "Satu agent + cakupan = satu workflow. Jalankan ulang dengan --force untuk menggantinya dengan workflow Backend." >&2
  exit 3
fi

backup() { [ -e "$1" ] && [ ! -e "$1.bak-backend-workflow" ] && cp "$1" "$1.bak-backend-workflow"; return 0; }
for ((i = 0; i < ${#ulinks[@]}; i += 2)); do
  l=${ulinks[$((i + 1))]}; mkdir -p "$(dirname "$l")"
  [ -L "$l" ] || [ ! -e "$l" ] || rm -rf "$l"   # --force over a plain file/folder
  ln -sfn "${ulinks[$i]}" "$l"
done
# old Claude install linked the shared docs as a skill; no longer needed
[ -L "$ROOT/.claude/skills/_backend-workflow-shared" ] && case $(readlink "$ROOT/.claude/skills/_backend-workflow-shared") in "$REPO"/*) rm "$ROOT/.claude/skills/_backend-workflow-shared";; esac

# ---- instruction section (replaced in place between markers on re-install) ----
T="$REPO/templates/agent-instructions.md"
write_instr() { # file agent-name
  mkdir -p "$(dirname "$1")"; backup "$1"
  python3 -I - "$1" "$T" "$REPO" "$2" <<'PY'
import os, re, sys
path, tpl, repo, agent = sys.argv[1:]
block = open(tpl).read().replace("__AGENT_WORKFLOW_DIR__", repo).replace("__AGENT__", agent).strip() + "\n"
old = open(path).read() if os.path.exists(path) else ""
start, end = "<!-- backend-agent-workflow:start", "<!-- backend-agent-workflow:end -->"
if start in old and end in old:
    a = old.index(start); b = old.index(end) + len(end)
    new = old[:a] + block.rstrip("\n") + old[b:]
else:
    # drop the pre-marker section of older installs ("# Jira agent workflow (Backend)" ... up to next "# " heading)
    old = re.sub(r"(?ms)^# (Jira agent workflow \(Backend\)|Agent workflow Backend)[^\n]*\n.*?(?=^# |\Z)", "", old)
    new = (old.rstrip("\n") + "\n\n" if old.strip() else "") + block
open(path, "w").write(new)
PY
}
for ((i = 0; i < ${#instr[@]}; i += 2)); do write_instr "${instr[$i]}" "${instr[$((i + 1))]}"; done

# ---- guard hook per agent ----
CMD="\"$REPO/hooks/guard.sh\""
hook_json() { # agent file
  local f=$2 tmp; mkdir -p "$(dirname "$f")"
  if [ -f "$f" ]; then
    jq -e type "$f" >/dev/null 2>&1 || { echo "Lewati hook: $f bukan JSON valid" >&2; return 0; }
    backup "$f"
  else
    echo '{}' > "$f"   # new file: nothing to back up
  fi
  tmp=$(mktemp)
  case $1 in
    claude|codex|gemini)
      local ev m
      case $1 in
        claude) ev=PreToolUse m='Bash|Edit|Write|MultiEdit|NotebookEdit|mcp__claude_ai_Atlassian__.*';;
        codex)  ev=PreToolUse m='Bash';;
        gemini) ev=BeforeTool m='run_shell_command|write_file|replace';;
      esac
      # one guard entry: an existing */guard.sh entry (also the Mobile one) is replaced by ours
      jq --arg ev "$ev" --arg cmd "$CMD" --arg m "$m" '
        def isguard: any((.hooks // [])[]?; .command | tostring | test("/guard\\.sh\"?$"));
        .hooks[$ev] = ((.hooks[$ev] // [])
          | if any(.[]; isguard) then map(if isguard then .matcher = $m | .hooks = [{type:"command",command:$cmd}] else . end)
            else . + [{matcher:$m, hooks:[{type:"command",command:$cmd}]}] end)' "$f" > "$tmp";;
    cursor)
      jq --arg cmd "$CMD" '
        .version = (.version // 1)
        | .hooks.beforeShellExecution = (((.hooks.beforeShellExecution // []) | map(select(.command | tostring | test("/guard\\.sh\"?$") | not))) + [{command:$cmd}])' "$f" > "$tmp";;
  esac
  mv "$tmp" "$f"
}
for ((i = 0; i < ${#hooks[@]}; i += 2)); do hook_json "${hooks[$i]}" "${hooks[$((i + 1))]}"; done

mkdir -p "$DEST/.agent-workflow/logs"
echo "Terpasang: agent=${SEL[*]} cakupan=$SCOPE lokasi=$ROOT"
[ -f "$DEST/.agent-workflow/prod-hosts.txt" ] || echo "Catatan: isi $DEST/.agent-workflow/prod-hosts.txt (host database/API production, satu per baris) supaya guard mengenalinya."
for ((i = 0; i < ${#notes[@]}; i++)); do echo "Catatan: ${notes[$i]}"; done
[ "$SCOPE" = project ] && echo "Catatan: file yang dibuat di project (.claude/, .agents/, AGENTS.md, ...) berisi symlink ke $REPO; tambahkan ke .gitignore bila tidak ingin ikut ter-commit."
exit 0
