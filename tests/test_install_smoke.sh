#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test_install_smoke.sh -- end-to-end installation smoke test in clean HOME
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/pf_test_smoke_XXXXXX")
trap 'rm -rf "$TEST_TMP"' EXIT

export HOME="$TEST_TMP/fake-home"
mkdir -p "$HOME"
unset PF_RC PF_VAR_DIR PF_NATIVE_DIR LD1_BIN QE_ROOT_DIR
# Ensure mock binaries from test suites or parent environments are not on PATH
CLEAN_PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'tests/mock' | paste -sd: -)
export PATH="$CLEAN_PATH"

printf '\n%s== Phase 7: installation smoke tests%s\n' "$DIM" "$RESET"

# 1. install.sh --help lists --deps, --bootstrap, --yes, --dry-run
help_out=$("$ROOT/install.sh" --help 2>&1)
for flag in "--deps" "--bootstrap" "--yes" "--dry-run"; do
    if printf '%s\n' "$help_out" | grep -q -- "$flag"; then
        ok_ "install.sh --help lists $flag"
    else
        bad_ "install.sh --help missing $flag" "$help_out"
    fi
done

# 2. install.sh --deps --dry-run --yes prints a package command
pkg_out=$(FAKE_DISTRO=debian "$ROOT/install.sh" --deps --dry-run --yes 2>&1)
if printf '%s\n' "$pkg_out" | grep -q "apt-get install -y"; then
    ok_ "install.sh --deps --dry-run prints a package command"
else
    bad_ "install.sh --deps --dry-run did not print package command" "$pkg_out"
fi

# 3. install.sh (no flags) creates $HOME/.local/bin/pseudoforge
inst_out=$("$ROOT/install.sh" 2>&1)
if [ -L "$HOME/.local/bin/pseudoforge" ] && [ -x "$HOME/.local/bin/pseudoforge" ]; then
    ok_ "install.sh creates executable symlink at \$HOME/.local/bin/pseudoforge"
else
    bad_ "install.sh did not create symlink at \$HOME/.local/bin/pseudoforge" "$inst_out"
fi

# 4. that symlink executes: $HOME/.local/bin/pseudoforge version
ver_out=$("$HOME/.local/bin/pseudoforge" version 2>&1)
if printf '%s\n' "$ver_out" | grep -q "PseudoForge 1.3"; then
    ok_ "symlink executes: pseudoforge version prints PseudoForge 1.3"
else
    bad_ "symlink failed to print version" "$ver_out"
fi

# 5. doctor --check exits 1 in the empty HOME
check_rc=0
"$HOME/.local/bin/pseudoforge" doctor --check >/dev/null 2>&1 || check_rc=$?
if [ "$check_rc" -eq 1 ]; then
    ok_ "doctor --check exits 1 in empty HOME"
else
    bad_ "doctor --check did not exit 1 (got $check_rc)"
fi

# 6. doctor (no flag) exits 0
doc_rc=0
"$HOME/.local/bin/pseudoforge" doctor >/dev/null 2>&1 || doc_rc=$?
if [ "$doc_rc" -eq 0 ]; then
    ok_ "doctor (no flags) exits 0"
else
    bad_ "doctor (no flags) exited with $doc_rc"
fi

# 7. engines build --help lists ld1 and adpack
build_help=$("$HOME/.local/bin/pseudoforge" engines build --help 2>&1)
if printf '%s\n' "$build_help" | grep -q "ld1" && printf '%s\n' "$build_help" | grep -q "adpack"; then
    ok_ "engines build --help lists ld1 and adpack"
else
    bad_ "engines build --help missing ld1 or adpack" "$build_help"
fi

# 8. with PF_AUTO_INSTALL_LD1=no, `pseudoforge generate -e Si -p psl-high` fails with the "ld1.x is required" message, not a generic error
export PF_AUTO_INSTALL_LD1=no
export PF_QE_SEARCH_DIRS="$TEST_TMP/nonexistent/*"
gen_out=$("$HOME/.local/bin/pseudoforge" generate -e Si -p psl-high 2>&1 || true)
if printf '%s\n' "$gen_out" | grep -qi "ld1.x is required and not installed"; then
    ok_ "generate psl-high with PF_AUTO_INSTALL_LD1=no fails with 'ld1.x is required'"
else
    bad_ "generate psl-high did not print 'ld1.x is required'" "$gen_out"
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
