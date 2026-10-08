# shellcheck shell=bash
# ---------------------------------------------------------------------------
# ui.sh -- the whiptail/dialog front end.
#
# The TUI is a thin skin over exactly the same functions the command line
# calls, so anything you can click here you can also put in a job script.  The
# final screen of the wizard shows the equivalent `pseudoforge generate ...` line
# for precisely that reason.
# ---------------------------------------------------------------------------

DIA=
UI_BACKTITLE=

ui_init() {
    DIA=$(deps_tui_backend) || { deps_tui_hint; exit 1; }
    UI_BACKTITLE="PseudoForge $PSEUDOFORGE_VERSION -- multi-engine pseudopotential generator and validator"
    ui_term_size

    # Better to say this once, up front, than to have screens fail one at a time
    # further into the flow.
    if ! ui_term_usable; then
        error "the terminal is ${UI_ROWS}x${UI_COLS}, which is too small for the menus"
        error "  resize to at least 24 rows by 80 columns, or use the command line:"
        error "    pseudoforge generate -e Si -t paw -x pbe"
        error "    pseudoforge help"
        exit 1
    fi
    if [ "$UI_ROWS" -lt 24 ] || [ "$UI_COLS" -lt 80 ]; then
        warn "terminal is ${UI_ROWS}x${UI_COLS}; menus will be cramped (24x80 or more is better)"
    fi
}

# ---- primitives -----------------------------------------------------------
# Pause only when there is a human at the keyboard; the test harness drives the
# menus with stdin closed and must not block here.
ui_pause() {
    [ -t 0 ] || return 0
    printf '\n%sPress Enter to return to the menu.%s ' "$C_DIM" "$C_RESET"
    read -r _ || true
}

# ---------------------------------------------------------------------------
# Dialog helpers.
#
# Two things these have to get right, both learned the hard way:
#
#   1. whiptail refuses to draw a box larger than the terminal, and fails with
#      a non-zero status when asked to.  Screens here ask for up to 26 rows and
#      100 columns, so on an 80x24 terminal several of them simply never
#      appeared.  Every geometry is therefore clamped to what actually fits.
#
#   2. whiptail signals "user pressed Cancel" and "I could not draw that" the
#      same way, with a non-zero exit.  Callers treat non-zero as cancel and
#      return to the previous screen, so a failure looked exactly like the user
#      changing their mind -- you picked an option, and the wizard bounced you
#      back to the main menu with no explanation.  ui_run separates the two and
#      says so out loud when it is the second.
# ---------------------------------------------------------------------------

UI_ROWS=0
UI_COLS=0

ui_term_size() {
    local sz
    UI_ROWS=0; UI_COLS=0

    # Deliberately not "stty size < /dev/tty": opening /dev/tty blocks
    # indefinitely where there is no controlling terminal, which includes the
    # test harness and any non-interactive shell.  Ask only file descriptors we
    # already know are terminals.
    if [ -t 2 ] && sz=$(stty size <&2 2>/dev/null) && [ -n "$sz" ]; then
        UI_ROWS=${sz%% *}; UI_COLS=${sz##* }
    elif [ -t 0 ] && sz=$(stty size 2>/dev/null) && [ -n "$sz" ]; then
        UI_ROWS=${sz%% *}; UI_COLS=${sz##* }
    elif [ -n "${LINES:-}" ] && [ -n "${COLUMNS:-}" ]; then
        UI_ROWS=$LINES; UI_COLS=$COLUMNS
    elif [ -t 2 ] && have tput; then
        UI_ROWS=$(tput lines 2>/dev/null); UI_COLS=$(tput cols 2>/dev/null)
    fi
    # 0 is numeric but not a size: it means every probe declined, which is the
    # normal case with no terminal at all.
    case $UI_ROWS in ''|0|*[!0-9]*) UI_ROWS=24 ;; esac
    case $UI_COLS in ''|0|*[!0-9]*) UI_COLS=80 ;; esac
}

# Largest box that fits, leaving room for the backtitle line and a margin.
ui_fit_h() {
    local want=$1 max
    [ "$UI_ROWS" -gt 0 ] || ui_term_size
    max=$((UI_ROWS - 2))
    [ "$max" -lt 8 ] && max=8
    [ "$want" -gt "$max" ] && want=$max
    printf '%s\n' "$want"
}

ui_fit_w() {
    local want=$1 max
    [ "$UI_COLS" -gt 0 ] || ui_term_size
    max=$((UI_COLS - 4))
    [ "$max" -lt 40 ] && max=40
    [ "$want" -gt "$max" ] && want=$max
    printf '%s\n' "$want"
}

# A menu's list must leave room for the prompt text and the button row.
ui_fit_lh() {
    local want=$1 h=$2 max
    max=$((h - 8))
    [ "$max" -lt 3 ] && max=3
    [ "$want" -gt "$max" ] && want=$max
    [ "$want" -lt 1 ] && want=1
    printf '%s\n' "$want"
}

# Is the terminal simply too small for a TUI at all?
ui_term_usable() {
    [ "$UI_ROWS" -gt 0 ] || ui_term_size
    [ "$UI_ROWS" -ge 10 ] && [ "$UI_COLS" -ge 50 ]
}

# ---------------------------------------------------------------------------
# ui_run <capture|status> -- run $DIA and tell a refusal apart from a cancel.
#
# Exit codes: 0 accepted, 1 Cancel/No, 255 Esc.  Anything else is whiptail
# telling us it could not do what we asked, and the user needs to hear that.
# ---------------------------------------------------------------------------
UI_LAST_ERROR=

ui_run() {
    local mode=$1; shift
    local out rc
    UI_LAST_ERROR=
    if [ "$mode" = capture ]; then
        out=$("$DIA" "$@" 3>&1 1>&2 2>&3)
        rc=$?
    else
        "$DIA" "$@"
        rc=$?
        out=
    fi
    case $rc in
        0)   [ "$mode" = capture ] && printf '%s\n' "$out"; return 0 ;;
        1|255) return 1 ;;                      # the user said no
        *)
            UI_LAST_ERROR=$(printf '%s' "$out" | tr -d '\033' | head -2)
            error "the dialog could not be displayed (whiptail exit $rc)"
            [ -n "$UI_LAST_ERROR" ] && error "  $UI_LAST_ERROR"
            error "  terminal is ${UI_ROWS}x${UI_COLS}; try a larger window,"
            error "  or use the command line: pseudoforge generate --help"
            # the next dialog would repaint straight over this, so hold here
            ui_pause
            return 2 ;;
    esac
}

ui_msg() {
    local h w
    h=$(ui_fit_h "${3:-16}"); w=$(ui_fit_w "${4:-74}")
    ui_run status --backtitle "$UI_BACKTITLE" --title "$1" --msgbox "$2" "$h" "$w"
}

ui_yesno() {
    local h w
    h=$(ui_fit_h "${3:-12}"); w=$(ui_fit_w "${4:-70}")
    ui_run status --backtitle "$UI_BACKTITLE" --cancel-button "${UI_CANCEL_LABEL:-Cancel}" --title "$1" --yesno "$2" "$h" "$w"
}

ui_input() {
    local h w
    h=$(ui_fit_h "${3:-10}"); w=$(ui_fit_w "${4:-70}")
    ui_run capture --backtitle "$UI_BACKTITLE" --cancel-button "${UI_CANCEL_LABEL:-Cancel}" --title "$1" --inputbox "$2" "$h" "$w" "${5:-}"
}

ui_text() {
    local h w
    h=$(ui_fit_h "${3:-24}"); w=$(ui_fit_w "${4:-100}")
    ui_run status --backtitle "$UI_BACKTITLE" --title "$1" --scrolltext --textbox "$2" "$h" "$w"
}


