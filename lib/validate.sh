# shellcheck shell=bash
# ---------------------------------------------------------------------------
# validate.sh -- transferability, once per engine rather than once for ld1.
#
# The original test was written when there was one engine.  It builds an ld1.x
# deck with iswitch=2, re-solves the pseudo-atom in configurations it was not
# fitted to, and compares eigenvalues against the all-electron atom.  That is a
# good test and it stays.  What was wrong was applying it as *the* test: run
# ONCVPSP, OPIUM or GTH and it found no PSlibrary deck, returned quietly, and
# the report showed "-" for transferability -- as though the pseudopotential
# had not been checked, when in fact every one of those codes had already run
# its own analysis and written the answer into a log nobody read.
#
# So each engine is asked in its own language:
#
#   ld1       iswitch=2 decks, re-solving in unfitted configurations
#   oncvpsp   its own "Test configuration" tables and its two ghost tests
#   opium     the `tc` command -- a non-local solve of extra configurations
#   gth       the fit's AE-vs-pseudo eigenvalue table, unoccupied states too
#   uspp      the ghost-state search runatom.x performs while generating
#   fhi98pp   pslp.x, which is the analysis half of that distribution
#
# Two things this file is careful about.
#
# **Units.** ONCVPSP and GTH work in Hartree; ld1 reports Rydberg.  Comparing
# them without converting would make those two engines look twice as accurate
# as they are, and the thresholds below are in Rydberg.  Every parser converts
# at the point of extraction.
#
# **Not pretending these are the same measurement.** They are not, and a single
# unlabelled number in a column invites exactly the comparison that should not
# be made.  Each row records the method that produced it, and the report prints
# it.  A ghost state is reported as its own verdict rather than folded into an
# eigenvalue error, because no eigenvalue agreement redeems one.
# ---------------------------------------------------------------------------

# Set by every validator, read by transfer_record.
VAL_METHOD=; VAL_MAXDE=; VAL_DETOT=; VAL_VERDICT=; VAL_NOTE=

# ---------------------------------------------------------------------------
# Does the file say it is what it is labelled?
#
# The first full build of the native store put 1,493 files under labels they
# did not carry: GBRV's PBE decks run as "pz", Vanderbilt's PW91 as "pbe",
# fhi98PP's PW-LDA as "pz" and "pbe", ADPACK's fully relativistic decks as
# "scalar" and "nonrel", GTH's scalar tables as "full". Each engine accepted
# the option and ignored it, and the name was built from the option. And
# every "vwn" file had no exchange at all ("NOX VWN"), because QE does not
# know the short name VWN.
#
# The cure for each was in its own place. This is the check that would have
# caught all of them at once, and will catch the next: after generation, read
# what the file declares and compare it with what was asked for. A file whose
# header disagrees is not accepted under that label.
#
# Only what can be read reliably is compared. The expected QE names below
# were taken from the headers ld1.x itself writes for each functional -- short
# and long forms both appear -- not from memory. Functionals outside LDA/GGA
# (meta-GGA, hybrid, vdW) are generated natively by some engines and by proxy
# by others, so their names are not compared; formats that do not record a
# functional (.cpi, .psp8 here) are not compared either.
# ---------------------------------------------------------------------------
label_upf_names() {   # label_upf_names <xc-id> -> accepted header names, '|'-separated
    case $1 in
        pz)     echo 'LDA|PZ|SLA PZ NOGX NOGC' ;;
        pw)     echo 'PW|SLA PW NOGX NOGC' ;;
        vwn)    echo 'SLA VWN|SLA VWN NOGX NOGC' ;;
        pbe)    echo 'PBE|SLA PW PBX PBC|SLA PW PBE PBE|SLA PW PBE' ;;
        pbesol) echo 'PBESOL|SLA PW PSX PSC' ;;
        pw91)   echo 'PW91|SLA PW GGX GGC' ;;
        bp)     echo 'BP|SLA PZ B88 P86' ;;
        blyp)   echo 'BLYP|SLA LYP B88 BLYP' ;;
        revpbe) echo 'REVPBE|SLA PW REVX PBC' ;;
        wc)     echo 'WC|SLA PW WCX PBC' ;;
    esac
}

