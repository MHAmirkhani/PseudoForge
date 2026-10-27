# shellcheck shell=bash
# ---------------------------------------------------------------------------
# advise.sh -- physics-reasoned pseudopotential advisory system
#
# Answers "which pseudopotential should I use for my calculation?" with
# physics reasoning, cutoffs, caveats, citations, avoid list, and CLI syntax.
# ---------------------------------------------------------------------------

declare -gA ADV_CALC_LABEL ADV_CALC_XC ADV_CALC_FAMILY ADV_CALC_FORMAT ADV_CALC_ACCURACY ADV_CALC_RATIONALE
declare -ga ADV_CALC_ORDER=()
declare -gA ADV_OVERRIDE_PROFILE ADV_OVERRIDE_XC ADV_OVERRIDE_WHY
declare -gA ADV_ELEMENT_NOTE

# Results stored from the most recent advise_for run
declare -g ADV_OUT_ELEMENT=""
declare -g ADV_OUT_ELEMENT_NAME=""
declare -g ADV_OUT_MATERIAL_CLASS=""
declare -g ADV_OUT_CALCULATION=""
declare -g ADV_OUT_CODE=""
declare -g ADV_OUT_IS_OVERVIEW=0

declare -gi ADV_OUT_COUNT=0
declare -ga ADV_OUT_RANK=()
declare -ga ADV_OUT_SCORE=()
declare -ga ADV_OUT_PROFILE=()
declare -ga ADV_OUT_PROFILE_LABEL=()
declare -ga ADV_OUT_FAMILY=()
declare -ga ADV_OUT_XC=()
declare -ga ADV_OUT_ENGINE=()
declare -ga ADV_OUT_ENGINE_LABEL=()
declare -ga ADV_OUT_FORMAT=()
declare -ga ADV_OUT_WHY=()
declare -ga ADV_OUT_CAVEATS=()
declare -ga ADV_OUT_CUTOFF_VAL=()
declare -ga ADV_OUT_CUTOFF_UNIT=()
declare -ga ADV_OUT_CUTOFF_SOURCE=()
declare -ga ADV_OUT_LIB_NAME=()
declare -ga ADV_OUT_LIB_DOI=()
declare -ga ADV_OUT_ENG_NAME=()
declare -ga ADV_OUT_ENG_DOI=()
declare -ga ADV_OUT_CLI=()

declare -gi ADV_OUT_AVOID_COUNT=0
declare -ga ADV_OUT_AVOID_WHAT=()
declare -ga ADV_OUT_AVOID_WHY=()

declare -gi ADV_OUT_RELATED_COUNT=0
declare -ga ADV_OUT_RELATED_LABEL=()
declare -ga ADV_OUT_RELATED_CLI=()

# Overview mode storage
declare -gi ADV_OVERVIEW_COUNT=0
declare -ga ADV_OVERVIEW_CALC_ID=()
declare -ga ADV_OVERVIEW_CALC_LABEL=()
declare -ga ADV_OVERVIEW_PROF=()
declare -ga ADV_OVERVIEW_PROF_LABEL=()
declare -ga ADV_OVERVIEW_FAM=()
declare -ga ADV_OVERVIEW_XC=()
declare -ga ADV_OVERVIEW_RATIONALE=()

pf_advice_load() {
    [ ${#ADV_CALC_ORDER[@]} -gt 0 ] && return 0
    local f_calc=$PF_DATA/advice/calculations.tsv
    local f_over=$PF_DATA/advice/calculation-material.tsv
    local f_elem=$PF_DATA/advice/element-notes.tsv

    [ -f "$f_calc" ] || die "calculations table missing: $f_calc"
    [ -f "$f_over" ] || die "overrides table missing: $f_over"
    [ -f "$f_elem" ] || die "element notes table missing: $f_elem"

    local id lbl xc fam fmt acc rat
    while IFS=$'\t' read -r id lbl xc fam fmt acc rat || [ -n "$id" ]; do
        case $id in ''|\#*|id) continue ;; esac
        rat=${rat%$'\r'}
        ADV_CALC_LABEL[$id]=$lbl
        ADV_CALC_XC[$id]=$xc
        ADV_CALC_FAMILY[$id]=$fam
        ADV_CALC_FORMAT[$id]=$fmt
        ADV_CALC_ACCURACY[$id]=$acc
        ADV_CALC_RATIONALE[$id]=$rat
        ADV_CALC_ORDER+=("$id")
    done < "$f_calc"

    local c mat phint xcovr why
    while IFS=$'\t' read -r c mat phint xcovr why || [ -n "$c" ]; do
        case $c in ''|\#*|calculation) continue ;; esac
        why=${why%$'\r'}
        ADV_OVERRIDE_PROFILE["$c:$mat"]=$phint
        ADV_OVERRIDE_XC["$c:$mat"]=$xcovr
        ADV_OVERRIDE_WHY["$c:$mat"]=$why
    done < "$f_over"

    local el note
    while IFS=$'\t' read -r el note || [ -n "$el" ]; do
        case $el in ''|\#*|element) continue ;; esac
        note=${note%$'\r'}
        ADV_ELEMENT_NOTE[$el]=$note
    done < "$f_elem"
}

# el_material_class <element>
# Maps an element to one of the 9 material classes:
# transition-metal | lanthanide | actinide | halogen | noble-gas |
# alkali-metal | alkaline-earth | main-group | metalloid
el_material_class() {
    pf_elements_load
    local el
    el=$(el_canon "$1") || return 1
    local series=${EL_SERIES[$el]:-}
    case $series in
        actinide)        printf 'actinide\n' ;;
        alkali)          printf 'alkali-metal\n' ;;
        alkaline)        printf 'alkaline-earth\n' ;;
        halogen)         printf 'halogen\n' ;;
        lanthanide)      printf 'lanthanide\n' ;;
        metalloid)       printf 'metalloid\n' ;;
        noble)           printf 'noble-gas\n' ;;
        transition)      printf 'transition-metal\n' ;;
        *)               printf 'main-group\n' ;;
    esac
}

