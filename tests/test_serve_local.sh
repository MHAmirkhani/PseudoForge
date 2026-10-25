#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Tests for deploy/scripts/serve-local.sh
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
SCRIPT=$ROOT/deploy/scripts/serve-local.sh

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

printf '\n%s== proxy immunity%s\n' "$DIM" "$RESET"
# 1. no_proxy exported near top
grep -qE 'export (no_proxy NO_PROXY|NO_PROXY no_proxy)' "$SCRIPT" \
    && ok_ "serve-local.sh exports no_proxy and NO_PROXY" \
    || bad_ "serve-local.sh does not export no_proxy"

# 2. Every 127.0.0.1 curl has --noproxy "*"
c1=$(grep -c 'curl.*127\.0\.0\.1' "$SCRIPT" || true)
c2=$(grep -c 'curl.*--noproxy "\*".*127\.0\.0\.1' "$SCRIPT" || true)
[ "$c1" -gt 0 ] && [ "$c1" -eq "$c2" ] \
    && ok_ "all internal 127.0.0.1 curl calls pass --noproxy \"*\" ($c2/$c1)" \
    || bad_ "not all internal curl calls have --noproxy \"*\" ($c2/$c1)"

# 3. Live probe bypass test: verify curl with --noproxy "*" succeeds when http_proxy is dead
PORT=$(( 30000 + RANDOM % 20000 ))
python3 -c "
import http.server, socketserver
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'ok')
    def log_message(self, *args): pass
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(('127.0.0.1', $PORT), H) as s:
    s.handle_request()
" &
srv_pid=$!
sleep 0.2
res=$(http_proxy=http://127.0.0.1:1 https_proxy=http://127.0.0.1:1 \
      curl -s --noproxy "*" "http://127.0.0.1:$PORT/" 2>/dev/null || true)
kill "$srv_pid" 2>/dev/null || true
[ "$res" = "ok" ] \
    && ok_ "curl with --noproxy \"*\" bypasses invalid http_proxy" \
    || bad_ "curl failed when http_proxy was set to unreachable host"

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
