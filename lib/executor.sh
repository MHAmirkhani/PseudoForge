# shellcheck shell=bash
# ---------------------------------------------------------------------------
# executor.sh -- run a generator engine and land a UPF in pseudos/.
#
# Each engine has its own calling convention, its own way of reporting trouble,
# and its own distance from UPF:
#
#   ld1       stdin -> stdout, writes the UPF itself
#   oncvpsp   stdin -> stdout, with the UPF embedded in the report between
#             PSP_UPF and END_PSP markers
#   uspp      two runs with six positional file arguments, producing a binary
#             Vanderbilt file that goes through reform.x and then upfconv.x
#   fhi98pp   no arguments at all: reads fort.20/fort.22 from the working
#             directory and scatters its output across a dozen fort.NN files
#
# Every engine runs in its own scratch directory so parallel jobs cannot
# collide over those fixed unit numbers.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# exec_env -- environment every engine run needs.
#
# OMP_NUM_THREADS is clamped to 1 on purpose.  These are single-atom radial
# solvers; the linear algebra is microseconds of real work, and a threaded BLAS
# spends far longer spin-waiting on barriers than computing.  On a machine that
# is already busy this turns a 1.5-second run into one that never finishes.
# PseudoForge's own parallelism is one element per core, which is the level that
# actually scales.
# ---------------------------------------------------------------------------
exec_env() {
    printf 'OMP_NUM_THREADS=%s\n' "${OMP_THREADS:-1}"
    printf 'OMP_PROC_BIND=false\n'
    printf 'MKL_NUM_THREADS=%s\n' "${OMP_THREADS:-1}"
    printf 'OPENBLAS_NUM_THREADS=%s\n' "${OMP_THREADS:-1}"
}

# exec_run <binary> <workdir> <logfile> <timeout> [stdin-file] [args...]
exec_run() {
    local bin=$1 wd=$2 log=$3 tmo=$4 stdin=$5; shift 5
    local rc
    mkdir -p "$wd" || return 1
    (
        cd "$wd" || exit 1
        # shellcheck disable=SC2046
        export $(exec_env | tr '\n' ' ')
        if [ "${tmo:-0}" != 0 ] && have timeout; then
            if [ -n "$stdin" ]; then
                timeout "$tmo" "$bin" "$@" < "$stdin" > "$log" 2>&1
            else
                timeout "$tmo" "$bin" "$@" < /dev/null > "$log" 2>&1
            fi
        else
            if [ -n "$stdin" ]; then
                "$bin" "$@" < "$stdin" > "$log" 2>&1
            else
                "$bin" "$@" < /dev/null > "$log" 2>&1
            fi
        fi
    )
    rc=$?
    [ $rc -eq 124 ] && warn "$(basename "$bin"): timed out after ${tmo}s"
    return $rc
}

# ---------------------------------------------------------------------------
# exec_generate <engine> <element> <deck> <expected> <workdir> <log>
#   -> echoes the path of the finished UPF, or fails.
#
# EXEC_MESSAGE carries a human explanation on failure.
# EXEC_NATIVE carries the engine's own output file when no UPF could be made.
# ---------------------------------------------------------------------------
EXEC_MESSAGE=
EXEC_NATIVE=
EXEC_WARNING=
EXEC_NOTE=

# exec_upf_to_xml <UPF-file> <element>
#
# XML is not a native output of any engine: it is a conversion from UPF by
# QE's upfconv.x -x.  Doing it here, once, means every engine that writes a
# UPF gains the xml output without a per-engine change.  The conversion is
# exact -- pw.x gives identical results from the .UPF and the .xml.
exec_upf_to_xml() {
    local upf=$1 el=$2 conv xdir xbase produced dest
    conv=$(exec_find_upfconv) || return 1
    xdir=$(dirname "$upf")
    xbase=$(basename "$upf")
    ( cd "$xdir" && OMP_NUM_THREADS=1 timeout 300 "$conv" -x "$xbase" ) >/dev/null 2>&1
    produced="$xdir/${xbase%.UPF}.xml"
    [ -s "$produced" ] || produced="$xdir/${xbase%.*}.xml"
    [ -s "$produced" ] || produced="$xdir/$xbase.xml"
    [ -s "$produced" ] || return 1
    # Take the destination name from the UPF that was actually written, not
    # from exec_upf_name.  The two can differ -- an ld1 recipe calls its
    # output Si.pbe-n-nc.UPF, while exec_upf_name would produce Si.pbe-psl --
    # and the pair must share a stem so a user looking for the xml of a
    # specific UPF finds it beside the UPF rather than under a name they
    # never saw.
    dest=$PROJECT_DIR/pseudos/$(basename "${upf%.UPF}.xml")
    mkdir -p "$PROJECT_DIR/pseudos" 2>/dev/null
    mv -f "$produced" "$dest" || return 1
    printf '%s\n' "$dest"
}

exec_generate() {
    local eng=$1 el=$2 deck=$3 expected=$4 wd=$5 log=$6
    local rc=1 upf="" out
    EXEC_MESSAGE=; EXEC_NATIVE=; EXEC_WARNING=; EXEC_NOTE=
    mkdir -p "$wd" || return 1
    out=$wd/.pf_engine_out

    # Redirecting to a file rather than capturing with $( ) keeps the engine
    # function in *this* shell, so the EXEC_* variables it sets survive.  A
    # command substitution would run it in a subshell and every diagnostic it
    # produced would be silently discarded.
    case $eng in
        ld1)     exec_ld1     "$el" "$deck" "$expected" "$wd" "$log" > "$out" ;;
        oncvpsp) exec_oncvpsp "$el" "$deck" "$expected" "$wd" "$log" > "$out" ;;
        uspp)    exec_uspp    "$el" "$deck" "$expected" "$wd" "$log" > "$out" ;;
        fhi98pp) exec_fhi98pp "$el" "$deck" "$expected" "$wd" "$log" > "$out" ;;
        opium)   exec_opium   "$el" "$deck" "$expected" "$wd" "$log" > "$out" ;;
        gth)     exec_gth     "$el" "$deck" "$expected" "$wd" "$log" > "$out" ;;
        adpack)  exec_adpack  "$el" "$deck" "$expected" "$wd" "$log" > "$out" ;;
        atompaw) exec_atompaw "$el" "$deck" "$expected" "$wd" "$log" > "$out" ;;
        ape)     exec_ape     "$el" "$deck" "$expected" "$wd" "$log" > "$out" ;;
        *) EXEC_MESSAGE="no executor for engine '$eng'"
           printf '%s%s%s%s%s
' "" "$EXEC_MESSAGE" "" "" ""
           return 1 ;;
    esac
    rc=$?
    upf=$(head -1 "$out" 2>/dev/null)
    rm -f "$out"

    # XML is a conversion from UPF, not a native format, so no engine writes
    # it directly.  When the caller asked for it and the engine produced a
    # UPF, run QE's upfconv.x -x once here and every engine benefits without
    # touching each exec_* function.
    if [ -n "$upf" ] && [ -s "$upf" ]; then
        case " ${SPEC[formats]:-upf} " in
            *" xml "*)
                if exec_upf_to_xml "$upf" "$el" >/dev/null 2>&1; then
                    EXEC_NOTE="${EXEC_NOTE:+$EXEC_NOTE; }xml written alongside"
                fi
                ;;
        esac
    fi

    # Everything the caller needs travels on one line, for the same reason.
    printf '%s%s%s%s%s
' "$upf" "$EXEC_MESSAGE" "$EXEC_NATIVE" "$EXEC_WARNING" "$EXEC_NOTE"
    return $rc
}

# ---------------------------------------------------------------------------
# ld1.x
# ---------------------------------------------------------------------------
exec_ld1() {
    local el=$1 deck=$2 upf=$3 wd=$4 log=$5 rc
    local bin; bin=$(eng_resolve ld1) || { EXEC_MESSAGE="ld1.x not found"; return 1; }

    exec_run "$bin" "$wd" "$log" "${LD1_TIMEOUT:-900}" "$deck"
    rc=$?
    if [ -f "$wd/$upf" ]; then
        printf '%s\n' "$wd/$upf"
        return 0
    fi
    EXEC_MESSAGE=$(ld1_message "$log")
    [ -n "$EXEC_MESSAGE" ] || EXEC_MESSAGE="ld1.x exited $rc without writing $upf"
    return 1
}

