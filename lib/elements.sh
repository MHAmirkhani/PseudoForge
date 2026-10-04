# shellcheck shell=bash
# ---------------------------------------------------------------------------
# elements.sh -- periodic table lookup and element-set expansion.
#
# Backed by data/elements/table.tsv:
#   Z  sym  name  period  group  block  series  mass  ground-state config
# ---------------------------------------------------------------------------

declare -gA EL_Z EL_NAME EL_PERIOD EL_GROUP EL_BLOCK EL_SERIES EL_MASS EL_CONFIG EL_RCOV
declare -ga EL_ORDER=()      # symbols ordered by Z

pf_elements_load() {
    [ ${#EL_ORDER[@]} -gt 0 ] && return 0
    local f=$PF_DATA/elements/table.tsv
    [ -f "$f" ] || die "element table not found: $f"
    local z sym name period group block series mass config rcov
    while IFS=$'\t' read -r z sym name period group block series mass config rcov; do
        case $z in ''|\#*) continue ;; esac
        EL_Z[$sym]=$z;         EL_NAME[$sym]=$name
        EL_PERIOD[$sym]=$period; EL_GROUP[$sym]=$group
        EL_BLOCK[$sym]=$block; EL_SERIES[$sym]=$series
        EL_MASS[$sym]=$mass;   EL_CONFIG[$sym]=$config
        EL_RCOV[$sym]=$rcov
        EL_ORDER+=("$sym")
    done < "$f"
    pf_elements_index
    [ ${#EL_ORDER[@]} -gt 0 ] || die "element table is empty: $f"
}

# Lookup maps built once at load time.  el_canon sits inside loops over the
# whole periodic table, so it must not fork.
declare -gA EL_BY_KEY=()

pf_elements_index() {
    local s
    for s in "${EL_ORDER[@]}"; do
        EL_BY_KEY[${s,,}]=$s
        EL_BY_KEY[${EL_NAME[$s],,}]=$s
        EL_BY_KEY[z${EL_Z[$s]}]=$s
    done
}

el_exists() { pf_elements_load; [ -n "${EL_Z[$1]:-}" ]; }

# Normalise user input ("fe", "FE", "iron", "26") to a canonical symbol.
el_canon() {
    pf_elements_load
    local in=$1
    case $in in
        [0-9]*) in=z$in ;;
        *)      in=${in,,} ;;
    esac
    local s=${EL_BY_KEY[$in]:-}
    [ -n "$s" ] || return 1
    printf '%s\n' "$s"
}

# The noble-gas core implied by an ld1 config string, or empty.
el_core() {
    case $1 in
        *\[He\]*) echo He ;; *\[Ne\]*) echo Ne ;; *\[Ar\]*) echo Ar ;;
        *\[Kr\]*) echo Kr ;; *\[Xe\]*) echo Xe ;; *\[Rn\]*) echo Rn ;;
        *) echo "" ;;
    esac
}

# ---------------------------------------------------------------------------
# el_expand <spec>...  ->  newline-separated canonical symbols, Z-ordered,
# de-duplicated.  Accepts:
#     Fe Si O            explicit symbols (or names, or Z numbers)
#     1-18               inclusive Z range
#     all                every element in the table
#     block:d  series:transition  period:4  group:16
#     lanthanides actinides transition-metals main-group magnetic semiconductors
#     !Fe                exclude (applied after all includes)
# ---------------------------------------------------------------------------
el_expand() {
    pf_elements_load
    local -A pick=() drop=()
    local spec s lo hi c

    for spec in "$@"; do
        [ -n "$spec" ] || continue
        # comma-separated lists behave like separate arguments
        case $spec in *,*) el_expand ${spec//,/ }; return $? ;; esac

        local negate=0
        case $spec in !*) negate=1; spec=${spec#!} ;; esac
        local -A hits=()

        case ${spec,,} in
            all)
                for s in "${EL_ORDER[@]}"; do hits[$s]=1; done ;;
            lanthanides|lanthanide)
                for s in "${EL_ORDER[@]}"; do [ "${EL_SERIES[$s]}" = lanthanide ] && hits[$s]=1; done ;;
            actinides|actinide)
                for s in "${EL_ORDER[@]}"; do [ "${EL_SERIES[$s]}" = actinide ] && hits[$s]=1; done ;;
            transition-metals|transition)
                for s in "${EL_ORDER[@]}"; do [ "${EL_SERIES[$s]}" = transition ] && hits[$s]=1; done ;;
            rare-earths)
                for s in "${EL_ORDER[@]}"; do
                    case ${EL_SERIES[$s]} in lanthanide) hits[$s]=1 ;; esac
                done
                hits[Sc]=1; hits[Y]=1 ;;
            main-group)
                for s in "${EL_ORDER[@]}"; do
                    case ${EL_BLOCK[$s]} in s|p) hits[$s]=1 ;; esac
                done ;;
            magnetic)
                for s in Cr Mn Fe Co Ni Gd; do hits[$s]=1; done ;;
            semiconductors)
                for s in Si Ge C B N P As Ga In Al Zn O S Se Te Cd Sb; do hits[$s]=1; done ;;
            block:*)  c=${spec#*:};  for s in "${EL_ORDER[@]}"; do [ "${EL_BLOCK[$s]}"  = "${c,,}" ] && hits[$s]=1; done ;;
            series:*) c=${spec#*:};  for s in "${EL_ORDER[@]}"; do [ "${EL_SERIES[$s]}" = "${c,,}" ] && hits[$s]=1; done ;;
            period:*) c=${spec#*:};  for s in "${EL_ORDER[@]}"; do [ "${EL_PERIOD[$s]}" = "$c" ] && hits[$s]=1; done ;;
            group:*)  c=${spec#*:};  for s in "${EL_ORDER[@]}"; do [ "${EL_GROUP[$s]}"  = "$c" ] && hits[$s]=1; done ;;
            [0-9]*-[0-9]*)
                lo=${spec%%-*}; hi=${spec##*-}
                for s in "${EL_ORDER[@]}"; do
                    [ "${EL_Z[$s]}" -ge "$lo" ] && [ "${EL_Z[$s]}" -le "$hi" ] && hits[$s]=1
                done ;;
            *)
                c=$(el_canon "$spec") || { warn "unknown element or selector: $spec"; continue; }
                hits[$c]=1 ;;
        esac

        if [ $negate = 1 ]; then for s in "${!hits[@]}"; do drop[$s]=1; done
        else                     for s in "${!hits[@]}"; do pick[$s]=1; done
        fi
    done

    for s in "${EL_ORDER[@]}"; do
        [ -n "${pick[$s]:-}" ] || continue
        [ -n "${drop[$s]:-}" ] && continue
        printf '%s\n' "$s"
    done
}

