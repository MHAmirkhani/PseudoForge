#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test_tools_tui.sh -- test suite for the TUI tools menu and its 6 entries
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT="$ROOT" PF_LIB="$ROOT/lib" PF_DATA="$ROOT/data"

for m in core sink config deps elements xc namelist profiles metadata formats gth sssp params engines recipe advise provenance element coverage recent capabilities cli ui tui; do
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

# 1. Functions are defined
for fn in tui_tools tui_advise tui_provenance tui_element tui_coverage tui_recent tui_capabilities; do
    if declare -F "$fn" >/dev/null; then
        ok_ "function $fn is defined"
    else
        bad_ "function $fn missing"
    fi
done

# 2. Mock ui functions to verify tool invocations
ui_input() { echo "${MOCK_INPUT:-}"; }
ui_menu()  { echo "${MOCK_MENU:-}"; }
ui_msg()   { MOCK_MSG_TITLE="$1"; MOCK_MSG_BODY="$2"; return 0; }
ui_text()  { MOCK_TEXT_TITLE="$1"; MOCK_TEXT_BODY=$(cat "$2"); return 0; }

# Test tui_capabilities
MOCK_TEXT_TITLE=""
MOCK_TEXT_BODY=""
tui_capabilities
grep -q "With the store alone" <<< "$MOCK_TEXT_BODY" && ok_ "tui_capabilities renders capability matrix" || bad_ "tui_capabilities failed"

# Test tui_advise
MOCK_INPUT="Fe"
MOCK_MENU="phonons"
MOCK_MSG_TITLE=""
MOCK_MSG_BODY=""
tui_advise
grep -q "Advisory: Fe (phonons)" <<< "$MOCK_MSG_TITLE" && ok_ "tui_advise sets correct title" || bad_ "tui_advise title mismatch"
grep -q "For Fe, phonons" <<< "$MOCK_MSG_BODY" && ok_ "tui_advise outputs recommendations" || bad_ "tui_advise output missing"

# Test tui_element
MOCK_INPUT="Fe"
MOCK_MSG_TITLE=""
MOCK_MSG_BODY=""
tui_element
grep -q "Element: Fe" <<< "$MOCK_MSG_TITLE" && ok_ "tui_element sets correct title" || bad_ "tui_element title mismatch"

# Test tui_coverage
MOCK_INPUT="psl-high"
MOCK_TEXT_TITLE=""
MOCK_TEXT_BODY=""
tui_coverage
grep -q "Coverage Matrix" <<< "$MOCK_TEXT_TITLE" && ok_ "tui_coverage sets correct title" || bad_ "tui_coverage title mismatch"

# Test tui_recent
MOCK_INPUT="3"
MOCK_TEXT_TITLE=""
MOCK_TEXT_BODY=""
tui_recent
grep -q "Recent Files" <<< "$MOCK_TEXT_TITLE" && ok_ "tui_recent sets correct title" || bad_ "tui_recent title mismatch"

# Test tui_tools dispatch
invoked=""
tui_advise() { invoked="advise"; return 0; }
MOCK_MENU="advise"
# Run once and break loop
ui_menu() {
    if [ -z "$invoked" ]; then
        echo "advise"
    else
        return 1
    fi
}
tui_tools || true
[ "$invoked" = "advise" ] && ok_ "tui_tools dispatches advise" || bad_ "tui_tools dispatch failed"

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
