# shellcheck shell=bash
# ---------------------------------------------------------------------------
# profiles.sh -- the pseudopotential library registry.
#
# A profile answers: "which recipe do I use for element X?".  There are three
# kinds, and PseudoForge is explicit about which one you are getting:
#
#   native   pseudoforge generates the pseudopotential with ld1.x from recipes that
#            are byte-identical to the published library's own inputs.
#            (all psl-* profiles -- verified by tests/test_psl_roundtrip.sh)
#
#   derived  PseudoForge builds the ld1.x recipe itself from the element's
#            configuration and a documented heuristic.  Not a reproduction of
#            anybody's library.  (pseudoforge-auto)
#
#   external the library is produced by a different generator (ONCVPSP, uspp,
#            fhi98PP, ATOMPAW) or is a curated selection.  ld1.x cannot
#            reproduce it, so pseudoforge imports the published files and runs the
#            same validation, cutoff-scan and reporting pipeline over them.
#
# Fabricating "close enough" parameters for an external library would produce
# files that carry a trusted name but not the trusted numbers, so pseudoforge
# refuses to do it.
# ---------------------------------------------------------------------------

declare -gA PROF_FORMATS PROF_XC PROF_REL PROF_FAMNOTE PROF_AVAILABLE PROF_LABEL PROF_FAMILIES PROF_PROVENANCE PROF_GENERATOR PROF_ENGINE \
            PROF_SET_PAW PROF_SET_US PROF_SET_NC PROF_SUMMARY PROF_NOTES \
            PROF_REFERENCE PROF_LICENSE PROF_AUTHOR PROF_UPSTREAM \
            PROF_ECUTWFC PROF_ECUTRHO PROF_CUTOFF_TABLE
declare -ga PROF_ORDER=()

pf_profiles_load() {
    [ ${#PROF_ORDER[@]} -gt 0 ] && return 0
    local d=$PF_DATA/profiles f id key val
    local -a nat=() der=() ext=()
    [ -d "$d" ] || die "profile directory not found: $d"
    # native first, then derived, then external -- this is also the menu order
    # user profiles load after the shipped ones, so a user file of the
    # same name is an override rather than a duplicate
    # Two globs rather than $(ls ...): the installation path may contain a
    # space, and command substitution would word-split every path in half.
    # Shipped profiles first, so a user file of the same name overrides.
    for f in "$d"/*.profile "${PF_USER_DATA:-$HOME/.pseudoforge}"/profiles/*.profile; do
        [ -e "$f" ] || continue
        id=${f##*/}; id=${id%.profile}
        case " ${PROF_ORDER[*]:-} " in
            *" $id "*) ;;
            *) PROF_ORDER+=("$id") ;;
        esac
        while IFS='=' read -r key val; do
            case $key in ''|\#*) continue ;; esac
            case $key in
                label)        PROF_LABEL[$id]=$val ;;
                families)     PROF_FAMILIES[$id]=$val ;;
                provenance)   PROF_PROVENANCE[$id]=$val ;;
                generator)    PROF_GENERATOR[$id]=$val ;;
                engine)       PROF_ENGINE[$id]=$val ;;
                set_paw)      PROF_SET_PAW[$id]=$val ;;
                set_us)       PROF_SET_US[$id]=$val ;;
                set_nc)       PROF_SET_NC[$id]=$val ;;
                summary)      PROF_SUMMARY[$id]=$val ;;
                available)    PROF_AVAILABLE[$id]=$val ;;
                formats)      PROF_FORMATS[$id]=$val ;;
                xc_available) PROF_XC[$id]=$val ;;
                rel_available) PROF_REL[$id]=$val ;;
                families_note) PROF_FAMNOTE[$id]=$val ;;
                notes)        PROF_NOTES[$id]=$val ;;
                reference)    PROF_REFERENCE[$id]=$val ;;
                license)      PROF_LICENSE[$id]=$val ;;
                author)       PROF_AUTHOR[$id]=$val ;;
                upstream)     PROF_UPSTREAM[$id]=$val ;;
                default_ecutwfc) PROF_ECUTWFC[$id]=$val ;;
                default_ecutrho) PROF_ECUTRHO[$id]=$val ;;
                cutoff_table) PROF_CUTOFF_TABLE[$id]=$val ;;
            esac
        done < "$f"
    done
    # stable ordering: native, derived, external; alphabetical within a group
    for id in "${PROF_ORDER[@]}"; do
        case ${PROF_PROVENANCE[$id]:-external} in
            native)       nat+=("$id") ;;
            reproducible) nat+=("$id") ;;
            derived)      der+=("$id") ;;
            *)            ext+=("$id") ;;
        esac
    done
    PROF_ORDER=("${nat[@]}" "${der[@]}" "${ext[@]}")
}

