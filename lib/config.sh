# shellcheck shell=bash
# ---------------------------------------------------------------------------
# config.sh -- the ~/.pseudoforgerc configuration file.
#
# The file is plain shell so users can put logic in it (e.g. deriving paths
# from a module system).  It is created on first run with commented defaults.
# ---------------------------------------------------------------------------

PF_RC=${PF_RC:-$HOME/.pseudoforgerc}

# ---- defaults -------------------------------------------------------------
pf_config_defaults() {
    : "${QE_ROOT_DIR:=}"
    : "${LD1_BIN:=${QE_ROOT_DIR:+$QE_ROOT_DIR/bin/}ld1.x}"
    : "${PW_BIN:=${QE_ROOT_DIR:+$QE_ROOT_DIR/bin/}pw.x}"
    : "${SCRATCH_DIR:=${TMPDIR:-/tmp}/pseudoforge}"
    : "${OUTPUT_BASE_DIR:=$PWD/pseudoforge-output}"
    : "${MAX_PARALLEL_JOBS:=4}"

    # execution wrappers -- e.g. PARA_PREFIX='mpirun -np 4'
    : "${PARA_PREFIX:=}"
    : "${PARA_POSTFIX:=}"

    # generation defaults
    : "${DEFAULT_PSEUDOTYPE:=paw}"      # nc | us | paw
    : "${DEFAULT_XC:=PBE}"
    : "${DEFAULT_RELATIVITY:=scalar}"   # nonrel | scalar | full
    : "${DEFAULT_PROFILE:=psl-high}"
    : "${DEFAULT_UPF_VERSION:=2}"       # 1 | 2
    : "${AUTHOR:=}"

    # behaviour
    : "${AUTOFIX_ENABLED:=1}"
    : "${AUTOFIX_MAX_ATTEMPTS:=2}"
    : "${RESUME:=1}"
    : "${LD1_TIMEOUT:=900}"             # seconds per ld1.x run, 0 disables
    : "${PW_TIMEOUT:=3600}"

    # validation
    : "${RUN_LD1_TESTS:=1}"             # transferability check (every engine)
    : "${RUN_CUTOFF_SCAN:=0}"           # pw.x cutoff convergence scan
    : "${CUTOFF_SCAN_LIST:=30 40 50 60 70 80 90 100}"
    : "${CUTOFF_TOL_MRY:=1.0}"          # convergence threshold, mRy/atom
    : "${DUAL_NC:=4}"                   # ecutrho / ecutwfc ratios
    : "${DUAL_US:=8}"
    : "${DUAL_PAW:=8}"
    : "${PW_TEMPLATE:=}"

    # ---- the website's served store (see lib/http.sh) ---------------------
    # The deployment target is a 1-core, 1 GB VPS with 10 GB of disk that does
    # not run engines.  The budget is asserted by tests/test_vps_layout.sh so
    # the layout cannot quietly outgrow the machine it is meant for.
    : "${PF_VAR_DIR:=/var/lib/pseudoforge}"
    : "${PF_NATIVE_DIR:=$PF_VAR_DIR/native}"
    : "${PF_CACHE_DIR:=$PF_VAR_DIR/cache}"
    : "${PF_VPS_BUDGET_MB:=8192}"

    # ---- generator engines (see lib/engines.sh) ----------------------------
    : "${ENGINE_DIR:=$HOME/.pseudoforge/engines}"
    : "${ONCVPSP_BIN:=}"
    : "${USPP_BIN:=}"
    : "${FHI98PP_BIN:=}"
    : "${OPIUM_BIN:=}"
    : "${GTH_BIN:=}"
    : "${ATOMPAW_BIN:=}"
    : "${APE_BIN:=}"
    : "${ADPACK_BIN:=}"
    : "${UPFCONV_BIN:=${QE_ROOT_DIR:+$QE_ROOT_DIR/upfconv.x}}"
    : "${ONCVPSP_SRC_DIR:=}"
    : "${USPP_SRC_DIR:=}"
    : "${FHI98PP_SRC_DIR:=}"
    : "${USPP_ROOT:=}"
    : "${FHI98PP_ROOT:=}"
    : "${DEFAULT_ENGINE:=auto}"
    : "${ONCVPSP_TIMEOUT:=1800}"
    : "${USPP_TIMEOUT:=1800}"
    : "${FHI98PP_TIMEOUT:=1800}"

    # ---- obtaining ready-made pseudopotentials -----------------------------
    : "${MIRROR_URL:=https://pseudo.amirkhani.me/library/}"
    : "${DEFAULT_SOURCE:=local}"
    : "${DOWNLOAD_TIMEOUT:=120}"
    : "${PARAMS_DIR:=}"

    # ---- threading ---------------------------------------------------------
    # Atomic solvers are single-atom problems; a threaded BLAS spends longer
    # spin-waiting than computing, and on a busy machine can hang outright.
    : "${OMP_THREADS:=1}"
}

