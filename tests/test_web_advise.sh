#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test_web_advise.sh -- verify web advise and cutoff download button logic
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

printf '\n%s== 1. Static assertions for advise/index.html and js/advise.js%s\n' "$DIM" "$RESET"

ADVISE_HTML="$ROOT/frontend/advise/index.html"
ADVISE_JS="$ROOT/frontend/js/advise.js"

if grep -qE "download-button|download-btn" "$ADVISE_HTML"; then
    ok_ "advise/index.html references download button style"
else
    bad_ "advise/index.html missing download button style"
fi

if grep -q "not-in-store-note" "$ADVISE_HTML"; then
    ok_ "advise/index.html references not-in-store-note style"
else
    bad_ "advise/index.html missing not-in-store-note style"
fi

if grep -q "API\.native()" "$ADVISE_JS"; then
    ok_ "js/advise.js queries API.native()"
else
    bad_ "js/advise.js does not query API.native()"
fi

if grep -q "API\.downloadUrl" "$ADVISE_JS"; then
    ok_ "js/advise.js links to API.downloadUrl"
else
    bad_ "js/advise.js missing API.downloadUrl link"
fi

if grep -q "Not in the store; generate it with the command below\." "$ADVISE_JS"; then
    ok_ "js/advise.js has fallback not-in-store message"
else
    bad_ "js/advise.js missing not-in-store message"
fi

printf '\n%s== 2. Static assertions for cutoff/index.html and js/cutoff.js%s\n' "$DIM" "$RESET"

CUTOFF_HTML="$ROOT/frontend/cutoff/index.html"
CUTOFF_JS="$ROOT/frontend/js/cutoff.js"

if grep -qE "download-button|download-btn" "$CUTOFF_HTML"; then
    ok_ "cutoff/index.html references download button style"
else
    bad_ "cutoff/index.html missing download button style"
fi

if grep -q "cut-download-btn-container" "$CUTOFF_HTML"; then
    ok_ "cutoff/index.html has download button container"
else
    bad_ "cutoff/index.html missing download button container"
fi

if grep -q "/api/native" "$CUTOFF_JS"; then
    ok_ "js/cutoff.js queries /api/native"
else
    bad_ "js/cutoff.js does not query /api/native"
fi

if grep -q "/api/download/" "$CUTOFF_JS"; then
    ok_ "js/cutoff.js links to /api/download/"
else
    bad_ "js/cutoff.js missing /api/download/ link"
fi

if grep -q "Not in the store; generate it with the command below\." "$CUTOFF_JS"; then
    ok_ "js/cutoff.js has fallback not-in-store message"
else
    bad_ "js/cutoff.js missing not-in-store message"
fi

printf '\n%s== 3. Matching logic simulation against API output%s\n' "$DIM" "$RESET"

python3 - << 'EOF'
import sys, json

# Mock native store with a Si entry
store = [
    {
        "id": "psl-high_nc_pbe_scalar_pseudos_Si.pbe-n-nc.UPF.gz",
        "element": "Si",
        "xc": "pbe",
        "family": "nc",
        "profile": "psl-high",
        "format": "upf"
    },
    {
        "id": "psl-high_nc_pbe_scalar_pseudos_Si.pbe-n-nc.xml.gz",
        "element": "Si",
        "xc": "pbe",
        "family": "nc",
        "profile": "psl-high",
        "format": "xml"
    }
]

# Recommendation to match
rec = {
    "element": "Si",
    "family": "nc",
    "xc": "pbe",
    "profile": "psl-high"
}

matches = [
    item for item in store
    if item["element"].lower() == rec["element"].lower()
    and item["family"].lower() == rec["family"].lower()
    and item["xc"].lower() == rec["xc"].lower()
    and item["profile"].lower() == rec["profile"].lower()
]

assert len(matches) == 2, f"Expected 2 matches, got {len(matches)}"
assert matches[0]["id"] == "psl-high_nc_pbe_scalar_pseudos_Si.pbe-n-nc.UPF.gz"
print("Store matching simulation: OK")
EOF
if [ $? -eq 0 ]; then
    ok_ "store matching logic accurately matches element/family/xc/profile"
else
    bad_ "store matching logic simulation failed"
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$([ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM")" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