# label_mismatch <file> <xc-id> <rel> -> prints the disagreement, or nothing.
label_mismatch() {
    local f=$1 xc=$2 rel=$3 got want r fam
    pf_xc_load 2>/dev/null
    fam=${XC_FAMILY[$xc]:-}
    case $(lower "${f##*.}") in
        upf)
            got=$(awk '/<PP_HEADER/,/\/>|<\/PP_HEADER>/' "$f" | grep -oE 'functional="[^"]*"' | head -1 \
                  | sed 's/^functional="//; s/"$//')
            # v1: QE reads the name as the first 20 columns (read_upf_v1,
            # '(a20,t24,a)'). Reading more took in whatever a writer puts
            # after column 20 and compared that too.
            [ -n "$got" ] || got=$(grep -m1 'Exchange-Correlation functional' "$f" | cut -c1-20)
            got=$(printf '%s' "$got" | tr '[:lower:]' '[:upper:]' | tr -s ' ' | sed 's/^ //; s/ $//')
            # No functional in this tree is exchange-free; a header saying so
            # is wrong whatever was asked for.
            case "$got " in
                "NOX "*) printf 'the file has no exchange (%s)\n' "$got"; return ;;
            esac
            if [ "$fam" = LDA ] || [ "$fam" = GGA ]; then
                want=$(label_upf_names "$xc")
                if [ -n "$want" ] && [ -n "$got" ]; then
                    case "|$want|" in
                        *"|$got|"*) ;;
                        *) printf 'labelled %s, the file declares %s\n' "$(upper "$xc")" "$got"; return ;;
                    esac
                fi
            fi
            r=$(awk '/<PP_HEADER/,/\/>/' "$f" | grep -oE 'relativistic="[^"]*"' | head -1 \
                | sed 's/^relativistic="//; s/"$//' | tr '[:upper:]' '[:lower:]')
            case "$rel:$r" in
                *:|scalar:scalar|full:full|nonrel:no|nonrel:nonrelativistic|nonrel:non-relativistic|nonrel:none) ;;
                *) printf 'labelled %s-relativistic, the file declares relativistic="%s"\n' "$rel" "$r" ;;
            esac ;;
        vps)
            got=$(awk '$1 == "xc.type" { print $2; exit }' "$f")
            case "$xc:$(upper "$got")" in
                pz:LDA|pbe:GGA|*:) ;;
                *) printf 'labelled %s; ADPACK wrote xc.type %s, which is %s\n' "$(upper "$xc")" "$got" \
                       "$([ "$(upper "$got")" = GGA ] && echo PBE || echo 'Ceperley-Alder LDA (PZ)')"; return ;;
            esac
            r=$(awk '$1 == "eq.type" { print $2; exit }' "$f")
            case "$rel:$r" in
                nonrel:sch|scalar:sdirac|full:dirac|*:) ;;
                *) printf 'labelled %s-relativistic, the file solves eq.type %s\n' "$rel" "$r" ;;
            esac ;;
        gth)
            got=$(head -3 "$f" | grep -oE 'GTH-[A-Za-z0-9]+' | head -1)
            want=$(case $xc in pz) echo GTH-PADE ;; pbe) echo GTH-PBE ;; pbesol) echo GTH-PBESOL ;;
                                blyp) echo GTH-BLYP ;; bp) echo GTH-BP ;; esac)
            [ -z "$want" ] || [ -z "$got" ] || [ "$(upper "$got")" = "$want" ] \
                || { printf 'labelled %s, the file is %s\n' "$(upper "$xc")" "$got"; return; }
            [ "$rel" = full ] && printf 'GTH tables carry no relativistic variant; labelled full\n' ;;
    esac
}

# label_verify_batch <element>...
#   After generation, before any test: every file that generated is compared
#   with its label. A disagreement fails the element and moves the file to
#   pseudos/rejected/, so it is kept for inspection but never served.
label_verify_batch() {
    local el upf f why n=0
    for el in "$@"; do
        case $(state_field "$el" 8) in ok|ok-warn) ;; *) continue ;; esac
        upf=$(state_field "$el" 7)
        f=$PROJECT_DIR/pseudos/$upf
        [ -f "$f" ] || continue
        why=$(label_mismatch "$f" "${SPEC[xc]}" "${SPEC[rel]}")
        [ -n "$why" ] || continue
        mkdir -p "$PROJECT_DIR/pseudos/rejected"
        mv -f "$f" "$PROJECT_DIR/pseudos/rejected/" 2>/dev/null
        error "$el  $upf rejected: $why"
        state_record "$el" "${SPEC[family]}" "${SPEC[profile]}" "${SPEC[xc]}" "${SPEC[rel]}" \
            "$(state_field "$el" 6)" "$upf" fail "$(state_field "$el" 9)" "$(state_field "$el" 10)" \
            "rejected: $why"
        n=$((n + 1))
    done
    [ "$n" -gt 0 ] && state_merge
    return 0
}

