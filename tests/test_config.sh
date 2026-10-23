#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test_config.sh -- verify config precedence (env vars win over config file).
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
PSM=$ROOT/pseudoforge

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

printf '\n%s== config priority (environment vs file)%s\n' "$DIM" "$RESET"

rc_file=$TMP/test_rc
cat > "$rc_file" <<'EOF'
LD1_BIN=/opt/espresso
ONCVPSP_BIN=/opt/oncvpsp
EOF

out=$(PF_RC="$rc_file" LD1_BIN=/tmp/mock "$PSM" config --show 2>&1)
val=$(printf '%s\n' "$out" | awk '$1 == "LD1_BIN" { print $2 }')

if [ "$val" = "/tmp/mock" ]; then
    ok_ "LD1_BIN in environment wins over config file ($val)"
else
    bad_ "LD1_BIN did not win over config file (got: '$val', expected: '/tmp/mock')" "$out"
fi

# Also check without env override, config file value is used
out2=$(PF_RC="$rc_file" "$PSM" config --show 2>&1)
val2=$(printf '%s\n' "$out2" | awk '$1 == "LD1_BIN" { print $2 }')

if [ "$val2" = "/opt/espresso" ]; then
    ok_ "without env override, config file value is used ($val2)"
else
    bad_ "config file value was not used (got: '$val2', expected: '/opt/espresso')" "$out2"
fi

printf '\n%s%d passed%s, %s%d failed%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET"
[ "$fail" -eq 0 ]
