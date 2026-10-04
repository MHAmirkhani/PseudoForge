# shellcheck shell=bash
# ---------------------------------------------------------------------------
# testing.sh -- validation of a finished pseudopotential.
#
# Two independent checks, because they catch different failures:
#
#   1. transferability (ld1.x, iswitch=2)
#      Re-solves the pseudo-atom in configurations it was *not* fitted to and
#      compares eigenvalues and total energies against the all-electron atom.
#      This is what catches a pseudopotential that is only right for its own
#      reference configuration.  The test decks shipped with PSlibrary are
#      reused verbatim where they exist.
#
#   2. kinetic-energy cutoff convergence (pw.x)
#      Runs a small elemental solid at a ladder of ecutwfc values and reports
#      the lowest cutoff at which the total energy (and, if available, the
#      pressure) has stopped moving.  Convergence of a plane-wave cutoff is a
#      property of the pseudopotential, not of the particular crystal, so a
#      generic fcc cell is a legitimate probe -- and a real structure can be
#      supplied instead with --pw-template.
# ---------------------------------------------------------------------------

BOHR_PER_ANGSTROM=1.8897259886

# ---------------------------------------------------------------------------
# Transferability
# ---------------------------------------------------------------------------

# ld1_test_one <element> -> 0 if the test ran, 1 otherwise.
# Appends a row to tests/transferability.tsv:
#   element  upf  nconf  max_abs_de_eig_Ry  de_etot_Ry  verdict
ld1_test_one() {
    local el=$1
    local prof=${SPEC[profile]} fam=${SPEC[family]} rel=${SPEC[rel]}
    local set tag key cond tpl deck log fct nrel upf fc out
    local maxde detot verdict

    upf=$(state_field "$el" 7)
    [ -n "$upf" ] && [ -f "$PROJECT_DIR/pseudos/$upf" ] || return 1

    fct=$(xc_tag "${SPEC[xc]}" "$rel")
    nrel=$(rel_code "$rel")

    IFS=$'\t' read -r set tag key cond < <(recipe_select "$prof" "$fam" "$el" "$rel") || return 1
    tpl=$(psl_test_template "$set" "$el" "$tag" "$cond") || {
        debug "$el: no shipped transferability deck for $set/$tag"
        return 1
    }
    fc=$(psl_test_frozen_core "$set")

    deck=$PROJECT_DIR/tests/$el.test.in
    log=$PROJECT_DIR/tests/$el.test.out
    sed -e "s/{{FCT}}/$fct/g" -e "s/{{GFUN}}/$(xc_qe_string "${SPEC[xc]}")/g" \
        -e "s/{{NREL}}/$nrel/g" -e "s|{{PSDIR}}|$PROJECT_DIR/pseudos|g" \
        -e "s/{{FROZEN_CORE}}/$fc/g" "$tpl" > "$deck"

    # Log derivatives, only when they are going to be drawn.  These are read
    # by the iswitch=2 validation run, which happens after the UPF has been
    # written, so they cannot change the pseudopotential -- and leaving them
    # out of the default path keeps the rendered deck identical to the one
    # PSlibrary ships.  (file_logder is an &inputp keyword and is rejected
    # here; with none given ld1.x writes ld1N.dlog and ld1Nps.dlog.)
    if [ "${PLOT_ENABLED:-0}" = 1 ]; then
        nml_set "$deck" input rlderiv "$(plot_rlderiv "$PROJECT_DIR" "$el")"
        nml_set "$deck" input eminld  "$PLOT_EMINLD"
        nml_set "$deck" input emaxld  "$PLOT_EMAXLD"
        nml_set "$deck" input deld    "$PLOT_DELD"
        nml_set "$deck" input nld     "$PLOT_NLD"
    fi

    ld1_run "$deck" "$log" "$PROJECT_DIR/tests" || true

    # ld1.x (iswitch=2) prints, for each test configuration, a table of
    # all-electron vs pseudo eigenvalues whose last column is the difference,
    # then a total-energy comparison.  The exact spacing has changed between QE
    # releases, so key off the "AE-PS" header and the "Delta E"/"dEtot" labels
    # rather than off fixed columns.
    maxde=$(awk '
        /AE-PS/            { intable = 1; next }
        intable && /^[[:space:]]*$/ { intable = 0; next }
        intable && $1 ~ /^[0-9]+$/ && $NF ~ /^-?[0-9]+\.[0-9]+([EeDd][-+]?[0-9]+)?$/ {
            v = $NF + 0; if (v < 0) v = -v; if (v > m) m = v
        }
        END { printf "%.6f\n", m + 0 }' "$log" 2>/dev/null)

    detot=$(awk '
        /Delta E *=/ || /dEtot_ae *- *dEtot_ps/ || /Etot_ae *- *Etot_ps/ {
            for (i = NF; i >= 1; i--) if ($i ~ /^-?[0-9]+\.[0-9]+([EeDd][-+]?[0-9]+)?$/) { v = $i + 0; break }
            if (v < 0) v = -v
            if (v > m) m = v
        }
        END { printf "%.6f\n", m + 0 }' "$log" 2>/dev/null)

    # Thresholds and the row format now live in validate.sh, so ld1 and the
    # five other engines cannot drift apart in how they grade or report.
    VAL_METHOD="ld1 iswitch=2"
    VAL_MAXDE=${maxde:-0}
    VAL_DETOT=${detot:-0}
    VAL_VERDICT=$(transfer_verdict "${maxde:-0}")
    VAL_NOTE="re-solved in unfitted configurations"
    transfer_record "$el" "$upf"
    return 0
}

# ---------------------------------------------------------------------------
# Cutoff convergence
# ---------------------------------------------------------------------------

# A generic fcc probe cell.
#
# Nearest neighbours in fcc sit at a/sqrt(2), so a = 2*sqrt(2)*r_cov would put
# them exactly one covalent bond apart.  That is far too close: a covalent
# radius describes 2- to 4-fold bonding while fcc is 12-fold, and using it raw
# compresses the cell to thousands of kbar, where small differences in the core
# region are wildly amplified.  Calibrated against Si, whose fcc cell reaches
# zero pressure at 1.22 times that spacing, the coordination correction below
# lands most elements within a few hundred kbar of equilibrium.  Every run
# reports its pressure, so a cell that is still unreasonable is visible rather
# than silent.
pw_test_celldm() {
    local el=$1 r=${EL_RCOV[$1]:-}
    [ -n "$r" ] && [ "$r" != "-" ] || r=1.40
    awk -v r="$r" -v b="$BOHR_PER_ANGSTROM" 'BEGIN { printf "%.4f\n", 2 * sqrt(2) * r * b * 1.22 }'
}

# pw_write_input <element> <upf> <ecutwfc> <ecutrho> <outfile>
#
# With PW_TEMPLATE set, the user's own pw.x input is used instead of the generic
# fcc cell, with these placeholders substituted:
#
#   {{ELEMENT}} {{UPF}} {{MASS}} {{ECUTWFC}} {{ECUTRHO}}
#   {{PSEUDO_DIR}} {{OUTDIR}} {{PREFIX}} {{CELLDM}}
#
# That is the right thing to do when cutoff convergence matters for a specific
# structure -- a molecule in a box, a surface slab, a high-pressure phase --
# rather than for a generic bulk environment.
pw_write_input() {
    local el=$1 upf=$2 wfc=$3 rho=$4 out=$5
    local a line
    a=$(pw_test_celldm "$el")

    if [ -n "${PW_TEMPLATE:-}" ]; then
        [ -f "$PW_TEMPLATE" ] || { error "pw template not found: $PW_TEMPLATE"; return 1; }
        local -a rendered=()
        while IFS= read -r line || [ -n "$line" ]; do
            line=${line//\{\{ELEMENT\}\}/$el}
            line=${line//\{\{UPF\}\}/$upf}
            line=${line//\{\{MASS\}\}/${EL_MASS[$el]}}
            line=${line//\{\{ECUTWFC\}\}/$wfc}
            line=${line//\{\{ECUTRHO\}\}/$rho}
            line=${line//\{\{PSEUDO_DIR\}\}/$PROJECT_DIR\/pseudos}
            line=${line//\{\{OUTDIR\}\}/$SCRATCH_DIR\/pw}
            line=${line//\{\{PREFIX\}\}/pf_${el}_${wfc}}
            line=${line//\{\{CELLDM\}\}/$a}
            rendered+=("$line")
        done < "$PW_TEMPLATE"
        printf '%s\n' "${rendered[@]}" > "$out"
        return 0
    fi

    cat > "$out" <<PWEOF
&CONTROL
  calculation  = 'scf'
  prefix       = 'pf_${el}_${wfc}'
  outdir       = '${SCRATCH_DIR}/pw'
  pseudo_dir   = '${PROJECT_DIR}/pseudos'
  tstress      = .true.
  tprnfor      = .true.
  verbosity    = 'low'
  disk_io      = 'none'
/
&SYSTEM
  ibrav        = 2
  celldm(1)    = ${a}
  nat          = 1
  ntyp         = 1
  ecutwfc      = ${wfc}
  ecutrho      = ${rho}
  occupations  = 'smearing'
  smearing     = 'marzari-vanderbilt'
  degauss      = 0.02
/
&ELECTRONS
  conv_thr     = 1.0d-10
  mixing_beta  = 0.3
  electron_maxstep = 200
/
ATOMIC_SPECIES
  ${el} ${EL_MASS[$el]} ${upf}
ATOMIC_POSITIONS crystal
  ${el} 0.0 0.0 0.0
K_POINTS automatic
  8 8 8 0 0 0
PWEOF
}

# pw_energy <outfile> -> total energy in Ry, or empty
pw_energy() { awk '/^!/ { e = $(NF-1) } END { if (e != "") print e }' "$1" 2>/dev/null; }
# pw_pressure <outfile> -> pressure in kbar, or empty
pw_pressure() { awk '/P=/ { for (i = 1; i <= NF; i++) if ($i == "P=") p = $(i+1)
                           if (p == "") { sub(/.*P=/, ""); p = $1 } } END { if (p != "") print p }' "$1" 2>/dev/null; }

# ---------------------------------------------------------------------------
# cutoff_scan_one <element>
#   Writes tests/cutoff-<el>.tsv  (ecutwfc  ecutrho  Etot  P  dE_mRy_per_atom)
#   and appends the recommendation to tests/cutoffs.tsv.
# ---------------------------------------------------------------------------
cutoff_scan_one() {
    local el=$1
    local upf fam dual wfc rho out tsv e p ref rec_wfc="" rec_rho=""
    upf=$(state_field "$el" 7)
    [ -n "$upf" ] && [ -f "$PROJECT_DIR/pseudos/$upf" ] || return 1

    deps_have_pw || { warn "pw.x not available; skipping cutoff scan"; return 1; }

    fam=${SPEC[family]}
    case $fam in nc) dual=${DUAL_NC:-4} ;; us) dual=${DUAL_US:-8} ;; *) dual=${DUAL_PAW:-8} ;; esac

    tsv=$PROJECT_DIR/tests/cutoff-$el.tsv
    printf '#ecutwfc\tecutrho\tEtot_Ry\tP_kbar\tdE_mRy_per_atom\n' > "$tsv"
    mkdir -p "$SCRATCH_DIR/pw"

    # The highest cutoff in the ladder is the reference the others are measured
    # against, so run it first and then walk upwards from the bottom.
    # The list is a space-separated string by design: it comes from
    # --cutoffs "30 40 50" on the command line and from the config file,
    # and both give one string that has to become several array entries.
    # shellcheck disable=SC2206
    local -a ladder=( ${CUTOFF_SCAN_LIST:-30 40 50 60 70 80 90 100} )
    local top=${ladder[${#ladder[@]}-1]}

    out=$PROJECT_DIR/tests/pw-$el-$top.out
    pw_write_input "$el" "$upf" "$top" "$(awk -v w="$top" -v d="$dual" 'BEGIN{printf "%d", w*d}')" \
                   "$PROJECT_DIR/tests/pw-$el-$top.in"
    qe_run "$PW_BIN" "$PROJECT_DIR/tests/pw-$el-$top.in" "$out" "${PW_TIMEOUT:-0}" "$PROJECT_DIR/tests"
    ref=$(pw_energy "$out")
    if [ -z "$ref" ]; then
        warn "$el: reference pw.x run at $top Ry did not converge; cutoff scan aborted"
        return 1
    fi

    for wfc in "${ladder[@]}"; do
        rho=$(awk -v w="$wfc" -v d="$dual" 'BEGIN { printf "%d", w * d }')
        out=$PROJECT_DIR/tests/pw-$el-$wfc.out
        if [ ! -s "$out" ]; then
            pw_write_input "$el" "$upf" "$wfc" "$rho" "$PROJECT_DIR/tests/pw-$el-$wfc.in"
            qe_run "$PW_BIN" "$PROJECT_DIR/tests/pw-$el-$wfc.in" "$out" "${PW_TIMEOUT:-0}" "$PROJECT_DIR/tests"
        fi
        e=$(pw_energy "$out"); p=$(pw_pressure "$out")
        if [ -z "$e" ]; then
            printf '%s\t%s\t-\t-\t-\n' "$wfc" "$rho" >> "$tsv"
            continue
        fi
        local de; de=$(awk -v a="$e" -v b="$ref" 'BEGIN { d = (a - b) * 1000; if (d < 0) d = -d; printf "%.3f", d }')
        printf '%s\t%s\t%s\t%s\t%s\n' "$wfc" "$rho" "$e" "${p:--}" "$de" >> "$tsv"
        if [ -z "$rec_wfc" ] && awk -v d="$de" -v t="${CUTOFF_TOL_MRY:-1.0}" 'BEGIN { exit (d <= t) ? 0 : 1 }'; then
            rec_wfc=$wfc; rec_rho=$rho
        fi
    done

    if [ -n "$rec_wfc" ]; then
        ok "$el  converged at ecutwfc=$rec_wfc Ry, ecutrho=$rec_rho Ry (within ${CUTOFF_TOL_MRY:-1.0} mRy/atom)"
    else
        rec_wfc=$top; rec_rho=$(awk -v w="$top" -v d="$dual" 'BEGIN{printf "%d", w*d}')
        warn "$el  not converged within ${CUTOFF_TOL_MRY:-1.0} mRy/atom below $top Ry -- extend CUTOFF_SCAN_LIST"
    fi
    printf '%s\t%s\t%s\t%s\n' "$el" "$rec_wfc" "$rec_rho" "$upf" >> "$PROJECT_DIR/tests/cutoffs.tsv"
    return 0
}

# ---------------------------------------------------------------------------
# validate_batch <element>... -- run whichever checks are enabled.
# ---------------------------------------------------------------------------
validate_batch() {
    local el slots=${MAX_PARALLEL_JOBS:-4}

    if [ "${RUN_LD1_TESTS:-1}" = 1 ]; then
        banner "Transferability tests ($(val_method_label "${SPEC[engine]:-ld1}"))"
        : > "$PROJECT_DIR/tests/transferability.tsv"
        for el in "$@"; do
            [ "$(state_status "$el")" = ok ] || [ "$(state_status "$el")" = ok-warn ] || continue
            while [ "$(jobs -rp | wc -l)" -ge "$slots" ]; do wait -n 2>/dev/null || sleep 1; done
            transfer_test_one "$el" &
        done
        wait
    fi

    if [ "${RUN_CUTOFF_SCAN:-0}" = 1 ]; then
        banner "Cutoff convergence scan (pw.x)"
        : > "$PROJECT_DIR/tests/cutoffs.tsv"
        # pw.x runs are already parallel internally when PARA_PREFIX is set, so
        # these are sequential unless the user is running serial QE.
        for el in "$@"; do
            [ "$(state_status "$el")" = ok ] || [ "$(state_status "$el")" = ok-warn ] || continue
            cutoff_scan_one "$el"
        done
    fi
    return 0
}

# ---------------------------------------------------------------------------
# compare.sh -- is this pseudopotential the same physics as that one?
#
# The question comes up whenever PseudoForge regenerates a published library
# locally: the file is not byte-identical to the published one and never will
# be -- a different version of the generator lays the radial grid out
# differently, and writes different numbers of points -- so comparing the files
# directly answers nothing.
#
# What can be compared is what the pseudopotential is *for*.  Both are put
# through the same crystal at the same cutoff and the total energies are
# compared.  That is grid-independent, code-version-independent, and is the
# quantity anyone using the file actually cares about.
#
# Thresholds, per atom, on the total-energy difference:
#
#   < 0.1 mRy    indistinguishable in practice
#   < 1 mRy      agrees to normal convergence standards
#   < 5 mRy      noticeably different; usable but worth understanding
#   otherwise    these are not the same pseudopotential
#
# 1 mRy/atom is the usual convergence target for a plane-wave calculation, so
# a difference below it cannot affect a converged result.
# ---------------------------------------------------------------------------

CMP_A_ENERGY=; CMP_B_ENERGY=; CMP_A_PRESS=; CMP_B_PRESS=; CMP_VERDICT=; CMP_DELTA=

# cmp_run <upf> <element> <ecut> <workdir> <label> -> "energy<TAB>pressure"
cmp_run() {
    local upf=$1 el=$2 ecut=$3 wd=$4 label=$5
    local a dual rho
    mkdir -p "$wd/out" || return 1
    cp -f "$upf" "$wd/$(basename "$upf")" 2>/dev/null

    a=$(pw_test_celldm "$el")
    dual=4
    case $(upf_get "$upf" type) in
        US|PAW) dual=8 ;;
    esac
    rho=$(awk -v e="$ecut" -v d="$dual" 'BEGIN { printf "%d", e * d }')

    cat > "$wd/$label.in" <<PWEOF
&CONTROL
  calculation = 'scf'
  prefix      = '$label'
  outdir      = '$wd/out'
  pseudo_dir  = '$wd'
  disk_io     = 'none'
  tstress     = .true.
  tprnfor     = .true.
/
&SYSTEM
  ibrav       = 2
  celldm(1)   = $a
  nat         = 1
  ntyp        = 1
  ecutwfc     = $ecut
  ecutrho     = $rho
  occupations = 'smearing'
  smearing    = 'marzari-vanderbilt'
  degauss     = 0.02
/
&ELECTRONS
  conv_thr    = 1.0d-10
  mixing_beta = 0.3
  electron_maxstep = 200
/
ATOMIC_SPECIES
  $el ${EL_MASS[$el]} $(basename "$upf")
ATOMIC_POSITIONS crystal
  $el 0.0 0.0 0.0
K_POINTS automatic
  8 8 8 0 0 0
PWEOF

    ( cd "$wd" && OMP_NUM_THREADS="${OMP_THREADS:-1}" \
        timeout "${PW_TIMEOUT:-3600}" "$PW_BIN" -in "$label.in" > "$label.out" 2>&1 )
    printf '%s\t%s\n' "$(pw_energy "$wd/$label.out")" "$(pw_pressure "$wd/$label.out")"
}

# ---------------------------------------------------------------------------
# cmp_pseudos <upf-a> <upf-b> [ecut]
#   Sets CMP_* and returns 0 when the two agree to better than 1 mRy/atom.
# ---------------------------------------------------------------------------
cmp_pseudos() {
    local a=$1 b=$2 ecut=${3:-} wd el_a el_b
    CMP_A_ENERGY=; CMP_B_ENERGY=; CMP_VERDICT=; CMP_DELTA=

    [ -s "$a" ] || { error "not readable: $a"; return 2; }
    [ -s "$b" ] || { error "not readable: $b"; return 2; }
    deps_have_pw || { error "pw.x is needed to compare pseudopotentials, and was not found"; return 2; }

    el_a=$(trim "$(upf_get "$a" element)")
    el_b=$(trim "$(upf_get "$b" element)")
    if [ "$el_a" != "$el_b" ]; then
        error "these are different elements: $el_a and $el_b"
        return 2
    fi
    el_exists "$el_a" || { error "unknown element '$el_a' in $a"; return 2; }

    # A cutoff both files are converged at, so the comparison measures the
    # pseudopotentials rather than the basis set.
    if [ -z "$ecut" ]; then
        local wa ra wb rb
        read -r wa ra <<<"$(upf_suggested_cutoffs "$a" nc)"
        read -r wb rb <<<"$(upf_suggested_cutoffs "$b" nc)"
        ecut=$(awk -v x="$wa" -v y="$wb" 'BEGIN { m = (x > y ? x : y); if (m < 60) m = 60; printf "%d", m * 1.3 }')
    fi

    wd=$(mktemp -d)
    info "comparing $el_a at ecutwfc = $ecut Ry"
    IFS=$'\t' read -r CMP_A_ENERGY CMP_A_PRESS < <(cmp_run "$a" "$el_a" "$ecut" "$wd" cmp_a)
    IFS=$'\t' read -r CMP_B_ENERGY CMP_B_PRESS < <(cmp_run "$b" "$el_b" "$ecut" "$wd" cmp_b)
    [ "${PF_KEEP_SCRATCH:-0}" = 1 ] || rm -rf "$wd"

    if [ -z "$CMP_A_ENERGY" ] || [ -z "$CMP_B_ENERGY" ]; then
        error "one of the two runs did not converge; cannot compare"
        CMP_VERDICT=failed
        return 2
    fi

    CMP_DELTA=$(awk -v x="$CMP_A_ENERGY" -v y="$CMP_B_ENERGY" \
        'BEGIN { d = x - y; if (d < 0) d = -d; printf "%.6f", d * 1000 }')
    CMP_VERDICT=$(awk -v d="$CMP_DELTA" 'BEGIN {
        if      (d < 0.1) print "identical"
        else if (d < 1.0) print "equivalent"
        else if (d < 5.0) print "different"
        else              print "incompatible" }')

    case $CMP_VERDICT in
        identical|equivalent) return 0 ;;
        *) return 1 ;;
    esac
}

cmp_report() {
    local a=$1 b=$2
    printf '\n'
    printf '  %-28s %16s Ry   %9s kbar\n' "$(basename "$a")" "$CMP_A_ENERGY" "${CMP_A_PRESS:-?}"
    printf '  %-28s %16s Ry   %9s kbar\n' "$(basename "$b")" "$CMP_B_ENERGY" "${CMP_B_PRESS:-?}"
    printf '\n  total energy differs by %s mRy/atom\n' "$CMP_DELTA"
    # A generic cell far from equilibrium exaggerates differences in the core
    # region, so say so when the comparison was made under heavy compression.
    if [ -n "${CMP_A_PRESS:-}" ]; then
        local _absp
        _absp=${CMP_A_PRESS#-}
        if awk -v p="$_absp" 'BEGIN { exit (p > 400) ? 0 : 1 }' 2>/dev/null; then
            printf '  note: the probe cell sits at %s kbar, well away from equilibrium;\n' "$CMP_A_PRESS"
            printf '        differences are amplified there\n'
        fi
    fi
    case $CMP_VERDICT in
        identical)
            ok "indistinguishable in practice (below 0.1 mRy/atom)" ;;
        equivalent)
            ok "agree to normal convergence standards (below 1 mRy/atom)"
            info "a residual difference at this level is expected when the two were"
            info "produced by different versions of the generator" ;;
        different)
            warn "noticeably different (1-5 mRy/atom) -- usable, but understand why before relying on it" ;;
        incompatible)
            error "these do not describe the same physics (over 5 mRy/atom)" ;;
    esac
    if [ -n "${CMP_A_PRESS:-}" ] && [ -n "${CMP_B_PRESS:-}" ]; then
        awk -v x="$CMP_A_PRESS" -v y="$CMP_B_PRESS" 'BEGIN {
            d = x - y; if (d < 0) d = -d
            if (d > 5) printf "  note: pressures differ by %.1f kbar, which is more than the energy\n        difference suggests -- check the cut-off radii if this matters to you\n", d }'
    fi
    printf '\n'
}