# ---------------------------------------------------------------------------
# ONCVPSP
#
# The UPF is embedded in the report between the PSP_UPF and END_PSP markers.
# Upstream's scripts/extract.sh does this with awk and a hardcoded install
# path; the awk is reproduced here so PseudoForge does not depend on that script.
# ---------------------------------------------------------------------------
exec_oncvpsp() {
    local el=$1 deck=$2 base=$3 wd=$4 log=$5 rc bin upf diag
    local _gm _gp _gcut

    bin=$(eng_binary_for_rel oncvpsp "${SPEC[rel]}") || {
        EXEC_MESSAGE="oncvpsp binary not found"; return 1; }
    [ -x "$bin" ] || { EXEC_MESSAGE="$bin is not executable"; return 1; }

    exec_run "$bin" "$wd" "$log" "${ONCVPSP_TIMEOUT:-1800}" "$deck"
    rc=$?

    # ONCVPSP is the authority on whether it produced a pseudopotential, and it
    # says so by emitting one.  It also prints diagnostics with the word ERROR
    # in them -- run_diag failures during the log-derivative analysis, for
    # instance -- while still finishing the job.  Treating those as fatal threw
    # away perfectly good output, including from PseudoDojo's own published
    # decks, so the file decides and the diagnostics become a warning.
    upf=$wd/$(exec_upf_name "$el")
    if grep -q 'PSP_UPF' "$log" 2>/dev/null; then
        awk 'BEGIN { o = 0 } /END_PSP/ { o = 0 } { if (o) print } /PSP_UPF/ { o = 1 }' \
            "$log" > "$upf"
    fi

    # psfile=both puts a PSP_UPF block and a PSPCODE8 block in the same log.
    # The UPF is the primary result; the psp8 is collected alongside it the way
    # OPIUM's and AtomPAW's extra formats are, so that --format upf,psp8 gives
    # you both files rather than quietly giving you one.
    if [ -s "$upf" ] && grep -q 'PSPCODE8' "$log" 2>/dev/null; then
        case " ${SPEC[formats]:-upf} " in
            *" psp8 "*)
                local p8x
                p8x=$PROJECT_DIR/pseudos/$(exec_upf_name "$el")
                p8x=${p8x%.UPF}.psp8
                mkdir -p "$PROJECT_DIR/pseudos" 2>/dev/null
                awk 'BEGIN { o = 0 } /END_PSP/ { o = 0 } { if (o) print } /PSPCODE8/ { o = 1 }'                     "$log" > "$p8x"
                if [ -s "$p8x" ]; then
                    EXEC_NOTE="${EXEC_NOTE:+$EXEC_NOTE; }psp8 written alongside ($(basename "$p8x"))"
                else
                    rm -f "$p8x"
                    EXEC_WARNING="${EXEC_WARNING:+$EXEC_WARNING; }psp8 was requested and the log carries no PSPCODE8 block"
                fi ;;
        esac
    fi

    if [ ! -s "$upf" ]; then
        if grep -q 'PSPCODE8' "$log" 2>/dev/null; then
            EXEC_NATIVE=$wd/$el.psp8
            awk 'BEGIN { o = 0 } /END_PSP/ { o = 0 } { if (o) print } /PSPCODE8/ { o = 1 }' \
                "$log" > "$EXEC_NATIVE"
            # psp8, which ONCVPSP writes natively. This used to be reported
            # as a failure and then `return 1`, so a psp8 run threw away a
            # perfectly good file. When psp8 is what was asked for, it is the
            # result rather than a disappointment.
            case " ${SPEC[formats]:-upf} " in
                *" psp8 "*)
                    if [ -s "$EXEC_NATIVE" ]; then
                        # Name it the way every other output is named, so a
                        # psp8 run sits in pseudos/ beside the UPFs rather
                        # than as a bare "Si.psp8" with no functional in it.
                        local p8
                        p8=$wd/$(exec_upf_name "$el")
                        p8=${p8%.UPF}.psp8
                        mv -f "$EXEC_NATIVE" "$p8" && EXEC_NATIVE=$p8
                        EXEC_NOTE="psp8, written natively by ONCVPSP; ABINIT reads it directly"
                        printf '%s
' "$EXEC_NATIVE"
                        return 0
                    fi ;;
            esac
            EXEC_MESSAGE="the deck asked for psp8 rather than UPF"
        else
            EXEC_MESSAGE=$(exec_oncvpsp_message "$log")
            [ -n "$EXEC_MESSAGE" ] || EXEC_MESSAGE="ONCVPSP exited $rc without producing a pseudopotential"
        fi
        return 1
    fi

    # Ghosts.  ONCVPSP reports two different things under that word, and
    # treating them alike either cries wolf or hides a real defect:
    #   GHOST(-)  a *bound* ghost state -- the pseudopotential is unusable
    #   GHOST(+)  a highly-localized positive-energy ghost, quoted with the
    #             cutoff it appears above.  Well-tested published tables carry
    #             these (SG15's own Si deck does); they matter only if you run
    #             near or above that cutoff.
    _gm=$(grep -c 'GHOST(-)' "$log" 2>/dev/null || true)
    _gp=$(grep -c 'GHOST(+)' "$log" 2>/dev/null || true)
    if [ "${_gm:-0}" -gt 0 ]; then
        EXEC_WARNING="${_gm} BOUND ghost state(s) -- this pseudopotential is not usable; see the log"
    elif [ "${_gp:-0}" -gt 0 ]; then
        # the line is "  l  <radius>/rc  E-diag  E-cutoff  WARNING - GHOST(+)",
        # so take the last numeric field before the word WARNING
        _gcut=$(awk '/GHOST\(\+\)/ {
                    for (i = 1; i <= NF; i++) if ($i == "WARNING") { print $(i-1); exit }
                 }' "$log" 2>/dev/null)
        EXEC_NOTE="positive-energy ghost above ~${_gcut:-?} Ry (informational; common in published tables)"
    fi

    # Any remaining diagnostic is worth surfacing, but it did not stop the run.
    if [ -z "${EXEC_WARNING:-}" ]; then
        diag=$(exec_oncvpsp_message "$log")
        [ -n "$diag" ] && EXEC_NOTE="${EXEC_NOTE:+$EXEC_NOTE; }diagnostic: $diag"
    fi

    printf '%s\n' "$upf"
}

exec_oncvpsp_message() {
    # ONCVPSP reports as "<routine>: ERROR <what went wrong>" and keeps going,
    # so the last such line is the one that actually stopped it.
    awk '
        /(^|[[:space:]:])ERROR([[:space:]]|$)/ { last = $0 }
        /Bad input/ { last = $0 }
        END { if (last != "") { sub(/^[[:space:]]+/, "", last); print last } }
    ' "$1" 2>/dev/null | cut -c1-200
}

# ---------------------------------------------------------------------------
# USPP (Vanderbilt)
#
#   runatom.x <in.adat> <out> <ae-file> <atwf> <logd> <uspp-out>
#
# Run once for the all-electron reference, once for the pseudopotential, then
# reform.x turns the binary into the ASCII .van that QE's upfconv.x can read.
# ---------------------------------------------------------------------------
exec_uspp() {
    local el=$1 deck=$2 base=$3 wd=$4 log=$5 rc bin reform native van upf
    local aedeck=${deck%.ps.adat}.ae.adat

    bin=$(eng_resolve uspp) || { EXEC_MESSAGE="runatom.x not found"; return 1; }
    [ -f "$aedeck" ] || { EXEC_MESSAGE="missing the all-electron deck $aedeck"; return 1; }

    cp -f "$aedeck" "$wd/$el.ae.adat"
    cp -f "$deck"   "$wd/$el.ps.adat"

    # stage 1: all-electron reference
    exec_run "$bin" "$wd" "$log" "${USPP_TIMEOUT:-1800}" "" \
             "$el.ae.adat" "$el.ae.out" "$el.ae" "$el.ae.atwf" "$el.ae.logd" dummy
    rc=$?
    if [ ! -s "$wd/$el.ae" ]; then
        EXEC_MESSAGE=$(exec_uspp_message "$log")
        [ -n "$EXEC_MESSAGE" ] || EXEC_MESSAGE="the USPP all-electron run failed (exit $rc)"
        return 1
    fi

    # stage 2: the pseudopotential itself
    exec_run "$bin" "$wd" "$log.ps" "${USPP_TIMEOUT:-1800}" "" \
             "$el.ps.adat" "$el.ps.out" "$el.ae" "$el.ps.atwf" "$el.ps.logd" "$el.uspp"
    rc=$?
    cat "$log.ps" >> "$log" 2>/dev/null; rm -f "$log.ps"
    native=$wd/$el.uspp
    if [ ! -s "$native" ]; then
        EXEC_MESSAGE=$(exec_uspp_message "$log")
        [ -n "$EXEC_MESSAGE" ] || EXEC_MESSAGE="the USPP pseudopotential run failed (exit $rc)"
        return 1
    fi
    EXEC_NATIVE=$native

    # runatom.x writes an unformatted (binary) file; QE reads the ASCII form.
    reform=$(exec_find_reform) || {
        EXEC_MESSAGE="USPP produced $el.uspp but reform.x is missing, so it cannot be converted to UPF"
        return 1
    }
    van=$wd/$el.van
    rm -f "$van"
    ( cd "$wd" && printf '1\n%s\n%s\n' "$el.uspp" "$el.van" | "$reform" ) >> "$log" 2>&1
    [ -s "$van" ] || {
        EXEC_MESSAGE="reform.x could not convert $el.uspp to ASCII"
        return 1
    }

    upf=$wd/$(exec_upf_name "$el")
    exec_upfconv "$van" "$upf" "$log" || {
        EXEC_MESSAGE="upfconv.x could not convert $el.van to UPF"
        return 1
    }

    # QE's Vanderbilt reader (readvan, upflib/read_uspp.f90) reads irel from
    # the file and never uses it, so the relativistic attribute upfconv writes
    # is whatever the structure held: two decks with the same irel = 2 came
    # out "scalar" and "no". The deck is what runatom solved -- runatom.f:
    # irel 0 non-relativistic, 1 Dirac (all-electron only), 2 Koelling-Harmon
    # scalar-relativistic -- so the header is written from it.
    local irel r=""
    irel=$(awk '/ncspvs,irel/ { print $2; exit }' "$aedeck" 2>/dev/null)
    case $irel in 0) r=no ;; 2) r=scalar ;; esac
    [ -n "$r" ] && sed -i -E "0,/relativistic=\"[^\"]*\"/s//relativistic=\"$r\"/" "$upf"

    # Native uspp and van: the binary and ASCII forms of the same Vanderbilt
    # dataset.  Both come from the same solve, so writing them costs nothing.
    # They are kept because the uspp code's own binary is what reproduces a
    # run, and the .van is what QE's upfconv reads.
    local dest nn=0
    mkdir -p "$PROJECT_DIR/pseudos" 2>/dev/null
    case " ${SPEC[formats]:-upf} " in
        *" uspp "*)
            dest=$PROJECT_DIR/pseudos/$(exec_upf_name "$el"); dest=${dest%.UPF}.uspp
            cp -f "$wd/$el.uspp" "$dest" 2>/dev/null && nn=$((nn + 1)) ;;
    esac
    case " ${SPEC[formats]:-upf} " in
        *" van "*)
            dest=$PROJECT_DIR/pseudos/$(exec_upf_name "$el"); dest=${dest%.UPF}.van
            cp -f "$van" "$dest" 2>/dev/null && nn=$((nn + 1)) ;;
    esac
    [ "$nn" -gt 0 ] && EXEC_NOTE="${EXEC_NOTE:+$EXEC_NOTE; }$nn native format(s) written"

    printf '%s\n' "$upf"
}

