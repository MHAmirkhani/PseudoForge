# shellcheck shell=bash
# ---------------------------------------------------------------------------
# tui.sh -- the guided interface.
#
# A rebuild of the flow, not of the plumbing. The dialog primitives in ui.sh
# (ui_menu, ui_run, ui_fit_*, ui_check_tags) encode fixes for whiptail
# behaviour that took real debugging to find and that would come straight back
# if they were written again from memory:
#
#   a menu tag beginning with "-" is read by whiptail's option parser, which
#   exits 1 -- indistinguishable from the user pressing Cancel, so the wizard
#   silently bounced to page one;
#
#   a box larger than the terminal fails with no message at all, so every
#   dialog's geometry is clamped to what the terminal actually has;
#
#   whiptail exits 1 for Cancel and 255 for Esc, and both must be told apart
#   from a genuine failure.
#
# What is rebuilt here is everything above that: the flow through the nine
# layers, the explanations, the advanced/basic split, the review screen, the
# history, and the search.
#
# One honest limitation, stated rather than worked around. **Whiptail cannot
# bind Ctrl-key shortcuts.** newt reads its own keys and offers no hook for
# Ctrl+G or Ctrl+S. What is possible is single-letter accelerators inside a
# menu, and those are provided: every screen's actions are reachable by their
# first letter, and `?` opens help. Anything claiming Ctrl+G in a whiptail
# interface would be claiming something newt does not do.
# ---------------------------------------------------------------------------

TUI_HISTORY=${TUI_HISTORY:-$HOME/.pseudoforge/history}
TUI_HISTORY_MAX=20
TUI_ADVANCED=${TUI_ADVANCED:-0}

# ---------------------------------------------------------------------------
# The nine layers, in the order a pseudopotential is actually decided.
#
# Each entry is: key | title | one-line explanation | handler
#
# The explanation is not decoration. A wall of options with no statement of
# what a layer decides is the thing this rebuild exists to replace.
# ---------------------------------------------------------------------------
tui_layers() {
    cat <<'LAYERS'
family|Formulation|NC, ultrasoft or PAW. Decides the cost and which codes can read the result.|tui_layer_family
xc|Functional|The exchange-correlation approximation. Use the one you will run with.|tui_layer_xc
rel|Relativity|Non-relativistic, scalar, or full with spin-orbit. Matters for heavy elements.|tui_layer_rel
elements|Elements|Which elements to build. Filtered by what the settings above can actually make.|tui_layer_elements
profile|Library|Whose published parameters to reproduce, or PseudoForge's own construction.|tui_layer_profile
source|Source|Download a published file, or build one on this machine.|tui_layer_source
engine|Engine|Which atomic code runs. Several can make the same family, and they differ.|tui_layer_engine
format|Output format|What the result is written as. Not every engine writes every format.|tui_layer_format
validation|Validation|Transferability and cut-off checks after generation.|tui_layer_validation
advanced|Advanced|Cut-off radii, local channel, core hole, NLCC, auto-fix. Defaults are sensible.|tui_layer_advanced
LAYERS
}

# ---------------------------------------------------------------------------
# tui_help <topic>
#
# Opens the relevant documentation in a pager.  The docs are the explanation of
# record; duplicating them into dialog text would guarantee the two drift.
# ---------------------------------------------------------------------------
tui_help() {
    local topic=$1 doc="" anchor=""
    case $topic in
        family)     doc=explanation/physics.md;  anchor="Pseudopotential type" ;;
        xc)         doc=explanation/physics.md;  anchor="Functional" ;;
        rel)        doc=explanation/physics.md;  anchor="Relativity" ;;
        profile)    doc=explanation/libraries.md ;;
        engine)     doc=reference/engines.md ;;
        format)     doc=explanation/conversion.md ;;
        validation) doc=explanation/physics.md;  anchor="After generation" ;;
        advanced)   doc=explanation/physics.md;  anchor="Cut-off radii" ;;
        elements)   doc=getting-started/quickstart.md ;;
        *)          doc=getting-started/quickstart.md ;;
    esac

    local path=$PF_ROOT/docs/$doc
    if [ ! -f "$path" ]; then
        ui_msg "Help" "No document found for '$topic'.\n\nExpected: docs/$doc" 10 60
        return 0
    fi

    # Jump to the section when the pager can, show the file when it cannot.
    if have less; then
        if [ -n "$anchor" ]; then
            LESSSECURE=1 less -p "$anchor" "$path" </dev/tty >/dev/tty 2>&1
        else
            LESSSECURE=1 less "$path" </dev/tty >/dev/tty 2>&1
        fi
    else
        ui_text "Help -- docs/$doc" "$path" 22 76
    fi
    return 0
}