# ---- template written on first run ----------------------------------------
pf_config_template() {
cat <<'RC'
# ---------------------------------------------------------------------------
# ~/.pseudoforgerc -- configuration for PseudoForge (pseudopotential generator)
#
# This file is sourced by every PseudoForge run.  It is ordinary shell, so you may
# compute values (e.g. `QE_ROOT_DIR=$(dirname "$(dirname "$(command -v pw.x)")")`).
# ---------------------------------------------------------------------------

# --- Quantum ESPRESSO -------------------------------------------------------
# Root of your QE installation.  LD1_BIN/PW_BIN are derived from it unless you
# set them explicitly.
QE_ROOT_DIR=""
#LD1_BIN="$QE_ROOT_DIR/bin/ld1.x"
#PW_BIN="$QE_ROOT_DIR/bin/pw.x"

# Parallel launcher used for every QE call, e.g. PARA_PREFIX="mpirun -np 4".
# Leave empty for serial runs.  ld1.x is a serial code; PARA_PREFIX is applied
# to pw.x only unless LD1_PARA=1.
PARA_PREFIX=""
PARA_POSTFIX=""
LD1_PARA=0

# --- Directories ------------------------------------------------------------
# Where generated projects are written.  Each run creates a subdirectory with
# inputs/ pseudos/ tests/ logs/ reports/ underneath.
OUTPUT_BASE_DIR="$HOME/pseudoforge-output"

# Scratch space for QE temporary files (pw.x outdir).  Should be on a fast disk.
SCRATCH_DIR="${TMPDIR:-/tmp}/pseudoforge"

# --- Execution --------------------------------------------------------------
# How many elements to process concurrently.
MAX_PARALLEL_JOBS=4

# Per-run wall-clock limits in seconds (0 = no limit).
LD1_TIMEOUT=900
PW_TIMEOUT=3600

# Skip elements whose .UPF already exists (1) or always regenerate (0).
RESUME=1

# --- Generation defaults ----------------------------------------------------
DEFAULT_PSEUDOTYPE="paw"        # nc | us | paw
DEFAULT_XC="PBE"
DEFAULT_RELATIVITY="scalar"     # nonrel | scalar | full
DEFAULT_PROFILE="psl-high"
DEFAULT_UPF_VERSION=2           # 1 = legacy text UPF, 2 = UPF v2 (XML)
# Author string written into every generated UPF.  Leave it empty to keep the
# author recorded in the library recipe itself -- with psl-* profiles that makes
# an untouched run reproduce the published deck exactly.
AUTHOR=""

# --- Auto-fix engine --------------------------------------------------------
# On a failed ld1.x run, retry with progressively relaxed parameters.
AUTOFIX_ENABLED=1
AUTOFIX_MAX_ATTEMPTS=2

# --- Validation -------------------------------------------------------------
# Run the transferability check after generation.  The variable name is
# historical: it now drives every engine own analysis, not just ld1.x decks.
RUN_LD1_TESTS=1

# Run a pw.x kinetic-energy cutoff scan.  Needs a working pw.x and is slow.
RUN_CUTOFF_SCAN=0
CUTOFF_SCAN_LIST="30 40 50 60 70 80 90 100"
CUTOFF_TOL_MRY=1.0              # total-energy convergence target, mRy/atom

# Default ecutrho/ecutwfc ratios per pseudopotential family.
DUAL_NC=4
DUAL_US=8
DUAL_PAW=8

# Optional: your own pw.x input for the cutoff scan, instead of the generic fcc
# cell PseudoForge builds. Placeholders: {{ELEMENT}} {{UPF}} {{MASS}} {{ECUTWFC}}
# {{ECUTRHO}} {{PSEUDO_DIR}} {{OUTDIR}} {{PREFIX}} {{CELLDM}}
PW_TEMPLATE=""

# --- Generator engines ------------------------------------------------------
# PseudoForge drives nine atomic codes.  ld1.x comes with Quantum ESPRESSO; the
# others are built by `pseudoforge engines build <name>` (or installed externally)
# and land in ENGINE_DIR.  Leave a path empty and PseudoForge will look in ENGINE_DIR
# and then on $PATH.  An engine that is missing only disables generation *with that
# engine* -- importing and validating its files still works.
ENGINE_DIR="$HOME/.pseudoforge/engines"

# [engines.ld1] Quantum ESPRESSO ld1.x -- all three families (NC, US, PAW).
# See QE_ROOT_DIR above, or set LD1_BIN explicitly.
#LD1_BIN=""

# [engines.oncvpsp] ONCVPSP (Hamann) -- norm-conserving, multi-projector. Writes UPF directly.
#   https://github.com/oncvpsp/oncvpsp
#ONCVPSP_BIN=""

# [engines.uspp] USPP (Vanderbilt) -- ultrasoft. Output goes through reform.x and upfconv.x.
#   https://www.physics.rutgers.edu/~dhv/uspp/
#USPP_BIN=""

# [engines.fhi98pp] fhi98PP (Fuchs/Scheffler) -- norm-conserving, Hamann or Troullier-Martins.
#   Writes .cpi; see docs/explanation/physics.md about UPF conversion on QE 7.x.
#FHI98PP_BIN=""

# [engines.opium] OPIUM (Rappe group) -- norm-conserving, RRKJ and Troullier-Martins.
#   https://github.com/rappegroup/opium
#OPIUM_BIN=""

# [engines.gth] GTH (Goedecker/Hartwigsen, CP2K) -- norm-conserving analytic form.
#   https://github.com/cp2k/cp2k-data
#GTH_BIN=""

# [engines.atompaw] AtomPAW (Holzwarth) -- PAW datasets.
#   https://github.com/atompaw/atompaw
#ATOMPAW_BIN=""

# [engines.ape] APE (Atomic Pseudopotential Engine) -- norm-conserving, libxc-driven.
#   https://gitlab.com/ape/ape
#APE_BIN=""

# [engines.adpack] ADPACK (Ozaki) -- norm-conserving, OpenMX .vps format. External install.
#   http://www.openmx-square.org/adpack/adpack.html
#ADPACK_BIN=""

# QE's format converter, used for the USPP and fhi98PP outputs.
#UPFCONV_BIN="$QE_ROOT_DIR/upfconv.x"

# Unpacked engine sources.  Set these if you keep the source trees somewhere
# of your own; otherwise PseudoForge looks beside itself and in ENGINE_DIR/build.
# These trees are also where the vendor parameter databases live, so keeping
# them is worthwhile after the build.
#ONCVPSP_SRC_DIR=""
#USPP_SRC_DIR=""
#FHI98PP_SRC_DIR=""

# Which engine to use when you do not say.  "auto" picks from the profile and
# the family: PAW -> ld1, US -> uspp, NC -> oncvpsp, any psl-* profile -> ld1.
DEFAULT_ENGINE="auto"

# Per-run wall-clock limits, seconds (0 = no limit).
ONCVPSP_TIMEOUT=1800
USPP_TIMEOUT=1800
FHI98PP_TIMEOUT=1800

# --- Getting ready-made pseudopotentials ------------------------------------
# Checked first by `--source online`.  Files are looked up as
#   $MIRROR_URL/<library>/<functional>/<Element>.<...>.UPF
# and PseudoForge falls back to the library's official site when the mirror has
# nothing.
MIRROR_URL="https://pseudo.amirkhani.me/library/"

# "local"  = generate with an engine on this machine
# "online" = download a published file and validate it
# "ask"    = let the wizard decide each time
DEFAULT_SOURCE="local"
DOWNLOAD_TIMEOUT=120

# A directory of published generator input files (SG15 .dat, PseudoDojo .in,
# USPP .adat, fhi98PP .ini).  Given these, PseudoForge reproduces those libraries
# properly instead of falling back to its own construction.
#PARAMS_DIR=""

# --- Threading --------------------------------------------------------------
# Atomic solvers are tiny; a threaded BLAS spends longer spin-waiting on
# barriers than doing arithmetic, and on a loaded machine an ld1.x run that
# should take 1.5 s can fail to finish at all.  PseudoForge parallelises over
# elements instead, which is the level that actually scales.  Raise this only
# if you know your BLAS behaves well on single-atom problems.
OMP_THREADS=1
RC
}

