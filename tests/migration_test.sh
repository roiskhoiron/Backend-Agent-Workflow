#!/usr/bin/env bash
# migration-lint.sh + migration-check.sh
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
ML="$REPO/bin/migration-lint.sh" MC="$REPO/bin/migration-check.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# --- lint: additive passes
cat > "$T/add.sql" <<'S'
-- drop table old_stuff (comment only)
CREATE TABLE orders (id bigserial primary key, note text);
ALTER TABLE users ADD COLUMN phone varchar(20);
CREATE INDEX idx_orders_note ON orders(note);
S
cat > "$T/add.js" <<'S'
exports.up = (knex) => knex.schema.createTable('orders', (t) => { t.increments(); t.string('author'); });
// knex.schema.dropTable('x') in a comment
S
assert_exit 0 "additive SQL passes" -- "$ML" "$T/add.sql"
assert_exit 0 "additive knex passes (author is not auth)" -- "$ML" "$T/add.js"

# --- lint: destructive per kind
hit() { # kind line [ext]
  printf '%s\n' "$2" > "$T/m.${3:-sql}"
  assert_eq "$1" "$("$ML" "$T/m.${3:-sql}" | sed -E 's/^[^:]+:[0-9]+: ([a-z-]+): .*/\1/')" "$1: $2"
}
hit hapus-tabel 'DROP TABLE orders;'
hit hapus-tabel '    drop_table :orders' rb
hit hapus-tabel "Schema::dropIfExists('orders'); Schema::dropTable('x');" php
hit hapus-tabel "migrations.DeleteModel(name='Order')," py
hit hapus-kolom 'ALTER TABLE users DROP COLUMN phone;'
hit hapus-kolom 'remove_column :users, :phone' rb
hit hapus-kolom "op.drop_column('users', 'phone')" py
hit hapus-kolom "\$table->dropColumn('phone');" php
hit hapus-kolom "migrations.RemoveField(model_name='user', name='phone')," py
hit ganti-nama 'ALTER TABLE users RENAME COLUMN phone TO mobile;'
hit ganti-nama 'rename_column :users, :phone, :mobile' rb
hit ganti-nama "queryInterface.renameColumn('users','phone','mobile')" js
hit ubah-kolom 'ALTER TABLE users ALTER COLUMN phone TYPE text;'
hit ubah-kolom 'ALTER TABLE users ALTER COLUMN phone SET NOT NULL;'
hit ubah-kolom 'ALTER TABLE users MODIFY phone varchar(10);'
hit ubah-kolom 'change_column :users, :phone, :text' rb
hit ubah-kolom "migrations.AlterField(model_name='user', name='phone')," py
hit ubah-kolom "\$table->string('phone', 10)->change();" php
hit hapus-data 'DELETE FROM users WHERE created_at < now();'
hit hapus-data 'TRUNCATE orders;'
hit ubah-data "UPDATE users SET phone = NULL;"
hit ubah-data "migrations.RunPython(forwards)," py
hit hapus-constraint 'ALTER TABLE orders DROP CONSTRAINT fk_user;'
hit hapus-constraint 'DROP INDEX idx_orders_note;'
assert_exit 1 "destructive exits 1" -- "$ML" "$T/m.sql"
assert_eq 2 "$("$ML" "$T/add.sql" "$T/m.sql" "$T/m.rb" | wc -l | tr -d ' ')" "one line per hit, many files"
assert_exit 2 "missing file" -- "$ML" "$T/nope.sql"
assert_exit 2 "usage" -- "$ML"

# --- check: fake project with a schema file, up/down scripts
P="$T/proj"; mkdir -p "$P"
echo "create table a;" > "$P/schema"
cat > "$P/up.sh" <<'S'
grep -q orders schema || echo "create table orders;" >> schema
S
cat > "$P/down-ok.sh" <<'S'
grep -v orders schema > s.tmp; mv s.tmp schema
S
cat > "$P/down-bad.sh" <<'S'
: # forgets to drop orders
S
cat > "$P/down-lossy.sh" <<'S'
echo "create table a;" > schema; echo "create table leftover;" >> schema
S
args=(--up "bash up.sh" --schema "cat schema" --dir "$P")
assert_exit 0 "reversible migration" -- env -u DATABASE_URL "$MC" "${args[@]}" --down "bash down-ok.sh" --out "$T/o1"
echo "create table a;" > "$P/schema"   # check leaves the DB migrated up
out=$(env -u DATABASE_URL "$MC" "${args[@]}" --down "bash down-ok.sh" --out "$T/o1b")
assert_eq 2 "$(printf '%s\n' "$out" | grep -c '^OK ')" "two OK lines"
echo "create table a;" > "$P/schema"
assert_exit 1 "down that does nothing" -- env -u DATABASE_URL "$MC" "${args[@]}" --down "bash down-bad.sh" --out "$T/o2"
assert_eq yes "$([ -s "$T/o2/diff-s0-s2.txt" ] && echo yes || echo no)" "diff file written"
echo "create table a;" > "$P/schema"
out=$(env -u DATABASE_URL "$MC" "${args[@]}" --down "bash down-lossy.sh" --out "$T/o3")
assert_eq yes "$(printf '%s\n' "$out" | grep -q '^BEDA turun' && echo yes || echo no)" "lossy down reported"
echo "create table a;" > "$P/schema"
assert_exit 1 "failing up" -- env -u DATABASE_URL "$MC" --up "false" --down true --schema "cat schema" --dir "$P" --out "$T/o4"
assert_exit 1 "failing schema" -- env -u DATABASE_URL "$MC" --up true --down true --schema "false" --dir "$P" --out "$T/o5"
assert_exit 2 "non-local DATABASE_URL refused" -- env DATABASE_URL=postgres://u:p@db.example.com/app "$MC" "${args[@]}" --down true --out "$T/o6"
assert_exit 0 "local DATABASE_URL ok" -- env DATABASE_URL=postgresql://agent:agent@127.0.0.1:18011/x "$MC" --up true --down true --schema "echo same" --dir "$P" --out "$T/o7"
assert_exit 2 "usage" -- "$MC" --up x

exit $((FAILS > 0))
