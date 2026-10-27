# shellcheck shell=bash
# ---------------------------------------------------------------------------
# build_command.sh -- turn physics choices into an exact CLI invocation
#
# Wraps cli_parse and cli_check_spec, and renders the command using
# spec_cmdline from lib/recipe.sh.
# ---------------------------------------------------------------------------

declare -g BUILD_CMD=""
declare -g BUILD_EXPLANATION=""
declare -g BUILD_REFUSAL=""

build_command_for() {
    BUILD_CMD=""
    BUILD_EXPLANATION=""
    BUILD_REFUSAL=""

    local err_file out_file rc=0
    err_file=$(mktemp)
    out_file=$(mktemp)

    (
        pf_sink_use cli
        pf_config_load 2>/dev/null || true
        pf_elements_load 2>/dev/null || true
        pf_xc_load 2>/dev/null || true
        pf_profiles_load 2>/dev/null || true
        pf_engines_load 2>/dev/null || true
        pf_metadata_load 2>/dev/null || true
        pf_formats_load 2>/dev/null || true
        spec_init
        cli_parse "$@"
        [ -n "$CLI_ELEMENTS" ] || die "no elements given: use -e/--elements (pseudoforge help)"
        cli_check_spec
        spec_cmdline
    ) > "$out_file" 2> "$err_file" || rc=$?

    if [ "$rc" -ne 0 ]; then
        BUILD_REFUSAL=$(sed -E $'s/\x1b\\[[0-9;]*[a-zA-Z]//g' "$err_file" | sed -e 's/^ERROR[[:space:]]*//' -e 's/^[[:space:]]*//' | grep -v '^[[:space:]]*$' | head -1)
        [ -z "$BUILD_REFUSAL" ] && BUILD_REFUSAL="Invalid or incompatible options for generation."
        rm -f "$err_file" "$out_file"
        return 1
    fi

    BUILD_CMD=$(tr -d '\r\n' < "$out_file")
    rm -f "$err_file" "$out_file"

    BUILD_EXPLANATION="Exact CLI invocation constructed from validated physics choices."
    return 0
}

build_command_render_json() {
    printf '{\n'
    printf '  "command": %s,\n' "$(http_json_str "$BUILD_CMD")"
    printf '  "explanation": %s\n' "$(http_json_str "$BUILD_EXPLANATION")"
    printf '}\n'
}

build_command_render_human() {
    printf '%s\n' "$BUILD_CMD"
}
