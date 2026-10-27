# shellcheck shell=bash
# ---------------------------------------------------------------------------
# element.sh -- list store holdings and available profiles for an element
#
# Answers "what exists for element X?" with all native files grouped by
# family and functional, file sizes, engines, and commands to generate missing ones.
# ---------------------------------------------------------------------------

declare -g EL_OUT_SYMBOL=""
declare -g EL_OUT_NAME=""
declare -g EL_OUT_Z=""
declare -gi EL_OUT_TOTAL=0

declare -ga EL_OUT_FAMILIES=()
declare -gA EL_OUT_FAM_LABEL=()
declare -gA EL_OUT_FAM_COUNT=()

# Per-file arrays
declare -gi EL_FILE_COUNT=0
declare -ga EL_FILE_ID=()
declare -ga EL_FILE_NAME=()
declare -ga EL_FILE_FAM=()
declare -ga EL_FILE_XC=()
declare -ga EL_FILE_REL=()
declare -ga EL_FILE_ENG=()
declare -ga EL_FILE_FMT=()
declare -ga EL_FILE_SIZE=()
declare -ga EL_FILE_PATH=()

# Uncovered / not available
declare -gi EL_UNAVAIL_COUNT=0
declare -ga EL_UNAVAIL_PROF=()
declare -ga EL_UNAVAIL_FAM=()
declare -ga EL_UNAVAIL_XC=()
declare -ga EL_UNAVAIL_CMD=()

_el_find_native_dir() {
    if [ -n "${PF_NATIVE_DIR:-}" ] && [ -f "$PF_NATIVE_DIR/index.tsv" ]; then
        printf '%s\n' "$PF_NATIVE_DIR"
        return 0
    fi
    local cand
    for cand in "${PF_NATIVE_DIR:-}" "/var/lib/pseudoforge/native" "$HOME/pf-native" "$HOME/pf-var/native" "/tmp/pseudoforge-local/native"; do
        if [ -n "$cand" ] && [ -f "$cand/index.tsv" ]; then
            printf '%s\n' "$cand"
            return 0
        fi
    done
    printf '%s\n' "${PF_NATIVE_DIR:-/var/lib/pseudoforge/native}"
}

_el_json_esc() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' -e 's/\r//g' -e ':a;N;$!ba;s/\n/\\n/g'
}

element_summary_for() {
    local sym=${1:-}
    [ -n "$sym" ] || { error "element: symbol required"; return 1; }

    pf_elements_load 2>/dev/null || true
    pf_profiles_load 2>/dev/null || true
    pf_engines_load 2>/dev/null || true
    pf_metadata_load 2>/dev/null || true

    # Normalize symbol
    local norm="" s
    for s in "${EL_ORDER[@]}"; do
        if [ "${s,,}" = "${sym,,}" ]; then
            norm=$s
            break
        fi
    done
    [ -n "$norm" ] || { error "unknown element: $sym"; return 1; }
    sym=$norm

    EL_OUT_SYMBOL=$sym
    EL_OUT_NAME=${EL_NAME[$sym]:-$sym}
    EL_OUT_Z=${EL_Z[$sym]:-0}
    EL_OUT_TOTAL=0
    EL_FILE_COUNT=0
    EL_UNAVAIL_COUNT=0
    EL_OUT_FAMILIES=("nc" "paw" "us")
    EL_OUT_FAM_LABEL[nc]="norm-conserving"
    EL_OUT_FAM_LABEL[paw]="projector augmented-wave"
    EL_OUT_FAM_LABEL[us]="ultrasoft"
    EL_OUT_FAM_COUNT[nc]=0
    EL_OUT_FAM_COUNT[paw]=0
    EL_OUT_FAM_COUNT[us]=0

    EL_FILE_ID=()
    EL_FILE_NAME=()
    EL_FILE_FAM=()
    EL_FILE_XC=()
    EL_FILE_REL=()
    EL_FILE_ENG=()
    EL_FILE_FMT=()
    EL_FILE_SIZE=()
    EL_FILE_PATH=()

    local store_dir
    store_dir=$(_el_find_native_dir)
    local idx="$store_dir/index.tsv"

    declare -A seen_configs
    if [ -f "$idx" ]; then
        while IFS=$'\t' read -r _id _el _xc _fam _rel _eng _fmt _prof _enc _path _size _sha _prov; do
            [ -n "$_id" ] || continue
            local fam_lower=${_fam,,}
            local fname
            fname=$(basename "${_path:-$_id}")
            fname=${fname%.gz}

            EL_FILE_ID+=("$_id")
            EL_FILE_NAME+=("$fname")
            EL_FILE_FAM+=("$fam_lower")
            EL_FILE_XC+=("${_xc^^}")
            EL_FILE_REL+=("$_rel")
            local elbl=${ENG_LABEL[$_eng]:-$_eng}
            local ever=${ENG_VERSION[$_eng]:-}
            EL_FILE_ENG+=("$elbl${ever:+ }$ever")
            EL_FILE_FMT+=("$_fmt")
            EL_FILE_SIZE+=("${_size:-0}")
            EL_FILE_PATH+=("${_path:-}")

            EL_OUT_FAM_COUNT[$fam_lower]=$(( ${EL_OUT_FAM_COUNT[$fam_lower]:-0} + 1 ))
            EL_OUT_TOTAL=$(( EL_OUT_TOTAL + 1 ))
            seen_configs["$_prof|$_fam|$_xc"]=1
            EL_FILE_COUNT=$(( EL_FILE_COUNT + 1 ))
        done < <(awk -F'\t' -v s="$sym" '$2 == s && $1 !~ /_rejected_/ && $1 !~ /^#/' "$idx")
    fi

    # Determine what is not available in the store
    EL_UNAVAIL_PROF=()
    EL_UNAVAIL_FAM=()
    EL_UNAVAIL_XC=()
    EL_UNAVAIL_CMD=()

    local check_profs=("psl-high" "pseudodojo" "gbrv" "sssp")
    local cp cf cx
    for cp in "${check_profs[@]}"; do
        for cf in ${PROF_FAMILIES[$cp]:-}; do
            for cx in pbe pbesol; do
                if [ -z "${seen_configs["$cp|$cf|$cx"]:-}" ]; then
                    EL_UNAVAIL_PROF+=("$cp")
                    EL_UNAVAIL_FAM+=("${cf^^}")
                    EL_UNAVAIL_XC+=("${cx^^}")
                    EL_UNAVAIL_CMD+=("pseudoforge generate -e $sym -t ${cf,,} -p $cp -x ${cx,,}")
                    EL_UNAVAIL_COUNT=$(( EL_UNAVAIL_COUNT + 1 ))
                    break 2
                fi
            done
        done
    done

    return 0
}

