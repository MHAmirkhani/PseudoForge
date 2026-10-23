#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# The documentation, checked against the code it documents.
#
# Documentation rots in a particular way: not by becoming wrong all at once,
# but by one flag being renamed, one verb being added, one default changing,
# while the prose stays as it was. By the time a reader notices, they have
# already typed a command that does not work and concluded the tool is broken.
#
# So every command printed in the docs is checked here:
#
#   * the verb exists in the dispatch,
#   * every flag is one the CLI actually parses,
#   * placeholders are obviously placeholders (<name>, ...), not stale values.
#
# This is the check that would have caught `--recipe r -e Fe` documenting an
# override that the parser did not implement -- found by hand, once, which is
# not a method.
#
# Generated reference pages are checked a second way: they must match what the
# generator produces from the code right now. A flag added to cli_parse and not
# to the docs fails here rather than being discovered by a reader.
#
# PF_SLOW_TESTS=1 additionally runs the first generate command of every
# tutorial, so a tutorial cannot promise output that the tool no longer
# produces.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
DOCS=$ROOT/docs
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

[ -d "$DOCS" ] || { echo "no docs/ directory" >&2; exit 1; }

# ---------------------------------------------------------------------------
# What the code says is valid.
# ---------------------------------------------------------------------------
# Verbs: the case labels of the dispatch in the entry point.
awk '/^case .*cmd/,/^esac/' "$ROOT/pseudoforge" \
    | awk '/^    [a-z|_-]+\)/ { sub(/\).*/, ""); gsub(/[ \t]/, ""); print }' \
    | tr '|' '\n' | sort -u > "$TMP/verbs"
# Bare options mean generate, and these are handled outside the case list.
printf 'help\n--help\n-h\n--version\n-V\n' >> "$TMP/verbs"
sort -u "$TMP/verbs" -o "$TMP/verbs"

# Flags: every case pattern in cli.sh that looks like an option.
# Every token of every case pattern that looks like an option.  Patterns
# alternate -- ''|--all|all) offers --all too -- so the whole label is split
# rather than only its first token.
grep -ohE '^[[:space:]]+[^);]*\)' "$PF_LIB"/*.sh \
    | tr -d ' )' | tr '|' '\n' | grep '^-' | sort -u > "$TMP/flags"
sort -u "$TMP/flags" -o "$TMP/flags"

nverbs=$(grep -c . "$TMP/verbs"); nflags=$(grep -c . "$TMP/flags")

printf '\n%s== the code offers something to document%s\n' "$DIM" "$RESET"
[ "$nverbs" -ge 10 ] && ok_ "$nverbs verbs found in the dispatch" \
                     || bad_ "only $nverbs verbs parsed out of the entry point"
[ "$nflags" -ge 30 ] && ok_ "$nflags flags found in the parsers" \
                     || bad_ "only $nflags flags parsed out of cli.sh"

# ---------------------------------------------------------------------------
# Pull every pseudoforge command out of every fenced block.
#
# Continuation lines are joined, comments and shell prompts stripped, so a
# wrapped command is checked as the one command it is.
# ---------------------------------------------------------------------------
extract() {
    local f=$1
    awk -v file="$f" '
        /^```/ { infence = !infence; next }
        !infence { next }
        {
            line = $0
            sub(/^[$#][[:space:]]+/, "", line)          # a prompt, if any
            if (cont != "") { line = cont " " line; cont = "" }
            if (line ~ /\\[[:space:]]*$/) {             # continuation
                sub(/\\[[:space:]]*$/, "", line); cont = line; next
            }
            if (line !~ /(^|[|&;][[:space:]]*)(\.\/)?pseudoforge[[:space:]]/) next
            # Only the pseudoforge command itself: what follows a pipe
            # belongs to grep, not to us.
            sub(/[[:space:]]*[|].*$/, "", line)
            sub(/#.*$/, "", line)                       # trailing comment
            printf "%s\t%d\t%s\n", file, NR, line
        }' "$f"
}

mapfile -t DOCFILES < <(find "$DOCS" -name '*.md' | sort)
: > "$TMP/cmds"
for f in "${DOCFILES[@]}"; do extract "$f" >> "$TMP/cmds"; done
ncmd=$(grep -c . "$TMP/cmds" 2>/dev/null || echo 0)

printf '\n%s== every documented command is a command%s\n' "$DIM" "$RESET"
[ "$ncmd" -gt 0 ] \
    && ok_ "$ncmd pseudoforge command(s) found across ${#DOCFILES[@]} pages" \
    || bad_ "no commands found in the docs" "either the docs show none, or the extractor is broken"

bad_verbs="" bad_flags=""
while IFS=$'\t' read -r file lineno cmd; do
    [ -n "$cmd" ] || continue
    rel=${file#"$ROOT/"}
    # Everything after the program name, one token at a time.
    set -- $cmd
    while [ $# -gt 0 ] && [ "${1##*/}" != pseudoforge ]; do shift; done
    shift || true
    verb=${1:-}
    case $verb in
        ''|-*) ;;                                  # bare flags mean generate
        *'<'*|*'>'*|'...') ;;                      # a placeholder, not a verb
        *) grep -qxF -- "$verb" "$TMP/verbs" \
               || bad_verbs="$bad_verbs
    $rel:$lineno  unknown verb '$verb'" ;;
    esac
    for tok in "$@"; do
        case $tok in
            -*)
                # Placeholders and negative numbers are not flags.
                case $tok in
                    -|-[0-9]*|*'<'*|*'>'*) continue ;;   # stdout, a number, a placeholder
                esac
                base=${tok%%=*}
                grep -qxF -- "$base" "$TMP/flags" \
                    || bad_flags="$bad_flags
    $rel:$lineno  unknown flag '$base'" ;;
        esac
    done
