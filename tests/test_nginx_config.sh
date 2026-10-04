#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# The Nginx configuration.
#
# One property dominates: **order**. `location /` is a prefix match and matches
# everything, so if it comes before `/docs/` or `/api/` it swallows them, and
# the symptom is the front page being served where the documentation should be
# — with no error anywhere.
#
# The rest is the contract the deployment depends on: the API is proxied and
# not served as files, the docs and the frontend are static, uploads are capped
# to what the service accepts, and the rate limit exists before the request
# reaches a one-core machine.
#
# `nginx -t` is used when nginx is installed; the structural checks need
# nothing and always run.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
CONF=$ROOT/deploy/nginx/pseudoforge.conf

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

printf '\n%s== the file exists and parses%s\n' "$DIM" "$RESET"
[ -f "$CONF" ] && ok_ "deploy/nginx/pseudoforge.conf exists" || { bad_ "no nginx config"; exit 1; }

# Braces must balance, or nginx -t is the first thing to find out.
open=$(grep -o '{' "$CONF" | wc -l); close=$(grep -o '}' "$CONF" | wc -l)
[ "$open" = "$close" ] \
    && ok_ "braces balance ($open)" || bad_ "$open { against $close }"

printf '\n%s== every location the deployment needs%s\n' "$DIM" "$RESET"
for loc in '/api/' '/docs/' '/library/' '/'; do
    grep -qE "^\s*location $loc \{" "$CONF" \
        && ok_ "location $loc is present" \
        || bad_ "location $loc is missing"
done

printf '\n%s== and in the right order%s\n' "$DIM" "$RESET"
# location / matches everything; anything after it is unreachable.
api=$(grep -n 'location /api/ {'     "$CONF" | cut -d: -f1)
docs=$(grep -n 'location /docs/ {'   "$CONF" | cut -d: -f1)
lib=$(grep -n 'location /library/ {' "$CONF" | cut -d: -f1)
root=$(grep -n 'location / {'        "$CONF" | cut -d: -f1)