prof_exists() { pf_profiles_load; [ -n "${PROF_LABEL[$1]:-}" ]; }

prof_supports_family() {   # <profile> <nc|us|paw>
    pf_profiles_load
    in_list "$2" ${PROF_FAMILIES[$1]:-}
}

prof_is_generatable() {    # can PseudoForge actually run ld1.x for this profile?
    pf_profiles_load
    case ${PROF_PROVENANCE[$1]:-} in native|derived) return 0 ;; esac
    return 1
}

# The PSlibrary database set backing <profile> for <family>, or empty.
prof_psl_set() {
    pf_profiles_load
    case $2 in
        paw) printf '%s\n' "${PROF_SET_PAW[$1]:-}" ;;
        us)  printf '%s\n' "${PROF_SET_US[$1]:-}"  ;;
        nc)  printf '%s\n' "${PROF_SET_NC[$1]:-}"  ;;
    esac
}

prof_list() { pf_profiles_load; printf '%s\n' "${PROF_ORDER[@]}"; }

prof_list_for_family() {
    pf_profiles_load
    local fam=$1 id
    for id in "${PROF_ORDER[@]}"; do prof_supports_family "$id" "$fam" && printf '%s\n' "$id"; done
}

# Human-readable provenance marker used in menus and reports.
prof_badge() {
    pf_profiles_load
    case ${PROF_PROVENANCE[$1]:-} in
        native)  printf 'generated
'; return ;;
        derived) printf 'derived
';   return ;;
    esac
    # Not shipped with PseudoForge, but most libraries publish their own generation
    # inputs.  If those are obtainable and an engine can run them, the library
    # is reproducible here and should not be called import-only.
    case $(params_kind "$1") in
        builtin)   printf 'generated
' ;;
        engine)    if params_have "$1"; then printf 'generated
'
                   else                      printf 'build engine
'; fi ;;
        tarball|github)
                   if params_have "$1"; then printf 'generated
'
                   else                      printf 'needs inputs
'; fi ;;
        analytic)  printf 'analytic
'; return ;;
        selection) printf 'selection
' ;;
        *)         printf 'import-only
' ;;
    esac
}

