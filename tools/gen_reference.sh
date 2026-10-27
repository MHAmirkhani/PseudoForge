#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# gen_reference.sh -- build the reference tables out of the code they describe.
#
#   tools/gen_reference.sh cli|engines|formats|profiles   page on stdout
#   tools/gen_reference.sh --write                        update the docs in place
#   tools/gen_reference.sh --check                        exit 1 if any is stale
#
# A hand-written flag table is wrong the first time someone adds a flag, and
# nobody finds out until a reader types it. So everything between the
# `generated:begin` and `generated:end` markers comes from the parsers and the
# registries themselves, and tests/test_docs.sh fails when what is committed is
# not what the code would produce today. The prose outside the markers is
# written by hand and is never touched.
#
# The awk programs live in tools/awk/ rather than inline. They are long enough
# that quoting them inside a shell string is how they acquire bugs.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT="$ROOT" PF_LIB="$ROOT/lib" PF_DATA="$ROOT/data"
DOCS="$ROOT/docs"
AWKDIR="$HERE/awk"

BEGIN='<!-- generated:begin -->'
END='<!-- generated:end -->'
NOTE='<!-- Do not edit between these markers: tools/gen_reference.sh writes them. -->'

load_lib() {
    local m
    for m in core sink config deps elements xc namelist profiles metadata formats \
             gth sssp convert doctor params engines; do
        # shellcheck source=/dev/null
        . "$PF_LIB/$m.sh" 2>/dev/null || true
    done
    pf_config_defaults 2>/dev/null || true
}

# ---------------------------------------------------------------------------
gen_cli() {
    printf '%s\n%s\n\n' "$BEGIN" "$NOTE"

    # Commands come from cli_usage -- the text a user already sees. A second
    # hand-written list would be a second thing to keep in step.
    printf '### Commands\n\n'
    printf '| Command | Arguments | What it does |\n|---|---|---|\n'
    awk -f "$AWKDIR/cli_commands.awk" "$PF_LIB/cli.sh"

    printf '\n### Options\n\n'
    printf '| Flag | Takes a value | Sets |\n|---|---|---|\n'
    awk -f "$AWKDIR/cli_options.awk" "$PF_LIB/cli.sh"

    printf '\n%s\n' "$END"
}

# ---------------------------------------------------------------------------
gen_engines() {
    load_lib
    pf_engines_load 2>/dev/null || true

    printf '%s\n%s\n\n' "$BEGIN" "$NOTE"
    printf '| Engine | Families | Writes UPF directly | Licence | Upstream |\n'
    printf '|---|---|---|---|---|\n'
    local e fam
    for e in $(printf '%s\n' "${!ENG_LABEL[@]}" | sort); do
        fam=$(printf '%s' "${ENG_FAMILIES[$e]:-}" | tr '[:lower:]' '[:upper:]')
        printf '| [%s](engines/%s.md) | %s | %s | %s | [source](%s) |\n' \
            "${ENG_LABEL[$e]}" "$e" "$fam" \
            "${ENG_NATIVE_UPF[$e]:-no}" \
            "${ENG_LICENSE[$e]:-unrecorded}" \
            "${ENG_UPSTREAM[$e]:-unrecorded}"
    done
    printf '\n%s\n' "$END"
}

