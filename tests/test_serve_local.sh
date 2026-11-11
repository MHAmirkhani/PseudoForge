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

printf '\n%s== inline server interpreter%s\n' "$DIM" "$RESET"
# 4. Assert launched with "$PYTHON"
grep -qE '"\$PYTHON"[[:space:]]+"\$TMPPY"' "$SCRIPT" \
    && ok_ "inline Python server launched with \"\$PYTHON\"" \
    || bad_ "inline server not launched with \"\$PYTHON\""

# 5. Assert PYTHON resolves to venv path
grep -qE 'PYTHON="\$ROOT/server/\.venv/bin/python3"' "$SCRIPT" \
    && ok_ "\$PYTHON targets server/.venv/bin/python3" \
    || bad_ "\$PYTHON does not target server/.venv/bin/python3"

printf '\n%s== converter symlinking%s\n' "$DIM" "$RESET"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_UPF="$TMP_DIR/fake-upfconv.x"
touch "$FAKE_UPF" && chmod +x "$FAKE_UPF"
TEST_VAR="$TMP_DIR/var"

CONV_BLOCK=$(sed -n '/^# --- converter:/,/^# --- end converter/p' "$SCRIPT")

# 6. Run the search block with UPFCONV_BIN set to fake
out_sym=$(
    PF_VAR_DIR="$TEST_VAR"
    UPFCONV_BIN="$FAKE_UPF"
    ROOT="$ROOT"
    say() { printf '  %s\n' "$*"; }
    warn() { printf '  WARN: %s\n' "$*"; }
    eval "$CONV_BLOCK"
)

if [ -L "$TEST_VAR/converter/upfconv.x" ] && [ "$(readlink "$TEST_VAR/converter/upfconv.x")" = "$FAKE_UPF" ]; then
    ok_ "converter block symlinks UPFCONV_BIN into \$PF_VAR_DIR/converter/upfconv.x"
else
    bad_ "converter symlink not created or points to wrong target"
fi

# 7. Run the search block with empty UPFCONV_BIN and dummy environment where upfconv is not found
SAFE_BIN="$TMP_DIR/safe_bin"
mkdir -p "$SAFE_BIN"
for cmd in sh bash mkdir ln sed grep awk head cut dirname basename; do
    p=$(command -v "$cmd" 2>/dev/null || true)
    [ -n "$p" ] && ln -sf "$p" "$SAFE_BIN/$cmd"
done

out_warn=$(
    PF_VAR_DIR="$TMP_DIR/var2"
    UPFCONV_BIN=""
    QE_ROOT_DIR="$TMP_DIR/no_qe"
    PATH="$SAFE_BIN"
    HOME="$TMP_DIR/fakehome"
    ROOT="$TMP_DIR/fakeroot"
    say() { printf '  %s\n' "$*"; }
    warn() { printf '  WARN: %s\n' "$*"; }
    eval "$CONV_BLOCK" 2>&1
)

if printf '%s' "$out_warn" | grep -q "upfconv.x not found"; then
    ok_ "warn path fires when upfconv.x is absent"
else
    bad_ "warn path did not fire when upfconv.x missing" "$out_warn"
fi

printf '\n%s== store resolution%s\n' "$DIM" "$RESET"

STORE_TMP=$(mktemp -d)
trap 'rm -rf "$TMP_DIR" "$STORE_TMP"' EXIT

# 8. With PF_VAR_DIR=$TMP/fake-store where $TMP/fake-store/native/index.tsv exists (3 lines): prints store: $TMP/fake-store/native
mkdir -p "$STORE_TMP/fake-store/native"
printf "id\tpath\tformat\n1\ta\tupf\n2\tb\tupf\n3\tc\tupf\n" > "$STORE_TMP/fake-store/native/index.tsv"
out_env=$(PF_NATIVE_DIR="" PF_VAR_DIR="$STORE_TMP/fake-store" CHECK_ONLY=1 "$SCRIPT" 2>&1)
if printf '%s' "$out_env" | grep -q "store:[[:space:]]*$STORE_TMP/fake-store/native"; then
    ok_ "prints store: \$TMP/fake-store/native when PF_VAR_DIR is set"
else
    bad_ "did not print expected store path when PF_VAR_DIR set" "$out_env"
fi

# 9. With PF_VAR_DIR unset and $HOME/pf-var/native/index.tsv present (simulate with a temp HOME): picks $HOME/pf-var/native
mkdir -p "$STORE_TMP/fake-home/pf-var/native"
printf "id\tpath\tformat\n1\ta\tupf\n" > "$STORE_TMP/fake-home/pf-var/native/index.tsv"
out_home=$(HOME="$STORE_TMP/fake-home" PF_VAR_DIR="" PF_NATIVE_DIR="" CHECK_ONLY=1 "$SCRIPT" 2>&1)
if printf '%s' "$out_home" | grep -q "store:[[:space:]]*$STORE_TMP/fake-home/pf-var/native"; then
    ok_ "picks \$HOME/pf-var/native when PF_VAR_DIR unset and present in HOME"
else
    bad_ "did not pick \$HOME/pf-var/native" "$out_home"
fi

# 10. With neither: falls back to the fixtures and says so
mkdir -p "$STORE_TMP/empty-home"
out_fix=$(HOME="$STORE_TMP/empty-home" PF_VAR_DIR="" PF_NATIVE_DIR="" CHECK_ONLY=1 "$SCRIPT" 2>&1)
if printf '%s' "$out_fix" | grep -qE "store:.*fixtures|fixtures"; then
    ok_ "falls back to fixtures and says so when no store present"
else
    bad_ "did not indicate fixture fallback when store absent" "$out_fix"
fi

# An explicit empty store wins over a populated default.
out_empty=$(PF_NATIVE_DIR="$STORE_TMP/empty" PF_VAR_DIR="$STORE_TMP/fake-store" CHECK_ONLY=1 "$SCRIPT" 2>&1)
if printf '%s' "$out_empty" | grep -q "store:[[:space:]]*$STORE_TMP/empty"; then
    ok_ "an explicit empty store is used without falling back to a populated default"
else
    bad_ "serve-local ignored an explicitly selected empty store" "$out_empty"
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