exec_uspp_message() {
    grep -iE 'error|fatal|not converged|stopping' "$1" 2>/dev/null | head -1 | cut -c1-200
}

# reform.x is built beside runatom.x, or lives in the USPP source tree.
exec_find_reform() {
    local d cand
    for cand in "$(eng_bindir)/reform.x" "${USPP_REFORM_BIN:-}"; do
        [ -n "$cand" ] && [ -x "$cand" ] && { printf '%s\n' "$cand"; return 0; }
    done
    for d in "${USPP_ROOT:-}" "${USPP_SRC_DIR:-}" "$(eng_builddir)/uspp" "$(eng_builddir)/uspp"/*; do
        [ -n "$d" ] && [ -x "$d/Utils/reform.x" ] && { printf '%s\n' "$d/Utils/reform.x"; return 0; }
    done
    return 1
}

# ---------------------------------------------------------------------------
# fhi98PP
#
# fhipp.x takes no arguments: it reads fort.20 and fort.22 from the current
# directory and writes fort.NN files.  The .cpi is assembled from fort.40-44
# exactly the way upstream's psgen does it.
# ---------------------------------------------------------------------------
exec_fhi98pp() {
    local el=$1 deck=$2 base=$3 wd=$4 log=$5 rc bin cpi upf
    local fort20=${deck%.ini}.fort20

    bin=$(eng_resolve fhi98pp) || { EXEC_MESSAGE="fhipp.x not found"; return 1; }
    [ -f "$fort20" ] || { EXEC_MESSAGE="missing the control file $fort20"; return 1; }

    cp -f "$fort20" "$wd/fort.20"
    # t/h have to reach the Fortran namelist quoted
    sed -e "s/ t/ 't'/g" -e "s/ h/ 'h'/g" -e "s/ T/ 't'/g" -e "s/ H/ 'h'/g" \
        "$deck" > "$wd/fort.22"

    exec_run "$bin" "$wd" "$log" "${FHI98PP_TIMEOUT:-1800}" ""
    rc=$?

    if [ ! -s "$wd/fort.40" ]; then
        EXEC_MESSAGE=$(grep -iE 'error|stop|fatal' "$log" 2>/dev/null | head -1 | cut -c1-200)
        [ -n "$EXEC_MESSAGE" ] || EXEC_MESSAGE="fhipp.x exited $rc without producing a pseudopotential"
        return 1
    fi

    cpi=$wd/$el.cpi
    exec_fhi_assemble_cpi "$wd" "$cpi" || {
        EXEC_MESSAGE="could not assemble the .cpi from fhipp.x output"; return 1; }
    EXEC_NATIVE=$cpi

    upf=$wd/$(exec_upf_name "$el")
    if exec_upfconv "$cpi" "$upf" "$log"; then
        printf '%s\n' "$upf"
        return 0
    fi

    # Not a PseudoForge failure: QE 7.x dropped the .cpi/.fhi branch from its
    # format dispatch (upflib/read_ps.f90 handles .psml, .van/.vdb, .RRKJ3 and
    # .gth, then falls through to read_ncpp).  read_fhi is still linked into
    # upfconv.x and still advertised by its -h text, but nothing calls it.
    # Asking for .cpi and getting .cpi is success, not failure.  The conversion
    # gap only matters to someone who wanted UPF.
    case " ${SPEC[formats]:-upf} " in
        *" cpi "*)
            EXEC_NOTE="${EXEC_NOTE:+$EXEC_NOTE; }written as .cpi (ABINIT-compatible)"
            printf '%s
' "$cpi"
            return 0 ;;
    esac
    EXEC_MESSAGE="generated $el.cpi, but this Quantum ESPRESSO cannot convert FHI files to UPF -- rerun with --format cpi to keep it (see docs/reference/engines.md)"
    return 1
}

exec_fhi_assemble_cpi() {
    local wd=$1 out=$2 p n
    [ -s "$wd/fort.40" ] || return 1
    n=$(ls "$wd"/fort.4[0-4] 2>/dev/null | wc -l | tr -d ' ')
    {
        printf '%s %s\n' "$(head -1 "$wd/fort.40" | awk '{print $NF}')" "$n"
        # ten rows of fit parameters the format reserves but fhi98PP never uses
        printf '  0.0000    0.0000    0.0000   0.0000\n'
        for _ in 1 2 3 4 5 6 7 8 9; do
            printf '  0.0000    .00e+00   .00e+00\n'
        done
        for p in "$wd"/fort.4[0-4]; do
            [ -e "$p" ] || continue
            head -1 "$p" | awk '{ print $2, " " $3 }'
            tail -n +2 "$p"
        done
        # the partial core density, when the run produced one
        [ -e "$wd/fort.27" ] && cat "$wd/fort.27"
    } > "$out"
    [ -s "$out" ]
}

# ---------------------------------------------------------------------------
# Format conversion through QE's upfconv.x.
# ---------------------------------------------------------------------------
exec_upfconv() {   # exec_upfconv <infile> <outfile> <log>
    local in=$1 out=$2 log=$3 conv produced
    conv=$(exec_find_upfconv) || return 1
    ( cd "$(dirname "$in")" \
      && OMP_NUM_THREADS=1 timeout 300 "$conv" -u "$(basename "$in")" ) >> "$log" 2>&1
    # upfconv.x names its output from the input, and not always the same way:
    # `Si.van` gives `Si.van.UPF2`, but an input already ending in .UPF has
    # that suffix stripped first (upfconv.f90 takes the prefix up to '.UPF'),
    # so `ape-v1.UPF` gives `ape-v1.UPF2`. Looking only for the first form
    # made every APE rewrite report failure.
    produced=$in.UPF2
    [ -s "$produced" ] || produced=${in%.*}.UPF2
    [ -s "$produced" ] || return 1
    mv -f "$produced" "$out"
    [ -s "$out" ] || return 1
    # QE's converter writes a header QE itself cannot always read back
    exec_upf_normalise "$out"
}

exec_find_upfconv() {
    local c
    for c in "${UPFCONV_BIN:-}" "${QE_ROOT_DIR:+$QE_ROOT_DIR/upfconv.x}" \
             "${QE_ROOT_DIR:+$QE_ROOT_DIR/bin/upfconv.x}" upfconv.x; do
        [ -n "$c" ] || continue
        [ -x "$c" ] && { printf '%s\n' "$c"; return 0; }
        have "$c" && { command -v "$c"; return 0; }
    done
    return 1
}

# ---------------------------------------------------------------------------
# The file name a generated pseudopotential gets.
#
# Engine and provenance are both in the name on purpose: dropping an ONCVPSP
# file and a PSlibrary file for the same element into one pseudo_dir should
# never be ambiguous.
# ---------------------------------------------------------------------------
exec_upf_name() {
    local el=$1 fct tag eng
    fct=$(xc_tag "${SPEC[xc]}" "${SPEC[rel]}")
    eng=${SPEC[engine]:-ld1}
    case $eng in
        oncvpsp) tag=oncv ;;
        uspp)    tag=uspp ;;
        fhi98pp) tag=fhi ;;
        opium)   tag=opium ;;
        gth)     tag=gth ;;
        adpack)  tag=adpack ;;
        atompaw) tag=atompaw ;;
        ape)     tag=ape ;;
        *)       tag=psl ;;
    esac
    printf '%s.%s-%s%s.UPF\n' "$el" "$fct" "$tag" "${SPEC[tag_suffix]:-}"
}

# ---------------------------------------------------------------------------
# exec_install <upf> <project> <element>  -- move a finished file into pseudos/
# and record where it came from.
# ---------------------------------------------------------------------------
exec_install() {
    local upf=$1 project=$2 el=$3 dest
    dest=$project/pseudos/$(basename "$upf")
    mkdir -p "$project/pseudos" || return 1
    # Some exec_* functions (exec_atompaw for meta-GGA in particular) do the
    # copy to pseudos/ themselves and return the project path as $upf.  Plain
    # `cp -f X X` refuses that, so treat a same-file copy as already done.
    if [ "$upf" -ef "$dest" ]; then
        :
    else
        cp -f "$upf" "$dest" || return 1
    fi
    printf '%s\n' "$dest"
}

# Keep an engine's native-format output alongside the UPF, so a run that could
# not be converted still leaves something usable behind.
exec_keep_native() {
    local native=$1 project=$2
    [ -n "$native" ] && [ -s "$native" ] || return 0
    mkdir -p "$project/pseudos/native" || return 1
    cp -f "$native" "$project/pseudos/native/" || return 1
    printf '%s/pseudos/native/%s\n' "$project" "$(basename "$native")"
}

# ---------------------------------------------------------------------------
# generate_one_engine <element>
#
# The non-ld1 path.  ld1 keeps its own routine in run.sh because it carries the
# auto-fix loop, which is built on ld1's error vocabulary and does not
# generalise: "widen rcut and retry" means something different to ONCVPSP's
# optimiser than it does to ld1's Troullier-Martins construction, and guessing
# there would produce confident nonsense.  These engines get one honest attempt
# and a clear message.
# ---------------------------------------------------------------------------
generate_one_engine() {
    local el=$1
    local eng=${SPEC[engine]} t0 deck expected work log upf dest native
    local status=fail message="" seconds=0 prov="" src=""

    t0=$(now)
    work=$SCRATCH_DIR/$$-$el
    log=$PROJECT_DIR/logs/$el.log
    mkdir -p "$work" "$PROJECT_DIR/logs"

    if ! IFS=$'\x1f' read -r deck expected prov src < <(ib_build "$eng" "$el" "$PROJECT_DIR/inputs"); then
        status=skip
        message="${IB_MESSAGE:-no input parameters available for $el with $eng}"
    elif [ -z "${deck:-}" ]; then
        status=skip
        message="no input parameters available for $el with $eng"
    elif [ -n "${SPEC[rcut_scale]:-}" ] \
         && ! ib_scale_rc "$eng" "$deck" "${SPEC[rcut_scale]}" 2>"$work/rcs.err"; then
        # The deck in inputs/ is what ran, so it is scaled in place and the
        # record matches the run. A deck that cannot be scaled fails the
        # element; it is never run unscaled under a -rc name.
        status=fail
        message=$(head -1 "$work/rcs.err" | sed 's/^ERROR *//')
        [ -n "$message" ] || message="could not apply --rcut-scale ${SPEC[rcut_scale]} to the $eng deck"
    else
        local emsg enative ewarn enote
        if IFS=$'\x1f' read -r upf emsg enative ewarn enote                < <(exec_generate "$eng" "$el" "$deck" "$expected" "$work" "$log")            && [ -n "$upf" ]; then
            if dest=$(exec_install "$upf" "$PROJECT_DIR" "$el"); then
                local problems
                if problems=$(upf_validate_any "$dest" 2>&1); then
                    status=ok
                    [ -n "$problems" ] && { status=ok-warn; message=$(printf '%s' "$problems" | head -1); }
                    # Both can matter at once.  An AtomPAW meta-GGA run sets
                    # ewarn ("no UPF for meta-GGA") while the validator
                    # separately finds the mislabelled type attribute; letting
                    # ewarn overwrite the validator hid the second one entirely.
                    if [ -n "${ewarn:-}" ]; then
                        status=ok-warn
                        if [ -n "$message" ] && [ "$message" != "$ewarn" ]; then
                            message="$ewarn; $message"
                        else
                            message=$ewarn
                        fi
                    elif [ -n "${enote:-}" ] && [ -z "$message" ]; then message=$enote; fi
                else
                    status=fail
                    message=$(printf '%s' "$problems" | head -1)
                    rm -f "$dest"
                fi
                expected=$(basename "$dest")
            else
                message="could not install the finished file"
            fi
        else
            message=$emsg
            # keep whatever the engine did manage to write
            if [ -n "$enative" ]; then
                native=$(exec_keep_native "$enative" "$PROJECT_DIR")
                [ -n "$native" ] && message="$message (native output kept: ${native##*/})"
            fi
        fi
    fi

    seconds=$(( $(now) - t0 ))
    [ "${PF_KEEP_SCRATCH:-0}" = 1 ] || rm -rf "$work"

    case $status in
        ok)      ok   "$el  ->  $expected  ($(human_time "$seconds"))" ;;
        ok-warn) warn "$el  ->  $expected  -- $message" ;;
        skip)    info "$el  skipped: $message" ;;
        *)       error "$el  FAILED: $message" ;;
    esac

    state_record "$el" "${SPEC[family]}" "${SPEC[profile]}" "${SPEC[xc]}" "${SPEC[rel]}" \
                 "${prov:-$eng}" "$expected" "$status" 0 "$seconds" "$message"
}

