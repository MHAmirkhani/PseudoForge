#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Tests for pseudoforge build-command (CLI, API, TUI presence)
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

printf '\n%s== 1. CLI build-command%s\n' "$DIM" "$RESET"

# 1.1 --help
out1=$("$PSM" build-command --help 2>&1 || true)
if grep -q "usage: pseudoforge build-command" <<< "$out1"; then
    ok_ "pseudoforge build-command --help prints usage"
else
    bad_ "pseudoforge build-command --help failed" "$out1"
fi

# 1.2 missing element
out2=$("$PSM" build-command 2>&1 || true)
if grep -q "no elements given" <<< "$out2"; then
    ok_ "pseudoforge build-command without element errors"
else
    bad_ "pseudoforge build-command without element did not error" "$out2"
fi

# 1.3 valid command construction
out3=$("$PSM" build-command -e Fe -t paw -x pbe --engine atompaw --relativity full 2>&1 || true)
if grep -q "pseudoforge generate -e Fe" <<< "$out3" && grep -q "atompaw" <<< "$out3" && grep -q "paw" <<< "$out3"; then
    ok_ "pseudoforge build-command returns exact generate command"
else
    bad_ "pseudoforge build-command failed to construct valid command" "$out3"
fi

# 1.4 refusal on incompatible choices (ONCVPSP + PAW)
out4=$("$PSM" build-command -e Fe -t paw --engine oncvpsp 2>&1 || true)
if grep -q "cannot make paw" <<< "$out4"; then
    ok_ "pseudoforge build-command refuses ONCVPSP + PAW"
else
    bad_ "pseudoforge build-command did not refuse incompatible choices" "$out4"
fi

# 1.5 JSON output
out5=$("$PSM" build-command -e Fe -t paw -x pbe --json 2>&1 || true)
if grep -q '"command": "pseudoforge generate -e Fe' <<< "$out5" && grep -q '"explanation"' <<< "$out5"; then
    ok_ "pseudoforge build-command --json returns structured JSON"
else
    bad_ "pseudoforge build-command --json failed" "$out5"
fi

printf '\n%s== 2. API build-command%s\n' "$DIM" "$RESET"

# 2.1 missing element
out6=$("$PSM" api GET /api/build-command 2>&1 || true)
if grep -q "status: 400" <<< "$out6"; then
    ok_ "GET /api/build-command without element returns 400"
else
    bad_ "GET /api/build-command without element did not return 400" "$out6"
fi

# 2.2 valid command
out7=$("$PSM" api GET "/api/build-command?element=Fe&family=paw&xc=pbe&engine=atompaw&relativity=full" 2>&1 || true)
if grep -q "status: 200" <<< "$out7" && grep -q "pseudoforge generate -e Fe" <<< "$out7"; then
    ok_ "GET /api/build-command returns 200 and command"
else
    bad_ "GET /api/build-command failed on valid choices" "$out7"
fi

# 2.3 refusal with 409
out8=$("$PSM" api GET "/api/build-command?element=Fe&family=paw&engine=oncvpsp" 2>&1 || true)
if grep -q "status: 409" <<< "$out8" && grep -q "cannot make paw" <<< "$out8"; then
    ok_ "GET /api/build-command returns 409 on incompatible choices"
else
    bad_ "GET /api/build-command did not return 409 on refusal" "$out8"
fi

printf '\n%s== 3. TUI presence%s\n' "$DIM" "$RESET"

if grep -qE '^[[:space:]]*build-command[[:space:]]+' "$PF_LIB/tui.sh"; then
    ok_ "lib/tui.sh contains build-command in tui_tools menu"
else
    bad_ "lib/tui.sh missing build-command in tui_tools menu"
fi

if grep -q "tui_build_command()" "$PF_LIB/tui.sh"; then
    ok_ "lib/tui.sh implements tui_build_command"
else
    bad_ "lib/tui.sh missing tui_build_command"
fi

printf '\n%s%d passed%s, %s%d failed%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$([ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM")" "$fail" "$RESET"
[ "$fail" -eq 0 ]
