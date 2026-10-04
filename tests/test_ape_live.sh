#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# APE, actually run.
#
# tests/test_ape.sh checks **deck construction** -- it says so in its own
# header, and it runs without APE installed. That is a useful thing to test and
# it is not the same thing as "APE works", and for a while the difference went
# unnoticed: 31 passing checks were read as seven working elements, and five of
# those elements had never been generated.
#
# This suite runs the engine. It records what passes and what fails as a
# measurement, so the roadmap's claim and the evidence for it are the same
# thing.
#
# It is gated behind PF_SLOW_TESTS=1 and skips cleanly without APE, but the
# skip message carries the last measured result so a fast run still tells you
# where things stood.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
PSM=$ROOT/pseudoforge

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# The measurement of record. Changing these means re-running and re-recording,
# which is the point: a status is a measurement, not an intention.
# With PBE. These five fail on APE's missing GGA path, not on anything about
# the elements -- all seven generate with -x pz, which LDA_PASS records.
KNOWN_PASS="Br Au"
KNOWN_FAIL="Ti Fe Cu Zn Ag"
LDA_PASS="Ti Fe Cu Zn Ag Br Au"

printf '\n%s== the deck suite does not claim to run the engine%s\n' "$DIM" "$RESET"
grep -qi 'check the deck, not the engine' "$HERE/test_ape.sh" \
    && ok_ "test_ape.sh says it checks decks, not generation" \
    || bad_ "test_ape.sh no longer states its scope" \
            "if it now runs APE, this suite is redundant; if it does not, say so"

printf '\n%s== the roadmap records what was measured%s\n' "$DIM" "$RESET"
RM=$ROOT/docs/contributing/roadmap.md
for el in $KNOWN_FAIL; do
    grep -q "$el" "$RM" || { bad_ "the roadmap does not name $el as failing"; continue; }
done
[ "$fail" = 0 ] && ok_ "every failing element is named in the roadmap"
grep -qiE 'attempts: 0|does not fire' "$RM" \
    && ok_ "and it records that the auto-fix does not fire for them" \
    || bad_ "the roadmap does not say why the bromine fallback does not help here"

printf '\n%s== the cause is recorded, not just the symptom%s\n' "$DIM" "$RESET"
# The finding that closed this item: it is the functional, not the element.
grep -qi 'no GGA path' "$RM" \
    && ok_ "the roadmap names the GGA path as the cause" \
    || bad_ "the roadmap still treats these as five broken elements"
grep -qiE '02-scalar_rel|chromium test|own .*test' "$RM" \
    && ok_ "and cites APE's own deck, so the claim is reproducible" \
    || bad_ "the upstream attribution has no reproduction attached"
grep -q 'no working GGA path' "$PF_LIB/executor.sh" \
    && ok_ "the engine's four-word error is translated for the user" \
    || bad_ "a failure still reports only 'State: 3d is unbound'"

printf '\n%s== the fallback fires on the failure it was written for%s\n' "$DIM" "$RESET"
# Bromine's rescue keys on multiroot_solve_system. The five open elements fail
# with an unbound state, which is a different thing -- and a fallback that
# quietly widened to catch both would change answers nobody asked it to.
awk '/Auto-fix: drop a deep filled d shell/,/^    fi$/' "$PF_LIB/executor.sh" \
    | grep -q 'multiroot_solve_system' \
    && ok_ "the d-shell fallback keys on multiroot_solve_system" \
    || bad_ "the fallback's trigger has changed" "it would now fire on failures it was not measured against"
awk '/Auto-fix: drop a deep filled d shell/,/^    fi$/' "$PF_LIB/executor.sh" \
    | grep -qi 'unbound' \
    && bad_ "the fallback now also catches unbound states" \
            "that is a physics change: it alters which shell is pseudised. Measure it." \
    || ok_ "it does not silently catch the unbound-state failure as well"

printf '\n%s== run it%s\n' "$DIM" "$RESET"
if [ "${PF_SLOW_TESTS:-0}" != 1 ]; then
    skip_ "gated behind PF_SLOW_TESTS=1 (measured 2026-09-27: LDA 7 of 7; PBE passes $KNOWN_PASS, fails $KNOWN_FAIL on APE's missing GGA path)"
else
    [ -f "${PF_RC:-$HOME/.pseudoforgerc}" ] && . "${PF_RC:-$HOME/.pseudoforgerc}"
    if ! "$PSM" engines path ape >/dev/null 2>&1; then
        skip_ "APE not built (pseudoforge engines build ape)"
    else
        export OMP_NUM_THREADS=1
        els=$(printf '%s %s' "$KNOWN_PASS" "$KNOWN_FAIL" | tr ' ' ',' | sed 's/^,//; s/,$//')
        ( cd "$ROOT" && ./pseudoforge generate -e "$els" -t nc -p pseudoforge-auto \
              -x pbe --engine ape -o "$TMP/ape" >/dev/null 2>&1 )

        got_pass="" got_fail=""
        while IFS=$'\t' read -r el _f _p _x _r _v _u st _rest; do
            case $el in ''|\#*) continue ;; esac
            case $st in
                ok|ok-warn) got_pass="$got_pass $el" ;;
                *)          got_fail="$got_fail $el" ;;
            esac
        done < "$TMP/ape/state.tsv"

        for el in $KNOWN_PASS; do
            case " $got_pass " in
                *" $el "*) ok_ "$el still generates" ;;
                *)         bad_ "$el used to generate and now does not" "a regression" ;;
            esac
        done

        # A failure that starts passing is good news, and must be recorded
        # rather than left as a stale "open" item -- that is how this went
        # wrong the first time.
        for el in $KNOWN_FAIL; do
            case " $got_pass " in
                *" $el "*) bad_ "$el now generates -- update KNOWN_FAIL and the roadmap" \
                                "an item that quietly stopped being open is how the last one rotted" ;;
                *)         ok_ "$el still fails, as recorded" ;;
            esac
        done

        # LDA is the working route, and a route claimed to work is run.
        ( cd "$ROOT" && ./pseudoforge generate -e "$els" -t nc -p pseudoforge-auto \
              -x pz --engine ape -j 4 -o "$TMP/apelda" >/dev/null 2>&1 )
        lda_ok=""
        while IFS=$'\t' read -r el _f _p _x _r _v _u st _rest; do
            case $el in ''|\#*) continue ;; esac
            case $st in ok|ok-warn) lda_ok="$lda_ok $el" ;; esac
        done < "$TMP/apelda/state.tsv"
        for el in $LDA_PASS; do
            case " $lda_ok " in
                *" $el "*) ok_ "  $el generates with LDA" ;;
                *)         bad_ "  $el no longer generates with LDA" \
                                "LDA is the documented route for these; it was 7 of 7" ;;
            esac
        done

        n_ok=$(printf '%s' "$got_pass" | wc -w)
        n_no=$(printf '%s' "$got_fail" | wc -w)
        printf '        measured: %s pass, %s fail\n' "$n_ok" "$n_no"

        # And the reason, so the record is diagnosable rather than a bare count.
        for el in $KNOWN_FAIL; do
            msg=$(awk -F'\t' -v e="$el" '$1 == e { print $11 }' "$TMP/ape/state.tsv")
            case $msg in
                *unbound*) ok_ "  $el fails on an unbound state, as recorded" ;;
                '')        bad_ "  $el has no recorded reason" ;;
                *)         bad_ "  $el now fails differently: $msg" \
                                "the recorded cause is out of date" ;;
            esac
        done
    fi
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
