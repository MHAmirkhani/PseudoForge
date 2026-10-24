#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test_build_fetch.sh -- verify engine source archive fetching and validation.
#
# Tests run entirely offline using file:// URLs:
#   1. file:// success with valid checksum in MANIFEST
#   2. checksum mismatch removes file and returns 1
#   3. missing MANIFEST succeeds with a warning
#   4. URL unreachable returns 1 and names the URL
#   5. libxc glob picks up libxc-*.tar.gz
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

TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/pf_test_fetch_XXXXXX")
trap 'rm -rf "$TEST_TMP"' EXIT

# Isolate engines directory under test temp dir
export ENGINE_DIR="$TEST_TMP/engines"
mkdir -p "$TEST_TMP/remote" "$ENGINE_DIR"

pf_engines_load

printf '\n%s== Phase 2: build_fetch_src tests%s\n' "$DIM" "$RESET"

# 1. file:// success with valid checksum in MANIFEST
printf 'dummy oncvpsp source content\n' > "$TEST_TMP/remote/oncvpsp-master.zip"
sha_oncvpsp=$(sha256sum "$TEST_TMP/remote/oncvpsp-master.zip" | awk '{print $1}')
printf 'oncvpsp-master.zip\t%s\t1234\t2026-10-24\n' "$sha_oncvpsp" > "$TEST_TMP/MANIFEST.txt"

export PF_ENGINES_SRC_URL="file://$TEST_TMP/remote"
export PF_MANIFEST_PATH="$TEST_TMP/MANIFEST.txt"

rm -f "$(eng_src_dir)/oncvpsp-master.zip"
if build_fetch_src oncvpsp >/dev/null 2>&1 && [ -f "$(eng_src_dir)/oncvpsp-master.zip" ]; then
    ok_ "file:// success: source downloaded and verified against MANIFEST.txt"
else
    bad_ "file:// success failed"
fi

# 2. checksum mismatch: returns 1 and removes the file
rm -f "$(eng_src_dir)/oncvpsp-master.zip"
printf 'oncvpsp-master.zip\t0000000000000000000000000000000000000000000000000000000000000000\t1234\t2026-10-24\n' > "$TEST_TMP/MANIFEST.txt"

if ! build_fetch_src oncvpsp >/dev/null 2>&1; then
    if [ ! -f "$(eng_src_dir)/oncvpsp-master.zip" ]; then
        ok_ "checksum mismatch: returns 1 and removes the invalid file"
    else
        bad_ "checksum mismatch did not remove corrupted file"
    fi
else
    bad_ "checksum mismatch returned 0 instead of failing"
fi

# 3. missing MANIFEST: succeeds with a warning
rm -f "$(eng_src_dir)/oncvpsp-master.zip"
export PF_MANIFEST_PATH="$TEST_TMP/nonexistent-manifest.txt"
warn_out=$(build_fetch_src oncvpsp 2>&1 || true)
if [ -f "$(eng_src_dir)/oncvpsp-master.zip" ] && printf '%s\n' "$warn_out" | grep -qi 'manifest'; then
    ok_ "missing MANIFEST: succeeds with a warning"
else
    bad_ "missing MANIFEST failed or did not warn" "$warn_out"
fi

# 4. URL unreachable: PF_ENGINES_SRC_URL=file:///nonexistent returns 1 naming URL
rm -f "$(eng_src_dir)/oncvpsp-master.zip"
export PF_ENGINES_SRC_URL="file:///nonexistent-pf-dir-test"
unreach_out=$(build_fetch_src oncvpsp 2>&1 || true)
if ! build_fetch_src oncvpsp >/dev/null 2>&1; then
    if printf '%s\n' "$unreach_out" | grep -q 'file:///nonexistent-pf-dir-test'; then
        ok_ "unreachable URL: returns 1 with message naming the URL"
    else
        bad_ "unreachable URL failed to name the URL in error output" "$unreach_out"
    fi
else
    bad_ "unreachable URL returned 0"
fi

# 5. libxc glob: libxc-7.1.2.tar.gz at PF_ENGINES_SRC_URL, call build_fetch_src libxc
export PF_ENGINES_SRC_URL="file://$TEST_TMP/remote"
export PF_MANIFEST_PATH="$TEST_TMP/MANIFEST_libxc.txt"
printf 'dummy libxc 7.1.2 content\n' > "$TEST_TMP/remote/libxc-7.1.2.tar.gz"
sha_libxc=$(sha256sum "$TEST_TMP/remote/libxc-7.1.2.tar.gz" | awk '{print $1}')
printf 'libxc-7.1.2.tar.gz\t%s\t5678\t2026-10-24\n' "$sha_libxc" > "$TEST_TMP/MANIFEST_libxc.txt"

rm -f "$(eng_src_dir)/libxc-7.1.2.tar.gz"
ENG_SRC[libxc]=""
if build_fetch_src libxc >/dev/null 2>&1 && [ -f "$(eng_src_dir)/libxc-7.1.2.tar.gz" ]; then
    ok_ "libxc glob: discovered and fetched libxc-7.1.2.tar.gz"
else
    bad_ "libxc glob fetch failed"
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
