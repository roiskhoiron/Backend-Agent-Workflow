#!/usr/bin/env bash
# install.sh: agents (claude, codex, gemini, cursor, generic) x scope (global, project)
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
I="$REPO/install.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
yes_() { [ "$@" ] && echo yes || echo no; }
islink() { [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ] && echo yes || echo no; }
guard_count() { jq --arg e "$2" '[(.hooks[$e] // [])[] | select(any(.hooks[]?; .command|test("guard.sh")))] | length' "$1"; }

# ---------- default = claude, global (backward compatible) ----------
H="$T/h1"; mkdir -p "$H/.claude"
echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}' > "$H/.claude/settings.json"
assert_exit 0 "default install" -- bash "$I" --home "$H" --yes
assert_exit 0 "default install again (idempotent)" -- bash "$I" --home "$H" --yes
S="$H/.claude/settings.json"
assert_eq yes "$(islink "$H/.claude/skills/develop-tiket" "$REPO/skills/develop-tiket")" "claude: flow skill"
assert_eq yes "$(islink "$H/.claude/skills/write-migration" "$REPO/skills/write-migration")" "claude: internal skill"
assert_eq no "$(yes_ -e "$H/.claude/skills/_shared")" "claude: _shared not linked as a skill"
assert_eq yes "$(islink "$H/.claude/agents/coder.md" "$REPO/agents/coder.md")" "claude: subagent"
assert_eq 1 "$(guard_count "$S" PreToolUse)" "claude: guard hook once"
assert_eq 1 "$(jq '[.hooks.PreToolUse[]|select(.hooks[0].command=="rtk hook claude")]|length' "$S")" "claude: other hook kept"
assert_eq yes "$(yes_ -f "$S.bak-backend-workflow")" "claude: settings backup"
assert_eq 1 "$(grep -c 'backend-agent-workflow:start' "$H/.claude/CLAUDE.md")" "claude: instruction block once"
assert_eq yes "$(grep -qF "AGENT_WORKFLOW_DIR=$REPO" "$H/.claude/CLAUDE.md" && echo yes || echo no)" "claude: repo path written"
assert_eq yes "$(grep -q 'Agent ini: Claude Code' "$H/.claude/CLAUDE.md" && echo yes || echo no)" "claude: agent named"
c=$(jq -r '[.hooks.PreToolUse[]|select(.hooks[0].command|test("guard.sh"))][0].hooks[0].command' "$S")
assert_eq 0 "$(echo '{"tool_name":"Read"}' | sh -c "$c" >/dev/null 2>&1; echo $?)" "claude: hook command runs via shell"
# older install had a plain section + _backend-workflow-shared skill link: both cleaned up
H0="$T/h0"; mkdir -p "$H0/.claude/skills"
printf '# Notes\nkeep me\n\n# Jira agent workflow (Backend)\n- old line\n\n# Other\nkeep too\n' > "$H0/.claude/CLAUDE.md"
ln -s "$REPO/skills/_shared" "$H0/.claude/skills/_backend-workflow-shared"
bash "$I" --home "$H0" --yes >/dev/null
assert_eq 0 "$(grep -c 'old line\|Jira agent workflow' "$H0/.claude/CLAUDE.md")" "upgrade: old section removed"
assert_eq 2 "$(grep -c 'keep' "$H0/.claude/CLAUDE.md")" "upgrade: user's own sections kept"
assert_eq no "$(yes_ -e "$H0/.claude/skills/_backend-workflow-shared")" "upgrade: old shared link removed"

# ---------- all agents, global ----------
H="$T/h2"; mkdir -p "$H"
assert_exit 0 "all agents global" -- bash "$I" --home "$H" --agent claude,codex,gemini,cursor,generic --scope global
assert_eq yes "$(islink "$H/.agents/skills/develop-tiket" "$REPO/skills/develop-tiket")" "codex/gemini/generic: ~/.agents/skills"
assert_eq yes "$(islink "$H/.cursor/skills/validate-tiket" "$REPO/skills/validate-tiket")" "cursor: ~/.cursor/skills"
assert_eq no "$(yes_ -e "$H/.agents/agents")" "subagents only for claude"
assert_eq yes "$(grep -q 'Agent ini: Codex CLI' "$H/.codex/AGENTS.md" && echo yes || echo no)" "codex: ~/.codex/AGENTS.md"
assert_eq yes "$(grep -q 'Agent ini: Gemini CLI' "$H/.gemini/GEMINI.md" && echo yes || echo no)" "gemini: ~/.gemini/GEMINI.md"
assert_eq 1 "$(guard_count "$H/.codex/hooks.json" PreToolUse)" "codex: PreToolUse guard"
assert_eq Bash "$(jq -r '.hooks.PreToolUse[0].matcher' "$H/.codex/hooks.json")" "codex: matcher Bash"
assert_eq 1 "$(guard_count "$H/.gemini/settings.json" BeforeTool)" "gemini: BeforeTool guard"
assert_eq "run_shell_command|write_file|replace" "$(jq -r '.hooks.BeforeTool[0].matcher' "$H/.gemini/settings.json")" "gemini: matcher"
assert_eq 1 "$(jq '.version' "$H/.cursor/hooks.json")" "cursor: hooks.json version 1"
assert_eq 1 "$(jq '[.hooks.beforeShellExecution[]|select(.command|test("guard.sh"))]|length' "$H/.cursor/hooks.json")" "cursor: beforeShellExecution guard"
bash "$I" --home "$H" --agent cursor,gemini --scope global >/dev/null
assert_eq 1 "$(jq '[.hooks.beforeShellExecution[]|select(.command|test("guard.sh"))]|length' "$H/.cursor/hooks.json")" "cursor: still once after re-install"
assert_eq 1 "$(grep -c 'backend-agent-workflow:start' "$H/.gemini/GEMINI.md")" "gemini: block once after re-install"
out=$(bash "$I" --home "$H" --agent generic --scope global)
assert_eq yes "$(printf '%s' "$out" | grep -q 'pagar keamanan TIDAK aktif' && echo yes || echo no)" "generic: warns there is no hook"