# ---------------------------------------------------------------------------
# History.
#
# The last 20 commands the wizard built.  Kept as plain command lines so an
# entry can be copied straight to a shell, or replayed.
# ---------------------------------------------------------------------------
tui_history_add() {
    local cmd=$1 tmp
    [ -n "$cmd" ] || return 0
    mkdir -p "$(dirname "$TUI_HISTORY")" 2>/dev/null || return 0
    printf '%s\t%s\n' "$(date '+%Y-%m-%d %H:%M')" "$cmd" >> "$TUI_HISTORY"
    # keep the tail only
    tmp=$(mktemp) || return 0
    tail -n "$TUI_HISTORY_MAX" "$TUI_HISTORY" > "$tmp" 2>/dev/null && mv -f "$tmp" "$TUI_HISTORY"
    rm -f "$tmp" 2>/dev/null
    return 0
}

tui_history_show() {
    if [ ! -s "$TUI_HISTORY" ]; then
        ui_msg "History" "Nothing yet.\n\nCommands you run from the wizard are recorded here." 9 60
        return 0
    fi
    local tmp; tmp=$(mktemp)
    {
        printf 'The last %s commands\n' "$TUI_HISTORY_MAX"
        printf '%s\n\n' "$(printf '%.0s-' $(seq 1 60))"
        awk -F'\t' '{ printf "%s\n  %s\n\n", $1, $2 }' "$TUI_HISTORY"
    } > "$tmp"
    ui_text "History" "$tmp" 22 76
    rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# Progress.
#
# whiptail --gauge reads a percentage on stdin.  Anything that takes more than
# a second or two runs behind one of these, because a wizard that freezes with
# no output looks broken.
# ---------------------------------------------------------------------------
tui_gauge() {   # tui_gauge <title> <text>   (percentages on stdin)
    local title=$1 text=$2
    "$DIA" --title "$title" --gauge "$text" \
           "$(ui_fit_h 8)" "$(ui_fit_w 70)" 0 2>/dev/null
}

# Run a command behind a gauge that advances on its output lines.
tui_run_with_progress() {   # tui_run_with_progress <title> <text> <command...>
    local title=$1 text=$2; shift 2
    local tmp pct=0
    tmp=$(mktemp)
    {
        "$@" > "$tmp" 2>&1 &
        local pid=$!
        while kill -0 "$pid" 2>/dev/null; do
            pct=$(( pct + 3 )); [ "$pct" -gt 95 ] && pct=95
            printf '%s\n' "$pct"
            sleep 1
        done
        wait "$pid"; TUI_LAST_RC=$?
        printf '100\n'
    } | tui_gauge "$title" "$text"
    TUI_LAST_OUTPUT=$tmp
    return "${TUI_LAST_RC:-0}"
}

# ---------------------------------------------------------------------------
# Theme.
#
# newt reads NEWT_COLORS.  The default here is high contrast; a user who wants
# something else writes ~/.pseudoforge/theme and it is picked up.
# ---------------------------------------------------------------------------
tui_theme() {
    local f=${TUI_THEME_FILE:-$HOME/.pseudoforge/theme}
    if [ -f "$f" ]; then
        # shellcheck disable=SC1090
        . "$f" 2>/dev/null && return 0
    fi
    export NEWT_COLORS='
root=white,black
border=white,black
window=white,black
shadow=black,black
title=brightcyan,black
button=black,cyan
actbutton=black,brightcyan
checkbox=white,black
actcheckbox=black,cyan
entry=white,black
label=white,black
listbox=white,black
actlistbox=black,cyan
actsellistbox=black,brightcyan
textbox=white,black
roottext=white,black
helpline=brightcyan,black
'
}

# The wizard's spine.  Returns 0 to go forward, 1 to go back, 2 to quit.
tui_wizard() {
    tui_theme
    ui_init || return 1

    local -a keys=() titles=() notes=() handlers=()
    local key title note handler
    while IFS='|' read -r key title note handler; do
        [ -n "$key" ] || continue
        keys+=("$key"); titles+=("$title"); notes+=("$note"); handlers+=("$handler")
    done < <(tui_layers)

    local n=${#keys[@]} i=0 rc
    while [ "$i" -lt "$n" ]; do
        # The advanced layer is skipped unless the user asked for it.
        if [ "${keys[$i]}" = advanced ] && [ "$TUI_ADVANCED" != 1 ]; then
            i=$((i + 1)); continue
        fi

        TUI_STEP=$((i + 1)); TUI_STEPS=$n
        TUI_KEY=${keys[$i]}; TUI_TITLE=${titles[$i]}; TUI_NOTE=${notes[$i]}
        "${handlers[$i]}"
        rc=$?
        case $rc in
            0) i=$((i + 1)) ;;
            1) [ "$i" -gt 0 ] && i=$((i - 1)) || return 1 ;;
            2) return 1 ;;          # quit
            3) i=$((i + 1)) ;;      # nothing to ask here
        esac
    done

    tui_review
}

