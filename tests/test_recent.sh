#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test_recent.sh -- test suite for the recent files tool
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT="$ROOT" PF_LIB="$ROOT/lib" PF_DATA="$ROOT/data"

for m in core sink config deps elements xc namelist profiles metadata formats gth sssp params engines recipe advise provenance element coverage recent cli http; do
    # shellcheck disable=SC1090
    . "$PF_LIB/$m.sh" || { echo "cannot load $m.sh" >&2; exit 1; }
done

pf_config_defaults 2>/dev/null || true
pf_elements_load; pf_xc_load; pf_profiles_load; pf_engines_load; pf_metadata_load

GREEN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  SKIP  %s\n' "$1"; skip=$((skip + 1)); }

TEST_STORE=$(_recent_find_native_dir)
if [ -f "$TEST_STORE/index.tsv" ]; then
    # 1. Default recent_files runs
    if recent_files 10; then
        ok_ "recent_files succeeds with default count"
        [ "${#RECENT_OUT_FILENAME[@]}" -gt 0 ] && ok_ "found files in store (${#RECENT_OUT_FILENAME[@]})" || bad_ "no files found"
    else
        bad_ "recent_files failed"
    fi

    # 2. Count limit
    if recent_files 3; then
        [ "${#RECENT_OUT_FILENAME[@]}" -le 3 ] && ok_ "count limit respected (${#RECENT_OUT_FILENAME[@]})" || bad_ "count limit failed"
    else
        bad_ "recent_files with count 3 failed"
    fi

    # 3. Human renderer
    h_out=$(recent_files 5 && recent_render_human 5 2>&1)
    grep -q "most recent files in the store" <<< "$h_out" && ok_ "human output includes header" || bad_ "header missing"
    [ -n "${RECENT_OUT_FILENAME[0]:-}" ] && grep -q "${RECENT_OUT_FILENAME[0]}" <<< "$h_out" && ok_ "human output includes first filename" || bad_ "filename missing"

    # 4. JSON renderer
    j_out=$(recent_files 2 && recent_render_json 2>&1)
    grep -q '"date":' <<< "$j_out" && ok_ "json output includes date" || bad_ "date missing from json"
    grep -q '"filename":' <<< "$j_out" && ok_ "json output includes filename" || bad_ "filename missing from json"
    grep -q '"profile":' <<< "$j_out" && ok_ "json output includes profile" || bad_ "profile missing from json"
    grep -q '"family":' <<< "$j_out" && ok_ "json output includes family" || bad_ "family missing from json"
    grep -q '"xc":' <<< "$j_out" && ok_ "json output includes xc" || bad_ "xc missing from json"

    # 5. CLI pseudoforge recent
    cli_out=$("$ROOT/pseudoforge" recent --count 3 2>&1)
    grep -q "most recent files in the store" <<< "$cli_out" && ok_ "CLI recent outputs header" || bad_ "CLI header missing"
else
    skip_ "no native index.tsv available to test recent store files"
    skip_ "count limit (needs store)"
    skip_ "human renderer (needs store)"
    skip_ "json renderer (needs store)"
    skip_ "CLI recent (needs store)"
fi

# 6. CLI help
help_out=$("$ROOT/pseudoforge" recent --help 2>&1)
grep -q "pseudoforge recent" <<< "$help_out" && ok_ "CLI recent --help works" || bad_ "help output missing"

# 7. HTTP API GET /api/recent
api_out=$(http_handle GET "/api/recent?count=2" 2>&1)
grep -q '"filename":' <<< "$api_out" && ok_ "HTTP API GET /api/recent returns json with filename" || bad_ "HTTP API failed"

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