# ---------------------------------------------------------------------------
gen_formats() {
    load_lib
    pf_convert_load 2>/dev/null || true

    printf '%s\n%s\n\n' "$BEGIN" "$NOTE"
    printf '### Formats\n\n'
    printf '| id | Format | Written natively by | Extension |\n|---|---|---|---|\n'
    awk -F'\t' '!/^#/ && NF >= 4 {
        printf "| `%s` | %s | %s | `.%s` |\n", $1, $2, ($3 == "" ? "--" : $3), $4
    }' "$PF_DATA/formats.tsv"

    printf '\n### Conversions\n\n'
    printf 'Every path PseudoForge knows about, and what it costs. A **refused**\n'
    printf 'path is a deliberate answer, not a gap -- the reason is given below.\n\n'
    printf 'The **demonstrated** column is a measurement, not a promise: it says\n'
    printf 'whether that exact path has been run against a real file on a real\n'
    printf 'machine. A path can be registered, have its tool installed, and still\n'
    printf 'not work.\n\n'
    printf '| From | To | Kind | Tool | Demonstrated |\n|---|---|---|---|---|\n'
    local k dem
    for k in "${CVT_ORDER[@]:-}"; do
        [ -n "$k" ] || continue
        if [ "${CVT_KIND[$k]:-}" = refused ]; then dem='n/a'
        elif [ -n "${CVT_CAVEAT[$k]:-}" ]; then dem='**no** -- see below'
        else dem='yes'; fi
        printf '| `%s` | `%s` | **%s** | %s | %s |\n' \
            "${k%%:*}" "${k##*:}" "${CVT_KIND[$k]:-?}" "${CVT_TOOL[$k]:---}" "$dem"
    done

    local any=0
    for k in "${CVT_ORDER[@]:-}"; do
        [ -n "${CVT_CAVEAT[$k]:-}" ] || continue
        [ "$any" = 0 ] && { printf '\n#### Registered, not demonstrated\n\n'; any=1; }
        printf '**`%s` to `%s`**\n\n> %s\n\n' "${k%%:*}" "${k##*:}" "${CVT_CAVEAT[$k]}"
    done

    printf '\n### Why the refusals are refusals\n\n'
    for k in "${CVT_ORDER[@]:-}"; do
        [ -n "$k" ] || continue
        [ "${CVT_KIND[$k]:-}" = refused ] || continue
        printf '**`%s` to `%s`** (%s)\n\n> %s\n\n' \
            "${k%%:*}" "${k##*:}" "${CVT_REFUSAL[$k]:-physics}" "${CVT_NOTE[$k]:-}"
    done
    printf '%s\n' "$END"
}

# ---------------------------------------------------------------------------
gen_profiles() {
    load_lib
    pf_profiles_load 2>/dev/null || true
    pf_metadata_load 2>/dev/null || true
    pf_engines_load 2>/dev/null || true

    printf '%s\n%s\n\n' "$BEGIN" "$NOTE"
    printf '| Profile | Library | Families | Recipes ship here |\n|---|---|---|---|\n'
    local p fam gen
    for p in $(prof_list 2>/dev/null | sort); do
        fam=$(printf '%s' "${PROF_FAMILIES[$p]:-}" | tr '[:lower:]' '[:upper:]')
        # A profile is generatable when its recipes can be obtained:
        #
        #   shipped with PseudoForge    -- native, derived (heuristic decks),
        #                                  builtin (cp2k-gth, hgh, adpack)
        #   fetched on first use        -- tarball (sg15, gbrv), github
        #                                  (pseudodojo)
        #   built by the engine itself  -- engine (opium, fhi, uspp,
        #                                  vanderbilt, atompaw)
        #
        # prof_is_generatable only recognised native|derived, so every
        # library whose recipes were fetched or engine-built was marked
        # "import only" -- wrong for atompaw, pseudodojo, gbrv, fhi, gth,
        # uspp, adpack, cp2k-gth, hgh, opium.
        # A profile is generatable when PseudoForge can produce its decks:
        #
        #   shipped with PseudoForge    -- native, derived (heuristic decks),
        #                                  builtin (cp2k-gth, hgh, adpack)
        #   fetched on first use        -- tarball (sg15, gbrv), github
        #                                  (pseudodojo)
        #   built by the engine itself  -- engine (opium, fhi, uspp,
        #                                  vanderbilt, atompaw)
        #
        # `selection` is deliberately excluded: SSSP is a curated index of
        # other people's pseudopotentials, not a generator of its own, and
        # marking it "yes" would claim we can produce it when we can only
        # point at the files the SSSP authors chose.
        case $(params_kind "$p" 2>/dev/null) in
            tarball|github|engine|builtin) gen=yes ;;
            *)
                case ${PROF_PROVENANCE[$p]:-} in
                    native|derived) gen=yes ;;
                    *)              gen='import only' ;;
                esac ;;
        esac
        printf '| `%s` | %s | %s | %s |\n' "$p" "${PROF_LABEL[$p]:-$p}" "$fam" "$gen"
    done
    printf '\n%s\n' "$END"
}

