# shellcheck shell=bash
# ---------------------------------------------------------------------------
# xc.sh -- exchange-correlation functional registry.
#
# ld1.x can only *generate* LDA and GGA pseudopotentials: the atomic code has
# no meta-GGA, hybrid or nonlocal-correlation solver.  That is a property of
# ld1.x, not a limitation of this tool, and it is also the reason every public
# library ships PBE (and LDA) pseudopotentials and nothing else.
#
# Rather than refuse those functionals, PseudoForge records for each of them the
# semilocal "generator functional" that the community actually uses, generates
# with that, and stamps the provenance into the UPF header and every report.
# A functional is therefore either:
#
#   native  -- ld1.x generates directly with this functional
#   proxy   -- generated with `proxy`, intended for use with this functional
# ---------------------------------------------------------------------------

declare -gA XC_TAG XC_QE XC_FAMILY XC_LABEL XC_STATUS XC_PROXY XC_NOTE
declare -ga XC_ORDER=()
declare -ga XC_FAMILIES=(LDA GGA metaGGA hybrid vdW)

pf_xc_load() {
    [ ${#XC_ORDER[@]} -gt 0 ] && return 0
    local f=$PF_DATA/xc.tsv
    [ -f "$f" ] || die "functional registry not found: $f"
    local id tag qe fam label status proxy note
    while IFS=$'\t' read -r id tag qe fam label status proxy note; do
        case $id in ''|\#*) continue ;; esac
        XC_TAG[$id]=$tag;     XC_QE[$id]=$qe
        XC_FAMILY[$id]=$fam;  XC_LABEL[$id]=$label
        XC_STATUS[$id]=$status
        XC_PROXY[$id]=$([ "$proxy" = "-" ] && echo "" || echo "$proxy")
        XC_NOTE[$id]=$note
        XC_ORDER+=("$id")
    done < "$f"

    # user-defined functionals, added with "pseudoforge xc add"
    local uf=${PF_USER_DATA:-$HOME/.pseudoforge}/xc.tsv
    [ -f "$uf" ] || return 0
    while IFS=$'	' read -r id tag qe fam label status proxy note; do
        case $id in ''|\#*) continue ;; esac
        XC_TAG[$id]=$tag;     XC_QE[$id]=$qe
        XC_FAMILY[$id]=$fam;  XC_LABEL[$id]=$label
        XC_STATUS[$id]=$status
        XC_PROXY[$id]=$([ "$proxy" = "-" ] && echo "" || echo "$proxy")
        XC_NOTE[$id]=$note
        case " ${XC_ORDER[*]:-} " in
            *" $id "*) ;;
            *) XC_ORDER+=("$id") ;;
        esac
    done < "$uf"
}

xc_exists() { pf_xc_load; [ -n "${XC_QE[$1]:-}" ]; }

# Accept an id, a QE short name or a label, return the canonical id.
xc_canon() {
    pf_xc_load
    local want id; want=$(lower "$1")
    for id in "${XC_ORDER[@]}"; do
        [ "$id" = "$want" ] && { printf '%s\n' "$id"; return 0; }
    done
    for id in "${XC_ORDER[@]}"; do
        [ "$(lower "${XC_QE[$id]}")" = "$want" ] && { printf '%s\n' "$id"; return 0; }
        [ "$(lower "${XC_TAG[$id]}")" = "$want" ] && { printf '%s\n' "$id"; return 0; }
    done
    return 1
}

xc_list_family() {
    pf_xc_load
    local fam=$1 id
    for id in "${XC_ORDER[@]}"; do [ "${XC_FAMILY[$id]}" = "$fam" ] && printf '%s\n' "$id"; done
}

# The functional ld1.x is actually asked to use (resolving proxies).
# ---------------------------------------------------------------------------
# xc_engine_native <xc> [engine]
#
# Whether the engine that will actually run can produce this functional itself.
#
# The registry marks meta-GGA as a proxy to PBE, and for seven of the eight
# engines that is exactly right: none has a meta-GGA code path, and running
# SCAN calculations on PBE-generated pseudopotentials is what the field does.
# AtomPAW is the exception -- it carries its own r2SCAN implementation and
# genuinely makes meta-GGA PAW datasets.  A proxy that ignored the engine
# would hand an AtomPAW user a PBE dataset while their input said r2SCAN.
#
# The engine's own functional mapper is the authority, not a second table, so
# the two cannot drift apart.
# ---------------------------------------------------------------------------
xc_engine_native() {
    local id=$1 eng=${2:-${SPEC[engine]:-ld1}} saved rc
    case $eng in
        atompaw)
            saved=${SPEC[xc]:-}
            SPEC[xc]=$id
            XC_NO_ENGINE_LOOKUP=1 ib_atompaw_xc >/dev/null 2>&1; rc=$?
            SPEC[xc]=$saved
            return $rc ;;
        *) return 1 ;;
    esac
}