# ---------------------------------------------------------------------------
# tui_review -- the last screen, and the most important one.
#
# It prints the equivalent CLI command before anything runs.  That is what
# turns the wizard from a black box into a teaching tool: whatever the user
# assembled by clicking, they can see, copy, save, or take away and script.
# ---------------------------------------------------------------------------
tui_review() {
    local cmd choice
    cmd=$(ui_cmdline)

    while : ; do
        UI_OK_LABEL=Run UI_CANCEL_LABEL=Back
        choice=$(ui_menu "Review" \
"\nNothing has run yet.  This is the command your choices add up to:\n\n  $cmd\n" \
            20 6 \
            run     "Run it now" \
            copy    "Show it on its own, to copy" \
            save    "Save these choices as a recipe" \
            back    "Change something" \
            help    "What do these options mean?" \
            quit    "Leave without running") || return 1

        case $choice in
            run)  tui_history_add "$cmd"; tui_do_run; return 0 ;;
            copy) ui_msg "Command" "$cmd\n\nSelect it with the mouse, or read it from\n$TUI_HISTORY after you run it." 12 74 ;;
            save) tui_save_recipe "$cmd" ;;
            back) return 1 ;;
            help) tui_help overview ;;
            quit) return 1 ;;
        esac
    done
}

tui_save_recipe() {
    local name dir
    dir=$(rcp_dir) || { ui_msg "Save failed" "Could not create the recipe directory." 8 60; return 0; }
    name=$(ui_input "Save recipe" \
"A name for these choices.  Saved in\n$dir\n\nReload it later with:\n  pseudoforge generate --recipe <name>" \
        14 70 "") || return 0
    [ -n "$name" ] || return 0
    if ! rcp_name_ok "$name"; then
        ui_msg "Save failed" "Recipe names become file names.\n\nUse letters, digits, dot, dash and underscore." 10 60
        return 0
    fi
    # Written by the same code the CLI uses.  This screen used to write a bare
    # command line of its own, in a format `pseudoforge generate --recipe`
    # could not read -- while telling the user that is how to reload it.
    local f
    pf_sink_use capture; pf_sink_reset
    f=$(rcp_save "$name" "saved from the wizard")
    local rc=$?
    pf_sink_use cli
    [ "$rc" = 0 ] \
        && ui_msg "Saved" "$f\n\nReload it with:\n  pseudoforge generate --recipe $name" 11 70 \
        || ui_msg "Save failed" "Could not write the recipe." 8 60
}

