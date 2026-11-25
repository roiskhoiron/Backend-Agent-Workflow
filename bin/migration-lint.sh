#!/usr/bin/env bash
# Usage: migration-lint.sh <file>...        (usually: the migration files added/changed by the ticket branch,
#                                            e.g. git diff --name-only --diff-filter=AM <base>...HEAD -- <migrations dir>)
# Flags migration statements that delete or change existing data/schema, across SQL and common ORM DSLs
# (Rails, Laravel, Knex, Sequelize, TypeORM, Django, Alembic, Prisma SQL, Mongo scripts).
# These need "berhenti dan tanya" and, when clients depend on the old shape, the three-stage change
# (add new -> clients move -> drop old). Additive statements (CREATE TABLE, ADD COLUMN, CREATE INDEX) pass.
# Output: one line per hit: <file>:<line>: <kind>: <text>
# Exit: 0 nothing destructive; 1 destructive hits; 2 usage / file missing.
[ $# -ge 1 ] || { echo "usage: $0 <migration-file>..." >&2; exit 2; }
exec python3 -I - "$@" <<'PY'
import re, sys
RULES = [  # (kind, pattern), first match wins per line
  ("hapus-tabel", r"\bdrop\s+(table|view|materialized\s+view|schema|database|collection)\b|\bdrop_table\b|\bdropTable(IfExists)?\b|\bDeleteModel\b|\bdropCollection\b|\.drop\(\)"),
  ("hapus-kolom", r"\bdrop\s+column\b|\bremove_columns?\b|\bdropColumns?\b|\bRemoveField\b|\bdrop_column\b|\$unset\b"),
  ("ganti-nama", r"\brename\s+(table|column|to)\b|\brename_(table|column|index)\b|\brenameColumn\b|\brenameTable\b|\bRename(Field|Model)\b"),
  ("ubah-kolom", r"\balter\s+column\b.*\b(type|set\s+not\s+null|set\s+data\s+type)\b|\bmodify\s+column\b|\balter\s+table\b.*\bmodify\b|\bchange_column(_null|_default)?\b|\bAlterField\b|\balter_column\b|\bchangeColumn\b|->change\(\)|\.alter\(\)"),
  ("hapus-data", r"\btruncate\b|\bdelete\s+from\b|\bdeleteMany\b|\bdelete_all\b|\bdestroy_all\b|\.delete\(\)"),
  ("ubah-data", r"\bupdate\s+[\w.\"`\[\]]+\s+set\b|\bupdateMany\b|\bupdate_all\b|\bRunPython\b|\bRunSQL\b"),
  ("hapus-constraint", r"\bdrop\s+(constraint|index|primary\s+key|foreign\s+key)\b|\bremove_(index|foreign_key|reference)\b|\bdrop(Index|Foreign|Primary|Unique)\b|\bRemove(Index|Constraint)\b"),
]
RULES = [(k, re.compile(p, re.I)) for k, p in RULES]
rc = 0
for f in sys.argv[1:]:
    try:
        lines = open(f, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        print(f"file tidak ada: {f}", file=sys.stderr); rc = 2; continue
    for n, line in enumerate(lines, 1):
        s = line.strip()
        if not s or s.startswith(("--", "#", "//", "*", "/*")):
            continue
        for kind, rx in RULES:
            if rx.search(s):
                print(f"{f}:{n}: {kind}: {s[:160]}")
                rc = rc or 1
                break
sys.exit(rc)
PY