# ---------------------------------------------------------------------------
gen_http_api() {
    load_lib
    # shellcheck source=/dev/null
    . "$PF_LIB/http.sh" 2>/dev/null || true

    printf '%s
%s

' "$BEGIN" "$NOTE"
    printf '| Method | Path | What it does |
|---|---|---|
'
    local m p h sm
    while IFS=$'	' read -r m p h sm; do
        [ -n "$m" ] || continue
        printf '| `%s` | `%s` | %s |
' "$m" "$p" "$sm"
    done < <(http_routes)
    printf '
%s
' "$END"
}

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
gen_coverage() {
    load_lib
    pf_profiles_load 2>/dev/null || true
    pf_engines_load 2>/dev/null || true
    pf_elements_load 2>/dev/null || true
    pf_xc_load 2>/dev/null || true
    pf_formats_load 2>/dev/null || true

    # prof_covers_element reads SPEC[family], SPEC[xc] and SPEC[rel].  Those
    # belong to the run specification in lib/recipe.sh, which this generator
    # does not source (it is not building a run, it is describing profiles).
    # Declaring the array here and filling the three keys below is enough for
    # the probe; nothing else in this function touches a run specification.
    declare -gA SPEC 2>/dev/null || true

    printf '%s\n%s\n\n' "$BEGIN" "$NOTE"

    # ----- 1. Per profile: engine, families, functionals, element counts ---
    #
    # prof_coverage_count reads SPEC[family], SPEC[xc] and SPEC[rel] when
    # deciding whether a profile covers an element.  Nothing in this script
    # populates SPEC, so we stage it per profile: the family is the profile's
    # own first family, and xc/rel are that profile's first declared value.
    # The element count then reflects "can this profile produce this element
    # in at least one of the configurations it declares".
    printf '### Profiles and what they cover\n\n'
    printf '| Profile | Engine | Families | Functionals | Elements |\n'
    printf '|---|---|---|---|---|\n'
    local p eng fams xcs fam n parts first_xc first_rel
    for p in $(prof_list 2>/dev/null | sort); do
        eng=${PROF_ENGINE[$p]:-ld1}
        fams=$(printf '%s' "${PROF_FAMILIES[$p]:-}" | tr '[:lower:]' '[:upper:]')
        xcs=${PROF_XC[$p]:-any}
        # A concrete xc/rel for prof_compatible.  The values do not change
        # the *element* count -- the recipe database is the same for every
        # xc and rel -- but prof_covers_element refuses to look until SPEC
        # is populated, so any valid value does.
        first_xc=${xcs%% *}
        case $first_xc in
            any|varies|"") first_xc=${DEFAULT_XC:-pbe} ;;
        esac
        first_rel=${PROF_REL[$p]:-scalar}
        first_rel=${first_rel%% *}
        case $first_rel in
            "" ) first_rel=${DEFAULT_RELATIVITY:-scalar} ;;
        esac
        SPEC[xc]="$first_xc"
        SPEC[rel]="$first_rel"
        # What the "elements" column means depends on where the decks come
        # from.  A profile backed by a library that publishes decks (psl-*,
        # gbrv, sg15, pseudodojo, cp2k-gth, hgh, adpack, gipaw) has a fixed
        # set of elements, and prof_coverage_count counts them.  A profile
        # whose decks are built by the engine from the element's ground-state
        # configuration (opium, atompaw, fhi98pp, vanderbilt) has no cached
        # decks to count -- every element the table covers can be produced.
        # Printing "0" there would say the profile covers nothing, which is
        # the opposite of the truth.
        local kind
        kind=$(params_kind "$p" 2>/dev/null || echo none)
        parts=""
        for fam in ${PROF_FAMILIES[$p]:-}; do
            SPEC[family]=$fam
            case $kind in
                engine)
                    parts="$parts ${fam^^}:any" ;;
                *)
                    n=$(prof_coverage_count "$p" "$fam" 2>/dev/null || echo 0)
                    parts="$parts ${fam^^}:$n" ;;
            esac
        done
        parts=$(printf '%s' "$parts" | sed 's/^ //')
        # No anchor: profiles.md is a table, not headings.  Link to the page.
        printf '| %s | %s | %s | %s | %s |\n' \
            "${PROF_LABEL[$p]:-$p}" "$eng" "$fams" "$xcs" "$parts"
    done
    printf '\n'

    # ----- 2. Per format: engines that write it natively -------------------
    printf '### Formats and the engines that write them\n\n'
    printf '| Format | Engines |\n'
    printf '|---|---|\n'
    local f
    for f in $(printf '%s\n' "${FMT_ORDER[@]}" 2>/dev/null); do
        fmt_engines_for "$f" >/dev/null 2>&1 || continue
        printf '| `%s` (%s) | %s |\n' "$f" "${FMT_LABEL[$f]:-$f}" \
            "$(fmt_engines_for "$f" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
    done
    printf '\n'

    # ----- 3. Per element: which profiles cover it -------------------------
    #
    # For each element we ask each profile in each of its families.  That is
    # 100+ elements × 20+ profiles × up to three families -- about 6,000
    # probes.  Acceptable here: this script is not on any hot path, and the
    # alternative is a hand-written table that drifts.
    printf '### Elements and the profiles that cover them\n\n'
    printf '| Element | Profiles |\n'
    printf '|---|---|\n'
    local el
    for el in "${EL_ORDER[@]}"; do
        parts=""
        for p in $(prof_list 2>/dev/null | sort); do
            xcs=${PROF_XC[$p]:-any}
            first_xc=${xcs%% *}
            case $first_xc in
                any|varies|"") first_xc=${DEFAULT_XC:-pbe} ;;
            esac
            first_rel=${PROF_REL[$p]:-scalar}
            first_rel=${first_rel%% *}
            case $first_rel in
                "") first_rel=${DEFAULT_RELATIVITY:-scalar} ;;
            esac
            SPEC[xc]="$first_xc"
            SPEC[rel]="$first_rel"
            for fam in ${PROF_FAMILIES[$p]:-}; do
                SPEC[family]=$fam
                if prof_covers_element "$p" "$el" "$fam" "$first_xc" "$first_rel" 2>/dev/null; then
                    parts="$parts $(printf '`%s`' "$p")"
                    break
                fi
            done
        done
        parts=$(printf '%s' "$parts" | sed 's/^ //')
        [ -n "$parts" ] || parts="--"
        printf '| %s (%s) | %s |\n' "$el" "${EL_NAME[$el]:-$el}" "$parts"
    done

    printf '\n%s\n' "$END"
}

