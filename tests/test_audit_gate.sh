#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test_audit_gate.sh -- verify audit isolation and non-hanging execution.
#
# Regression tests for Phase 2.5:
# 1. ~/.pseudoforgerc pointing LD1_BIN to /nonexistent does not prevent
#    tools/audit.sh from using the mock engine and completing successfully.
# 2. tools/audit.sh completes when stdin is redirected from /dev/null
#    (proves audit.sh provides its own stdin redirection and never hangs).
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

printf '\n%s== audit gate isolation%s\n' "$DIM" "$RESET"

# 1. Create a fake config file that sets LD1_BIN=/nonexistent
fake_home=$TMP/fake_home
mkdir -p "$fake_home"
cat > "$fake_home/.pseudoforgerc" <<'EOF'
LD1_BIN=/nonexistent
EOF

# Run tools/audit.sh --quick with HOME pointing to fake_home (300s timeout to allow full suite)
out1=$(HOME="$fake_home" timeout -s KILL 300 bash "$ROOT/tools/audit.sh" --quick 2>&1)
rc1=$?
if [ "$rc1" -eq 0 ]; then
    ok_ "audit.sh --quick uses mock LD1 and exits 0 despite LD1_BIN=/nonexistent in ~/.pseudoforgerc"
else
    bad_ "audit.sh --quick failed or hung when ~/.pseudoforgerc points LD1_BIN to /nonexistent (rc=$rc1)" "$out1"
fi

# 2. Run tools/audit.sh --quick < /dev/null
out2=$(timeout -s KILL 300 bash "$ROOT/tools/audit.sh" --quick < /dev/null 2>&1)
rc2=$?
if [ "$rc2" -eq 0 ]; then
    ok_ "audit.sh --quick < /dev/null completes and exits 0"
else
    bad_ "audit.sh --quick < /dev/null failed or hung (rc=$rc2)" "$out2"
fi

# 3. Verify 'generate an element a profile does not cover' appears in AUDIT-raw.tsv
if grep -q '^PASS[[:space:]]*generate an element a profile does not cover' "$ROOT/AUDIT-raw.tsv"; then
    ok_ "generate an element a profile does not cover is recorded in AUDIT-raw.tsv with ^PASS"
else
    bad_ "generate an element a profile does not cover missing from AUDIT-raw.tsv"
fi

if grep -q '\\n' "$ROOT/AUDIT-raw.tsv"; then
    bad_ "literal \\n detected in AUDIT-raw.tsv"
else
    ok_ "AUDIT-raw.tsv contains no literal \\n"
fi

printf '\n%s%d passed%s, %s%d failed%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET"
[ "$fail" -eq 0 ]