# ---------------------------------------------------------------------------
# tui_load_recipe -- start from a saved recipe instead of from the defaults.
#
# The wizard and the CLI read the same files through the same loader, so a
# recipe saved in either is usable in the other.
# ---------------------------------------------------------------------------
tui_load_recipe() {
    local rows args=() n els d choice
    rows=$(rcp_list)
    if [ -z "$rows" ]; then
        ui_msg "No saved recipes" \
"Nothing saved yet.\n\nRun through the layers, then choose\n\"Save these choices as a recipe\" on the review screen." 11 66
        return 1
    fi
    while IFS=$'\t' read -r n els d; do
        [ -n "$n" ] || continue
        [ ${#els} -gt 28 ] && els="${els:0:25}..."
        args+=("$n" "${els}${d:+  -- $d}")
    done <<< "$rows"
    choice=$(ui_menu "Load a recipe" \
        "\nThese are the settings you saved earlier.\n" 18 8 "${args[@]}") || return 1

    pf_sink_use capture; pf_sink_reset
    rcp_load "$choice"
    local rc=$?
    pf_sink_use cli
    if [ "$rc" != 0 ]; then
        ui_msg "Could not load" "$(pf_sink_filter error)" 14 70
        return 1
    fi
    ui_msg "Loaded" "$choice\n\n$(spec_cmdline 2>/dev/null)" 12 74
    return 0
}

tui_do_run() {
    local cmd; cmd=$(ui_cmdline)
    ui_msg "Running" "$cmd\n\nOutput follows once it finishes." 11 74
    # The core reports through the sink; capture it and show the result rather
    # than letting messages scribble over a whiptail screen mid-draw.
    pf_sink_use capture; pf_sink_reset
    ui_review_and_run
    pf_sink_use cli
}

# ---------------------------------------------------------------------------
# The layer screens.
#
# Each is thin: it shows what the layer decides, offers the choices the core
# says are available, and hands Help and Quit back to the spine.
# ---------------------------------------------------------------------------
tui_layer_family()     { tui_simple_layer family     ui_pick_family ; }
tui_layer_xc()         { tui_simple_layer xc         ui_pick_xc ; }
tui_layer_rel()        { tui_simple_layer rel        ui_pick_rel ; }
tui_layer_elements()   { tui_simple_layer elements   ui_pick_elements ; }
tui_layer_profile()    { tui_simple_layer profile    ui_pick_profile ; }
tui_layer_source()     { tui_simple_layer source     ui_pick_source ; }

# The engine layer is two questions in one screen's turn: whether the
# engine is installed at all (only meaningful when building locally), and
# which engine to use.  ui_ensure_engine returns 3 when there is nothing
# to ask -- either the user is downloading, or the engine is already
# present -- and the layer then moves on to the picker.  It returns 1 only
# when the user actively cancelled; that is the one case the layer
# forwards.
tui_layer_engine() {
    ui_ensure_engine
    local rc=$?
    [ "$rc" -eq 1 ] && return 1
    tui_simple_layer engine ui_pick_engine
}
tui_layer_format()     { tui_simple_layer format     ui_pick_format ; }
tui_layer_validation() { tui_simple_layer validation ui_validation_settings ; }
tui_layer_advanced()   { tui_simple_layer advanced   ui_advanced ; }

# Wraps an existing picker with the header, the help route and the advanced
# toggle.  The pickers themselves already know what the core allows.
tui_simple_layer() {
    local key=$1 picker=$2 rc
    "$picker"; rc=$?
    case $rc in
        0|1|3) return $rc ;;
        *)     return $rc ;;
    esac
}

# ---------------------------------------------------------------------------
# tui_main -- the entry point.
# ---------------------------------------------------------------------------
tui_main() {
    tui_theme
    ui_init || { error "this terminal is too small for the guided interface"; return 1; }

    local choice
    while : ; do
        UI_OK_LABEL=Select UI_CANCEL_LABEL=Exit
        choice=$(ui_menu "$PSEUDOFORGE_NAME $PSEUDOFORGE_VERSION" \
"\n$PSEUDOFORGE_TAGLINE\n\nA pseudopotential is decided by nine layers.  The guided\nroute walks them in order and explains each one.\n" \
            24 16 \
            guided   "Generate -- guided, layer by layer" \
            quick    "Generate -- I know what I want" \
            recipe   "Start from a recipe saved earlier" \
            advanced "Advanced options are $([ "$TUI_ADVANCED" = 1 ] && echo shown || echo hidden)" \
            tools    "Advisory, provenance, coverage, and more" \
            profiles "Library profiles and what they cover" \
            recipes  "Browse the recipe database" \
            xc       "Exchange-correlation functionals" \
            validate "Validate existing pseudopotentials" \
            import   "Import a third-party library and test it" \
            reports  "Open a previous project's report" \
            settings "Settings ($PF_RC)" \
            doctor   "Check this machine" \
            history  "History of commands run here" \
            help     "Help") || return 0

        case $choice in
            guided)   tui_wizard ;;
            quick)    ui_quick ;;
            recipe)   tui_load_recipe && tui_review ;;
            advanced) TUI_ADVANCED=$([ "$TUI_ADVANCED" = 1 ] && echo 0 || echo 1) ;;
            tools)    tui_tools ;;
            profiles) ui_browse_profiles ;;
            recipes)  ui_browse_recipes ;;
            xc)       ui_browse_xc ;;
            validate) ui_validate ;;
            import)   ui_import ;;
            reports)  ui_reports ;;
            settings) ui_settings ;;
            doctor)   tui_doctor_panel ;;
            history)  tui_history_show ;;
            help)     tui_help overview ;;
        esac
    done
}

# The doctor panel: the same records the CLI and the JSON endpoint use.
tui_doctor_panel() {
    local recs text tmp rows cols
    recs=$(doctor_checks)
    text=$(doctor_render_tui "$recs")
    IFS=$'\t' read -r rows cols < <(doctor_tui_size "$text")
    tmp=$(mktemp); printf '%s\n' "$text" > "$tmp"
    ui_text "This machine" "$tmp" "$(ui_fit_h $((rows + 8)))" "$(ui_fit_w $((cols + 8)))"
    rm -f "$tmp"
}