# Internal escape helper for JSON output
_adv_json_esc() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' -e 's/\r//g' -e ':a;N;$!ba;s/\n/\\n/g'
}

# advise_for <element> [<calculation>] [<code>] [<material_class>] [<functional>] [<accuracy>]
advise_for() {
    pf_advice_load
    pf_elements_load
    pf_profiles_load
    pf_engines_load
    pf_metadata_load
    pf_formats_load
    pf_xc_load

    declare -gA SPEC 2>/dev/null || true
    local saved_spec_fam=${SPEC[family]:-}
    local saved_spec_xc=${SPEC[xc]:-}
    local saved_spec_rel=${SPEC[rel]:-}
    SPEC[family]=""
    SPEC[xc]=""
    SPEC[rel]=""

    local raw_el=$1
    local raw_calc=${2:-}
    local raw_code=${3:-}
    local raw_mat=${4:-}
    local raw_xc=${5:-}
    local raw_acc=${6:-}

    local el
    el=$(el_canon "$raw_el") || { error "unknown element '$raw_el'"; return 1; }

    local mat=$raw_mat
    [ -z "$mat" ] && mat=$(el_material_class "$el")

    local code=$raw_code
    [ "$code" = "any" ] && code=""

    ADV_OUT_ELEMENT=$el
    ADV_OUT_ELEMENT_NAME=${EL_NAME[$el]:-$el}
    ADV_OUT_MATERIAL_CLASS=$mat
    ADV_OUT_CALCULATION=$raw_calc
    ADV_OUT_CODE=$code

    ADV_OUT_COUNT=0
    ADV_OUT_RANK=()
    ADV_OUT_SCORE=()
    ADV_OUT_PROFILE=()
    ADV_OUT_PROFILE_LABEL=()
    ADV_OUT_FAMILY=()
    ADV_OUT_XC=()
    ADV_OUT_ENGINE=()
    ADV_OUT_ENGINE_LABEL=()
    ADV_OUT_FORMAT=()
    ADV_OUT_WHY=()
    ADV_OUT_CAVEATS=()
    ADV_OUT_CUTOFF_VAL=()
    ADV_OUT_CUTOFF_UNIT=()
    ADV_OUT_CUTOFF_SOURCE=()
    ADV_OUT_LIB_NAME=()
    ADV_OUT_LIB_DOI=()
    ADV_OUT_ENG_NAME=()
    ADV_OUT_ENG_DOI=()
    ADV_OUT_CLI=()

    ADV_OUT_AVOID_COUNT=0
    ADV_OUT_AVOID_WHAT=()
    ADV_OUT_AVOID_WHY=()

    ADV_OUT_RELATED_COUNT=0
    ADV_OUT_RELATED_LABEL=()
    ADV_OUT_RELATED_CLI=()

    # If calculation is empty, run overview mode over all calculations
    if [ -z "$raw_calc" ]; then
        ADV_OUT_IS_OVERVIEW=1
        ADV_OVERVIEW_COUNT=0
        ADV_OVERVIEW_CALC_ID=()
        ADV_OVERVIEW_CALC_LABEL=()
        ADV_OVERVIEW_PROF=()
        ADV_OVERVIEW_PROF_LABEL=()
        ADV_OVERVIEW_FAM=()
        ADV_OVERVIEW_XC=()
        ADV_OVERVIEW_RATIONALE=()

        local c
        for c in "${ADV_CALC_ORDER[@]}"; do
            advise_for "$el" "$c" "$code" "$mat" "$raw_xc" "$raw_acc" >/dev/null 2>&1 || continue
            ADV_OVERVIEW_CALC_ID+=("$c")
            ADV_OVERVIEW_CALC_LABEL+=("${ADV_CALC_LABEL[$c]:-$c}")
            if [ "$ADV_OUT_COUNT" -gt 0 ]; then
                ADV_OVERVIEW_PROF+=("${ADV_OUT_PROFILE[0]}")
                ADV_OVERVIEW_PROF_LABEL+=("${ADV_OUT_PROFILE_LABEL[0]}")
                ADV_OVERVIEW_FAM+=("${ADV_OUT_FAMILY[0]}")
                ADV_OVERVIEW_XC+=("${ADV_OUT_XC[0]}")
            else
                ADV_OVERVIEW_PROF+=("n/a")
                ADV_OVERVIEW_PROF_LABEL+=("n/a")
                ADV_OVERVIEW_FAM+=("n/a")
                ADV_OVERVIEW_XC+=("n/a")
            fi
            ADV_OVERVIEW_RATIONALE+=("${ADV_CALC_RATIONALE[$c]:-}")
            ADV_OVERVIEW_COUNT=$((ADV_OVERVIEW_COUNT + 1))
        done
        ADV_OUT_CALCULATION=""
        ADV_OUT_IS_OVERVIEW=1
        return 0
    fi

    ADV_OUT_IS_OVERVIEW=0
    local calc=$raw_calc
    if [ -z "${ADV_CALC_LABEL[$calc]:-}" ]; then
        error "unknown calculation '$calc' -- try: $(printf '%s ' "${ADV_CALC_ORDER[@]}")"
        return 1
    fi

    local xc_target="${ADV_CALC_XC[$calc]}"
    local family_target="${ADV_CALC_FAMILY[$calc]}"
    local format_target="${ADV_CALC_FORMAT[$calc]}"
    local acc_target="$raw_acc"
    [ -z "$acc_target" ] && acc_target="${ADV_CALC_ACCURACY[$calc]:-balanced}"
    local rationale="${ADV_CALC_RATIONALE[$calc]}"

    # Check override
    local profile_hint=""
    local material_why=""
    local key_spec="$calc:$mat"
    local key_any="$calc:any"
    if [ -n "${ADV_OVERRIDE_PROFILE[$key_spec]:-}" ]; then
        profile_hint="${ADV_OVERRIDE_PROFILE[$key_spec]}"
        [ -n "${ADV_OVERRIDE_XC[$key_spec]:-}" ] && xc_target="${ADV_OVERRIDE_XC[$key_spec]}"
        material_why="${ADV_OVERRIDE_WHY[$key_spec]:-}"
    elif [ -n "${ADV_OVERRIDE_PROFILE[$key_any]:-}" ]; then
        profile_hint="${ADV_OVERRIDE_PROFILE[$key_any]}"
        [ -n "${ADV_OVERRIDE_XC[$key_any]:-}" ] && xc_target="${ADV_OVERRIDE_XC[$key_any]}"
        material_why="${ADV_OVERRIDE_WHY[$key_any]:-}"
    fi

    [ -n "$raw_xc" ] && xc_target="$raw_xc"

    local element_note="${ADV_ELEMENT_NOTE[$el]:-}"

    # Preferred format based on code
    local preferred_fmt=$format_target
    case ${code,,} in
        qe|quantum-espresso) preferred_fmt="upf" ;;
        abinit)              preferred_fmt="psp8" ;;
        cp2k)                preferred_fmt="gth" ;;
        siesta)              preferred_fmt="siesta" ;;
        openmx)              preferred_fmt="openmx" ;;
        castep)              preferred_fmt="recpot" ;;
        vasp)                preferred_fmt="upf" ;;
    esac

    # SSSP probe
    local sssp_acc="efficiency"
    [ "$acc_target" = "stringent" ] && sssp_acc="precision"
    local sssp_rec sssp_lib="" sssp_prof="" sssp_wfc=""
    sssp_rec=$(SSSP_ACCURACY="$sssp_acc" sssp_entry "$el" "$xc_target" 2>/dev/null || \
               SSSP_ACCURACY="$sssp_acc" sssp_entry "$el" "pbe" 2>/dev/null || true)
    if [ -n "$sssp_rec" ]; then
        sssp_lib=$(printf '%s' "$sssp_rec" | awk -F'\t' '{print $2}')
        sssp_prof=$(sssp_profile_for "$sssp_lib" 2>/dev/null || true)
        sssp_wfc=$(printf '%s' "$sssp_rec" | awk -F'\t' '{print $3}')
    fi

    # Relativity
    local rel="scalar"
    [ "$calc" = "xas" ] && rel="full"

    # Enumerate candidate profiles
    local candidates=()
    local p fam eng x score badge
    for p in $(prof_list_sorted ""); do
        badge=$(prof_badge "$p" 2>/dev/null)
        for fam in nc paw us; do
            prof_supports_family "$p" "$fam" || continue
            eng=$(eng_for_profile "$p" "$fam")
            eng_exists "$eng" || continue
            eng_supports_family "$eng" "$fam" || continue

            local test_xcs=()
            if prof_supports_xc "$p" "$xc_target"; then
                test_xcs=("$xc_target")
            else
                for x in pbe pbesol lda; do
                    prof_supports_xc "$p" "$x" && { test_xcs=("$x"); break; }
                done
            fi

            for x in "${test_xcs[@]}"; do
                SPEC[family]=$fam
                SPEC[xc]=$x
                SPEC[rel]=$rel
                prof_covers_element "$p" "$el" "$fam" "$x" "$rel" || continue

                score=0
                [ "$p" = "$profile_hint" ] && score=$((score + 10))
                [ "$x" = "$xc_target" ] && score=$((score + 5))
                [ "$fam" = "$family_target" ] && score=$((score + 3))
                [ -n "$sssp_prof" ] && [ "$p" = "$sssp_prof" ] && score=$((score + 2))
                if [ "$acc_target" = "stringent" ]; then
                    case $p in *high*|*str*|pseudodojo) score=$((score + 2)) ;; esac
                fi
                [ "$badge" = "import-only" ] && score=$((score - 5))
                if [ "$p" = "psl-low" ]; then
                    case $calc in phonons|elastic|phonon-2d) score=$((score - 3)) ;; esac
                fi
                [ "$p" = "psl-tot" ] && score=$((score - 1))
                [ "$p" = "pseudoforge-auto" ] && score=$((score - 3))

                candidates+=("$score|$p|$fam|$x|$eng")
            done
        done
    done

    # Sort candidates by score descending
    local sorted=()
    if [ ${#candidates[@]} -gt 0 ]; then
        while IFS= read -r line; do
            [ -n "$line" ] && sorted+=("$line")
        done < <(printf '%s\n' "${candidates[@]}" | sort -t'|' -k1,1nr -k2,2 -k3,3)
    fi

    # Deduplicate: keep top 3, ensuring distinct (profile, family) tuples
    local seen_combos=""
    local item c_score c_prof c_fam c_xc c_eng
    local chosen=()
    for item in "${sorted[@]}"; do
        c_prof=$(printf '%s' "$item" | cut -d'|' -f2)
        c_fam=$(printf '%s' "$item" | cut -d'|' -f3)
        case " $seen_combos " in
            *" $c_prof:$c_fam "*) continue ;;
        esac
        seen_combos="$seen_combos $c_prof:$c_fam"
        chosen+=("$item")
        [ ${#chosen[@]} -eq 3 ] && break
    done

    # If fewer than 3 chosen, fill with remaining sorted items
    if [ ${#chosen[@]} -lt 3 ]; then
        for item in "${sorted[@]}"; do
            case " ${chosen[*]} " in *" $item "*) continue ;; esac
            chosen+=("$item")
            [ ${#chosen[@]} -eq 3 ] && break
        done
    fi

    # Compose each recommendation
    local rank=1
    for item in "${chosen[@]}"; do
        c_score=$(printf '%s' "$item" | cut -d'|' -f1)
        c_prof=$(printf '%s' "$item" | cut -d'|' -f2)
        c_fam=$(printf '%s' "$item" | cut -d'|' -f3)
        c_xc=$(printf '%s' "$item" | cut -d'|' -f4)
        c_eng=$(printf '%s' "$item" | cut -d'|' -f5)

        ADV_OUT_RANK+=("$rank")
        ADV_OUT_SCORE+=("$c_score")
        ADV_OUT_PROFILE+=("$c_prof")
        ADV_OUT_PROFILE_LABEL+=("${PROF_LABEL[$c_prof]:-$c_prof}")
        ADV_OUT_FAMILY+=("$c_fam")
        ADV_OUT_XC+=("$c_xc")
        ADV_OUT_ENGINE+=("$c_eng")
        ADV_OUT_ENGINE_LABEL+=("${ENG_LABEL[$c_eng]:-$c_eng}")

        # Format resolution
        local fmt=$format_target
        if [ -n "$code" ]; then
            if fmt_for_engine "$c_eng" | grep -qw "$preferred_fmt"; then
                fmt=$preferred_fmt
            fi
        fi
        ADV_OUT_FORMAT+=("$fmt")

        # Why text
        local why_text="$rationale"
        if [ -n "$profile_hint" ] && [ "$c_prof" = "$profile_hint" ] && [ -n "$material_why" ]; then
            why_text="$why_text\n\n$material_why"
        fi
        [ -n "$element_note" ] && why_text="$why_text\n\n$element_note"
        ADV_OUT_WHY+=("$why_text")

        # Caveats
        local caveats=""
        if ! eng_available "$c_eng"; then
            caveats="Requires $c_eng, which is not installed. Install with: ./install.sh --bootstrap or pseudoforge engines build $c_eng"
        fi
        if [ -n "$code" ] && [ "$fmt" != "$preferred_fmt" ]; then
            local c_fmt_warn="Format $preferred_fmt is not written by $c_eng; add --format $fmt"
            if [ -n "$caveats" ]; then
                caveats="$caveats\n$c_fmt_warn"
            else
                caveats="$c_fmt_warn"
            fi
        fi
        ADV_OUT_CAVEATS+=("$caveats")

        # Cutoff
        if [ -n "$sssp_wfc" ]; then
            local clean_wfc
            clean_wfc=$(awk -v v="$sssp_wfc" 'BEGIN { if (v == int(v)) print int(v); else print v }')
            ADV_OUT_CUTOFF_VAL+=("$clean_wfc")
            ADV_OUT_CUTOFF_UNIT+=("Ry")
            local src="SSSP efficiency"
            [ "$acc_target" = "stringent" ] && src="SSSP precision"
            ADV_OUT_CUTOFF_SOURCE+=("$src")
        else
            ADV_OUT_CUTOFF_VAL+=("")
            ADV_OUT_CUTOFF_UNIT+=("")
            ADV_OUT_CUTOFF_SOURCE+=("")
        fi

        # Citations
        ADV_OUT_LIB_NAME+=("${PROF_LABEL[$c_prof]:-$c_prof}")
        ADV_OUT_LIB_DOI+=("$(md_doi "$c_prof")")
        ADV_OUT_ENG_NAME+=("${ENG_LABEL[$c_eng]:-$c_eng}")
        ADV_OUT_ENG_DOI+=("$(md_doi "$c_eng")")

        # CLI command
        local cmd="pseudoforge generate -e $el -t $c_fam -p $c_prof -x $c_xc -r $rel -o ./${el,,}-run"
        ADV_OUT_CLI+=("$cmd")

        rank=$((rank + 1))
        ADV_OUT_COUNT=$((ADV_OUT_COUNT + 1))
    done

    # Compose Avoid list
    case $calc in
        phonons|elastic|phonon-2d)
            ADV_OUT_AVOID_WHAT+=("psl-low")
            ADV_OUT_AVOID_WHY+=("PSLibrary's low-cutoff sets trade accuracy for speed. For phonons, that shows up as soft modes and imaginary frequencies.")
            ADV_OUT_AVOID_COUNT=$((ADV_OUT_AVOID_COUNT + 1))
            ;;
    esac
    ADV_OUT_AVOID_WHAT+=("psl-tot")
    ADV_OUT_AVOID_WHY+=("psl-tot holds upstream's untested extras. Use it only when nothing else covers the element.")
    ADV_OUT_AVOID_COUNT=$((ADV_OUT_AVOID_COUNT + 1))

    # Import-only profiles from prof_list_sorted
    local avoid_p b
    for avoid_p in $(prof_list_sorted ""); do
        b=$(prof_badge "$avoid_p" 2>/dev/null)
        if [ "$b" = "import-only" ]; then
            ADV_OUT_AVOID_WHAT+=("$avoid_p")
            ADV_OUT_AVOID_WHY+=("$avoid_p is import-only; it can be downloaded from the library but not generated here.")
            ADV_OUT_AVOID_COUNT=$((ADV_OUT_AVOID_COUNT + 1))
        fi
    done

    # Compose Related list
    local rel1=""
    case $calc in
        phonons)
            case $mat in
                transition-metal) rel1="magnetism" ;;
                *) rel1="elastic" ;;
            esac
            ;;
        elastic)   rel1="phonons" ;;
        eos)       rel1="phonons" ;;
        band-gap)  rel1="gw" ;;
        gw)        rel1="optics" ;;
        optics)    rel1="gw" ;;
        xas)       rel1="optics" ;;
        magnetism) rel1="dft-u" ;;
        dft-u)     rel1="magnetism" ;;
        md)        rel1="eos" ;;
        transport) rel1="band-gap" ;;
        phonon-2d) rel1="phonons" ;;
    esac
    if [ -n "$rel1" ]; then
        ADV_OUT_RELATED_LABEL+=("$rel1")
        ADV_OUT_RELATED_CLI+=("pseudoforge advise -e $el --calculation $rel1")
        ADV_OUT_RELATED_COUNT=$((ADV_OUT_RELATED_COUNT + 1))
    fi

    SPEC[family]=$saved_spec_fam
    SPEC[xc]=$saved_spec_xc
    SPEC[rel]=$saved_spec_rel

    return 0
}