# ---- load / create --------------------------------------------------------
pf_config_load() {
    pf_config_migrate
    if [ ! -f "$PF_RC" ]; then
        info "first run: creating $PF_RC"
        pf_config_template | write_atomic "$PF_RC" || die "cannot write $PF_RC"
        PF_CONFIG_CREATED=1
    fi
    # shellcheck disable=SC1090
    . "$PF_RC" || die "failed to read $PF_RC"
    pf_config_defaults
    pf_config_expand
}

# Expand ~ and make paths absolute so later `cd`s cannot break them.
pf_config_expand() {
    local v
    for v in QE_ROOT_DIR LD1_BIN PW_BIN SCRATCH_DIR OUTPUT_BASE_DIR ENGINE_DIR ONCVPSP_BIN USPP_BIN FHI98PP_BIN OPIUM_BIN GTH_BIN ATOMPAW_BIN APE_BIN ADPACK_BIN UPFCONV_BIN PARAMS_DIR ONCVPSP_SRC_DIR USPP_SRC_DIR FHI98PP_SRC_DIR USPP_ROOT FHI98PP_ROOT; do
        local cur=${!v:-}
        [ -n "$cur" ] || continue
        case $cur in "~"/*) cur=$HOME/${cur#\~/} ;; esac
        printf -v "$v" '%s' "$cur"
    done
    # LD1_BIN/PW_BIN may be bare command names found on PATH -- leave those alone.
    for v in LD1_BIN PW_BIN ONCVPSP_BIN USPP_BIN FHI98PP_BIN OPIUM_BIN GTH_BIN ATOMPAW_BIN APE_BIN ADPACK_BIN UPFCONV_BIN; do
        local cur=${!v:-}
        case $cur in */*) abspath_r "$cur"; printf -v "$v" "%s" "$REPLY" ;; esac
    done
    for v in SCRATCH_DIR OUTPUT_BASE_DIR; do
        abspath_r "${!v:-}"; printf -v "$v" "%s" "$REPLY"
    done
}

