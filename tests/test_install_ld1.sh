#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test_install_ld1.sh -- tests for build_ld1, pf_ask_install_ld1, and QE discovery
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

TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/pf_test_ld1_XXXXXX")
trap 'rm -rf "$TEST_TMP"' EXIT

export HOME="$TEST_TMP/home"
export PF_RC="$HOME/.pseudoforgerc"
export PF_QE_SEARCH_DIRS="$TEST_TMP/nonexistent/*"
mkdir -p "$HOME" "$TEST_TMP/remote"

pf_engines_load

# ---------------------------------------------------------------------------
# Create fake QE source tarball
# ---------------------------------------------------------------------------
QE_FAKE_DIR="$TEST_TMP/qe_src/qe-7.4.1"
mkdir -p "$QE_FAKE_DIR"
cat << 'EOF' > "$QE_FAKE_DIR/configure"
#!/bin/sh
touch .configured
exit 0
EOF
chmod +x "$QE_FAKE_DIR/configure"

cat << 'EOF' > "$QE_FAKE_DIR/Makefile"
ld1:
	touch ld1.x
	chmod +x ld1.x
EOF

tar -czf "$TEST_TMP/remote/qe-7.4.1.tar.gz" -C "$TEST_TMP/qe_src" qe-7.4.1

printf '\n%s== Phase 4: build_ld1 and pf_ask_install_ld1 tests%s\n' "$DIM" "$RESET"

# 1. Mock download + build with PF_AUTO_INSTALL_LD1=yes
export QE_VERSION=7.4.1
export QE_URL="file://$TEST_TMP/remote/qe-7.4.1.tar.gz"
export PF_AUTO_INSTALL_LD1=yes

if build_ld1 > "$TEST_TMP/build.log" 2>&1; then
    src_archive="$(eng_src_dir)/qe-7.4.1.tar.gz"
    if [ -f "$src_archive" ]; then
        ok_ "mock QE: tarball fetched to eng_src_dir"
    else
        bad_ "mock QE: tarball missing from $(eng_src_dir)"
    fi

    if [ -f "$(eng_builddir)/ld1/qe-7.4.1/.configured" ] || [ -f "$(eng_builddir)/ld1/.configured" ]; then
        ok_ "mock QE: ./configure executed"
    else
        bad_ "mock QE: ./configure did not run"
    fi

    if [ -x "$(eng_bindir)/ld1.x" ]; then
        ok_ "mock QE: ld1.x installed to eng_bindir"
    else
        bad_ "mock QE: ld1.x not executable in $(eng_bindir)"
    fi

    if grep -q "LD1_BIN.*ld1.x" "$PF_RC" 2>/dev/null; then
        ok_ "mock QE: LD1_BIN recorded in PF_RC"
    else
        bad_ "mock QE: LD1_BIN not recorded in $PF_RC"
    fi
else
    bad_ "mock QE: build_ld1 failed" "$(cat "$TEST_TMP/build.log")"
fi

# 2. No-prompt refusal: PF_AUTO_INSTALL_LD1=no
unset LD1_BIN
rm -f "$(eng_bindir)/ld1.x" "$PF_RC"
export PF_AUTO_INSTALL_LD1=no
if ! pf_ask_install_ld1 >/dev/null 2>&1; then
    ok_ "no-prompt: PF_AUTO_INSTALL_LD1=no refused without calling build_ld1"
else
    bad_ "no-prompt: PF_AUTO_INSTALL_LD1=no returned 0"
fi

# Also test CLI refusal: pseudoforge generate with ld1 and PF_AUTO_INSTALL_LD1=no
gen_out=$("$ROOT/pseudoforge" generate -e Si -p psl-high 2>&1 || true)
if printf '%s\n' "$gen_out" | grep -qi 'ld1.x is required and not installed'; then
    ok_ "cli generate: fails with expected message when ld1 is missing and auto-install refused"
else
    bad_ "cli generate: did not print expected refusal message" "$gen_out"
fi

# 3. Non-tty treated as no: PF_AUTO_INSTALL_LD1 unset, non-tty stdin
unset PF_AUTO_INSTALL_LD1
nontty_out=$(pf_ask_install_ld1 < /dev/null 2>&1 || true)
if ! pf_ask_install_ld1 < /dev/null >/dev/null 2>&1; then
    if printf '%s\n' "$nontty_out" | grep -qi 'needs ld1.x'; then
        ok_ "non-tty: treated as no without prompt"
    else
        bad_ "non-tty: unexpected message" "$nontty_out"
    fi
else
    bad_ "non-tty: returned 0 unexpectedly"
fi