[ -n "$root" ] || bad_ "no catch-all location"
for pair in "api:$api" "docs:$docs" "library:$lib"; do
    name=${pair%%:*}; line=${pair##*:}
    if [ -n "$line" ] && [ -n "$root" ] && [ "$line" -lt "$root" ]; then
        ok_ "/$name/ comes before the catch-all (line $line < $root)"
    else
        bad_ "/$name/ is at line $line, after the catch-all at $root" \
             "location / matches everything; /$name/ would never be reached"
    fi
done

printf '\n%s== the API is proxied, not served%s\n' "$DIM" "$RESET"
api_block=$(awk '/location \/api\/ \{/,/^\s*\}/' "$CONF")
printf '%s' "$api_block" | grep -q 'proxy_pass' \
    && ok_ "/api/ is proxy_pass'd to the service" \
    || bad_ "/api/ does not proxy" "it would be served as static files"
printf '%s' "$api_block" | grep -q 'X-Forwarded-For' \
    && ok_ "the client address is forwarded" \
    || bad_ "no X-Forwarded-For; per-IP rate limiting would see only nginx"
printf '%s' "$api_block" | grep -q 'proxy_read_timeout' \
    && ok_ "a read timeout is set" \
    || bad_ "no read timeout" "a conversion on one core is slow, not hung"

printf '\n%s== the docs and the frontend are static%s\n' "$DIM" "$RESET"
docs_block=$(awk '/location \/docs\/ \{/,/^\s*\}/' "$CONF")
printf '%s' "$docs_block" | grep -q 'alias .*docs' \
    && ok_ "/docs/ aliases the built site" || bad_ "/docs/ has no alias"
printf '%s' "$docs_block" | grep -q 'try_files' \
    && ok_ "  and resolves directory URLs to index.html" \
    || bad_ "  no try_files: mkdocs use_directory_urls would 404"

root_block=$(awk '/location \/ \{/,/^\s*\}/' "$CONF")
printf '%s' "$root_block" | grep -q 'try_files' \
    && ok_ "/ falls back for the frontend" || bad_ "/ has no try_files"

printf '\n%s== limits match the service%s\n' "$DIM" "$RESET"
grep -q 'client_max_body_size' "$CONF" \
    && ok_ "an upload limit is set" \
    || bad_ "no client_max_body_size" "an 8 MB upload would reach a 1 GB machine"

# The two limits must agree, or one of them is decorative.
ngx_mb=$(grep -oE 'client_max_body_size[[:space:]]+[0-9]+' "$CONF" | grep -oE '[0-9]+' | head -1)
svc_mb=$(grep -oE 'str\([0-9]+ \* 1024 \* 1024\)' "$ROOT/server/app.py" \
         | grep -oE '[0-9]+' | head -1)
if [ -n "$ngx_mb" ] && [ -n "$svc_mb" ]; then
    [ "$ngx_mb" = "$svc_mb" ] \
        && ok_ "nginx and the service agree on ${ngx_mb}MB" \
        || bad_ "nginx allows ${ngx_mb}MB, the service allows ${svc_mb}MB" \
                "the smaller one wins and the larger is a lie"
else
    skip_ "could not read both upload limits"
fi

grep -q 'limit_req_zone' "$CONF" \
    && ok_ "a rate-limit zone is declared" || bad_ "no rate limiting at the edge"
grep -q 'limit_req_status 429' "$CONF" \
    && ok_ "  and a limited request is 429" \
    || bad_ "  limited requests would get nginx's default 503"

printf '\n%s== the domain is not committed%s\n' "$DIM" "$RESET"
grep -q 'PSEUDOFORGE_DOMAIN' "$CONF" \
    && ok_ "server_name is a placeholder the installer substitutes" \
    || bad_ "a real domain is committed in the config" \
            "machine-specific values belong in deploy/local/"

printf '\n%s== nginx itself agrees%s\n' "$DIM" "$RESET"
if ! command -v nginx >/dev/null 2>&1; then
    skip_ "nginx not installed (structural checks above still ran)"
else
    # -t needs a full config; wrap the site in a minimal one and point the
    # roots at a temporary tree so it is checking syntax, not the filesystem.
    mkdir -p "$TMP/www" "$TMP/docs" "$TMP/native" "$TMP/logs" "$TMP/client"
    sed -e "s|PSEUDOFORGE_DOMAIN|test.invalid|" \
        -e "s|/var/lib/pseudoforge/www|$TMP/www|" \
        -e "s|/var/lib/pseudoforge/docs/|$TMP/docs/|" \
        -e "s|/var/lib/pseudoforge/native/|$TMP/native/|" \
        -e "s|/var/log/nginx|$TMP/logs|g" \
        "$CONF" > "$TMP/site.conf"
    {
        printf 'pid %s/nginx.pid;\n' "$TMP"
        printf 'error_log %s/error.log;\n' "$TMP/logs"
        printf 'events { worker_connections 16; }\n'
        printf 'http {\n'
        printf '  client_body_temp_path %s/client;\n' "$TMP"
        printf '  proxy_temp_path %s/proxy;\n' "$TMP"
        printf '  fastcgi_temp_path %s/fastcgi;\n' "$TMP"
        printf '  uwsgi_temp_path %s/uwsgi;\n' "$TMP"
        printf '  scgi_temp_path %s/scgi;\n' "$TMP"
        printf '  access_log %s/access.log;\n' "$TMP/logs"
        printf '  include %s;\n' "$TMP/site.conf"
        printf '}\n'
    } > "$TMP/nginx.conf"

    out=$(nginx -t -c "$TMP/nginx.conf" -p "$TMP" 2>&1)
    if printf '%s' "$out" | grep -q 'syntax is ok'; then
        ok_ "nginx -t accepts the configuration"
    else
        bad_ "nginx -t rejected it" "$(printf '%s' "$out" | head -3)"
    fi
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
