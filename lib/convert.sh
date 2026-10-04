# shellcheck shell=bash
# ---------------------------------------------------------------------------
# convert.sh -- moving a pseudopotential between file formats.
#
# The boundary this file keeps is the difference between *transforming a file*
# and *making a different pseudopotential*.  Those look similar from the
# command line and are not the same thing at all, and the second one produces a
# file that looks right and is not.
#
# A conversion is in scope when every number the target format needs is already
# present in the source, and the work is rearranging and relabelling.  It is
# out of scope when the target needs something the source does not contain --
# then the only way to produce it is to construct it, and a construction issued
# under the original library's name is exactly what this tool refuses to do.
#
# Three kinds of answer, and each is reported rather than blurred:
#
#   exact      every number survives; a round trip returns the original
#   lossy      the conversion succeeds but drops something the target cannot
#              hold.  What was dropped is named, in the file and in the report.
#   refused    it does not happen.  Two different reasons, reported as two
#              different things, because they mean different things to the
#              person reading:
#                physics  the target needs data the source does not have, and
#                         no tool could supply it without inventing numbers;
#                no-tool  the conversion is possible in principle and nothing
#                         performs it.  A path nobody can run is refused
#                         rather than listed as "available: no", which reads
#                         as "install something and it will work".
#
# Cross-family conversion -- NC to US, US to PAW -- is refused on principle and
# not because it is hard.  An ultrasoft pseudopotential is not a norm-conserving
# one in a different file layout; it is a different physical object built from a
# different calculation.
# ---------------------------------------------------------------------------

CONVERT_VERSION=1.0

declare -gA CVT_TOOL CVT_KIND CVT_NOTE CVT_REFUSAL CVT_CAVEAT
declare -ga CVT_ORDER=()

