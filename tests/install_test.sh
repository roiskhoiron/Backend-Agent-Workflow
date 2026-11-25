#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
H=$(mktemp -d); trap 'rm -rf "$H"' EXIT
mkdir -p "$H/.claude"
echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}' > "$H/.claude/settings.json"

assert_exit 0 "install run 1" -- bash "$REPO/install.sh" --home "$H"
assert_exit 0 "install run 2 (idempotent)" -- bash "$REPO/install.sh" --home "$H"
S="$H/.claude/settings.json"
assert_eq yes "$([ -L "$H/.claude/skills/develop-tiket" ] && echo yes || echo no)" "flow skill symlink"
assert_eq yes "$([ -L "$H/.claude/skills/write-migration" ] && echo yes || echo no)" "internal skill symlink"
assert_eq yes "$([ -L "$H/.claude/skills/_backend-workflow-shared" ] && echo yes || echo no)" "shared symlink"
assert_eq yes "$([ -f "$H/.claude/skills/_backend-workflow-shared/rules.md" ] && echo yes || echo no)" "shared rules reachable"
assert_eq no "$([ -e "$H/.claude/skills/_shared" ] && echo yes || echo no)" "_shared not linked by own name"
assert_eq yes "$([ -L "$H/.claude/agents/coder.md" ] && echo yes || echo no)" "agent symlink"
assert_eq 1 "$(jq '[.hooks.PreToolUse[]|select(.hooks[0].command|test("guard.sh"))]|length' "$S")" "guard hook once"
assert_eq 1 "$(jq '[.hooks.PreToolUse[]|select(.hooks[0].command=="rtk hook claude")]|length' "$S")" "other hook preserved"
assert_eq "\"$REPO/hooks/guard.sh\"" "$(jq -r '.hooks.PreToolUse[]|select(.hooks[0].command|test("guard.sh"))|.hooks[0].command' "$S")" "guard path quoted, from repo"
assert_eq yes "$([ -f "$S.bak-backend-workflow" ] && echo yes || echo no)" "backup made"
assert_eq 1 "$(grep -c '^# Agent workflow Backend' "$H/.claude/CLAUDE.md")" "global CLAUDE.md section once"
assert_eq yes "$([ -d "$H/.agent-workflow/logs" ] && echo yes || echo no)" "state logs dir"
c=$(jq -r '.hooks.PreToolUse[]|select(.hooks[0].command|test("guard.sh"))|.hooks[0].command' "$S")
assert_eq 0 "$(echo '{"tool_name":"Read"}' | sh -c "$c" >/dev/null 2>&1; echo $?)" "hook command runs via shell"

# another workflow (Mobile) already installed: refuse without --force, nothing changed
H2="$H/h2"; M="$H/mobiledev-agent-workflow"
mkdir -p "$H2/.claude/skills" "$H2/.claude/agents" "$M/skills/develop-tiket" "$M/hooks" "$M/agents"
touch "$M/agents/coder.md"
ln -s "$M/skills/develop-tiket" "$H2/.claude/skills/develop-tiket"
ln -s "$M/agents/coder.md" "$H2/.claude/agents/coder.md"
jq -n --arg c "\"$M/hooks/guard.sh\"" '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$c}]}]}}' > "$H2/.claude/settings.json"
assert_exit 3 "conflict with another repo -> exit 3" -- bash "$REPO/install.sh" --home "$H2"
assert_eq "$M/skills/develop-tiket" "$(readlink "$H2/.claude/skills/develop-tiket")" "refused install left the link alone"
assert_eq no "$([ -e "$H2/.claude/skills/write-migration" ] && echo yes || echo no)" "refused install linked nothing"
assert_exit 0 "--force replaces" -- bash "$REPO/install.sh" --home "$H2" --force
assert_eq "$REPO/skills/develop-tiket" "$(readlink "$H2/.claude/skills/develop-tiket")" "link now ours"
assert_eq "\"$REPO/hooks/guard.sh\"" "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$H2/.claude/settings.json")" "the other guard replaced by ours"
assert_eq 1 "$(jq '.hooks.PreToolUse|length' "$H2/.claude/settings.json")" "still one guard entry"
assert_exit 2 "bad option" -- bash "$REPO/install.sh" --nope

# repo path with a space
R="$H/my repo"; mkdir -p "$R"; cp -R "$REPO/install.sh" "$REPO/hooks" "$REPO/skills" "$REPO/agents" "$REPO/templates" "$R/"
H3="$H/home3"; mkdir -p "$H3"
assert_exit 0 "install from path with space" -- bash "$R/install.sh" --home "$H3"
c=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$H3/.claude/settings.json")
assert_eq 0 "$(echo '{"tool_name":"Read"}' | sh -c "$c" >/dev/null 2>&1; echo $?)" "space path: hook runs"
exit $((FAILS > 0))
