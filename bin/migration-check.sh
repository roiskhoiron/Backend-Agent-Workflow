#!/usr/bin/env bash
# Usage: migration-check.sh --up "<cmd>" --down "<cmd>" --schema "<cmd>" [--dir <worktree>] [--out <dir>]
# Round-trip test of the ticket's migrations on the slot's TEST database (test-db.sh up first):
#   S0 = schema; up; S1 = schema; down; S2 = schema (must equal S0); up; S3 = schema (must equal S1).
# <cmd> are the project's own commands (from project memory), e.g.
#   --up "npx knex migrate:latest" --down "npx knex migrate:rollback" --schema "pg_dump -s \"\$DATABASE_URL\""
# --down must undo exactly the ticket's migrations (e.g. rollback N steps), not the whole history.
# Refuses when DATABASE_URL is set and does not point at 127.0.0.1/localhost (test DB only).
# Writes s0..s3.sql, run.log and the diffs to --out (default ${TMPDIR:-/tmp}/qa/migration-check).
# Exit: 0 reversible; 1 a step failed or a schema differs (stdout says which); 2 usage / not a local DB.
up='' down='' schema='' dir=$PWD out="${TMPDIR:-/tmp}/qa/migration-check"
while [ $# -gt 0 ]; do
  case $1 in
    --up) up=$2; shift 2;; --down) down=$2; shift 2;; --schema) schema=$2; shift 2;;
    --dir) dir=$2; shift 2;; --out) out=$2; shift 2;;
    *) echo "argumen tidak dikenal: $1" >&2; exit 2;;
  esac
done
[ -n "$up" ] && [ -n "$down" ] && [ -n "$schema" ] || { echo "usage: $0 --up <cmd> --down <cmd> --schema <cmd> [--dir <worktree>] [--out <dir>]" >&2; exit 2; }
if [ -n "${DATABASE_URL:-}" ]; then
  host=$(python3 -I -c 'import sys,urllib.parse as u; print(u.urlsplit(sys.argv[1]).hostname or "")' "$DATABASE_URL")
  case $host in 127.0.0.1|localhost|::1) ;; *) echo "DATABASE_URL mengarah ke '$host': migration-check hanya untuk database uji lokal" >&2; exit 2;; esac
fi
mkdir -p "$out"; : > "$out/run.log"
step() { # name cmd
  echo "== $1: $2" >> "$out/run.log"
  (cd "$dir" && bash -c "$2") >> "$out/run.log" 2>&1 || { echo "GAGAL langkah $1 (lihat $out/run.log)"; exit 1; }
}
snap() { # n -> schema with volatile lines (dump timestamps, pg_dump \restrict tokens) removed
  echo "== schema s$1" >> "$out/run.log"
  (cd "$dir" && bash -c "$schema") > "$out/s$1.raw" 2>>"$out/run.log" || { echo "GAGAL ambil skema s$1 (lihat $out/run.log)"; exit 1; }
  grep -vE '^-- (Dump|Started|Completed) |^\\(un)?restrict ' "$out/s$1.raw" > "$out/s$1.sql"; rm -f "$out/s$1.raw"
}
same() { # a b label
  if diff -u "$out/s$1.sql" "$out/s$2.sql" > "$out/diff-s$1-s$2.txt"; then echo "OK $3"; rm -f "$out/diff-s$1-s$2.txt"
  else echo "BEDA $3 (lihat $out/diff-s$1-s$2.txt)"; rc=1; fi
}
rc=0
snap 0; step up "$up"; snap 1
cmp -s "$out/s0.sql" "$out/s1.sql" && echo "CATATAN: migrasi naik tidak mengubah skema (migrasi data saja?)"
step down "$down"; snap 2; same 0 2 "turun mengembalikan skema awal"
step up-lagi "$up"; snap 3; same 1 3 "naik lagi menghasilkan skema yang sama"
exit $rc
