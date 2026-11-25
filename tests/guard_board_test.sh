#!/usr/bin/env bash
# guard.sh: GitHub/GitLab board rules (ticket-platform.md) - never close, status moves only to allowed values
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
G="$REPO/hooks/guard.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export AGENT_WORKFLOW_STATE="$T/st"; mkdir -p "$AGENT_WORKFLOW_STATE"
check() { # expected command
  jq -cn --arg c "$2" --arg d "$T" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | "$G" >/dev/null 2>"$T/err"
  assert_eq "$1" "$?" "[$1] $2"
}

# closing = Done: always blocked, even without any config
check 2 'gh issue close 12 -R acme/api'
check 2 'glab issue close 12 -R grp/api'
check 2 'gh issue delete 12'
check 2 'gh project item-delete 3 --owner acme --id X'
check 2 'gh issue edit 12 --state=closed'
assert_eq yes "$(grep -q 'Done hanya oleh manusia' "$T/err" && echo yes || echo no)" "message: Done by humans"
# read/comment always fine
check 0 'gh issue view 12 -R acme/api --comments'
check 0 'gh issue comment 12 -R acme/api --body-file /tmp/c.md'
check 0 'glab issue note 12 -R grp/api -m "halo"'
check 0 'gh issue list -R acme/api --search "orders in:title"'
check 0 'gh pr create --draft --title "API-12"'
# GitHub Projects status: option must be allowed for that project
check 2 'gh project item-edit --id I1 --project-id PVT_1 --field-id F1 --single-select-option-id opt-todo'   # no config
cat > "$AGENT_WORKFLOW_STATE/board-transitions.json" <<'J'
{"github:PVT_1":{"allow":["opt-todo","opt-prog","opt-rtr"]},
 "gitlab:grp/api":{"allow":["workflow::todo","workflow::in progress","workflow::ready to review"],
   "status":["workflow::todo","workflow::in progress","workflow::ready to review","workflow::done"]},
 "github-label:acme/api":{"allow":["status: ready to review"],"status":["status: ready to review","status: done"]}}
J
check 0 'gh project item-edit --id I1 --project-id PVT_1 --field-id F1 --single-select-option-id opt-rtr'
check 0 'gh project item-edit --id I1 --project-id=PVT_1 --field-id F1 --single-select-option-id=opt-prog'
check 2 'gh project item-edit --id I1 --project-id PVT_1 --field-id F1 --single-select-option-id opt-done'
check 2 'gh project item-edit --id I1 --project-id PVT_9 --field-id F1 --single-select-option-id opt-rtr'
check 0 'gh project item-edit --id I1 --project-id PVT_1 --field-id F2 --text "catatan"'
# label boards
check 0 'glab issue update 12 -R grp/api --label "workflow::ready to review" --unlabel "workflow::in progress"'
check 2 'glab issue update 12 -R grp/api --label "workflow::done"'
check 2 'glab issue update 12 -R grp/api --label bug,workflow::done'
check 0 'glab issue update 12 -R grp/api --label bug,backend'
check 0 'gh issue edit 12 --add-label "status: ready to review" --remove-label "status: in progress"'
check 2 'gh issue edit 12 --add-label "status: done"'
check 0 'gh issue edit 12 --remove-label "status: done"'
# audit mode: board read-only
export AGENT_AUDIT=1
check 0 'gh issue view 12'
check 0 'glab issue list -R grp/api'
check 2 'gh issue comment 12 --body x'
check 2 'gh issue create --title x'
check 2 'glab issue note 12 -m x'
check 2 'gh project item-edit --id I1 --project-id PVT_1 --field-id F1 --single-select-option-id opt-rtr'
exit $((FAILS > 0))
