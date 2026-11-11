#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# serve-local.sh -- the whole site on your own machine, one command.
#
#   deploy/scripts/serve-local.sh
#   -> http://127.0.0.1:8080
#
# Why this exists: `uvicorn app:app` alone serves **only** /api/. The frontend
# and the documentation are static files, and on the VPS it is Nginx that puts
# the three together:
#
#     /       -> www/       the frontend        (static)
#     /docs/  -> docs/      the built MkDocs    (static)
#     /api/   -> uvicorn    the transport       (proxied)
#
# Running the API on its own and opening / gives a 404, correctly, and that is
# a confusing first experience. This script does locally what Nginx does on the
# server, so what you see is what will be deployed.
#
# Run it **inside WSL or Linux**, not from Windows PowerShell: `pseudoforge` is
# a Bash program and the API shells out to it.
#
# Python is used here for the same reason it is used for the transport -- it is
# an external tool, documented as such. Nothing in lib/ depends on it.
# ---------------------------------------------------------------------------
set -euo pipefail

# Internal probes must not go through a proxy. The user may have
# http_proxy exported for other work; an internal probe to 127.0.0.1
# that tunnels through that proxy is not a probe of this machine.
no_proxy="127.0.0.1,localhost,${no_proxy:-}"
NO_PROXY="$no_proxy"
export no_proxy NO_PROXY

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)

PORT=${PORT:-8080}
API_PORT=${API_PORT:-8099}

# Which address to bind. 127.0.0.1 is right when WSL's localhost forwarding is
# working, which is most of the time -- Windows reaches the same address. It
# stops working after WSL restarts on some builds, and then the site is
# unreachable from the browser with no error on this side, because nothing is
# wrong on this side. HOST=0.0.0.0 binds every interface, so the WSL IP
# printed below works regardless; that also exposes the port to your local
# network, which is why it is not the default.
HOST=${HOST:-127.0.0.1}

# ---------------------------------------------------------------------------
# Store resolution: caller env, ~/.pseudoforgerc, $HOME/.pseudoforge,
# $HOME/pf-var, $HOME/pf-native, or fallback to /tmp/pseudoforge-local-$UID
# seeded from fixtures.
PF_NATIVE_DIR="${PF_NATIVE_DIR:-}"
using_fixtures=0

if [ -n "${PF_VAR_DIR:-}" ]; then
    if [ -z "$PF_NATIVE_DIR" ]; then
        if [ -f "$PF_VAR_DIR/native/index.tsv" ]; then
            PF_NATIVE_DIR="$PF_VAR_DIR/native"
        elif [ -f "$PF_VAR_DIR/index.tsv" ]; then
            PF_NATIVE_DIR="$PF_VAR_DIR"
        else
            PF_NATIVE_DIR="$PF_VAR_DIR/native"
        fi
    fi
elif [ -z "$PF_NATIVE_DIR" ] && [ -f "$HOME/.pseudoforgerc" ] && bash -c '[ -f "$1/.pseudoforgerc" ] && . "$1/.pseudoforgerc" && [ -n "${PF_VAR_DIR:-}" ]' _ "$HOME" 2>/dev/null; then
    rc_var=$(bash -c '. "$1/.pseudoforgerc"; printf "%s" "${PF_VAR_DIR:-}"' _ "$HOME" 2>/dev/null || true)
    if [ -n "$rc_var" ]; then
        PF_VAR_DIR="$rc_var"
        if [ -f "$PF_VAR_DIR/native/index.tsv" ]; then
            PF_NATIVE_DIR="$PF_VAR_DIR/native"
        elif [ -f "$PF_VAR_DIR/index.tsv" ]; then
            PF_NATIVE_DIR="$PF_VAR_DIR"
        else
            PF_NATIVE_DIR="$PF_VAR_DIR/native"
        fi
    fi
fi

if [ -z "${PF_VAR_DIR:-}" ] && [ -n "$PF_NATIVE_DIR" ]; then
    PF_VAR_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/pseudoforge/local
fi

