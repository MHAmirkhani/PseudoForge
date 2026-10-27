"""
PseudoForge REST transport.

This is not the API. The API is ``lib/http.sh`` -- the routes, the response
shapes, the status codes and the refusals all live there, in Bash, with the
rest of the core. This file moves bytes:

    HTTP request  ->  pseudoforge api <METHOD> <PATH> [body-file]  ->  HTTP response

Everything it knows about the API it learns by asking. The route table comes
from ``pseudoforge api --routes``; the bodies come from the subprocess
verbatim. There is no business logic here and there must not be: a rule that
existed only in this file would be a rule the command line does not have, and
the four interfaces would have started to disagree.

Python is an external dependency, documented as such -- the same status as
gnuplot and matplotlib. Nothing in ``lib/`` imports it, and the command line,
the wizard and the JSON interface work identically without it.

Run it:

    uvicorn app:app --host 127.0.0.1 --port 8099

See ``server/README.md``, and ``docs/how-to/deploy.md`` for the VPS.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import time
from collections import defaultdict, deque
from pathlib import Path

from fastapi import FastAPI, Request, Response, UploadFile, File
from fastapi.responses import FileResponse, JSONResponse, PlainTextResponse

# --------------------------------------------------------------------------
# Configuration. Everything is overridable by environment variable so the same
# file runs from a checkout and from /opt on the VPS.
# --------------------------------------------------------------------------
PF_BIN = os.environ.get("PF_BIN", "pseudoforge")
PF_VAR_DIR = Path(os.environ.get("PF_VAR_DIR", "/var/lib/pseudoforge"))
PF_NATIVE_DIR = Path(os.environ.get("PF_NATIVE_DIR", PF_VAR_DIR / "native"))
if not (PF_NATIVE_DIR / "index.tsv").is_file():
    for _fallback in [Path.home() / "pf-native", Path.home() / "pf-var" / "native"]:
        if (_fallback / "index.tsv").is_file():
            PF_NATIVE_DIR = _fallback
            break
PF_CACHE_DIR = Path(os.environ.get("PF_CACHE_DIR", PF_VAR_DIR / "cache"))
DECOMPRESSED_DIR = Path(os.environ.get("PF_DECOMPRESSED_DIR", PF_VAR_DIR / "decompressed"))
PF_TIMEOUT = int(os.environ.get("PF_API_TIMEOUT", "60"))

# A 1 GB VPS. An upload larger than this is refused before it is read.
MAX_UPLOAD = int(os.environ.get("PF_MAX_UPLOAD", str(8 * 1024 * 1024)))

RATE_LIMIT = int(os.environ.get("PF_RATE_LIMIT", "60"))      # requests
RATE_WINDOW = int(os.environ.get("PF_RATE_WINDOW", "60"))    # seconds

app = FastAPI(
    title="PseudoForge",
    description="Pre-built pseudopotentials, on-demand conversion, and validation. "
                "Generation runs on your machine.",
    docs_url="/api/_docs",
    redoc_url=None,
)


# --------------------------------------------------------------------------
# The one thing this file does.
# --------------------------------------------------------------------------
def call_core(method: str, path: str, body_path: str | None = None):
    """Run ``pseudoforge api`` and return (status, parsed-or-raw body).

    The status comes back on stderr as ``status: NNN`` so that stdout stays
    exactly the JSON body -- nothing has to be stripped out of it.
    """
    argv = [PF_BIN, "api", method, path]
    if body_path:
        argv.append(body_path)

    env = dict(os.environ)
    env.setdefault("PF_VAR_DIR", str(PF_VAR_DIR))
    env.setdefault("PF_NATIVE_DIR", str(PF_NATIVE_DIR))
    env.setdefault("PF_CACHE_DIR", str(PF_CACHE_DIR))

    try:
        proc = subprocess.run(
            argv, capture_output=True, text=True, timeout=PF_TIMEOUT, env=env
        )
    except FileNotFoundError:
        return 500, {
            "error": "core_not_found",
            "message": f"{PF_BIN} is not on PATH for this service.",
        }
    except subprocess.TimeoutExpired:
        return 504, {
            "error": "core_timeout",
            "message": f"The core did not answer within {PF_TIMEOUT}s.",
        }

    status = 500
    for line in proc.stderr.splitlines():
        if line.startswith("status:"):
            try:
                status = int(line.split(":", 1)[1].strip())
            except ValueError:
                pass

    out = proc.stdout.strip()
    if not out:
        return status if status != 200 else 500, {
            "error": "empty_response",
            "message": "The core produced no body.",
            "detail": proc.stderr.strip()[:500],
        }
    try:
        return status, json.loads(out)
    except json.JSONDecodeError:
        # Never pass a half-parsed body off as JSON: say what happened.
        return 500, {
            "error": "malformed_core_response",
            "message": "The core produced output that is not JSON.",
            "detail": out[:500],
        }


# --------------------------------------------------------------------------
# Rate limiting. In-process and per-IP, which is all a single-worker service
# on one core needs; anything heavier belongs in Nginx.
# --------------------------------------------------------------------------
_hits: dict[str, deque] = defaultdict(deque)


@app.middleware("http")
async def rate_limit(request: Request, call_next):
    if request.url.path.startswith("/api/"):
        who = request.client.host if request.client else "unknown"
        now = time.time()
        q = _hits[who]
        while q and now - q[0] > RATE_WINDOW:
            q.popleft()
        if len(q) >= RATE_LIMIT:
            return JSONResponse(
                status_code=429,
                content={
                    "error": "rate_limited",
                    "message": f"More than {RATE_LIMIT} requests in {RATE_WINDOW}s.",
                    "retry_after": RATE_WINDOW,
                },
                headers={"Retry-After": str(RATE_WINDOW)},
            )
        q.append(now)
    return await call_next(request)


# --------------------------------------------------------------------------
# Read endpoints. Each is one line, because each is a pass-through.
# --------------------------------------------------------------------------
def _passthrough(path: str):
    status, body = call_core("GET", path)
    return JSONResponse(status_code=status, content=body)


@app.get("/api/health")
def health():
    return _passthrough("/api/health")


@app.get("/api/engines")
def engines():
    return _passthrough("/api/engines")


@app.get("/api/engines/{name}")
def engine(name: str):
    return _passthrough(f"/api/engines/{name}")


@app.get("/api/formats")
def formats():
    return _passthrough("/api/formats")


@app.get("/api/profiles")
def profiles():
    return _passthrough("/api/profiles")


@app.get("/api/xc")
def xc():
    return _passthrough("/api/xc")


@app.get("/api/elements")
def elements():
    return _passthrough("/api/elements")


@app.get("/api/elements/{symbol}")
def elements_one(symbol: str):
    return _passthrough(f"/api/elements/{symbol}")


@app.get("/api/coverage")
def coverage_get(request: Request):
    q = request.url.query
    path = "/api/coverage" + (f"?{q}" if q else "")
    return _passthrough(path)


@app.get("/api/recent")
def recent_get(request: Request):
    q = request.url.query
    path = "/api/recent" + (f"?{q}" if q else "")
    return _passthrough(path)


@app.get("/api/capabilities")
def capabilities_get():
    return _passthrough("/api/capabilities")


@app.get("/api/advise")
def advise_get(request: Request):
    q = request.url.query
    path = "/api/advise" + (f"?{q}" if q else "")
    status, body = call_core("GET", path)
    return JSONResponse(status_code=status, content=body)


@app.post("/api/advise")
async def advise_post(request: Request):
    raw = await request.body()
    if len(raw) > 64 * 1024:
        return JSONResponse(
            status_code=413,
            content={"error": "body_too_large", "message": "An advise request is a small JSON object."},
        )
    with tempfile.NamedTemporaryFile("wb", suffix=".json", delete=False) as fh:
        fh.write(raw)
        tmp = fh.name
    try:
        status, body = call_core("POST", "/api/advise", tmp)
    finally:
        os.unlink(tmp)
    return JSONResponse(status_code=status, content=body)


@app.post("/api/compare")
async def compare_post(request: Request):
    raw = await request.body()
    if len(raw) > 64 * 1024:
        return JSONResponse(
            status_code=413,
            content={"error": "body_too_large", "message": "A compare request is a small JSON object."},
        )
    with tempfile.NamedTemporaryFile("wb", suffix=".json", delete=False) as fh:
        fh.write(raw)
        tmp = fh.name
    try:
        status, body = call_core("POST", "/api/compare", tmp)
    finally:
        os.unlink(tmp)
    return JSONResponse(status_code=status, content=body)


@app.get("/api/compare")
def compare_get(request: Request):
    q = request.url.query
    path = "/api/compare" + (f"?{q}" if q else "")
    status, body = call_core("GET", path)
    return JSONResponse(status_code=status, content=body)


@app.get("/api/native")
def native_list():
    return _passthrough("/api/native")


@app.get("/api/native/{file_id}")
def native_one(file_id: str):
    return _passthrough(f"/api/native/{file_id}")


@app.get("/api/provenance/{file_id:path}")
def provenance_one(file_id: str):
    return _passthrough(f"/api/provenance/{file_id}")


@app.get("/api/routes")
def routes():
    """The route table, from the core. Useful for a client and for the docs."""
    status, body = call_core("GET", "/api/routes")
    return JSONResponse(status_code=status, content=body)


# --------------------------------------------------------------------------
# Convert and download.
# --------------------------------------------------------------------------
@app.post("/api/convert")
async def convert(request: Request):
    raw = await request.body()
    if len(raw) > 64 * 1024:
        return JSONResponse(
            status_code=413,
            content={"error": "body_too_large", "message": "A convert request is a small JSON object."},
        )
    with tempfile.NamedTemporaryFile("wb", suffix=".json", delete=False) as fh:
        fh.write(raw)
        tmp = fh.name
    try:
        status, body = call_core("POST", "/api/convert", tmp)
    finally:
        os.unlink(tmp)
    return JSONResponse(status_code=status, content=body)


def _resolve_and_check(file_id: str):
    """Return (Path, error_response).  Core resolves id -> path."""
    status, body = call_core("GET", f"/api/download/{file_id}")
    if status != 200:
        return None, JSONResponse(status_code=status, content=body)
    p = Path(body.get("path", "")).resolve()
    allowed = [PF_NATIVE_DIR.resolve(), PF_CACHE_DIR.resolve()]
    if not any(str(p).startswith(str(root) + os.sep) for root in allowed):
        return None, JSONResponse(
            status_code=403,
            content={"error": "forbidden", "message": "That file is outside the served tree."},
        )
    if not p.is_file():
        return None, JSONResponse(
            status_code=404,
            content={"error": "not_found", "message": "The file is no longer on disk."},
        )
    return p, None


def _plain_file(path: Path) -> Path:
    """Return a plain (decompressed) file on disk, cached.

    The store keeps files gzipped to save disk.  Serving them with
    Content-Encoding: gzip works for browsers but breaks download managers
    (FDM, IDM, aria2): they receive the compressed bytes, decompress them,
    compare against the announced Content-Length, find a mismatch, and
    retry forever.  Sending the bytes plain fixes that -- but decompressing
    on every request costs CPU and, worse, forces us to answer Range
    requests ourselves, which is where multi-connection download managers
    live.

    So we decompress once into a cache directory and hand the plain file
    to FileResponse, which supports HEAD, Range and multi-connection
    downloads natively.
    """
    if path.suffix != ".gz":
        return path
    rel = path.relative_to(PF_NATIVE_DIR) if str(path).startswith(str(PF_NATIVE_DIR)) else Path(path.name)
    plain = DECOMPRESSED_DIR / rel.with_suffix("")
    if plain.is_file() and plain.stat().st_mtime >= path.stat().st_mtime:
        return plain
    import gzip as _gzip
    plain.parent.mkdir(parents=True, exist_ok=True)
    tmp = plain.with_suffix(plain.suffix + ".tmp")
    tmp.write_bytes(_gzip.decompress(path.read_bytes()))
    tmp.replace(plain)
    return plain


@app.head("/api/download/{file_id:path}")
def download_head(file_id: str):
    """HEAD for download managers (FDM, IDM). They probe before GET."""
    path, err = _resolve_and_check(file_id)
    if err:
        return err
    plain = _plain_file(path)
    r = FileResponse(plain, filename=plain.name, media_type="application/octet-stream")
    r.headers["Accept-Ranges"] = "bytes"
    return r


@app.get("/api/download/{file_id:path}")
def download(file_id: str):
    """Serve the file plain.  FileResponse handles Range and HEAD."""
    path, err = _resolve_and_check(file_id)
    if err:
        return err
    plain = _plain_file(path)
    resp = FileResponse(plain, filename=plain.name, media_type="application/octet-stream")
    resp.headers["Accept-Ranges"] = "bytes"
    return resp


@app.post("/api/validate")
async def validate(file: UploadFile = File(...)):
    with tempfile.NamedTemporaryFile("wb", delete=False) as fh:
        written = 0
        while chunk := await file.read(64 * 1024):
            written += len(chunk)
            if written > MAX_UPLOAD:
                fh.close()
                os.unlink(fh.name)
                return JSONResponse(
                    status_code=413,
                    content={
                        "error": "file_too_large",
                        "message": f"The limit on this server is {MAX_UPLOAD // (1024 * 1024)} MB.",
                    },
                )
            fh.write(chunk)
        tmp = fh.name
    try:
        status, body = call_core("POST", "/api/validate", tmp)
    finally:
        os.unlink(tmp)
    return JSONResponse(status_code=status, content=body)


# --------------------------------------------------------------------------
# Generate -- refused, from the core, so the refusal is worded once.
# --------------------------------------------------------------------------
@app.post("/api/generate")
async def generate():
    status, body = call_core("POST", "/api/generate")
    return JSONResponse(status_code=status, content=body)


# --------------------------------------------------------------------------
@app.get("/api/version")
def version():
    status, body = call_core("GET", "/api/version")
    return JSONResponse(status_code=status, content=body)