# whiptail parses its arguments with popt, which reads anything starting with a
# dash as an option -- including a *menu tag*.  A tag like "--info--" makes it
# exit 1 with "unknown option", which callers cannot tell apart from the user
# pressing Cancel, so the screen silently never appears.  Catch it here instead.
ui_check_tags() {
    local i=1 a
    for a in "$@"; do
        if [ $((i % 2)) = 1 ] && [ "${a#-}" != "$a" ]; then
            error "internal error: menu tag '$a' starts with a dash"
            error "  whiptail would read it as a command-line option and refuse the dialog"
            return 1
        fi
        i=$((i + 1))
    done
    return 0
}

# ui_menu <title> <prompt> <height> <listheight> <tag> <item> ...
ui_menu() {
    local title=$1 prompt=$2 h=$3 lh=$4; shift 4
    local ok=${UI_OK_LABEL:-Ok}
    ui_check_tags "$@" || return 2
    h=$(ui_fit_h "$h"); lh=$(ui_fit_lh "$lh" "$h")
    ui_run capture --backtitle "$UI_BACKTITLE" --cancel-button "${UI_CANCEL_LABEL:-Cancel}" --title "$title" \
           --menu "$prompt" "$h" "$(ui_fit_w 78)" "$lh" "$@"
}

# ui_checklist <title> <prompt> <height> <listheight> <tag> <item> <on|off> ...
ui_checklist() {
    local title=$1 prompt=$2 h=$3 lh=$4; shift 4
    ui_check_tags "$@" || return 2
    h=$(ui_fit_h "$h"); lh=$(ui_fit_lh "$lh" "$h")
    ui_run capture --backtitle "$UI_BACKTITLE" --cancel-button "${UI_CANCEL_LABEL:-Cancel}" --title "$title" \
           --checklist "$prompt" "$h" "$(ui_fit_w 78)" "$lh" "$@"
}

# whiptail returns items quoted; strip the quotes.
ui_unquote() { printf '%s\n' "$1" | tr -d '"'; }

# ---------------------------------------------------------------------------
# Main menu
# ---------------------------------------------------------------------------

# spec_init resets everything, which would throw away the answers when walking
# back into an earlier step.  Only do it the first time round.

# ---------------------------------------------------------------------------
# Step 4 -- download a published file, or build one here.
#
# Downloading is usually the better answer and the wizard says so: published
# tables have been through far more testing than a fresh local run.  Building
# locally is for the settings nobody publishes -- a core hole, a different
# valence, an unusual functional.
# ---------------------------------------------------------------------------
ui_pick_source() {
    local prof=${SPEC[profile]} eng build_line choice
    eng=$(eng_for_profile "$prof" "${SPEC[family]}")
    SPEC[engine]=$eng

    if ! prof_is_generatable "$prof"; then
        build_line="Build here -- with ${ENG_LABEL[$eng]}, but with PseudoForge's own parameters"
    elif eng_available "$eng"; then
        build_line="Build here -- ${ENG_LABEL[$eng]} is installed and ready"
    else
        build_line="Build here -- needs ${ENG_LABEL[$eng]}; PseudoForge can install it"
    fi

    choice=$(ui_menu "Where the files come from" \
"\nHow should PseudoForge obtain ${PROF_LABEL[$prof]}?\n\nA published file has usually been tested far more thoroughly than\nanything generated on the spot.  Build locally when you need a\nsetting nobody publishes.\n" 16 2 \
        online "Download   -- mirror first, then the library's own site" \
        local  "$build_line") || return 1
    SPEC[source]=$choice

    if [ "$choice" = local ] && ! prof_is_generatable "$prof"; then
        ui_msg "About provenance" \
"\n${PROF_LABEL[$prof]} is produced by ${PROF_GENERATOR[$prof]}.\n\nWhat makes it that library is its published table of cut-off radii\nand projectors -- not the code that consumed them, and PseudoForge does\nnot have that table.\n\n${ENG_LABEL[$eng]} will run, but the result is a pseudoforge\npseudopotential and is labelled that way in the file and in every\nreport.  For a real reproduction, supply the library's own input\nfiles with  --params <dir>.\n" 20 76
        ui_yesno "Continue?" "\nGenerate with PseudoForge's own parameters anyway?" 10 70 || return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Step 5 -- make sure the engine is actually here.
# ---------------------------------------------------------------------------
ui_ensure_engine() {
    local eng=${SPEC[engine]} state detail choice path
    # Nothing to ask if we are downloading, or the engine is already present:
    # return 3 so the wizard keeps moving the way the user was going instead of
    # bouncing them between two screens.
    [ "${SPEC[source]:-local}" = local ] || return 3
    eng_available "$eng" && return 3
    IFS=$'\t' read -r state detail < <(eng_status "$eng")

    if [ "$eng" = ld1 ]; then
        ui_msg "Quantum ESPRESSO is missing" \
"\nld1.x was not found.\n\npseudoforge does not build Quantum ESPRESSO itself.  Install it with\nyour package manager, or:\n\n  git clone https://gitlab.com/QEF/q-e.git\n  cd q-e && ./configure && make pw ld1\n\nthen set QE_ROOT_DIR in\n  $PF_RC\n" 20 76
        return 1
    fi

    choice=$(ui_menu "Engine required -- ${ENG_LABEL[$eng]} is not installed" \
"\nBuilding this needs ${ENG_LABEL[$eng]}, which PseudoForge cannot find.\n\nSource: $detail\n\nAuto-install compiles it into\n  $(eng_bindir)\nand records the path in your config.  It needs a Fortran compiler\nand BLAS/LAPACK, and will ask before installing system packages.\n" 20 3 \
        install "Auto-install -- compile it now (a minute or two)" \
        manual  "Enter a path -- I already have it" \
        cancel  "Cancel") || return 1

    case $choice in
        install)
            clear
            banner "Installing ${ENG_LABEL[$eng]}"
            if build_engine "$eng"; then
                ui_pause
            else
                ui_msg "Build failed" \
"\n${ENG_LABEL[$eng]} did not build.\n\nThe log is at\n  $(eng_builddir)/$eng-build.log\n\nYou can still download published files for this library.\n" 16 76
                return 1
            fi ;;
        manual)
            path=$(ui_input "Path to ${ENG_BINARIES[$eng]%% *}" \
                   "Full path to the binary, or the directory holding it:" 10 74 \
                   "$(eng_bindir)") || return 1
            printf -v "${ENG_BIN_VAR[$eng]}" '%s' "$path"
            if eng_available "$eng"; then
                pf_config_set "${ENG_BIN_VAR[$eng]}" "$path"
            else
                ui_msg "Not found" "\nNothing executable at\n  $path\n" 10 70
                return 1
            fi ;;
        *) return 1 ;;
    esac
    return 0
}


ui_pick_family() {
    local c
    c=$(ui_menu "Pseudopotential type" \
"\nWhich construction should ld1.x use?\n" 19 6 \
        paw "PAW    Projector-augmented wave (Kresse-Joubert)  -- most accurate" \
        us  "US     Ultrasoft (RRKJ / Vanderbilt)              -- softest, fastest" \
        nc  "NC     Norm-conserving, separable (Kleinman-Bylander)" ) || return 1
    SPEC[family]=$c
    return 0
}