# ---------------------------------------------------------------------------
# run_online_batch <elements...> -- the --source online path.
#
# Reports every URL it tries and which step of the chain it is on, then, for
# anything it could not find, offers to generate it locally instead -- which is
# the whole point of having both paths in one tool.
# ---------------------------------------------------------------------------
run_online_batch() {
    local el file status message seconds t0 total=0 got=0
    local -a missing=()

    banner "Downloading"
    info "chain: official source -> mirror (${MIRROR_URL:-none}) -> generate locally"
    for el in "$@"; do
        if ! state_should_run "$el"; then
            info "$el  already present (resume)"
            continue
        fi
        total=$((total + 1))
        t0=$(now); status=fail; message=""
        info "$el:"
        local forigin fmsg
        if IFS=$'' read -r file forigin fmsg                < <(fetch_and_install "${SPEC[profile]}" "$el" "$PROJECT_DIR") && [ -n "$file" ]; then
            status=ok
            message=$forigin
            got=$((got + 1))
            ok "$el  <-  $(basename "$file")"
        else
            message=${fmsg:-not available online}
            error "$el  $message"
            missing+=("$el")
            file=""
        fi
        seconds=$(( $(now) - t0 ))
        state_record "$el" "${SPEC[family]}" "${SPEC[profile]}" "${SPEC[xc]}" "${SPEC[rel]}" \
                     "download" "$(basename "${file:-}")" "$status" 0 "$seconds" "$message"
    done
    state_merge

    [ ${#missing[@]} -eq 0 ] && return 0

    warn "${#missing[@]} of $total not available online: ${missing[*]}"
    fetch_explain "${SPEC[profile]}" | pf_emit_stream info

    # Can we make them here instead?
    if ! prof_can_generate "${SPEC[profile]}" "${SPEC[family]}"; then
        info "PseudoForge cannot generate ${PROF_LABEL[${SPEC[profile]}]} locally either."
        info "  pseudoforge params status      -- what can be generated"
        return 0
    fi

    # Asked through the interface, never from this module.  The default is
    # yes -- generating what a download could not supply is the useful answer
    # -- and a non-interactive caller gets it without blocking on a terminal.
    local reply=no
    if PF_ASSUME=${PF_ASSUME:-yes} pf_confirm \
        "Generate the ${#missing[@]} missing element(s) locally instead?"; then
        reply=yes
    fi
    case $reply in
        yes)
            info "generating ${missing[*]} with $(eng_for_profile "${SPEC[profile]}" "${SPEC[family]}")"
            SPEC[source]=local
            run_batch "${missing[@]}"
            ;;
        *)
            info "left alone; to generate them later:"
            info "  pseudoforge generate -e $(printf '%s,' "${missing[@]}" | sed 's/,$//') -p ${SPEC[profile]} -t ${SPEC[family]} --source local"
            ;;
    esac
    return 0
}

# exec_upf_normalise lives in lib/upf.sh as upf_normalise. This name stays so
# nothing that already calls it breaks.
exec_upf_normalise() { upf_normalise "$@"; }


# ---------------------------------------------------------------------------
# OPIUM
#
#   opium <prefix> <logfile> <commands...>
#
# where the commands are a pipeline: "all" runs the all-electron and
# pseudopotential solves, "ke" the kinetic-energy convergence analysis, "rpt"
# the report, and then one word per output format.  Everything lands beside the
# parameter file as <prefix>.<something>, so the run gets its own directory.
#
# Unusually among these engines, OPIUM writes more than one format from a
# single run.  PseudoForge asks for UPF plus whatever else the caller wanted,
# so a user who needs a CASTEP recpot or a SIESTA file gets it from the same
# solve rather than a second one.
# ---------------------------------------------------------------------------

# Format keyword -> the extension OPIUM writes.
exec_opium_formats() {
    local want=${OPIUM_FORMATS:-${SPEC[formats]:-upf}} f rel
    rel=$(rel_canon "${SPEC[rel]:-}")
    for f in $want; do
        case $f in
            upf)     printf 'upf upf\n' ;;
            teter)
                # Teter is the one OPIUM writer that is fully-relativistic
                # only: it prints "Currently the Teter format can only be
                # used for fully relativistic psps" and writes nothing
                # otherwise.
                case $rel in
                    full) printf 'teter teter\n' ;;
                    *)    warn "opium: teter is fully-relativistic only, skipping (rel=$rel)" ;;
                esac ;;
            fhi|recpot|siesta|cpmd|casino|champ|qso|ncpp)
                # These eight writers refuse fully-relativistic potentials
                # with "ERROR!!: the <name> format does not support fully
                # relativistic psps currently".  That refusal is OPIUM's,
                # not PseudoForge's -- we expose the format only for the
                # relativity modes OPIUM itself will honour.
                case $rel in
                    full) warn "opium: $f does not support fully-relativistic psps, skipping" ;;
                    *)
                        case $f in
                            recpot) printf 'recpot recpot\n' ;;   # CASTEP
                            siesta) printf 'siesta psf\n' ;;
                            qso)    printf 'qso qso.xml\n' ;;     # <name>.qso.xml
                            *)      printf '%s %s\n' "$f" "$f" ;;
                        esac ;;
                esac ;;
            *) warn "unknown OPIUM output format '$f'; ignoring" ;;
        esac
    done
}

