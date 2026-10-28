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

printf '\n%s== MAX_PARALLEL_JOBS defaults and precedence%s\n' "$DIM" "$RESET"

# 1. With MAX_PARALLEL_JOBS unset: equals capped nproc (min(nproc, 8))
n_cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
[ "$n_cores" -gt 8 ] && expected_jobs=8 || expected_jobs=$n_cores

empty_rc=$TMP/empty_rc
touch "$empty_rc"

jobs_out=$(env -u MAX_PARALLEL_JOBS PF_RC="$empty_rc" "$PSM" config --show 2>&1)
jobs_val=$(printf '%s\n' "$jobs_out" | awk '$1 == "MAX_PARALLEL_JOBS" { print $2 }')
if [ "$jobs_val" = "$expected_jobs" ]; then
    ok_ "MAX_PARALLEL_JOBS unset defaults to min(nproc, 8) ($jobs_val)"
else
    bad_ "MAX_PARALLEL_JOBS default expected $expected_jobs, got '$jobs_val'" "$jobs_out"
fi

# 2. With MAX_PARALLEL_JOBS=2 in environment: value stays 2
jobs_out2=$(env MAX_PARALLEL_JOBS=2 PF_RC="$empty_rc" "$PSM" config --show 2>&1)
jobs_val2=$(printf '%s\n' "$jobs_out2" | awk '$1 == "MAX_PARALLEL_JOBS" { print $2 }')
if [ "$jobs_val2" = "2" ]; then
    ok_ "MAX_PARALLEL_JOBS=2 in environment stays 2 ($jobs_val2)"
else
    bad_ "MAX_PARALLEL_JOBS in env expected 2, got '$jobs_val2'" "$jobs_out2"
fi

# 3. With -j 16 on the command line: the flag wins
cmd_out=$("$PSM" build-command -e Si -j 16 2>&1)
if [[ "$cmd_out" =~ -j[[:space:]]+16 ]]; then
    ok_ "-j 16 flag wins over nproc default in generated command"
else
    bad_ "-j 16 flag did not set jobs to 16" "$cmd_out"
fi

printf '\n%s%d passed%s, %s%d failed%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET"
[ "$fail" -eq 0 ]
