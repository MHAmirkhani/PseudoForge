# shellcheck shell=bash
# ---------------------------------------------------------------------------
# sssp.sh -- the Standard Solid State Pseudopotentials selection.
#
# SSSP is not a library.  It publishes no generator, no radii, no input decks,
# and it does not make pseudopotentials.  What it publishes is a *verdict*: for
# each element, which of the existing libraries won a large convergence and
# equation-of-state verification against all-electron reference data, and what
# cut-off that winner needs.  Treating it as a library to be downloaded misses
# the point of it; treating it as a table to be resolved is the whole job.
#
# So this module answers one question per element -- "whose pseudopotential did
# SSSP pick, and at what cut-off" -- and hands the work to the profile that
# actually owns that pseudopotential.  Nearly all of them are profiles this tool
# already generates, so an SSSP run is mostly a locally generated one:
#
#   100PAW / 100US / -low   PSlibrary 1.0.0        generated here
#   031PAW / 031US          PSlibrary 0.3.1        generated here
#   SG15 / SG15-1.1         SG15 ONCV              generated here
#   Dojo                    PseudoDojo             generated here
#   GBRV-*                  GBRV                   generated here
#   MalteSachs              Marburg (AG Kraus)     generated here
#   Wentzcovitch            Wentzcovitch           download only
#   THEOS                   THEOS                  download only
#
# The cut-offs are the part that cannot be regenerated and are worth carrying
# on their own: they are the output of the verification campaign, not of any
# atomic code, and they are why people cite SSSP.
#
# Only the selection tables are bundled -- four JSON files, 120 KB -- not the
# 60 MB pseudopotential archives.  Shipping those would be shipping copies of
# other people's libraries under SSSP's name, which is the confusion this file
# exists to avoid.
# ---------------------------------------------------------------------------

SSSP_DEFAULT_VERSION=1.3.0

sssp_data_dir() { printf '%s/params/sssp\n' "$PF_DATA"; }

# sssp_accuracy -- "efficiency" (cheaper) or "precision" (tighter).
sssp_accuracy() {
    case $(lower "${SSSP_ACCURACY:-efficiency}") in
        precision|prec|tight) printf 'precision\n' ;;
        *)                    printf 'efficiency\n' ;;
    esac
}

# The functional half of the table name.  SSSP publishes PBE and PBEsol only,
# and asking for anything else has to fail rather than silently get PBE.
sssp_xc_name() {
    case $(lower "$(xc_qe_string "${1:-${SPEC[xc]}}")") in
        pbe)    printf 'PBE\n' ;;
        pbesol) printf 'PBEsol\n' ;;
        *) return 1 ;;
    esac
}

# sssp_table [xc] -- the selection file for the current settings.
sssp_table() {
    local xc name f
    name=$(sssp_xc_name "${1:-${SPEC[xc]}}") || return 1
    f=$(sssp_data_dir)/SSSP_${SSSP_VERSION:-$SSSP_DEFAULT_VERSION}_${name}_$(sssp_accuracy).json
    [ -f "$f" ] || return 1
    printf '%s\n' "$f"
}

