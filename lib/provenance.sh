# shellcheck shell=bash
# ---------------------------------------------------------------------------
# provenance.sh -- show full provenance record for native files
#
# Answers "where did a file come from?" with engine version, binary SHA256,
# build date, profile, upstream source, generation command, size, and SHA256.
# ---------------------------------------------------------------------------

declare -g PROV_OUT_ID=""
declare -g PROV_OUT_ELEMENT=""
declare -g PROV_OUT_ELEMENT_NAME=""
declare -g PROV_OUT_Z=""
declare -g PROV_OUT_FAMILY=""
declare -g PROV_OUT_FUNCTIONAL=""
declare -g PROV_OUT_RELATIVITY=""
declare -g PROV_OUT_PROFILE=""
declare -g PROV_OUT_ENGINE=""
declare -g PROV_OUT_ENGINE_LABEL=""
declare -g PROV_OUT_ENGINE_VERSION=""
declare -g PROV_OUT_BINARY_SHA256=""
declare -g PROV_OUT_BUILD_DATE=""
declare -g PROV_OUT_SOURCE=""
declare -g PROV_OUT_GENERATED_BY=""
declare -g PROV_OUT_FORMAT=""
declare -g PROV_OUT_SIZE=""
declare -g PROV_OUT_SHA256=""
declare -g PROV_OUT_RAW=""

_prov_find_native_dir() {
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

_prov_json_esc() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' -e 's/\r//g' -e ':a;N;$!ba;s/\n/\\n/g'
}