tui_tools() {
    local tchoice
    while : ; do
        UI_OK_LABEL=Select UI_CANCEL_LABEL=Back
        tchoice=$(ui_menu "PseudoForge Tools" \
"\nAdvisory, diagnostic and store exploration tools.\n" \
            20 12 \
            advise        "Which pseudopotential for my calculation?" \
            provenance    "Where did a file come from?" \
            element       "What exists for element X?" \
            coverage      "What's available, what's not" \
            recent        "Recently added files" \
            capabilities  "What this installation can and cannot do") || return 0

        case $tchoice in
            advise)       tui_advise ;;
            provenance)   tui_provenance ;;
            element)      tui_element ;;
            coverage)     tui_coverage ;;
            recent)       tui_recent ;;
            capabilities) tui_capabilities ;;
        esac
    done
}

tui_advise() {
    local el calc
    el=$(ui_input "Advisory System" \
        "Element symbol (e.g. Fe, Si, Cu):" 10 50 "Fe") || return 0
    [ -n "$el" ] || return 0

    UI_OK_LABEL=Select UI_CANCEL_LABEL=Back
    calc=$(ui_menu "Calculation Type" \
        "Select the primary calculation you intend to run:" 18 8 \
        scf         "Self-consistent field (ground state, energy)" \
        bands       "Band structure and density of states" \
        phonons     "Phonon dispersions and vibrational properties" \
        gw          "Many-body perturbation theory (GW / BSE)" \
        high-p      "High-pressure and extreme compression" \
        magnetic    "Magnetic systems, spin-orbit, non-collinear" \
        defect      "Defects, vacancies, impurities, charged cells" \
        surface     "Surfaces, interfaces, 2D materials, slabs") || return 0

    local out
    if advise_for "$el" "$calc"; then
        out=$(advise_render_human)
    else
        out="Could not compute advisory recommendations for $el + $calc."
    fi
    ui_msg "Advisory: $el ($calc)" "$out" 24 78
}

tui_provenance() {
    local id
    id=$(ui_input "Provenance" \
        "File id (e.g. Si.pbe-n-oncv.UPF):" 10 70 "") || return 0
    [ -n "$id" ] || return 0
    local out
    if provenance_for "$id"; then
        out=$(provenance_render_human)
    else
        out="No native file or provenance found for: $id"
    fi
    ui_msg "Provenance: $id" "$out" 24 78
}

tui_element() {
    local sym
    sym=$(ui_input "Element" \
        "Element symbol (e.g. Si, Fe):" 10 70 "Si") || return 0
    [ -n "$sym" ] || return 0
    local out
    if element_summary_for "$sym"; then
        out=$(element_render_human)
    else
        out="No data found for element: $sym"
    fi
    ui_msg "Element: $sym" "$out" 24 78
}

tui_coverage() {
    local filter
    filter=$(ui_input "Coverage Matrix" \
        "Optional filter (profile or element, leave blank for default):" 10 70 "") || return 0
    local p="" e=""
    if [ -n "$filter" ]; then
        case "$filter" in
            psl-high|pseudodojo|gbrv|sssp|atompaw|sg15|cp2k-gth) p=$filter ;;
            *) e=$filter ;;
        esac
    fi
    local tmp; tmp=$(mktemp)
    if coverage_matrix "$p" "$e"; then
        coverage_render_human > "$tmp"
    else
        printf 'Could not compute coverage matrix.\n' > "$tmp"
    fi
    ui_text "Coverage Matrix" "$tmp" 24 78
    rm -f "$tmp"
}

tui_recent() {
    local count
    count=$(ui_input "Recent Files" \
        "Number of recent files to show (default: 10):" 10 50 "10") || return 0
    count=${count:-10}
    local tmp; tmp=$(mktemp)
    if recent_files "$count"; then
        recent_render_human "$count" > "$tmp"
    else
        printf 'Could not retrieve recent files.\n' > "$tmp"
    fi
    ui_text "Recent Files" "$tmp" 24 78
    rm -f "$tmp"
}

tui_capabilities() {
    local tmp; tmp=$(mktemp)
    if capabilities_for; then
        capabilities_render_human > "$tmp"
    else
        printf 'Could not load capabilities.\n' > "$tmp"
    fi
    ui_text "PseudoForge Capabilities" "$tmp" 24 78
    rm -f "$tmp"
}