exec_opium() {
    local el=$1 deck=$2 prefix=$3 wd=$4 log=$5
    local bin rc out upf kw ext

    bin=$(eng_resolve opium) || { EXEC_MESSAGE="opium not found"; return 1; }

    cp -f "$deck" "$wd/$prefix.param" || { EXEC_MESSAGE="cannot stage the parameter file"; return 1; }

    local -a cmds=(all ke rpt)
    while read -r kw ext; do
        [ -n "$kw" ] && cmds+=("$kw")
    done < <(exec_opium_formats)

    # OPIUM writes its own log; keep ours as the transcript of the invocation
    exec_run "$bin" "$wd" "$log" "${OPIUM_TIMEOUT:-1800}" "" \
             "$prefix" "$prefix.log" "${cmds[@]}"
    rc=$?

    # Its own log carries the real diagnosis, so fold it in either way
    [ -f "$wd/$prefix.log" ] && cat "$wd/$prefix.log" >> "$log" 2>/dev/null

    if [ "$rc" -ge 128 ]; then
        EXEC_MESSAGE="opium crashed (signal $((rc - 128)))"
        case $(grep -ciE '^[[:space:]]*hf[[:space:]]*$' "$deck" 2>/dev/null) in
            0) ;;
            *) EXEC_MESSAGE="$EXEC_MESSAGE -- Hartree-Fock mode is known to crash in this build" ;;
        esac
        return 1
    fi

    # OPIUM names its output after the parameter file; rename to PseudoForge's
    # convention so an OPIUM file and an ld1 file for the same element cannot be
    # confused in one pseudo_dir.
    if [ -s "$wd/$prefix.upf" ]; then
        mv -f "$wd/$prefix.upf" "$wd/$(exec_upf_name "$el")"
    fi
    upf=$wd/$(exec_upf_name "$el")
    if [ ! -s "$upf" ]; then
        EXEC_MESSAGE=$(exec_opium_message "$wd/$prefix.log" "$log")
        [ -n "$EXEC_MESSAGE" ] || EXEC_MESSAGE="opium exited $rc without writing a pseudopotential"
        return 1
    fi

    # Ghost states make a norm-conserving pseudopotential unusable whatever the
    # exit code, and OPIUM reports them in prose.
    if grep -qiE 'ghost' "$wd/$prefix.log" 2>/dev/null; then
        grep -iE 'ghost' "$wd/$prefix.log" | grep -qiE 'no ghost|ghost.*not' || \
            warn "$el: OPIUM reports a possible ghost state -- check $log"
    fi

    # Install every other format the caller asked for, beside the UPF.  OPIUM
    # writes them all from the one solve, so the alternative would be throwing
    # away work the engine has already done.
    local kw ext src dest n=0
    while read -r kw ext; do
        [ -n "$kw" ] || continue
        src=$wd/$prefix.$ext
        [ -s "$src" ] || continue
        [ "$ext" = upf ] && continue
        dest=$PROJECT_DIR/pseudos/$(exec_upf_name "$el")
        dest=${dest%.UPF}.$ext
        mkdir -p "$PROJECT_DIR/pseudos" 2>/dev/null
        cp -f "$src" "$dest" 2>/dev/null && n=$((n + 1))
    done < <(exec_opium_formats)
    [ "$n" -gt 0 ] && EXEC_NOTE="${EXEC_NOTE:+$EXEC_NOTE; }$n extra format(s) written"


    printf '%s\n' "$upf"
}

# ---------------------------------------------------------------------------
# exec_gth -- Goedecker-Teter-Hutter.
#
# The odd one out in this file, for a reason worth stating plainly: every other
# engine here hands back a radial grid that becomes a UPF.  GTH hands back a
# dozen coefficients, and Quantum ESPRESSO cannot read them at all -- upfconv.x
# lists .gth as "DOES NOT WORK".  Manufacturing a UPF anyway would mean
# resampling an analytic form onto a grid and calling the result the library's
# pseudopotential, which it would not be.  So this writes the native coefficient
# block, and the caller is told that is what it got.
#
# Two paths, and which one ran is recorded rather than blurred:
#
#   published  Copy CP2K's own coefficients into the requested layout.  Exact.
#   refit      Re-solve and re-fit.  Close to published, not identical, and
#              labelled PSEUDOFORGE so no one mistakes it for the library.
# ---------------------------------------------------------------------------
exec_gth() {
    local el=$1 deck=$2 expected=$3 wd=$4 log=$5
    local kw out ext label valence psp tbl q inputs

    kw=$(gth_xc_keyword "${SPEC[xc]}") || {
        EXEC_MESSAGE="GTH has no published table for $(upper "$(xc_qe_string "${SPEC[xc]}")")"
        EXEC_MESSAGE="$EXEC_MESSAGE -- it covers pade(LDA), pbe, pbesol, blyp, bp, olyp, hcth120, hcth407"
        printf '\n'; return 1
    }
    mkdir -p "$wd" || return 1
    ext=gth
    out=$wd/$(exec_upf_name "$el"); out=${out%.UPF}.$ext

    if [ "${GTH_REFIT:-0}" = 1 ]; then
        inputs=$(gth_inputs "${SPEC[xc]}" "$el") || {
            EXEC_MESSAGE="no published GTH generation inputs for $el with $kw"
            printf '\n'; return 1
        }
        psp=$(gth_run_fit "$wd/fit" "$el" "$inputs" "${GTH_CYCLES:-200}") || {
            EXEC_MESSAGE="the GTH fit failed for $el"; printf '\n'; return 1
        }
        valence=$(gth_valence_from_atom_dat "$inputs/atom/atom.dat")
        label="GTH-$(upper "$kw")-PSEUDOFORGE"
        gth_psp_to_cp2k "$psp" "$el" "$label" "$valence" > "$out" || { printf '\n'; return 1; }
        EXEC_NATIVE=$out
        EXEC_NOTE="refitted here (penalty $(gth_final_penalty "$wd/fit/psp/fit.log")); not the published coefficients"
        cp -f "$wd/fit/psp/fit.log" "$log" 2>/dev/null
    else
        tbl=$(gth_table cp2k "${SPEC[xc]}" "$el" "${SPEC[variant]:-}") || {
            EXEC_MESSAGE="no published GTH table for $el with $kw"
            printf '\n'; return 1
        }
        sed '/^$/d' "$tbl" > "$out" || { printf '\n'; return 1; }
        EXEC_NATIVE=$out
        EXEC_NOTE="published CP2K coefficients, copied exactly ($(basename "$tbl"))"
        printf 'GTH: %s written from %s\n' "$el" "$tbl" > "$log"
    fi

    [ -s "$out" ] || { EXEC_MESSAGE="GTH produced an empty file for $el"; printf '\n'; return 1; }

    # The same coefficients in the other two layouts, when the run asked for
    # them.  These are published side by side upstream, so they are copied
    # rather than re-derived.
    local other n=0 src dest
    mkdir -p "$PROJECT_DIR/pseudos" 2>/dev/null
    for other in cpmd abinit; do
        case " ${SPEC[formats]:-upf} " in *" gth-$other "*) ;; *) continue ;; esac
        src=$(gth_table "$other" "${SPEC[xc]}" "$el" "${SPEC[variant]:-}" 2>/dev/null) || continue
        # Deliver to pseudos/ alongside the primary .gth -- the extra layouts
        # are new files in the working directory, not variants of $out, so
        # they need the project directory, not the scratch directory.
        dest=$PROJECT_DIR/pseudos/$(exec_upf_name "$el"); dest=${dest%.UPF}.$other
        cp -f "$src" "$dest" 2>/dev/null && n=$((n + 1))
    done
    [ "$n" -gt 0 ] && EXEC_NOTE="${EXEC_NOTE:+$EXEC_NOTE; }$n extra layout(s)"

    EXEC_WARNING="GTH coefficients are not UPF; Quantum ESPRESSO cannot read this file. CP2K, CPMD and ABINIT can."
    printf '%s\n' "$out"
}