prof_describe() {
    pf_profiles_load
    local id=$1
    # An id that is not a profile must not take the whole screen down with it.
    if [ -z "${PROF_LABEL[$id]:-}" ]; then
        printf 'No profile called "%s".
' "$id"
        return 1
    fi
    printf '%s%s%s  [%s]\n' "$C_BOLD" "${PROF_LABEL[$id]}" "$C_RESET" "$(prof_badge "$id")"
    printf '  families : %s\n' "${PROF_FAMILIES[$id]:-n/a}"
    printf '  generator: %s\n' "${PROF_GENERATOR[$id]:-n/a}"
    [ -n "${PROF_AUTHOR[$id]:-}" ]    && printf '  author   : %s\n' "${PROF_AUTHOR[$id]}"
    [ -n "${PROF_REFERENCE[$id]:-}" ] && printf '  reference: %s\n' "${PROF_REFERENCE[$id]}"
    [ -n "${PROF_LICENSE[$id]:-}" ]   && printf '  license  : %s\n' "${PROF_LICENSE[$id]}"
    printf '\n  %s\n' "${PROF_SUMMARY[$id]:-}"
    # What the library itself publishes -- measured, not assumed, so the
    # download step cannot promise a functional that was never released.
    if [ -n "${PROF_AVAILABLE[$id]:-}" ]; then
        printf '\n  Officially available: %s\n' "${PROF_AVAILABLE[$id]}"

    fi
    [ -n "${PROF_NOTES[$id]:-}" ] && printf '\n  %s\n' "${PROF_NOTES[$id]}"
    # The settings this profile actually accepts.  Someone choosing it needs to
    # know which functional and relativity to ask for, or they hit a refusal
    # three screens later.
    if [ -n "${PROF_XC[$id]:-}" ]; then
        printf '
  Settings this profile supports
'
        printf '    functional  %s
' "${PROF_XC[$id]}"
        printf '    relativity  %s
' "${PROF_REL[$id]:-scalar}"
        printf '    families    %s
' "${PROF_FAMNOTE[$id]:-${PROF_FAMILIES[$id]:-}}"
        printf '    writes      %s
' "${PROF_FORMATS[$id]:-upf}"
    fi
}

# ---------------------------------------------------------------------------
# Recipe lookup against the extracted PSlibrary database.
# ---------------------------------------------------------------------------

