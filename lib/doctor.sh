# shellcheck shell=bash
# ---------------------------------------------------------------------------
# doctor.sh -- what is installed, what is missing, what to run about it.
#
# The checks live here and produce *records*.  Nothing in this file prints:
# rendering belongs to the interface, and there are three of them.  Before this
# split, cmd_doctor interleaved `printf` with the checks themselves, so the TUI
# could not show the same information in a panel and the web API could not
# return it as JSON without running the checks a second time and scraping the
# output.
#
# One record per line, tab-separated:
#
#     <category>  <name>  <status>  <detail>  <fix>
#
#   category  toolchain | buildtool | library | engine | database | path
#   status    ok | missing | optional | info
#   detail    what was found, or why it is not there
#   fix       the exact command that resolves it, empty when nothing to do
#
# `fix` is a field rather than prose so an interface can offer it as a button,
# a menu entry or a JSON action without parsing a sentence.
# ---------------------------------------------------------------------------

# doctor_record <category> <name> <status> <detail> [fix]
doctor_record() {
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "${5:-}"
}

# ---------------------------------------------------------------------------
# doctor_checks -- every check, as records on stdout.
#
# Callers read this as data.  It reports nothing through the sink: a check that
# found something missing is a finding, not a warning, and whether that
# deserves a yellow line is the interface's decision.
# ---------------------------------------------------------------------------
doctor_checks() {
    pf_engines_load
    pf_manifest_load 2>/dev/null || true
    local prefix t c eng state detail
    prefix=$(eng_prefix)

    doctor_record path "engine prefix" info "$prefix" ""
    doctor_record path "bundled data"  info "$PF_DATA" ""

    for t in gfortran gcc make awk sed; do
        if have "$t"; then
            doctor_record toolchain "$t" ok "$(command -v "$t")" ""
        else
            local deb_pkg=$t fed_pkg=$t arch_pkg=$t brew_pkg=$t
            case $t in
                gfortran) fed_pkg="gcc-gfortran"; arch_pkg="gcc-fortran"; brew_pkg="gcc" ;;
                awk)      deb_pkg="gawk"; fed_pkg="gawk"; arch_pkg="gawk"; brew_pkg="gawk" ;;
                sed)      brew_pkg="gnu-sed" ;;
            esac
            doctor_record toolchain "$t" missing "not on PATH" \
                "$(pf_dep_fix "$t" "$deb_pkg" "$fed_pkg" "$arch_pkg" "$brew_pkg")"
        fi
    done

    if have unzip; then
        doctor_record toolchain "unzip" ok "$(command -v unzip)" ""
    else
        doctor_record toolchain "unzip" missing "needed to extract engine archives" \
            "$(pf_dep_fix "unzip" "unzip" "unzip" "unzip" "unzip")"
    fi

    if have python3; then
        doctor_record toolchain "python3" ok "$(command -v python3)" ""
    else
        doctor_record toolchain "python3" optional "needed by opium patch script" \
            "$(pf_dep_fix "python3" "python3" "python3" "python" "python3")"
    fi

    # Plotting is optional in the strong sense: with no backend, --plot prints
    # what it would have drawn and the run is otherwise identical.  So this is
    # a note, never a problem.
    case $(plot_backend 2>/dev/null) in
        none|'') doctor_record plotting backend optional \
                     "none: --plot will say so and carry on" \
                     "$(pf_dep_fix "gnuplot" "gnuplot" "gnuplot" "gnuplot" "gnuplot")" ;;
        *)       doctor_record plotting backend ok "$(plot_backend_label)" "" ;;
    esac

    # cmake and ninja are fetched on demand, so their absence is not a problem
    # to solve -- it is a note.
    if c=$(build_find_cmake 2>/dev/null); then
        doctor_record buildtool cmake ok "$c" ""
    else
        doctor_record buildtool cmake optional "fetched when an engine needs it" ""
    fi
    if c=$(build_find_ninja 2>/dev/null); then
        doctor_record buildtool ninja ok "$c" ""
    else
        doctor_record buildtool ninja optional "fetched when APE needs it" ""
    fi

    if build_have_lapack 2>/dev/null; then
        doctor_record library "BLAS/LAPACK" ok "system LAPACK/BLAS" ""
    else
        doctor_record library "BLAS/LAPACK" missing "needed to link ONCVPSP" \
            "$(pf_dep_fix "BLAS/LAPACK" "libblas-dev liblapack-dev" "blas-devel lapack-devel" "blas lapack" "lapack")"
    fi

    if build_have_libxc 2>/dev/null; then
        doctor_record library libxc ok "$prefix/lib (${ENG_VERSION[libxc]:-version unrecorded})" ""
    else
        doctor_record library libxc missing \
            "APE needs it; without it ONCVPSP has only PZ and PBE" \
            "pseudoforge engines build libxc"
    fi
    if [ -f "$prefix/include/gsl/gsl_version.h" ]; then
        doctor_record library GSL ok "$prefix/lib" ""
    else
        doctor_record library GSL missing "APE needs it; will not configure without it" \
            "pseudoforge engines build gsl"
    fi

    for eng in "${ENG_ORDER[@]}"; do
        IFS=$'\t' read -r state detail < <(eng_status "$eng")
        case $state in
            installed) doctor_record engine "${ENG_LABEL[$eng]}" ok "$detail" "" ;;
            buildable) doctor_record engine "${ENG_LABEL[$eng]}" missing \
                           "source available, not built" \
                           "pseudoforge engines build $eng" ;;
            *)         doctor_record engine "${ENG_LABEL[$eng]}" missing "$detail" "" ;;
        esac
    done

    local set n
    for set in "$PF_DATA"/psl/*.index; do
        [ -e "$set" ] || continue
        n=$(grep -c . "$set" 2>/dev/null)
        doctor_record database "$(basename "$set" .index)" ok "$n recipes" ""
    done

    if [ -n "${MIRROR_URL:-}" ]; then
        if fetch_host_reachable "$MIRROR_URL" 2>/dev/null; then
            doctor_record database mirror ok "$MIRROR_URL" ""
        else
            doctor_record database mirror optional \
                "$MIRROR_URL unreachable; --source online falls back to upstream" ""
        fi
    fi
}

# ---------------------------------------------------------------------------
# Summaries, computed from the records rather than counted twice.
# ---------------------------------------------------------------------------
doctor_count() {   # doctor_count <records> <category> [status]
    local recs=$1 cat=$2 st=${3:-}
    printf '%s\n' "$recs" | awk -F'\t' -v c="$cat" -v s="$st" \
        '$1 == c && (s == "" || $3 == s) { n++ } END { print n + 0 }'
}

# Which families some installed engine can actually make.
doctor_families() {
    local eng fam out=""
    for fam in nc us paw; do
        for eng in "${ENG_ORDER[@]}"; do
            eng_supports_family "$eng" "$fam" || continue
            eng_available "$eng" || continue
            out="$out $(upper "$fam")"; break
        done
    done
    [ -n "$out" ] && trim "$out" || printf 'none'
}

# Which essential dependencies are missing for `doctor --check`.
# Returns a space-separated list of missing tools, or empty string.
doctor_missing_required() {
    local missing="" t recs n_ok n_eng
    recs=${1:-}
    [ -n "$recs" ] || recs=$(doctor_checks)

    # bash >= 4
    if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
        missing="$missing bash"
    fi

    # awk, sed, grep, sort, cut, tr, find, mkdir, mktemp, date, curl
    for t in awk sed grep sort cut tr find mkdir mktemp date curl; do
        have "$t" || missing="$missing $t"
    done

    # gfortran, gcc, make (only if no engine is installed — skip if every engine is present)
    n_ok=$(doctor_count "$recs" engine ok)
    n_eng=$(doctor_count "$recs" engine)
    if [ "$n_ok" -eq 0 ]; then
        for t in gfortran gcc make; do
            have "$t" || missing="$missing $t"
        done
    fi

    # BLAS, LAPACK
    if ! build_have_lapack 2>/dev/null; then
        missing="$missing lapack/blas"
    fi

    trim "$missing"
}

# ---------------------------------------------------------------------------
# doctor_render_cli <records>
#
# The printed report.  Same content and shape as before the split.
# ---------------------------------------------------------------------------
doctor_render_cli() {
    local recs=$1 cat name st detail fix last="" n_ok n_eng
    banner "$PSEUDOFORGE_NAME $PSEUDOFORGE_VERSION -- environment"

    while IFS=$'\t' read -r cat name st detail fix; do
        [ -n "$cat" ] || continue
        if [ "$cat" != "$last" ]; then
            case $cat in
                path)      printf '\n' ;;
                toolchain) printf '\n  Toolchain\n' ;;
                buildtool) printf '\n  Build tools (fetched on demand, no root needed)\n' ;;
                library)   printf '\n  Libraries\n' ;;
                engine)    printf '\n  Engines\n' ;;
                database)  printf '\n  Recipe database\n' ;;
            esac
            last=$cat
        fi
        case $cat in
            path) printf '  %-26s %s\n' "$name" "$detail" ;;
            *)
                case $st in
                    ok)       printf '    %s%-9s%s %-26s %s\n' "$C_GREEN"  ok       "$C_RESET" "$name" "$detail" ;;
                    optional) printf '    %s%-9s%s %-26s %s\n' "$C_DIM"    optional "$C_RESET" "$name" "$detail" ;;
                    *)        printf '    %s%-9s%s %-26s %s\n' "$C_YELLOW" missing  "$C_RESET" "$name" "$detail" ;;
                esac
                [ -n "$fix" ] && printf '    %-9s %-26s %s-> %s%s\n' "" "" "$C_DIM" "$fix" "$C_RESET"
                ;;
        esac
    done <<< "$recs"

    n_ok=$(doctor_count "$recs" engine ok)
    n_eng=$(doctor_count "$recs" engine)
    printf '\n  %d of %d engines available.\n' "$n_ok" "$n_eng"
    [ "$n_ok" -gt 0 ] && printf '  Families you can generate now: %s\n' "$(doctor_families)"
    [ "$n_ok" -lt "$n_eng" ] && \
        printf '  Build everything that is missing:  pseudoforge engines build all\n'
    printf '\n'
}

# ---------------------------------------------------------------------------
# doctor_render_json <records>
#
# One object per record.  Line-delimited rather than a single array, matching
# the sink: a long check streams, and a truncated response is still parseable
# up to the cut.
# ---------------------------------------------------------------------------
doctor_render_json() {
    local recs=$1 cat name st detail fix
    while IFS=$'\t' read -r cat name st detail fix; do
        [ -n "$cat" ] || continue
        printf '{"category":"%s","name":"%s","status":"%s","detail":"%s","fix":"%s"}\n' \
            "$(pf_json_escape "$cat")"    "$(pf_json_escape "$name")" \
            "$(pf_json_escape "$st")"     "$(pf_json_escape "$detail")" \
            "$(pf_json_escape "$fix")"
    done <<< "$recs"
}

# ---------------------------------------------------------------------------
# doctor_render_tui <records>
#
# Text for a whiptail panel, grouped by category and kept inside 80x24.
#
# Whiptail borrows about 6 columns and 7 rows for its frame, title and button,
# so the usable area is roughly 72x16.  Detail is therefore truncated per line
# and each category is summarised rather than listed in full -- an engine list
# of nine plus five toolchain entries plus the database does not fit, and a
# panel that scrolls past the bottom of an 80x24 terminal is unreadable.
# ---------------------------------------------------------------------------
doctor_render_tui() {
    local recs=$1 cat name st detail fix
    local w=${DOCTOR_TUI_WIDTH:-72}

    printf '%s %s\n' "$PSEUDOFORGE_NAME" "$PSEUDOFORGE_VERSION"

    local c label
    for c in toolchain buildtool library engine database; do
        case $c in
            toolchain) label="Toolchain" ;;
            buildtool) label="Build tools" ;;
            library)   label="Libraries" ;;
            engine)    label="Engines" ;;
            database)  label="Database" ;;
        esac
        # Optional items are excluded from the denominator.  An absent
        # optional is not a deficit -- the mirror has not been set up yet, and
        # "Database 11 of 12" read as though something were broken.
        local tot okn opt
        tot=$(doctor_count "$recs" "$c")
        opt=$(doctor_count "$recs" "$c" optional)
        tot=$((tot - opt))
        [ "$tot" -le 0 ] && continue
        okn=$(doctor_count "$recs" "$c" ok)
        printf '\n%-12s %s of %s\n' "$label" "$okn" "$tot"
        # Only what needs attention is listed; everything else is in the count.
        printf '%s\n' "$recs" | awk -F'\t' -v c="$c" -v w="$w" '
            $1 == c && $3 == "missing" {
                line = "  - " $2
                if ($5 != "") line = line ": " $5
                else if ($4 != "") line = line " (" $4 ")"
                if (length(line) > w) line = substr(line, 1, w - 1) "~"
                print line
            }'
    done
}

# The panel's dimensions, so an interface can size the dialog and a test can
# assert it fits.
doctor_tui_size() {
    local text=$1 rows cols
    rows=$(printf '%s\n' "$text" | grep -c .)
    cols=$(printf '%s\n' "$text" | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')
    printf '%s\t%s\n' "$rows" "$cols"
}
