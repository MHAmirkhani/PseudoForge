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
PF_VAR_DIR=${PF_VAR_DIR:-/tmp/pseudoforge-local}

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
mkdir -p "$PF_VAR_DIR"/{native,cache,db,converter}
if [ ! -f "$PF_VAR_DIR/native/index.tsv" ]; then
    "$ROOT/pseudoforge" native index "$PF_VAR_DIR/native" >/dev/null 2>&1 || true
fi
# grep -c exits 1 when the count is zero and still prints the zero, so the
# old fallback appended a second one and the line read "(0" then "0 native
# file(s))" on the next. Dropping that fallback was worse: under `set -e`
# the non-zero status killed the script here, silently, before it ever
# reached "starting". Take the number grep printed, neutralise its exit
# status separately.
n=$(grep -vc '^#' "$PF_VAR_DIR/native/index.tsv" 2>/dev/null) || true
n=${n:-0}
say "store:   $PF_VAR_DIR ($n native file(s))"
[ "$n" = 0 ] && say "         (empty is fine -- generate some and re-run 'pseudoforge native index')"

if [ -d "$ROOT/site" ]; then
    say "docs:    $ROOT/site ($(find "$ROOT/site" -name '*.html' | wc -l) pages)"
else
    say "docs:    not built -- /docs/ will 404"
    say "         build them with: mkdocs build --strict --site-dir site"
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
trap cleanup EXIT INT TERM

( cd "$ROOT/server" && \
  PF_BIN="$ROOT/pseudoforge" \
  PF_VAR_DIR="$PF_VAR_DIR" \
  PF_NATIVE_DIR="$PF_VAR_DIR/native" \
  PF_CACHE_DIR="$PF_VAR_DIR/cache" \
  PF_RATE_LIMIT=1000 \
  "$UVICORN" app:app --host "$HOST" --port "$API_PORT" --log-level warning \
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
cat > "$TMPPY" <<PYEOF
import http.server
import socketserver, urllib.request, urllib.error, os, posixpath
from http.server import ThreadingHTTPServer

WWW  = "$ROOT/frontend"
DOCS = "$ROOT/site"
API  = "http://127.0.0.1:$API_PORT" if "$HOST" == "127.0.0.1" else "http://$HOST:$API_PORT"

class Handler(http.server.SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def translate_path(self, path):
        path = path.split("?", 1)[0].split("#", 1)[0]
        if path.startswith("/docs/"):
            root, rel = DOCS, path[len("/docs/"):]
        elif path == "/docs":
            self.send_response(301); self.send_header("Location", "/docs/")
            self.end_headers(); return ""
        else:
            root, rel = WWW, path.lstrip("/")
        # Refuse to leave the two directories this serves from.
        full = os.path.normpath(os.path.join(root, rel))
        if not full.startswith(os.path.normpath(root)):
            return os.path.join(root, "index.html")
        if os.path.isdir(full):
            full = os.path.join(full, "index.html")
        return full

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
                r = urllib.request.urlopen(req)
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
            msg = ('{"error":"transport","message":"%s"}' % exc).encode()
            try:
                self.send_response(502)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(msg)))
                self.end_headers()
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
with socketserver.ThreadingTCPServer(("$HOST", $PORT), Handler) as httpd:
    httpd.serve_forever()
PYEOF

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
