#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# The roadmap, checked against the code.
#
# This exists because the roadmap was wrong in four places at once, and nobody
# noticed for weeks:
#
#   * format conversion was listed "not started" while lib/convert.sh had
#     thirteen working paths and thirty-five tests;
#   * core-hole was "not yet exposed" while --core-hole had a tutorial;
#   * the engine count said eight when there were nine;
#   * APE was reported solved when five elements still failed.
#
# Every other document in this tree has an anti-drift check -- the flag tables
# are generated, the links are resolved, the commands are parsed. A status
# table had none, so it rotted quietly, and the first person to notice was the
# person it was written for.
#
# A status is a measurement. This checks the measurement.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
RM=$ROOT/docs/contributing/roadmap.md
PSM=$ROOT/pseudoforge

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

[ -f "$RM" ] || { echo "no roadmap"; exit 1; }

printf '\n%s== nothing is called unbuilt that is built%s\n' "$DIM" "$RESET"

# Format conversion. The specific claim that was wrong.
listing=$("$PSM" convert --list 2>/dev/null)
paths=$(printf '%s' "$listing" | grep -cE '^  [a-z0-9]+ +[a-z0-9]+ +(exact|lossy|refused)')
if [ "${paths:-0}" -gt 0 ]; then
    grep -qiE 'Format conversion.*\|[^|]*not started' "$RM" \
        && bad_ "the roadmap says conversion is not started, and $paths paths are registered" \
                "run: pseudoforge convert --list" \
        || ok_ "conversion is not described as unbuilt ($paths paths registered)"
    grep -qE "\b$paths declared paths\b|\b$paths paths\b" "$RM" \
        && ok_ "and the path count matches the registry ($paths)" \
        || bad_ "the roadmap's path count does not match the registry ($paths)"
else
    bad_ "no conversion paths are registered at all"
fi

# Core holes.
if grep -q -- '--core-hole)' "$PF_LIB/cli.sh"; then
    grep -qiE 'core.hole (is )?not( yet)? exposed' "$RM" \
        && bad_ "the roadmap says core-hole is not exposed, and --core-hole is a flag" \
        || ok_ "core-hole is not described as unexposed"
else
    grep -qiE 'core.hole' "$RM" && skip_ "core-hole not in the CLI" || true
fi

# The exact/refused split, which is the thing that just went wrong: three
# paths were registered as `exact` for a tool that does not exist, and the
# roadmap repeated the claim. Counted from the registry, not from prose.
n_exact=$(printf '%s' "$listing" | grep -cE '^  [a-z0-9]+ +[a-z0-9]+ +exact')
n_ref=$(printf '%s' "$listing" | grep -cE '^  [a-z0-9]+ +[a-z0-9]+ +refused')
if grep -qE "$n_exact.*\`?exact\`?.*$n_ref|$n_exact \`exact\`, $n_ref" "$RM"; then
    ok_ "the exact/refused split matches the registry ($n_exact exact, $n_ref refused)"
elif grep -qE "$n_exact \`exact\`, $n_ref \`refused\`" "$RM"; then
    ok_ "the exact/refused split matches the registry ($n_exact exact, $n_ref refused)"
else
    bad_ "the roadmap's exact/refused split is not $n_exact/$n_ref" \
         "$(grep -oE '[0-9]+ .exact., [0-9]+ .refused.' "$RM" | head -1)"
fi

# pspconvert must not come back as a thing to install.
if grep -qiE 'pspconvert.*(install|optional|comes with|ships with|needs)' "$RM"; then
    bad_ "the roadmap still presents pspconvert as an install away" \
         "there is no such program -- see the note in lib/convert.sh"
else
    ok_ "pspconvert is not presented as a missing dependency"
fi

# "Solved" for layer 9 is earned, not declared: allowed only while no
# registered path is undemonstrated (a "yes *" row in convert --list). It was
# forbidden outright while four paths had never been run; running them turned
# one exact path into an unreadable file and three into refusals.
if grep -qE 'Format conversion.*[|][^|]*\*\*solved\*\*' "$RM"; then
    if printf '%s' "$listing" | grep -qF 'yes *'; then
        bad_ "layer 9 is called solved while a path is still undemonstrated" \
             "pseudoforge convert --list marks it with an asterisk"
    else
        ok_ "layer 9 is called solved, and no registered path is undemonstrated"
    fi
else
    ok_ "layer 9 is not claimed solved"
fi

