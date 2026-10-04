#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# The documentation site builds, strictly.
#
# `mkdocs build --strict` turns warnings into errors, so a link to a page that
# does not exist, a page missing from the navigation, or a malformed config
# fails the build instead of producing a site with a dead link in it.
#
# MkDocs is a Python tool and is deliberately **not** a dependency: the docs are
# Markdown and read perfectly well in the repository or on a git forge. So this
# suite skips cleanly when mkdocs is absent, and the structural checks in
# tests/test_docs.sh -- which need nothing but bash -- cover the same ground a
# second way.
#
# Set MKDOCS_BIN to point at one in a virtualenv.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

printf '\n%s== the configuration is present and sane%s\n' "$DIM" "$RESET"
[ -f "$ROOT/mkdocs.yml" ] \
    && ok_ "mkdocs.yml exists" || { bad_ "no mkdocs.yml"; exit 1; }

grep -q '^strict: true' "$ROOT/mkdocs.yml" \
    && ok_ "strict mode is on in the config, not only on the command line" \
    || bad_ "strict: true is not set" "a broken link would produce a site instead of an error"

grep -q 'name: material' "$ROOT/mkdocs.yml" \
    && ok_ "the Material theme is configured" || bad_ "no theme configured"

# Every page the navigation names must exist.  test_docs.sh checks this too;
# here it is a precondition, so a missing page is reported as itself rather
# than as a mkdocs traceback.
missing=""
while IFS= read -r page; do
    [ -n "$page" ] || continue
    [ -f "$ROOT/docs/$page" ] || missing="$missing $page"
done < <(awk '/^nav:/,0' "$ROOT/mkdocs.yml" | grep -oE '[A-Za-z0-9_./-]+\.md')
[ -z "$missing" ] \
    && ok_ "every page in the navigation exists" \
    || bad_ "navigation names missing page(s):$missing"

printf '\n%s== it builds%s\n' "$DIM" "$RESET"
MK=${MKDOCS_BIN:-}
if [ -z "$MK" ]; then
    MK=$(command -v mkdocs 2>/dev/null || true)
fi
if [ -z "$MK" ] || [ ! -x "$MK" ]; then
    skip_ "mkdocs not installed (set MKDOCS_BIN, or pip install mkdocs mkdocs-material)"
else
    out=$("$MK" build --strict --site-dir "$TMP/site" -f "$ROOT/mkdocs.yml" 2>&1)
    rc=$?
    if [ "$rc" = 0 ]; then
        ok_ "mkdocs build --strict succeeded"
    else
        bad_ "mkdocs build --strict failed" "$(printf '%s' "$out" | grep -iE 'warning|error' | head -8)"
    fi

    # A warning that strict did not catch is still worth knowing about.
    #
    # Counted from mkdocs's own "WARNING -" line prefix, not from the word
    # anywhere in the output: the Material theme prints a promotional banner
    # containing "Warning from the Material for MkDocs team", which a
    # case-insensitive search reports as a build warning it is not.
    nwarn=$(printf '%s' "$out" | grep -c '^WARNING -' || true)
    [ "${nwarn:-0}" = 0 ] \
        && ok_ "no warnings" \
        || bad_ "$nwarn warning(s)" "$(printf '%s' "$out" | grep -i WARNING | head -5)"

    [ -f "$TMP/site/index.html" ] \
        && ok_ "the site has an index page" || bad_ "no index.html was produced"

    n=$(find "$TMP/site" -name '*.html' | wc -l)
    [ "$n" -ge 30 ] \
        && ok_ "$n pages rendered" \
        || bad_ "only $n pages rendered" "the navigation names more than that"

    # The search index is what makes a reference site usable.
    [ -f "$TMP/site/search/search_index.json" ] \
        && ok_ "the search index was built" || bad_ "no search index"
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