# A short human description of an element, used in menus and reports.
el_describe() {
    pf_elements_load
    local s=$1
    printf 'Z=%-3s %-14s %s-block, %s\n' "${EL_Z[$s]}" "${EL_NAME[$s]}" "${EL_BLOCK[$s]}" "${EL_SERIES[$s]}"
}

# Elements for which a full-relativistic (spin-orbit) treatment is the
# physically sensible default.  Below Z~37 spin-orbit splitting in the valence
# is negligible for most purposes.
el_needs_soc() { pf_elements_load; [ "${EL_Z[$1]:-0}" -ge 37 ]; }

# Elements where nonlinear core correction matters most: alkali/alkaline-earth
# with shallow semicore, 3d/4d/5d transition metals, lanthanides and actinides.
el_wants_nlcc() {
    pf_elements_load
    case ${EL_SERIES[$1]:-} in
        transition|lanthanide|actinide|alkali|alkaline) return 0 ;;
    esac
    return 1
}

# ---------------------------------------------------------------------------
# Covalent radii (Cordero et al., Dalton Trans. 2008) -- used only by the
# pseudoforge-auto profile to scale cut-off radii when a recipe has to be borrowed
# from a same-group neighbour.  Values for the heaviest actinides are
# estimates; anything built on them is flagged as heuristic.
# ---------------------------------------------------------------------------

# The closest element in the same group (or, for f-block elements, the same
# series), preferring the lighter neighbour.
el_group_neighbour() {
    pf_elements_load
    local el=$1 z=${EL_Z[$1]:-} g=${EL_GROUP[$1]:-} ser=${EL_SERIES[$1]:-}
    [ -n "$z" ] || return 1
    local s best="" bestd=999 d
    for s in "${EL_ORDER[@]}"; do
        [ "$s" = "$el" ] && continue
        if [ "$ser" = lanthanide ] || [ "$ser" = actinide ]; then
            [ "${EL_SERIES[$s]}" = "$ser" ] || continue
        else
            [ "${EL_GROUP[$s]}" = "$g" ] || continue
        fi
        d=$(( EL_Z[$s] > z ? EL_Z[$s] - z : z - EL_Z[$s] ))
        # break ties towards the lighter element: its recipe is better tested
        [ "${EL_Z[$s]}" -lt "$z" ] || d=$((d * 2))
        if [ "$d" -lt "$bestd" ]; then bestd=$d; best=$s; fi
    done
    [ -n "$best" ] || return 1
    printf '%s\n' "$best"
}

# Ratio of covalent radii, rounded to two decimals and clamped to a sane band
# so a bad table entry cannot produce a nonsensical deck.
el_radius_ratio() {
    pf_elements_load
    local a=${EL_RCOV[$1]:-} b=${EL_RCOV[$2]:-}
    if [ -z "$a" ] || [ -z "$b" ] || [ "$a" = "-" ] || [ "$b" = "-" ]; then
        echo 1.00; return 0
    fi
    awk -v a="$a" -v b="$b" 'BEGIN {
        r = a / b
        if (r < 0.75) r = 0.75
        if (r > 1.35) r = 1.35
        printf "%.2f\n", r
    }'
}
