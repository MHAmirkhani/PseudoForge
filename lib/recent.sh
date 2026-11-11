# shellcheck shell=bash
# ---------------------------------------------------------------------------
# recent.sh -- list recently added files to the store
#
# Shows the N most recently added files, most recent first, with date,
# filename, profile, family, and functional.
# ---------------------------------------------------------------------------

declare -ga RECENT_OUT_DATE=()
declare -ga RECENT_OUT_FILENAME=()
declare -ga RECENT_OUT_ELEMENT=()
declare -ga RECENT_OUT_XC=()
declare -ga RECENT_OUT_FAMILY=()
declare -ga RECENT_OUT_PROFILE=()
declare -ga RECENT_OUT_ID=()
declare -ga RECENT_OUT_PATH=()

_recent_find_native_dir() {
    if [ -n "${PF_NATIVE_DIR:-}" ] && [ "$PF_NATIVE_DIR" != /var/lib/pseudoforge/native ]; then
        printf '%s\n' "$PF_NATIVE_DIR"
        return 0
    fi
    local cand
    for cand in "${PF_NATIVE_DIR:-}" "/var/lib/pseudoforge/native" "$HOME/pf-native" "$HOME/pf-var/native" "/tmp/pseudoforge-local/native"; do
        if [ -n "$cand" ] && [ -d "$cand" ]; then
            printf '%s\n' "$cand"
            return 0
        fi
    done
    printf '%s\n' "${PF_NATIVE_DIR:-/var/lib/pseudoforge/native}"
}

_recent_json_esc() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' -e 's/\r//g' -e ':a;N;$!ba;s/\n/\\n/g'
}

recent_files() {
    local count=${1:-10}
    # The caller chooses the default; an explicitly invalid count is an error.
    if [[ "$count" = *[!0-9]* ]] || ! [ "$count" -gt 0 ] 2>/dev/null; then
        error "count must be a positive integer"
        return 1
    fi

    RECENT_OUT_DATE=()
    RECENT_OUT_FILENAME=()
    RECENT_OUT_ELEMENT=()
    RECENT_OUT_XC=()
    RECENT_OUT_FAMILY=()
    RECENT_OUT_PROFILE=()
    RECENT_OUT_ID=()
    RECENT_OUT_PATH=()

    local store_dir idx
    store_dir=$(_recent_find_native_dir)
    idx="$store_dir/index.tsv"

    [ -f "$idx" ] || return 0

    # Stat all indexed formats and skip files removed since the last scan.
    while IFS=$'\t' read -r _date _fn _el _xc _fam _prof _id _path; do
        [ -n "$_date" ] || continue
        RECENT_OUT_DATE+=("$_date")
        RECENT_OUT_FILENAME+=("$_fn")
        RECENT_OUT_ELEMENT+=("$_el")
        RECENT_OUT_XC+=("$_xc")
        RECENT_OUT_FAMILY+=("$_fam")
        RECENT_OUT_PROFILE+=("$_prof")
        RECENT_OUT_ID+=("$_id")
        RECENT_OUT_PATH+=("$_path")
    done < <(
        find "$store_dir" -type f -printf '%T@\t%TY-%Tm-%Td\t%P\n' 2>/dev/null |
            awk -F'\t' '
                BEGIN { OFS = FS }
                FILENAME == ARGV[1] {
                    if ($1 !~ /^#/ && $1 !~ /_rejected_/ && $10 !~ /(^|\/)\.?rejected\// && $10 != "") {
                        id[$10] = $1; el[$10] = $2; xc[$10] = $3; fam[$10] = $4; prof[$10] = $8
                    }
                    next
                }
                $3 in id {
                    path = $3; name = path; sub(/.*\//, "", name); sub(/\.gz$/, "", name)
                    print $1, $2, name, el[path], xc[path], fam[path], prof[path], id[path], path
                }
            ' "$idx" - | sort -t $'\t' -k1,1nr -k8,8 | sed -n "1,${count}p" | cut -f2-
    )

    return 0
}

recent_render_human() {
    local count=${1:-${#RECENT_OUT_FILENAME[@]}}
    local total=${#RECENT_OUT_FILENAME[@]}

    if [ "$total" -eq 0 ]; then
        printf 'No files found in the store.\n'
        return 0
    fi

    printf '%d most recent files in the store:\n\n' "$total"

    local i d fn el xc fam prof
    for (( i=0; i<total; i++ )); do
        d=${RECENT_OUT_DATE[i]}
        fn=${RECENT_OUT_FILENAME[i]}
        prof=${RECENT_OUT_PROFILE[i]:-—}
        fam=${RECENT_OUT_FAMILY[i]:-—}
        xc=${RECENT_OUT_XC[i]:-—}
        printf '%-12s %-24s %-12s %-5s %-8s\n' "$d" "$fn" "$prof" "${fam^^}" "${xc^^}"
    done
}

recent_render_json() {
    local total=${#RECENT_OUT_FILENAME[@]}
    if [ "$total" -eq 0 ]; then
        printf '[]\n'
        return 0
    fi
    printf '[\n'
    local i
    for (( i=0; i<total; i++ )); do
        printf '  {\n'
        printf '    "date": "%s",\n' "$(_recent_json_esc "${RECENT_OUT_DATE[i]}")"
        printf '    "filename": "%s",\n' "$(_recent_json_esc "${RECENT_OUT_FILENAME[i]}")"
        printf '    "element": "%s",\n' "$(_recent_json_esc "${RECENT_OUT_ELEMENT[i]}")"
        printf '    "xc": "%s",\n' "$(_recent_json_esc "${RECENT_OUT_XC[i]}")"
        printf '    "family": "%s",\n' "$(_recent_json_esc "${RECENT_OUT_FAMILY[i]}")"
        printf '    "profile": "%s",\n' "$(_recent_json_esc "${RECENT_OUT_PROFILE[i]}")"
        printf '    "id": "%s",\n' "$(_recent_json_esc "${RECENT_OUT_ID[i]}")"
        printf '    "path": "%s"\n' "$(_recent_json_esc "${RECENT_OUT_PATH[i]}")"
        if [ "$i" -lt $((total - 1)) ]; then
            printf '  },\n'
        else
            printf '  }\n'
        fi
    done
    printf ']\n'
}
