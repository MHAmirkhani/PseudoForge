#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Provenance tests.
#
# "Generated with ONCVPSP" is not a reproducible statement, and that is the
# whole reason this exists.  Two builds of the same engine version produce
# different pseudopotentials from the same input -- the case that actually
# bites is ONCVPSP linked against libxc versus against its stub, which report
# the identical version 4.0.1 and are not the same program.  Measured here:
#
#     oncvpsp.x          9c0080741f21   libxc=yes
#     oncvpsp.x.nolibxc  53da52f522a9   libxc=no
#
# So the recorded identity has to be version *and* build fingerprint, and both
# have to reach a file that travels with the pseudopotentials.
#
# These tests also guard the manifest itself, which spent its whole life until
# now as a file nothing read -- exactly the state in which documentation
# drifts away from reality unnoticed.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
for m in core sink config deps elements xc namelist profiles metadata formats gth sssp params engines recipe project report; do
    . "$PF_LIB/$m.sh" || { echo "cannot load $m.sh" >&2; exit 1; }
done
pf_config_defaults; pf_elements_load; pf_xc_load
pf_profiles_load; pf_metadata_load; pf_params_load; pf_engines_load
spec_init 2>/dev/null || true

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

printf '\n%s== the manifest is read, not just shipped%s\n' "$DIM" "$RESET"
pf_manifest_load
[ -n "${PF_MANIFEST_LOADED:-}" ] && ok_ "manifest loads" || bad_ "manifest did not load"

# Every engine PseudoForge builds needs a version recorded.  ld1 is the one
# exception and it is deliberate: it ships inside Quantum ESPRESSO.
missing=""
for eng in "${ENG_ORDER[@]}"; do
    [ "$eng" = ld1 ] && continue
    [ -n "${ENG_VERSION[$eng]:-}" ] || missing="$missing $eng"
done
[ -z "$missing" ] \
    && ok_ "every buildable engine has a version in the manifest" \
    || bad_ "no manifest version for:$missing" \
            "an engine built without a recorded version produces unreproducible output"

[ -n "${ENG_VERSION[libxc]:-}" ] \
    && ok_ "libxc's version is recorded (it changes ONCVPSP's answers)" \
    || bad_ "libxc has no manifest entry"

# ld1 must NOT be in the manifest -- a pinned number there would be a claim
# about someone else's Quantum ESPRESSO install.
[ -z "${ENG_VERSION[ld1]:-}" ] \
    && ok_ "ld1 is absent from the manifest, as its version belongs to QE" \
    || bad_ "ld1 has a pinned manifest version" "that would assert a version of QE we do not control"

printf '\n%s== build fingerprints%s\n' "$DIM" "$RESET"
seen=""; dupes=""
for eng in "${ENG_ORDER[@]}"; do
    bid=$(eng_build_id "$eng" 2>/dev/null) || { skip_ "$eng not installed"; continue; }
    case $bid in
        [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])
            ok_ "$eng -> $bid" ;;
        *) bad_ "$eng gave a malformed build id: '$bid'" ;;
    esac
    case " $seen " in *" $bid "*) dupes="$dupes $eng" ;; esac
    seen="$seen $bid"
done
[ -z "$dupes" ] \
    && ok_ "no two engines share a fingerprint" \
    || bad_ "these share a fingerprint with another engine:$dupes"

printf '\n%s== provenance line%s\n' "$DIM" "$RESET"
for eng in "${ENG_ORDER[@]}"; do
    eng_available "$eng" 2>/dev/null || continue
    line=$(eng_provenance "$eng")
    case $line in
        *"[build "*) ok_ "$eng provenance carries a build id" ;;
        *) bad_ "$eng provenance has no build id: $line" ;;
    esac
    break
done

# An engine that is not installed must not invent an identity for itself.
line=$(eng_provenance nosuchengine 2>/dev/null || true)
case $line in
    *"[build "*) bad_ "an unknown engine was given a build id" "provenance must omit what it does not know" ;;
    *) ok_ "an unknown engine gets no invented build id" ;;
esac

printf '\n%s== the provenance file%s\n' "$DIM" "$RESET"
# Built from a synthetic project so the test needs no generation run.
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export PROJECT_DIR=$TMP PROJECT_STATE=$TMP/state.tsv
mkdir -p "$TMP"
printf 'Si\tnc\tsg15\tpbe\tscalar\tlibrary\tSi.pbe-oncv.UPF\tok\t1\t2\t\n' > "$PROJECT_STATE"
SPEC[profile]=sg15; SPEC[family]=nc; SPEC[xc]=pbe; SPEC[rel]=scalar
SPEC[engine]=oncvpsp; SPEC[source]=local

out=$(report_provenance 2>/dev/null) || { echo "  report_provenance is not available"; }
if [ -n "${out:-}" ] && [ -f "$out" ]; then
    for key in tool.version engine.id engine.version engine.build engine.binary profile family functional relativity; do
        grep -q "^$key=" "$out" && ok_ "records $key" || bad_ "PROVENANCE.txt has no $key"
    done
    # the per-element table has to be there too, or the file describes a run
    # without saying what it produced
    grep -q 'Si.pbe-oncv.UPF' "$out" \
        && ok_ "the per-element table is included" \
        || bad_ "no element rows in PROVENANCE.txt"
    # nothing may be silently blank: unknown values are spelled out
    if grep -qE '^[a-z.]+=$' "$out"; then
        bad_ "some keys are empty" "an empty value reads as 'not applicable'; write 'unrecorded' instead"
    else
        ok_ "no key is left silently blank"
    fi
else
    skip_ "report_provenance unavailable in this context"
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
