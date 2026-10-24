# shellcheck shell=bash
# ---------------------------------------------------------------------------
# wizard.sh -- the guided flow.
#
# The old TUI was a tree of menus: you had to know what you wanted before you
# could find it.  The wizard asks instead, in the order the decisions actually
# depend on each other:
#
#   1. what kind of pseudopotential   (NC / US / PAW)
#   2. which functional               (filtered to what the engines can do)
#   3. which library                  (filtered to what supports 1 and 2)
#   4. download it, or build it here
#   5. if building: is the engine present?  install it if not
#   6. run, with a progress bar and per-element failure isolation
#   7. offer validation, then write the reports
#
# Every screen carries the consequence of the choice, not just its name, and
# nothing is hidden behind a menu the user has to guess at.  Falls back to a
# plain-text flow when whiptail is absent.
# ---------------------------------------------------------------------------

WIZ_BACKEND=
WIZ_HEIGHT=22
WIZ_WIDTH=78
WIZ_LIST=13

wiz_init() {
    # PF_FORCE_TEXT makes the plain-text flow testable on a machine that has
    # whiptail installed.
    if [ -n "${PF_FORCE_TEXT:-}" ]; then WIZ_BACKEND=text; return 0; fi
    WIZ_BACKEND=$(deps_tui_backend 2>/dev/null || echo text)
}

# ---------------------------------------------------------------------------
# Thin wrappers so the flow reads the same whether we have whiptail or not.
# ---------------------------------------------------------------------------

# wiz_menu <title> <text> <tag> <item> [<tag> <item>...] -> chosen tag
wiz_menu() {
    local title=$1 text=$2; shift 2
    if [ "$WIZ_BACKEND" = text ]; then
        wiz_menu_text "$title" "$text" "$@"
        return $?
    fi
    "$WIZ_BACKEND" --title "$title" --notags --menu "$text" \
        "$WIZ_HEIGHT" "$WIZ_WIDTH" "$WIZ_LIST" "$@" 3>&1 1>&2 2>&3
}

wiz_menu_text() {
    local title=$1 text=$2; shift 2
    local -a tags=() items=()
    while [ $# -gt 1 ]; do tags+=("$1"); items+=("$2"); shift 2; done
    {
        printf '\n%s== %s ==%s\n' "$C_BOLD$C_CYAN" "$title" "$C_RESET"
        printf '%s\n\n' "$text"
        local i
        for i in "${!tags[@]}"; do
            printf '  %2d) %s\n' "$((i + 1))" "${items[$i]}"
        done
        printf '\nChoice [1-%d]: ' "${#tags[@]}"
    } >&2
    local reply
    read -r reply
    case $reply in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$reply" -ge 1 ] && [ "$reply" -le "${#tags[@]}" ] || return 1
    printf '%s\n' "${tags[$((reply - 1))]}"
}

wiz_yesno() {   # wiz_yesno <title> <question> [default-no]
    local title=$1 q=$2 defno=${3:-}
    if [ "$WIZ_BACKEND" = text ]; then
        local reply prompt='[Y/n]'
        [ -n "$defno" ] && prompt='[y/N]'
        printf '\n%s\n%s ' "$q" "$prompt" >&2
        read -r reply
        case $reply in
            y|Y|yes|YES) return 0 ;;
            n|N|no|NO)   return 1 ;;
            '')          [ -z "$defno" ] && return 0 || return 1 ;;
            *)           return 1 ;;
        esac
    fi
    local extra=()
    [ -n "$defno" ] && extra=(--defaultno)
    "$WIZ_BACKEND" --title "$title" "${extra[@]}" --yesno "$q" 14 "$WIZ_WIDTH"
}

wiz_input() {   # wiz_input <title> <prompt> <default>
    local title=$1 prompt=$2 def=$3
    if [ "$WIZ_BACKEND" = text ]; then
        local reply
        printf '\n%s\n[%s]: ' "$prompt" "$def" >&2
        read -r reply
        printf '%s\n' "${reply:-$def}"
        return 0
    fi
    "$WIZ_BACKEND" --title "$title" --inputbox "$prompt" 12 "$WIZ_WIDTH" "$def" 3>&1 1>&2 2>&3
}