HARTREE_TO_RY=2

# ---------------------------------------------------------------------------
# transfer_verdict <max|dE| in Ry>
#
# The usual standard for a well-behaved pseudopotential: eigenvalues within
# about a milli-Rydberg of all-electron across the configurations tested.
# ---------------------------------------------------------------------------
transfer_verdict() {
    awk -v d="${1:-0}" 'BEGIN {
        if (d + 0 <= 0)     print "no-data"
        else if (d < 0.001) print "excellent"
        else if (d < 0.005) print "good"
        else if (d < 0.020) print "marginal"
        else                print "poor" }'
}

# ---------------------------------------------------------------------------
# transfer_record <element> <upf>
#   Writes one row of tests/transferability.tsv from the VAL_* variables and
#   says something proportionate on the console.
#
#   1 element  2 upf  3 max|dE|(Ry)  4 dEtot(Ry)  5 verdict  6 method  7 note
#
# Columns 1-5 are the original layout, so the CSV, JSON and HTML reporters keep
# working unchanged; method and note are appended.
# ---------------------------------------------------------------------------
transfer_record() {
    local el=$1 upf=$2
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$el" "$upf" "${VAL_MAXDE:-0}" "${VAL_DETOT:-0}" \
        "${VAL_VERDICT:-no-data}" "${VAL_METHOD:-unknown}" "${VAL_NOTE:-}" \
        >> "$PROJECT_DIR/tests/transferability.tsv"

    local where="${VAL_METHOD:-unknown}"
    case ${VAL_VERDICT:-no-data} in
        excellent|good)
            ok   "$el  transferability: ${VAL_VERDICT} (max |dE| = ${VAL_MAXDE} Ry, $where)" ;;
        marginal)
            warn "$el  transferability: marginal (max |dE| = ${VAL_MAXDE} Ry, $where)" ;;
        poor)
            warn "$el  transferability: POOR (max |dE| = ${VAL_MAXDE} Ry, $where) -- do not use without checking" ;;
        ghost)
            warn "$el  GHOST STATE reported by $where -- ${VAL_NOTE:-see the log}" ;;
        *)
            debug "$el  transferability: no usable data from $where" ;;
    esac
}

