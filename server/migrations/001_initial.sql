-- ---------------------------------------------------------------------------
-- 001_initial -- the served store's bookkeeping.
--
-- What this database is NOT: the source of truth. The native files on disk
-- are, and `pseudoforge native index` derives native/index.tsv from them by
-- reading each file's own provenance sidecar. This table is loaded from that
-- index so the server can answer a query without a filesystem scan.
--
-- Rebuild it at any time:
--     pseudoforge native index && deploy/scripts/load-index.sh
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS native_files (
    id              TEXT PRIMARY KEY,
    element         TEXT NOT NULL,
    xc              TEXT NOT NULL,
    family          TEXT NOT NULL,
    relativity      TEXT NOT NULL,
    engine          TEXT NOT NULL,
    native_format   TEXT NOT NULL,
    path            TEXT NOT NULL,
    size            INTEGER NOT NULL,
    sha256          TEXT NOT NULL,
    provenance_path TEXT,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS conversions (
    id                TEXT PRIMARY KEY,
    source_id         TEXT REFERENCES native_files(id),
    target_format     TEXT NOT NULL,
    path              TEXT NOT NULL,
    size              INTEGER NOT NULL,
    converter         TEXT NOT NULL,
    converter_version TEXT,
    warnings          TEXT,
    created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS validation_results (
    id          TEXT PRIMARY KEY,
    file_id     TEXT,
    score       INTEGER,
    report_json TEXT,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- The lookup the front page makes on every element click.
CREATE INDEX IF NOT EXISTS idx_native_lookup
    ON native_files(element, xc, family, relativity);
CREATE INDEX IF NOT EXISTS idx_conversions_source
    ON conversions(source_id);

-- Applied migrations, so the script can be idempotent.
CREATE TABLE IF NOT EXISTS schema_migrations (
    version    TEXT PRIMARY KEY,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT OR IGNORE INTO schema_migrations(version) VALUES ('001_initial');
