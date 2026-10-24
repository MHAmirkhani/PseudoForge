#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test_build_adpack.sh -- verify adpack build recipe and makefile patching.
#
# Tests run entirely offline:
#   1. dry-run: PF_DRY_RUN=1 prints the make command and does not execute it
#   2. patch verification: rewrites CC and LIB lines in source/makefile
#   3. build_all loop in lib/build.sh contains adpack
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data

for m in core sink config deps elements xc namelist profiles metadata formats gth sssp convert doctor params engines build fetch recipe; do
    # shellcheck disable=SC1090
    . "$PF_LIB/$m.sh" || { echo "cannot load $m.sh" >&2; exit 1; }
done

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/pf_test_adpack_XXXXXX")
trap 'rm -rf "$TEST_TMP"' EXIT

export ENGINE_DIR="$TEST_TMP/engines"
mkdir -p "$ENGINE_DIR"

pf_engines_load

printf '\n%s== Phase 3: build_adpack tests%s\n' "$DIM" "$RESET"

# Setup fake source tree with original adpack makefile
fake_src="$TEST_TMP/adpack-src"
mkdir -p "$fake_src/source"
cat > "$fake_src/source/makefile" <<'MKEOF'
CC  = gcc -Dnoomp -std=c99 -O3 -I/usr/local/include -I/home/ozaki/include
LIB = -L/home/ozaki/lib -latlas_p4 -static

all:
	@echo "building adpack"
MKEOF

# 1. dry-run: PF_DRY_RUN=1 prints make command and does not execute it
out=$(PF_ADPACK_SRC_OVERRIDE="$fake_src" PF_DRY_RUN=1 build_adpack 2>&1)
rc=$?

if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q 'dry-run: ( cd .* && make -j.* )'; then
    ok_ "dry-run: PF_DRY_RUN=1 prints make command and does not execute make"
else
    bad_ "dry-run failed or did not print make command (rc=$rc)" "$out"
fi

# 2. patch verification: confirm sed rewrote CC and LIB lines
if grep -q '^CC      = gcc -Dnoomp -std=c99 -O3$' "$fake_src/source/makefile" && \
   grep -q '^LIB     = -lblas -llapack$' "$fake_src/source/makefile"; then
    ok_ "patch verification: rewrote CC and LIB lines in source/makefile"
else
    bad_ "patch verification failed" "$(cat "$fake_src/source/makefile")"
fi

# 3. build_all loop lists adpack
if grep -E 'for eng in.*adpack.*do' "$PF_LIB/build.sh" >/dev/null 2>&1; then
    ok_ "build_all lists adpack in its iteration loop"
else
    bad_ "build_all does not list adpack in its iteration loop"
fi

# 4. build_engine case statement handles adpack
if grep -E '^\s*adpack\)\s*build_adpack' "$PF_LIB/build.sh" >/dev/null 2>&1; then
    ok_ "build_engine dispatches adpack to build_adpack"
else
    bad_ "build_engine does not dispatch adpack to build_adpack"
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