# advise_render_human [quiet]
advise_render_human() {
    local quiet=${1:-0}
    if [ "$ADV_OUT_IS_OVERVIEW" -eq 1 ]; then
        printf 'Calculations for %s (%s, %s):\n\n' \
            "$ADV_OUT_ELEMENT" "$ADV_OUT_ELEMENT_NAME" "$ADV_OUT_MATERIAL_CLASS"
        local i
        for ((i=0; i<ADV_OVERVIEW_COUNT; i++)); do
            printf '  %-12s %-24s %s (%s, %s)\n' \
                "${ADV_OVERVIEW_CALC_ID[i]}" \
                "${ADV_OVERVIEW_CALC_LABEL[i]}" \
                "${ADV_OVERVIEW_PROF_LABEL[i]}" \
                "${ADV_OVERVIEW_FAM[i]}" \
                "${ADV_OVERVIEW_XC[i]}"
        done
        printf "\nRun 'pseudoforge advise -e %s --calculation <type>' for full physics reasoning.\n" "$ADV_OUT_ELEMENT"
        return 0
    fi

    if [ "$quiet" -eq 1 ]; then
        if [ "$ADV_OUT_COUNT" -gt 0 ]; then
            printf '%s\n' "${ADV_OUT_CLI[0]}"
        fi
        return 0
    fi

    # Header
    if [ -n "$ADV_OUT_CODE" ]; then
        printf 'For %s, %s, with %s:\n\n' \
            "$ADV_OUT_ELEMENT" "$ADV_OUT_CALCULATION" "${ADV_OUT_CODE}"
    else
        printf 'For %s, %s:\n\n' \
            "$ADV_OUT_ELEMENT" "$ADV_OUT_CALCULATION"
    fi

    local i
    for ((i=0; i<ADV_OUT_COUNT; i++)); do
        local fam_name="${ADV_OUT_FAMILY[i]}"
        case $fam_name in
            nc)  fam_name="norm-conserving" ;;
            paw) fam_name="PAW" ;;
            us)  fam_name="ultrasoft" ;;
        esac

        local xc_name="${ADV_OUT_XC[i]}"
        case ${xc_name,,} in
            pbe)    xc_name="PBE" ;;
            pbesol) xc_name="PBEsol" ;;
            lda)    xc_name="LDA" ;;
        esac

        printf '%d. %s — %s, %s  (score %d)\n' \
            "${ADV_OUT_RANK[i]}" \
            "${ADV_OUT_PROFILE_LABEL[i]}" \
            "$fam_name" \
            "$xc_name" \
            "${ADV_OUT_SCORE[i]}"

        printf '   %s\n\n' "${ADV_OUT_CLI[i]}"

        # Render why
        local first_w=1 w_line
        while IFS= read -r w_line || [ -n "$w_line" ]; do
            if [ -z "$w_line" ]; then
                printf '\n'
            elif [ "$first_w" -eq 1 ]; then
                printf '   Why: %s\n' "$w_line"
                first_w=0
            else
                printf '        %s\n' "$w_line"
            fi
        done < <(printf '%b\n' "${ADV_OUT_WHY[i]}")
        printf '\n'

        # Caveats
        if [ -n "${ADV_OUT_CAVEATS[i]}" ]; then
            local first_c=1 c_line
            while IFS= read -r c_line || [ -n "$c_line" ]; do
                [ -z "$c_line" ] && continue
                if [ "$first_c" -eq 1 ]; then
                    printf '   Caveat: %s\n' "$c_line"
                    first_c=0
                else
                    printf '           %s\n' "$c_line"
                fi
            done < <(printf '%b\n' "${ADV_OUT_CAVEATS[i]}")
            printf '\n'
        fi

        # Cutoff
        if [ -n "${ADV_OUT_CUTOFF_VAL[i]}" ]; then
            printf '   Recommended cutoff: %s %s  (%s)\n' \
                "${ADV_OUT_CUTOFF_VAL[i]}" \
                "${ADV_OUT_CUTOFF_UNIT[i]}" \
                "${ADV_OUT_CUTOFF_SOURCE[i]}"
        fi

        # Engine & Library
        printf '   Engine:  %-20s' "${ADV_OUT_ENGINE_LABEL[i]}"
        [ -n "${ADV_OUT_ENG_DOI[i]}" ] && printf ' DOI %s' "${ADV_OUT_ENG_DOI[i]}"
        printf '\n'
        printf '   Library: %-20s' "${ADV_OUT_LIB_NAME[i]}"
        [ -n "${ADV_OUT_LIB_DOI[i]}" ] && printf ' DOI %s' "${ADV_OUT_LIB_DOI[i]}"
        printf '\n\n'
    done

    # Avoid list
    if [ "$ADV_OUT_AVOID_COUNT" -gt 0 ]; then
        printf 'Avoid:\n'
        for ((i=0; i<ADV_OUT_AVOID_COUNT; i++)); do
            printf '  %s — %s\n' "${ADV_OUT_AVOID_WHAT[i]}" "${ADV_OUT_AVOID_WHY[i]}"
        done
        printf '\n'
    fi

    # Related
    printf 'Related:\n'
    for ((i=0; i<ADV_OUT_RELATED_COUNT; i++)); do
        printf '  %s\n' "${ADV_OUT_RELATED_CLI[i]}"
    done
    printf '  pseudoforge advise -e %s                  (all calculations)\n' "$ADV_OUT_ELEMENT"
}

