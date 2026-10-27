#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Tests for pseudoforge compare (CLI, API, TUI presence)
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
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

printf '\n%s== 1. CLI compare%s\n' "$DIM" "$RESET"

# 1.1 --help
out1=$("$PSM" compare --help 2>&1 || true)
if grep -q "usage: pseudoforge compare" <<< "$out1"; then
    ok_ "pseudoforge compare --help prints usage"
else
    bad_ "pseudoforge compare --help failed" "$out1"
fi

# 1.2 missing arguments
out2=$("$PSM" compare 2>&1 || true)
if grep -q "usage: pseudoforge compare" <<< "$out2"; then
    ok_ "pseudoforge compare without arguments prints usage"
else
    bad_ "pseudoforge compare without arguments did not print usage" "$out2"
fi

# Create two mock UPF fixtures for comparison
f1="$TMP/Fe1.UPF"
f2="$TMP/Fe2.UPF"

cat <<'UPF1' > "$f1"
<UPF version="2.0.1">
  <PP_HEADER
     element="Fe"
     pseudo_type="NC"
     relativistic="scalar"
     functional="PBE"
     author="oncvpsp"
  />
  <PP_MESH dx="0.01" mesh="100"/>
</UPF>
UPF1

cat <<'UPF2' > "$f2"
<UPF version="2.0.1">
  <PP_HEADER
     element="Fe"
     pseudo_type="PAW"
     relativistic="scalar"
     functional="PBE"
     author="atompaw"
  />
  <PP_MESH dx="0.01" mesh="120"/>
  <PP_RHOATOM> 0.1 0.2 </PP_RHOATOM>
</UPF>
UPF2

# 1.3 CLI --diff
out3=$("$PSM" compare "$f1" "$f2" --diff 2>&1 || true)
if grep -q "Comparison:" <<< "$out3" && grep -q "Diff summary:" <<< "$out3"; then
    ok_ "pseudoforge compare --diff prints human comparison"
else
    bad_ "pseudoforge compare --diff failed" "$out3"
fi

# 1.4 CLI --json
out4=$("$PSM" compare "$f1" "$f2" --json 2>&1 || true)
if grep -q '"diff"' <<< "$out4" && grep -q '"warnings"' <<< "$out4"; then
    ok_ "pseudoforge compare --json outputs structured JSON"
else
    bad_ "pseudoforge compare --json failed" "$out4"
fi
if python3 -m json.tool <<< "$out4" >/dev/null 2>&1; then
    ok_ "pseudoforge compare --json produces valid JSON"
else
    bad_ "pseudoforge compare --json produces invalid JSON" "$out4"
fi

printf '\n%s== 2. API compare%s\n' "$DIM" "$RESET"

# 2.1 Missing parameters
req_empty="$TMP/req_empty.json"
printf '{}' > "$req_empty"
out5=$("$PSM" api POST /api/compare "$req_empty" 2>&1 || true)
if grep -q "status: 400" <<< "$out5"; then
    ok_ "POST /api/compare with missing body parameters returns 400"
else
    bad_ "POST /api/compare did not return 400 on empty request" "$out5"
fi

# 2.2 Non-existent file / id
req_missing="$TMP/req_missing.json"
printf '{"a":"nonexistent1.UPF","b":"nonexistent2.UPF"}' > "$req_missing"
out6=$("$PSM" api POST /api/compare "$req_missing" 2>&1 || true)
if grep -q "status: 404" <<< "$out6"; then
    ok_ "POST /api/compare with non-existent id returns 404"
else
    bad_ "POST /api/compare did not return 404 on missing file" "$out6"
fi

# 2.3 Valid compare
req_valid="$TMP/req_valid.json"
printf '{"a":"%s","b":"%s"}' "$f1" "$f2" > "$req_valid"
out7=$("$PSM" api POST /api/compare "$req_valid" 2>&1 || true)
if grep -q "status: 200" <<< "$out7" && grep -q '"engine_changed": true' <<< "$out7"; then
    ok_ "POST /api/compare returns 200 and diff fields"
else
    bad_ "POST /api/compare failed on valid request" "$out7"
fi
out7_body=$(grep -v '^status:' <<< "$out7")
if python3 -m json.tool <<< "$out7_body" >/dev/null 2>&1; then
    ok_ "POST /api/compare produces valid JSON body"
else
    bad_ "POST /api/compare produces invalid JSON body" "$out7"
fi

printf '\n%s== 3. TUI presence%s\n' "$DIM" "$RESET"

if grep -qE '^[[:space:]]*compare[[:space:]]+' "$PF_LIB/tui.sh"; then
    ok_ "lib/tui.sh contains compare in tui_tools menu"
else
    bad_ "lib/tui.sh missing compare in tui_tools menu"
fi

if grep -q "tui_compare()" "$PF_LIB/tui.sh"; then
    ok_ "lib/tui.sh implements tui_compare"
else
    bad_ "lib/tui.sh missing tui_compare"
fi

printf '\n%s%d passed%s, %s%d failed%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$([ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM")" "$fail" "$RESET"
[ "$fail" -eq 0 ]