# ---------------------------------------------------------------------------
# exec_atompaw -- PAW data sets from Holzwarth's generator.
#
# atompaw reads its deck from standard input rather than from a named file, and
# it writes into the current directory with names it chooses itself, so the run
# has to happen inside the scratch directory and the results are collected
# afterwards by pattern.
#
# It exits 0 in cases where it has not produced a usable data set -- an
# unconverged atomic solve still reaches the end of the output menu -- so the
# exit status is not the test.  The test is whether a PAW file appeared and
# whether the log admits a failure.
# ---------------------------------------------------------------------------
exec_atompaw() {
    local el=$1 deck=$2 expected=$3 wd=$4 log=$5
    local bin rc upf n=0 f dest

    bin=$(eng_resolve atompaw) || {
        EXEC_MESSAGE="AtomPAW not installed -- run: pseudoforge engines build atompaw"
        printf '\n'; return 1
    }
    mkdir -p "$wd" || return 1
    cp -f "$deck" "$wd/atompaw.input" 2>/dev/null || { printf '\n'; return 1; }

    ( cd "$wd" && OMP_NUM_THREADS=1 timeout "${ATOMPAW_TIMEOUT:-1200}" \
        "$bin" < atompaw.input ) > "$log" 2>&1
    rc=$?

    upf=$(ls "$wd"/*.UPF "$wd"/*.upf 2>/dev/null | head -1)

    # A meta-GGA run writes no UPF, and that is AtomPAW's behaviour rather than
    # a failure.  Its UPF writer has no place to put the kinetic-energy density
    # a meta-GGA functional needs, so it writes the PAW-XML and ABINIT datasets
    # and skips the UPF.  Treating a missing UPF as "wrote no PAW data set"
    # threw away a 733 KB r2SCAN dataset that had converged to 4e-13.
    if [ -z "$upf" ]; then
        # meta-GGA produces *two* native datasets -- <el>*-paw.xml and
        # <el>*-paw.abinit -- and neither is UPF.  The old code picked one
        # of them and dropped the other, so a run asking for
        # `--format paw-abinit,paw-xml` silently got only the xml.
        local xml_native abi_native n=0
        xml_native=$(ls "$wd"/*-paw.xml "$wd"/*.xml 2>/dev/null | head -1)
        abi_native=''
        for _f in "$wd"/*-paw.abinit "$wd"/*.abinit; do
            [ -e "$_f" ] || continue
            case ${_f##*/} in *compare*) continue ;; esac
            abi_native=$_f; break
        done
        if [ -n "$xml_native" ] || [ -n "$abi_native" ]; then
            mkdir -p "$PROJECT_DIR/pseudos" 2>/dev/null
            if [ -n "$xml_native" ] && \
               case " ${SPEC[formats]:-paw-xml} " in *" paw-xml "*) true ;; *) false ;; esac; then
                local xdest
                xdest=$PROJECT_DIR/pseudos/$(exec_upf_name "$el"); xdest=${xdest%.UPF}.xml
                cp -f "$xml_native" "$xdest" 2>/dev/null && n=$((n + 1))
                EXEC_NATIVE=$xdest
            fi
            if [ -n "$abi_native" ] && \
               case " ${SPEC[formats]:-paw-xml} " in *" paw-abinit "*) true ;; *) false ;; esac; then
                local adest
                adest=$PROJECT_DIR/pseudos/$(exec_upf_name "$el"); adest=${adest%.UPF}.abinit
                cp -f "$abi_native" "$adest" 2>/dev/null && n=$((n + 1))
                [ -z "${EXEC_NATIVE:-}" ] && EXEC_NATIVE=$adest
            fi
            if [ "$n" -gt 0 ]; then
                EXEC_WARNING="AtomPAW writes no UPF for meta-GGA: the kinetic-energy density has no place in that format. This is a PAW-XML/ABINIT data set, read by ABINIT and by any code that takes PAW-XML."
                printf '%s\n' "${EXEC_NATIVE:-$xml_native}"
                return 0
            fi
        fi
    fi

    if [ -z "$upf" ]; then
        EXEC_MESSAGE=$(exec_atompaw_message "$log")
        [ -n "$EXEC_MESSAGE" ] || EXEC_MESSAGE="AtomPAW wrote no PAW data set (exit $rc)"
        EXEC_NATIVE=$(ls "$wd"/*.abinit "$wd"/*.xml 2>/dev/null | head -1)
        printf '\n'; return 1
    fi

    mv -f "$upf" "$wd/$(exec_upf_name "$el")" 2>/dev/null && upf=$wd/$(exec_upf_name "$el")

    # The ABINIT and PAW-XML datasets come from the same solve, so writing them
    # out costs nothing and is the reason to reach for this engine over ld1.
    # AtomPAW also writes compare.abinit and newcompare.abinit alongside --
    # those are diagnostic diffs, not datasets, so match only the <el>*-paw.*
    # files.  The formats decision comes from SPEC[formats] (space-separated,
    # populated from the profile or from --format by cli_check_spec), not from
    # CLI_FORMATS which carries a comma-separated list and would never match
    # the pattern below.
    for f in "$wd"/*-paw.abinit "$wd"/*-paw.xml; do
        [ -f "$f" ] || continue
        # Skip the diagnostic diff files AtomPAW also writes.
        case ${f##*/} in compare.*|newcompare.*) continue ;; esac
        # Check the requested format for this file's extension specifically.
        # A single case outside the loop over `paw-abinit|paw-xml` would
        # copy both extensions whenever either was requested.
        case ${f##*.} in
            abinit)
                case " ${SPEC[formats]:-upf} " in
                    *" paw-abinit "*) ;;
                    *) continue ;;
                esac ;;
            xml)
                case " ${SPEC[formats]:-upf} " in
                    *" paw-xml "*) ;;
                    *) continue ;;
                esac ;;
            *) continue ;;
        esac
        dest=$PROJECT_DIR/pseudos/$(exec_upf_name "$el")
        dest=${dest%.UPF}.${f##*.}
        mkdir -p "$PROJECT_DIR/pseudos" 2>/dev/null
        cp -f "$f" "$dest" 2>/dev/null && n=$((n + 1))
    done
    [ "$n" -gt 0 ] && EXEC_NOTE="$n extra PAW format(s) written"

    local warn_txt
    warn_txt=$(exec_atompaw_message "$log")
    [ -n "$warn_txt" ] && EXEC_WARNING=$warn_txt

    printf '%s\n' "$upf"
}

