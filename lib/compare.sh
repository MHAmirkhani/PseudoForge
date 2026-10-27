# shellcheck shell=bash
# ---------------------------------------------------------------------------
# compare.sh -- diff two pseudopotentials across all dimensions
#
# Answers "what differs between these two pseudopotentials?" across physics,
# generators, formats, and numerical representations.
# ---------------------------------------------------------------------------

declare -g CMP_ID_A="" CMP_EL_A="" CMP_ENG_A="" CMP_XC_A="" CMP_FAM_A="" CMP_REL_A="" CMP_FMT_A="" CMP_SIZE_A=0 CMP_SHA_A="" CMP_CUTOFF_A="" CMP_CUTOFF_A_JSON="{}" CMP_PATH_A=""
declare -g CMP_ID_B="" CMP_EL_B="" CMP_ENG_B="" CMP_XC_B="" CMP_FAM_B="" CMP_REL_B="" CMP_FMT_B="" CMP_SIZE_B=0 CMP_SHA_B="" CMP_CUTOFF_B="" CMP_CUTOFF_B_JSON="{}" CMP_PATH_B=""
declare -g CMP_DELTA_SIZE=0
declare -g CMP_SHA_EQUAL=false
declare -g CMP_FAM_CHANGED=false
declare -g CMP_XC_CHANGED=false
declare -g CMP_REL_CHANGED=false
declare -g CMP_ENG_CHANGED=false
declare -g CMP_FMT_CHANGED=false
declare -ga CMP_WARNINGS=()