ui_pick_xc() {
    local fam id c items=()
    fam=$(ui_menu "Functional family" "\nChoose the family, then the functional.\n" 18 6 \
        LDA     "Local density approximation" \
        GGA     "Generalised gradient approximation (recommended)" \
        metaGGA "Meta-GGA -- generated with its semilocal parent" \
        hybrid  "Hybrid   -- generated with its semilocal parent" \
        vdW     "van der Waals -- generated with its exchange parent" ) || return 1

    for id in $(xc_list_family "$fam"); do
        if xc_is_native "$id"; then
            items+=("$id" "${XC_LABEL[$id]} [dft=${XC_QE[$id]}]")
        else
            items+=("$id" "${XC_LABEL[$id]} -> generated with $(xc_qe_string "$id")")
        fi
    done
    c=$(ui_menu "Functional ($fam)" \
"\nld1.x can only solve the atom with LDA or GGA. For the other families pseudoforge
generates with the accepted semilocal parent and records that in the UPF and
in the report -- which is what every public library does too.\n" 22 10 "${items[@]}") || return 1
    SPEC[xc]=$c

    # Ask whether something other than the requested functional will
    # actually be used, not merely whether the registry calls it a proxy:
    # AtomPAW generates meta-GGA for real, and telling that user their
    # dataset is not self-consistent would be false.
    if [ "$(xc_generator "$c")" != "$c" ]; then
        ui_msg "Functional provenance" \
"$(xc_explain "$c")

The generated files will carry dft=$(xc_qe_string "$c").
Use them with ${XC_QE[$c]} in pw.x. This is standard practice, but the
pseudopotential was not generated self-consistently with ${XC_QE[$c]}." 15 74
    fi
    return 0
}

ui_pick_rel() {
    local c
    c=$(ui_menu "Relativity" \
"\nFull-relativistic (spin-orbit) treatment is normally required from about
Z = 37 upwards, and essential for 5d elements and actinides.\n" 17 5 \
        scalar "Scalar-relativistic  -- no spin-orbit (rel=1)" \
        full   "Full-relativistic    -- with spin-orbit (rel=2)" \
        nonrel "Non-relativistic     -- light elements only (rel=0)" ) || return 1
    SPEC[rel]=$c
    return 0
}

ui_profiles_about() {
    local tmp id; tmp=$(mktemp)
    {
        printf 'Libraries PseudoForge cannot generate\n'
        printf '=====================================\n\n'
        printf 'Most libraries in the menu are reproducible here: PseudoForge holds the\n'
        printf 'generation inputs their authors publish and runs them with the matching\n'
        printf 'engine, so the result is a real reproduction rather than a lookalike.\n\n'
        printf 'These are the exceptions, and the reason in each case:\n\n'
        for id in $(prof_list); do
            prof_can_generate "$id" "${SPEC[family]}" && continue
            printf -- '---------------------------------------------------------------\n'
            printf '%s\n  reason    : %s\n  reference : %s\n\n  %s\n\n' \
                "${PROF_LABEL[$id]}" \
                "$(ui_why_not "$id")" \
                "${PROF_REFERENCE[$id]:-}" \
                "${PROF_NOTES[$id]:-}"
        done
    } > "$tmp"
    ui_text "Not generatable" "$tmp" 26 100
    rm -f "$tmp"
}


# ---------------------------------------------------------------------------
# ui_pick_profile -- now element-aware.
#
# The elements are chosen before this screen, which is what makes an honest
# filter possible: "PseudoDojo" is not a yes/no answer, it is "covers 12 of your
# 14 elements", and a library that covers none of them should not be offered at
# all.  Choosing the library first, as the wizard used to, meant the mismatch
# could only surface at generation time.
# ---------------------------------------------------------------------------
ui_pick_profile() {
    local id items=() hidden=() partial=() c n total
    local -a els=()
    # shellcheck disable=SC2086
    mapfile -t els < <(el_expand ${CLI_ELEMENTS:-Si})
    total=${#els[@]}

    while IFS=$'\t' read -r id n _; do
        [ -n "$id" ] || continue
        if [ "$n" -eq "$total" ]; then
            items+=("$id" "$(printf '%-30s all %s' "${PROF_LABEL[$id]}" "$total")")
        elif [ "$n" -gt 0 ]; then
            items+=("$id" "$(printf '%-30s %s of %s' "${PROF_LABEL[$id]}" "$n" "$total")")
            partial+=("${PROF_LABEL[$id]} covers $n of $total")
        else
            hidden+=("${PROF_LABEL[$id]} -- none of your elements")
        fi
    done < <(prof_rank_for_elements "${SPEC[family]}" "${SPEC[xc]}" "${SPEC[rel]}" "${els[@]}")

    # Libraries filtered out by the settings themselves, not by coverage
    for id in $(prof_list_for_family "${SPEC[family]}"); do
        prof_can_generate "$id" "${SPEC[family]}" || continue
        prof_compatible "$id" "${SPEC[family]}" "${SPEC[xc]}" "${SPEC[rel]}" && continue
        hidden+=("${PROF_LABEL[$id]} -- $(prof_incompatible_reason "$id" "${SPEC[family]}" "${SPEC[xc]}" "${SPEC[rel]}")")
    done

    if [ ${#items[@]} -eq 0 ]; then
        local msg
        msg="Nothing can generate $(upper "${SPEC[family]}") with $(upper "$(xc_qe_string "${SPEC[xc]}")"), $(rel_label "${SPEC[rel]}"),\nfor the elements you chose.\n\n"
        for id in "${hidden[@]}"; do msg="$msg  - $id\n"; done
        msg="$msg\nGo back and change the functional, the type, or the elements."
        ui_msg "Nothing matches" "$msg" 20 78
        return 1
    fi

    items+=("about" "Libraries that cannot be generated, and why")
    [ ${#hidden[@]} -gt 0 ] && \
        items+=("hidden" "$(printf '%s hidden by these settings' "${#hidden[@]}")")

    c=$(ui_menu "Library" \
"\n$total element(s), $(upper "${SPEC[family]}"), $(upper "$(xc_qe_string "${SPEC[xc]}")").
The number is how many of your elements each library actually covers.\n" 20 9 "${items[@]}") || return $?

    case $c in
        hidden)
            local tmp; tmp=$(mktemp)
            { printf 'Not offered for this run\n========================\n\n'
              for id in "${hidden[@]}"; do printf '  %s\n' "$id"; done
              printf '\nChange the functional, the type or the elements to see these.\n'
            } > "$tmp"
            ui_text "Hidden libraries" "$tmp" 24 84; rm -f "$tmp"
            ui_pick_profile; return $? ;;
        about)
            ui_profiles_about; ui_pick_profile; return $? ;;
    esac

    SPEC[profile]=$c

    # A partial match is usable, but the user has to agree to it knowingly.
    local -a missing=()
    mapfile -t missing < <(prof_missing_elements "$c" "${SPEC[family]}" "${SPEC[xc]}" "${SPEC[rel]}" "${els[@]}")
    if [ ${#missing[@]} -gt 0 ]; then
        ui_yesno "Partial coverage" \
"${PROF_LABEL[$c]} has no published parameters for:

  ${missing[*]}

Those would be built with PseudoForge's own parameters instead, which is a
different pseudopotential and is labelled 'PSEUDOFORGE' in the report.

Continue anyway?" 17 76 || { ui_pick_profile; return $?; }
    fi

    ui_show_attribution "$c"
    if [ "$c" = pseudoforge-auto ]; then
        ui_msg "Derived profile" \
"${PROF_NOTES[pseudoforge-auto]}

Transferability testing will be forced on for this profile." 14 74
        RUN_LD1_TESTS=1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# ui_pick_engine -- only asked when the choice is real.
#
# Several engines can produce a norm-conserving pseudopotential, and they do not
# produce the same one: ONCVPSP optimises for a plane-wave cutoff, fhi98PP
# follows Hamann or Troullier-Martins, OPIUM fits its own basis and writes nine
# formats.  Where more than one qualifies, that is the user's decision, not a
# default buried in a table.
# ---------------------------------------------------------------------------
ui_pick_engine() {
    local prof=${SPEC[profile]} fam=${SPEC[family]} eng items=() n=0 c preferred
    [ "${SPEC[source]:-local}" = local ] || return 3

    preferred=$(eng_for_profile "$prof" "$fam")

    for eng in "${ENG_ORDER[@]}"; do
        eng_supports_family "$eng" "$fam" || continue
        eng_available "$eng" || continue
        # A library's own decks only run on the engine that wrote them.
        case $prof in
            psl-*|marburg)  [ "$eng" = ld1 ]     || continue ;;
            sg15|pseudodojo|scan-tm) [ "$eng" = oncvpsp ] || [ "$eng" = opium ] || continue ;;
            gbrv|vanderbilt) [ "$eng" = uspp ]   || continue ;;
        esac
        if [ "$eng" = "$preferred" ]; then
            items+=("$eng" "$(printf '%-26s %s' "${ENG_LABEL[$eng]}" 'recommended for this library')")
        else
            items+=("$eng" "$(printf '%-26s %s' "${ENG_LABEL[$eng]}" "writes $(fmt_for_engine "$eng" | tr '\n' ' ')")")
        fi
        n=$((n + 1))
    done

    if [ "$n" -le 1 ]; then
        SPEC[engine]=$preferred
        return 3
    fi

    c=$(ui_menu "Engine" \
"\nMore than one atomic code can produce $(upper "$fam") here, and they do not
produce the same pseudopotential.  The recommended one is the code the
library's own parameters were written for.\n" 18 6 "${items[@]}") || return $?
    SPEC[engine]=$c
    return 0
}

# Why a library is not in the generatable list -- the honest, specific reason.
ui_why_not() {
    local id=$1 eng
    eng=$(eng_for_profile "$id" "${SPEC[family]}")
    if ! eng_supports_family "$eng" "${SPEC[family]}"; then
        printf 'its engine (%s) does not make %s pseudopotentials' \
               "${ENG_LABEL[$eng]}" "$(upper "${SPEC[family]}")"
        return
    fi
    case $(params_kind "$id") in
        analytic)  printf 'published fit coefficients, not generator output' ;;
        selection) printf 'a per-element selection from other libraries' ;;
        none)      printf 'PseudoForge does not know where its generation inputs are published' ;;
        *)
            if ! eng_available "$eng"; then
                printf '%s is not installed (pseudoforge engines build %s)' "${ENG_LABEL[$eng]}" "$eng"
            else
                printf 'no published generation inputs available' 
            fi ;;
    esac
}

# ---------------------------------------------------------------------------
# Element selection
# ---------------------------------------------------------------------------
ui_pick_elements() {
    local c avail n

    # The library has not been chosen yet -- that comes next, and choosing it
    # first is what made the old flow offer libraries that could not make the
    # elements asked for.  What can be answered here is the broader question:
    # which elements *any* library can make with the functional and relativity
    # already selected.
    avail=$(ui_available_elements)
    n=$(printf '%s\n' "$avail" | grep -c . || true)

    while : ; do
        UI_OK_LABEL=Select UI_CANCEL_LABEL=Back
        c=$(ui_menu "Elements" \
"\n$(upper "${SPEC[family]}"), $(upper "$(xc_qe_string "${SPEC[xc]}")"), $(rel_label "${SPEC[rel]}")
can be made for $n element(s).  Which library covers which is decided next.
\nCurrent selection: ${CLI_ELEMENTS:-<none>}\n" 21 9 \
            table     "Pick from the periodic table (by period)" \
            supported "Everything these settings support ($n elements)" \
            preset    "A preset group (transition metals, lanthanides, ...)" \
            type      "Type a selection (Fe,Si,O or 1-36 or block:d)" \
            review    "Review the current selection" \
            finish    "Continue" ) || return 1

        case $c in
            table)     ui_elements_by_period ;;
            supported) CLI_ELEMENTS=$(printf '%s' "$avail" | tr '\n' ' ') ;;
            preset)    ui_elements_preset ;;
            type)      CLI_ELEMENTS=$(ui_input "Element selection" \
"Symbols, names or atomic numbers, comma or space separated.

  Fe,Si,O            explicit
  1-36               atomic-number range
  block:d            s | p | d | f
  series:lanthanide  transition | actinide | halogen | noble | ...
  period:4  group:16
  transition-metals  lanthanides  actinides  main-group  magnetic
  all                everything" "${CLI_ELEMENTS:-}") || true ;;
            review)    ui_review_elements "$avail" ;;
            finish)
                if [ -z "$(trim "${CLI_ELEMENTS:-}")" ]; then
                    ui_msg "Nothing selected" "Choose at least one element." 9 60
                    continue
                fi
                local -a chosen unmakeable
                # shellcheck disable=SC2086
                mapfile -t chosen < <(el_expand ${CLI_ELEMENTS})
                mapfile -t unmakeable < <(
                    for e in "${chosen[@]}"; do
                        printf '%s\n' "$avail" | grep -qx "$e" || printf '%s\n' "$e"
                    done)
                if [ ${#unmakeable[@]} -gt 0 ]; then
                    ui_yesno "Some elements cannot be made" \
"No library can produce these with $(upper "$(xc_qe_string "${SPEC[xc]}")"), $(rel_label "${SPEC[rel]}"):

  ${unmakeable[*]}

They will be reported as skipped.  Drop them and continue with the rest?" 16 74 \
                        && CLI_ELEMENTS=$(
                            for e in "${chosen[@]}"; do
                                printf '%s\n' "$avail" | grep -qx "$e" && printf '%s ' "$e"
                            done)
                fi
                [ -n "$(trim "${CLI_ELEMENTS:-}")" ] || { ui_msg "Nothing left" "Every element was dropped." 9 60; continue; }
                return 0 ;;
        esac
    done
}

# Elements that at least one library can produce under the current settings.
ui_available_elements() {
    local el prof
    for el in "${EL_ORDER[@]}"; do
        for prof in $(prof_list_for_family "${SPEC[family]}"); do
            prof_can_generate "$prof" "${SPEC[family]}" || continue
            if prof_covers_element "$prof" "$el" "${SPEC[family]}" "${SPEC[xc]}" "${SPEC[rel]}"; then
                printf '%s\n' "$el"; break
            fi
        done
    done
}

# Show the current selection against what is actually makeable.
ui_review_elements() {
    local avail=$1 tmp e
    tmp=$(mktemp)
    {
        printf 'Selection\n=========\n\n'
        printf 'settings : %s, %s, %s\n\n' \
            "$(upper "${SPEC[family]}")" "$(upper "$(xc_qe_string "${SPEC[xc]}")")" \
            "$(rel_label "${SPEC[rel]}")"
        printf '%-5s %-4s %-16s %s\n' Z EL NAME 'can be made'
        printf -- '---------------------------------------------------\n'
        # shellcheck disable=SC2086
        for e in $(el_expand ${CLI_ELEMENTS:-}); do
            printf '%-5s %-4s %-16s %s\n' "${EL_Z[$e]}" "$e" "${EL_NAME[$e]}" \
                "$(printf '%s\n' "$avail" | grep -qx "$e" && echo yes || echo 'no -- would be skipped')"
        done
    } > "$tmp"
    ui_text "Selection review" "$tmp" 24 70
    rm -f "$tmp"
}

ui_elements_by_period() {
    # `chosen` is a string built up over the menu loop below; `items` is the
    # array the menu is fed from.  ShellCheck reads the two declarations on
    # adjacent lines as one variable used both ways.  It is not.
    # shellcheck disable=SC2178
    local period s sel chosen=""
    local -a items=()
    period=$(ui_menu "Periodic table" "\nWhich period?\n" 18 8 \
        1 "Period 1  H  He" \
        2 "Period 2  Li .. Ne" \
        3 "Period 3  Na .. Ar" \
        4 "Period 4  K  .. Kr" \
        5 "Period 5  Rb .. Xe" \
        6 "Period 6  Cs .. Rn  (incl. lanthanides)" \
        7 "Period 7  Fr .. Lr  (incl. actinides)" ) || return

    local set; set=$(prof_psl_set "${SPEC[profile]}" "${SPEC[family]}")
    for s in "${EL_ORDER[@]}"; do
        [ "${EL_PERIOD[$s]}" = "$period" ] || continue
        local mark=""
        if [ -n "$set" ] && ! psl_recipes "$set" "$s" | grep -q .; then mark=" (no recipe)"; fi
        local on=off
        case " $CLI_ELEMENTS " in *" $s "*) on=on ;; esac
        items+=("$s" "$(printf 'Z=%-3s %s%s' "${EL_Z[$s]}" "${EL_NAME[$s]}" "$mark")" "$on")
    done
    sel=$(ui_checklist "Period $period" "\nSpace selects, Enter confirms.\n" 22 12 "${items[@]}") || return
    sel=$(ui_unquote "$sel")

    # replace this period's entries, keep the rest of the selection
    local keep="" e
    for e in $CLI_ELEMENTS; do
        e=$(el_canon "$e" 2>/dev/null) || continue
        [ "${EL_PERIOD[$e]}" = "$period" ] || keep="$keep $e"
    done
    CLI_ELEMENTS="$keep $sel"
}

ui_elements_preset() {
    local c
    c=$(ui_menu "Presets" "\nAdd a group to the selection.\n" 20 10 \
        transition-metals "All d-block transition metals" \
        lanthanides       "La .. Lu" \
        actinides         "Ac .. Lr" \
        main-group        "s- and p-block" \
        magnetic          "Cr Mn Fe Co Ni Gd" \
        semiconductors    "Common semiconductor elements" \
        rare-earths       "Lanthanides plus Sc and Y" \
        period:4          "K .. Kr" \
        1-18              "H .. Ar" \
        all               "Every element in the table" ) || return
    CLI_ELEMENTS="$CLI_ELEMENTS $c"
}


# ---------------------------------------------------------------------------
# Advanced / physics settings
# ---------------------------------------------------------------------------
ui_advanced() {
    local c v
    while : ; do
        # Ok opens the highlighted setting; Cancel means "I am finished here"
        # and moves on, which is why this call returns 0 rather than 1.
        UI_OK_LABEL=Edit UI_CANCEL_LABEL=Done
        c=$(ui_menu "Advanced settings" \
"\nEverything here maps onto a real ld1.x variable. Leave it alone to reproduce
the library recipe exactly.\n" 26 18 \
            config    "Atomic configuration      [${SPEC[config]:-recipe default}]" \
            variant   "PSlibrary variant tag     [${SPEC[variant]:-auto}]" \
            author    "Author string in the file [${SPEC[author]:-none}]" \
            corehole  "Core hole (XPS/XAS)       [${SPEC[core_hole]:-none}]" \
            zed       "Fractional nuclear charge [${SPEC[zed]:-recipe default}]" \
            zval      "Valence charge zval       [${SPEC[zval]:-automatic}]" \
            nlcc      "Nonlinear core correction [${SPEC[nlcc]:-recipe default}]" \
            augfun    "Augmentation functions    [${SPEC[which_augfun]:-recipe default}]" \
            lloc      "Local channel lloc/rcloc  [${SPEC[lloc]:-recipe default}]" \
            proj      "Extra projectors          [${SPEC[extra_projectors]:-none}]" \
            rcut      "Cut-off radius scaling    [${SPEC[rcut_scale]:-1.00}]" \
            grid      "Radial grid               [${SPEC[xmin]:-default}]" \
            scf       "SCF controls beta/tr2     [${SPEC[beta]:-default}]" \
            gipaw     "GIPAW reconstruction      [$([ "${SPEC[gipaw]}" = 1 ] && echo on || echo off)]" \
            lsd       "Spin-polarised generation [$([ "${SPEC[lsd]}" = 1 ] && echo on || echo off)]" \
            ncform    "Norm-conserving form      [${SPEC[nc_form]:-separable}]" \
            valid     "Validation and execution options" ) || return 0

        case $c in
        variant)  SPEC[variant]=$(ui_input "PSlibrary variant tag" \
"Pick a specific PSlibrary variant tag rather than the first that matches.

  spn   spin-polarised, non-relativistic
  dn    spin-polarised, scalar-relativistic
  nl    non-relativistic
  ...

Leave empty to let PseudoForge pick the variant the recipe database
supplies for the family, functional and relativity already chosen." 16 74 "${SPEC[variant]}") || true ;;
        author)   SPEC[author]=$(ui_input "Author string" \
"Written into the generated file's author field.  Leave empty to inherit
the recipe's own value, which is the library author and not you." 12 74 "${SPEC[author]}") || true ;;
        config)   SPEC[config]=$(ui_input "Atomic configuration" \
"ld1.x config string, e.g.

  [Ar] 3d7 4s1        transition metal, semicore in the core
  [Ne] 3s2 3p2 3d-2   negative occupation = unbound state used as a projector

Leave empty to keep the recipe's own configuration." 16 74 "${SPEC[config]}") || true ;;
        corehole) SPEC[core_hole]=$(ui_input "Core hole" \
"Shell to remove one electron from, e.g. 1s or 2p.

This builds an XSpectra-style core-hole pseudopotential: the noble-gas
shorthand is expanded, the named shell loses one electron, and you should
set zval yourself to keep the valence charge right.

Leave empty for no core hole." 17 74 "${SPEC[core_hole]}") || true ;;
        zed)      SPEC[zed]=$(ui_input "Fractional nuclear charge" \
"zed for ld1.x. A non-integer value builds a virtual-crystal pseudopotential,
e.g. 13.5 for a 50/50 Al/Si alloy site.

Leave empty for the true nuclear charge." 14 74 "${SPEC[zed]}") || true ;;
        zval)     SPEC[zval]=$(ui_input "Valence charge" \
"Explicit zval. Normally ld1.x works this out from the configuration; set it
by hand for core-hole or fractional-charge pseudopotentials." 12 74 "${SPEC[zval]}") || true ;;
        nlcc)     v=$(ui_menu "Nonlinear core correction" \
"\nNLCC matters for alkali and alkaline-earth metals, transition metals,
lanthanides and actinides, and for any spin-polarised calculation.\n" 16 4 \
                    ""    "Leave the recipe alone (recommended)" \
                    on    "Force NLCC on" \
                    off   "Force NLCC off") && SPEC[nlcc]=$v
                  if [ "${SPEC[nlcc]}" = on ]; then
                      SPEC[rcore]=$(ui_input "NLCC core radius" \
"rcore -- where the pseudo core charge is matched.
Typically 0.7-1.5 bohr. Leave empty for the recipe default." 11 70 "${SPEC[rcore]}") || true
                      SPEC[rho0]=$(ui_input "NLCC core charge rho0" \
"rho0 -- the model core charge at the origin, in electrons per bohr^3.
Leave empty to let ld1.x use the recipe's own value." 11 70 "${SPEC[rho0]}") || true
                  fi ;;
        augfun)   v=$(ui_menu "Augmentation functions" \
"\nHow the US/PAW augmentation charges are represented.\n" 18 6 \
                    ""       "Leave the recipe alone (recommended)" \
                    PSQ      "PSQ     -- pseudised Q, PSlibrary's default" \
                    AE       "AE      -- all-electron Q, hardest and most accurate" \
                    BESSEL   "BESSEL  -- spherical Bessel expansion" \
                    GAUSS    "GAUSS   -- Gaussian expansion" \
                    BG       "BG      -- Bloechl-Gaussian") && SPEC[which_augfun]=$v
                  [ -n "${SPEC[which_augfun]}" ] && SPEC[rmatch_augfun]=$(ui_input "Augmentation matching radius" \
"rmatch_augfun, in bohr. Must sit inside the smallest cut-off radius.
Leave empty for the recipe default." 11 70 "${SPEC[rmatch_augfun]}") ;;
        lloc)     SPEC[lloc]=$(ui_input "Local channel" \
"lloc:
  -1   build the local potential from the all-electron potential (needs rcloc) || return 1
   0   use the s channel as local
   1   use p,  2 use d,  3 use f

Leave empty for the recipe default." 15 74 "${SPEC[lloc]}") || true
                  SPEC[rcloc]=$(ui_input "Local channel radius" \
"rcloc, in bohr. Only used when lloc = -1." 10 70 "${SPEC[rcloc]}") || true ;;
        proj)     SPEC[extra_projectors]=$(ui_input "Extra projectors" \
"Add a second projector in a channel by naming the shell and a reference
energy in Ry, space separated:

  3D:0.5 4P:1.0

More projectors improve transferability at the cost of a harder potential." 15 74 "${SPEC[extra_projectors]}") || true ;;
        rcut)     SPEC[rcut_scale]=$(ui_input "Cut-off radius scaling" \
"Multiply every rcut and rcutus by this factor.

  < 1  harder, more transferable, higher cutoff needed
  > 1  softer, cheaper, less transferable

Leave empty for 1.00." 15 74 "${SPEC[rcut_scale]}") || true ;;
        grid)     v=$(ui_input "Radial grid" \
"xmin:dx:rmax   -- r(i) = exp(xmin + (i-1)*dx) / zed, out to rmax bohr.

Default is about -7.0:0.0125:100.0. Refine dx or extend rmax when the
atomic solver struggles to converge." 14 74 \
                    "${SPEC[xmin]:-}:${SPEC[dx]:-}:${SPEC[rmax]:-}") && {
                        SPEC[xmin]=${v%%:*}
                        SPEC[dx]=$(printf '%s' "$v" | cut -d: -f2)
                        SPEC[rmax]=${v##*:}; } ;;
        scf)      SPEC[beta]=$(ui_input "SCF mixing" \
"beta -- mixing factor for the atomic SCF loop. Lower is slower but steadier;
0.1 often rescues a non-converging heavy element. Default is about 0.2." 12 74 "${SPEC[beta]}") || true
                  SPEC[tr2]=$(ui_input "SCF threshold" "tr2, e.g. 1.0d-14" 9 60 "${SPEC[tr2]}") || true ;;
        gipaw)    if ui_yesno "GIPAW reconstruction" \
"Write the all-electron reconstruction data needed by the GIPAW module for
NMR chemical shifts and EPR g-tensors?

This adds PP_GIPAW blocks to the UPF file and makes it somewhat larger."; then
                      SPEC[gipaw]=1; else SPEC[gipaw]=; fi ;;
        lsd)      if ui_yesno "Spin polarisation" \
"Generate from a spin-polarised atomic configuration (lsd=1)?

Only meaningful for open-shell atoms, and the resulting pseudopotential is
still spin-independent -- this only changes the reference atom."; then
                      SPEC[lsd]=1; else SPEC[lsd]=; fi ;;
        ncform)   v=$(ui_menu "Norm-conserving form" \
"\nHow should the norm-conserving pseudopotential be written?\n" 15 2 \
                    separable "Separable Kleinman-Bylander (pseudotype=2) -- the default" \
                    semilocal "Semilocal (pseudotype=1) -- ghost-free, larger and slower") && SPEC[nc_form]=$v ;;
        valid)    ui_validation_settings ;;

        esac
    done
}

ui_validation_settings() {
    local c v
    while : ; do
        c=$(ui_menu "Validation and execution" "" 20 9 \
            tests   "transferability check          [$([ "${RUN_LD1_TESTS:-1}" = 1 ] && echo on || echo off)]" \
            scan    "pw.x cutoff convergence scan  [$([ "${RUN_CUTOFF_SCAN:-0}" = 1 ] && echo on || echo off)]" \
            ladder  "Cutoff ladder                 [${CUTOFF_SCAN_LIST}]" \
            tol     "Convergence target            [${CUTOFF_TOL_MRY} mRy/atom]" \
            jobs    "Parallel elements             [${MAX_PARALLEL_JOBS}]" \
            autofix "Auto-fix failures             [$([ "${AUTOFIX_ENABLED:-1}" = 1 ] && echo "on, ${AUTOFIX_MAX_ATTEMPTS} attempts" || echo off)]" \
            resume  "Resume finished elements      [$([ "${RESUME:-1}" = 1 ] && echo on || echo off)]" \
            back    "Back" ) || return
        case $c in
            tests)   RUN_LD1_TESTS=$([ "${RUN_LD1_TESTS:-1}" = 1 ] && echo 0 || echo 1) ;;
            scan)    if [ "${RUN_CUTOFF_SCAN:-0}" = 1 ]; then RUN_CUTOFF_SCAN=0
                     else
                         deps_resolve_qe
                         if deps_have_pw; then RUN_CUTOFF_SCAN=1
                         else ui_msg "pw.x not found" "A cutoff scan needs a working pw.x.\n\nSet QE_ROOT_DIR or PW_BIN in $PF_RC first." 11 70; fi
                     fi ;;
            ladder)  v=$(ui_input "Cutoff ladder" "ecutwfc values in Ry, space separated." 10 70 "$CUTOFF_SCAN_LIST") && CUTOFF_SCAN_LIST=$v ;;
            tol)     v=$(ui_input "Convergence target" "Total-energy convergence target in mRy per atom.\n\n1.0 is a normal production target; 0.1 is strict." 12 70 "$CUTOFF_TOL_MRY") && CUTOFF_TOL_MRY=$v ;;
            jobs)    v=$(ui_input "Parallel jobs" "How many elements to process at once." 9 60 "$MAX_PARALLEL_JOBS") && MAX_PARALLEL_JOBS=$v ;;
            autofix) if [ "${AUTOFIX_ENABLED:-1}" = 1 ]; then AUTOFIX_ENABLED=0
                     else AUTOFIX_ENABLED=1
                          v=$(ui_input "Auto-fix attempts" "How many relaxed retries per failing element?" 9 60 "$AUTOFIX_MAX_ATTEMPTS") && AUTOFIX_MAX_ATTEMPTS=$v
                     fi ;;
            resume)  RESUME=$([ "${RESUME:-1}" = 1 ] && echo 0 || echo 1) ;;
            back)    return ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Review and run
