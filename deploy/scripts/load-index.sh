#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# load-index.sh -- load native/index.tsv into SQLite.
#
# The files are the source of truth; `pseudoforge native index` derives the
# TSV from them; this loads the TSV into the table the server queries. Three
# steps, one direction, no second opinion.
#
# Idempotent: the table is replaced, not appended to.
# ---------------------------------------------------------------------------
set -euo pipefail

PF_VAR_DIR=${PF_VAR_DIR:-/var/lib/pseudoforge}
DB=$PF_VAR_DIR/db/pseudoforge.db
IDX=$PF_VAR_DIR/native/index.tsv

[ -f "$IDX" ] || { echo "no index: run pseudoforge native index" >&2; exit 1; }
[ -f "$DB" ]  || { echo "no database: run the migration first" >&2; exit 1; }

tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
grep -v '^#' "$IDX" > "$tmp"

sqlite3 "$DB" <<SQL
BEGIN;
DELETE FROM native_files;
.mode tabs
.import '$tmp' native_files_import
INSERT INTO native_files
    (id, element, xc, family, relativity, engine, native_format, path, size, sha256, provenance_path)
SELECT * FROM native_files_import;
DROP TABLE native_files_import;
COMMIT;
SQL

echo "loaded $(wc -l < "$tmp") row(s) into native_files"