# ---------------------------------------------------------------------------
# sssp_entry <element> [xc] -> "filename<TAB>library<TAB>ecutwfc<TAB>ecutrho<TAB>md5"
#
# Parsed with awk rather than a JSON library because the tool is pure Bash and
# this file has a fixed, flat shape: one object per element, five scalar keys.
# ---------------------------------------------------------------------------
sssp_entry() {
    local el=$1 f
    f=$(sssp_table "${2:-${SPEC[xc]}}") || return 1
    local _out
    _out=$(awk -v want="$el" '
        function val(s) {
            sub(/^[^:]*:[[:space:]]*/, "", s)
            gsub(/^[",[:space:]]+|[",[:space:]]+$/, "", s)
            return s
        }
        # element keys sit at the top level: "Si": {
        /^[[:space:]]*"[A-Z][a-z]?"[[:space:]]*:[[:space:]]*\{/ {
            k = $0
            gsub(/^[[:space:]]*"|"[[:space:]]*:.*$/, "", k)
            inblock = (k == want)
            next
        }
        inblock && /"filename"/    { fn  = val($0) }
        inblock && /"pseudopotential"/ { lib = val($0) }
        inblock && /"cutoff_wfc"/  { wfc = val($0) }
        inblock && /"cutoff_rho"/  { rho = val($0) }
        inblock && /"md5"/         { md5 = val($0) }
        inblock && /^[[:space:]]*\}/ {
            if (fn != "") printf "%s\t%s\t%s\t%s\t%s\n", fn, lib, wfc, rho, md5
            exit
        }' "$f")
    # The awk prints nothing for an element the table does not carry.  An
    # empty result must be a non-zero exit rather than a silent success: the
    # interface contract says failure is signalled by the status code, and a
    # caller that only checked $? would have treated "no such element" as a
    # valid empty record.
    [ -n "$_out" ] || return 1
    printf '%s
' "$_out"
}

sssp_elements() {
    local f
    f=$(sssp_table "${1:-${SPEC[xc]}}") || return 1
    grep -oE '^[[:space:]]*"[A-Z][a-z]?"[[:space:]]*:' "$f" | tr -d ' ":' | sort -u
}

# ---------------------------------------------------------------------------
# sssp_profile_for <sssp-library-name>
#
# Map SSSP's label for a source onto the profile that owns it.  An unknown
# label returns nothing, and the caller must treat that as "cannot generate"
# rather than guessing a profile -- guessing would silently substitute a
# different library's pseudopotential for the one SSSP verified.
# ---------------------------------------------------------------------------
sssp_profile_for() {
    case $1 in
        100PAW|100US|100PAW-low|US100-low) printf 'psl-high\n' ;;
        031PAW|031US)                      printf 'psl-031\n' ;;
        SG15|SG15-1.1)                     printf 'sg15\n' ;;
        Dojo)                              printf 'pseudodojo\n' ;;
        GBRV-*)                            printf 'gbrv\n' ;;
        MalteSachs)                        printf 'marburg\n' ;;
        Wentzcovitch)                      printf 'wentzcovitch\n' ;;
        THEOS)                             printf 'theos\n' ;;
        *) return 1 ;;
    esac
}

# The family SSSP's choice implies, read off the filename it names.
sssp_family_for() {
    case $1 in
        *kjpaw*|*PAW*|*paw*) printf 'paw\n' ;;
        *rrkjus*|*.us.*|*US*|*us*|*van*) printf 'us\n' ;;
        *oncv*|*ONCV*|*nc*|*NC*) printf 'nc\n' ;;
        *) printf '\n' ;;
    esac
}

# Can PseudoForge produce SSSP's choice for this element itself?
sssp_can_generate() {
    local el=$1 fn lib prof fam
    IFS=$'\t' read -r fn lib _ _ _ < <(sssp_entry "$el") || return 1
    [ -n "${lib:-}" ] || return 1
    prof=$(sssp_profile_for "$lib") || return 1
    fam=$(sssp_family_for "$fn")
    [ -n "$fam" ] || return 1
    prof_can_generate "$prof" "$fam" 2>/dev/null
}

# ---------------------------------------------------------------------------
# sssp_report [xc] -- what `pseudoforge list sssp` prints.
# ---------------------------------------------------------------------------
sssp_report() {
    local xc=${1:-${SPEC[xc]}} el fn lib wfc rho prof fam n=0 gen=0
    if ! sssp_table "$xc" >/dev/null 2>&1; then
        error "SSSP publishes PBE and PBEsol only; there is no $(upper "$(xc_qe_string "$xc")") table."
        return 1
    fi
    banner "SSSP $(upper "$(sssp_xc_name "$xc")") $(sssp_accuracy) ${SSSP_VERSION:-$SSSP_DEFAULT_VERSION}"
    printf '  %-4s %-46s %-14s %-9s %s\n' EL FILE 'CHOSEN FROM' 'ECUT/RHO' 'HERE?'
    printf '  %s\n' "$(printf '%.0s-' $(seq 1 92))"
    for el in $(sssp_elements "$xc"); do
        IFS=$'\t' read -r fn lib wfc rho _ < <(sssp_entry "$el" "$xc") || continue
        n=$((n + 1))
        prof=$(sssp_profile_for "$lib" 2>/dev/null || printf '?')
        fam=$(sssp_family_for "$fn")
        if sssp_can_generate "$el" 2>/dev/null; then
            gen=$((gen + 1)); mark="generate"
        else
            mark="download"
        fi
        printf '  %-4s %-46s %-14s %5s/%-4s %s\n' "$el" "$fn" "$lib" "$wfc" "$rho" "$mark"
    done
    printf '\n  %d elements; %d can be generated here, %d have to be fetched.\n' "$n" "$gen" "$((n - gen))"
    printf '  The cut-offs are SSSP verification results and cannot be regenerated;\n'
    printf '  they are recorded with every run that uses this profile.\n\n'
}