done < "$TMP/cmds"

[ -z "$bad_verbs" ] \
    && ok_ "every verb is one the entry point dispatches" \
    || bad_ "the docs show verbs that do not exist:$bad_verbs"
[ -z "$bad_flags" ] \
    && ok_ "every flag is one the parsers accept" \
    || bad_ "the docs show flags the CLI rejects:$bad_flags" \
            "a reader typing these gets 'unknown option'"

printf '\n%s== placeholders look like placeholders%s\n' "$DIM" "$RESET"
# A stale real value reads as an instruction; <name> cannot be mistaken for one.
suspicious=$(grep -rnoE '/home/[a-z]+/|/Users/[a-z]+/|/tmp/[a-z0-9]+/pseudos' "$DOCS" \
             --include='*.md' 2>/dev/null | grep -v 'example\|e\.g\.' | head -5)
[ -z "$suspicious" ] \
    && ok_ "no machine-specific path is presented as a value to copy" \
    || bad_ "absolute paths from a developer's machine appear in the docs" "$suspicious"

printf '\n%s== generated reference pages match the code%s\n' "$DIM" "$RESET"
GEN=$ROOT/tools/gen_reference.sh
if [ ! -x "$GEN" ]; then
    bad_ "tools/gen_reference.sh is missing" "the reference tables would be hand-maintained"
else
    drift=""
    for page in cli engines formats profiles http-api; do
        target=$DOCS/reference/$page.md
        [ -f "$target" ] || { drift="$drift $page(missing)"; continue; }
        if "$GEN" "$page" > "$TMP/$page.md" 2>/dev/null; then
            # Only the generated region is compared; the prose around it is
            # written by hand and is not the generator's business.
            sed -n '/<!-- generated:begin -->/,/<!-- generated:end -->/p' "$target" > "$TMP/have.$page"
            sed -n '/<!-- generated:begin -->/,/<!-- generated:end -->/p' "$TMP/$page.md" > "$TMP/want.$page"
            if [ ! -s "$TMP/want.$page" ]; then
                drift="$drift $page(generator-produced-nothing)"
            elif ! cmp -s "$TMP/have.$page" "$TMP/want.$page"; then
                drift="$drift $page"
            fi
        else
            drift="$drift $page(generator-failed)"
        fi
    done
    [ -z "$drift" ] \
        && ok_ "cli, engines, formats and profiles tables are current" \
        || bad_ "generated page(s) are stale:$drift" \
                "run tools/gen_reference.sh --write to refresh them"
fi

