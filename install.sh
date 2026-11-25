#!/usr/bin/env bash
# Usage: install.sh [--home DIR] [--force]  (default $HOME). Idempotent.
# Links skills, agents, and the shared docs into ~/.claude, adds the guard hook to settings.json,
# and appends the workflow section to the global CLAUDE.md once.
# Skill and agent names are the same as the Mobile workflow (/develop-tiket, coder.md, ...): when one of them
# is already a symlink into ANOTHER repo, install stops (one machine = one workflow) unless --force.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd -P)"
DEST="$HOME" FORCE=0
while [ $# -gt 0 ]; do
  case $1 in
    --home) DEST="${2:?--home butuh folder}"; shift 2;;
    --force) FORCE=1; shift;;
    *) echo "usage: $0 [--home DIR] [--force]" >&2; exit 2;;
  esac
done
C="$DEST/.claude"
mkdir -p "$C/skills" "$C/agents"
command -v jq >/dev/null || { echo "jq tidak ditemukan (brew install jq / apt install jq)" >&2; exit 1; }

# pairs: <source> <link>
links=()
for d in "$REPO"/skills/*/; do
  n=$(basename "$d"); [ "$n" = _shared ] && n=_backend-workflow-shared
  links+=("${d%/}" "$C/skills/$n")
done
for f in "$REPO"/agents/*.md; do [ -e "$f" ] && links+=("$f" "$C/agents/$(basename "$f")"); done

# conflict check first, so a refused install changes nothing
conflicts=()
for ((i = 0; i < ${#links[@]}; i += 2)); do
  l=${links[$((i + 1))]}
  if [ -L "$l" ]; then
    t=$(readlink "$l")
    case $t in "$REPO"/*) ;; *) conflicts+=("$l -> $t");; esac
  elif [ -e "$l" ]; then
    conflicts+=("$l (file/folder biasa, bukan symlink)")
  fi
done
if [ ${#conflicts[@]} -gt 0 ] && [ "$FORCE" = 0 ]; then
  echo "Berhenti: nama ini sudah dipakai workflow/skill lain (mis. mobiledev-agent-workflow):" >&2
  printf '  %s\n' "${conflicts[@]}" >&2
  echo "Satu mesin = satu workflow. Jalankan ulang dengan --force untuk menggantinya dengan workflow Backend." >&2
  exit 3
fi
for ((i = 0; i < ${#links[@]}; i += 2)); do
  l=${links[$((i + 1))]}
  [ -L "$l" ] || [ ! -e "$l" ] || rm -rf "$l"   # --force over a plain file/folder
  ln -sfn "${links[$i]}" "$l"
done

S="$C/settings.json"
[ -f "$S" ] || echo '{}' > "$S"
[ -e "$S.bak-backend-workflow" ] || cp "$S" "$S.bak-backend-workflow"  # keep the first original
tmp=$(mktemp)
# one guard hook: an existing */guard.sh entry (also the Mobile one) is replaced by ours
jq --arg cmd "\"$REPO/hooks/guard.sh\"" --arg m 'Bash|Edit|Write|MultiEdit|NotebookEdit|mcp__claude_ai_Atlassian__.*' '
  def isguard: any((.hooks // [])[]?; .command | tostring | test("/guard\\.sh\"?$"));
  .hooks.PreToolUse = ((.hooks.PreToolUse // [])
    | if any(.[]; isguard) then map(if isguard then .matcher = $m | .hooks = [{type:"command",command:$cmd}] else . end)
      else . + [{matcher:$m, hooks:[{type:"command",command:$cmd}]}] end)' "$S" > "$tmp"
mv "$tmp" "$S"

mkdir -p "$DEST/.agent-workflow/logs"
T="$REPO/templates/claude-global.md"
if [ -f "$T" ] && ! grep -qsE '^# (Jira agent workflow \(Backend\)|Agent workflow Backend)' "$C/CLAUDE.md"; then
  { [ -s "$C/CLAUDE.md" ] && echo; cat "$T"; } >> "$C/CLAUDE.md"
fi
[ -f "$DEST/.agent-workflow/prod-hosts.txt" ] || echo "Catatan: isi $DEST/.agent-workflow/prod-hosts.txt (host database/API production, satu per baris) supaya guard mengenalinya."
echo "installed into $DEST"