if [ -z "${PF_VAR_DIR:-}" ]; then
    if [ -f "$HOME/.pseudoforge/native/index.tsv" ]; then
        PF_VAR_DIR="$HOME/.pseudoforge"
        PF_NATIVE_DIR="$HOME/.pseudoforge/native"
    elif [ -f "$HOME/pf-var/native/index.tsv" ]; then
        PF_VAR_DIR="$HOME/pf-var"
        PF_NATIVE_DIR="$HOME/pf-var/native"
    elif [ -f "$HOME/pf-native/index.tsv" ]; then
        PF_VAR_DIR="$HOME/pf-native"
        PF_NATIVE_DIR="$HOME/pf-native"
    else
        PF_VAR_DIR="/tmp/pseudoforge-local-${UID:-$(id -u)}"
        PF_NATIVE_DIR="$PF_VAR_DIR/native"
        using_fixtures=1
    fi
fi

say()  { printf '  %s\n' "$*"; }
warn() { printf '  WARN: %s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }

# ---------------------------------------------------------------------------
step "checking"

case "$(uname -s)" in
    Linux) ;;
    *) printf 'This has to run inside WSL or Linux: the API shells out to\n' >&2
       printf 'pseudoforge, which is a Bash program.\n' >&2
       exit 1 ;;
esac

UVICORN=""
if [ -n "${UVICORN_BIN:-}" ]; then
    if [ -x "$UVICORN_BIN" ]; then
        UVICORN=$UVICORN_BIN
    else
        printf 'UVICORN_BIN is set to %s, which is not an executable file.
' "$UVICORN_BIN" >&2
        printf 'Ignoring it and looking in the usual places.

' >&2
    fi
fi
if [ -z "$UVICORN" ]; then
    for c in "$ROOT/server/.venv/bin/uvicorn" "$(command -v uvicorn 2>/dev/null || true)"; do
        [ -n "$c" ] && [ -x "$c" ] && { UVICORN=$c; break; }
    done
fi
if [ -z "$UVICORN" ]; then
    printf 'uvicorn not found. Either:\n' >&2
    printf '  python3 -m venv server/.venv\n' >&2
    printf '  server/.venv/bin/pip install -r server/requirements.txt\n' >&2
    printf 'or set UVICORN_BIN to one you already have.\n' >&2
    exit 1
fi

PYTHON="$ROOT/server/.venv/bin/python3"
if [ ! -x "$PYTHON" ]; then
    PYTHON=$(command -v python3 || true)
fi

say "uvicorn: $UVICORN"
say "python:  $PYTHON"
say "core:    $ROOT/pseudoforge"

# The served tree. Created empty if absent: the site works with nothing in it,
# and /download/ says so rather than breaking.
mkdir -p "$PF_VAR_DIR"/{cache,db,converter}
mkdir -p "$PF_NATIVE_DIR"

if [ "$using_fixtures" -eq 1 ]; then
    if [ ! -f "$PF_NATIVE_DIR/index.tsv" ] || [ ! -s "$PF_NATIVE_DIR/index.tsv" ]; then
        cp "$ROOT/tests/fixtures/upf/"*.UPF "$PF_NATIVE_DIR/" 2>/dev/null || true
        cp "$ROOT/tests/fixtures/psp8/"*.psp8 "$PF_NATIVE_DIR/" 2>/dev/null || true
        cp "$ROOT/tests/fixtures/gth/"*.gth "$PF_NATIVE_DIR/" 2>/dev/null || true
        "$ROOT/pseudoforge" native index "$PF_NATIVE_DIR" >/dev/null 2>&1 || true
    fi
fi

n=$(grep -vc '^#' "$PF_NATIVE_DIR/index.tsv" 2>/dev/null) || true
n=${n:-0}
if [ "$using_fixtures" -eq 1 ]; then
    say "store:   $PF_NATIVE_DIR ($n native file(s)) (seeded from fixtures)"
else
    say "store:   $PF_NATIVE_DIR ($n native file(s))"
fi
[ "$n" = 0 ] && say "         (empty is fine -- generate some and re-run 'pseudoforge native index')"

if [ -d "$ROOT/site" ]; then
    say "docs:    $ROOT/site ($(find "$ROOT/site" -name '*.html' | wc -l) pages)"
else
    say "docs:    not built -- /docs/ will 404"
    say "         build them with: mkdocs build --strict --site-dir site"
fi

if [ "${CHECK_ONLY:-0}" = 1 ] || [ "${1:-}" = "--check" ]; then
    exit 0
fi