# ---------------------------------------------------------------------------
# The registry.  Keys are "<from>:<to>".
#
# "kind" is exact, lossy or refused, and it is the first thing a caller should
# look at.  The note is shown to the user verbatim, so it says what happened or
# why it did not, in words that mean something without reading this file.
# ---------------------------------------------------------------------------
pf_convert_load() {
    [ ${#CVT_ORDER[@]} -gt 0 ] && return 0
    local k

    # --- conversions Quantum ESPRESSO's own upfconv.x performs --------------
    #
    # "exact" is a claim, and each of these has been checked the only way that
    # settles it: bulk Si in pw.x, identical input, the source file read
    # natively by pw.x against the converted file. Measured 2026-09-28,
    # ecutwfc 30 / ecutrho 240, 4x4x4, conv_thr 1e-10:
    #
    #   .van native      -15.90704670 Ry   van -> upf    -15.90704670 Ry
    #   .RRKJ3 native    -22.99954954 Ry   rrkj3 -> upf  -22.99954954 Ry
    #   .UPF             -15.76231144 Ry   upf -> xml    -15.76231144 Ry
    #
    # Identical to the last printed digit, pressures included. Before this,
    # the only check was "the result passes UPF validation" -- which a
    # converted .van also passed while being a file pw.x could not open
    # (2,496-character PP_QFCOEF row; see upf_normalise). Validation is a
    # check of form. This is a check of physics.
    for k in van:upf vdb:upf rrkj3:upf; do
        CVT_TOOL[$k]=upfconv
        CVT_KIND[$k]=exact
        CVT_ORDER+=("$k")
    done
    CVT_NOTE[van:upf]="Vanderbilt ultrasoft ASCII to UPF, by QE's upfconv.x. Exact: bulk Si in pw.x gives the same energy and pressure from the .van read natively and from the converted UPF."
    CVT_NOTE[vdb:upf]="${CVT_NOTE[van:upf]}"
    # upfconv matches only the uppercase '.RRKJ3' (upflib/read_ps.f90);
    # cvt_run_upfconv stages the file under that name. And a caution about the
    # *source*, not the conversion: ld1.x writing RRKJ3 from a modern
    # PSlibrary deck already gives a different pseudopotential from the UPF
    # it writes from the same deck -- 2.2 eV per Si cell -- because the old
    # layout has no l-resolved augmentation (PP_QIJL). The conversion
    # reproduces the RRKJ3 exactly; it cannot restore what the RRKJ3 never
    # held.
    CVT_NOTE[rrkj3:upf]="The atomic code's old ultrasoft layout to UPF, by QE's upfconv.x. Exact: pw.x gives identical results from the .RRKJ3 read natively and from the converted UPF. Note that the RRKJ3 layout itself cannot hold l-resolved augmentation, so an RRKJ3 written from a modern deck is already not the pseudopotential the deck's UPF would be -- measured 2.2 eV per Si cell. Convert RRKJ3 files you have; do not generate new ones to convert."

    CVT_TOOL[upf:xml]=upfconv
    CVT_KIND[upf:xml]=exact
    CVT_NOTE[upf:xml]="UPF to the QE XML schema, by QE's upfconv.x. Exact: pw.x gives identical results from both files."
    CVT_ORDER+=(upf:xml)

    # --- FHI and CPMD: advertised by upfconv, performed by nothing ----------
    #
    # `upfconv.x -h` lists "*.cpi or *.fhi" and "*.cpmd". The code does not
    # read them. In QE 7.x upfconv.f90 sends every file through read_ps_new
    # (upflib/read_ps.f90), whose dispatch is, in full:
    #
    #   .psml -> read_psml   .vdb/.van -> readvan   .RRKJ3 -> readrrkj
    #   .gth/.GTH -> error   anything else -> read_ncpp (old PWSCF format)
    #
    # No FHI branch, no CPMD branch. A valid .cpi therefore lands in read_ncpp
    # and fails "PP file is empty or wrong" -- measured on this tool's own
    # fhi98PP output, kept as tests/fixtures/cpi/. The dedicated fhi2upf.x and
    # cpmd2upf.x of older releases are not in QE 7.6's bin/ (only casino2upf.x
    # and upfconv.x are). These were registered as exact, then as "yes *";
    # they are refusals of kind no-tool, like the psp8 paths.
    for k in cpi:upf fhi:upf cpmd:upf; do
        CVT_TOOL[$k]=none
        CVT_KIND[$k]=refused
        CVT_REFUSAL[$k]=no-tool
    done
    CVT_NOTE[cpi:upf]="No tool performs this in Quantum ESPRESSO 7.x. upfconv.x's help lists .cpi and .fhi, but its reader dispatch (read_ps_new in upflib/read_ps.f90) has no FHI branch: the file falls through to the old PWSCF reader and fails. QE 7.6 ships no fhi2upf.x. ABINIT reads the FHI layout directly; for a UPF, generate one with an engine that writes UPF."
    CVT_NOTE[fhi:upf]="${CVT_NOTE[cpi:upf]}"
    CVT_NOTE[cpmd:upf]="No tool performs this in Quantum ESPRESSO 7.x. upfconv.x's help lists .cpmd, but its reader dispatch (read_ps_new in upflib/read_ps.f90) has no CPMD branch, and QE 7.6 ships no cpmd2upf.x. CPMD reads the file directly; for a UPF, generate one -- OPIUM writes both from one run (--engine opium --format upf,cpmd)."

    # --- refusals, each with its own reason ---------------------------------
    CVT_TOOL[pawxml:upf]=none
    CVT_KIND[pawxml:upf]=refused
    CVT_REFUSAL[pawxml:upf]=physics
    CVT_NOTE[pawxml:upf]="UPF has no tag for the kinetic-energy density. For a meta-GGA data set that term is what makes it meta-GGA, so the conversion would return an r2SCAN file that is no longer r2SCAN. For LDA and GGA the conversion is unnecessary: AtomPAW writes UPF itself -- add PWSCFOUT to the deck, or run without --format pawxml."

    CVT_TOOL[vps:upf]=none
    CVT_KIND[vps:upf]=refused
    CVT_REFUSAL[vps:upf]=physics
    CVT_NOTE[vps:upf]="An OpenMX .vps holds semilocal potentials V_l(r), one curve per channel. UPF wants a separable Kleinman-Bylander form: projector functions and a D_ij matrix. Going from one to the other means choosing a local channel and constructing projectors -- a new pseudopotential, not a relabelled file. Use ADPACK's output with OpenMX, or generate with an engine that writes UPF."

    CVT_TOOL[gth:upf]=none
    CVT_KIND[gth:upf]=refused
    CVT_REFUSAL[gth:upf]=physics
    CVT_NOTE[gth:upf]="A GTH file is a dozen analytic coefficients, not a radial table. QE's own upfconv.x lists .gth as \"DOES NOT WORK\". Producing a UPF means sampling the analytic form onto a grid, which is a construction rather than a conversion. CP2K, CPMD and ABINIT read GTH directly."

    # --- the psp8 paths, and a correction ----------------------------------
    #
    # These three were registered as `exact`, performed by a tool called
    # `pspconvert` said to ship with ABINIT.  It does not, because there is no
    # such program.  Measured, not assumed:
    #
    #   * ABINIT 8.10.3 and 9.10.3 source: no `pspconvert` anywhere in the
    #     tree, and the 98_main program list does not name one;
    #   * conda-forge `abinit=8.10.2` and `abinit=10.0.3`, installed and
    #     listed: no `pspconvert` in bin/;
    #   * `abitk`, ABINIT 10's toolkit, has no pseudopotential subcommand at
    #     all -- its help lists header, k-point, crystal and band tools;
    #   * QE's `upfconv.x -h` prints the formats it handles (.upf, .vdb/.van,
    #     .rrkj3, .cpi/.fhi, .cpmd) and psp8 is not among them.
    #
    # So the entries promised something that could never run, and the
    # "AVAILABLE: no" column read as "install ABINIT and it will work".  They
    # are refusals now, each naming the route that does work.  The reason is
    # carried in full rather than shortened to "unsupported": a refusal that
    # does not say what to do instead is a dead end.
    CVT_TOOL[psp8:upf]=none
    CVT_KIND[psp8:upf]=refused
    CVT_REFUSAL[psp8:upf]=no-tool
    CVT_NOTE[psp8:upf]="No tool performs this conversion. ABINIT ships no psp8 converter (checked: the 8.10.3 and 9.10.3 source trees, and the conda-forge binaries of 8.10.2 and 10.0.3), and QE's upfconv.x does not list psp8 among the formats it reads. The two layouts both tabulate Kleinman-Bylander projectors, so a converter is possible to write; none exists, and PseudoForge does not invent one. To get a UPF, generate one: every engine here except GTH and ADPACK writes UPF directly."

    CVT_TOOL[upf:psp8]=none
    CVT_KIND[upf:psp8]=refused
    CVT_REFUSAL[upf:psp8]=no-tool
    CVT_NOTE[upf:psp8]="No tool performs this conversion -- see psp8 -> upf for what was checked. psp8 does not need converting to: ONCVPSP writes it natively. Run with --engine oncvpsp --format psp8 and the file ABINIT reads is the file the engine produced, with no intermediate step to lose anything in."

    CVT_TOOL[fhi:psp8]=none
    CVT_KIND[fhi:psp8]=refused
    CVT_REFUSAL[fhi:psp8]=no-tool
    CVT_NOTE[fhi:psp8]="No tool performs this conversion -- see psp8 -> upf for what was checked. ABINIT appears to read the fhi layout directly (its binary carries an m_psp6 module, and pspcod 6 is the fhi98PP format -- Unverified: check ABINIT's psp6 reader in the source). For psp8 specifically, generate it: --engine oncvpsp --format psp8."

    for k in pawxml:upf vps:upf gth:upf psp8:upf upf:psp8 fhi:psp8 cpi:upf fhi:upf cpmd:upf; do CVT_ORDER+=("$k"); done
}

# What format is this file?  By extension, then by content when the extension
# is ambiguous -- .xml is used by both PAW-XML and QE's own schema.
cvt_detect() {
    local f=$1 ext
    ext=$(lower "${f##*.}")
    case $ext in
        upf)        printf 'upf\n' ;;
        psp8)       printf 'psp8\n' ;;
        vps)        printf 'vps\n' ;;
        gth)        printf 'gth\n' ;;
        van)        printf 'van\n' ;;
        vdb)        printf 'vdb\n' ;;
        rrkj3)      printf 'rrkj3\n' ;;
        cpi)        printf 'cpi\n' ;;
        fhi)        printf 'fhi\n' ;;
        cpmd)       printf 'cpmd\n' ;;
        xml)
            if grep -qm1 'paw_dataset' "$f" 2>/dev/null; then printf 'pawxml\n'
            else printf 'xml\n'; fi ;;
        *) return 1 ;;
    esac
}