# atompaw's own complaints, in the order that matters.
# ---------------------------------------------------------------------------
# exec_ape -- the Atomic Pseudopotential Engine.
#
# APE takes no argument and reads no standard input: it opens a file named
# inp.ape in the current directory.  Handing it a path instead produces a run
# that parses nothing and then fails on the first value it needs, so the deck
# is copied into place under that exact name rather than passed along.
#
# It also needs libxc and GSL at run time, which live in PseudoForge's engine
# prefix rather than on the system path.
# ---------------------------------------------------------------------------
exec_ape() {
    local el=$1 deck=$2 expected=$3 wd=$4 log=$5
    local bin rc upf prefix

    bin=$(eng_resolve ape) || {
        EXEC_MESSAGE="APE not installed -- run: pseudoforge engines build ape"
        printf '\n'; return 1
    }
    prefix=$(eng_prefix)
    mkdir -p "$wd" || return 1
    cp -f "$deck" "$wd/inp.ape" 2>/dev/null || { printf '\n'; return 1; }

    ( cd "$wd" && OMP_NUM_THREADS=1 \
        LD_LIBRARY_PATH="$prefix/lib:${LD_LIBRARY_PATH:-}" \
        timeout "${APE_TIMEOUT:-1800}" "$bin" < /dev/null ) > "$log" 2>&1
    rc=$?

    upf=$(ls "$wd"/*.UPF "$wd"/*.upf 2>/dev/null | head -1)

    # ------------------------------------------------------------------
    # Auto-fix: drop a deep filled d shell from the pseudised channels.
    #
    # Bromine's 3d10 sits well below its 4s/4p valence.  Pseudising it with a
    # radius taken from a published deck makes APE's Troullier-Martins
    # construction fail in multiroot_solve_system.  Listing 3d as an orbital
    # but not pseudising it succeeds, and for a halogen that is the textbook
    # partition anyway.
    #
    # This is a retry, not a rule, and the distinction matters.  Zinc has the
    # same 3d10/4s2 shape and builds *with* its d pseudised -- its first
    # attempt succeeds, so it never reaches this code.  A blanket
    # "filled d below valence -> core" rule would have changed Zn's answer for
    # no reason.  Only the element that actually fails gets the fallback, and
    # the report says it fired.
    # ------------------------------------------------------------------
    if [ -z "$upf" ] && [ "${APE_NO_RETRY:-0}" != 1 ] \
       && grep -qiE 'multiroot_solve_system|Error in subtoutine multiroot' "$log" 2>/dev/null; then
        local dl retry
        # the deepest pseudised d channel, if the deck has one
        dl=$(awk '/%PPComponents/ { g = 1; next } g && /^%/ { exit }
                  g && $0 ~ /\|/ { split($0, a, "|"); if (a[2] + 0 == 2) print a[1] + 0 }' \
                  "$wd/inp.ape" | sort -n | head -1)
        if [ -n "$dl" ]; then
            retry=$wd/inp.ape.retry
            # Drop the d line from PPComponents only.  It stays in %Orbitals,
            # so the all-electron atom is unchanged and the channel still
            # exists -- it is simply not pseudised.
            awk -v n="$dl" '
                /%PPComponents/ { g = 1; print; next }
                g && /^%/       { g = 0; print; next }
                g && $0 ~ /\|/  { split($0, a, "|"); if (a[1] + 0 == n && a[2] + 0 == 2) next }
                { print }
            ' "$wd/inp.ape" > "$retry"
            if ! cmp -s "$retry" "$wd/inp.ape"; then
                info "$el: APE could not pseudise the ${dl}d shell; retrying with it as core"
                cp -f "$retry" "$wd/inp.ape"
                ( cd "$wd" && OMP_NUM_THREADS=1 \
                    LD_LIBRARY_PATH="$prefix/lib:${LD_LIBRARY_PATH:-}" \
                    timeout "${APE_TIMEOUT:-1800}" "$bin" < /dev/null ) > "$log.retry" 2>&1
                rc=$?
                cat "$log.retry" >> "$log" 2>/dev/null
                upf=$(ls "$wd"/*.UPF "$wd"/*.upf 2>/dev/null | head -1)
                [ -n "$upf" ] && EXEC_AUTOFIX="${dl}d treated as core (fallback; it could not be pseudised)"
            fi
        fi
    fi

    # ------------------------------------------------------------------
    # Ghost states, by APE's own analysis.
    #
    # APE runs the Gonze-Stumpf-Scheffler test on its Kleinman-Bylander form
    # and says so in the log: "KB energy < 0; Eref > E0 => Ghost state found".
    # Nothing read that line, so a file APE itself had flagged was shipped as
    # ok. Measured on Si PBE with APE's default local potential (a Vanderbilt
    # function), read by pw.x as v2: -59.73 Ry for bulk Si where ONCVPSP gives
    # -15.76 -- the electrons sit in the ghost. The pressure, 39 kbar, looked
    # plausible; the energy is what gives it away.
    #
    # The textbook remedy is a different local channel. So, on that signature
    # only, each pseudised channel is tried as local in turn (LLocal), and the
    # first one APE's *own* analysis reports clean is taken -- APE is the
    # judge, not this code. With s local the same Si gives -15.761 Ry, 2 mRy
    # from ONCVPSP. If every channel ghosts, the element fails: a file with a
    # ghost in it is not a pseudopotential anyone should use.
    # ------------------------------------------------------------------
    if [ -n "$upf" ] && [ "${APE_NO_RETRY:-0}" != 1 ] \
       && grep -q 'Ghost state found' "$log" 2>/dev/null; then
        local ll clean="" chans
        chans=$(awk '/%PPComponents/ { g = 1; next } g && /^%/ { exit }
                     g && $0 ~ /\|/ { split($0, a, "|"); print a[2] + 0 }' "$wd/inp.ape" | sort -nu)
        cp -f "$wd/inp.ape" "$wd/inp.ape.ghost"
        for ll in $chans; do
            rm -f "$wd"/*.UPF "$wd"/*.upf
            { grep -v '^ *LLocal *=' "$wd/inp.ape.ghost"; printf 'LLocal = %s\n' "$ll"; } > "$wd/inp.ape"
            ( cd "$wd" && OMP_NUM_THREADS=1 \
                LD_LIBRARY_PATH="$prefix/lib:${LD_LIBRARY_PATH:-}" \
                timeout "${APE_TIMEOUT:-1800}" "$bin" < /dev/null ) > "$log.l$ll" 2>&1
            rc=$?
            cat "$log.l$ll" >> "$log" 2>/dev/null
            # Tested by output, not by ls's exit status: `ls a*.UPF a*.upf`
            # exits non-zero when either pattern matches nothing, which made
            # every retry look like it had written no file.
            if [ -n "$(ls "$wd"/*.UPF "$wd"/*.upf 2>/dev/null | head -1)" ] \
               && ! grep -q 'Ghost state found' "$log.l$ll"; then
                clean=$ll; break
            fi
        done
        upf=$(ls "$wd"/*.UPF "$wd"/*.upf 2>/dev/null | head -1)
        if [ -n "$clean" ] && [ -n "$upf" ]; then
            EXEC_AUTOFIX="${EXEC_AUTOFIX:+$EXEC_AUTOFIX; }ghost state with APE's default local potential; l=$clean made local, which APE's own ghost analysis reports clean"
        else
            upf=""
            EXEC_MESSAGE="APE's own ghost analysis finds a ghost state with the default local potential and with every pseudised channel ($(printf '%s' "$chans" | tr '\n' ' ' | sed 's/ $//')) as local; a file with a ghost in it gives wrong physics"
        fi
    fi

    if [ -z "$upf" ]; then
        [ -n "$EXEC_MESSAGE" ] || EXEC_MESSAGE=$(exec_ape_message "$log")
        if [ "$rc" -eq 124 ]; then
            EXEC_MESSAGE="APE did not converge within ${APE_TIMEOUT:-1800}s${EXEC_MESSAGE:+ ($EXEC_MESSAGE)}"
        fi
        [ -n "$EXEC_MESSAGE" ] || EXEC_MESSAGE="APE wrote no pseudopotential (exit $rc)"
        printf '\n'; return 1
    fi

    mv -f "$upf" "$wd/$(exec_upf_name "$el")" 2>/dev/null && upf=$wd/$(exec_upf_name "$el")

    # APE writes UPF v1 and leaves the functional field blank: it runs the
    # functional through libxc and has no Quantum ESPRESSO name to put there.
    # pw.x then stops with "unrecognized dft", so every APE file was unusable
    # as written -- including runs this tool reported as ok.
    #
    # The deck names the functional, so the header can say what was run. But
    # only where QE's name means exactly that: for LDA and GGA, xc_qe_string
    # is the functional itself. For meta-GGA it is ld1's *proxy* parent --
    # "PBE" for SCAN -- and APE runs SCAN natively, so writing PBE would label
    # a SCAN pseudopotential as PBE. There it stays blank, and says so.
    if [ "$(upf_format "$upf")" = v1 ] \
       && [ -z "$(upf_v1_field "$upf" 'Exchange-Correlation functional' | tr -d ' ')" ]; then
        pf_xc_load 2>/dev/null
        case ${XC_FAMILY[${SPEC[xc]}]:-} in
            LDA|GGA)
                upf_v1_set_functional "$upf" "$(xc_qe_string "${SPEC[xc]}")" \
                    && EXEC_AUTOFIX="${EXEC_AUTOFIX:+$EXEC_AUTOFIX; }functional name $(xc_qe_string "${SPEC[xc]}") written into the header APE left blank" ;;
            *)
                EXEC_WARNING="APE names no functional in the file and ${SPEC[xc]} has no Quantum ESPRESSO name meaning exactly it; set input_dft in pw.x" ;;
        esac
    fi

    # ------------------------------------------------------------------
    # APE writes UPF v1, and QE 7.6's pw.x misreads it.
    #
    # Measured on one ghost-free Si PBE pseudopotential from APE, the same
    # numbers read two ways:
    #
    #   APE's v1 file, read by pw.x         -11.049 Ry   645 kbar
    #   rewritten as v2 by upfconv.x        -15.761 Ry    46 kbar
    #   ONCVPSP, independently               -15.763 Ry    25 kbar
    #
    # Ruled out before blaming the reader: the local potential's units (its
    # tail is -2Z/r in Rydberg), the D_ij scale (x2 and x0.5 do not bring it
    # back), the radial grid (PP_RAB matches dr/di) and the charge
    # (PP_RHOATOM integrates to 4.0000). The pseudopotential is right; the v1
    # route into pw.x is not. So it goes through the same upfconv wrapper the
    # USPP path uses, which also normalises the result. Nothing numerical is
    # changed -- the v2 file carries APE's numbers, read correctly.
    # ------------------------------------------------------------------
    if [ "$(upf_format "$upf")" = v1 ]; then
        local v1=$wd/ape-v1.UPF v2=$wd/ape-v2.UPF
        cp -f "$upf" "$v1"
        if exec_upfconv "$v1" "$v2" "$log"; then
            mv -f "$v2" "$upf"
            # A v1 file has no relativistic field, so upfconv writes "no" --
            # and a scalar-relativistic APE Si was then rejected by the label
            # check as non-relativistic. The deck says what APE solved.
            # Only schrodinger and scalar_rel are written: a dirac run through
            # v1 carries no spin-orbit data, and "full" on it would be false,
            # so that case is left for the label check to refuse.
            local weq r=""
            weq=$(awk -F= 'tolower($1) ~ /waveequation/ { gsub(/[ \t]/, "", $2); print tolower($2); exit }' "$wd/inp.ape")
            case $weq in schrodinger) r=no ;; scalar_rel) r=scalar ;; esac
            [ -n "$r" ] && sed -i -E "0,/relativistic=\"[^\"]*\"/s//relativistic=\"$r\"/" "$upf"
        else
            EXEC_MESSAGE="APE wrote UPF v1, which Quantum ESPRESSO 7.6's pw.x misreads (bulk Si 645 kbar against 25 from ONCVPSP), and upfconv.x could not rewrite it as v2"
            printf '\n'; return 1
        fi
    fi
    EXEC_NOTE="Troullier-Martins, libxc functional $(ib_ape_xc 2>/dev/null | tr ' ' '+')"
    [ -n "${EXEC_AUTOFIX:-}" ] && EXEC_NOTE="$EXEC_NOTE; $EXEC_AUTOFIX"
    printf '%s\n' "$upf"
}

# APE states its failures under a "Fatal Error" banner, on the line after it.
# ---------------------------------------------------------------------------
# exec_ape_message <log>  -- APE's own words, and what they mean.
#
# One failure gets translated rather than repeated, because "State: 3d is
# unbound" is true and tells you nothing you can act on.
#
# APE has no working GGA path for an open-d transition metal. That is
# upstream's, not ours, and it is reproducible from upstream's own file:
# testsuite/all_electron/02-scalar_rel.01-no_spin.inp is APE's shipped
# chromium deck, it passes as distributed with lda_x_rel + lda_c_vwn, and it
# fails with exactly this message when the single line naming the functional
# is changed to gga_x_pbe + gga_c_pbe. APE's test suite contains no GGA case
# at all -- every functional in it is an lda_* -- so the combination has never
# been exercised upstream.
#
# Ruled out here, one at a time, before attributing it upstream: the order of
# the orbitals in the deck, the empty p channel, whether the d shell is
# pseudised at all (it fails in the all-electron stage, before pseudisation),
# libxc's density threshold from 1e-16 to 1e-6, numerical versus analytical
# XC derivatives, the radial mesh extent from 15 to 140 bohr and its point
# count, the eigensolver tolerance, and the SCF iteration cap. LDA succeeds in
# every one of those configurations and no GGA succeeds in any of them.
#
# The mechanism, for whoever picks this up: states_batch.F90 asks
# wavefunctions_n_bound_states how many bound states the l channel holds, and
# that function counts the nodes of a trial integration at the top of the
# well. Under GGA the l=2 count comes back short, so an occupied d is
# classified unbound and the run is aborted.
# ---------------------------------------------------------------------------
exec_ape_message() {
    local f=$1 raw xc
    [ -s "$f" ] || return 0
    raw=$(awk '/Fatal Error/ { getline; sub(/^[[:space:]]*/, ""); print; exit }' "$f" | cut -c1-160)

    case $raw in
        *"is unbound"*)
            xc=$(lower "${SPEC[xc]:-}")
            case $xc in
                ''|pz|pw|vwn|vwn-rpa) ;;   # LDA: this is a real physics answer
                *) raw="$raw -- APE has no working GGA path for an open-d transition metal. Its own chromium test fails the same way when only the functional is changed. Use -x pz with APE, or --engine ld1 or oncvpsp for $(upper "$xc")." ;;
            esac ;;
    esac
    printf '%s\n' "$raw"
}