splice() {   # splice <page>
    local page=$1 tmp gen target
    target=$DOCS/reference/$page.md
    [ -f "$target" ] || { printf 'no such page: %s\n' "$target" >&2; return 1; }
    gen=$(mktemp); tmp=$(mktemp)
    local fn=gen_$page; [ "$page" = http-api ] && fn=gen_http_api
    "$fn" > "$gen" || { rm -f "$gen" "$tmp"; return 1; }
    awk -v genfile="$gen" '
        index($0, "generated:begin") {
            while ((getline line < genfile) > 0) print line
            skipping = 1; next
        }
        index($0, "generated:end") { skipping = 0; next }
        !skipping { print }' "$target" > "$tmp"
    mv "$tmp" "$target"; rm -f "$gen"
    printf 'updated %s\n' "${target#"$ROOT/"}"
}

region() { awk 'index($0,"generated:begin"),index($0,"generated:end")'; }

PAGES="cli engines formats profiles http-api coverage"

case ${1:-} in
    cli|engines|formats|profiles|coverage) "gen_$1" ;;
    http-api) gen_http_api ;;
    --write) for p in $PAGES; do splice "$p"; done ;;
    --check)
        rc=0
        for p in $PAGES; do
            t=$DOCS/reference/$p.md
            [ -f "$t" ] || { printf 'missing: docs/reference/%s.md\n' "$p"; rc=1; continue; }
            gf=gen_$p; [ "$p" = http-api ] && gf=gen_http_api
            if ! diff -q <(region < "$t") <("$gf" | region) >/dev/null 2>&1; then
                printf 'stale: docs/reference/%s.md\n' "$p"; rc=1
            fi
        done
        [ "$rc" = 0 ] && printf 'all generated tables are current\n'
        exit $rc ;;
    *)
        printf 'usage: %s cli|engines|formats|profiles|http-api|coverage | --write | --check\n' "${0##*/}" >&2
        exit 2 ;;
esac