# ---------------------------------------------------------------------------
# ONCVPSP
#
# The generation run already does the work.  Its "Test configuration N" blocks
# list, per orbital, the all-electron and pseudo eigenvalues and their
# difference; the "PSP excitation error" line is the transferability number
# proper, being the error in the energy *difference* between a test
# configuration and the reference.  Both are in Hartree.
#
# Both ghost tests are read.  The positive-energy one matters: a highly
# localized state above zero will not show up as a bad eigenvalue anywhere in
# the tables, and it is the failure that makes a pseudopotential unusable in a
# solid while looking perfect in the atom.
# ---------------------------------------------------------------------------
val_oncvpsp() {
    local log=$1 nconf ghost ghost_pos ghost_ecut
    [ -s "$log" ] || return 1
    grep -q 'Test configuration' "$log" || return 1

    VAL_METHOD="oncvpsp test configs"

    # The two ghost tests do not mean the same thing and must not be graded
    # the same.  A *bound* ghost is a spurious state below zero: the
    # pseudopotential is wrong and nothing else about it matters.  A
    # positive-energy ghost is a highly localized state above zero, and
    # ONCVPSP reports the cutoff at which it appears -- if that cutoff is far
    # above the one anybody will use, it cannot be reached and is a note, not
    # a failure.  Grading both as "ghost" condemned a perfectly good SG15
    # silicon whose only ghost sits at 46 Ry.
    ghost=$(grep -ciE 'bound ghost.*(found|detected)|WARNING.*GHOST\(-\)' "$log" 2>/dev/null || true)
    ghost_pos=$(grep -cE 'WARNING - GHOST\(\+\)' "$log" 2>/dev/null || true)
    ghost_ecut=$(awk '/WARNING - GHOST\(\+\)/ { print $(NF-3) }' "$log" 2>/dev/null | head -1)
    VAL_MAXDE=$(awk '
        /Test configuration/ { intable = 1; next }
        intable && /Total energies/ { intable = 0 }
        # n l f eae eps diff -- only the rows that carry a pseudo eigenvalue
        intable && NF == 6 && $1 ~ /^[0-9]+$/ {
            d = $6; gsub(/[dD]/, "E", d); d += 0
            if (d < 0) d = -d
            if (d > m) m = d
        }
        END { printf "%.6f\n", m * 2 }' "$log")

    # The excitation error is only meaningful once a configuration other than
    # the reference has been tested; against the reference it is trivially zero.
    nconf=$(grep -c 'Test configuration' "$log")
    VAL_DETOT=$(awk '
        /PSP excitation error/ {
            for (i = NF; i >= 1; i--)
                if ($i ~ /^-?[0-9.]+[dDeE][-+]?[0-9]+$/ || $i ~ /^-?[0-9]+\.[0-9]+$/) {
                    v = $i; gsub(/[dD]/, "E", v); v += 0; break
                }
            if (v < 0) v = -v
            if (v > m) m = v
        }
        END { printf "%.6f\n", m * 2 }' "$log")

    if [ "${ghost:-0}" -gt 0 ]; then
        VAL_VERDICT=ghost
        VAL_NOTE="bound ghost state -- this pseudopotential should not be used"
    else
        VAL_VERDICT=$(transfer_verdict "$VAL_MAXDE")
        [ "${ghost_pos:-0}" -gt 0 ] &&             VAL_NOTE="positive-energy ghost at about ${ghost_ecut:-?} Ry; harmless below that cutoff, check if you plan to exceed it"
    fi

    if [ "$nconf" -le 1 ]; then
        VAL_NOTE="${VAL_NOTE:+$VAL_NOTE; }reference configuration only -- the deck defines no alternative configurations, so this checks the fit, not transferability"
    else
        VAL_NOTE="${VAL_NOTE:+$VAL_NOTE; }$nconf configurations"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# OPIUM
#
# Unlike the others this one is an extra run, because `tc` is a separate
# command: a non-local solve of the configurations listed in the parameter
# file's [Configs] block.  With no extra configurations there is nothing to
# solve and saying so is better than reporting the reference back as a result.
# ---------------------------------------------------------------------------
val_opium() {
    local log=$1 deck=$2 el=$3 wd bin nconf out
    bin=$(eng_resolve opium 2>/dev/null) || return 1
    [ -s "$deck" ] || return 1

    # [Configs] opens with a count; zero or absent means no extra configurations
    nconf=$(awk '/^\[Configs\]/ { getline; gsub(/[^0-9]/, ""); print; exit }' "$deck")
    VAL_METHOD="opium tc"

    if [ -z "${nconf:-}" ] || [ "$nconf" -le 0 ] 2>/dev/null; then
        VAL_VERDICT=no-data
        VAL_NOTE="the deck lists no extra configurations, so there is nothing for tc to solve"
        return 0
    fi

    wd=$SCRATCH_DIR/opiumtc-$$-$el
    mkdir -p "$wd" || return 1
    cp "$deck" "$wd/$(lower "$el").param" 2>/dev/null || { rm -rf "$wd"; return 1; }
    out=$wd/tc.log
    ( cd "$wd" && OMP_NUM_THREADS=1 timeout "${OPIUM_TC_TIMEOUT:-600}" \
    # `rpt` is not optional: the plain log records each configuration being
    # solved and the ghost tests, but the table this check needs -- the errors
    # in the total-energy *differences* between configurations -- is written
    # only into OPIUM's report file.
        "$bin" "$(lower "$el").param" "$(lower "$el").log" all tc rpt ) > "$out" 2>&1

    local src
    src=$wd/$(lower "$el").rpt
    [ -s "$src" ] || src=$wd/$(lower "$el").log
    [ -s "$src" ] || src=$out
    cp -f "$src" "${log%.log}.tc.log" 2>/dev/null

    # OPIUM's tc report ends with the table this test exists for:
    #
    #   AE-NL-   i   j         DD[mRy]        DD[meV]
    #   AE-NL-   0   1        -7.755580    -105.520099
    #
    # DD is the error in the total-energy *difference* between two
    # configurations -- an excitation energy -- which is the quantity a
    # transferable pseudopotential has to get right.  Both columns are on the
    # line, so a parser that takes "any float on a line mentioning error"
    # picks up the meV column as readily as the mRy one and reports a number
    # 13.6 times too large.  Take column 4 by position, and convert mRy to Ry.
    VAL_MAXDE=$(awk '
        /^ *AE-[NS]L- +[0-9]+ +[0-9]+ / {
            v = $(NF - 1) + 0            # DD[mRy]
            if (v < 0) v = -v
            if (v > m) m = v
        }
        END { printf "%.6f\n", m / 1000 }' "$src" 2>/dev/null)

    # The per-configuration eigenvalue error, for the note.
    local eig
    eig=$(awk '
        /total error *=/ {
            v = $(NF - 1) + 0
            if (v < 0) v = -v
            if (v > m) m = v
        }
        END { printf "%.4f\n", m + 0 }' "$src" 2>/dev/null)

    if grep -qiE 'ghost' "$src" 2>/dev/null && ! grep -qiE 'no ghosts' "$src" 2>/dev/null; then
        VAL_VERDICT=ghost
        VAL_NOTE=$(grep -iE 'ghost' "$src" | grep -viE 'not done|sorry|[?][?][?]|testing|local part' | head -1 | sed 's/^[[:space:]]*//')
    elif [ "${VAL_MAXDE:-0}" = "0.000000" ]; then
        VAL_VERDICT=no-data
        VAL_NOTE="tc ran over $nconf configuration(s) but wrote no DD table; see ${log%.log}.tc.log"
    else
        VAL_VERDICT=$(transfer_verdict "$VAL_MAXDE")
        VAL_NOTE="excitation error over $nconf extra configuration(s); max eigenvalue error ${eig} mRy"
    fi
    rm -rf "$wd"
    return 0
}

# ---------------------------------------------------------------------------
# GTH
#
# The fit log ends with a table of all-electron against pseudo eigenvalues for
# every orbital it fitted, occupied and unoccupied alike, in Hartree.  The
# unoccupied ones are the interesting part: fitting them is what the GTH
# procedure does deliberately to buy transferability, so reading them is
# reading the thing the method claims to provide.
#
# The occupied states set the headline number, which keeps it comparable with
# what the other engines report; the unoccupied spread goes in the note, since
# it is normally an order of magnitude larger and would otherwise look like a
# failure rather than the expected behaviour.
# ---------------------------------------------------------------------------
val_gth() {
    local log=$1 occ_max unocc_max pen
    [ -s "$log" ] || return 1

    # Without --refit no fit was run: the file holds CP2K's published
    # coefficients, copied. There is no residual to report and reporting one
    # would be reporting somebody else's fit as this run's result. Say that
    # instead of writing nothing, which reads as "not checked".
    if ! grep -q 'ae *pseudo *diff' "$log"; then
        VAL_METHOD="none (published coefficients)"
        VAL_MAXDE=0; VAL_DETOT=0
        VAL_VERDICT=no-data
        VAL_NOTE="published CP2K coefficients, not fitted here; upstream Delta-tests them. Use --refit to fit and measure locally."
        return 0
    fi

    VAL_METHOD="gth fit residuals"

    # Read the last table only: earlier ones are intermediate simplex states.
    read -r occ_max unocc_max < <(awk '
        /nl *s *occ *ae *pseudo *diff/ { delete o; delete u; no = 0; nu = 0; next }
        # an orbital header line: "3s   0.5    2.0000"
        $1 ~ /^[0-9][spdf]$/ && NF == 3 { occ = $3 + 0; next }
        $1 == "eigenvalue" && NF >= 4 {
            d = $4; gsub(/[dD]/, "E", d); d += 0
            if (d < 0) d = -d
            if (occ > 0) { if (d > mo) mo = d } else { if (d > mu) mu = d }
        }
        END { printf "%.6f %.6f\n", mo * 2, mu * 2 }' "$log")

    VAL_MAXDE=$occ_max
    pen=$(grep -i 'penalty' "$log" 2>/dev/null | tail -1 | awk '{print $NF}')
    VAL_DETOT=0
    VAL_VERDICT=$(transfer_verdict "$VAL_MAXDE")
    VAL_NOTE="occupied states; unoccupied max |dE| = ${unocc_max} Ry${pen:+; final penalty $pen}"
    return 0
}

# ---------------------------------------------------------------------------
# USPP
#
# runatom.x searches for ghost states as part of generating, over a ladder of
# Bessel cutoffs.  It produces no eigenvalue comparison table, so there is no
# transferability number to report and inventing one would be worse than the
# honest gap: what this returns is a ghost verdict and nothing else.
# ---------------------------------------------------------------------------
val_uspp() {
    local log=$1
    [ -s "$log" ] || return 1
    grep -qi 'ghost' "$log" || return 1

    VAL_METHOD="uspp ghost scan"
    VAL_MAXDE=0
    VAL_DETOT=0
    if grep -qiE 'ghost state (found|detected)|possible ghost.*found|warning.*ghost' "$log" 2>/dev/null; then
        VAL_VERDICT=ghost
        VAL_NOTE=$(grep -iE 'ghost' "$log" | grep -viE 'beginning search' | head -1 | sed 's/^[[:space:]]*//')
    else
        VAL_VERDICT=no-data
        VAL_NOTE="ghost search ran and reported none; this engine writes no eigenvalue comparison, so there is no transferability number"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# fhi98PP
#
# pslp.x is the analysis half of the distribution: it does the ghost-state
# analysis and the logarithmic-derivative comparison that fhipp.x does not.
# It reads the pseudopotential fhipp.x wrote, so it needs that run's working
# directory, which exec_fhi98pp keeps when PF_KEEP_SCRATCH is set.  When the
# directory is gone, say so rather than report a silent "-".
# ---------------------------------------------------------------------------
val_fhi98pp() {
    local log=$1 el=$2 bin wd out
    bin=$(eng_resolve fhi98pp 2>/dev/null) || return 1
    bin=$(dirname "$bin")/pslp.x
    [ -x "$bin" ] || return 1

    wd=$SCRATCH_DIR/$$-$el
    if [ ! -f "$wd/fort.20" ]; then
        VAL_METHOD="pslp"
        VAL_VERDICT=no-data
        VAL_NOTE="pslp.x needs the generation working directory; re-run with PF_KEEP_SCRATCH=1 to analyse"
        return 0
    fi

    out=$wd/pslp.out
    ( cd "$wd" && OMP_NUM_THREADS=1 timeout "${PSLP_TIMEOUT:-300}" "$bin" ) > "$out" 2>&1
    cp -f "$out" "${log%.log}.pslp.log" 2>/dev/null

    VAL_METHOD="pslp ghost/logderiv"
    VAL_MAXDE=0
    VAL_DETOT=0

    # pslp states its conclusion on lines beginning "*": "* no ghost state",
    # "* ghost state below the reference energy", "* undetermined".  Searching
    # for the bare word "ghost" instead matches its own explanatory prose --
    # "the ghost state analysis will assume a zero reference energy" -- and
    # reports a ghost for a file that has none. That is the worst possible
    # direction for this check to fail in.
    if grep -qE '^ *\* *ghost state' "$out" 2>/dev/null; then
        VAL_VERDICT=ghost
        VAL_NOTE=$(grep -E '^ *\* *ghost state' "$out" | head -1 | sed 's/^[[:space:]]*\* *//')
        return 0
    fi

    # And pslp can fail outright while still exiting normally: it stops on a
    # log-derivative radius it cannot use, leaves NaN in the KB energies, and
    # writes an "undetermined" verdict. That is an analysis that did not run,
    # not a pseudopotential that passed.
    if grep -qE 'STOP pslp|NaN' "$out" 2>/dev/null; then
        VAL_VERDICT=no-data
        VAL_NOTE="pslp.x could not complete the analysis ($(grep -oE 'STOP pslp[^"]*' "$out" | head -1 | cut -c1-70)); see ${log%.log}.pslp.log"
        return 0
    fi
    if grep -qE '^ *\* *undetermined' "$out" 2>/dev/null; then
        VAL_VERDICT=no-data
        VAL_NOTE="pslp.x returned undetermined -- inspect the log derivatives in ${log%.log}.pslp.log"
        return 0
    fi

    VAL_VERDICT=no-data
    VAL_NOTE="pslp.x reported no ghost states; it writes no eigenvalue comparison, so there is no transferability number"
    return 0
}

# ---------------------------------------------------------------------------
# AtomPAW
#
# This one reports a health check, not a transferability number, and the
# distinction is kept rather than papered over.  atompaw does not re-solve the
# atom in other configurations the way ld1 does, so there is no eigenvalue
# difference to quote.  What it does publish is two things that decide whether
# the data set is usable at all:
#
#   the overlap operator's eigenvalues in the projector basis -- all positive
#   means the basis is well conditioned; a negative one means the projectors
#   are near-duplicates and atompaw refuses to continue
#
#   orbital leakage, the fraction of each orbital lying outside the
#   augmentation sphere -- a core orbital leaking more than a fraction of a
#   percent means the augmentation radius has been pushed out over a state
#   that should have been frozen, which quietly corrupts the frozen-core
#   approximation the whole method rests on
# ---------------------------------------------------------------------------
val_atompaw() {
    local log=$1 leak minov
    [ -s "$log" ] || return 1
    grep -q 'Orbital leakage' "$log" || return 1

    VAL_METHOD="atompaw leakage/overlap"
    VAL_MAXDE=0
    VAL_DETOT=0

    # worst leakage among orbitals marked core (is_core? == T)
    leak=$(awk '
        /Orbital leakage/ { inblock = 1; next }
        inblock && /Summary of PAW/ { inblock = 0 }
        inblock && NF == 4 && $3 == "T" {
            v = $4 + 0; if (v > m) m = v
        }
        END { printf "%.2f\n", m + 0 }' "$log")

    minov=$(awk '
        /Eigenvalues of overlap operator/ { inblock = 1; next }
        inblock && NF == 2 && $1 ~ /^[0-9]+$/ {
            v = $2 + 0
            if (first == 0 || v < m) { m = v; first = 1 }
            next
        }
        inblock && NF == 0 { if (first) inblock = 0 }
        END { if (first) printf "%.3e\n", m; else print "" }' "$log")

    if awk -v l="${leak:-0}" 'BEGIN { exit !(l > 1.0) }'; then
        VAL_VERDICT=marginal
        VAL_NOTE="a core orbital leaks ${leak}% outside the augmentation sphere -- the matching radius is too large for the frozen core"
    else
        VAL_VERDICT=no-data
        VAL_NOTE="core leakage ${leak}%${minov:+, smallest overlap eigenvalue $minov}; atompaw writes no eigenvalue comparison, so there is no transferability number"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# transfer_test_one <element>
#
# Dispatch to whichever validator matches the engine that actually produced
# this file, and record the result.  Returns 0 when a row was written.
# ---------------------------------------------------------------------------
transfer_test_one() {
    local el=$1 eng=${SPEC[engine]:-ld1} upf log deck rc=1

    upf=$(state_field "$el" 7)
    [ -n "$upf" ] && [ -f "$PROJECT_DIR/pseudos/$upf" ] || return 1
    log=$PROJECT_DIR/logs/$el.log

    VAL_METHOD=; VAL_MAXDE=; VAL_DETOT=; VAL_VERDICT=; VAL_NOTE=

    case $eng in
        ld1)
            # ld1 keeps its own routine: it builds and runs a fresh deck rather
            # than reading a log, and it already writes its own row.
            ld1_test_one "$el"
            return $? ;;
        oncvpsp) val_oncvpsp "$log"; rc=$? ;;
        gth)     val_gth     "$log"; rc=$? ;;
        uspp)    val_uspp    "$log"; rc=$? ;;
        atompaw) val_atompaw "$log"; rc=$? ;;
        fhi98pp) val_fhi98pp "$log" "$el"; rc=$? ;;
        opium)
            deck=$(ls "$PROJECT_DIR/inputs/$(lower "$el")".param 2>/dev/null | head -1)
            val_opium "$log" "${deck:-}" "$el"; rc=$? ;;
        *)       return 1 ;;
    esac

    [ "$rc" -eq 0 ] || return 1
    transfer_record "$el" "$upf"
    return 0
}

# ---------------------------------------------------------------------------
# val_method_label <engine> -- what the banner should say it is about to run.
#
# Naming the actual analysis matters more than it looks: "Transferability tests
# (ld1.x)" over an ONCVPSP run told the user something that was simply untrue.
# ---------------------------------------------------------------------------
val_method_label() {
    case $1 in
        ld1)     printf 'ld1.x, iswitch=2
' ;;
        oncvpsp) printf "oncvpsp's own test configurations
" ;;
        opium)   printf 'opium tc
' ;;
        gth)     printf 'GTH fit residuals
' ;;
        uspp)    printf 'uspp ghost search
' ;;
        fhi98pp) printf 'pslp.x
' ;;
        atompaw) printf 'atompaw leakage/overlap
' ;;
        *)       printf '%s
' "$1" ;;
    esac
}