# psl_recipes <set> <element> [rel]   ->  lines "tag<TAB>upfkey<TAB>cond"
psl_recipes() {
    local set=$1 el=$2 rel=${3:-} line cond
    psl_recipes_r "$set" "$el" || return 1
    for line in "${PSL_R[@]}"; do
        cond=${line##*	}
        [ -z "$rel" ] || [ "$cond" = any ] || [ "$cond" = "$rel" ] || continue
        printf '%s\n' "$line"
    done
}

# psl_template <set> <element> <tag> <cond>  -> path to the .tpl file
psl_template() {
    local set=$1 el=$2 tag=$3 cond=$4
    local p=$PF_DATA/psl/$set/$el.$tag.tpl
    [ "$cond" = any ] || p=$PF_DATA/psl/$set/$el.$tag.$cond.tpl
    [ -f "$p" ] || return 1
    printf '%s\n' "$p"
}

psl_test_template() {
    local set=$1 el=$2 tag=$3 cond=$4
    local p=$PF_DATA/psl/tests/$set/$el.$tag.tpl
    [ "$cond" = any ] || p=$PF_DATA/psl/tests/$set/$el.$tag.$cond.tpl
    [ -f "$p" ] || return 1
    printf '%s\n' "$p"
}

psl_test_frozen_core() {
    local f=$PF_DATA/psl/tests/$1.frozen_core
    [ -f "$f" ] && cat "$f" || echo ".false."
}

# ---------------------------------------------------------------------------
# Upstream errata.
#
# data/psl/ERRATA.tsv records the handful of upstream PSlibrary decks that are
# not merely unusual but impossible, together with the correction the extractor
# reapplies on every extraction.  A run that used a corrected recipe has to say
# so: the deck is PSlibrary's in every other byte, and a reader comparing our
# output against upstream's deserves to know which line differs and why.
# ---------------------------------------------------------------------------
declare -gA PSL_ERRATA=()
declare -g  PSL_ERRATA_LOADED=

psl_errata_load() {
    [ -n "$PSL_ERRATA_LOADED" ] && return 0
    PSL_ERRATA_LOADED=1
    local f=$PF_DATA/psl/ERRATA.tsv set el tag field up corr reason
    [ -f "$f" ] || return 0
    while IFS=$'\t' read -r set el tag field up corr reason; do
        case $set in ''|\#*) continue ;; esac
        PSL_ERRATA["$set|$el|$tag"]="$field	$up	$corr	$reason"
    done < "$f"
    return 0
}

# psl_erratum <set> <element> <tag> -> "field<TAB>upstream<TAB>corrected<TAB>reason", or 1
psl_erratum() {
    psl_errata_load
    local v=${PSL_ERRATA["$1|$2|$3"]:-}
    [ -n "$v" ] || return 1
    printf '%s\n' "$v"
}

# Elements covered by a set.
psl_set_elements() {
    local idx=$PF_DATA/psl/$1.index
    [ -f "$idx" ] && cut -f1 "$idx" | sort -u
}


# ---------------------------------------------------------------------------
# In-memory index cache.
#
# Generating a whole periodic table means thousands of index lookups; reading
# each .index file once into an associative array turns that from thousands of
# awk processes into a few file reads.
# ---------------------------------------------------------------------------
declare -gA PSL_IDX=()          # "<set>|<element>" -> "tag\tkey\tcond" lines
declare -gA PSL_IDX_LOADED=()

psl_index_load() {
    local set=$1 idx el tag key cond
    [ -n "${PSL_IDX_LOADED[$set]:-}" ] && return 0
    PSL_IDX_LOADED[$set]=1
    idx=$PF_DATA/psl/$set.index
    [ -f "$idx" ] || return 1
    while IFS=$'\t' read -r el tag key cond; do
        [ -n "$el" ] || continue
        PSL_IDX["$set|$el"]+="$tag	$key	$cond"$'\n'
    done < "$idx"
    return 0
}

# Fill the array PSL_R with the "tag\tkey\tcond" lines for one element.
psl_recipes_r() {
    local set=$1 el=$2
    PSL_R=()
    psl_index_load "$set" || return 1
    local blob=${PSL_IDX["$set|$el"]:-}
    [ -n "$blob" ] || return 1
    local line
    while IFS= read -r line; do
        [ -n "$line" ] && PSL_R+=("$line")
    done <<<"$blob"
    [ ${#PSL_R[@]} -gt 0 ]
}
declare -ga PSL_R=()

# Fork-free template lookup: sets REPLY.
psl_template_r() {
    local set=$1 el=$2 tag=$3 cond=$4
    REPLY=$PF_DATA/psl/$set/$el.$tag.tpl
    [ "$cond" = any ] || REPLY=$PF_DATA/psl/$set/$el.$tag.$cond.tpl
    [ -f "$REPLY" ]
}

prof_psl_set_r() {
    case $2 in
        paw) REPLY=${PROF_SET_PAW[$1]:-} ;;
        us)  REPLY=${PROF_SET_US[$1]:-}  ;;
        nc)  REPLY=${PROF_SET_NC[$1]:-}  ;;
        *)   REPLY= ;;
    esac
    [ -n "$REPLY" ]
}

# ---------------------------------------------------------------------------
# prof_can_generate <profile> <family>
#
# The old question was "did PseudoForge ship this library's recipes?", which made
# everything else import-only.  The real question is whether the *authors'*
# generation inputs can be had -- and most libraries publish them alongside the
# finished pseudopotentials.  If the inputs are obtainable and an engine can
# run them, the library is reproducible here.
# ---------------------------------------------------------------------------
prof_can_generate() {
    local prof=$1 fam=${2:-${SPEC[family]:-}} eng
    prof_is_generatable "$prof" && return 0
    case $(params_kind "$prof") in
        tarball|github|engine|builtin) ;;
        *) return 1 ;;
    esac
    eng=$(eng_for_profile "$prof" "$fam")
    eng_supports_family "$eng" "$fam" || return 1
    eng_available "$eng"
}

# Do we already hold this library's own inputs, so a run would be a genuine
# reproduction rather than PseudoForge's own construction?
prof_has_params() { params_have "$1"; }