# 4. Prompt declined via pty: answer 'n'
# 5. Prompt accepted via pty: answer 'y'
rm -f "$(eng_bindir)/ld1.x" "$PF_RC"
unset LD1_BIN
pty_test_rc=0
python3 -c '
import pty, os, sys

def run_test(answer, expect_rc):
    master, slave = pty.openpty()
    pid = os.fork()
    if pid == 0:
        os.close(master)
        os.dup2(slave, 0)
        os.dup2(slave, 1)
        os.dup2(slave, 2)
        os.close(slave)
        cmd = """
        unset PF_AUTO_INSTALL_LD1
        unset LD1_BIN
        pf_ask_install_ld1
        """
        os.execlp("bash", "bash", "-c", f"""
        . "{os.environ["PF_LIB"]}/core.sh"
        for m in sink config deps elements xc namelist profiles metadata formats gth sssp convert doctor params engines build fetch recipe; do
            . "{os.environ["PF_LIB"]}/$m.sh"
        done
        {cmd}
        """)
    else:
        os.close(slave)
        os.write(master, (answer + "\n").encode())
        out = b""
        while True:
            try:
                c = os.read(master, 1024)
                if not c:
                    break
                out += c
            except OSError:
                break
        os.close(master)
        _, status = os.waitpid(pid, 0)
        code = status >> 8
        if code != expect_rc:
            print(f"FAILED: answer {answer!r} expected {expect_rc}, got {code}. Output: {out.decode()}", file=sys.stderr)
            sys.exit(1)

run_test("n", 1)
run_test("y", 0)
' || pty_test_rc=$?

if [ "$pty_test_rc" -eq 0 ]; then
    ok_ "interactive pty: 'n' returns 1, 'y' installs and returns 0"
else
    bad_ "interactive pty prompt test failed"
fi

# 6. QE discovery and prompt to record
mkdir -p "$TEST_TMP/fake_opt/bin"
cat << 'EOF' > "$TEST_TMP/fake_opt/bin/ld1.x"
#!/bin/sh
exit 0
EOF
chmod +x "$TEST_TMP/fake_opt/bin/ld1.x"

# Test discovery via QE_ROOT_DIR
rm -f "$PF_RC"
unset LD1_BIN
export QE_ROOT_DIR="$TEST_TMP/fake_opt"
export PF_PROMPT_QE_RECORD=0
deps_resolve_qe
if [ "${LD1_BIN:-}" = "$TEST_TMP/fake_opt/bin/ld1.x" ]; then
    ok_ "qe discovery: resolved LD1_BIN from QE_ROOT_DIR"
else
    bad_ "qe discovery: failed to resolve from QE_ROOT_DIR (got: ${LD1_BIN:-<unset>})"
fi

# Test discovery via search dirs
rm -f "$PF_RC" "$(eng_bindir)/ld1.x"
unset LD1_BIN QE_ROOT_DIR
export PF_QE_SEARCH_DIRS="$TEST_TMP/fake_opt/bin/ld1.x"
export PF_PROMPT_QE_RECORD=0
deps_resolve_qe
if [ "${LD1_BIN:-}" = "$TEST_TMP/fake_opt/bin/ld1.x" ]; then
    ok_ "qe discovery: resolved LD1_BIN from search dirs"
else
    bad_ "qe discovery: failed to resolve from search dirs (got: ${LD1_BIN:-<unset>})"
fi

# Test interactive record prompt for discovered QE
rm -f "$PF_RC"
export PF_PROMPT_QE_RECORD=1
record_test_rc=0
python3 -c '
import pty, os, sys

master, slave = pty.openpty()
pid = os.fork()
if pid == 0:
    os.close(master)
    os.dup2(slave, 0)
    os.dup2(slave, 1)
    os.dup2(slave, 2)
    os.close(slave)
    os.execlp("bash", "bash", "-c", f"""
    . "{os.environ["PF_LIB"]}/core.sh"
    for m in sink config deps elements xc namelist profiles metadata formats gth sssp convert doctor params engines build fetch recipe; do
        . "{os.environ["PF_LIB"]}/$m.sh"
    done
    unset LD1_BIN
    deps_resolve_qe
    """)
else:
    os.close(slave)
    os.write(master, b"y\n")
    out = b""
    while True:
        try:
            c = os.read(master, 1024)
            if not c:
                break
            out += c
        except OSError:
            break
    os.close(master)
    _, status = os.waitpid(pid, 0)
    sys.exit(status >> 8)
' || record_test_rc=$?

if [ "$record_test_rc" -eq 0 ] && grep -q "LD1_BIN.*ld1.x" "$PF_RC" 2>/dev/null; then
    ok_ "qe discovery: interactive prompt recorded discovered LD1_BIN in PF_RC"
else
    bad_ "qe discovery: failed to record in PF_RC"
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
