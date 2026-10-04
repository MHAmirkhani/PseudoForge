#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# The documentation, as it will be served.
#
# tests/test_mkdocs.sh checks that the site *builds*. This checks that what was
# built is deployable: the pages Nginx is configured to serve exist at the
# paths it will look for them, the search index is there, every internal link
# in the **built HTML** resolves, and the site works under the `/docs/` prefix
# rather than at a domain root.
#
# The last one is the subtle one. MkDocs with `use_directory_urls` writes
# `reference/cli/index.html`, and Nginx resolves `/docs/reference/cli/` to it
# via `try_files`. A link written as `/reference/cli/` instead of a relative
# one would work in a local `mkdocs serve` and 404 on the deployment -- which
# is the worst kind of bug, because it passes every check done before upload.
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
SITE=$TMP/site

MK=${MKDOCS_BIN:-$(command -v mkdocs 2>/dev/null || true)}
if [ -z "$MK" ] || [ ! -x "$MK" ]; then
    printf '\n  %sSKIP%s  mkdocs not installed (set MKDOCS_BIN)\n' "$YELLOW" "$RESET"
    printf '\n%s0 passed%s, %s0 failed%s, %s1 skipped%s\n' "$GREEN" "$RESET" "$DIM" "$RESET" "$DIM" "$RESET"
    exit 0
fi

printf '\n%s== it builds for deployment%s\n' "$DIM" "$RESET"
out=$("$MK" build --strict --site-dir "$SITE" -f "$ROOT/mkdocs.yml" 2>&1)
if [ $? = 0 ]; then
    ok_ "mkdocs build --strict succeeded"
else
    bad_ "the build failed" "$(printf '%s' "$out" | grep -iE 'error|warning' | head -5)"
    printf '\n%s%d passed%s, %s%d failed%s\n' "$GREEN" "$pass" "$RESET" "$RED" "$fail" "$RESET"
    exit 1
fi

printf '\n%s== the files Nginx will look for%s\n' "$DIM" "$RESET"
[ -f "$SITE/index.html" ] \
    && ok_ "site/index.html exists -- /docs/ resolves" \
    || bad_ "no index.html; /docs/ would 403"

[ -f "$SITE/search/search_index.json" ] \
    && ok_ "the search index was built" \
    || bad_ "no search index; site search would silently return nothing"

n=$(find "$SITE" -name 'index.html' | wc -l)
[ "$n" -ge 40 ] \
    && ok_ "$n directory-style pages" \
    || bad_ "only $n pages; use_directory_urls may be off"

# The pages the frontend and the installer link to by name. A rename here is
# a dead link on the live site, and nothing else would catch it.
linked="getting-started/installation getting-started/quickstart getting-started/concepts
        architecture/http reference/formats reference/errata reference/profiles
        how-to/validate how-to/deploy tutorials/01-carbon"
missing=""
for p in $linked; do
    [ -f "$SITE/$p/index.html" ] || missing="$missing $p"
done
[ -z "$missing" ] \
    && ok_ "every page the site links to by name is there" \
    || bad_ "the frontend links to pages that will 404:$missing"

printf '\n%s== every internal link in the built HTML resolves%s\n' "$DIM" "$RESET"
# The built HTML, not the Markdown: this is what a browser will follow.
# The path the site is served under, read from the configuration rather than
# assumed: it is what turns a root-relative link into a file on disk.
PREFIX=$(grep -oE '^site_url:.*' "$ROOT/mkdocs.yml"          | sed -E 's|^site_url:[[:space:]]*https?://[^/]*||; s|/$||')
[ -n "$PREFIX" ] && ok_ "the site is served under $PREFIX/"                  || skip_ "no site_url prefix; links resolved at the root"

broken=0; checked=0; report=""
while IFS= read -r page; do
    dir=$(dirname "$page")
    while IFS= read -r href; do
        [ -n "$href" ] || continue
        case $href in
            http://*|https://*|mailto:*|'#'*|data:*|javascript:*) continue ;;
        esac
        target=${href%%#*}; target=${target%%\?*}
        [ -n "$target" ] || continue
        case $target in
            # The site is served under /docs/, so a root-relative link that
            # already carries that prefix resolves at the site root -- the
            # prefix is where the site begins, not a directory inside it.
            "$PREFIX"/*) resolved=$SITE${target#"$PREFIX"} ;;
            /*)          resolved=$SITE${target} ;;
            *)           resolved=$dir/$target ;;
        esac
        checked=$((checked + 1))
        if [ ! -e "$resolved" ] && [ ! -e "${resolved%/}/index.html" ]; then
            broken=$((broken + 1))
            [ "$broken" -le 8 ] && report="$report
    ${page#"$SITE/"} -> $href"
        fi
    done < <(grep -oE 'href="[^"]+"' "$page" | sed 's/^href="//; s/"$//')
done < <(find "$SITE" -name '*.html')

[ "$broken" = 0 ] \
    && ok_ "$checked links checked, none broken" \
    || bad_ "$broken of $checked links are broken:$report"

printf '\n%s== it is built to live under /docs/%s\n' "$DIM" "$RESET"
grep -q 'site_url:.*\/docs\/' "$ROOT/mkdocs.yml" \
    && ok_ "site_url ends in /docs/" \
    || bad_ "site_url does not name the /docs/ prefix" \
            "canonical URLs and the sitemap would point at the wrong place"

grep -qE '^use_directory_urls:\s*true' "$ROOT/mkdocs.yml" \
    && ok_ "use_directory_urls is on, which is what the nginx try_files expects" \
    || bad_ "use_directory_urls is off but nginx resolves \$uri/index.html"

# A page linking to an absolute path outside /docs/ is fine (back to the app);
# one linking to an absolute path *inside* the docs is not, because the built
# site is served from a prefix.
badabs=$(grep -rhoE 'href="/(reference|tutorials|how-to|architecture|getting-started|explanation|contributing)/[^"]*"' \
         "$SITE" 2>/dev/null | sort -u | head -5)
[ -z "$badabs" ] \
    && ok_ "no page links to a docs path as if the site were at the domain root" \
    || bad_ "absolute links that ignore the /docs/ prefix:" "$badabs"

printf '\n%s== back to the application%s\n' "$DIM" "$RESET"
# Someone who clicks "Docs" must be able to get back.
withlink=$(grep -rl 'href="/"' "$SITE" --include='*.html' 2>/dev/null | wc -l)
[ "$withlink" -ge "$n" ] \
    && ok_ "every page links back to the site root ($withlink pages)" \
    || bad_ "only $withlink of $n pages link back to /" \
            "a reader who clicks Docs has no way home"

printf '\n%s== size, for the deployment budget%s\n' "$DIM" "$RESET"
mb=$(du -sm "$SITE" | cut -f1)
[ "$mb" -le 50 ] \
    && ok_ "the built site is ${mb}M, inside its 50M share" \
    || bad_ "the built site is ${mb}M, over the 50M planned for /var/lib/pseudoforge/docs"

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