# ---------------------------------------------------------------------------
# prof_supports_xc / prof_supports_rel / prof_compatible
#
# The wizard asks for a family, a functional and a relativity before it asks
# which library.  Offering a library that cannot honour those answers is a trap:
# the user picks it, and the refusal arrives two screens later, or worse the run
# silently falls back to something else.  So the profile list is filtered by
# what has already been chosen.
#
# A profile that declares nothing is treated as compatible rather than hidden:
# absent data should not silently remove a working option.
# ---------------------------------------------------------------------------
prof_supports_xc() {   # prof_supports_xc <profile> <xc-id>
    pf_profiles_load
    local have=${PROF_XC[$1]:-}
    [ -n "$have" ] || return 0
    case $have in *varies*) return 0 ;; esac
    # A proxy functional is generated with its semilocal parent, so judge the
    # profile on the functional that will actually be handed to the engine.
    in_list "$(xc_generator "$2")" $have
}

prof_supports_rel() {  # prof_supports_rel <profile> <scalar|full|nonrel>
    pf_profiles_load
    local have=${PROF_REL[$1]:-}
    [ -n "$have" ] || return 0
    case $have in *varies*) return 0 ;; esac
    # Non-relativistic is free only for an engine that builds the atom from
    # the relativity it is given -- ld1 and the other generators solve a
    # non-relativistic atom when asked. Engines that run a library's fixed
    # decks return the deck's relativity whatever is requested: ADPACK's are
    # all dirac, and its "nonrel" runs produced fully relativistic files under
    # a nonrel name. For those, nonrel has to be declared like anything else.
    case $(rel_canon "$2") in
        nonrel)
            case ${PROF_ENGINE[$1]:-} in
                adpack|gth|uspp|fhi98pp) in_list nonrel $have ;;
                *) return 0 ;;
            esac ;;
        *) in_list "$(rel_canon "$2")" $have ;;
    esac
}

# prof_compatible <profile> <family> <xc> <rel>
prof_compatible() {
    prof_supports_family "$1" "$2" || return 1
    prof_supports_xc     "$1" "$3" || return 1
    prof_supports_rel    "$1" "$4" || return 1

    # AtomPAW's meta-GGA path is non-relativistic only: its relativistic
    # solver has no meta-GGA branch, and the CLI refuses the combination
    # with a die().  Apply the same rule here so a store plan built for a
    # profile does not schedule a run the CLI will then refuse.
    if [ "${PROF_ENGINE[$1]:-}" = atompaw ] \
       && [ "${XC_FAMILY[$3]:-}" = metaGGA ] \
       && [ "$(rel_canon "$4")" != nonrel ]; then
        return 1
    fi
    return 0
}

# Why was a profile filtered out?  Used to explain an empty list.
prof_incompatible_reason() {
    local id=$1 fam=$2 xc=$3 rel=$4
    if ! prof_supports_family "$id" "$fam"; then
        printf 'no %s recipes (it covers %s)\n' "$(upper "$fam")" "${PROF_FAMILIES[$id]:-?}"
    elif ! prof_supports_xc "$id" "$xc"; then
        printf 'no %s (it publishes %s)\n' "$(upper "$(xc_generator "$xc")")" "${PROF_XC[$id]:-?}"
    elif ! prof_supports_rel "$id" "$rel"; then
        printf 'no %s-relativistic set (it has %s)\n' "$(rel_canon "$rel")" "${PROF_REL[$id]:-?}"
    fi
}

# ---------------------------------------------------------------------------
# Per-element coverage.
#
# "Can this library make Si?" and "can it make Tl?" have different answers, and
# a filter that only reasons about the library as a whole will happily offer
# PseudoDojo for a fully-relativistic PBEsol Tl run that it has no deck for.
# Coverage therefore has to be asked per element, under the settings actually
# chosen, using the same lookup the generator will use -- anything else drifts.
# ---------------------------------------------------------------------------

