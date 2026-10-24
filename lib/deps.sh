# shellcheck shell=bash
# ---------------------------------------------------------------------------
# deps.sh -- environment checks.
#
# Split into three tiers, because most of PseudoForge is useful without a working
# Quantum ESPRESSO: you can browse recipes, build decks and produce reports
# with nothing but coreutils.
#
#   required   PseudoForge cannot run at all without these
#   qe         needed to actually execute ld1.x / pw.x
#   optional   nicer output when present
# ---------------------------------------------------------------------------

DEPS_REQUIRED="awk sed grep sort cut tr find mkdir mktemp date"
DEPS_OPTIONAL="whiptail dialog tar gzip column timeout xz"

deps_bash_version() {
    if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
        error "PseudoForge needs bash 4.0 or newer (associative arrays); this is ${BASH_VERSION:-unknown}"
        case $(uname -s 2>/dev/null) in
            Darwin) error "  on macOS: brew install bash, then run PseudoForge with that bash" ;;
        esac
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Platform detection and dependency fix commands
# ---------------------------------------------------------------------------
pf_detect_os() {
    if [ -n "${FAKE_DISTRO:-}" ]; then
        echo "$FAKE_DISTRO"
        return
    fi
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case ${ID:-}${ID_LIKE:-} in
            *debian*|*ubuntu*) echo debian; return ;;
            *fedora*|*rhel*|*centos*) echo fedora; return ;;
            *arch*)            echo arch; return ;;
            *suse*)            echo suse; return ;;
        esac
    fi
    case $(uname -s 2>/dev/null) in
        Darwin) echo macos; return ;;
    esac
    echo unknown
}

pf_dep_fix() {   # pf_dep_fix <purpose> <debian-pkg> <fedora-pkg> <arch-pkg> <brew-pkg>
    local purpose=$1 deb=$2 fed=$3 arch=$4 brew=$5
    case $(pf_detect_os) in
        debian) echo "sudo apt-get install -y $deb" ;;
        fedora|rhel) echo "sudo dnf install -y $fed" ;;
        arch)   echo "sudo pacman -S --needed --noconfirm $arch" ;;
        macos)  echo "brew install $brew" ;;
        *)      echo "install $purpose with your package manager" ;;
    esac
}

# deps_check_required -> non-zero if anything essential is missing
deps_check_required() {
    local missing="" t
    for t in $DEPS_REQUIRED; do have "$t" || missing="$missing $t"; done
    if [ -n "$missing" ]; then
        error "missing required tools:$missing"
        error "  Debian/Ubuntu : sudo apt install coreutils gawk sed grep findutils"
        error "  Fedora/RHEL   : sudo dnf install coreutils gawk sed grep findutils"
        error "  macOS         : brew install coreutils gawk gnu-sed grep"
        return 1
    fi
    deps_bash_version || return 1
    return 0
}

# The TUI front end. Returns the name of the dialog program, or non-zero.
deps_tui_backend() {
    if have whiptail; then echo whiptail; return 0; fi
    if have dialog;   then echo dialog;   return 0; fi
    return 1
}

deps_tui_hint() {
    error "no TUI backend found (whiptail or dialog)"
    error "  Debian/Ubuntu : sudo apt install whiptail"
    error "  Fedora/RHEL   : sudo dnf install newt"
    error "  Arch          : sudo pacman -S libnewt"
    error "  macOS         : brew install newt      (or: brew install dialog)"
    error "PseudoForge still works without it -- use the command line interface, e.g."
    error "  pseudoforge generate --elements Si,Fe --family paw --xc pbe"
}

# ---------------------------------------------------------------------------
# Quantum ESPRESSO binaries.  Resolved from the config, then from PATH.
# ---------------------------------------------------------------------------
deps_resolve_qe() {
    local v path
    for v in LD1_BIN PW_BIN; do
        path=${!v}
        if [ -z "$path" ]; then
            case $v in LD1_BIN) path=ld1.x ;; PW_BIN) path=pw.x ;; esac
        fi
        if [ -x "$path" ]; then
            printf -v "$v" '%s' "$path"
        elif have "$(basename "$path")"; then
            printf -v "$v" '%s' "$(command -v "$(basename "$path")")"
        fi
    done
}

deps_have_ld1() { [ -x "$LD1_BIN" ] || have "$LD1_BIN"; }
deps_have_pw()  { [ -x "$PW_BIN" ]  || have "$PW_BIN"; }