# advise_render_json
advise_render_json() {
    if [ "$ADV_OUT_IS_OVERVIEW" -eq 1 ]; then
        printf '{\n'
        printf '  "element": "%s",\n' "$(_adv_json_esc "$ADV_OUT_ELEMENT")"
        printf '  "element_name": "%s",\n' "$(_adv_json_esc "$ADV_OUT_ELEMENT_NAME")"
        printf '  "material_class": "%s",\n' "$(_adv_json_esc "$ADV_OUT_MATERIAL_CLASS")"
        printf '  "calculations": [\n'
        local i
        for ((i=0; i<ADV_OVERVIEW_COUNT; i++)); do
            printf '    {\n'
            printf '      "id": "%s",\n' "$(_adv_json_esc "${ADV_OVERVIEW_CALC_ID[i]}")"
            printf '      "label": "%s",\n' "$(_adv_json_esc "${ADV_OVERVIEW_CALC_LABEL[i]}")"
            printf '      "top_profile": "%s",\n' "$(_adv_json_esc "${ADV_OVERVIEW_PROF[i]}")"
            printf '      "top_profile_label": "%s",\n' "$(_adv_json_esc "${ADV_OVERVIEW_PROF_LABEL[i]}")"
            printf '      "top_family": "%s",\n' "$(_adv_json_esc "${ADV_OVERVIEW_FAM[i]}")"
            printf '      "top_xc": "%s",\n' "$(_adv_json_esc "${ADV_OVERVIEW_XC[i]}")"
            printf '      "rationale": "%s"\n' "$(_adv_json_esc "${ADV_OVERVIEW_RATIONALE[i]}")"
            if [ $((i + 1)) -lt "$ADV_OVERVIEW_COUNT" ]; then
                printf '    },\n'
            else
                printf '    }\n'
            fi
        done
        printf '  ]\n'
        printf '}\n'
        return 0
    fi

    printf '{\n'
    printf '  "element": "%s",\n' "$(_adv_json_esc "$ADV_OUT_ELEMENT")"
    printf '  "element_name": "%s",\n' "$(_adv_json_esc "$ADV_OUT_ELEMENT_NAME")"
    printf '  "material_class": "%s",\n' "$(_adv_json_esc "$ADV_OUT_MATERIAL_CLASS")"
    printf '  "calculation": "%s",\n' "$(_adv_json_esc "$ADV_OUT_CALCULATION")"
    printf '  "code": "%s",\n' "$(_adv_json_esc "$ADV_OUT_CODE")"

    # Recommendations
    printf '  "recommendations": [\n'
    local i
    for ((i=0; i<ADV_OUT_COUNT; i++)); do
        printf '    {\n'
        printf '      "rank": %d,\n' "${ADV_OUT_RANK[i]}"
        printf '      "score": %d,\n' "${ADV_OUT_SCORE[i]}"
        printf '      "profile": "%s",\n' "$(_adv_json_esc "${ADV_OUT_PROFILE[i]}")"
        printf '      "profile_label": "%s",\n' "$(_adv_json_esc "${ADV_OUT_PROFILE_LABEL[i]}")"
        printf '      "family": "%s",\n' "$(_adv_json_esc "${ADV_OUT_FAMILY[i]}")"
        printf '      "xc": "%s",\n' "$(_adv_json_esc "${ADV_OUT_XC[i]}")"
        printf '      "engine": "%s",\n' "$(_adv_json_esc "${ADV_OUT_ENGINE[i]}")"
        printf '      "engine_label": "%s",\n' "$(_adv_json_esc "${ADV_OUT_ENGINE_LABEL[i]}")"
        printf '      "format": "%s",\n' "$(_adv_json_esc "${ADV_OUT_FORMAT[i]}")"
        printf '      "why": "%s",\n' "$(_adv_json_esc "${ADV_OUT_WHY[i]}")"

        # caveats array
        printf '      "caveats": ['
        if [ -n "${ADV_OUT_CAVEATS[i]}" ]; then
            local first_c=1 c_line
            while IFS= read -r c_line; do
                [ -z "$c_line" ] && continue
                if [ "$first_c" -eq 1 ]; then
                    printf '"%s"' "$(_adv_json_esc "$c_line")"
                    first_c=0
                else
                    printf ', "%s"' "$(_adv_json_esc "$c_line")"
                fi
            done < <(printf '%b' "${ADV_OUT_CAVEATS[i]}")
        fi
        printf '],\n'

        # cutoff object (if available)
        if [ -n "${ADV_OUT_CUTOFF_VAL[i]}" ]; then
            printf '      "cutoff": {\n'
            printf '        "value": %s,\n' "${ADV_OUT_CUTOFF_VAL[i]}"
            printf '        "unit": "%s",\n' "$(_adv_json_esc "${ADV_OUT_CUTOFF_UNIT[i]}")"
            printf '        "source": "%s"\n' "$(_adv_json_esc "${ADV_OUT_CUTOFF_SOURCE[i]}")"
            printf '      },\n'
        fi

        # citations
        printf '      "citations": [\n'
        printf '        { "kind": "library", "name": "%s", "doi": "%s" },\n' \
            "$(_adv_json_esc "${ADV_OUT_LIB_NAME[i]}")" \
            "$(_adv_json_esc "${ADV_OUT_LIB_DOI[i]}")"
        printf '        { "kind": "engine", "name": "%s", "doi": "%s" }\n' \
            "$(_adv_json_esc "${ADV_OUT_ENG_NAME[i]}")" \
            "$(_adv_json_esc "${ADV_OUT_ENG_DOI[i]}")"
        printf '      ],\n'

        # cli_command
        printf '      "cli_command": "%s"\n' "$(_adv_json_esc "${ADV_OUT_CLI[i]}")"

        if [ $((i + 1)) -lt "$ADV_OUT_COUNT" ]; then
            printf '    },\n'
        else
            printf '    }\n'
        fi
    done
    printf '  ],\n'

    # Avoid list
    printf '  "avoid": [\n'
    for ((i=0; i<ADV_OUT_AVOID_COUNT; i++)); do
        printf '    {\n'
        printf '      "what": "%s",\n' "$(_adv_json_esc "${ADV_OUT_AVOID_WHAT[i]}")"
        printf '      "why": "%s"\n' "$(_adv_json_esc "${ADV_OUT_AVOID_WHY[i]}")"
        if [ $((i + 1)) -lt "$ADV_OUT_AVOID_COUNT" ]; then
            printf '    },\n'
        else
            printf '    }\n'
        fi
    done
    printf '  ],\n'

    # Related list
    printf '  "related": [\n'
    for ((i=0; i<ADV_OUT_RELATED_COUNT; i++)); do
        printf '    {\n'
        printf '      "label": "%s",\n' "$(_adv_json_esc "${ADV_OUT_RELATED_LABEL[i]}")"
        printf '      "cli": "%s"\n' "$(_adv_json_esc "${ADV_OUT_RELATED_CLI[i]}")"
        if [ $((i + 1)) -lt "$ADV_OUT_RELATED_COUNT" ]; then
            printf '    },\n'
        else
            printf '    }\n'
        fi
    done
    printf '  ]\n'
    printf '}\n'
}

# ---------------------------------------------------------------------------
# advise_top_one <element> <calculation>
#
# Return the highest-ranked profile, family, xc as tab-separated values.
# ---------------------------------------------------------------------------
advise_top_one() {
    local sym=$1 calc=$2
    advise_for "$sym" "$calc" >/dev/null 2>&1 || return 1
    if [ "${ADV_OUT_COUNT:-0}" -gt 0 ]; then
        printf '%s\t%s\t%s\n' "${ADV_OUT_PROFILE[0]}" "${ADV_OUT_FAMILY[0]}" "${ADV_OUT_XC[0]}"
        return 0
    fi
    return 1
}
