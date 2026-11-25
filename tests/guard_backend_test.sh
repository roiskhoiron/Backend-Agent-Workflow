#!/usr/bin/env bash
# guard.sh, Backend additions: production DB/env (check_prod) and the user's docker data (check_docker)
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
G="$REPO/hooks/guard.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export AGENT_WORKFLOW_STATE="$T/st"; mkdir -p "$AGENT_WORKFLOW_STATE"
printf '# production\ndb.prod.example.com\nAPI.Example.com  \n\n' > "$AGENT_WORKFLOW_STATE/prod-hosts.txt"
check() { # expected command
  jq -cn --arg c "$2" --arg d "$T" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | "$G" >/dev/null 2>"$T/err"
  assert_eq "$1" "$?" "[$1] $2"
}

# DB clients to a production host
check 2 'psql "postgres://u:p@db.prod.example.com:5432/app" -c "select 1"'
check 2 'mysql -h db.prod.example.com -u root app'
check 2 'pg_dump -h replica.db.prod.example.com app'          # subdomain of a listed host
check 2 'DATABASE_URL=postgres://db.prod.example.com/app npx prisma migrate deploy'
check 2 'echo x | mongosh mongodb://db.prod.example.com/app'
check 0 'psql postgres://agent:agent@127.0.0.1:18011/agent_svc_12'
check 0 'psql -h notdb.prod.example.community'                # not the same host
check 0 'psql -h db.prod.example.com.evil'                    # suffix of another domain: still allowed (not prod)
# migration tools with a production env marker
check 2 'NODE_ENV=production npx knex migrate:latest'
check 2 'RAILS_ENV=production bin/rails db:migrate'
check 2 'php artisan migrate --env=production'
check 2 'npx sequelize db:migrate --env production'
check 2 'DJANGO_SETTINGS_MODULE=app.settings.prod python manage.py migrate'
check 2 'MIX_ENV=prod mix ecto.migrate migrate'
check 0 'npx knex migrate:latest'
check 0 'NODE_ENV=test npx knex migrate:latest'
check 0 'NODE_ENV=production node server.js'                  # prod env, but not a migration/DB tool
# writes over HTTP to production
check 2 'curl -X POST https://api.example.com/v1/orders'
check 2 'curl -XDELETE https://api.example.com/v1/orders/1'
check 2 'curl --request=PUT https://api.example.com/v1/x'
check 2 'curl -d @body.json https://v2.api.example.com/x'
check 2 'curl --json {} https://api.example.com/x'
check 2 'wget --post-data=a=1 https://api.example.com/x'
check 2 'http POST https://api.example.com/x a=1'
check 0 'curl -sS https://api.example.com/v1/health'
check 0 'curl -I https://api.example.com/v1/health'
check 0 'curl -X POST https://api.dev.example.org/v1/orders'  # dev server: allowed
check 0 'http GET https://api.example.com/x'
check 2 'curl -X PATCH https://api.example.com/x'
assert_eq yes "$(grep -q "http-evidence.sh --safe" "$T/err" && echo yes || echo no)" "pesan menyebut http-evidence.sh --safe"

# no prod-hosts.txt: only env markers apply
rm "$AGENT_WORKFLOW_STATE/prod-hosts.txt"
check 0 'psql -h db.prod.example.com'
check 2 'RAILS_ENV=production bin/rails db:rollback'

# docker: only agent containers/volumes may be destroyed
check 2 'docker system prune -af'
check 2 'docker volume prune -f'
check 2 'docker container prune'
check 2 'docker rm -f mydb'
check 2 'docker kill postgres'
check 2 'docker volume rm pgdata'
check 2 'docker container rm mydb'
check 2 'docker compose down -v'
check 2 'docker-compose down --volumes'
check 2 'docker compose -f dev.yml down -v'
check 0 'docker rm -f agentdb-svc-12'
check 0 'docker -H unix:///x.sock rm agentdb-svc-12'
check 0 'docker compose -p agent-svc-12 down -v'
check 0 'COMPOSE_PROJECT_NAME=agent-svc-12 docker compose down -v'
check 0 'docker compose down'
check 0 'docker compose up -d'
check 0 'docker ps -a'
check 0 'docker run -d --name agentdb-x -v data:/x postgres'

# audit mode: docker read-only
export AGENT_AUDIT=1
check 0 'docker ps'
check 0 'docker logs svc'
check 0 'docker compose logs api'
check 2 'docker run -d postgres'
check 2 'docker compose up -d'
check 2 'docker rm -f agentdb-x'
check 2 '"$AGENT_WORKFLOW_DIR/bin/test-db.sh" up /w postgres'
check 2 'migration-check.sh --up a --down b --schema c'
check 2 'docs-publish.sh put /w docs/audit/x.md /tmp/audit/x.md'
check 0 'test-db.sh status /w'
check 0 'env-slot.sh show /w'
unset AGENT_AUDIT
check 0 '"$AGENT_WORKFLOW_DIR/bin/test-db.sh" up /w postgres'

exit $((FAILS > 0))