xc_generator() {
    pf_xc_load
    local id=$1
    if [ "${XC_STATUS[$id]}" = proxy ]; then
        # ...unless the engine about to run can do it for real.
        if [ -z "${XC_NO_ENGINE_LOOKUP:-}" ] && xc_engine_native "$id" 2>/dev/null; then
            printf '%s
' "$id"; return 0
        fi
        printf '%s
' "${XC_PROXY[$id]}"
    else
        printf '%s
' "$id"
    fi
}

xc_qe_string()  { pf_xc_load; printf '%s\n' "${XC_QE[$(xc_generator "$1")]}"; }
xc_is_native()  { pf_xc_load; [ "${XC_STATUS[$1]}" = native ]; }

# File-name tag, including PSlibrary's "rel-" prefix for full-relativistic sets.
# xc_tag <xc-id> <nonrel|scalar|full>
xc_tag() {
    pf_xc_load
    local tag=${XC_TAG[$(xc_generator "$1")]}
    case $2 in full) printf 'rel-%s\n' "$tag" ;; *) printf '%s\n' "$tag" ;; esac
}

# One-line human explanation of what will actually be generated.
xc_explain() {
    pf_xc_load
    local id=$1 gen eng label how
    eng=${SPEC[engine]:-ld1}
    label=${ENG_LABEL[$eng]:-$eng}
    case $eng in
        ld1) how=" as dft=${XC_QE[$id]}" ;;
        gth) how=" from the published $(upper "$(gth_xc_keyword "$id" 2>/dev/null || printf '%s' "$id")") table" ;;
        *)   how="" ;;
    esac
    if [ "${XC_STATUS[$id]}" = native ] || xc_engine_native "$id" "$eng" 2>/dev/null; then
        printf '%s (%s) -- generated natively by %s%s
'                "${XC_LABEL[$id]}" "${XC_FAMILY[$id]}" "$label" "$how"
    else
        gen=$(xc_generator "$id")
        printf '%s (%s) -- %s cannot generate this family; generated with %s instead. %s
'                "${XC_LABEL[$id]}" "${XC_FAMILY[$id]}" "$label" "${XC_LABEL[$gen]}" "${XC_NOTE[$id]}"
    fi
}

# ---- relativity -----------------------------------------------------------
# rel= value for ld1.x.
rel_code() {
    case $1 in
        nonrel|none|0)   echo 0 ;;
        scalar|sr|1)     echo 1 ;;
        full|fr|so|soc|2) echo 2 ;;
        *) return 1 ;;
    esac
}
rel_canon() {
    case $1 in
        nonrel|none|0)    echo nonrel ;;
        scalar|sr|1)      echo scalar ;;
        full|fr|so|soc|2) echo full ;;
        *) return 1 ;;
    esac
}
rel_label() {
    case $(rel_canon "$1") in
        nonrel) echo "Non-relativistic" ;;
        scalar) echo "Scalar-relativistic (no spin-orbit)" ;;
        full)   echo "Full-relativistic (with spin-orbit)" ;;
    esac
}

# ---------------------------------------------------------------------------
# Fork-free variants.  These set REPLY instead of writing to stdout, so callers
# in per-element loops do not pay for a subshell on every lookup.
# ---------------------------------------------------------------------------
xc_generator_r() {
    REPLY=$1
    [ "${XC_STATUS[$1]:-}" = proxy ] && REPLY=${XC_PROXY[$1]}
    return 0
}
xc_qe_string_r() { xc_generator_r "$1"; REPLY=${XC_QE[$REPLY]}; }
xc_tag_r() {
    xc_generator_r "$1"
    REPLY=${XC_TAG[$REPLY]}
    [ "$2" = full ] && REPLY="rel-$REPLY"
    return 0
}
rel_canon_r() {
    case $1 in
        nonrel|none|0)    REPLY=nonrel ;;
        scalar|sr|1)      REPLY=scalar ;;
        full|fr|so|soc|2) REPLY=full ;;
        *) return 1 ;;
    esac
}
rel_code_r() {
    case $1 in
        nonrel|none|0)    REPLY=0 ;;
        scalar|sr|1)      REPLY=1 ;;
        full|fr|so|soc|2) REPLY=2 ;;
        *) return 1 ;;
    esac
}