# Persist a single key back into ~/.pseudoforgerc (used by the TUI settings screen).
pf_config_set() {
    local key=$1 val=$2
    [ -f "$PF_RC" ] || pf_config_load
    if grep -q "^[[:space:]]*#\?[[:space:]]*$key=" "$PF_RC"; then
        awk -v k="$key" -v v="$val" '
            $0 ~ "^[[:space:]]*#?[[:space:]]*" k "=" && !done { print k "=\"" v "\""; done = 1; next }
            { print }' "$PF_RC" | write_atomic "$PF_RC"
    else
        printf '%s="%s"\n' "$key" "$val" >> "$PF_RC"
    fi
    printf -v "$key" '%s' "$val"
}

# Print the effective configuration (used by `pseudoforge config --show`).
pf_config_show() {
    local v
    for v in QE_ROOT_DIR LD1_BIN PW_BIN PARA_PREFIX PARA_POSTFIX \
             OUTPUT_BASE_DIR SCRATCH_DIR MAX_PARALLEL_JOBS \
             LD1_TIMEOUT PW_TIMEOUT RESUME \
             DEFAULT_PSEUDOTYPE DEFAULT_XC DEFAULT_RELATIVITY DEFAULT_PROFILE \
             DEFAULT_UPF_VERSION AUTHOR \
             AUTOFIX_ENABLED AUTOFIX_MAX_ATTEMPTS \
             RUN_LD1_TESTS RUN_CUTOFF_SCAN CUTOFF_SCAN_LIST CUTOFF_TOL_MRY \
             DUAL_NC DUAL_US DUAL_PAW ENGINE_DIR DEFAULT_ENGINE \
             ONCVPSP_BIN USPP_BIN FHI98PP_BIN OPIUM_BIN GTH_BIN ATOMPAW_BIN APE_BIN ADPACK_BIN \
             UPFCONV_BIN MIRROR_URL DEFAULT_SOURCE PARAMS_DIR OMP_THREADS; do
        printf '%-22s %s\n' "$v" "${!v}"
    done
}

# ---------------------------------------------------------------------------
# The tool used to be called psmaker.  Carry a previous installation's settings
# and built engines across rather than silently starting from defaults -- a
# user who has compiled three Fortran packages should not have to do it twice
# because the program was renamed.
# ---------------------------------------------------------------------------
pf_config_migrate() {
    local old_rc=$HOME/.psmakerrc old_dir=$HOME/.psmaker
    local new_dir=${PF_USER_DATA:-$HOME/.pseudoforge}

    if [ ! -f "$PF_RC" ] && [ -f "$old_rc" ]; then
        info "found a psmaker configuration; carrying it over to $PF_RC"
        sed -e 's/\.psmakerrc/.pseudoforgerc/g' \
            -e 's|\.psmaker/|.pseudoforge/|g' \
            -e 's|/\.psmaker$|/.pseudoforge|' \
            "$old_rc" > "$PF_RC" || return 1
        ok "migrated $old_rc -> $PF_RC (the old file is left alone)"
    fi

    if [ ! -d "$new_dir" ] && [ -d "$old_dir" ]; then
        info "found engines and cached inputs under $old_dir"
        if cp -a "$old_dir" "$new_dir" 2>/dev/null; then
            ok "copied to $new_dir -- no need to rebuild anything"
            # paths recorded inside the config still point at the old location
            [ -f "$PF_RC" ] && sed -i "s|$old_dir|$new_dir|g" "$PF_RC"
        else
            warn "could not copy $old_dir; engines may need rebuilding"
        fi
    fi
    return 0
}
