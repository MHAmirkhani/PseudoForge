#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# The REST interface.
#
# The property: **the website is a fourth interface, not a second
# implementation.** Every endpoint answers with what the CLI would answer,
# because it calls the same functions. If a shape, a refusal or a status could
# be produced by the server and not by `pseudoforge api`, the two have started
# to diverge and this suite fails.
#
# Two levels, and both matter:
#
#   * the **core** contract -- `pseudoforge api METHOD PATH` -- which needs
#     nothing but bash and is always tested;
#   * the **transport** -- uvicorn on a random port, hit with curl -- which
#     needs FastAPI and is skipped cleanly without it.
#
# The one thing checked hardest is the refusal. POST /api/generate must be 501
# with the documented shape, and a refused conversion must be 409 with the
# core's own reason, because an API that quietly did something else would be
# worse than one that errored.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
PSM=$ROOT/pseudoforge

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

TMP=$(mktemp -d)
cleanup() { [ -n "${SRV_PID:-}" ] && kill "$SRV_PID" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

# A served tree with one real file and its provenance, so the native, convert
# and download paths have something true to work on.
export PF_VAR_DIR=$TMP/var
export PF_NATIVE_DIR=$PF_VAR_DIR/native
export PF_CACHE_DIR=$PF_VAR_DIR/cache
mkdir -p "$PF_NATIVE_DIR" "$PF_CACHE_DIR"

FIXTURE=$(find "$ROOT/tests/fixtures/upf" -type f 2>/dev/null | head -1)
VPSFIX=$(find "$ROOT/tests/fixtures/vps" -type f 2>/dev/null | head -1)
if [ -n "$FIXTURE" ]; then
    cp "$FIXTURE" "$PF_NATIVE_DIR/Si.test.UPF"
    printf 'element=Si\nfunctional=pbe\nfamily=paw\nrelativity=scalar\nengine=ld1\n' \
        > "$PF_NATIVE_DIR/Si.test.UPF.provenance"
fi
[ -n "$VPSFIX" ] && cp "$VPSFIX" "$PF_NATIVE_DIR/Te.test.vps"

# A deployed server always has an index; build it now so the endpoints below
# are exercised against a populated store rather than an empty one.
"$ROOT/pseudoforge" native index "$PF_NATIVE_DIR" >/dev/null 2>&1

# ---------------------------------------------------------------------------
# api <METHOD> <PATH> [body] -- body on stdout, status in API_STATUS
# ---------------------------------------------------------------------------
API_STATUS=
api() {
    local m=$1 p=$2 b=${3:-} err
    err=$TMP/err.$$
    "$PSM" api "$m" "$p" ${b:+"$b"} >/dev/null 2>"$err"
    API_STATUS=$(awk '/^status:/ { print $2; exit }' "$err")
    rm -f "$err"
}

json_has() { printf '%s' "$1" | grep -q "\"$2\""; }

printf '\n%s== the route table is the contract%s\n' "$DIM" "$RESET"
routes=$("$PSM" api --routes 2>/dev/null)
n=$(printf '%s\n' "$routes" | grep -c '^\(GET\|POST\)')
[ "$n" -ge 12 ] \
    && ok_ "$n routes declared" || bad_ "only $n routes"

for want in /api/health /api/version /api/routes /api/engines /api/formats /api/profiles /api/xc \
            /api/elements /api/native /api/convert /api/validate /api/generate; do
    printf '%s\n' "$routes" | grep -q " $want\b" \
        && ok_ "$want is declared" || bad_ "$want is missing from the table"
done

printf '\n%s== read endpoints answer what the CLI answers%s\n' "$DIM" "$RESET"
api GET /api/version
[ "$API_STATUS" = 200 ] && ok_ "GET /api/version is 200" || bad_ "version is $API_STATUS"
ver=$("$PSM" api GET /api/version 2>/dev/null)
json_has "$ver" 'version' && ok_ "  has 'version' key" || bad_ "  missing 'version' key"
json_has "$ver" 'tool' && ok_ "  has 'tool' key" || bad_ "  missing 'tool' key"

api GET /api/routes
[ "$API_STATUS" = 200 ] && ok_ "GET /api/routes is 200" || bad_ "routes is $API_STATUS"
rts=$("$PSM" api GET /api/routes 2>/dev/null)
json_has "$rts" 'routes' && ok_ "  has 'routes' key" || bad_ "  missing 'routes' key"

api GET /api/health
[ "$API_STATUS" = 200 ] && ok_ "GET /api/health is 200" || bad_ "health is $API_STATUS"
health=$("$PSM" api GET /api/health 2>/dev/null)
napi=$(printf '%s' "$health" | grep -o '"category"' | wc -l)
ncli=$("$PSM" doctor --json 2>/dev/null | grep -c '^{')
[ "$napi" = "$ncli" ] && [ "$napi" -gt 0 ] \
    && ok_ "health carries the same $napi records as doctor --json" \
    || bad_ "api has $napi records, doctor --json has $ncli" \
            "the endpoint is not calling the same checks"

api GET /api/engines
eng_n=$(printf '%s' "$("$PSM" api GET /api/engines 2>/dev/null)" | grep -o '"id"' | wc -l)
cli_n=$("$PSM" api --routes >/dev/null 2>&1; grep -c 'ENG_LABEL\[[a-z0-9]*\]=' "$PF_LIB/engines.sh")
[ "$eng_n" -ge 9 ] \
    && ok_ "GET /api/engines lists $eng_n engines" \
    || bad_ "only $eng_n engines listed"

for ep in /api/formats /api/profiles /api/xc /api/elements; do
    api GET "$ep"
    [ "$API_STATUS" = 200 ] && ok_ "GET $ep is 200" || bad_ "$ep is $API_STATUS"
done

body=$("$PSM" api GET /api/engines/ape 2>/dev/null)
json_has "$body" 'families' && ok_ "GET /api/engines/:name returns the engine" \
                            || bad_ "engine detail is missing fields"

printf '\n%s== a bad request is a 4xx, never a 500%s\n' "$DIM" "$RESET"
api GET /api/nope
[ "$API_STATUS" = 404 ] && ok_ "an unknown path is 404" || bad_ "unknown path gave $API_STATUS"

api POST /api/engines
[ "$API_STATUS" = 405 ] \
    && ok_ "a known path with the wrong method is 405, not 404" \
    || bad_ "wrong method gave $API_STATUS" \
            "405 and 404 tell a client different things: fix the verb, or fix the URL"

api GET /api/engines/no-such-engine
[ "$API_STATUS" = 404 ] && ok_ "an unknown engine is 404" || bad_ "unknown engine gave $API_STATUS"

api POST /api/convert
[ "$API_STATUS" = 400 ] && ok_ "a convert with no body is 400" || bad_ "empty convert gave $API_STATUS"

printf '{"id":"nope","to":"upf"}\n' > "$TMP/missing.json"
api POST /api/convert "$TMP/missing.json"
[ "$API_STATUS" = 404 ] && ok_ "converting a file that is not here is 404" \
                        || bad_ "unknown id gave $API_STATUS"

printf '\n%s== generation is refused, with the documented shape%s\n' "$DIM" "$RESET"
api POST /api/generate
gen=$("$PSM" api POST /api/generate 2>/dev/null)
[ "$API_STATUS" = 501 ] \
    && ok_ "POST /api/generate is 501" \
    || bad_ "generate returned $API_STATUS" "the VPS cannot generate and must say so"
for k in error message instructions install_url; do
    json_has "$gen" "$k" && ok_ "  the response carries \"$k\"" \
                         || bad_ "  the response is missing \"$k\""
done
printf '%s' "$gen" | grep -q 'generation_not_available_here' \
    && ok_ "  the error code is the documented one" \
    || bad_ "  the error code is not generation_not_available_here"
printf '%s' "$gen" | grep -q 'pseudoforge generate' \
    && ok_ "  and it says what to run instead" \
    || bad_ "  the refusal does not say what to do"

printf '\n%s== the served store%s\n' "$DIM" "$RESET"
if [ -f "$PF_NATIVE_DIR/index.tsv" ]; then
    ok_ "the index is built from the files"
    grep -q 'index.tsv' "$PF_NATIVE_DIR/index.tsv" \
        && bad_ "the index indexed itself" \
        || ok_ "and it does not contain itself"

    api GET /api/native
    [ "$API_STATUS" = 200 ] && ok_ "GET /api/native is 200" || bad_ "native list is $API_STATUS"

    if [ -n "$FIXTURE" ]; then
        api GET /api/native/Si.test.UPF
        [ "$API_STATUS" = 200 ] \
            && ok_ "GET /api/native/:id returns one file" \
            || bad_ "native detail is $API_STATUS"
        one=$("$PSM" api GET /api/native/Si.test.UPF 2>/dev/null)
        printf '%s' "$one" | grep -q '"format":"upf"' \
            && ok_ "the format is the registry id, not the file extension" \
            || bad_ "format is not normalised: $(printf '%s' "$one" | head -c 120)"
        printf '%s' "$one" | grep -q '"has_provenance":true' \
            && ok_ "the provenance sidecar is recorded" \
            || bad_ "provenance was not picked up"
    fi
else
    bad_ "no index was produced"
fi

api GET /api/native/../../etc/passwd
case $API_STATUS in
    400|404) ok_ "a traversal in an id is refused ($API_STATUS)" ;;
    *)       bad_ "a traversal gave $API_STATUS" "an id must never become a path" ;;
