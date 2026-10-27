#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test_capabilities.sh -- test suite for the capabilities tool
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT="$ROOT" PF_LIB="$ROOT/lib" PF_DATA="$ROOT/data"

for m in core sink config deps elements xc namelist profiles metadata formats gth sssp params engines recipe advise provenance element coverage recent capabilities cli http; do
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

# 1. capabilities_for
if capabilities_for; then
    ok_ "capabilities_for succeeds"
    [ "${CAP_COUNT[engines]}" -eq 9 ] && ok_ "records 9 engines" || bad_ "engine count mismatch"
else
    bad_ "capabilities_for failed"
fi

# 2. Human renderer
h_out=$(capabilities_for && capabilities_render_human 2>&1)
grep -q "With the store alone (this website):" <<< "$h_out" && ok_ "human output includes store alone" || bad_ "store alone missing"
grep -q "With PseudoForge installed, no engines:" <<< "$h_out" && ok_ "human output includes cli no engines" || bad_ "no engines missing"
grep -q "With PseudoForge and engines installed:" <<< "$h_out" && ok_ "human output includes cli with engines" || bad_ "with engines missing"
grep -q "Install:  ./install.sh --bootstrap" <<< "$h_out" && ok_ "human output includes install command" || bad_ "install command missing"
grep -q "docs/getting-started/installation.md" <<< "$h_out" && ok_ "human output includes docs path" || bad_ "docs path missing"

# 3. JSON renderer
j_out=$(capabilities_for && capabilities_render_json 2>&1)
grep -q '"store_alone":' <<< "$j_out" && ok_ "json output includes store_alone" || bad_ "store_alone missing from json"
grep -q '"cli_no_engines":' <<< "$j_out" && ok_ "json output includes cli_no_engines" || bad_ "cli_no_engines missing from json"
grep -q '"cli_with_engines":' <<< "$j_out" && ok_ "json output includes cli_with_engines" || bad_ "cli_with_engines missing from json"
grep -q '"supported": true' <<< "$j_out" && ok_ "json output includes supported true" || bad_ "supported true missing"
grep -q '"supported": false' <<< "$j_out" && ok_ "json output includes supported false" || bad_ "supported false missing"

# 4. CLI pseudoforge capabilities
cli_out=$("$ROOT/pseudoforge" capabilities 2>&1)
grep -q "With the store alone" <<< "$cli_out" && ok_ "CLI capabilities outputs header" || bad_ "CLI header missing"

# 5. CLI help
help_out=$("$ROOT/pseudoforge" capabilities --help 2>&1)
grep -q "pseudoforge capabilities" <<< "$help_out" && ok_ "CLI capabilities --help works" || bad_ "help output missing"

# 6. HTTP API GET /api/capabilities
api_out=$(http_handle GET "/api/capabilities" 2>&1)
grep -q '"store_alone":' <<< "$api_out" && ok_ "HTTP API GET /api/capabilities returns json" || bad_ "HTTP API failed"

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
