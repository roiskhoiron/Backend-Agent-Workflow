#!/usr/bin/env bash
# guard.sh accepts the hook input of Claude Code, Codex, Gemini CLI, and Cursor
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
G="$REPO/hooks/guard.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export AGENT_WORKFLOW_STATE="$T/st"; mkdir -p "$AGENT_WORKFLOW_STATE"
echo db.prod.example.com > "$AGENT_WORKFLOW_STATE/prod-hosts.txt"
M="$T/main"; L="$T/linked"
git init -q "$M"; git -C "$M" -c user.name=t -c user.email=t@t commit -q --allow-empty -m i
git -C "$M" worktree add -q -b feat/x "$L"
run() { printf '%s' "$2" | "$G" >/dev/null 2>"$T/err"; assert_eq "$1" "$?" "[$1] $3"; }

# Claude Code + Codex (same shape)
run 2 '{"tool_name":"Bash","tool_input":{"command":"git push upstream main"},"cwd":"/tmp"}' "claude/codex: push upstream"
run 0 '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"/tmp","turn_id":"1"}' "codex: ls"
# Cursor beforeShellExecution
run 2 '{"hook_event_name":"beforeShellExecution","command":"psql -h db.prod.example.com","cwd":"/tmp"}' "cursor: prod db"
run 2 '{"hook_event_name":"beforeShellExecution","command":"gh issue close 3","workspace_roots":["/tmp"]}' "cursor: close issue (cwd from workspace_roots)"
run 0 '{"hook_event_name":"beforeShellExecution","command":"npm test","cwd":"/tmp"}' "cursor: npm test"
assert_eq yes "$(grep -q 'DIBLOKIR' "$T/err" || echo yes)" "cursor allow: no message"
# Gemini BeforeTool
run 2 '{"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"docker system prune -af"},"cwd":"/tmp"}' "gemini: docker prune"
run 0 '{"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"docker ps"},"cwd":"/tmp"}' "gemini: docker ps"
run 2 "$(jq -cn --arg d "$T" '{tool_name:"run_shell_command",tool_input:{command:"rm -rf ../linked",directory:"main"},cwd:$d}')" "gemini: directory joins cwd for rm -r check"
run 2 "$(jq -cn --arg p "$M/a.txt" --arg c "$M" '{tool_name:"write_file",tool_input:{file_path:$p,content:"x"},cwd:$c}')" "gemini: write_file in primary worktree"
run 0 "$(jq -cn --arg p "$L/a.txt" --arg c "$L" '{tool_name:"replace",tool_input:{file_path:$p},cwd:$c}')" "gemini: replace in linked worktree"
run 0 '{"tool_name":"read_file","tool_input":{"file_path":"/etc/hosts"}}' "gemini: other tools pass"
run 0 'not json' "malformed passes"
exit $((FAILS > 0))