cvt_tool_available() {
    case $1 in
        upfconv)    cvt_upfconv_bin >/dev/null 2>&1 ;;
        none)       return 1 ;;
        *)          return 1 ;;
    esac
}

cvt_upfconv_bin() {
    local b
    if [ -n "${UPFCONV_BIN:-}" ] && [ -x "$UPFCONV_BIN" ]; then printf '%s\n' "$UPFCONV_BIN"; return 0; fi
    have upfconv.x && { command -v upfconv.x; return 0; }
    b=$(ls "${QE_ROOT_DIR:-/opt/espresso}"/*/upfconv.x 2>/dev/null | head -1)
    [ -n "$b" ] && [ -x "$b" ] && { printf '%s\n' "$b"; return 0; }
    return 1
}

# ---------------------------------------------------------------------------
# cvt_provenance <converted> <source> <from> <to> <kind> <loss>
#
# Written beside the converted file.  A conversion is a step in the history of
# a pseudopotential, and a file that does not say where it came from cannot be
# reproduced.  Losses are recorded as losses, not omitted because the
# conversion "worked".
# ---------------------------------------------------------------------------
cvt_provenance() {
    local out=$1 src=$2 from=$3 to=$4 kind=$5 loss=${6:-}
    local p=${out}.provenance
    {
        printf '# %s %s -- conversion record\n' "$PSEUDOFORGE_NAME" "$PSEUDOFORGE_VERSION"
        printf 'converted=%s\n'        "$(basename "$out")"
        printf 'source.file=%s\n'      "$(basename "$src")"
        printf 'source.format=%s\n'    "$from"
        printf 'target.format=%s\n'    "$to"
        printf 'conversion.path=%s\n'  "$from->$to"
        printf 'conversion.kind=%s\n'  "$kind"
        printf 'converter=%s\n'        "${CVT_TOOL[$from:$to]:-unknown}"
        printf 'converter.version=%s\n' "$(cvt_tool_version "${CVT_TOOL[$from:$to]:-}")"
        printf 'convert.module=%s\n'   "$CONVERT_VERSION"
        printf 'date=%s\n'             "$(date '+%Y-%m-%d %H:%M:%S %z')"
        # carry the original engine forward if the source run recorded one
        if [ -f "$(dirname "$src")/../PROVENANCE.txt" ]; then
            grep -E '^engine\.(id|version|build)=' "$(dirname "$src")/../PROVENANCE.txt" 2>/dev/null \
                | sed 's/^engine\./source.engine./'
        fi
        [ -n "$loss" ] && printf 'information.lost=%s\n' "$loss"
    } > "$p"
    printf '%s\n' "$p"
}

cvt_tool_version() {
    case $1 in
        upfconv)
            local b; b=$(cvt_upfconv_bin 2>/dev/null) || { printf 'unknown\n'; return; }
            printf 'upfconv.x from %s\n' "$(basename "$(dirname "$b")")" ;;
        *) printf 'n/a\n' ;;
    esac
}

# ---------------------------------------------------------------------------
# cvt_convert <file> <target-format> [outdir]
#
# Echoes the path of the converted file.  Refusals return 1 and explain.
# ---------------------------------------------------------------------------
cvt_convert() {
    local src=$1 to=$2
    local outdir=${3:-$(dirname "$1")}
    local from key tool kind out base rc

    pf_convert_load
    [ -f "$src" ] || { error "no such file: $src"; return 1; }

    if ! from=$(cvt_detect "$src"); then
        error "cannot tell what format $src is from its name."
        error "  Known: upf psp8 vps gth van vdb rrkj3 cpi fhi cpmd xml"
        return 1
    fi
    to=$(lower "$to")

    if [ "$from" = "$to" ]; then
        error "$(basename "$src") is already $to"
        return 1
    fi

    key=$from:$to
    if [ -z "${CVT_KIND[$key]:-}" ]; then
        error "no conversion from $from to $to."
        error "  Paths this tool knows: $(cvt_list_paths | tr '\n' ' ')"
        return 1
    fi

    kind=${CVT_KIND[$key]}
    tool=${CVT_TOOL[$key]}

    if [ "$kind" = refused ]; then
        case ${CVT_REFUSAL[$key]:-physics} in
            no-tool) error "$from -> $to: nothing performs this conversion." ;;
            *)       error "$from -> $to is not a format conversion." ;;
        esac
        printf '%s\n' "${CVT_NOTE[$key]}" | fold -s -w 72 | while IFS= read -r l; do error "  $l"; done
        return 1
    fi

    if [ -n "${CVT_CAVEAT[$key]:-}" ]; then
        warn "$from -> $to is registered but not demonstrated on this machine:"
        printf '%s\n' "${CVT_CAVEAT[$key]}" | fold -s -w 72 | while IFS= read -r l; do warn "  $l"; done
    fi

    if ! cvt_tool_available "$tool"; then
        error "$from -> $to needs $tool, which is not installed."
        case $tool in
            upfconv)    error "  upfconv.x ships with Quantum ESPRESSO; set QE_ROOT_DIR." ;;
        esac
        return 1
    fi

    mkdir -p "$outdir" || return 1
    base=$(basename "$src"); base=${base%.*}
    out=$outdir/$base.$(cvt_extension "$to")

    case $tool in
        upfconv)    cvt_run_upfconv "$src" "$out" "$to" || return 1 ;;
    esac

    [ -s "$out" ] || { error "$tool produced no output for $(basename "$src")"; return 1; }

    local loss=""
    [ "$kind" = lossy ] && loss=${CVT_LOSS[$key]:-unspecified}
    cvt_provenance "$out" "$src" "$from" "$to" "$kind" "$loss" >/dev/null

    printf '%s\n' "$out"
}

cvt_extension() {
    case $1 in
        upf)  printf 'UPF\n' ;;
        xml)  printf 'xml\n' ;;
        psp8) printf 'psp8\n' ;;
        *)    printf '%s\n' "$1" ;;
    esac
}

# upfconv.x writes beside its input and names the result itself, so the run
# happens in a scratch directory and the product is moved into place.
cvt_run_upfconv() {
    local src=$1 out=$2 to=$3 bin wd flag rc
    bin=$(cvt_upfconv_bin) || return 1
    case $to in
        upf) flag=-u ;;
        xml) flag=-x ;;
        *)   error "upfconv.x cannot write $to"; return 1 ;;
    esac
    wd=$(mktemp -d) || return 1

    # The name upfconv.x sees decides which reader it uses, and its matching
    # is narrower than its help text. read_ps_new in QE's upflib/read_ps.f90
    # compares the tail of the file name with no case folding:
    #
    #     ELSE IF (psfile (lm5:l) =='.RRKJ3') THEN
    #        CALL readrrkj (iunps, upf, ierr)
    #
    # so `Si.rrkj3` -- which is what ld1.x writes, and what `upfconv -h`
    # advertises as "*.rrkj3 or *.RRKJ3" -- falls through to read_ncpp, the
    # old-PWSCF reader, and fails with "PP file is empty or wrong". The file
    # is staged under the one spelling the dispatcher actually matches. The
    # bytes are untouched; only the name upfconv reads changes.
    local staged; staged=$(basename "$src")
    case $staged in
        *.rrkj3|*.Rrkj3) staged=${staged%.*}.RRKJ3 ;;
    esac
    cp -f "$src" "$wd/$staged" || { rm -rf "$wd"; return 1; }
    ( cd "$wd" && OMP_NUM_THREADS=1 timeout "${CONVERT_TIMEOUT:-300}" \
        "$bin" "$flag" "$staged" ) > "$wd/convert.log" 2>&1
    rc=$?
    # upfconv.x names the result itself and does not say so on the command
    # line: converting to UPF v2 it appends ".UPF2", not ".UPF".  Globbing for
    # the name we expected found nothing and reported "wrote nothing (exit 0)"
    # for a conversion that had in fact succeeded.  Take whatever it produced.
    local made
    # The most recently written pseudopotential file the converter left
    # behind.  A glob, not `ls | grep`: the filenames come from element
    # symbols and format extensions, all of which are alphanumeric, so a
    # glob is safe here and does not fork `ls` and `grep` for every probe.
    #
    # `-vF "$staged$"` was the old exclusion -- drop the input file itself.
    local -a _cand=()
    for _f in "$wd"/*.UPF2 "$wd"/*.UPF "$wd"/*.upf "$wd"/*.xml; do
        [ -e "$_f" ] || continue
        [ "${_f##*/}" = "$staged" ] && continue
        _cand+=("$_f")
    done
    made=""
    [ ${#_cand[@]} -gt 0 ] && made=${_cand[0]}

    if [ -z "$made" ]; then
        # Nothing with a known extension: take the newest file in the
        # directory that is not the input and not the converter's own log.
        while IFS= read -r _f; do
            [ "${_f##*/}" = "$staged" ] && continue
            [ "${_f##*/}" = convert.log ] && continue
            made=$_f
            break
        done < <(find "$wd" -maxdepth 1 -type f -printf '%T@\t%p\n' 2>/dev/null \
                     | sort -rn | cut -f2-)
    fi
    [ -n "$made" ] && [ "${made#/}" = "$made" ] && made=$wd/$made
    [ -z "$made" ] && made=$(find "$wd" -newer "$wd/$staged" -type f \
                             ! -name convert.log ! -name "$staged" 2>/dev/null | head -1)
    # upfconv.x exits 0 whether or not it succeeded.  "readpp: file X could
    # not be read" followed by "Cannot read file, stopping" is a failure with
    # status zero, so the log is the authority, not $?.
    if grep -qiE 'could not be read|Cannot read file|is empty or wrong|Error' "$wd/convert.log" 2>/dev/null; then
        error "upfconv.x could not read $(basename "$src"):"
        grep -iE 'could not be read|Cannot read file|is empty or wrong|Error' "$wd/convert.log"             | head -2 | while IFS= read -r l; do error "  $(printf '%s' "$l" | sed 's/^ *//')"; done
        rm -rf "$wd"
        return 1
    fi
    if [ -n "$made" ] && [ -s "$made" ]; then
        mv -f "$made" "$out"; rm -rf "$wd"
        # The same normalisation the engine path has always applied. Without
        # it a converted ultrasoft file had an empty pseudo_type and a
        # 2,496-character PP_QFCOEF row that QE's own reader rejects.
        case $to in
            upf) upf_normalise "$out" || { error "could not normalise $(basename "$out")"; return 1; } ;;
        esac
        # upfconv leaves element="" for an RRKJ3 source, although the RRKJ3
        # file names it: its first record is the element symbol. Taken from
        # the source, and only when it is a real element -- never inferred
        # from the file name.
        if grep -q 'element=""' "$out" 2>/dev/null; then
            case $staged in
                *.RRKJ3)
                    local sym
                    sym=$(awk 'NR == 1 { print $1; exit }' "$src" 2>/dev/null)
                    if [ -n "$sym" ] && declare -F el_exists >/dev/null 2>&1 \
                       && { pf_elements_load; el_exists "$sym"; }; then
                        sed -i "s/element=\"\"/element=\"$sym\"/" "$out"
                    fi ;;
            esac
        fi
        return 0
    fi
    error "upfconv.x wrote nothing (exit $rc)"
    sed -n '1,8p' "$wd/convert.log" 2>/dev/null | while IFS= read -r l; do error "  $l"; done
    rm -rf "$wd"
    return 1
}