# ---------- project scope ----------
H="$T/h3"; P="$T/proj"; mkdir -p "$H" "$P"; git init -q "$P"
printf '# Project rules\nexisting\n' > "$P/AGENTS.md"
assert_exit 0 "project scope codex+cursor+claude" -- bash "$I" --home "$H" --agent codex,cursor,claude --scope project --project "$P"
assert_eq yes "$(islink "$P/.agents/skills/develop-tiket" "$REPO/skills/develop-tiket")" "project: .agents/skills"
assert_eq yes "$(islink "$P/.cursor/skills/develop-tiket" "$REPO/skills/develop-tiket")" "project: .cursor/skills"
assert_eq yes "$(islink "$P/.claude/skills/develop-tiket" "$REPO/skills/develop-tiket")" "project: .claude/skills"
assert_eq yes "$(islink "$P/.claude/agents/qa.md" "$REPO/agents/qa.md")" "project: .claude/agents"
assert_eq 1 "$(grep -c 'backend-agent-workflow:start' "$P/AGENTS.md")" "project: AGENTS.md block once (codex+cursor share it)"
assert_eq yes "$(grep -q '^existing' "$P/AGENTS.md" && echo yes || echo no)" "project: user's AGENTS.md content kept"
assert_eq yes "$(yes_ -f "$P/CLAUDE.md")" "project: CLAUDE.md"
assert_eq 1 "$(guard_count "$P/.codex/hooks.json" PreToolUse)" "project: .codex/hooks.json"
assert_eq yes "$(yes_ -f "$P/.cursor/hooks.json")" "project: .cursor/hooks.json"
assert_eq no "$(yes_ -e "$P/.cursor/hooks.json.bak-backend-workflow")" "no backup for a file install.sh created itself"
assert_eq yes "$(yes_ -f "$P/.claude/settings.json")" "project: .claude/settings.json"
assert_eq no "$(yes_ -e "$H/.claude")" "project scope leaves home untouched"
assert_eq yes "$(yes_ -d "$H/.agent-workflow/logs")" "state dir stays per machine"
assert_exit 2 "project scope: missing folder" -- bash "$I" --home "$H" --scope project --project "$T/nope"
assert_exit 2 "project scope: not into the workflow repo itself" -- bash "$I" --home "$H" --scope project --project "$REPO"

# ---------- conflicts with another workflow ----------
H="$T/h4"; M="$T/mobiledev-agent-workflow"
mkdir -p "$H/.claude/skills" "$H/.claude/agents" "$M/skills/develop-tiket" "$M/hooks" "$M/agents"; touch "$M/agents/coder.md"
ln -s "$M/skills/develop-tiket" "$H/.claude/skills/develop-tiket"; ln -s "$M/agents/coder.md" "$H/.claude/agents/coder.md"
jq -n --arg c "\"$M/hooks/guard.sh\"" '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$c}]}]}}' > "$H/.claude/settings.json"
assert_exit 3 "conflict -> exit 3" -- bash "$I" --home "$H" --yes
assert_eq yes "$(islink "$H/.claude/skills/develop-tiket" "$M/skills/develop-tiket")" "refused: link untouched"
assert_eq no "$(yes_ -e "$H/.claude/skills/write-migration")" "refused: nothing linked"
assert_exit 0 "--force replaces" -- bash "$I" --home "$H" --yes --force
assert_eq yes "$(islink "$H/.claude/skills/develop-tiket" "$REPO/skills/develop-tiket")" "forced: link ours"
assert_eq "\"$REPO/hooks/guard.sh\"" "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$H/.claude/settings.json")" "forced: other guard replaced"
assert_eq 1 "$(jq '.hooks.PreToolUse|length' "$H/.claude/settings.json")" "forced: one guard entry"

# ---------- bad input ----------
assert_exit 2 "unknown agent" -- bash "$I" --home "$T/h5" --agent vim
assert_exit 2 "bad scope" -- bash "$I" --home "$T/h5" --scope team
assert_exit 2 "unknown option" -- bash "$I" --nope
mkdir -p "$T/h6/.codex"; echo 'not json' > "$T/h6/.codex/hooks.json"
assert_exit 0 "invalid hooks.json: skipped, not destroyed" -- bash "$I" --home "$T/h6" --agent codex
assert_eq "not json" "$(cat "$T/h6/.codex/hooks.json")" "invalid hooks.json left as is"

# repo path with a space
R="$T/my repo"; mkdir -p "$R"; cp -R "$REPO/install.sh" "$REPO/hooks" "$REPO/skills" "$REPO/agents" "$REPO/templates" "$R/"
assert_exit 0 "install from path with space" -- bash "$R/install.sh" --home "$T/h7" --agent claude,cursor
c=$(jq -r '.hooks.beforeShellExecution[0].command' "$T/h7/.cursor/hooks.json")
assert_eq 0 "$(echo '{"command":"ls","cwd":"/tmp"}' | sh -c "$c" >/dev/null 2>&1; echo $?)" "space path: cursor hook runs"
exit $((FAILS > 0))