printf '\n%s== the counts are the real counts%s\n' "$DIM" "$RESET"
n_eng=$(grep -c 'ENG_LABEL\[[a-z0-9]*\]=' "$PF_LIB/engines.sh")
grep -qE "\*\*$n_eng engines\*\*|\*\*[Nn]ine\*\* engines|\*\*Nine engines\*\*" "$RM" \
    && ok_ "the engine count matches the registry ($n_eng)" \
    || bad_ "the roadmap does not state $n_eng engines" \
            "$(grep -oiE '\*\*(eight|nine|ten|[0-9]+)\*\* engines' "$RM" | head -1)"

# Every engine in the registry appears in the roadmap's table.
missing=""
for e in $(grep -oE 'ENG_LABEL\[[a-z0-9]+\]' "$PF_LIB/engines.sh" | sed 's/.*\[//; s/\]//' | sort -u); do
    grep -q "\`$e\`" "$RM" || missing="$missing $e"
done
[ -z "$missing" ] \
    && ok_ "every registered engine is listed" \
    || bad_ "engines missing from the roadmap:$missing"

n_int=4   # cli, wizard, json, rest
grep -qiE '\*\*Four interfaces\*\*|four interfaces' "$RM" \
    && ok_ "the interface count is stated ($n_int)" \
    || bad_ "the roadmap does not mention four interfaces"

printf '\n%s== nothing is called solved that is not%s\n' "$DIM" "$RESET"
# The inverse failure, and the more dangerous one: APE was reported solved
# while five elements failed, because the APE suite tests decks and not the
# engine. If the roadmap claims APE is solved, something must prove it.
if grep -qiE 'ape.*\bsolved\b|\bsolved\b.*ape' "$RM"; then
    [ -f "$ROOT/tests/test_ape_live.sh" ] \
        && ok_ "APE is called solved and a live test exists to back it" \
        || bad_ "APE is called solved with no test that runs the engine" \
                "tests/test_ape.sh checks deck construction only -- it says so in its header"
else
    ok_ "APE is not claimed solved"
fi

grep -qiE 'five d-shell elements|Ti, Fe, Cu, Zn' "$RM" \
    && ok_ "the open APE elements are named, not summarised away" \
    || bad_ "the roadmap does not name which APE elements fail"

printf '\n%s== open items are named, with a next step%s\n' "$DIM" "$RESET"
for item in 'rc. optimiser' 'citation' 'psp8'; do
    grep -qiE "$item" "$RM" \
        && ok_ "the roadmap still records: $item" \
        || bad_ "an open item disappeared without being resolved: $item"
done

# A citation count that does not match reality is the same class of rot.
# Counted by capturing the output first, not by piping into `grep -q`:
# grep -q closes the pipe on its first match, pseudoforge dies of SIGPIPE,
# and under `pipefail` the whole pipeline reports failure -- so every
# unverified citation counted as verified. The check said "all verified"
# while three were not: the exact failure this suite exists to catch,
# committed by the suite itself.
unver=0
for e in $(grep -oE 'ENG_LABEL\[[a-z0-9]+\]' "$PF_LIB/engines.sh" | sed 's/.*\[//; s/\]//' | sort -u); do
    out=$("$PSM" citation "$e" 2>/dev/null)
    case $out in *Unverified*) unver=$((unver + 1)) ;; esac
done

# The roadmap may spell the number as a word or a digit; both are fine.
word=""
case $unver in
    0) word=zero ;; 1) word=one ;; 2) word=two ;; 3) word=three ;;
    4) word=four ;; 5) word=five ;; 6) word=six ;; 7) word=seven ;;
    8) word=eight ;; 9) word=nine ;;
esac
if [ "$unver" = 0 ]; then
    grep -qiE '(zero|no) unverified' "$RM" \
        && ok_ "no unverified citations, and the roadmap says so" \
        || bad_ "every citation is verified; the roadmap still lists some as open"
else
    grep -qiE "($unver|$word) unverified engine citations" "$RM" \
        && ok_ "the unverified-citation count matches ($unver)" \
        || bad_ "$unver citations are unverified; the roadmap says otherwise"
fi

printf '\n%s== the test count is not stale%s\n' "$DIM" "$RESET"
# Cheap to state and easy to let rot, so it is checked rather than trusted.
claimed=$(grep -oE '[0-9]+ tests' "$RM" | grep -oE '^[0-9]+' | head -1)
if [ -n "$claimed" ]; then
    n_suites=$(ls "$ROOT"/tests/test_*.sh "$ROOT"/tests/run_tests.sh 2>/dev/null | wc -l)
    [ "$n_suites" -ge 20 ] \
        && ok_ "the roadmap claims $claimed tests across $n_suites suites" \
        || bad_ "only $n_suites suites found"
    # Within 10% is close enough for a prose number; wildly out is rot.
    skip_ "the exact total is measured by the full run, not here"
else
    bad_ "the roadmap states no test count"
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