# prof_covers_element <profile> <element> [family] [xc] [rel]
#   True when a run with these settings would use *that library's* parameters.
prof_covers_element() {
    local prof=$1 el=$2
    local fam=${3:-${SPEC[family]}} xc=${4:-${SPEC[xc]}} rel=${5:-${SPEC[rel]}}

    prof_compatible "$prof" "$fam" "$xc" "$rel" || return 1

    case $prof in
        # PseudoForge's own construction is available wherever it can find
        # something to adapt from, which prof_auto_source decides.
        pseudoforge-auto) prof_auto_source "$el" >/dev/null 2>&1 && return 0 || return 1 ;;
    esac

    # A PSlibrary-backed profile: does the recipe database hold this element?
    local set
    set=$(prof_psl_set "$prof" "$fam")
    if [ -n "$set" ]; then
        psl_recipes "$set" "$el" >/dev/null 2>&1 && \
            [ -n "$(psl_recipes "$set" "$el" 2>/dev/null)" ] && return 0
    fi

    # A profile shipping its own decks: ask the same finder the builder uses.
    #
    # The family has to be staged along with the functional and relativity.
    # params_find reads SPEC[family] for the libraries whose decks differ by
    # family -- gipaw splits ultrasoft from norm-conserving by directory name --
    # so leaving it at whatever the caller happened to have set made every
    # column of the coverage table report the same family's answer.
    local saved_xc=${SPEC[xc]} saved_rel=${SPEC[rel]} saved_fam=${SPEC[family]:-} found=1
    SPEC[xc]=$xc; SPEC[rel]=$rel; SPEC[family]=$fam
    params_find "$prof" "$el" >/dev/null 2>&1 && found=0
    SPEC[xc]=$saved_xc; SPEC[rel]=$saved_rel; SPEC[family]=$saved_fam
    return $found
}

# Every element a profile covers under the current settings.
prof_covered_elements() {
    local prof=$1 fam=${2:-${SPEC[family]}} xc=${3:-${SPEC[xc]}} rel=${4:-${SPEC[rel]}}
    local el
    for el in "${EL_ORDER[@]}"; do
        prof_covers_element "$prof" "$el" "$fam" "$xc" "$rel" && printf '%s\n' "$el"
    done
}

# How many, without building the list -- used for menu labels.
prof_coverage_count() {
    prof_covered_elements "$@" | grep -c . || true
}

# ---------------------------------------------------------------------------
# Which libraries can make *these* elements, with these settings?
#
# Returns "profile<TAB>covered<TAB>total" so a menu can say "SG15 (12 of 14)"
# rather than pretending it is all or nothing.
# ---------------------------------------------------------------------------
prof_rank_for_elements() {
    local fam=$1 xc=$2 rel=$3; shift 3
    local prof el n
    for prof in $(prof_list_for_family "$fam"); do
        prof_can_generate "$prof" "$fam" || continue
        prof_compatible "$prof" "$fam" "$xc" "$rel" || continue
        n=0
        for el in "$@"; do
            prof_covers_element "$prof" "$el" "$fam" "$xc" "$rel" && n=$((n + 1))
        done
        printf '%s\t%s\t%s\n' "$prof" "$n" "$#"
    done
}

# The elements a profile would *not* cover, for an honest warning.
prof_missing_elements() {
    local prof=$1 fam=$2 xc=$3 rel=$4; shift 4
    local el
    for el in "$@"; do
        prof_covers_element "$prof" "$el" "$fam" "$xc" "$rel" || printf '%s\n' "$el"
    done
}

