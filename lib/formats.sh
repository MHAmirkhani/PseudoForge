# shellcheck shell=bash
# ---------------------------------------------------------------------------
# formats.sh -- what a run can actually write.
#
# UPF is the default because Quantum ESPRESSO reads it and most other codes
# now do too, but it is not the only thing anyone wants.  OPIUM alone writes
# thirteen formats; ONCVPSP writes psp8 and PSML; the ultrasoft and fhi98PP
# codes write their own layouts before any conversion happens.  Someone
# running CASTEP, SIESTA, CPMD or a quantum Monte Carlo code needs one of
# those, and telling them "generate UPF and convert it yourself" is not an
# answer when the engine could simply have written it.
#
# The rule here is the same one that governs the rest of the tool: a format is
# offered only where an engine genuinely produces it.  Asking for a format the
# chosen engine cannot write is refused with the list of engines that can,
# rather than quietly handed back a UPF with the wrong extension.
# ---------------------------------------------------------------------------

declare -gA FMT_LABEL FMT_ENGINES FMT_EXT FMT_KEYWORD FMT_NOTE
declare -ga FMT_ORDER=()

pf_formats_load() {
    [ ${#FMT_ORDER[@]} -gt 0 ] && return 0
    local f=$PF_DATA/formats.tsv
    [ -f "$f" ] || die "format registry not found: $f"
    local id label engines ext kw note
    while IFS=$'\t' read -r id label engines ext kw note; do
        case $id in ''|\#*) continue ;; esac
        FMT_LABEL[$id]=$label
        FMT_ENGINES[$id]=$engines
        FMT_EXT[$id]=$ext
        FMT_KEYWORD[$id]=$([ "$kw" = "-" ] && echo "" || echo "$kw")
        FMT_NOTE[$id]=$note
        FMT_ORDER+=("$id")
    done < "$f"
}

fmt_exists() { pf_formats_load; [ -n "${FMT_LABEL[$1]:-}" ]; }

# Can this engine write this format directly?
fmt_engine_can() {   # fmt_engine_can <engine> <format>
    pf_formats_load
    in_list "$1" ${FMT_ENGINES[$2]:-}
}

# Every format the engine can write.
fmt_for_engine() {
    pf_formats_load
    local eng=$1 id
    for id in "${FMT_ORDER[@]}"; do
        fmt_engine_can "$eng" "$id" && printf '%s\n' "$id"
    done
}

# Which engines can write this format?  Used to make a refusal useful.
fmt_engines_for() {
    pf_formats_load
    printf '%s\n' "${FMT_ENGINES[$1]:-}"
}

# ---------------------------------------------------------------------------
# fmt_validate <engine> <comma-or-space separated list>
#   Echoes the normalised list, or fails with an explanation.
# ---------------------------------------------------------------------------
fmt_validate() {
    local eng=$1 want=$2 id out="" bad=0
    pf_formats_load
    for id in ${want//,/ }; do
        id=$(lower "$id")
        if ! fmt_exists "$id"; then
            error "unknown output format '$id'"
            error "  known formats: $(printf '%s ' "${FMT_ORDER[@]}")"
            bad=1; continue
        fi
        if ! fmt_engine_can "$eng" "$id"; then
            error "${ENG_LABEL[$eng]:-$eng} cannot write '$id' (${FMT_LABEL[$id]})."
            error "  Engines that can: $(fmt_engines_for "$id")"
            error "  Or pick a format this engine writes: $(fmt_for_engine "$eng" | tr '\n' ' ')"
            bad=1; continue
        fi
        out="$out $id"
    done
    [ "$bad" = 0 ] || return 1
    trim "$out"
}


# ---------------------------------------------------------------------------
# fmt_list -- what `pseudoforge list formats` prints.
# ---------------------------------------------------------------------------
fmt_list() {
    pf_formats_load
    pf_engines_load
    local id
    banner "Output formats"
    printf '  %-9s %-28s %-26s %s\n' FORMAT NAME "WRITTEN BY" EXT
    printf '  %s\n' "$(printf '%.0s-' $(seq 1 92))"
    for id in "${FMT_ORDER[@]}"; do
        printf '  %-9s %-28s %-26s .%s\n' \
            "$id" "${FMT_LABEL[$id]}" "${FMT_ENGINES[$id]}" "${FMT_EXT[$id]}"
    done
    printf '\n  Pick one or more with --format, e.g.  --format upf,recpot,siesta\n'
    printf '  A format is only offered where an engine really writes it.\n\n'
}