# ---------------------------------------------------------------------------
# The command line is built in recipe.sh, not here: the CLI, the wizard's
# review screen and `pseudoforge recipe load` must all show the same command,
# and a second copy in an interface module is how they stop agreeing.
ui_cmdline() { spec_cmdline; }

ui_review_and_run() {
    local n dir tmp
    n=$(el_expand $CLI_ELEMENTS | wc -l | tr -d ' ')
    dir=$(ui_input "Output directory" "Where should this project be written?" 10 74 \
          "$OUTPUT_BASE_DIR/$(project_default_name)") || return
    CLI_OUTPUT=$dir

    tmp=$(mktemp)
    {
        printf 'ABOUT TO GENERATE\n=================\n\n'
        printf '  profile      %s  [%s]\n' "${PROF_LABEL[${SPEC[profile]}]}" "$(prof_badge "${SPEC[profile]}")"
        printf '  family       %s\n' "$(upper "${SPEC[family]}")"
        printf '  functional   %s\n' "$(xc_explain "${SPEC[xc]}")"
        printf '  relativity   %s\n' "$(rel_label "${SPEC[rel]}")"
        printf '  UPF format   v%s\n' "${SPEC[upf]}"
        printf '  source       %s\n' \
            "$([ "${SPEC[source]:-local}" = online ] \
                && echo 'download (official source, then mirror)' \
                || echo "build here with ${ENG_LABEL[${SPEC[engine]:-ld1}]}")"
        printf '  elements     %s\n' "$n"
        printf '  parallel     %s job(s)\n' "$MAX_PARALLEL_JOBS"
        printf '  tests        %s\n' "$([ "${RUN_LD1_TESTS:-1}" = 1 ] && echo "transferability" || echo none)"
        printf '  cutoff scan  %s\n' "$([ "${RUN_CUTOFF_SCAN:-0}" = 1 ] && echo "yes ($CUTOFF_SCAN_LIST Ry)" || echo no)"
        printf '  output       %s\n\n' "$dir"
        printf 'Equivalent command line\n-----------------------\n\n'
        ui_cmdline | fold -s -w 76 | sed 's/^/  /'
        printf '\n\nElements\n--------\n\n'
        el_expand $CLI_ELEMENTS | tr '\n' ' ' | fold -s -w 76 | sed 's/^/  /'
        printf '\n'
    } > "$tmp"
    ui_text "Review" "$tmp" 26 88
    rm -f "$tmp"

    if [ "${SPEC[source]:-local}" = online ]; then
        ui_yesno "Start" "Download $n pseudopotential(s) into

  $dir

PseudoForge tries the official source first, then your mirror, and
offers to generate anything it cannot find." || return 1
    else
        ui_yesno "Start" "Generate $n pseudopotential(s) into

  $dir

This runs ${ENG_LABEL[${SPEC[engine]:-ld1}]} and can take a while." || return 1
    fi

    clear
    cmd_generate
    ui_pause
}