esac

printf '\n%s== conversion, and refusals with their reason%s\n' "$DIM" "$RESET"
if [ -n "$FIXTURE" ]; then
    printf '{"id":"Si.test.UPF","to":"xml"}\n' > "$TMP/conv.json"
    api POST /api/convert "$TMP/conv.json"
    conv=$("$PSM" api POST /api/convert "$TMP/conv.json" 2>/dev/null)
    case $API_STATUS in
        200)
            ok_ "upf to xml converts"
            json_has "$conv" 'kind' && ok_ "  and says what it cost (exact or lossy)" \
                                    || bad_ "  no kind in the response"
            json_has "$conv" 'download' && ok_ "  and where to get the file" \
                                        || bad_ "  no download path"
            dl=$(printf '%s' "$conv" | sed 's/.*"download":"\([^"]*\)".*/\1/')
            api GET "$dl"
            [ "$API_STATUS" = 200 ] \
                && ok_ "  the download path resolves" \
                || bad_ "  the advertised download is $API_STATUS"
            got=$("$PSM" api GET "$dl" 2>/dev/null)
            p=$(printf '%s' "$got" | sed 's/.*"path":"\([^"]*\)".*/\1/')
            [ -f "$p" ] && [ -s "$p" ] \
                && ok_ "  and points at a real, non-empty file" \
                || bad_ "  the download points at $p, which is not a file" \
                        "a directory passes a -s test; a converted file must be a file"
            ;;
        503) skip_ "upfconv.x not available for the conversion test" ;;
        *)   bad_ "convert returned $API_STATUS" "$(printf '%s' "$conv" | head -c 200)" ;;
    esac
