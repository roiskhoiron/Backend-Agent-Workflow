#!/usr/bin/env bash
# agents/ + skills/: frontmatter, models, and every cross-reference resolves inside the repo
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"

# fm FILE KEY -> value of KEY in the leading --- frontmatter block (empty if absent)
fm() { awk -v k="$2" 'NR==1&&$0!="---"{exit} NR>1&&$0=="---"{exit} NR>1&&index($0,k": ")==1{print substr($0,length(k)+3)}' "$1"; }

ROLES="spv:opus planner:claude-fable-5-2 validator:opus reviewer:opus release:haiku coder:sonnet qa:sonnet auditor:opus analis:opus pdm:sonnet contract-runner:sonnet hoe:opus eskalasi:claude-fable-5-2 pjm:sonnet"
for pair in $ROLES; do
  n=${pair%%:*} m=${pair#*:} f="$REPO/agents/$n.md"
  assert_eq yes "$([ -f "$f" ] && echo yes || echo no)" "agents/$n.md exists"
  [ -f "$f" ] || continue
  assert_eq "$n" "$(fm "$f" name)" "$n: name"
  assert_eq "$m" "$(fm "$f" model)" "$n: model"
  assert_eq yes "$([ -n "$(fm "$f" description)" ] && echo yes || echo no)" "$n: description"
  tools=$(fm "$f" tools)
  case $n in
    coder|qa)
      assert_eq yes "$([ -n "$tools" ] && echo yes || echo no)" "$n: explicit tools"
      assert_eq no "$(printf '%s' "$tools" | grep -qE 'mcp__|Atlassian|Claude_Docs' && echo yes || echo no)" "$n: no MCP tools" ;;
    *) assert_eq "" "$tools" "$n: inherits all tools" ;;
  esac
done
assert_eq "" "$(ls "$REPO/agents" | grep -vxE "($(echo "$ROLES" | sed -E 's/:[^ ]+//g; s/ /|/g'))\.md")" "no unexpected agent file (product-designer not used)"

# skills: name = folder; flow skills user-invocable, internal skills not
FLOW="validate-tiket develop-tiket rilis-tiket branch-manager audit-issue"
INTERNAL="reproduce-request check-compat write-migration test-integration verify-provider deploy-service deploy-variant"
for n in $FLOW $INTERNAL; do
  f="$REPO/skills/$n/SKILL.md"
  assert_eq yes "$([ -f "$f" ] && echo yes || echo no)" "skills/$n/SKILL.md exists"
  [ -f "$f" ] || continue
  assert_eq "$n" "$(fm "$f" name)" "$n: name"
  assert_eq yes "$([ -n "$(fm "$f" description)" ] && echo yes || echo no)" "$n: description"
done
for n in $FLOW; do assert_eq "" "$(fm "$REPO/skills/$n/SKILL.md" user-invocable)" "$n: user-invocable (default)"; done
for n in $INTERNAL; do assert_eq false "$(fm "$REPO/skills/$n/SKILL.md" user-invocable)" "$n: hidden from / menu"; done

# every reference resolves
files=$(ls "$REPO"/agents/*.md "$REPO"/skills/*/*.md 2>/dev/null)
assert_eq "" "$(cat $files | grep -oE '_agent-workflow-shared/' | head -1)" "no Mobile shared path (_agent-workflow-shared)"
for r in $(cat $files | grep -oE '_backend-workflow-shared/[A-Za-z0-9_-]+\.md' | sort -u); do
  assert_eq yes "$([ -f "$REPO/skills/_shared/${r#*/}" ] && echo yes || echo no)" "ref $r exists"
done
for r in $(cat $files | grep -oE 'AGENT_WORKFLOW_DIR/bin/[A-Za-z0-9_.-]+' | sort -u); do
  assert_eq yes "$([ -f "$REPO/bin/${r##*/}" ] && echo yes || echo no)" "ref $r exists"
done
for r in $(cat $files | grep -oE '~/.claude/agents/[a-z-]+\.md' | sort -u); do
  assert_eq yes "$([ -f "$REPO/agents/${r##*/}" ] && echo yes || echo no)" "ref $r exists"
done
for r in $(cat $files | grep -oE '~/.claude/agents/\{[a-z,-]+\}\.md' | sort -u); do
  for a in $(echo "$r" | sed -E 's/.*\{(.*)\}.*/\1/' | tr , ' '); do
    assert_eq yes "$([ -f "$REPO/agents/$a.md" ] && echo yes || echo no)" "ref agents/$a.md exists"
  done
done
for r in $(cat $files | grep -oE '~/.claude/skills/[a-z-]+/SKILL\.md' | sort -u); do
  n=${r#"~/.claude/skills/"}; n=${n%/SKILL.md}
  assert_eq yes "$([ -f "$REPO/skills/$n/SKILL.md" ] && echo yes || echo no)" "ref skill $n exists"
done
# a skill invoked as `/name` must exist (or be a known external command)
EXTERNAL="modify-epic-ticket initiate-epic-ticket config"
for n in $(cat $files | grep -oE '`/[a-z][a-z-]+[ `]' | tr -d '`/ ' | sort -u); do
  case " $EXTERNAL " in *" $n "*) continue;; esac
  assert_eq yes "$([ -d "$REPO/skills/$n" ] && echo yes || echo no)" "skill /$n exists"
done
for d in rules environments credentials deploy-release report-format; do
  assert_eq yes "$([ -f "$REPO/skills/_shared/$d.md" ] && echo yes || echo no)" "_shared/$d.md exists"
done
assert_eq yes "$([ -f "$REPO/templates/qa.env.example" ] && echo yes || echo no)" "qa template exists"
assert_eq "" "$(grep -rlE 'maestro|xcrun|adb |annotate\.py|build-number\.sh|device-pick|Firebase|TestFlight' $files 2>/dev/null)" "no Mobile device/build leftovers"
# public repo: no user paths or private words (extra words: gitignored .private-denylist, one per line)
assert_eq "" "$(grep -rlE '/Users/|@gmail' "$REPO"/agents "$REPO"/skills "$REPO"/docs "$REPO"/templates "$REPO"/README.md 2>/dev/null)" "no private identifiers"
if [ -f "$REPO/.private-denylist" ]; then
  assert_eq "" "$(git -C "$REPO" grep -lwFf <(grep -v '^[[:space:]]*$' "$REPO/.private-denylist") -- . ':!.private-denylist' 2>/dev/null)" "no words from .private-denylist"
fi
exit $((FAILS > 0))