# ---------------------------------------------------------------------------
# Quick generate
# ---------------------------------------------------------------------------
ui_quick() {
    spec_init
    local el
    el=$(ui_input "Quick generate" \
"Element symbol.

Uses your configured defaults:
  ${DEFAULT_PROFILE} / $(upper "${DEFAULT_PSEUDOTYPE}") / ${DEFAULT_XC} / ${DEFAULT_RELATIVITY}" 14 70) || return
    el=$(el_canon "$el") || { ui_msg "Unknown element" "No element matches '$el'." 8 50; return; }
    CLI_ELEMENTS=$el
    CLI_OUTPUT=$OUTPUT_BASE_DIR/$(project_default_name)
    clear
    cmd_generate
    ui_pause
}

# ---------------------------------------------------------------------------
# Browsers
# ---------------------------------------------------------------------------
ui_browse_recipes() {
    local el tmp
    el=$(ui_input "Browse recipes" "Element symbol, name or atomic number." 9 60) || return
    el=$(el_canon "$el") || { ui_msg "Unknown element" "No element matches '$el'." 8 50; return; }
    tmp=$(mktemp)
    {
        printf '%s -- %s\n%s\n\n' "$el" "$(el_describe "$el")" "$(printf '%.0s=' $(seq 1 60))"
        printf 'Ground-state configuration: %s\n' "${EL_CONFIG[$el]}"
        printf 'Covalent radius: %s A     Standard mass: %s\n\n' "${EL_RCOV[$el]}" "${EL_MASS[$el]}"
        printf '%-12s %-16s %-42s\n' SET VARIANT 'FILE NAME PATTERN'
        printf '%s\n' "$(printf '%.0s-' $(seq 1 74))"
        local f sid tag key cond
        for f in "$PF_DATA"/psl/*.index; do
            sid=$(basename "$f" .index)
            while IFS=$'\t' read -r tag key cond; do
                printf '%-12s %-16s %-42s%s\n' "$sid" "$tag" "${key//\{\{FCT\}\}/<fct>}" \
                       "$([ "$cond" = any ] && echo "" || echo "  ($cond only)")"
            done < <(psl_recipes "$sid" "$el")
        done
        printf '\n\nThe variant tag records which semicore shells are in the valence:\n'
        printf '  s / p / d / f  that shell is treated as valence (semicore)\n'
        printf '  n              nonlinear core correction is on\n'
        printf '  l / ll         a softer, lower-cutoff variant of the same valence\n'
    } > "$tmp"
    ui_text "Recipes for $el" "$tmp" 26 92
    rm -f "$tmp"
}

ui_browse_profiles() {
    local items=() id c tmp
    for id in $(prof_list_sorted); do
        items+=("$id" "$(printf '%s%s' "$(prof_star "$id")" "${PROF_LABEL[$id]}")")
    done
    c=$(ui_menu "Library profiles" "\nSelect one to read its description and coverage.\n" 24 15 "${items[@]}") || return
    tmp=$(mktemp)
    { NO_COLOR=1 C_BOLD='' C_RESET='' prof_describe "$c"
      printf '\n'
      if prof_is_generatable "$c" && [ "$c" != pseudoforge-auto ]; then
          local fam set
          for fam in paw us nc; do
              set=$(prof_psl_set "$c" "$fam"); [ -n "$set" ] || continue
              printf '\n%s -- %s elements:\n' "$(upper "$fam")" "$(psl_set_elements "$set" | wc -l | tr -d ' ')"
              psl_set_elements "$set" | tr '\n' ' ' | fold -s -w 70 | sed 's/^/  /'
              printf '\n'
          done
      fi
    } > "$tmp"
    ui_text "$c" "$tmp" 26 92
    rm -f "$tmp"
    ui_browse_profiles
}

ui_browse_xc() {
    local tmp; tmp=$(mktemp)
    {
        printf 'EXCHANGE-CORRELATION FUNCTIONALS\n================================\n\n'
        printf 'ld1.x solves the atom with LDA or GGA only. Meta-GGA, hybrid and\n'
        printf 'van der Waals functionals have no atomic solver in ld1.x, so pseudoforge\n'
        printf 'generates with the accepted semilocal parent and records that fact.\n'
        printf 'Every public pseudopotential library does the same.\n\n'
        local fam id
        for fam in "${XC_FAMILIES[@]}"; do
            printf '\n%s\n%s\n' "$fam" "$(printf '%.0s-' $(seq 1 ${#fam}))"
            for id in $(xc_list_family "$fam"); do
                if xc_is_native "$id"; then
                    printf '  %-14s %-38s dft=%s\n' "$id" "${XC_LABEL[$id]}" "${XC_QE[$id]}"
                else
                    printf '  %-14s %-38s -> %s\n' "$id" "${XC_LABEL[$id]}" "$(xc_qe_string "$id")"
                    [ -n "${XC_NOTE[$id]}" ] && printf '  %-14s   %s\n' "" "${XC_NOTE[$id]}"
                fi
            done
        done
        printf '\n'
    } > "$tmp"
    ui_text "Functionals" "$tmp" 26 96
    rm -f "$tmp"
}

# ---------------------------------------------------------------------------
ui_validate() {
    local path tmp
    path=$(ui_input "Validate UPF files" "Directory or file glob to check." 9 70 "$OUTPUT_BASE_DIR") || return
    tmp=$(mktemp)
    local f found=0
    {
        for f in $path $path/*.UPF $path/*.upf; do
            [ -f "$f" ] || continue
            found=1
            local problems; problems=$(upf_validate "$f")
            if [ -z "$problems" ]; then
                printf '[ ok ]  %-44s %s\n' "$(basename "$f")" "$(upf_summary "$f")"
            else
                printf '[fail]  %s\n' "$(basename "$f")"
                printf '%s\n' "$problems" | sed 's/^/          /'
            fi
        done
        [ "$found" = 1 ] || printf 'No UPF files found under %s\n' "$path"
    } > "$tmp"
    ui_text "Validation results" "$tmp" 26 96
    rm -f "$tmp"
}

ui_import() {
    local src
    src=$(ui_input "Import a library" \
"Directory containing .UPF files from another library (SG15, GBRV,
PseudoDojo, SSSP, ...).

PseudoForge will copy them into a project, validate every file, and -- if you
enable the cutoff scan -- run pw.x convergence tests on them." 16 74) || return
    [ -d "$src" ] || { ui_msg "Not a directory" "$src" 8 60; return; }
    clear
    cmd_import "$src"
    ui_pause
}

ui_reports() {
    local items=() d c
    for d in "$OUTPUT_BASE_DIR"/*/; do
        [ -f "$d/state.tsv" ] || continue
        items+=("${d%/}" "$(awk -F'\t' '!/^#/&&NF{n++} END{printf "%d elements", n+0}' "$d/state.tsv")")
    done
    [ ${#items[@]} -gt 0 ] || { ui_msg "No projects" "No PseudoForge projects found under\n\n  $OUTPUT_BASE_DIR" 10 70; return; }
    c=$(ui_menu "Projects" "\nSelect a project to rebuild and view its report.\n" 22 12 "${items[@]}") || return
    cmd_report "$c" >/dev/null 2>&1
    ui_text "$(basename "$c")" "$c/reports/summary.txt" 26 100
}

ui_settings() {
    local c v
    while : ; do
        c=$(ui_menu "Settings" "\nStored in $PF_RC\n" 22 12 \
            qe      "QE_ROOT_DIR        [${QE_ROOT_DIR:-not set}]" \
            ld1     "LD1_BIN            [${LD1_BIN:-not set}]" \
            pw      "PW_BIN             [${PW_BIN:-not set}]" \
            para    "PARA_PREFIX        [${PARA_PREFIX:-none}]" \
            out     "OUTPUT_BASE_DIR    [${OUTPUT_BASE_DIR}]" \
            scratch "SCRATCH_DIR        [${SCRATCH_DIR}]" \
            jobs    "MAX_PARALLEL_JOBS  [${MAX_PARALLEL_JOBS}]" \
            author  "AUTHOR             [${AUTHOR}]" \
            defs    "Generation defaults" \
            edit    "Edit $PF_RC in \$EDITOR" \
            back    "Back" ) || return
        case $c in
            qe)      v=$(ui_input "QE_ROOT_DIR" "Root of your Quantum ESPRESSO installation.\nld1.x and pw.x are expected in <root>/bin." 11 70 "$QE_ROOT_DIR") && {
                         pf_config_set QE_ROOT_DIR "$v"
                         pf_config_set LD1_BIN "$v/bin/ld1.x"
                         pf_config_set PW_BIN  "$v/bin/pw.x"; } ;;
            ld1)     v=$(ui_input "LD1_BIN" "Full path to ld1.x" 9 70 "$LD1_BIN") && pf_config_set LD1_BIN "$v" ;;
            pw)      v=$(ui_input "PW_BIN"  "Full path to pw.x"  9 70 "$PW_BIN")  && pf_config_set PW_BIN "$v" ;;
            para)    v=$(ui_input "PARA_PREFIX" "Parallel launcher for pw.x, e.g.\n\n  mpirun -np 8\n\nLeave empty for serial runs." 13 70 "$PARA_PREFIX") && pf_config_set PARA_PREFIX "$v" ;;
            out)     v=$(ui_input "OUTPUT_BASE_DIR" "Where new projects are created." 9 70 "$OUTPUT_BASE_DIR") && pf_config_set OUTPUT_BASE_DIR "$v" ;;
            scratch) v=$(ui_input "SCRATCH_DIR" "Scratch space for QE temporary files." 9 70 "$SCRATCH_DIR") && pf_config_set SCRATCH_DIR "$v" ;;
            jobs)    v=$(ui_input "MAX_PARALLEL_JOBS" "Elements to process concurrently." 9 60 "$MAX_PARALLEL_JOBS") && pf_config_set MAX_PARALLEL_JOBS "$v" ;;
            author)  v=$(ui_input "AUTHOR" "Written into the author field of every generated UPF." 9 70 "$AUTHOR") && pf_config_set AUTHOR "$v" ;;
            defs)    ui_settings_defaults ;;
            edit)    clear; "${EDITOR:-vi}" "$PF_RC"; pf_config_load ;;
            back)    return ;;
        esac
    done
}