else
    skip_ "no UPF fixture to convert"
fi

if [ -n "$VPSFIX" ]; then
    printf '{"id":"Te.test.vps","to":"upf"}\n' > "$TMP/ref.json"
    api POST /api/convert "$TMP/ref.json"
    ref=$("$PSM" api POST /api/convert "$TMP/ref.json" 2>/dev/null)
    [ "$API_STATUS" = 409 ] \
        && ok_ "a refused conversion is 409, not 200 and not 500" \
        || bad_ "refused conversion gave $API_STATUS"
    printf '%s' "$ref" | grep -q '"kind":"refused"' \
        && ok_ "  it says it was refused" || bad_ "  the response does not say refused"
    printf '%s' "$ref" | grep -q 'semilocal potentials' \
        && ok_ "  and carries the core's own reason, in full" \
        || bad_ "  the reason was dropped" \
                "a refusal without its reason is indistinguishable from a bug"
else
    skip_ "no .vps fixture to test a refusal with"
fi

printf '\n%s== validate needs no engine%s\n' "$DIM" "$RESET"
if [ -n "$FIXTURE" ]; then
    api POST /api/validate "$FIXTURE"
    v=$("$PSM" api POST /api/validate "$FIXTURE" 2>/dev/null)
    [ "$API_STATUS" = 200 ] && ok_ "POST /api/validate is 200" || bad_ "validate is $API_STATUS"
    printf '%s' "$v" | grep -q '"valid":true' \
        && ok_ "  it reports a verdict" || bad_ "  no verdict" "$v"
    json_has "$v" 'errors'   && ok_ "  and the errors"        || bad_ "  no errors field"
    json_has "$v" 'warnings' && ok_ "  and the warnings"      || bad_ "  no warnings field"
    api POST /api/validate
    [ "$API_STATUS" = 400 ] && ok_ "validate with no file is 400" || bad_ "empty validate is $API_STATUS"
else
    skip_ "no fixture to validate"
fi

for nf in "$ROOT/tests/fixtures/psp8/Si.pbe-oncv.psp8" \
          "$ROOT/tests/fixtures/gth/sample.gth" \
          "$ROOT/tests/fixtures/vps/Be.pz-adpack.vps"; do
    if [ -f "$nf" ]; then
        nv=$("$PSM" api POST /api/validate "$nf" 2>/dev/null)
        printf '%s' "$nv" | grep -q '"valid":true' \
            && ok_ "POST /api/validate accepts $(basename "$nf")" \
            || bad_ "POST /api/validate rejected $(basename "$nf")" "$nv"
    fi