deps_qe_hint() {
    error "Quantum ESPRESSO binaries not found."
    error "  ld1.x : ${LD1_BIN:-<unset>}   $(deps_have_ld1 && echo found || echo MISSING)"
    error "  pw.x  : ${PW_BIN:-<unset>}    $(deps_have_pw  && echo found || echo MISSING)"
    error ""
    error "Set QE_ROOT_DIR (or LD1_BIN/PW_BIN directly) in $PF_RC, for example:"
    error "  QE_ROOT_DIR=\"\$HOME/q-e-7.4\""
    error ""
    error "To build Quantum ESPRESSO:"
    error "  git clone https://gitlab.com/QEF/q-e.git && cd q-e"
    error "  ./configure && make pw ld1"
    error "Or install a package: apt install quantum-espresso / dnf install quantum-espresso"
}

# ld1.x version string, best effort.
#
# This is a diagnostic for the run manifest, and it must never be able to hold
# the whole tool up.  ld1.x reads its deck from stdin, and an MPI-enabled build
# can sit waiting rather than returning on a minimal one, so the probe is
# bounded and failure just yields "unknown".
deps_ld1_version() {
    deps_have_ld1 || { echo unknown; return 1; }
    local out wd key cache pid i lim=${VERSION_PROBE_TIMEOUT:-10}

    # Cached per binary. This probe ran on every report -- once per build of
    # the native store's 280 combinations -- and each run starts Open MPI,
    # which lists the network interfaces through netlink. One of those
    # starts blocked in the kernel on rtnl_lock (WSL's networking lock had
    # wedged) and stopped a multi-hour build for three hours. The version of
    # a binary does not change until the binary does.
    key=$(stat -c '%d-%i-%Y' "$LD1_BIN" 2>/dev/null)
    cache=${XDG_CACHE_HOME:-$HOME/.cache}/pseudoforge/ld1-version-${key:-unknown}
    if [ -n "$key" ] && [ -s "$cache" ]; then cat "$cache"; return 0; fi

    # In a scratch directory, not wherever the user happens to be standing.
    # ld1.x writes its stdin back out as "input_tmp.in" in the current
    # directory, so probing the version from a project root silently drops a
    # stray file there -- which is how one appeared in this repository.
    wd=$(mktemp -d 2>/dev/null) || { echo unknown; return 1; }
    printf ' &input\n  iswitch=1,\n  zed=1.0,\n  config="1s1",\n  rel=0,\n  dft="PZ"\n /\n' > "$wd/in"

    # Watched, not waited on. `timeout` cannot help here: a process blocked
    # in the kernel (state D) ignores every signal, and timeout waits for it
    # to die. So the probe runs in the background with its output in a file,
    # and if it is still alive at the limit it is killed and abandoned --
    # nothing here waits on it, so nothing here can hang with it. Reading the
    # file afterwards also replaces `| grep -m1`, which closed the pipe on
    # ld1.x mid-write.
    ( cd "$wd" && OMP_NUM_THREADS="${OMP_THREADS:-1}" exec "$LD1_BIN" < in > out 2>/dev/null ) &
    pid=$!
    i=0
    while kill -0 "$pid" 2>/dev/null && [ "$i" -lt $((lim * 10)) ]; do
        sleep 0.1; i=$((i + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null
        disown "$pid" 2>/dev/null
    else
        wait "$pid" 2>/dev/null
    fi
    out=$(grep -m1 -oE 'v\.[0-9][^ ]*' "$wd/out" 2>/dev/null)
    rm -rf "$wd" 2>/dev/null
    if [ -n "$out" ] && [ -n "$key" ]; then
        mkdir -p "${cache%/*}" 2>/dev/null && printf '%s\n' "$out" > "$cache"
    fi
    printf '%s\n' "${out:-unknown}"
}

# ---------------------------------------------------------------------------
# deps_report -- what `pseudoforge doctor` prints.
# ---------------------------------------------------------------------------
deps_report() {
    local t status
    banner "Environment"
    printf '  %-16s %s\n' "PseudoForge" "$PSEUDOFORGE_VERSION"
    printf '  %-16s %s\n' "bash" "${BASH_VERSION:-unknown}"
    printf '  %-16s %s\n' "config" "$PF_RC"
    printf '  %-16s %s\n' "data" "$PF_DATA"

    banner "Required tools"
    for t in $DEPS_REQUIRED; do
        if have "$t"; then printf '  %s%-16s%s %s\n' "$C_GREEN" "$t" "$C_RESET" "$(command -v "$t")"
        else               printf '  %s%-16s%s MISSING\n' "$C_RED" "$t" "$C_RESET"; fi
    done
    if [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then
        printf '  %s%-16s%s %s\n' "$C_GREEN" "bash >= 4" "$C_RESET" "${BASH_VERSION}"
    else
        printf '  %s%-16s%s %s\n' "$C_RED" "bash >= 4" "$C_RESET" "${BASH_VERSION:-unknown}"
    fi

    banner "Optional tools"
    for t in $DEPS_OPTIONAL; do
        if have "$t"; then printf '  %s%-16s%s %s\n' "$C_GREEN" "$t" "$C_RESET" "$(command -v "$t")"
        else               printf '  %s%-16s%s not installed\n' "$C_DIM" "$t" "$C_RESET"; fi
    done

    banner "Quantum ESPRESSO"
    deps_resolve_qe
    if deps_have_ld1; then
        printf '  %s%-16s%s %s  (%s)\n' "$C_GREEN" "ld1.x" "$C_RESET" "$LD1_BIN" "$(deps_ld1_version)"
    else
        printf '  %s%-16s%s %s\n' "$C_RED" "ld1.x" "$C_RESET" "${LD1_BIN:-<unset>} -- not executable"
    fi
    if deps_have_pw; then
        printf '  %s%-16s%s %s\n' "$C_GREEN" "pw.x" "$C_RESET" "$PW_BIN"
    else
        printf '  %s%-16s%s %s\n' "$C_YELLOW" "pw.x" "$C_RESET" "${PW_BIN:-<unset>} -- cutoff scans unavailable"
    fi
    [ -n "$PARA_PREFIX" ] && printf '  %-16s %s\n' "launcher" "$PARA_PREFIX ... $PARA_POSTFIX"

    banner "Generator engines"
    local eng state detail colour
    for eng in "${ENG_ORDER[@]}"; do
        IFS=$'\t' read -r state detail < <(eng_status "$eng")
        case $state in
            installed) colour=$C_GREEN ;;
            buildable) colour=$C_YELLOW ;;
            *)         colour=$C_RED ;;
        esac
        printf '  %b%-10s%b %-11s %-9s %s\n' "$colour" "$state" "$C_RESET" \
               "$eng" "${ENG_FAMILIES[$eng]}" "$detail"
    done
    printf '\n'
    for eng in "${ENG_ORDER[@]}"; do
        eng_available "$eng" && continue
        [ "$eng" = ld1 ] && continue
        printf '  %s is not installed: generation with it is disabled,\n' "${ENG_LABEL[$eng]}"
        printf '    but importing and validating its files still works.\n'
        if [ "$eng" = adpack ]; then
            printf '    external install; see docs/reference/engines/adpack.md\n'
        else
            printf '    To build it:  pseudoforge engines build %s\n' "$eng"
        fi
    done
    if ! eng_available ld1; then
        printf '  %s is missing: PAW and the whole PSlibrary set are unavailable.\n' "${ENG_LABEL[ld1]}"
        printf '    Install Quantum ESPRESSO and set QE_ROOT_DIR in %s\n' "$PF_RC"
    fi

    banner "Format conversion"
    local conv
    if conv=$(exec_find_upfconv 2>/dev/null); then
        printf '  %supfconv.x%s   %s\n' "$C_GREEN" "$C_RESET" "$conv"
        printf '  %-12s %s\n' "" "converts USPP (.van) output to UPF"
        printf '  %-12s %s\n' "" "NOTE: QE 7.x cannot convert fhi98PP .cpi/.fhi -- see docs/explanation/physics.md"
    else
        printf '  %supfconv.x%s   not found -- USPP output cannot be converted to UPF\n' "$C_YELLOW" "$C_RESET"
    fi

    banner "Downloads"
    printf '  %-12s %s\n' "mirror" "${MIRROR_URL:-<unset>}"
    if [ -n "${MIRROR_URL:-}" ]; then
        if fetch_host_reachable "$MIRROR_URL" 2>/dev/null; then
            printf '  %-12s %sreachable%s\n' "" "$C_GREEN" "$C_RESET"
        else
            printf '  %-12s %sunreachable%s -- "--source online" will fall back to upstream\n' \
                   "" "$C_YELLOW" "$C_RESET"
        fi
    fi
    printf '  %-12s %s\n' "params" "${PARAMS_DIR:-<unset>  (set it to reproduce a published library exactly)}"

    banner "Recipe database"
    local set n
    for set in "$PF_DATA"/psl/*.index; do
        [ -e "$set" ] || continue
        n=$(wc -l < "$set" | tr -d ' ')
        printf '  %-16s %4s recipes, %3s elements\n' "$(basename "$set" .index)" "$n" \
               "$(psl_set_elements "$(basename "$set" .index)" | wc -l | tr -d ' ')"
    done

    banner "Directories"
    for t in OUTPUT_BASE_DIR SCRATCH_DIR; do
        status=$([ -d "${!t}" ] && echo exists || echo "will be created")
        printf '  %-16s %s (%s)\n' "$t" "${!t}" "$status"
    done
    printf '\n'
}
