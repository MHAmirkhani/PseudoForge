#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Tests for pseudoforge cutoff (CLI, API, TUI presence)
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

printf '\n%s== 1. CLI cutoff%s\n' "$DIM" "$RESET"

# 1.1 --help
out1=$("$PSM" cutoff --help 2>&1 || true)
if grep -q "usage: pseudoforge cutoff" <<< "$out1"; then
    ok_ "pseudoforge cutoff --help prints usage"
else
    bad_ "pseudoforge cutoff --help failed" "$out1"
fi

# 1.2 missing element
out2=$("$PSM" cutoff 2>&1 || true)
if grep -q "element required" <<< "$out2"; then
    ok_ "pseudoforge cutoff without element errors"
else
    bad_ "pseudoforge cutoff without element did not error" "$out2"
fi

# 1.3 standard lookup
out3=$("$PSM" cutoff -e Fe 2>&1 || true)
if grep -q "Recommended Cutoff: Fe" <<< "$out3" && grep -q "ecutwfc:" <<< "$out3"; then
    ok_ "pseudoforge cutoff -e Fe returns recommendation"
else
    bad_ "pseudoforge cutoff -e Fe failed" "$out3"
fi

# 1.4 precision lookup as JSON
out4=$("$PSM" cutoff -e Fe --accuracy precision --json 2>&1 || true)
if grep -q '"ecutwfc": 90' <<< "$out4" && grep -q '"ecutrho": 1080' <<< "$out4"; then
    ok_ "pseudoforge cutoff -e Fe --accuracy precision --json returns valid cutoffs"
else
    bad_ "pseudoforge cutoff -e Fe --json failed" "$out4"
fi

# 1.5 project scan override
mock_proj="$TMP/mock_project"
mkdir -p "$mock_proj/tests"
printf 'Fe\t45\t360\tFe.mock.UPF\n' > "$mock_proj/tests/cutoffs.tsv"

out5=$("$PSM" cutoff -e Fe -o "$mock_proj" --json 2>&1 || true)
if grep -q '"ecutwfc": 45' <<< "$out5" && grep -q '"source": "project scan"' <<< "$out5"; then
    ok_ "pseudoforge cutoff -e Fe -o <proj> uses project scan"
else
    bad_ "pseudoforge cutoff -e Fe -o <proj> failed to use project scan" "$out5"
fi

# 1.6 refusal on unknown element
out6=$("$PSM" cutoff -e NonExistent 2>&1 || true)
if grep -q "no recommended cutoff found" <<< "$out6"; then
    ok_ "pseudoforge cutoff on unknown element refuses cleanly"
else
    bad_ "pseudoforge cutoff on unknown element did not refuse" "$out6"
fi

printf '\n%s== 2. API cutoff%s\n' "$DIM" "$RESET"

# 2.1 missing element
out7=$("$PSM" api GET /api/cutoff 2>&1 || true)
if grep -q "status: 400" <<< "$out7"; then
    ok_ "GET /api/cutoff without element returns 400"
else
    bad_ "GET /api/cutoff without element did not return 400" "$out7"
fi

# 2.2 valid element
out8=$("$PSM" api GET "/api/cutoff?element=Fe&accuracy=precision" 2>&1 || true)
if grep -q "status: 200" <<< "$out8" && grep -q '"ecutwfc": 90' <<< "$out8"; then
    ok_ "GET /api/cutoff?element=Fe returns 200 and cutoffs"
else
    bad_ "GET /api/cutoff?element=Fe failed" "$out8"
fi

# 2.3 refusal
out9=$("$PSM" api GET "/api/cutoff?element=NonExistent" 2>&1 || true)
if grep -q "status: 404" <<< "$out9"; then
    ok_ "GET /api/cutoff?element=NonExistent returns 404"
else
    bad_ "GET /api/cutoff?element=NonExistent did not return 404" "$out9"
fi

printf '\n%s== 3. TUI presence%s\n' "$DIM" "$RESET"

if grep -qE '^[[:space:]]*cutoff[[:space:]]+' "$PF_LIB/tui.sh"; then
    ok_ "lib/tui.sh contains cutoff in tui_tools menu"
else
    bad_ "lib/tui.sh missing cutoff in tui_tools menu"
fi

if grep -q "tui_cutoff()" "$PF_LIB/tui.sh"; then
    ok_ "lib/tui.sh implements tui_cutoff"
else
    bad_ "lib/tui.sh missing tui_cutoff"
fi

printf '\n%s%d passed%s, %s%d failed%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$([ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM")" "$fail" "$RESET"
[ "$fail" -eq 0 ]
