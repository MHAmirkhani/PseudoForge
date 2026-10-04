# The HTTP transport

This directory is **not** the API. The API is `lib/http.sh` — the routes, the
response shapes, the status codes and the refusals are all there, in Bash,
with the rest of the core.

What is here moves bytes:

```text
HTTP request  ->  pseudoforge api <METHOD> <PATH> [body]  ->  HTTP response
```

`app.py` has no business logic and must not acquire any. A rule that existed
only here would be a rule the command line does not have, and the four
interfaces would have started to disagree.

## Run the whole site locally

```bash
deploy/scripts/serve-local.sh          # -> http://127.0.0.1:8080
```

That is almost certainly what you want. It does locally what Nginx does on the
server: the frontend at `/`, the built documentation at `/docs/`, and this
service proxied at `/api/`.

!!! warning "`uvicorn app:app` alone serves only `/api/`"
    Opening `/` against it returns **404, correctly** -- the frontend is static
    files and this service never sees them. And it must run **inside WSL or
    Linux**: the API shells out to `pseudoforge`, which is a Bash program, so
    running it from Windows gives `core_not_found` on every endpoint.

## Run just the API

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt

export PF_BIN=$PWD/../pseudoforge
export PF_VAR_DIR=/tmp/pfvar
uvicorn app:app --host 127.0.0.1 --port 8099 --reload
```

```bash
curl -s localhost:8099/api/health   | head -c 200
curl -s localhost:8099/api/routes
curl -s -X POST localhost:8099/api/generate     # 501, by design
```

Interactive docs, from FastAPI: <http://127.0.0.1:8099/api/_docs>

## Configuration

| Variable | Default | What |
|---|---|---|
| `PF_BIN` | `pseudoforge` | the core, on `PATH` or absolute |
| `PF_VAR_DIR` | `/var/lib/pseudoforge` | the served tree |
| `PF_NATIVE_DIR` | `$PF_VAR_DIR/native` | pre-built native files |
| `PF_CACHE_DIR` | `$PF_VAR_DIR/cache` | converted files |
| `PF_API_TIMEOUT` | `60` | seconds before the core is given up on |
| `PF_MAX_UPLOAD` | `8388608` | upload limit for `/api/validate` |
| `PF_RATE_LIMIT` | `60` | requests per window, per IP |
| `PF_RATE_WINDOW` | `60` | the window, in seconds |

## The database

```bash
sqlite3 /var/lib/pseudoforge/db/pseudoforge.db < migrations/001_initial.sql
```

Idempotent — every statement is `IF NOT EXISTS`, and applied versions are
recorded in `schema_migrations`.

The database is **not** the source of truth. The files are, and
`pseudoforge native index` derives `native/index.tsv` from them by reading
each file's provenance sidecar. `native_files` is loaded from that index.

## What this server will never do

**Generate.** The target is a 1-core, 1 GB VPS with no engines and no Quantum
ESPRESSO. `POST /api/generate` answers 501 with instructions for running it
locally, which is the honest answer rather than a queue nothing will collect.

See [`docs/architecture/http.md`](../docs/architecture/http.md) for why, and
for the queue-and-worker model as a possible future extension.