done

PAWFIX="$ROOT/tests/fixtures/pawxml/Li.r2scan-atompaw.xml"
if [ -f "$PAWFIX" ]; then
    pv=$("$PSM" api POST /api/validate "$PAWFIX" 2>/dev/null)
    printf '%s' "$pv" | grep -q '"valid":true' \
        && ok_ "POST /api/validate accepts PAW-XML" \
        || bad_ "POST /api/validate rejected PAW-XML" "$pv"
    printf '%s' "$pv" | grep -q 'MGGA-R2SCAN-001' \
        && ok_ "  and captures warnings through pf_emit" \
        || bad_ "  warnings were lost" "$pv"
fi

printf 'not a pseudopotential\n' > "$TMP/bad.UPF"
bv=$("$PSM" api POST /api/validate "$TMP/bad.UPF" 2>/dev/null)
printf '%s' "$bv" | grep -q '"valid":false' \
    && ok_ "invalid UPF is reported invalid" \
    || bad_ "invalid UPF was not rejected" "$bv"
printf '%s' "$bv" | grep -q 'no <PP_HEADER> found' \
    && ok_ "  and captures errors through pf_emit" \
    || bad_ "  errors were lost" "$bv"

printf '\n%s== no logic lives only in the website%s\n' "$DIM" "$RESET"
# The handler must not re-decide what the converter already decides.
awk '/^http_h_convert\(\)/,/^}/' "$PF_LIB/http.sh" | grep -q 'cvt_convert' \
    && ok_ "the convert handler delegates to cvt_convert" \
    || bad_ "the handler converts by itself" "that judgement would exist twice"
awk '/^http_h_validate\(\)/,/^}/' "$PF_LIB/http.sh" | grep -q 'upf_validate_any' \
    && ok_ "the validate handler delegates to upf_validate_any" \
    || bad_ "the validate handler does not call upf_validate_any"
awk '/^http_h_health\(\)/,/^}/' "$PF_LIB/http.sh" | grep -q 'doctor_checks' \
    && ok_ "health calls doctor_checks, not its own probes" \
    || bad_ "health does its own checking"
grep -q 'pf_sink_use null' "$PF_LIB/http.sh" \
    && ok_ "messages are silenced so only the handler's JSON is the body" \
    || bad_ "a core warning could end up inside a JSON response"