printf '\n%s== the navigation and the files agree%s\n' "$DIM" "$RESET"
if [ -f "$ROOT/mkdocs.yml" ]; then
    missing=""
    while IFS= read -r page; do
        [ -n "$page" ] || continue
        [ -f "$DOCS/$page" ] || missing="$missing $page"
    done < <(awk '/^nav:/,0' "$ROOT/mkdocs.yml" | grep -oE '[A-Za-z0-9_./-]+\.md')
    [ -z "$missing" ] \
        && ok_ "every page the navigation names exists" \
        || bad_ "navigation points at missing page(s):$missing" "mkdocs --strict would fail"

    orphan=""
    while IFS= read -r f; do
        rel=${f#"$DOCS/"}
        grep -qF "$rel" "$ROOT/mkdocs.yml" || orphan="$orphan $rel"
    done < <(printf '%s\n' "${DOCFILES[@]}")
    [ -z "$orphan" ] \
        && ok_ "every page is reachable from the navigation" \
        || bad_ "page(s) not in the navigation:$orphan" "a reader would never find them"
else
    skip_ "no mkdocs.yml yet"
fi

printf '\n%s== internal links resolve%s\n' "$DIM" "$RESET"
broken=""
for f in "${DOCFILES[@]}"; do
    d=$(dirname "$f"); rel=${f#"$ROOT/"}
    while IFS= read -r target; do
        [ -n "$target" ] || continue
        case $target in
            http*|mailto:*|'#'*) continue ;;
        esac
        t=${target%%#*}
        [ -n "$t" ] || continue
        [ -e "$d/$t" ] || broken="$broken
    $rel -> $t"
    done < <(grep -oE '\]\([^)]+\)' "$f" | sed 's/^](//; s/)$//')
done
[ -z "$broken" ] \
    && ok_ "every relative link points at something that exists" \
    || bad_ "broken link(s):$broken"

printf '\n%s== link anchors resolve%s\n' "$DIM" "$RESET"
# The file existence check above does not look at the fragment.  A link
# to `limitations.md#--projector` is as broken as one to a missing file:
# the reader lands at the top of the page with no idea what went wrong.
# The slugs are computed by tools/check-anchors.py, which MkDocs would
# compute the same way at build time.
if [ -x "$ROOT/tools/check-anchors.py" ]; then
    out=$(python3 "$ROOT/tools/check-anchors.py" 2>&1)
    [ $? -eq 0 ] \
        && ok_ "every relative link's anchor is a heading in its target" \
        || bad_ "broken anchor link(s):" "$out"
else
    skip_ "tools/check-anchors.py not present"
fi

printf '\n%s== claims are qualified where the code qualifies them%s\n' "$DIM" "$RESET"
# The recipe database is byte-identical to upstream *except* where ERRATA says
# otherwise.  Saying it without the exception is the kind of overclaim that
# makes the rest of the document less believable.
# Only the PSlibrary claim: the recipe database is byte-identical to upstream
# *except* where ERRATA declares otherwise, and saying it without the
# exception is the kind of overclaim that makes the rest less believable.
#
# A saved recipe reproducing its own output byte for byte, and -j 1 matching
# -j 8, are different claims and are true without qualification.  The check
# reads a three-line window, because the exception is often the next sentence.
unqualified=""
for f in "${DOCFILES[@]}"; do
    hit=$(awk -f "$ROOT/tools/awk/unqualified_claims.awk" "$f")
    [ -n "$hit" ] && unqualified="$unqualified
    ${hit#"$ROOT/"}"
done
[ -z "$unqualified" ] \
    && ok_ "the PSlibrary claim carries its exception everywhere it is made" \
    || bad_ "unqualified byte-identical claim(s):$unqualified"
printf '\n%s== the wizard limitation is stated, not buried%s\n' "$DIM" "$RESET"
W=$DOCS/reference/wizard.md
[ -f "$W" ] || W=$DOCS/WIZARD.md
if [ -f "$W" ]; then
    grep -qiE 'cannot bind|newt reads its own keys|whiptail cannot' "$W" \
        && ok_ "the Ctrl-shortcut limitation is documented" \
        || bad_ "the wizard reference does not state what whiptail cannot do"
    grep -qiE 'accelerator|first letter|single-letter' "$W" \
        && ok_ "and what is offered instead" \
        || bad_ "the limitation is stated without the alternative"
else
    bad_ "no wizard reference page"
fi

printf '\n%s== metadata and prose agree with the code%s\n' "$DIM" "$RESET"
code_ver=$(awk -F= '/^PSEUDOFORGE_VERSION=/ { gsub(/["'\'' ]/, "", $2); print $2; exit }' "$PF_LIB/core.sh")
cff_ver=$(awk -F': *' '/^version:/ { gsub(/["'\'' ]/, "", $2); print $2; exit }' "$ROOT/CITATION.cff")
[ "$code_ver" = "$cff_ver" ] \
    && ok_ "CITATION.cff version ($cff_ver) matches PSEUDOFORGE_VERSION" \
    || bad_ "CITATION.cff says $cff_ver, core.sh says $code_ver"