exec_atompaw_message() {
    local f=$1
    [ -s "$f" ] || return 0
    # Match failures, not the report.  atompaw prints diagnostic lines like
    # "Smooth tcore shape (no negative nhat) :  NO", and a grep for "negative"
    # turned every healthy run into a warning -- worse than no warning at all,
    # because it teaches the reader to ignore the column.
    grep -iE 'not converged|no convergence|pgm terminating|option not recognized|fatal error|abort' "$f" 2>/dev/null \
        | head -1 | sed 's/^[[:space:]]*//' | cut -c1-160
}

# ---------------------------------------------------------------------------
# exec_adpack -- ADPACK, whose output is .vps for OpenMX rather than UPF.
#
# Two things this has to get right.
#
# The thread count must be passed explicitly.  Without -nt, adpack.c reads an
# uninitialised variable in its argument parser and the behaviour changes with
# the optimisation level: at -O0 it exits immediately with "cannot find the
# number of threads", at -O2 it runs.  That is a defect in the released source
# and it is left alone (fixing it would change behaviour rather than restore
# it), so the flag is always supplied.
#
# And the output name comes from System.Name in the deck, not from the element,
# so the file is located rather than guessed.
# ---------------------------------------------------------------------------
exec_adpack() {
    local el=$1 deck=$2 expected=$3 wd=$4 log=$5
    local bin rc vps out base

    bin=$(eng_resolve adpack) || {
        EXEC_MESSAGE="ADPACK not installed -- run: pseudoforge engines build adpack"
        printf '\n'; return 1
    }
    mkdir -p "$wd" || return 1
    base=$(basename "$deck")
    cp -f "$deck" "$wd/$base" 2>/dev/null || { printf '\n'; return 1; }

    ( cd "$wd" && OMP_NUM_THREADS=1 timeout "${ADPACK_TIMEOUT:-1800}" \
        "$bin" "$base" -nt 1 ) > "$log" 2>&1
    rc=$?

    vps=$(ls "$wd"/*.vps 2>/dev/null | head -1)

    # ------------------------------------------------------------------
    # Auto-fix: widen the cut-off radii when the TM root-finder gives up.
    #
    # ADPACK's Troullier-Martins construction solves for a coefficient c2 that
    # satisfies its matching conditions.  For tellurium the radii shipped in
    # Te_VPS.inp put that solve out of reach and ADPACK declines cleanly --
    # exit 0, no file, and a message saying which step failed.
    #
    # Widening the radii slightly brings it back in range.  Two things make
    # this safe to do automatically:
    #
    #   - the shipped deck is never modified.  The retry edits a copy in the
    #     scratch directory; data/params/adpack/Te_VPS.inp stays byte-identical
    #     to the distribution, which is what a test asserts.
    #   - the radius that actually worked is recorded, so the result is
    #     reproducible and visibly not the published parameter set.
    #
    # A wider radius is a softer pseudopotential: it is a real change to the
    # physics, not a build fix, and it is reported as one rather than folded
    # into a success.
    # ------------------------------------------------------------------
    if [ -z "$vps" ] && [ "${ADPACK_NO_RETRY:-0}" != 1 ] \
       && grep -qiE 'Failure in searching of an appropriate c2|Please check cutoff radii' "$log" 2>/dev/null; then
        local scale tried=""
        # Always scale from the pristine deck.  Scaling the working copy again
        # on the second pass would compound (1.1 x 1.2 = 1.32) and the radius
        # recorded in the report would not be the radius that ran.
        cp -f "$deck" "$wd/$base.orig" 2>/dev/null
        for scale in 1.1 1.2; do
            awk -v s="$scale" '
                /<pseudo\.NandL/ { g = 1; print; next }
                g && /pseudo\.NandL>/ { g = 0; print; next }
                g && NF >= 5 { printf "  %s %s %s %8.3f %s\n", $1, $2, $3, $4 * s, $5; next }
                { print }
            ' "$wd/$base.orig" > "$wd/$base.retry"
            cmp -s "$wd/$base.retry" "$wd/$base.orig" && continue
            cp -f "$wd/$base.retry" "$wd/$base"
            info "$el: ADPACK declined the published radii; retrying with rc x $scale"
            ( cd "$wd" && OMP_NUM_THREADS=1 timeout "${ADPACK_TIMEOUT:-1800}" \
                "$bin" "$base" -nt 1 ) > "$log.retry" 2>&1
            rc=$?
            cat "$log.retry" >> "$log" 2>/dev/null
            vps=$(ls "$wd"/*.vps 2>/dev/null | head -1)
            tried="$tried $scale"
            if [ -n "$vps" ]; then
                EXEC_AUTOFIX="cut-off radii scaled by $scale (the published radii were declined by the TM solver)"
                EXEC_WARNING_EXTRA="This is NOT the published ADPACK parameter set: every cut-off radius was scaled by $scale because the TM solver declined the published ones. A wider radius is a softer pseudopotential -- validate before use."
                PF_AUTOFIX_RC=$scale
                break
            fi
        done
        [ -z "$vps" ] && [ -n "$tried" ] && \
            EXEC_MESSAGE="ADPACK declined the published radii, and retries at$tried did not converge either"
    fi

    if [ -z "$vps" ]; then
        # ADPACK declines cleanly when its Troullier-Martins root-finder cannot
        # satisfy the deck's radii -- exit 0, no file, and a message saying so.
        # That is a parameter problem in the deck, not a crash, and the user is
        # better served by ADPACK's own words than by ours.
        EXEC_MESSAGE=$(grep -A3 -iE 'Failure in searching' "$log" 2>/dev/null \
                       | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-160)
        [ -n "$EXEC_MESSAGE" ] || EXEC_MESSAGE="ADPACK wrote no pseudopotential (exit $rc)"
        printf '\n'; return 1
    fi

    out=$wd/$(exec_upf_name "$el"); out=${out%.UPF}.vps
    mv -f "$vps" "$out" 2>/dev/null || out=$vps
    EXEC_NATIVE=$out

    # The pseudo-atomic orbital basis comes out of the same solve when the deck
    # asks for it; keep it beside the potential where one exists.
    local pao n=0
    case " ${SPEC[formats]:-upf} " in
        *" openmx-pao "*)
            pao=$(ls "$wd"/*.pao 2>/dev/null | head -1)
            if [ -n "$pao" ]; then
                cp -f "$pao" "${out%.vps}.pao" 2>/dev/null && n=1
            fi ;;
    esac

    EXEC_WARNING="ADPACK writes OpenMX .vps, not UPF. Quantum ESPRESSO cannot read this file; OpenMX can."
    [ -n "${EXEC_WARNING_EXTRA:-}" ] && EXEC_WARNING="$EXEC_WARNING $EXEC_WARNING_EXTRA"
    [ -n "${EXEC_AUTOFIX:-}" ] && EXEC_NOTE="${EXEC_NOTE:+$EXEC_NOTE; }$EXEC_AUTOFIX"
    [ "$n" = 1 ] && EXEC_NOTE="pseudo-atomic orbital basis written alongside"
    printf '%s\n' "$out"
}

exec_opium_message() {
    local f
    for f in "$@"; do
        [ -s "$f" ] || continue
        grep -iE 'error|fatal|cannot|failed|not converged|bad ' "$f" 2>/dev/null \
            | grep -viE 'no error' | head -1 | sed 's/^[[:space:]]*//' | cut -c1-200
    done | grep . | head -1
}