cvt_list_paths() {
    pf_convert_load
    local k
    for k in "${CVT_ORDER[@]}"; do printf '%s\n' "$k"; done
}

# ---------------------------------------------------------------------------
# cvt_report -- what `pseudoforge convert --list` prints.
# ---------------------------------------------------------------------------
cvt_report() {
    pf_convert_load
    local k from to kind tool avail
    banner "Format conversion"
    printf '  %-14s %-10s %-12s %-9s %s\n' FROM TO KIND TOOL AVAILABLE
    printf '  %s\n' "$(printf '%.0s-' $(seq 1 78))"
    for k in "${CVT_ORDER[@]}"; do
        from=${k%%:*}; to=${k##*:}
        kind=${CVT_KIND[$k]}; tool=${CVT_TOOL[$k]}
        if [ "$kind" = refused ]; then avail="-"
        elif ! cvt_tool_available "$tool"; then avail="no"
        elif [ -n "${CVT_CAVEAT[$k]:-}" ]; then avail="yes *"
        else avail="yes"; fi
        printf '  %-14s %-10s %-12s %-9s %s\n' "$from" "$to" "$kind" "$tool" "$avail"
    done
    local k2 anycav=0
    for k2 in "${CVT_ORDER[@]}"; do [ -n "${CVT_CAVEAT[$k2]:-}" ] && anycav=1; done
    if [ "$anycav" = 1 ]; then
        printf '\n  * the tool is installed and this path is not demonstrated on it.\n'
        printf '    pseudoforge convert --why <from> <to>  prints what was measured.\n'
    fi
    printf '\n  Refused, for one of two reasons, and --why says which:\n'
    printf '    physics  the target needs numbers the source does not contain\n'
    printf '    no-tool  possible in principle; nothing performs it\n'
    printf '  Neither is a missing feature waiting on an install.\n'
    printf '    pseudoforge convert --why <from> <to>\n\n'
    printf '  Cross-family conversion (NC to US, US to PAW) is out of scope: that is a\n'
    printf '  different physical object, not a different file layout.\n\n'
}

cvt_why() {
    pf_convert_load
    local k=$1:$2
    if [ -z "${CVT_KIND[$k]:-}" ]; then
        error "no path $1 -> $2 is known"
        return 1
    fi
    if [ "${CVT_KIND[$k]}" = refused ]; then
        banner "$1 -> $2  (refused: ${CVT_REFUSAL[$k]:-physics})"
    else
        banner "$1 -> $2  (${CVT_KIND[$k]})"
    fi
    printf '%s\n' "${CVT_NOTE[$k]}" | fold -s -w 74 | sed 's/^/  /'
    if [ -n "${CVT_CAVEAT[$k]:-}" ]; then
        printf '\n  Measured on this machine:\n'
        printf '%s\n' "${CVT_CAVEAT[$k]}" | fold -s -w 74 | sed 's/^/  /'
    fi
    printf '\n'
}