element_render_human() {
    printf '%s (%s, Z=%s)  —  %d files in the store\n' \
        "$EL_OUT_SYMBOL" "$EL_OUT_NAME" "$EL_OUT_Z" "$EL_OUT_TOTAL"

    local fam
    for fam in "${EL_OUT_FAMILIES[@]}"; do
        local count=${EL_OUT_FAM_COUNT[$fam]:-0}
        [ "$count" -gt 0 ] || continue

        printf '\n%s — %s\n' "${fam^^}" "${EL_OUT_FAM_LABEL[$fam]:-$fam}"
        local i
        for ((i=0; i<EL_FILE_COUNT; i++)); do
            [ "${EL_FILE_FAM[i]}" = "$fam" ] || continue
            local sz_kb=$(( (${EL_FILE_SIZE[i]} + 1023) / 1024 ))
            local conf="${EL_FILE_XC[i]}, ${EL_FILE_REL[i]}"
            printf '  %-15s %-28s %-20s %4d KB\n' \
                "$conf" "${EL_FILE_NAME[i]}" "${EL_FILE_ENG[i]}" "$sz_kb"
        done
    done

    if [ "$EL_UNAVAIL_COUNT" -gt 0 ]; then
        printf '\nNot available in the store:\n'
        local u
        for ((u=0; u<EL_UNAVAIL_COUNT; u++)); do
            printf '  %-10s %-4s %-4s  —  generate with:\n' \
                "${EL_UNAVAIL_PROF[u]}" "${EL_UNAVAIL_FAM[u]}" "${EL_UNAVAIL_XC[u]}"
            printf '    %s\n' "${EL_UNAVAIL_CMD[u]}"
        done
    fi
}

element_render_json() {
    printf '{\n'
    printf '  "symbol": "%s",\n' "$(_el_json_esc "$EL_OUT_SYMBOL")"
    printf '  "name": "%s",\n' "$(_el_json_esc "$EL_OUT_NAME")"
    printf '  "z": %s,\n' "${EL_OUT_Z:-0}"
    printf '  "total_files": %d,\n' "$EL_OUT_TOTAL"
    printf '  "families": {\n'

    local f_idx=0
    local fam
    for fam in "${EL_OUT_FAMILIES[@]}"; do
        f_idx=$(( f_idx + 1 ))
        printf '    "%s": [\n' "$fam"
        local first=1
        local i
        for ((i=0; i<EL_FILE_COUNT; i++)); do
            [ "${EL_FILE_FAM[i]}" = "$fam" ] || continue
            [ "$first" -eq 1 ] || printf ',\n'
            first=0
            local sz_kb=$(( (${EL_FILE_SIZE[i]} + 1023) / 1024 ))
            printf '      {\n'
            printf '        "id": "%s",\n' "$(_el_json_esc "${EL_FILE_ID[i]}")"
            printf '        "file": "%s",\n' "$(_el_json_esc "${EL_FILE_NAME[i]}")"
            printf '        "xc": "%s",\n' "$(_el_json_esc "${EL_FILE_XC[i]}")"
            printf '        "relativity": "%s",\n' "$(_el_json_esc "${EL_FILE_REL[i]}")"
            printf '        "engine": "%s",\n' "$(_el_json_esc "${EL_FILE_ENG[i]}")"
            printf '        "format": "%s",\n' "$(_el_json_esc "${EL_FILE_FMT[i]}")"
            printf '        "size_kb": %d,\n' "$sz_kb"
            printf '        "path": "%s"\n' "$(_el_json_esc "${EL_FILE_PATH[i]}")"
            printf '      }'
        done
        printf '\n    ]'
        [ "$f_idx" -lt "${#EL_OUT_FAMILIES[@]}" ] && printf ',\n' || printf '\n'
    done
    printf '  },\n'

    printf '  "not_available": [\n'
    local u
    for ((u=0; u<EL_UNAVAIL_COUNT; u++)); do
        printf '    {\n'
        printf '      "profile": "%s",\n' "$(_el_json_esc "${EL_UNAVAIL_PROF[u]}")"
        printf '      "family": "%s",\n' "$(_el_json_esc "${EL_UNAVAIL_FAM[u]}")"
        printf '      "xc": "%s",\n' "$(_el_json_esc "${EL_UNAVAIL_XC[u]}")"
        printf '      "command": "%s"\n' "$(_el_json_esc "${EL_UNAVAIL_CMD[u]}")"
        if [ $((u + 1)) -lt "$EL_UNAVAIL_COUNT" ]; then
            printf '    },\n'
        else
            printf '    }\n'
        fi
    done
    printf '  ]\n'
    printf '}\n'
}