ui_settings_defaults() {
    local c v
    while : ; do
        c=$(ui_menu "Generation defaults" "" 18 7 \
            type "DEFAULT_PSEUDOTYPE  [${DEFAULT_PSEUDOTYPE}]" \
            xc   "DEFAULT_XC          [${DEFAULT_XC}]" \
            rel  "DEFAULT_RELATIVITY  [${DEFAULT_RELATIVITY}]" \
            prof "DEFAULT_PROFILE     [${DEFAULT_PROFILE}]" \
            upf  "DEFAULT_UPF_VERSION [v${DEFAULT_UPF_VERSION}]" \
            back "Back" ) || return
        case $c in
            type) v=$(ui_menu "Default type" "" 12 3 paw PAW us Ultrasoft nc Norm-conserving) && pf_config_set DEFAULT_PSEUDOTYPE "$v" ;;
            xc)   v=$(ui_input "Default functional" "e.g. PBE, PBEsol, PZ" 9 60 "$DEFAULT_XC") && pf_config_set DEFAULT_XC "$v" ;;
            rel)  v=$(ui_menu "Default relativity" "" 12 3 scalar Scalar full Full nonrel None) && pf_config_set DEFAULT_RELATIVITY "$v" ;;
            prof)
                local -a _prof_items=()
                while IFS= read -r id; do
                    prof_is_generatable "$id" || continue
                    _prof_items+=("$id" "${PROF_LABEL[$id]// /_}")
                done < <(prof_list)
                v=$(ui_menu "Default profile" "" 16 6 "${_prof_items[@]}") \
                    && pf_config_set DEFAULT_PROFILE "$v" ;;
            back) return ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Show what the chosen library costs you in attribution, before any work is