_compare_find_native_dir() {
    if [ -n "${PF_NATIVE_DIR:-}" ] && [ -d "$PF_NATIVE_DIR" ]; then
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

# Resolve one target (id, path, or basename) into metadata fields
# _compare_resolve_side <target> <side: A|B>
_compare_resolve_side() {
    local q=${1:-} side=${2:-A}
    [ -n "$q" ] || return 1

    local id="" el="" xc="" fam="" rel="" eng="" fmt="" size=0 sha="" path=""
    local store_dir idx line=""

    store_dir=$(_compare_find_native_dir)
    idx="$store_dir/index.tsv"

    # 1. Check if index exists and has matching line
    if [ -f "$idx" ]; then
        # Exact match on id ($1)
        line=$(awk -F'\t' -v q="$q" '$1 == q { print; exit }' "$idx")
        # Match on path ($10)
        [ -z "$line" ] && line=$(awk -F'\t' -v q="$q" '$10 == q { print; exit }' "$idx")
        # Match on basename
        if [ -z "$line" ]; then
            line=$(awk -F'\t' -v q="$q" '{
                n = split($10, parts, "/");
                base = parts[n];
                sub(/\.gz$/, "", base);
                q_clean = q;
                sub(/\.gz$/, "", q_clean);
                if (base == q_clean || parts[n] == q || parts[n] == (q ".gz")) { print; exit }
            }' "$idx")
        fi
    fi

    if [ -n "$line" ]; then
        id=$(printf '%s' "$line" | cut -f1)
        el=$(printf '%s' "$line" | cut -f2)
        xc=$(printf '%s' "$line" | cut -f3)
        fam=$(printf '%s' "$line" | cut -f4)
        rel=$(printf '%s' "$line" | cut -f5)
        eng=$(printf '%s' "$line" | cut -f6)
        fmt=$(printf '%s' "$line" | cut -f7)
        local relpath; relpath=$(printf '%s' "$line" | cut -f10)
        path="$store_dir/$relpath"
        size=$(printf '%s' "$line" | cut -f11)
        sha=$(printf '%s' "$line" | cut -f12)
    elif [ -f "$q" ] || [ -f "$store_dir/$q" ]; then
        if [ -f "$q" ]; then path="$q"; else path="$store_dir/$q"; fi
        id=$(basename "$path")
        size=$(stat -c%s "$path" 2>/dev/null || wc -c < "$path" 2>/dev/null || echo 0)
        sha=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
        el=$(upf_get "$path" element 2>/dev/null || true)
        xc=$(upf_get "$path" functional 2>/dev/null || true)
        fam=$(upf_get "$path" type 2>/dev/null || true)
        eng=$(upf_get "$path" author 2>/dev/null || true)
        [ -z "$eng" ] && eng=$(upf_get "$path" generated 2>/dev/null || true)
        rel=$(upf_get "$path" relativistic 2>/dev/null || true)
        fmt=$(upf_format "$path" 2>/dev/null || echo "upf")
    else
        return 1
    fi

    # Lookup cutoffs via SSSP precision
    local cutoff_val="" cutoff_json="{}"
    if [ -n "$el" ]; then
        local sssp_rec sssp_wfc=""
        sssp_rec=$(SSSP_ACCURACY="precision" sssp_entry "$el" "${xc:-pbe}" 2>/dev/null || \
                   SSSP_ACCURACY="precision" sssp_entry "$el" "pbe" 2>/dev/null || true)
        if [ -n "$sssp_rec" ]; then
            sssp_wfc=$(printf '%s' "$sssp_rec" | awk -F'\t' '{print $3}')
            cutoff_val=$(awk -v v="$sssp_wfc" 'BEGIN { if (v == int(v)) print int(v); else print v }')
            if [ -n "$cutoff_val" ]; then
                cutoff_json="{\"sssp_precision\":$cutoff_val}"
            fi
        fi
    fi

    if [ "$side" = "A" ]; then
        CMP_ID_A="$id"; CMP_EL_A="$el"; CMP_XC_A="$xc"; CMP_FAM_A="$fam"
        CMP_REL_A="$rel"; CMP_ENG_A="$eng"; CMP_FMT_A="$fmt"; CMP_SIZE_A="${size:-0}"
        CMP_SHA_A="$sha"; CMP_CUTOFF_A="$cutoff_val"; CMP_CUTOFF_A_JSON="$cutoff_json"; CMP_PATH_A="$path"
    else
        CMP_ID_B="$id"; CMP_EL_B="$el"; CMP_XC_B="$xc"; CMP_FAM_B="$fam"
        CMP_REL_B="$rel"; CMP_ENG_B="$eng"; CMP_FMT_B="$fmt"; CMP_SIZE_B="${size:-0}"
        CMP_SHA_B="$sha"; CMP_CUTOFF_B="$cutoff_val"; CMP_CUTOFF_B_JSON="$cutoff_json"; CMP_PATH_B="$path"
    fi
    return 0
}

compare_for() {
    local a=${1:-} b=${2:-}
    [ -n "$a" ] && [ -n "$b" ] || return 1

    pf_elements_load 2>/dev/null || true
    pf_xc_load 2>/dev/null || true
    pf_profiles_load 2>/dev/null || true
    pf_engines_load 2>/dev/null || true

    _compare_resolve_side "$a" "A" || return 1
    _compare_resolve_side "$b" "B" || return 1

    CMP_DELTA_SIZE=$(( CMP_SIZE_B - CMP_SIZE_A ))
    [ "$CMP_SHA_A" = "$CMP_SHA_B" ] && CMP_SHA_EQUAL=true || CMP_SHA_EQUAL=false
    [ "$CMP_FAM_A" != "$CMP_FAM_B" ] && CMP_FAM_CHANGED=true || CMP_FAM_CHANGED=false
    [ "$CMP_XC_A" != "$CMP_XC_B" ] && CMP_XC_CHANGED=true || CMP_XC_CHANGED=false
    [ "$CMP_REL_A" != "$CMP_REL_B" ] && CMP_REL_CHANGED=true || CMP_REL_CHANGED=false
    [ "$CMP_ENG_A" != "$CMP_ENG_B" ] && CMP_ENG_CHANGED=true || CMP_ENG_CHANGED=false
    [ "$CMP_FMT_A" != "$CMP_FMT_B" ] && CMP_FMT_CHANGED=true || CMP_FMT_CHANGED=false

    CMP_WARNINGS=()
    if [ "$CMP_ENG_CHANGED" = true ] && [ -n "$CMP_ENG_A" ] && [ -n "$CMP_ENG_B" ]; then
        CMP_WARNINGS+=("Switching engine between $CMP_ENG_A and $CMP_ENG_B may change projector indexing.")
    fi
    if [ "$CMP_XC_CHANGED" = true ] && [ -n "$CMP_XC_A" ] && [ -n "$CMP_XC_B" ]; then
        CMP_WARNINGS+=("Exchange-correlation functional changed from $CMP_XC_A to $CMP_XC_B; total energies are not directly comparable.")
    fi
    if [ "$CMP_FAM_CHANGED" = true ] && [ -n "$CMP_FAM_A" ] && [ -n "$CMP_FAM_B" ]; then
        CMP_WARNINGS+=("Pseudopotential family changed from $CMP_FAM_A to $CMP_FAM_B; projector counts and transferability will differ.")
    fi
    if [ "$CMP_EL_A" != "$CMP_EL_B" ] && [ -n "$CMP_EL_A" ] && [ -n "$CMP_EL_B" ]; then
        CMP_WARNINGS+=("Comparing different elements ($CMP_EL_A vs $CMP_EL_B).")
    fi
    if [ "$CMP_REL_CHANGED" = true ] && [ -n "$CMP_REL_A" ] && [ -n "$CMP_REL_B" ]; then
        CMP_WARNINGS+=("Relativity changed from $CMP_REL_A to $CMP_REL_B; spin-orbit splitting and core treatment differ.")
    fi
    if [ "$CMP_FMT_CHANGED" = true ] && [ -n "$CMP_FMT_A" ] && [ -n "$CMP_FMT_B" ]; then
        CMP_WARNINGS+=("Format changed from $CMP_FMT_A to $CMP_FMT_B.")
    fi

    return 0
}

compare_render_json() {
    local warnings_json="[]"
    if [ ${#CMP_WARNINGS[@]} -gt 0 ]; then
        local w_items=() w
        for w in "${CMP_WARNINGS[@]}"; do
            w_items+=("$(http_json_str "$w")")
        done
        warnings_json="[$(IFS=,; echo "${w_items[*]}")]"
    fi

    printf '{\n'
    printf '  "a": { "id": %s, "element": %s, "engine": %s, "xc": %s, "cutoffs": %s },\n' \
        "$(http_json_str "$CMP_ID_A")" \
        "$(http_json_str "$CMP_EL_A")" \
        "$(http_json_str "$CMP_ENG_A")" \
        "$(http_json_str "$CMP_XC_A")" \
        "${CMP_CUTOFF_A_JSON:-{}}"
    printf '  "b": { "id": %s, "element": %s, "engine": %s, "xc": %s, "cutoffs": %s },\n' \
        "$(http_json_str "$CMP_ID_B")" \
        "$(http_json_str "$CMP_EL_B")" \
        "$(http_json_str "$CMP_ENG_B")" \
        "$(http_json_str "$CMP_XC_B")" \
        "${CMP_CUTOFF_B_JSON:-{}}"
    printf '  "diff": {\n'
    printf '    "size_bytes_delta": %d,\n' "$CMP_DELTA_SIZE"
    printf '    "sha256_equal": %s,\n' "$CMP_SHA_EQUAL"
    printf '    "family_changed": %s,\n' "$CMP_FAM_CHANGED"
    printf '    "xc_changed": %s,\n' "$CMP_XC_CHANGED"
    printf '    "relativity_changed": %s,\n' "$CMP_REL_CHANGED"
    printf '    "engine_changed": %s,\n' "$CMP_ENG_CHANGED"
    printf '    "format_changed": %s\n' "$CMP_FMT_CHANGED"
    printf '  },\n'
    printf '  "warnings": %s\n' "$warnings_json"
    printf '}\n'
}

compare_render_human() {
    printf '\n'
    printf 'Comparison: %s vs %s\n\n' "$CMP_ID_A" "$CMP_ID_B"
    printf '  %-22s %-26s %-26s\n' "Property" "File A" "File B"
    printf '  %-22s %-26s %-26s\n' "---------------------" "-------------------------" "-------------------------"
    printf '  %-22s %-26s %-26s\n' "Element" "${CMP_EL_A:--}" "${CMP_EL_B:--}"
    printf '  %-22s %-26s %-26s\n' "Engine" "${CMP_ENG_A:--}" "${CMP_ENG_B:--}"
    printf '  %-22s %-26s %-26s\n' "Functional (XC)" "${CMP_XC_A:--}" "${CMP_XC_B:--}"
    printf '  %-22s %-26s %-26s\n' "Family" "${CMP_FAM_A:--}" "${CMP_FAM_B:--}"
    printf '  %-22s %-26s %-26s\n' "Relativity" "${CMP_REL_A:--}" "${CMP_REL_B:--}"
    printf '  %-22s %-26s %-26s\n' "Format" "${CMP_FMT_A:--}" "${CMP_FMT_B:--}"
    printf '  %-22s %-26s %-26s\n' "Size (bytes)" "$CMP_SIZE_A" "$CMP_SIZE_B"
    printf '  %-22s %-26s %-26s\n' "SSSP Cutoff (prec)" "${CMP_CUTOFF_A:-none}" "${CMP_CUTOFF_B:-none}"
    printf '\n'
    printf 'Diff summary:\n'
    printf '  Size delta:        %+d bytes\n' "$CMP_DELTA_SIZE"
    printf '  SHA256 equal:      %s\n' "$CMP_SHA_EQUAL"
    printf '  Engine changed:    %s\n' "$CMP_ENG_CHANGED"
    printf '  Family changed:    %s\n' "$CMP_FAM_CHANGED"
    printf '  XC changed:        %s\n' "$CMP_XC_CHANGED"
    printf '  Relativity changed:%s\n' "$CMP_REL_CHANGED"
    printf '  Format changed:    %s\n' "$CMP_FMT_CHANGED"

    if [ ${#CMP_WARNINGS[@]} -gt 0 ]; then
        printf '\nWarnings:\n'
        local w
        for w in "${CMP_WARNINGS[@]}"; do
            printf '  * %s\n' "$w"
        done
    fi
    printf '\n'
}
