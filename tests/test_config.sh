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

printf '\n%s== PF_VAR_DIR default and fallback chain%s\n' "$DIM" "$RESET"

# 1. Unset PF_VAR_DIR on non-VPS defaults to $HOME/.pseudoforge
tmp_home=$TMP/non_vps_home
mkdir -p "$tmp_home"
touch "$tmp_home/.pseudoforgerc"
out3=$(env -u PF_VAR_DIR -u PF_NATIVE_DIR HOME="$tmp_home" PF_RC="$tmp_home/.pseudoforgerc" "$PSM" native list 2>&1 || true)
if grep -q "$tmp_home/.pseudoforge/native" <<< "$out3" && ! grep -q "/var/lib/pseudoforge" <<< "$out3"; then
    ok_ "default PF_VAR_DIR uses \$HOME/.pseudoforge when /var/lib/pseudoforge is absent"
else
    bad_ "default PF_VAR_DIR failed to use \$HOME/.pseudoforge" "$out3"
fi

# 2. Explicit PF_VAR_DIR is respected
explicit_dir=$TMP/explicit_var
out4=$(env -u PF_NATIVE_DIR PF_VAR_DIR="$explicit_dir" HOME="$tmp_home" PF_RC="$tmp_home/.pseudoforgerc" "$PSM" native list 2>&1 || true)
if grep -q "$explicit_dir/native" <<< "$out4"; then
    ok_ "explicit PF_VAR_DIR is respected ($explicit_dir)"
else
    bad_ "explicit PF_VAR_DIR was not respected" "$out4"
fi

# 3. Simulated /var/lib/pseudoforge (writable directory) is used when PF_VAR_DIR is unset
mock_vps=$TMP/mock_vps_var
mkdir -p "$mock_vps"
out5=$(env -u PF_VAR_DIR -u PF_NATIVE_DIR PF_VPS_VAR_DIR="$mock_vps" HOME="$tmp_home" PF_RC="$tmp_home/.pseudoforgerc" "$PSM" native list 2>&1 || true)
if grep -q "$mock_vps/native" <<< "$out5"; then
    ok_ "writable deployment dir is used when PF_VAR_DIR is unset ($mock_vps)"
else
    bad_ "deployment dir fallback was not used" "$out5"
fi

printf '\n%s%d passed%s, %s%d failed%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET"
[ "$fail" -eq 0 ]