# --- converter: browser conversion needs upfconv.x -------------------
if [ -z "${UPFCONV_BIN:-}" ]; then
    for cand in \
        "$ROOT/data/converter/upfconv.x" \
        "$HOME/.pseudoforge/engines/bin/upfconv.x" \
        ${QE_ROOT_DIR:-/opt/espresso}/*/upfconv.x \
        "$(command -v upfconv.x 2>/dev/null || true)" \
        "$(command -v upfconv   2>/dev/null || true)" ; do
        [ -n "$cand" ] && [ -x "$cand" ] && { UPFCONV_BIN=$cand; break; }
    done
fi
if [ -n "${UPFCONV_BIN:-}" ]; then
    mkdir -p "$PF_VAR_DIR/converter"
    ln -sf "$UPFCONV_BIN" "$PF_VAR_DIR/converter/upfconv.x"
    export UPFCONV_BIN
    say "converter: $UPFCONV_BIN"
else
    warn "upfconv.x not found; browser conversion will return 503"
    warn "  Install Quantum ESPRESSO, or set UPFCONV_BIN to its path."
fi
# --- end converter --------------------------------------------------

# ---------------------------------------------------------------------------
step "starting"

cleanup() {
    [ -n "${API_PID:-}"   ] && kill "$API_PID"   2>/dev/null || true
    [ -n "${FRONT_PID:-}" ] && kill "$FRONT_PID" 2>/dev/null || true
    rm -f "${TMPPY:-}"
    printf '\nstopped\n'
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

( cd "$ROOT/server" && \
  export PF_BIN="$ROOT/pseudoforge" && \
  export PF_VAR_DIR="$PF_VAR_DIR" && \
  export PF_NATIVE_DIR="$PF_NATIVE_DIR" && \
  export PF_CACHE_DIR="$PF_VAR_DIR/cache" && \
  export PF_RATE_LIMIT=1000 && \
  exec "$UVICORN" app:app --host "$HOST" --port "$API_PORT" --log-level warning \
) & API_PID=$!

up=0
for _ in $(seq 1 60); do
    curl -fsS --noproxy "*" "http://127.0.0.1:$API_PORT/api/version" >/dev/null 2>&1 && { up=1; break; }
    curl -fsS --noproxy "*" "http://$HOST:$API_PORT/api/version"      >/dev/null 2>&1 && { up=1; break; }
    sleep 0.25
done
[ "$up" = 1 ] || { printf 'the API did not start\n' >&2; exit 1; }
say "api      http://127.0.0.1:$API_PORT/api/"

# The front door: the same routing Nginx does, in about forty lines.
TMPPY=$(mktemp --suffix=.py)
cat > "$TMPPY" <<'PYEOF'
import http.server
import json
import os
import re
import socketserver
import urllib.error
import urllib.parse
import urllib.request

from pathlib import Path

ROOT = Path(os.environ["PF_LOCAL_ROOT"])
WWW = ROOT / "frontend"
DOCS = ROOT / "site"
API = "http://127.0.0.1:" + os.environ["PF_LOCAL_API_PORT"]

class Handler(http.server.SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def send_head(self):
        if urllib.parse.urlsplit(self.path).path == "/docs":
            self.send_response(301)
            self.send_header("Location", "/docs/")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return None
        return super().send_head()

    def translate_path(self, path):
        path = urllib.parse.unquote(urllib.parse.urlsplit(path).path)
        if re.fullmatch(r"/elements/[A-Za-z]{1,2}/?", path):
            return str(WWW / "elements" / "index.html")
        if path.startswith("/docs/"):
            root, rel = DOCS, path[len("/docs/"):]
        else:
            root, rel = WWW, path.lstrip("/")
        full = (root / rel.lstrip("/")).resolve()
        if not full.is_relative_to(root.resolve()):
            return os.devnull + "/index.html"
        if full.is_dir():
            full /= "index.html"
        return str(full)

    # Headers we forward from the client to the core. Range matters: FDM,
    # IDM and aria2 open downloads by asking for one byte and reading the
    # 206 answer. Without forwarding Range they receive a 200 with the whole
    # file, decide the server does not do ranges, and either fall back to a
    # single slow connection or hang on "requesting info".
    _FORWARD_REQUEST = (
        "Content-Type", "Content-Length",
        "Range", "If-Range", "If-None-Match", "If-Modified-Since",
        "Accept", "Accept-Encoding", "User-Agent",
    )
    # Headers we forward from the core back to the client. Content-Range and
    # Accept-Ranges are what tell a download manager it can split the file.
    # Content-Length is passed through verbatim: if the core sent a length,
    # we send the same one, and we do NOT compute our own -- a proxy that
    # rewrites Content-Length is how a working download becomes a broken one.
    _FORWARD_RESPONSE = (
        "Content-Type", "Content-Disposition", "Content-Encoding",
        "Content-Range", "Accept-Ranges", "Content-Length",
        "ETag", "Last-Modified", "Cache-Control",
    )

    def _proxy(self):
        try:
            data = None
            n = self.headers.get("Content-Length")
            if n:
                data = self.rfile.read(int(n))
            req = urllib.request.Request(API + self.path, data=data, method=self.command)
            for k in self._FORWARD_REQUEST:
                v = self.headers.get(k)
                if v:
                    req.add_header(k, v)
            try:
                r = urllib.request.urlopen(req, timeout=125)
            except urllib.error.HTTPError as e:
                r = e
            with r:
                body = r.read()
                self.send_response(r.status)
                for k in self._FORWARD_RESPONSE:
                    v = r.headers.get(k)
                    if v:
                        self.send_header(k, v)
                # If the core did not announce a length, announce one now --
                # otherwise the client falls back to connection-close framing,
                # which download managers treat as an unknown-size stream.
                if not r.headers.get("Content-Length") and self.command != "HEAD":
                    self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            # The client closed the connection before we finished writing.
            # This is normal when a page navigates away, when a second tab
            # reloads, or when a download manager abandons a probe and
            # immediately opens a new one.  There is nothing to send and
            # nothing to fix; log a single line and move on.
            print("  (client closed early)")
        except Exception as exc:
            print(f"  transport error: {exc}")
            msg = json.dumps({"error": "transport", "message": "Could not reach the local API."}).encode()
            try:
                self.send_response(502)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(msg)))
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(msg)
            except (BrokenPipeError, ConnectionResetError):
                # Same cause as above, just caught a moment later.
                pass

    def do_GET(self):
        if self.path.startswith("/api/"):
            return self._proxy()
        return super().do_GET()

    def do_POST(self):
        if self.path.startswith("/api/"):
            return self._proxy()
        self.send_error(405)

    def do_HEAD(self):
        # Route HEAD to the proxy too. Download managers (FDM, IDM) send
        # HEAD before GET to learn the size and whether ranges are
        # supported. Without this they hit SimpleHTTP's do_HEAD, get a 404,
        # and hang on "requesting info" forever.
        if self.path.startswith("/api/"):
            return self._proxy()
        return super().do_HEAD()

    def log_message(self, fmt, *args):
        print("  %s" % (fmt % args))

socketserver.ThreadingTCPServer.allow_reuse_address = True
with socketserver.ThreadingTCPServer(
    (os.environ["PF_LOCAL_HOST"], int(os.environ["PF_LOCAL_PORT"])), Handler
) as httpd:
    httpd.serve_forever()
PYEOF

PF_LOCAL_ROOT="$ROOT" PF_LOCAL_PORT="$PORT" PF_LOCAL_API_PORT="$API_PORT" PF_LOCAL_HOST="$HOST" \
    "$PYTHON" "$TMPPY" & FRONT_PID=$!
sleep 1

curl -fsS --noproxy "*" "http://127.0.0.1:$PORT/" >/dev/null 2>&1 \
    || { printf 'the front door did not start\n' >&2; exit 1; }

# ---------------------------------------------------------------------------
step "ready"
say ""
say "    http://127.0.0.1:$PORT"
say ""
say "  /            the site          (frontend/)"
say "  /download/   pre-built files"
say "  /validate/   upload and check"
say "  /docs/       the documentation (site/)"
say "  /api/        the REST API"
say ""
say "From Windows, open the same address in your browser -- WSL forwards it."
if [ "$HOST" = 127.0.0.1 ]; then
    wslip=$(hostname -I 2>/dev/null | awk '{ print $1 }')
    if [ -n "$wslip" ]; then
        say ""
        say "If that address does not answer from Windows, WSL's localhost"
        say "forwarding is down. Restart this with:"
        say ""
        say "    HOST=0.0.0.0 deploy/scripts/serve-local.sh"
        say ""
        say "and use  http://$wslip:$PORT  instead."
    fi
fi
say "Ctrl-C to stop."
printf '\n'

wait $FRONT_PID
