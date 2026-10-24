#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test_install.sh -- tests for install.sh flags, distro commands, and dry runs
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/pf_test_install_XXXXXX")
trap 'rm -rf "$TEST_TMP"' EXIT

printf '\n%s== Phase 5: install.sh tests%s\n' "$DIM" "$RESET"

# 1. --help lists every flag
help_out=$("$ROOT/install.sh" --help 2>&1)
for flag in "--deps" "--bootstrap" "--dry-run" "--yes" "--help"; do
    if printf '%s\n' "$help_out" | grep -q -- "$flag"; then
        ok_ "help: lists $flag"
    else
        bad_ "help: missing $flag" "$help_out"
    fi
done

# 2. --deps --dry-run --yes on debian
TEST_HOME="$TEST_TMP/fake_home"
mkdir -p "$TEST_HOME"
deb_out=$(HOME="$TEST_HOME" FAKE_DISTRO=debian "$ROOT/install.sh" --deps --dry-run --yes 2>&1)
if printf '%s\n' "$deb_out" | grep -q "apt-get install -y gfortran gcc make libblas-dev liblapack-dev unzip curl"; then
    ok_ "debian dry-run: prints expected apt-get command with build packages"
else
    bad_ "debian dry-run: unexpected output" "$deb_out"
fi

if [ -z "$(ls -A "$TEST_HOME")" ]; then
    ok_ "debian dry-run: does not touch \$HOME"
else
    bad_ "debian dry-run: touched \$HOME" "$(ls -A "$TEST_HOME")"
fi

# 3. Same for fedora, arch, macos via $FAKE_DISTRO
fed_out=$(HOME="$TEST_HOME" FAKE_DISTRO=fedora "$ROOT/install.sh" --deps --dry-run --yes 2>&1)
if printf '%s\n' "$fed_out" | grep -q "dnf install -y gcc-gfortran gcc make blas-devel lapack-devel unzip curl"; then
    ok_ "fedora dry-run: prints expected dnf command"
else
    bad_ "fedora dry-run: unexpected output" "$fed_out"
fi

arch_out=$(HOME="$TEST_HOME" FAKE_DISTRO=arch "$ROOT/install.sh" --deps --dry-run --yes 2>&1)
if printf '%s\n' "$arch_out" | grep -q "pacman -S --needed --noconfirm gcc-fortran gcc make blas lapack unzip curl"; then
    ok_ "arch dry-run: prints expected pacman command"
else
    bad_ "arch dry-run: unexpected output" "$arch_out"
fi

mac_out=$(HOME="$TEST_HOME" FAKE_DISTRO=macos "$ROOT/install.sh" --deps --dry-run --yes 2>&1)
if printf '%s\n' "$mac_out" | grep -q "brew install gcc make openblas unzip curl"; then
    ok_ "macos dry-run: prints expected brew command"
else
    bad_ "macos dry-run: unexpected output" "$mac_out"
fi

# 4. --bootstrap --dry-run prints both commands
boot_out=$(HOME="$TEST_HOME" FAKE_DISTRO=debian "$ROOT/install.sh" --bootstrap --dry-run 2>&1)
if printf '%s\n' "$boot_out" | grep -q "apt-get install -y" && printf '%s\n' "$boot_out" | grep -q "engines build all"; then
    ok_ "bootstrap dry-run: prints both package install and engines build commands"
else
    bad_ "bootstrap dry-run: missing commands" "$boot_out"
fi

# 5. Run where every package is present: exit 0, prints the QE note
# Setup fake bin directory with mock unzip so build_missing_tools is empty
MOCK_BIN="$TEST_TMP/mock_bin"
mkdir -p "$MOCK_BIN"
cat << 'EOF' > "$MOCK_BIN/unzip"
#!/bin/sh
exit 0
EOF
chmod +x "$MOCK_BIN/unzip"

PRES_HOME="$TEST_TMP/present_home"
mkdir -p "$PRES_HOME"
pres_rc=0
pres_out=$(PATH="$MOCK_BIN:$PATH" HOME="$PRES_HOME" "$ROOT/install.sh" --deps --yes "$PRES_HOME/bin" 2>&1) || pres_rc=$?

if [ "$pres_rc" -eq 0 ]; then
    ok_ "all packages present: exits 0"
else
    bad_ "all packages present: exited with code $pres_rc" "$pres_out"
fi

if printf '%s\n' "$pres_out" | grep -qi "Quantum ESPRESSO is not installed by this script"; then
    ok_ "all packages present: prints QE note"
else
    bad_ "all packages present: did not print QE note" "$pres_out"
fi

if [ -L "$PRES_HOME/bin/pseudoforge" ]; then
    ok_ "all packages present: creates pseudoforge symlink"
else
    bad_ "all packages present: missing pseudoforge symlink"
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