# And the transport must not contain rules of its own.
if [ -f "$ROOT/server/app.py" ]; then
    grep -qE '^\s*(if|elif).*(refused|lossy|exact)' "$ROOT/server/app.py" \
        && bad_ "server/app.py decides about conversion kinds" \
                "that belongs in lib/convert.sh" \
        || ok_ "server/app.py carries no conversion logic"
    grep -q 'call_core' "$ROOT/server/app.py" \
        && ok_ "every endpoint goes through the core" \
        || bad_ "app.py answers something itself"

    n_dl=$(grep -cE '^\s*def download\(' "$ROOT/server/app.py")
    [ "$n_dl" -eq 1 ] \
        && ok_ "server/app.py has exactly one def download" \
        || bad_ "server/app.py has $n_dl download definitions (duplicate route)"
    awk '/@app\.get\("\/api\/download/,/return resp/' "$ROOT/server/app.py" | grep -q 'FileResponse' \
        && ok_ "server/app.py download route uses FileResponse" \
        || bad_ "server/app.py download route does not use FileResponse"
    if [ -x "$ROOT/server/.venv/bin/python3" ] && [ -n "$FIXTURE" ]; then
        head_ar=$("$ROOT/server/.venv/bin/python3" -c "
import os, sys
os.environ['PF_RC'] = '${PF_RC:-/tmp/.pseudoforgerc}'
os.environ['PF_VAR_DIR'] = '$PF_VAR_DIR'
os.environ['PF_NATIVE_DIR'] = '$PF_NATIVE_DIR'
os.environ['PF_CACHE_DIR'] = '$PF_CACHE_DIR'
sys.path.insert(0, '$ROOT/server')
import app
from pathlib import Path
app.PF_BIN = Path('$PSM')
app.PF_NATIVE_DIR = Path('$PF_NATIVE_DIR')
app.PF_CACHE_DIR = Path('$PF_CACHE_DIR')
res = app.download_head('Si.test.UPF')
print(res.headers.get('accept-ranges', '') if hasattr(res, 'headers') else '')
" 2>/dev/null)
        [ "$head_ar" = "bytes" ] \
            && ok_ "server/app.py download_head sets Accept-Ranges: bytes" \
            || bad_ "server/app.py download_head did not set Accept-Ranges: bytes (got '$head_ar')"
    fi

    if [ -f "$ROOT/server/requirements.txt" ]; then
        req_mk=$(grep -E '^\s*mkdocs(>=|==)' "$ROOT/server/requirements.txt" || true)
        req_mat=$(grep -E '^\s*mkdocs-material(>=|==)' "$ROOT/server/requirements.txt" || true)
        if [ -n "$req_mk" ] && [ -n "$req_mat" ]; then
            ok_ "server/requirements.txt ships mkdocs and mkdocs-material"
            printf '        found: %s, %s\n' "$req_mk" "$req_mat"
        else
            bad_ "server/requirements.txt missing mkdocs or mkdocs-material"
        fi
    fi
fi

printf '\n%s== the transport, over real HTTP%s\n' "$DIM" "$RESET"
UVICORN=${UVICORN_BIN:-$(command -v uvicorn 2>/dev/null || true)}
if [ -z "$UVICORN" ] || [ ! -x "$UVICORN" ]; then
    skip_ "uvicorn not installed (set UVICORN_BIN; pip install -r server/requirements.txt)"
elif ! command -v curl >/dev/null 2>&1; then
    skip_ "curl not available"
else
    PORT=$(( 20000 + RANDOM % 20000 ))
    ( cd "$ROOT/server" && PF_BIN=$PSM PF_VAR_DIR=$PF_VAR_DIR \
        PF_NATIVE_DIR=$PF_NATIVE_DIR PF_CACHE_DIR=$PF_CACHE_DIR \
        PF_RATE_LIMIT=5 PF_RATE_WINDOW=60 \
        "$UVICORN" app:app --host 127.0.0.1 --port "$PORT" --log-level error \
        >"$TMP/uvicorn.log" 2>&1 ) &
    SRV_PID=$!

    up=0
    for _ in $(seq 1 40); do
        curl -fsS "http://127.0.0.1:$PORT/api/version" >/dev/null 2>&1 && { up=1; break; }
        sleep 0.25
    done

    if [ "$up" != 1 ]; then
        bad_ "the server did not start" "$(tail -3 "$TMP/uvicorn.log" 2>/dev/null)"
    else
        ok_ "the server started on port $PORT"

        code=$(curl -s -o "$TMP/h.json" -w '%{http_code}' "http://127.0.0.1:$PORT/api/health")
        [ "$code" = 200 ] && ok_ "GET /api/health over HTTP is 200" || bad_ "health over HTTP is $code"
        grep -q '"category"' "$TMP/h.json" \
            && ok_ "  and the body is the core's records" || bad_ "  the body is not doctor records"

        code=$(curl -s -o "$TMP/g.json" -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/api/generate")
        [ "$code" = 501 ] \
            && ok_ "POST /api/generate over HTTP is 501" \
            || bad_ "generate over HTTP is $code"
        grep -q 'generation_not_available_here' "$TMP/g.json" \
            && ok_ "  with the documented error code" || bad_ "  wrong error code"

        code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/api/nope")
        [ "$code" = 404 ] && ok_ "an unknown path over HTTP is 404" || bad_ "unknown path is $code"

        if [ -n "$FIXTURE" ]; then
            head_ar=$(curl -s -I "http://127.0.0.1:$PORT/api/download/Si.test.UPF" | grep -i '^accept-ranges:' | tr -d '\r\n')
            echo "$head_ar" | grep -qi 'bytes' \
                && ok_ "HEAD /api/download returns Accept-Ranges: bytes" \
                || bad_ "HEAD /api/download did not return Accept-Ranges: bytes ($head_ar)"
        fi

        # Rate limiting: the service was started with a limit of 5.
        got429=0
        for _ in $(seq 1 12); do
            c=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/api/engines")
            [ "$c" = 429 ] && { got429=1; break; }
        done
        [ "$got429" = 1 ] \
            && ok_ "too many requests is 429" \
            || bad_ "the rate limit never fired" "one core cannot absorb a loop"

        code=$(curl -s -o /dev/null -w '%{http_code}' \
               "http://127.0.0.1:$PORT/api/download/../../../etc/passwd")
        case $code in
            200) bad_ "a traversal served a file outside the tree" "this is the one that matters" ;;
            *)   ok_ "a traversal over HTTP is refused ($code)" ;;
        esac
    fi
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