# done.  A licence that does not suit your project is worth knowing about now
# rather than after a two-hour run.
# ---------------------------------------------------------------------------
ui_show_attribution() {
    local prof=$1 eng tmp id
    eng=$(eng_for_profile "$prof" "${SPEC[family]}")
    tmp=$(mktemp)
    {
        printf 'Attribution for %s\n' "${PROF_LABEL[$prof]:-$prof}"
        printf '=================================================================\n\n'
        printf 'Licence : %s\n' "$(md_license "$prof")"
        [ -n "${MD_LICENSE_URL[$prof]:-}" ] && printf 'Terms   : %s\n' "${MD_LICENSE_URL[$prof]}"
        [ -n "${MD_OFFICIAL_URL[$prof]:-}" ] && printf 'Source  : %s\n' "${MD_OFFICIAL_URL[$prof]}"
        printf '\nCite:\n\n'
        local n=0
        while read -r id; do
            [ -n "$id" ] || continue
            n=$((n + 1))
            printf '  [%d] %s\n' "$n" "$(md_citation "$id")"
            local u; u=$(md_doi_url "$id")
            [ -n "$u" ] && printf '      %s\n' "$u"
            printf '\n'
        done < <(md_citation_set "$prof" "$eng")
        [ "$n" = 0 ] && printf '  PseudoForge has no verified citation for this library.\n  Check the distribution before citing it.\n\n'
        [ -n "${MD_NOTE[$prof]:-}" ] && printf 'Note: %s\n\n' "${MD_NOTE[$prof]}"
        printf -- '-----------------------------------------------------------------\n'
        printf 'PseudoForge writes this into pseudos/CITATION.txt and the licence terms\n'
        printf 'into pseudos/LICENSE.txt, beside the generated files.\n'
    } > "$tmp"
    ui_text "Licence and citation" "$tmp" 24 84
    rm -f "$tmp"
}
# ---------------------------------------------------------------------------
# Output format.  Only shown when the chosen engine can write more than one:
# for ld1 there is nothing to decide, and a screen with one option is noise.
# ---------------------------------------------------------------------------
ui_pick_format() {
    # Load in *this* shell: fmt_for_engine below runs in a process substitution,
    # and anything it populates there is lost when that subshell exits.
    pf_formats_load
    local eng=${SPEC[engine]:-ld1} id items=() n=0 c
    [ "${SPEC[source]:-local}" = local ] || return 3

    while read -r id; do
        [ -n "$id" ] || continue
        items+=("$id" "$(printf '%-9s %s' "$id" "${FMT_LABEL[$id]:-$id}")")
        n=$((n + 1))
    done < <(fmt_for_engine "$eng")

    # One format means no menu; set the SPEC and skip.  The old code
    # returned without touching SPEC[formats], so a profile whose engine
    # writes a non-upf format alone (fhi98pp writes cpi, adpack writes
    # openmx) ended up with the spec_init default `upf` and was refused
    # downstream.  Setting what the engine actually writes is what the
    # user would have picked from a single-item menu.
    if [ "$n" -le 1 ]; then
        SPEC[formats]=$(fmt_for_engine "$eng")
        return 3
    fi

    items+=("more" "Several formats at once")
    c=$(ui_menu "Output format" \
"\n${ENG_LABEL[$eng]} writes ${n} formats from a single solve, so asking for
more than one costs nothing extra.\n" 20 10 "${items[@]}") || return $?

    if [ "$c" = more ]; then
        local sel=() on
        for id in $(fmt_for_engine "$eng"); do
            on=off; [ "$id" = upf ] && on=on
            sel+=("$id" "${FMT_LABEL[$id]:-$id}" "$on")
        done
        c=$(ui_checklist "Output formats" \
"\nSpace toggles, Enter accepts.  All of them come from the one run.\n" \
            22 12 "${sel[@]}") || return $?
        c=$(ui_unquote "$c")
        [ -n "$(trim "$c")" ] || c=upf
    fi
    SPEC[formats]=$(trim "$c")
    return 0
}