# ---------------------------------------------------------------------------
# prof_auto_source <element>
#
# What PseudoForge's own profile adapts from.  This is the difference between a
# defensible construction and a guess: rather than inventing radii, it looks for
# a *published* deck for this element in any bundled library and adapts that,
# and only falls back to a same-group neighbour when nothing exists at all.
#
# Echoes "<kind>\t<path-or-set>" so the caller can record provenance honestly.
# ---------------------------------------------------------------------------
prof_auto_source() {
    local el=$1 fam=${SPEC[family]} prof set f
    # 1. a published deck for this very element, from any library that has one
    for prof in psl-high psl-low marburg sg15 pseudodojo gbrv psl-alt psl-031; do
        prof_supports_family "$prof" "$fam" 2>/dev/null || continue
        set=$(prof_psl_set "$prof" "$fam")
        if [ -n "$set" ] && [ -n "$(psl_recipes "$set" "$el" 2>/dev/null)" ]; then
            printf 'library\t%s\n' "$prof"; return 0
        fi
        if f=$(params_find "$prof" "$el" 2>/dev/null) && [ -n "$f" ]; then
            printf 'library\t%s\n' "$prof"; return 0
        fi
    done
    # 2. a same-group neighbour, scaled -- clearly a heuristic, labelled as one
    local nb
    nb=$(el_group_neighbour "$el" 2>/dev/null) || return 1
    [ -n "$nb" ] || return 1
    for prof in psl-high psl-low psl-031; do
        set=$(prof_psl_set "$prof" "$fam")
        [ -n "$set" ] || continue
        [ -n "$(psl_recipes "$set" "$nb" 2>/dev/null)" ] && {
            printf 'neighbour\t%s\n' "$nb"; return 0; }
    done
    return 1
}

# ---------------------------------------------------------------------------
# prof_list_sorted [family]
#
# Generatable libraries first, then the ones that can only be fetched or
# imported.  Those are marked with a star wherever they appear, so a list can be
# skimmed without reading every badge: the star means "PseudoForge cannot make
# this one here, and the profile says why".
# ---------------------------------------------------------------------------
prof_list_sorted() {
    # ${1:-...} would treat an explicit empty argument as "unset" and fall
    # back to the current family; ${1-...} distinguishes the two, which is
    # what lets a caller ask for every profile regardless of family.
    local fam=${1-${SPEC[family]:-}} id
    local -a can=() cannot=()
    # An "A && B || C" here would run C as well whenever B exits non-zero,
    # which prof_list_for_family does, and every profile would be listed twice.
    local -a source_list=()
    if [ -n "$fam" ]; then
        mapfile -t source_list < <(prof_list_for_family "$fam")
    else
        mapfile -t source_list < <(prof_list)
    fi
    for id in "${source_list[@]}"; do
        # With no family asked for, sort on whether the library can be
        # generated at all rather than on whether it can be generated as
        # norm-conserving, which is what the nc fallback silently meant.
        if { [ -n "$fam" ] && prof_can_generate "$id" "$fam" 2>/dev/null; } ||
           { [ -z "$fam" ] && prof_can_generate_any "$id" 2>/dev/null; }; then
            can+=("$id")
        else
            cannot+=("$id")
        fi
    done
    [ ${#can[@]}    -gt 0 ] && printf '%s\n' "${can[@]}"
    [ ${#cannot[@]} -gt 0 ] && printf '%s\n' "${cannot[@]}"
    return 0
}

# ---------------------------------------------------------------------------
# prof_can_generate_any <profile>
#
# Can this library be generated in *any* of the families it declares?
#
# The distinction matters for the list and the star: asking prof_can_generate
# with a single family answers "can it be generated as norm-conserving", and
# defaulting that to nc marked GBRV and Vanderbilt as unreproducible when both
# are ultrasoft libraries this tool generates perfectly well.  "Not offered for
# this run" and "not reproducible at all" are different statements and the
# listing makes the second one.
# ---------------------------------------------------------------------------
prof_can_generate_any() {
    pf_profiles_load
    local prof=$1 fam
    for fam in ${PROF_FAMILIES[$prof]:-nc}; do
        prof_can_generate "$prof" "$fam" 2>/dev/null && return 0
    done
    return 1
}

# The marker shown beside a library that cannot be generated here at all.
prof_star() {
    if [ -n "${2:-}" ]; then
        prof_can_generate "$1" "$2" 2>/dev/null && printf '  ' || printf ' *'
    else
        prof_can_generate_any "$1" && printf '  ' || printf ' *'
    fi
}