provenance_for() {
    local q=${1:-}
    [ -n "$q" ] || { error "provenance: file id required"; return 1; }

    pf_elements_load 2>/dev/null || true
    pf_profiles_load 2>/dev/null || true
    pf_engines_load 2>/dev/null || true
    pf_metadata_load 2>/dev/null || true

    local store_dir
    store_dir=$(_prov_find_native_dir)
    local idx="$store_dir/index.tsv"
    [ -f "$idx" ] || { error "no native index found at $idx"; return 1; }

    # Find matching line in index.tsv
    local line=""
    # 1. Exact match on id ($1)
    line=$(awk -F'\t' -v q="$q" '$1 == q { print; exit }' "$idx")

    # 2. Exact match on path ($10)
    if [ -z "$line" ]; then
        line=$(awk -F'\t' -v q="$q" '$10 == q { print; exit }' "$idx")
    fi

    # 3. Match basename of path ($10)
    if [ -z "$line" ]; then
        line=$(awk -F'\t' -v q="$q" '{
            n = split($10, parts, "/");
            base = parts[n];
            sub(/\.gz$/, "", base);
            q_clean = q;
            sub(/\.gz$/, "", q_clean);
            if (base == q_clean || parts[n] == q) { print; exit }
        }' "$idx")
    fi

    # 4. Fuzzy match normalized without -n- (e.g. Si.pbe-n-oncv.UPF -> Si.pbe-oncv.UPF)
    if [ -z "$line" ]; then
        local q_norm
        q_norm=${q//-n-/-}
        line=$(awk -F'\t' -v q="$q_norm" '{
            n = split($10, parts, "/");
            base = parts[n];
            sub(/\.gz$/, "", base);
            q_clean = q;
            sub(/\.gz$/, "", q_clean);
            if (base == q_clean || parts[n] == q) { print; exit }
        }' "$idx")
    fi

    # 5. Fallback substring match
    if [ -z "$line" ]; then
        local q_sub
        q_sub=${q//-n-/}
        q_sub=${q_sub%.UPF}
        q_sub=${q_sub%.upf}
        line=$(awk -F'\t' -v q="$q_sub" 'index($1, q) > 0 || index($10, q) > 0 { print; exit }' "$idx")
    fi

    [ -n "$line" ] || { error "no native file matching '$q'"; return 1; }

    # Parse index line
    local _id _el _xc _fam _rel _eng _fmt _prof _enc _path _size _sha _prov
    IFS=$'\t' read -r _id _el _xc _fam _rel _eng _fmt _prof _enc _path _size _sha _prov <<< "$line"

    PROV_OUT_ID=$q
    PROV_OUT_ELEMENT=$_el
    PROV_OUT_ELEMENT_NAME=${EL_NAME[$_el]:-$_el}
    PROV_OUT_Z=${EL_Z[$_el]:-}
    PROV_OUT_FAMILY=$(printf '%s' "$_fam" | tr '[:lower:]' '[:upper:]')
    PROV_OUT_FUNCTIONAL="$(printf '%s' "$_xc" | tr '[:lower:]' '[:upper:]') (native)"
    PROV_OUT_RELATIVITY=$_rel
    PROV_OUT_PROFILE=$_prof
    PROV_OUT_FORMAT=$_fmt
    PROV_OUT_SIZE=${_size:-0}
    PROV_OUT_SHA256=$_sha

    # Resolve ancestor PROVENANCE.txt
    local prov_file=""
    if [ -n "$_path" ]; then
        local cur_dir
        cur_dir="$store_dir/$(dirname "$_path")"
        while [ -n "$cur_dir" ] && [ "$cur_dir" != "/" ] && [ "$cur_dir" != "$store_dir" ]; do
            if [ -f "$cur_dir/PROVENANCE.txt" ]; then
                prov_file="$cur_dir/PROVENANCE.txt"
                break
            fi
            cur_dir=$(dirname "$cur_dir")
        done
        if [ -z "$prov_file" ] && [ -f "$store_dir/PROVENANCE.txt" ]; then
            prov_file="$store_dir/PROVENANCE.txt"
        fi
    fi

    PROV_OUT_RAW=""
    local eng_label="" eng_ver="" eng_bld="" bld_date="" prov_src=""
    if [ -n "$prov_file" ] && [ -f "$prov_file" ]; then
        PROV_OUT_RAW=$(cat "$prov_file")
        while IFS= read -r pline; do
            case "$pline" in
                "# Generated "*)
                    bld_date=${pline#"# Generated "} ;;
                engine.label=*)
                    eng_label=${pline#engine.label=} ;;
                engine.version=*)
                    eng_ver=${pline#engine.version=} ;;
                engine.build=*)
                    eng_bld=${pline#engine.build=} ;;
                source=*)
                    prov_src=${pline#source=} ;;
            esac
        done < "$prov_file"

        # Check table at the bottom of PROVENANCE.txt for specific file status/provenance
        local tbl_prov
        tbl_prov=$(awk -F'\t' -v el="$_el" '$1 == el { print $3; exit }' "$prov_file")
        if [ -n "$tbl_prov" ]; then
            prov_src="$tbl_prov"
        fi
    fi

    # Fallbacks and refinements
    [ -n "$eng_label" ] || eng_label=${ENG_LABEL[$_eng]:-${PROF_ENGINE[$_prof]:-$_eng}}
    [ -n "$eng_ver" ] || eng_ver=${ENG_VERSION[$_eng]:-""}
    PROV_OUT_ENGINE_LABEL=$eng_label
    PROV_OUT_ENGINE_VERSION=$eng_ver
    PROV_OUT_ENGINE="$eng_label${eng_ver:+ }$eng_ver"
    PROV_OUT_BINARY_SHA256=${eng_bld:-unrecorded}

    # Format build date
    if [ -n "$bld_date" ]; then
        local d_part t_part tz_part
        read -r d_part t_part tz_part <<< "$bld_date"
        if [ -n "$d_part" ] && [ -n "$t_part" ]; then
            PROV_OUT_BUILD_DATE="${d_part}T${t_part}${tz_part:+Z}"
        else
            PROV_OUT_BUILD_DATE=$bld_date
        fi
    else
        PROV_OUT_BUILD_DATE="unrecorded"
    fi

    # Source formatting
    local prof_lbl=${PROF_LABEL[$_prof]:-$_prof}
    if [ "$prov_src" = "library" ]; then
        PROV_OUT_SOURCE="library ($prof_lbl)"
    elif [ -n "$prov_src" ]; then
        PROV_OUT_SOURCE="$prov_src"
    else
        PROV_OUT_SOURCE="library ($prof_lbl)"
    fi

    # Generated by command
    local el_lower
    el_lower=$(printf '%s' "$_el" | tr '[:upper:]' '[:lower:]')
    PROV_OUT_GENERATED_BY="pseudoforge generate -e $_el -t $_fam -p $_prof -x $_xc -r $_rel -o ./${el_lower}-run"

    return 0
}

provenance_render_human() {
    printf '%s\n' "$PROV_OUT_ID"
    printf '%s\n' "─────────────────────────────────────────────"
    printf '%-15s%s\n' "Element" "$PROV_OUT_ELEMENT ($PROV_OUT_ELEMENT_NAME, Z=$PROV_OUT_Z)"
    printf '%-15s%s\n' "Family" "$PROV_OUT_FAMILY"
    printf '%-15s%s\n' "Functional" "$PROV_OUT_FUNCTIONAL"
    printf '%-15s%s\n' "Relativity" "$PROV_OUT_RELATIVITY"
    printf '%-15s%s\n' "Profile" "$PROV_OUT_PROFILE"
    printf '%-15s%s\n' "Engine" "$PROV_OUT_ENGINE"
    printf '%-15s%s\n' "Binary SHA256" "$PROV_OUT_BINARY_SHA256"
    printf '%-15s%s\n' "Build date" "$PROV_OUT_BUILD_DATE"
    printf '%-15s%s\n' "Source" "$PROV_OUT_SOURCE"
    printf '%-15s%s \\\n' "Generated by" "pseudoforge generate -e $PROV_OUT_ELEMENT -t $(printf '%s' "$PROV_OUT_FAMILY" | tr '[:upper:]' '[:lower:]') -p $PROV_OUT_PROFILE"
    printf '                   -x %s -r %s -o ./%s-run\n' "$(printf '%s' "$PROV_OUT_FUNCTIONAL" | awk '{print tolower($1)}')" "$PROV_OUT_RELATIVITY" "$(printf '%s' "$PROV_OUT_ELEMENT" | tr '[:upper:]' '[:lower:]')"
    printf '%-15s%s\n' "Format" "$PROV_OUT_FORMAT"
    printf '%-15s%s bytes\n' "Size" "$PROV_OUT_SIZE"
    printf '%-15s%s\n' "SHA256" "$PROV_OUT_SHA256"
}

provenance_render_json() {
    printf '{\n'
    printf '  "id": "%s",\n' "$(_prov_json_esc "$PROV_OUT_ID")"
    printf '  "element": "%s",\n' "$(_prov_json_esc "$PROV_OUT_ELEMENT")"
    printf '  "element_name": "%s",\n' "$(_prov_json_esc "$PROV_OUT_ELEMENT_NAME")"
    printf '  "z": %s,\n' "${PROV_OUT_Z:-0}"
    printf '  "family": "%s",\n' "$(_prov_json_esc "$PROV_OUT_FAMILY")"
    printf '  "functional": "%s",\n' "$(_prov_json_esc "$PROV_OUT_FUNCTIONAL")"
    printf '  "relativity": "%s",\n' "$(_prov_json_esc "$PROV_OUT_RELATIVITY")"
    printf '  "profile": "%s",\n' "$(_prov_json_esc "$PROV_OUT_PROFILE")"
    printf '  "engine": "%s",\n' "$(_prov_json_esc "$PROV_OUT_ENGINE")"
    printf '  "binary_sha256": "%s",\n' "$(_prov_json_esc "$PROV_OUT_BINARY_SHA256")"
    printf '  "build_date": "%s",\n' "$(_prov_json_esc "$PROV_OUT_BUILD_DATE")"
    printf '  "source": "%s",\n' "$(_prov_json_esc "$PROV_OUT_SOURCE")"
    printf '  "generated_by": "%s",\n' "$(_prov_json_esc "$PROV_OUT_GENERATED_BY")"
    printf '  "format": "%s",\n' "$(_prov_json_esc "$PROV_OUT_FORMAT")"
    printf '  "size": %s,\n' "${PROV_OUT_SIZE:-0}"
    printf '  "sha256": "%s",\n' "$(_prov_json_esc "$PROV_OUT_SHA256")"
    printf '  "raw": "%s"\n' "$(_prov_json_esc "$PROV_OUT_RAW")"
    printf '}\n'
}