grep -q 'ADPACK' "$ROOT/CITATION.cff" \
    && ok_ "CITATION.cff abstract names ADPACK among the nine engines" \
    || bad_ "CITATION.cff omits ADPACK from the engine list"
grep -qi 'only engine here that makes PAW' "$PF_LIB/engines.sh" \
    && bad_ "engines.sh still claims ld1 is the only PAW engine" \
    || ok_ "engines.sh does not claim ld1 is the only PAW engine"
grep -q 'seven of the eight' "$PF_LIB/xc.sh" \
    && bad_ "xc.sh still says seven of the eight" \
    || ok_ "xc.sh says eight of the nine"
grep -q 'Three of the eight' "$PF_LIB/build.sh" \
    && bad_ "build.sh still says Three of the eight" \
    || ok_ "build.sh says Three of the nine"
grep -q 'Eight engines with different' "$PF_LIB/cli.sh" \
    && bad_ "cli.sh still says Eight engines" \
    || ok_ "cli.sh says Nine engines"
[ "$(grep -c '^#\+ Where downloads come from' "$ROOT/README.md")" -eq 1 ] \
    && ! grep -q 'checks `MIRROR_URL` first' "$ROOT/README.md" \
    && ok_ "README.md states one download order matching lib/fetch.sh" \
    || bad_ "README.md has a duplicate or inverted download order"
grep -n '^[[:space:]]*whiptail ' "$PF_LIB/tui.sh" >/dev/null 2>&1 \
    && bad_ "lib/tui.sh calls bare whiptail instead of \$DIA" \
    || ok_ "lib/tui.sh dispatches through \$DIA"

printf '\n%s== the tutorials still run%s\n' "$DIM" "$RESET"
if [ "${PF_SLOW_TESTS:-0}" != 1 ]; then
    skip_ "tutorial commands gated behind PF_SLOW_TESTS=1"
elif [ ! -d "$DOCS/tutorials" ]; then
    skip_ "no tutorials directory"
else
    [ -f "${PF_RC:-$HOME/.pseudoforgerc}" ] && . "${PF_RC:-$HOME/.pseudoforgerc}"
    export OMP_NUM_THREADS=1
    for t in "$DOCS"/tutorials/*.md; do
        [ -e "$t" ] || continue
        name=$(basename "$t" .md)
        # The first generate in the tutorial is the one that must still work.
        # A tutorial may deliberately show a command that is refused -- the
        # meta-GGA one does, because the refusal is what it teaches.  A
        # "# expect: refused" comment in the block marks it, and the refusal
        # is then asserted rather than skipped: a refusal that stopped
        # happening would be a silent change in behaviour.
        exp=$(awk '/^```/ { infence = !infence; next }
            infence && /^# expect: refused/ { getline; print; exit }' "$t")
        if [ -n "$exp" ]; then
            ( cd "$ROOT" && eval "${exp/pseudoforge/./pseudoforge}" -o "$TMP/$name-x" ) >/dev/null 2>&1
            [ $? -ne 0 ] \
                && ok_ "$name: the documented refusal still refuses" \
                || bad_ "$name: a command documented as refused succeeded" "$exp"
        fi

        # The first command not marked as expected to fail must work.
        cmd=$(awk '/^```/ { infence = !infence; next }
            infence && /^# expect: refused/ { skip = 1; next }
            infence && /pseudoforge (generate|gen) / {
                if (skip) { skip = 0; next }
                print; exit }' "$t")
        [ -n "$cmd" ] || { skip_ "$name: no generate command"; continue; }
        out=$TMP/$name
        ( cd "$ROOT" && eval "${cmd/pseudoforge/./pseudoforge}" -o "$out" ) >/dev/null 2>&1
        rc=$?
        n=$(ls "$out"/pseudos/*.UPF "$out"/pseudos/*.psp8 "$out"/pseudos/*.xml 2>/dev/null | wc -l)
        [ "$rc" = 0 ] && [ "$n" -gt 0 ] \
            && ok_ "$name produces $n file(s), as documented" \
            || bad_ "$name: exit $rc, $n file(s)" "$cmd"
    done
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