wiz_msg() {     # wiz_msg <title> <text>
    local title=$1 text=$2
    if [ "$WIZ_BACKEND" = text ]; then
        printf '\n%s%s%s\n%s\n' "$C_BOLD" "$title" "$C_RESET" "$text" >&2
        return 0
    fi
    "$WIZ_BACKEND" --title "$title" --msgbox "$text" 18 "$WIZ_WIDTH"
}

# ---------------------------------------------------------------------------
# Step 1 -- what kind of pseudopotential
# ---------------------------------------------------------------------------
wiz_step_family() {
    local choice
    choice=$(wiz_menu "Step 1 of 6: pseudopotential type" \
"What kind of pseudopotential do you need?

PAW keeps the most physics and is the usual choice for magnetism, NMR
and anything needing the all-electron density back.  Ultrasoft is the
cheapest to run.  Norm-conserving is the most portable, and the only
option some codes and some functionals accept." \
        paw "PAW          -- most accurate, moderate cutoff, QE/VASP-style" \
        us  "Ultrasoft    -- lowest cutoff, cheapest plane-wave runs" \
        nc  "Norm-conserving -- most portable, needed for hybrids/TDDFT/phonons") || return 1
    SPEC[family]=$choice
}

# ---------------------------------------------------------------------------
# Step 2 -- functional
# ---------------------------------------------------------------------------
wiz_step_xc() {
    local -a opts=()
    local id
    for id in pbe pbesol pz revpbe blyp scan r2scan hse pbe0 vdw-df; do
        xc_exists "$id" || continue
        if xc_is_native "$id"; then
            opts+=("$id" "$(printf '%-10s %s' "${XC_LABEL[$id]}" "-- generated directly")")
        else
            opts+=("$id" "$(printf '%-10s %s' "${XC_LABEL[$id]}" "-- via ${XC_LABEL[$(xc_generator "$id")]}")")
        fi
    done
    opts+=(more "Something else (show the full list)")

    local choice
    choice=$(wiz_menu "Step 2 of 6: exchange-correlation functional" \
"Which functional will you run with?

Atomic generators only solve LDA and GGA.  Pick a meta-GGA, a hybrid or
a van der Waals functional and pseudoforge generates with its accepted
semilocal parent and records that in the file and in the report -- which
is what every published library does." "${opts[@]}") || return 1

    if [ "$choice" = more ]; then
        local -a all=()
        for id in "${XC_ORDER[@]}"; do
            all+=("$id" "$(printf '%-12s %-8s %s' "$id" "${XC_FAMILY[$id]}" "${XC_LABEL[$id]}")")
        done
        choice=$(wiz_menu "All functionals" "Every functional PseudoForge knows:" "${all[@]}") || return 1
    fi
    SPEC[xc]=$choice

    if ! xc_is_native "$choice"; then
        wiz_msg "How ${XC_LABEL[$choice]} will be handled" \
"$(xc_explain "$choice")

The file PseudoForge writes is genuinely a $(upper "$(xc_qe_string "$choice")") pseudopotential.
That is deliberate and it is what you want: use it for your
${XC_LABEL[$choice]} calculation and cite it as such."
    fi
}

# ---------------------------------------------------------------------------
# Step 3 -- relativity
# ---------------------------------------------------------------------------
wiz_step_rel() {
    local choice
    choice=$(wiz_menu "Step 3 of 6: relativity" \
"How should the atom be solved?

Scalar-relativistic is the right answer for almost everything.  Full
relativistic treatment adds j-dependent projectors and is required for
spin-orbit calculations -- worth the extra cost above roughly Z=37
(rubidium), and unnecessary below it." \
        scalar "Scalar-relativistic -- the usual choice" \
        full   "Full-relativistic   -- with spin-orbit (j-dependent projectors)" \
        nonrel "Non-relativistic    -- light elements, or for comparison") || return 1
    SPEC[rel]=$choice
}

# ---------------------------------------------------------------------------
# Step 3 -- library
# ---------------------------------------------------------------------------
wiz_step_profile() {
    local -a opts=()
    local p badge eng cov
    for p in $(prof_list_for_family "${SPEC[family]}"); do
        prof_can_generate "$p" "${SPEC[family]}" || continue
        badge=$(prof_badge "$p")
        eng=$(eng_for_profile "$p" "${SPEC[family]}")
        case $badge in
            generated) cov="generate here with ${ENG_LABEL[$eng]}" ;;
            derived)   cov="PseudoForge's own construction" ;;
            *)         cov="download or import; $(eng_available "$eng" && echo "or rebuild with ${ENG_LABEL[$eng]}" || echo "engine not installed")" ;;
        esac
        opts+=("$p" "$(printf '%-14s %s' "${PROF_LABEL[$p]:0:32}" "-- $cov")")
    done
    [ ${#opts[@]} -gt 0 ] || {
        wiz_msg "Nothing available" \
"No library in PseudoForge offers ${SPEC[family]} pseudopotentials."
        return 1
    }

    local choice
    choice=$(wiz_menu "Step 4 of 6: library" \
"Which library or standard?

\"generate here\" means PseudoForge reproduces that library's own recipes
with an atomic code on this machine.  \"download or import\" means the
library is made by a generator whose published parameters PseudoForge will
not invent -- so it fetches the real files instead." "${opts[@]}") || return 1
    SPEC[profile]=$choice
    SPEC[engine]=$(eng_for_profile "$choice" "${SPEC[family]}")

    # Same information the full-screen flow shows: licence and citation before
    # any work starts, not after.
    local id n=0 body=""
    body="Licence : $(md_license "$choice")"
    [ -n "${MD_OFFICIAL_URL[$choice]:-}" ] && body="$body
Source  : ${MD_OFFICIAL_URL[$choice]}"
    body="$body

Cite:"
    while read -r id; do
        [ -n "$id" ] || continue
        n=$((n + 1))
        body="$body
  [$n] $(md_citation "$id")"
    done < <(md_citation_set "$choice" "${SPEC[engine]}")
    [ "$n" = 0 ] && body="$body
  PseudoForge has no verified citation for this library -- check the distribution."
    wiz_msg "Licence and citation" "$body"
}

# ---------------------------------------------------------------------------
# Step 4 -- download or build
# ---------------------------------------------------------------------------
wiz_step_source() {
    local prof=${SPEC[profile]} eng=${SPEC[engine]} choice
    local can_generate=no
    prof_is_generatable "$prof" && can_generate=yes

    local build_line
    if eng_available "$eng"; then
        build_line="Build here     -- ${ENG_LABEL[$eng]} is installed and ready"
    else
        build_line="Build here     -- needs ${ENG_LABEL[$eng]}, which PseudoForge can install"
    fi
    [ "$can_generate" = no ] && \
        build_line="Build here     -- PseudoForge will not invent ${PROF_LABEL[$prof]} parameters"

    choice=$(wiz_menu "Step 5 of 6: where should the files come from?" \
"PseudoForge can either fetch a published, already-tested file, or build one
on this machine.

Downloading is usually the better default: published tables have been
through far more testing than a fresh local run.  Build locally when you
need a setting nobody publishes -- a core hole, a different valence, an
unusual functional." \
        online "Download       -- mirror first, then the library's own site" \
        local  "$build_line") || return 1
    SPEC[source]=$choice

    if [ "$choice" = local ] && [ "$can_generate" = no ]; then
        wiz_msg "That is not something PseudoForge will fake" \
"${PROF_LABEL[$prof]} is produced by ${PROF_GENERATOR[$prof]}, and what makes it
that library is its published table of cut-off radii and projectors --
not the code that consumed them.

PseudoForge can run ${ENG_LABEL[$eng]} for you, but the result would be a
PseudoForge pseudopotential, not a ${PROF_LABEL[$prof]} one, and it would be
labelled that way.

If you have the library's own input files, point PseudoForge at them with
--params <dir> and you will get a real reproduction.  Otherwise download
the finished files."
        wiz_yesno "Continue?" "Generate with PseudoForge's own parameters anyway?" defno || return 1
        SPEC[profile]=pseudoforge-auto
    fi
}

# ---------------------------------------------------------------------------
# Step 5 -- make sure the engine is there
# ---------------------------------------------------------------------------
wiz_step_engine() {
    local eng=${SPEC[engine]} state detail choice
    [ "${SPEC[source]}" = local ] || return 0

    eng_available "$eng" && return 0
    IFS=$'\t' read -r state detail < <(eng_status "$eng")

    if [ "$eng" = ld1 ]; then
        if pf_ask_install_ld1; then
            return 0
        fi
        return 1
    fi

    choice=$(wiz_menu "${ENG_LABEL[$eng]} is not installed" \
"Building ${PROF_LABEL[${SPEC[profile]}]} here needs ${ENG_LABEL[$eng]},
and PseudoForge cannot find it.

Source archive: $detail

Auto-install compiles it from that source into
$(eng_bindir) and records the path in $PF_RC.
It needs a Fortran compiler and BLAS/LAPACK; PseudoForge will ask before
installing anything with your package manager." \
        install "Auto-install   -- compile it now (a minute or two)" \
        manual  "Enter a path   -- I already have it somewhere" \
        cancel  "Cancel         -- go back") || return 1

    case $choice in
        install)
            banner "Installing ${ENG_LABEL[$eng]}"
            build_engine "$eng" || {
                wiz_msg "Build failed" \
"${ENG_LABEL[$eng]} did not build.  The log is at
$(eng_builddir)/$eng-build.log

You can still download published files for this library."
                return 1
            }
            ;;
        manual)
            local path
            path=$(wiz_input "Path to ${ENG_BINARIES[$eng]%% *}" \
                "Full path to the ${ENG_BINARIES[$eng]%% *} binary, or the directory holding it:" \
                "$(eng_bindir)") || return 1
            printf -v "${ENG_BIN_VAR[$eng]}" '%s' "$path"
            if eng_available "$eng"; then
                pf_config_set "${ENG_BIN_VAR[$eng]}" "$path"
                ok "${ENG_LABEL[$eng]}: $(eng_resolve "$eng")"
            else
                wiz_msg "Not found" "Nothing executable at $path"
                return 1
            fi
            ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Elements
# ---------------------------------------------------------------------------
wiz_step_elements() {
    local spec
    spec=$(wiz_input "Step 6 of 6: elements" \
"Which elements?

  Si Fe O          symbols, names or atomic numbers
  1-18             a range of Z
  transition-metals, lanthanides, main-group, all
  all !lanthanides  exclusions with a leading !" \
        "${WIZ_ELEMENTS:-Si}") || return 1
    [ -n "$spec" ] || return 1
    # shellcheck disable=SC2086
    WIZ_ELEMENT_LIST=$(el_expand $spec | tr '\n' ' ')
    [ -n "$(trim "$WIZ_ELEMENT_LIST")" ] || {
        wiz_msg "Nothing selected" "'$spec' did not match any element."
        return 1
    }
    WIZ_ELEMENTS=$spec
}

# ---------------------------------------------------------------------------
# Confirmation -- show what is about to happen, in physics terms
# ---------------------------------------------------------------------------
wiz_confirm() {
    local n eng_label
    n=$(printf '%s\n' $WIZ_ELEMENT_LIST | grep -c .)
    eng_label=${ENG_LABEL[${SPEC[engine]}]:-n/a}

    local xc_line
    if xc_is_native "${SPEC[xc]}"; then
        xc_line="${XC_LABEL[${SPEC[xc]}]} (generated directly)"
    else
        xc_line="${XC_LABEL[${SPEC[xc]}]} via ${XC_LABEL[$(xc_generator "${SPEC[xc]}")]}"
    fi

    wiz_yesno "Ready" \
"  type        : $(upper "${SPEC[family]}")
  functional  : $xc_line
  relativity  : $(rel_label "${SPEC[rel]}")
  library     : ${PROF_LABEL[${SPEC[profile]}]}
  source      : $([ "${SPEC[source]}" = online ] && echo "download" || echo "build here with $eng_label")
  elements    : $n  ($(printf '%s' "$WIZ_ELEMENT_LIST" | cut -c1-46))
  output      : ${WIZ_OUTPUT:-$OUTPUT_BASE_DIR/...}

Go ahead?"
}

# ---------------------------------------------------------------------------
# Post-run validation prompt
# ---------------------------------------------------------------------------
wiz_step_validate() {
    local project=$1 ok_count
    ok_count=$(state_count ok)
    [ "${ok_count:-0}" -gt 0 ] || return 0

    wiz_yesno "Validation" \
"$ok_count pseudopotential(s) generated.

Validation runs two independent checks:

  transferability  re-solves the atom in configurations it was not
                   fitted to and compares against all-electron.  Fast.

  cutoff scan      runs pw.x over a ladder of cutoffs to find where the
                   energy stops moving.  This is what tells you the
                   ecutwfc to put in your input file.  Slower.

Run them now?" || return 0

    RUN_LD1_TESTS=1
    if deps_have_pw; then
        if wiz_yesno "Cutoff scan" \
"Also run the pw.x cutoff scan?

This is the slow one -- a handful of small SCF runs per element." defno; then
            RUN_CUTOFF_SCAN=1
        fi
    else
        warn "pw.x not found; skipping the cutoff scan"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# wizard_main -- the whole flow
# ---------------------------------------------------------------------------
wizard_main() {
    wiz_init
    pf_engines_load

    spec_init
    SPEC[source]=${DEFAULT_SOURCE:-local}

    wiz_step_family   || { info "cancelled"; return 1; }
    wiz_step_xc       || { info "cancelled"; return 1; }
    wiz_step_rel      || { info "cancelled"; return 1; }
    wiz_step_profile  || { info "cancelled"; return 1; }
    wiz_step_source   || { info "cancelled"; return 1; }
    wiz_step_engine   || { info "cancelled"; return 1; }
    wiz_step_elements || { info "cancelled"; return 1; }

    # A heavy element with a scalar-relativistic pseudopotential is a common and
    # quiet mistake, so say something rather than let it pass.
    local e
    for e in $WIZ_ELEMENT_LIST; do
        if el_needs_soc "$e" && [ "$(rel_canon "${SPEC[rel]}")" != full ]; then
            wiz_msg "Worth checking" \
"$e is heavy enough that spin-orbit coupling is often significant, and
you chose $(rel_label "${SPEC[rel]}").

That is fine if you will not switch spin-orbit on.  If you will, go back
and choose full-relativistic: a scalar pseudopotential carries no
j-dependent projectors for it to use."
            break
        fi
    done

    WIZ_OUTPUT=$(wiz_input "Output directory" "Where should the project go?" \
        "$OUTPUT_BASE_DIR/$(project_default_name)") || return 1

    wiz_confirm || { info "cancelled"; return 1; }

    recipe_apply_auto_suffix
    project_init "$WIZ_OUTPUT"
    # shellcheck disable=SC2086
    project_write_manifest $WIZ_ELEMENT_LIST

    local rc=0
    # shellcheck disable=SC2086
    if [ "${SPEC[source]}" = online ]; then
        run_online_batch $WIZ_ELEMENT_LIST || rc=$?
    else
        run_batch $WIZ_ELEMENT_LIST || rc=$?
    fi
    # shellcheck disable=SC2086
    label_verify_batch $WIZ_ELEMENT_LIST

    if wiz_step_validate "$PROJECT_DIR"; then
        # shellcheck disable=SC2086
        validate_batch $WIZ_ELEMENT_LIST
    fi

    report_all

    wiz_msg "Done" \
"Project: $PROJECT_DIR

  pseudos/   the .UPF files
  reports/   summary.txt, summary.csv, summary.json, summary.html
  logs/      one log per element

To use them, point pseudo_dir at $PROJECT_DIR/pseudos"
    return $rc
}
