# shellcheck shell=bash
# ---------------------------------------------------------------------------
# input_builder.sh -- write the input deck each engine expects.
#
# The four engines share nothing: different file formats, different physics
# knobs, different ideas of what a "cut-off radius" even indexes.  This module
# is the single place that knows those differences.  Everything it emits is
# derived from one of three sources, and every deck records which one:
#
#   library     parameters published by the pseudopotential library itself
#               (fetched, or supplied with --params)
#   vendor      parameters shipped inside the engine's own source tree --
#               fhi98PP's bin/Elements, USPP's Work/, ONCVPSP's tests/data
#   PseudoForge     PseudoForge's own construction from the ground-state configuration
#               and a documented radius heuristic
#
# Nothing here invents a number and calls it SG15 or GBRV.  When no vetted
# parameters exist for an element, the deck is built from the element's own
# electronic structure and stamped "PseudoForge" so it can never be mistaken for a
# published set.  See docs/reference/data-provenance.md.
# ---------------------------------------------------------------------------

# The provenance of the deck most recently built, for the caller to record.
IB_PROVENANCE=
IB_SOURCE=

# ---------------------------------------------------------------------------
# ib_check_deck <deck> <engine>
#
# A deck that contains a literal backslash-n is always a bug, never data.
#
# This exists because the same mistake has now been made three times, in three
# different engines, and each time it was silent in a different way.  A `printf`
# format string inside an awk program loses its escape somewhere between the
# editor and the file, and:
#
#   - awk stops with "unterminated string" and writes nothing, so the deck is
#     empty and the run reports "no input parameters available" (OPIUM, ADPACK);
#   - or the escape survives as two characters and lands in the deck itself,
#     where the engine reads it as data (APE).
#
# Neither failure names the real cause.  Checking the product instead of
# trusting the process catches the whole class at the point it happens.
#
# None of the nine engines' formats can legitimately contain a backslash: they
# are Fortran namelists, keyword blocks and numeric tables.  Verified against
# every bundled deck before this check was added.
# ---------------------------------------------------------------------------
ib_check_deck() {
    local deck=$1 eng=${2:-}

    [ -e "$deck" ] || { error "$eng: the input builder produced no file at $deck"; return 1; }
    if [ -f "$deck" ] && [ ! -s "$deck" ]; then
        error "$eng: the input builder produced an empty deck ($deck)."
        error "  This is usually an awk or printf format string that lost an escape:"
        error "  awk stops on \"unterminated string\" and writes nothing."
        return 1
    fi

    if [ -f "$deck" ] && grep -q '\\n' "$deck" 2>/dev/null; then
        error "$eng: the deck contains a literal backslash-n ($deck)."
        error "  No engine format here uses one, so this is an escaping bug in the"
        error "  builder, not data.  The offending line(s):"
        grep -n '\\n' "$deck" | head -3 | while IFS= read -r l; do error "    $l"; done
        return 1
    fi

    # A deck of one or two lines is a truncated write, not a real input.
    local n
    n=$(grep -c . "$deck")
    if [ "${n:-0}" -lt 3 ]; then
        error "$eng: the deck has only $n non-empty line(s) ($deck) -- truncated write"
        return 1
    fi

    # The valence partition is an ld1.x concern: it is the only engine here
    # whose deck states the reference configuration as a noble-gas core plus
    # shells, which is the notation the mistake hides in.
    if [ "$eng" = ld1 ]; then
        ib_check_valence "$deck" || return 1
    fi

    return 0
}


# ---------------------------------------------------------------------------
# ib_check_valence <deck>
#
# A generation deck may not ask for more electrons than the nucleus has
# protons.  ld1.x does not refuse one that does: it puts the surplus in the
# core, so z_core exceeds Z and the pseudopotential comes out with a negative
# z_valence.
#
# That is how caesium failed.  PSlibrary 1.0.0 ships
#
#     config='[Xe] 4f14 6s1 6p0 5d0'          (us_ps_low.job, paw_ps_low.job)
#
# for an element with Z=55.  Xenon is already 54 electrons and contains no 4f,
# so the deck asks for 69.  4F is not in the pseudised list, so all 14 go to
# the core: z_core = 60, z_valence = 55 - 60 = -5.  The generated file then
# declares z_valence="-5.0" in its header while its own local potential decays
# as -2*9/r -- internally inconsistent, and unusable by any code that reads the
# header.  The scattering was never wrong; the bookkeeping was.
#
# The 4f14 is upstream's own copy-paste from the Hf-Hg block directly below it,
# where it is correct (hafnium really is [Xe]4f14 5d2 6s2).  Three independent
# sources say so: the library's ChangeLog documents the partition for this row
# as "5s, 5p, 5d, 6s, 6p (Cs-Hg)"; the 0.2.3 generation deck for the same
# pseudopotential uses '[Xe] 5d0.0 6s1 6p0'; and PSlibrary's *own* test deck
# for this very file (us_ps_test_low.job) also uses '[Xe] 5d0.0 6s1 6p0'.
# Upstream's two halves contradict each other and the test half is right.
#
# Checked against every deck in data/psl before being switched on: 1040 decks,
# three exceed Z -- the two caesium ones this fixes, and one *test* deck for
# lanthanum.  Test decks are exempt, and legitimately so: iswitch=2 measures
# transferability in excited and charged configurations, so an anion there is
# the point.  Generation decks (iswitch=3) have no such licence.
#
# A config asking for FEWER electrons than Z is left alone -- generating from a
# positive ion is a real technique, and fourteen shipped decks do it (Na(+0.5),
# Mg(+0.5), Hg(+1)).
# ---------------------------------------------------------------------------
ib_check_valence() {
    local deck=$1 zed cfg sum

    # Generation decks only.  iswitch=2 is a transferability test.
    grep -qE '^[[:space:]]*iswitch[[:space:]]*=[[:space:]]*3' "$deck" 2>/dev/null || return 0

    zed=$(grep -m1 -oE 'zed[[:space:]]*=[[:space:]]*[0-9.]+' "$deck" 2>/dev/null \
          | grep -oE '[0-9.]+$')
    cfg=$(grep -m1 -E "config[[:space:]]*=" "$deck" 2>/dev/null \
          | sed "s/.*config[[:space:]]*=[[:space:]]*'//; s/'.*//")
    [ -n "$zed" ] && [ -n "$cfg" ] || return 0

    sum=$(awk -v cfg="$cfg" '
        BEGIN {
            ng["He"]=2; ng["Ne"]=10; ng["Ar"]=18
            ng["Kr"]=36; ng["Xe"]=54; ng["Rn"]=86
            n = split(cfg, a, " "); tot = 0
            for (i = 1; i <= n; i++) {
                t = a[i]
                if (t == "") continue
                if (t ~ /^\[/) {
                    g = t; gsub(/[][]/, "", g)
                    if (g in ng) { tot += ng[g]; continue }
                    print "?"; exit
                }
                if (match(t, /^[0-9]+[spdfSPDF]/)) {
                    occ = substr(t, RSTART + RLENGTH)
                    if (occ == "") occ = 0
                    if (occ !~ /^-?[0-9]*\.?[0-9]*$/) { print "?"; exit }
                    # A negative occupation is ld1.x notation for an unbound
                    # state carried in the basis, not an electron.
                    if (occ + 0 > 0) tot += occ + 0
                    continue
                }
                print "?"; exit
            }
            printf "%g\n", tot
        }' 2>/dev/null)

    # An unrecognised token means the check cannot speak, not that the deck is
    # wrong.  Stay quiet rather than block a deck we do not understand.
    [ -n "$sum" ] && [ "$sum" != "?" ] || return 0

    if awk -v e="$sum" -v z="$zed" 'BEGIN { exit (e > z + 0.001) ? 0 : 1 }'; then
        error "ld1: the reference configuration asks for more electrons than the element has."
        error "  config='$cfg'  is $sum electrons, but zed=$zed."
        error "  ld1.x will put the surplus in the core and emit a negative z_valence."
        error "  Check for a shell listed twice -- a noble-gas core already contains it."
        return 1
    fi
    return 0
}
# ---------------------------------------------------------------------------
# ib_build <engine> <element> <outdir>
#   Writes the deck and echoes "<deckfile>\t<expected-output-basename>".
#   IB_PROVENANCE / IB_SOURCE are set as a side effect.
# ---------------------------------------------------------------------------
ib_build() {
    local eng=$1 el=$2 outdir=$3
    IB_PROVENANCE=; IB_SOURCE=
    mkdir -p "$outdir" || return 1
    local line rc
    case $eng in
        ld1)     line=$(ib_build_ld1     "$el" "$outdir"); rc=$? ;;
        oncvpsp) line=$(ib_build_oncvpsp "$el" "$outdir"); rc=$? ;;
        uspp)    line=$(ib_build_uspp    "$el" "$outdir"); rc=$? ;;
        fhi98pp) line=$(ib_build_fhi98pp "$el" "$outdir"); rc=$? ;;
        opium)   line=$(ib_build_opium   "$el" "$outdir"); rc=$? ;;
        gth)     line=$(ib_build_gth     "$el" "$outdir"); rc=$? ;;
        adpack)  line=$(ib_build_adpack  "$el" "$outdir"); rc=$? ;;
        atompaw) line=$(ib_build_atompaw "$el" "$outdir"); rc=$? ;;
        ape)     line=$(ib_build_ape     "$el" "$outdir"); rc=$? ;;
        *) error "no input builder for engine '$eng'"; return 1 ;;
    esac
    [ "$rc" -eq 0 ] && [ -n "$line" ] || return 1
    # Check the product, not the process -- see ib_check_deck.
    ib_check_deck "$(printf '%s' "$line" | cut -d"$(printf '')" -f1)" "$eng" || return 1
    # The builders run in a command substitution, so they append their own
    # provenance to the line rather than setting a variable that would be lost.
    printf '%s
' "$line"
}

# ---------------------------------------------------------------------------
# ld1 -- delegates to the existing recipe engine, which already reproduces
# PSlibrary byte for byte.  Nothing to add here.
# ---------------------------------------------------------------------------
ib_build_ld1() {
    local el=$1 outdir=$2 deck upf set tag
    # A profile may ship its own ld1.x decks rather than being backed by the
    # PSlibrary recipe database -- Marburg publishes exactly that for the
    # actinoids.  Those are the library's real numbers, so they come first.
    local libdeck
    if libdeck=$(params_find "${SPEC[profile]}" "$el" 2>/dev/null) && [ -n "$libdeck" ]; then
        case $libdeck in
            *.in)
                if ib_ld1_adopt "$libdeck" "$el" "$outdir"; then
                    return 0
                fi
                ;;
        esac
    fi
    IFS=$'\t' read -r deck upf set tag < <(recipe_build "$el" "$outdir") || return 1
    [ -n "${deck:-}" ] || return 1
    IB_PROVENANCE=library
    IB_SOURCE="PSlibrary $set/$tag"
    case ${SPEC[profile]} in
        pseudoforge-auto) IB_PROVENANCE=pseudoforge; IB_SOURCE="pseudoforge-auto" ;;
    esac
    printf '%s\x1f%s\x1f%s\x1f%s\n' "$deck" "$upf" "$IB_PROVENANCE" "$IB_SOURCE"
}

# ---------------------------------------------------------------------------
# ONCVPSP
#
# Input layout (see the ONCVPSP user guide):
#   atsym z nc nv iexc psfile
#   nc+nv lines:  n l f
#   lmax
#   lmax+1 lines: l rc ep ncon nbas qcut
#   lloc lpopt rc(5) dvloc0
#   lmax+1 lines: l nproj debl
#   icmod fcfact
#   epsh1 epsh2 depsh
#   rlmax drl
#   ncnf   (then the test configurations)
#
# Parameter source, in order:
#   1. a published .dat/.in from the library (SG15, PseudoDojo) if we have one
#   2. ONCVPSP's own tests/data deck for that element
#   3. PseudoForge's construction
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# ONCVPSP's iexc codes.
#
# Positive values are the four built-ins.  A negative value is a pair of libxc
# functional ids packed as -(exchange*1000 + correlation) -- exc_libxc.f90 takes
# it apart with id(1)=abs(iexc)/1000, id(2)=abs(iexc)-id(1)*1000.  That path
# exists only when ONCVPSP was linked against a real libxc, so the build is
# probed rather than assumed: a negative iexc handed to a stub build stops with
# an error, and falling back silently to PBE would hand back the wrong
# functional under the right file name.
#
# The ids below are read from the installed libxc header at build time and
# recorded in data/libxc.tsv, not written from memory.
# ---------------------------------------------------------------------------
oncv_has_libxc() {
    [ -n "${ONCVPSP_LIBXC:-}" ] && { [ "$ONCVPSP_LIBXC" = 1 ]; return $?; }
    local bin
    bin=$(eng_resolve oncvpsp 2>/dev/null) || return 1
    # The stub reports itself; a real link pulls in libxc's shared object.
    ldd "$bin" 2>/dev/null | grep -qi 'libxc' && return 0
    return 1
}

# The libxc id pair for one of our functional ids, from data/libxc.tsv.
oncv_libxc_iexc() {
    local want=$1 f=$PF_DATA/libxc.tsv x c
    [ -f "$f" ] || return 1
    IFS=$'\t' read -r _ x c < <(awk -F'\t' -v w="$want" '$1 == w { print; exit }' "$f") || return 1
    [ -n "${x:-}" ] && [ -n "${c:-}" ] || return 1
    printf -- '-%d\n' $(( x * 1000 + c ))
}

# ---------------------------------------------------------------------------
# oncv_iexc_functional <iexc> -- which functional does this code mean?
#
# Needed because the same functional has two spellings.  ONCVPSP's built-in 4
# and libxc's -101130 are both PBE, and comparing the raw numbers made SG15's
# own PBE deck look like a mismatch: it was retargeted to the libxc spelling
# and relabelled as this tool's construction, quietly losing the byte-identical
# reproduction of the library. Compare what the codes *mean*, not how they are
# written.
# ---------------------------------------------------------------------------
oncv_iexc_functional() {
    local ie=$1 f=$PF_DATA/libxc.tsv
    case $ie in
        1) printf 'wigner
'; return 0 ;;
        2) printf 'hl
';     return 0 ;;
        3) printf 'pz
';     return 0 ;;
        4) printf 'pbe
';    return 0 ;;
    esac
    case $ie in
        -*) ;;
        *) return 1 ;;
    esac
    [ -f "$f" ] || return 1
    local n=${ie#-} x c
    x=$(( n / 1000 )); c=$(( n - x * 1000 ))
    awk -F'	' -v x="$x" -v c="$c" '$2 == x && $3 == c { print $1; found = 1; exit }
                                    END { exit !found }' "$f"
}

ib_oncv_iexc() {
    local gen; gen=$(xc_generator "${SPEC[xc]}")
    if oncv_has_libxc; then
        local ie
        if ie=$(oncv_libxc_iexc "$gen"); then printf '%s\n' "$ie"; return 0; fi
    fi
    case $gen in
        pz|vwn|vwn-rpa) echo 3 ;;   # Perdew-Zunger LDA
        pw)             echo 3 ;;   # closest built-in LDA
        pbe|pbesol|revpbe|blyp|bp|pw91|wc|b86b|optb88|sogga|q2d) echo 4 ;;  # PBE
        *)              echo 4 ;;
    esac
}

# Does the chosen functional actually exist in this ONCVPSP build?
ib_oncv_xc_warn() {
    local gen; gen=$(xc_generator "${SPEC[xc]}")
    if oncv_has_libxc; then
        oncv_libxc_iexc "$gen" >/dev/null 2>&1 && return 0
        # libxc is linked but this functional is not in the table.  The common
        # case is meta-GGA, and it is worth being specific: libxc has SCAN,
        # ONCVPSP does not use it.  functionals.F90 stops at XC_FAMILY_MGGA
        # with "meta GGA not coded yet", so linking libxc does not buy it.
        case ${XC_FAMILY[${SPEC[xc]}]:-} in
            metaGGA|MGGA)
                warn "ONCVPSP cannot generate meta-GGA even with libxc: its own functionals.F90 stops at XC_FAMILY_MGGA."
                warn "  '$gen' will be generated as PBE instead; the file is labelled accordingly." ;;
            *)  warn "no libxc mapping for '$gen'; generated as $(printf '%s' "$(ib_oncv_iexc)" | sed 's/^3$/PZ/; s/^4$/PBE/')" ;;
        esac
        return 0
    fi
    case $gen in
        pz|pbe) return 0 ;;
        *) warn "this ONCVPSP was built without libxc, so it offers only LDA(PZ) and PBE; '$gen' is generated as $(ib_oncv_iexc | sed 's/3/PZ/; s/4/PBE/')"
           warn "  rebuild with libxc for PBEsol, BLYP, revPBE, WC, PW91 and AM05: pseudoforge engines build oncvpsp" ;;
    esac
}


# Find a published or vendor deck for this element.
ib_oncv_find_deck() {
    local el=$1 z d f
    z=${EL_Z[$el]}
    # 0. the library's own inputs, fetched by params.sh.  These are the real
    #    thing -- SG15's .dat decks, PseudoDojo's .in files -- so a run using
    #    them is a reproduction, not an approximation.
    if f=$(params_find "${SPEC[profile]}" "$el" 2>/dev/null) && [ -n "$f" ]; then
        printf 'library	%s
' "$f"; return 0
    fi
    # 1. a library deck fetched or supplied by the user
    for d in "${PARAMS_DIR:-}" "$PF_DATA/params/${SPEC[profile]}" "$PF_DATA/params/oncvpsp"; do
        [ -n "$d" ] && [ -d "$d" ] || continue
        for f in "$d/$el.dat" "$d/$el.in" "$d/$(printf '%02d' "$z")_$el.dat"; do
            [ -f "$f" ] && { printf 'library\t%s\n' "$f"; return 0; }
        done
    done
    # 2. ONCVPSP's own regression decks
    local root=${ONCVPSP_SRC_DIR:-$(eng_builddir)/oncvpsp}
    for d in "$root" "$root"/*/; do
        [ -d "$d/tests/data" ] || continue
        for f in "$d/tests/data/$(printf '%02d' "$z")_$el.dat" \
                 "$d/tests/data/$(printf '%02d' "$z")_${el}_UPF.dat"; do
            [ -f "$f" ] && { printf 'vendor\t%s\n' "$f"; return 0; }
        done
    done
    return 1
}

ib_build_oncvpsp() {
    local el=$1 outdir=$2
    local kind src deck out z

    # Say so when the requested functional is not the one that will be used.
    # This check existed but nothing called it, so a run asking for PBEsol on
    # a stub-linked ONCVPSP quietly produced PBE with no warning at all.
    ib_oncv_xc_warn
    z=${EL_Z[$el]}
    deck=$outdir/$el.dat
    out=$el

    if IFS=$'\t' read -r kind src < <(ib_oncv_find_deck "$el"); then
        # Reuse the published deck verbatim, changing only the output format.
        # Touching anything else would make the result something other than
        # what that deck describes.
        #
        # ONCVPSP writes one format per run -- psfile is a single field -- and
        # this used to force "upf" whatever was asked for, so `--format psp8`
        # silently produced a UPF and the psp8 branch in the executor was
        # unreachable. The requested format decides it now.
        ib_oncv_retarget_psfile "$src" "$deck" "$(ib_oncv_psfile)" || return 1
        IB_PROVENANCE=$kind
        IB_SOURCE=$src

        # The deck carries its own functional, and until now it was used as
        # published while the *file* was named after whatever the run asked
        # for.  Ask SG15 -- a PBE-only library -- for PBEsol and the result was
        # a PBE pseudopotential called Si.pbesol-oncv.UPF: the one failure mode
        # this tool exists to avoid.  Compare the two and act on the mismatch.
        local deck_iexc want_iexc
        deck_iexc=$(awk '!/^[[:space:]]*#/ && NF >= 5 { print $5; exit }' "$deck")
        want_iexc=$(ib_oncv_iexc)
        local deck_fn want_fn
        deck_fn=$(oncv_iexc_functional "${deck_iexc:-}" 2>/dev/null || printf '%s' "${deck_iexc:-}")
        want_fn=$(xc_generator "${SPEC[xc]}")
        if [ -n "$deck_iexc" ] && [ "$deck_fn" != "$want_fn" ]; then
            if oncv_has_libxc; then
                # Retarget it, but stop calling the result the library's: a
                # published deck run at a different functional is no longer
                # that library's pseudopotential.
                awk -v ie="$want_iexc" '
                    !done && !/^[[:space:]]*#/ && NF >= 5 {
                        printf "    %-4s %-4s %3s %3s %6s   %s\n", $1, $2, $3, $4, ie, $6
                        done = 1; next
                    }
                    { print }' "$deck" > "$deck.tmp" && mv -f "$deck.tmp" "$deck"
                warn "$el: ${PROF_LABEL[${SPEC[profile]}]:-${SPEC[profile]}} publishes this deck for a different functional."
                warn "  Its radii and projectors are being re-run at $(upper "$(xc_generator "${SPEC[xc]}")") via libxc, which is"
                warn "  NOT ${PROF_LABEL[${SPEC[profile]}]:-${SPEC[profile]}}; labelled 'pseudoforge' in the report and file name."
                IB_PROVENANCE=pseudoforge
                IB_SOURCE="$src, re-run at $(xc_generator "${SPEC[xc]}")"
            else
                error "$el: this deck is for iexc=$deck_iexc but the run asked for $(upper "$(xc_generator "${SPEC[xc]}")")."
                error "  This ONCVPSP has no libxc, so it cannot be re-run at that functional."
                error "  Build libxc support (pseudoforge engines build oncvpsp) or pick the functional the library publishes."
                IB_MESSAGE="deck functional does not match the requested one"
                return 1
            fi
        fi
    else
        ib_oncv_synthesise "$el" "$deck" || return 1
        # The user asked for a named library.  If it has no deck for this
        # element under these settings, they are getting PseudoForge's own
        # construction instead -- which is a different pseudopotential, and they
        # have to be told at the moment it happens, not left to find it in a
        # column later.
        case ${SPEC[profile]} in
            pseudoforge-auto|psl-*) ;;
            *) warn "$el: ${PROF_LABEL[${SPEC[profile]}]:-${SPEC[profile]}} publishes no deck for $(upper "$(xc_generator "${SPEC[xc]}")")/$(rel_canon "${SPEC[rel]}")."
               warn "  Generating with PseudoForge's own parameters instead -- this is NOT ${PROF_LABEL[${SPEC[profile]}]:-${SPEC[profile]}}."
               warn "  It is labelled 'pseudoforge' in the report and in the file name." ;;
        esac
        IB_PROVENANCE=pseudoforge
        IB_SOURCE="PseudoForge construction from the ground-state configuration"
    fi
    printf '%s\x1f%s\x1f%s\x1f%s\n' "$deck" "$out" "$IB_PROVENANCE" "$IB_SOURCE"
}

# ---------------------------------------------------------------------------
# ib_oncv_psfile -- which format this run should ask ONCVPSP to write.
#
# ONCVPSP writes exactly one: psfile is a single field on the atom line. So the
# requested format decides, and asking for both is refused in cli_check_spec
# rather than quietly served with one of them.
# ---------------------------------------------------------------------------
# ONCVPSP writes one format per run, chosen by the `psfile` field of the
# pp_out section -- and it accepts three values, not two: the binary's own
# validation message is "psfile must == psp8 or upf or both". `both` is what
# makes --format upf,psp8 mean what it says; without it the second format was
# silently dropped, and the deck was in fact hardcoded to `upf` until the psp8
# path was fixed, so --format psp8 could not work at all.
ib_oncv_psfile() {
    case " ${SPEC[formats]:-upf} " in
        *" psp8 "*)
            case " ${SPEC[formats]:-upf} " in
                *" upf "*) printf 'both
' ;;
                *)         printf 'psp8
' ;;
            esac ;;
        *)  printf 'upf
' ;;
    esac
}


# Copy a deck, forcing the psfile field (row 1, column 6) to the wanted format.
ib_oncv_retarget_psfile() {
    local src=$1 dst=$2 fmt=$3
    awk -v fmt="$fmt" '
        # the first non-comment, non-blank line is the atom line
        !done && !/^[[:space:]]*#/ && NF >= 5 {
            $6 = fmt
            printf "    %-4s %-4s %3s %3s %3s   %s\n", $1, $2, $3, $4, $5, $6
            done = 1; next
        }
        { print }
    ' "$src" > "$dst"
}

# ---------------------------------------------------------------------------
# PseudoForge's own ONCVPSP deck.
#
# This is a *starting point*, not a curated set, and it says so in a comment
# at the top of the file.  The construction:
#   - valence = the shells the element's ground state occupies outermost,
#     plus any semicore shell of the same principal number
#   - rc from the covalent radius, capped to a band that keeps the solver happy
#   - two projectors per channel, the ONCVPSP default that avoids ghosts
#   - qcut and the optimisation basis at the values ONCVPSP's own documentation
#     recommends as a first attempt
# ---------------------------------------------------------------------------
ib_oncv_synthesise() {
    local el=$1 deck=$2
    local z cfg iexc lmax rc rcloc l nc nv
    z=${EL_Z[$el]}
    cfg=${SPEC[config]:-${EL_CONFIG[$el]}}
    iexc=$(ib_oncv_iexc)

    # split the configuration into explicit (n, l, f) rows
    local rows; rows=$(ib_shell_rows "$el" "$cfg") || return 1
    nc=$(printf '%s\n' "$rows" | awk '$4 == "core"    { n++ } END { print n + 0 }')
    nv=$(printf '%s\n' "$rows" | awk '$4 == "valence" { n++ } END { print n + 0 }')
    [ "$nv" -gt 0 ] || { error "$el: could not work out a valence configuration"; return 1; }

    lmax=$(printf '%s\n' "$rows" | awk '$4 == "valence" { if ($2 > m) m = $2 } END { print m + 0 }')
    # ONCVPSP wants a channel for every l up to lmax; one above the highest
    # occupied l gives the scattering states somewhere to go
    [ "$lmax" -lt 2 ] && lmax=$((lmax + 1))
    [ "$lmax" -gt 3 ] && lmax=3

    local xcname
    if ! xcname=$(ib_opium_xc); then
        error "$el: OPIUM has no $(upper "$(xc_generator "${SPEC[xc]}")") functional."
        error "  It offers pzlda, pwlda, pw91gga, pbegga, wcgga, pbesol and hf."
        error "  Use --engine oncvpsp or --engine ld1 for this functional."
        return 1
    fi

    rc=$(ib_rc_from_radius "$el")
    rcloc=$rc

    {
        printf '# Generated by PseudoForge %s.\n' "$PSEUDOFORGE_VERSION"
        printf '# NOT a published parameter set: built from the ground-state\n'
        printf '# configuration of %s with PseudoForge cut-off radii.  Validate it\n' "$el"
        printf '# (ghost check, cutoff scan, transferability) before using it.\n'
        printf '# ATOM AND REFERENCE CONFIGURATION\n'
        printf '# atsym  z    nc  nv  iexc  psfile\n'
        printf '    %-4s %-6s %3s %3s %4s   %s\n' "$el" "$z." "$nc" "$nv" "$iexc" "$(ib_oncv_psfile)"
        printf '#\n# n  l  f\n'
        printf '%s\n' "$rows" | awk '{ printf "    %s  %s  %.2f\n", $1, $2, $3 }'
        printf '#\n# PSEUDOPOTENTIAL AND OPTIMIZATION\n# lmax\n'
        printf '    %s\n' "$lmax"
        printf '#\n# l, rc, ep, ncon, nbas, qcut\n'
        for l in $(seq 0 "$lmax"); do
            # ep=0 means "use the bound eigenvalue for this l".  A channel with
            # no occupied state has no such eigenvalue, and the all-electron
            # solver then fails with a wellstate convergence error, so those
            # channels get a positive reference energy instead -- which is what
            # ONCVPSP's own decks do for empty d and f channels.
            if printf '%s\n' "$rows" | awk -v l="$l" '$2 == l && $3 > 0 && $4 == "valence" { f = 1 } END { exit !f }'; then
                printf '    %s   %5.2f   0.00    5    8    %5.2f\n' "$l" "$rc" 6.0
            else
                printf '    %s   %5.2f   0.10    5    8    %5.2f\n' "$l" "$rc" 6.0
            fi
        done
        printf '#\n# LOCAL POTENTIAL\n# lloc, lpopt, rc(5), dvloc0\n'
        printf '    4    5   %5.2f   0.0\n' "$rcloc"
        printf '#\n# VANDERBILT-KLEINMAN-BYLANDER PROJECTORS\n# l, nproj, debl\n'
        for l in $(seq 0 "$lmax"); do
            printf '    %s    2    1.00\n' "$l"
        done
        printf '#\n# MODEL CORE CHARGE\n# icmod, fcfact\n'
        # icmod selects the model core charge.  icmod=3 is the optimised
        # (Teter) form and takes *two* parameters, fcfact and rcfact; giving it
        # only one is reported as a read error several lines further on.
        if el_wants_nlcc "$el"; then
            printf '    3    5.00    1.30\n'
        else
            printf '    0    0.00\n'
        fi
        printf '#\n# LOG DERIVATIVE ANALYSIS\n# epsh1, epsh2, depsh\n'
        printf '   -2.0  2.0  0.02\n'
        printf '#\n# OUTPUT GRID\n# rlmax, drl\n'
        printf '    6.0  0.01\n'
        printf '#\n# TEST CONFIGURATIONS\n# ncnf\n    0\n'
    } > "$deck"
}

# ---------------------------------------------------------------------------
# ib_shell_rows <element> <config>
#   -> "n l occ core|valence" per shell, in shell order.
#
# The valence set is every shell of the outermost principal number, plus a d or
# f shell one below it when that shell is the chemically active one -- which is
# exactly the semicore question every generator has to answer.
# ---------------------------------------------------------------------------
ib_shell_rows() {
    local el=$1 cfg=$2
    cfg=$(cfg_expand_core "$cfg")
    printf '%s\n' "$cfg" | awk '
        function lof(c) { return (c == "s") ? 0 : (c == "p") ? 1 : (c == "d") ? 2 : 3 }
        {
            nmax = 0
            for (i = 1; i <= NF; i++) {
                tok = $i
                if (tok !~ /^[0-9][spdf]-?[0-9.]+$/) continue
                n = substr(tok, 1, 1) + 0
                l = lof(substr(tok, 2, 1))
                f = substr(tok, 3) + 0
                if (f < 0) f = 0
                k++; N[k] = n; L[k] = l; F[k] = f
                if (n > nmax && f > 0) nmax = n
            }
            for (i = 1; i <= k; i++) {
                v = "core"
                if (N[i] == nmax) v = "valence"
                # a d/f shell just below the outermost s is valence too
                else if (N[i] == nmax - 1 && L[i] >= 2 && F[i] > 0) v = "valence"
                printf "%d %d %g %s\n", N[i], L[i], F[i], v
            }
        }'
}

# A cut-off radius from the covalent radius, in bohr, clamped to a band where
# the norm-conserving construction is numerically well behaved.
ib_rc_from_radius() {
    local el=$1
    local r=${EL_RCOV[$1]:-}
    [ -n "$r" ] && [ "$r" != "-" ] || r=1.30
    awk -v r="$r" -v b="$BOHR_PER_ANGSTROM" 'BEGIN {
        rc = 0.9 * r * b          # a little inside the covalent radius
        if (rc < 1.10) rc = 1.10
        if (rc > 3.00) rc = 3.00
        printf "%.2f\n", rc
    }'
}

# ---------------------------------------------------------------------------
# USPP (Vanderbilt)
#
# Two runs: an all-electron reference, then the pseudopotential itself.  Both
# use the same .adat layout.  Vanderbilt ships decks for a good part of the
# periodic table under Work/<NNN-El>/, and those are the only USPP parameters
# PseudoForge will claim as authoritative.
# ---------------------------------------------------------------------------
ib_build_uspp() {
    local el=$1 outdir=$2
    local root d cand ae ps z tag

    z=$(printf '%03d' "${EL_Z[$el]}")
    root=${USPP_ROOT:-${USPP_SRC_DIR:-$(eng_builddir)/uspp}}

    # Vanderbilt's own deck for this element, if the tree is present.
    cand=""
    # the library's own Work/ tree first (GBRV ships one), then the engine's
    if cand=$(params_find "${SPEC[profile]}" "$el" 2>/dev/null) && [ -n "$cand" ]; then
        cand=${cand%/}
    fi
    # The glob has quoted and unquoted fragments side by side because the
    # directory names come from variables and the wildcard has to stay
    # outside the quotes to expand.  ShellCheck reads `"A"B"C"` and asks if
    # a literal quote was intended; it was not, and the pattern works.
    # shellcheck disable=SC2140
    for d in "$root"/Work/"$z-$el"/*/ "$root"/*/Work/"$z-$el"/*/; do
        [ -n "$cand" ] && break
        [ -d "$d" ] || continue
        # prefer a scalar-relativistic PBE/LDA "vgrp" deck when several exist
        [ -f "$d/$(lower "$el")_ps.adat" ] || [ -f "$d/${el}_ps.adat" ] || continue
        cand=${d%/}
        case $d in *vgrp*) break ;; esac
    done

    if [ -z "$cand" ]; then
        error "$el: USPP ships no input deck for this element, and PseudoForge will not"
        error "  invent ultrasoft parameters -- the augmentation-charge settings are"
        error "  not something to guess at.  Options:"
        error "    - use --engine ld1 --family us  (PSlibrary's RRKJ ultrasoft recipes)"
        error "    - supply a deck with --params <dir> containing ${el}_ps.adat"
        return 1
    fi

    ae=$(ls "$cand"/*_ae_*.adat 2>/dev/null | head -1)
    ps=$(ls "$cand"/*_ps.adat 2>/dev/null | head -1)
    [ -n "$ae" ] && [ -n "$ps" ] || { error "$el: incomplete USPP deck in $cand"; return 1; }

    cp -f "$ae" "$outdir/$el.ae.adat" || return 1
    cp -f "$ps" "$outdir/$el.ps.adat" || return 1

    IB_PROVENANCE=vendor
    IB_SOURCE="USPP $cand"
    # the executor needs both stages; hand back the ps deck and derive the other
    printf '%s\x1f%s\x1f%s\x1f%s\n' "$outdir/$el.ps.adat" "$el" "$IB_PROVENANCE" "$IB_SOURCE"
}

# ---------------------------------------------------------------------------
# fhi98PP
#
# fhipp.x reads two Fortran unit files from its working directory:
#   fort.20  two control lines -- TDOPSP/TNRL, then TSPIN
#   fort.22  the .ini parameter block, with t/h quoted as 't'/'h'
#
# fhi98PP ships a per-element database under bin/Elements/{Ham,TM}; pseudoforge
# uses it and does not second-guess it, beyond the README's own warning that
# these are starting points rather than production settings.
# ---------------------------------------------------------------------------
ib_build_fhi98pp() {
    local el=$1 outdir=$2
    local root scheme ini z

    z=$(printf '%02d' "${EL_Z[$el]}")
    root=${FHI98PP_ROOT:-${FHI98PP_SRC_DIR:-$(eng_builddir)/fhi98pp}}
    scheme=${SPEC[nc_scheme]:-TM}          # TM (Troullier-Martins) or Ham (Hamann)

    ini=""
    local d f
    for d in "$root/bin/Elements/$scheme" "$root"/*/bin/Elements/"$scheme" \
             "${PARAMS_DIR:-}"; do
        [ -n "$d" ] && [ -d "$d" ] || continue
        for f in "$d/$z-$el:tm.ini" "$d/$z-$el:ham.ini" "$d/$z-$el.ini" "$d/$el.ini"; do
            [ -f "$f" ] && { ini=$f; break 2; }
        done
        # the database names files "<ZZ>-<El>:<scheme>.ini"; glob for safety
        f=$(ls "$d/$z-$el:"*.ini 2>/dev/null | head -1)
        [ -n "$f" ] && { ini=$f; break; }
    done

    if [ -z "$ini" ]; then
        error "$el: fhi98PP ships no parameter file for this element under scheme $scheme"
        error "  supply one with --params <dir>, or use --engine ld1 / --engine oncvpsp"
        return 1
    fi

    cp -f "$ini" "$outdir/$el.ini" || return 1

    # fhipp.x takes its switches from fort.20 rather than the command line.
    #   TDOPSP  .t. = build a pseudopotential (rather than only the atom)
    #   TNRL    .t. = non-relativistic;  .f. = scalar-relativistic
    #   TSPIN   .t. = spin-polarised
    local tnrl=.f. tspin=.f.
    [ "$(rel_canon "${SPEC[rel]}")" = nonrel ] && tnrl=.t.
    [ "${SPEC[lsd]:-}" = 1 ] && tspin=.t.
    if [ "$(rel_canon "${SPEC[rel]}")" = full ]; then
        warn "$el: fhi98PP has no fully-relativistic generator; using scalar-relativistic"
    fi
    printf '.t. %s  : TDOPSP TNRL\n%s      : TSPIN\n' "$tnrl" "$tspin" > "$outdir/$el.fort20"

    IB_PROVENANCE=vendor
    IB_SOURCE="fhi98PP $ini"
    printf '%s\x1f%s\x1f%s\x1f%s\n' "$outdir/$el.ini" "$el" "$IB_PROVENANCE" "$IB_SOURCE"
}

# OPIUM names its functionals explicitly -- its own error message lists
# pzlda, pwlda, pw91gga, pbegga, wcgga, pbesol and hf.  Writing a bare "gga"
# would leave OPIUM to choose one, so someone asking for PBEsol could quietly
# receive PBE.  Anything outside that list is reported, never substituted.
ib_opium_xc() {
    case $(xc_generator "${SPEC[xc]}") in
        pz|vwn|vwn-rpa) printf 'pzlda\n' ;;
        pw)             printf 'pwlda\n' ;;
        pw91)           printf 'pw91gga\n' ;;
        pbe)            printf 'pbegga\n' ;;
        pbesol)         printf 'pbesol\n' ;;
        wc)             printf 'wcgga\n' ;;
        *)              return 1 ;;
    esac
}

ib_opium_rel() {
    case $(rel_canon "${SPEC[rel]}") in
        nonrel) printf 'nrl\n' ;;
        full)   printf 'frl\n' ;;
        *)      printf 'srl\n' ;;
    esac
}

# A vendor deck from OPIUM's own test tree, if it covers this element.
ib_opium_find_deck() {
    local el=$1 root f
    # 1. recovered from a published OPIUM-generated file
    if f=$(params_find "${SPEC[profile]}" "$el" 2>/dev/null) && [ -n "$f" ]; then
        case $f in *.param) printf 'library\t%s\n' "$f"; return 0 ;; esac
    fi
    # 2. shipped with OPIUM itself
    root=${OPIUM_ROOT:-${OPIUM_SRC_DIR:-$(eng_builddir)/opium}}
    for d in "$root" "$root"/*/; do
        [ -d "$d/tests/$el" ] || continue
        # prefer GGA or LDA: the Hartree-Fock path segfaults in this build
        for sub in GGA LDA PBE HF; do
            f=$(ls "$d/tests/$el/$sub/references/"*.param 2>/dev/null | head -1)
            [ -n "$f" ] && { printf 'vendor\t%s\n' "$f"; return 0; }
        done
        f=$(find "$d/tests/$el" -name '*.param' 2>/dev/null | head -1)
        [ -n "$f" ] && { printf 'vendor\t%s\n' "$f"; return 0; }
    done
    return 1
}

ib_build_opium() {
    local el=$1 outdir=$2
    local kind src deck

    deck=$outdir/$(lower "$el").param

    if IFS=$'\t' read -r kind src < <(ib_opium_find_deck "$el"); then
        # Reuse the published deck, retargeting only the exchange-correlation
        # and relativity sections -- those are the run's choice, everything
        # else is the library's.
        ib_opium_retarget "$src" "$deck" || return 1
        IB_PROVENANCE=$kind
        IB_SOURCE=$src
    else
        ib_opium_synthesise "$el" "$deck" || return 1
        IB_PROVENANCE=pseudoforge
        IB_SOURCE="PseudoForge construction from the ground-state configuration"
    fi
    printf '%s%s%s%s
' "$deck" "$(lower "$el")" "$IB_PROVENANCE" "$IB_SOURCE"
}

# ---------------------------------------------------------------------------
# ADPACK.
#
# Like fhi98PP, ADPACK ships a per-element parameter database -- 29 decks under
# work/ -- and those are the author's radii and reference configurations, not
# ours.  So this reuses a published deck and retargets only what the run chose:
# the functional and the relativistic solver.  Everything that makes the deck
# ADPACK's is left alone.
#
# There is no synthesised fallback.  ADPACK's parameters are not derivable from
# the ground-state configuration the way a Troullier-Martins radius is: the
# deck also fixes the pseudization scheme, the local channel and a set of
# per-channel radii that were chosen by hand.  Inventing them and shipping the
# result as an ADPACK pseudopotential is exactly what this tool does not do.
# ---------------------------------------------------------------------------
ib_adpack_deck() {
    local el=$1 d=$PF_DATA/params/adpack
    [ -f "$d/${el}_VPS.inp" ] && { printf '%s\n' "$d/${el}_VPS.inp"; return 0; }
    return 1
}

ib_adpack_xc() {
    case $(xc_generator "${SPEC[xc]}") in
        pz|lda|pw|vwn) printf 'LDA\n' ;;
        pbe|pbesol|revpbe|blyp|bp|pw91|wc) printf 'GGA\n' ;;
        *) return 1 ;;
    esac
}


ib_build_adpack() {
    local el=$1 outdir=$2 src deck xc eq deck_rel

    if ! src=$(ib_adpack_deck "$el"); then
        IB_MESSAGE="ADPACK ships no deck for $el (it covers 29 elements: $(ls "$PF_DATA/params/adpack"/*_VPS.inp 2>/dev/null | sed 's|.*/||; s/_VPS.inp//' | tr '\n' ' '))"
        return 1
    fi
    if ! xc=$(ib_adpack_xc); then
        IB_MESSAGE="ADPACK offers LDA and GGA only; '$(xc_generator "${SPEC[xc]}")' is not among them"
        return 1
    fi
    # Relativity is NOT retargeted, and that is deliberate.  eq.type is
    # coupled to the shape of other blocks in the same deck: with "dirac" the
    # <log.deri.R> table carries two values per channel, one for each
    # j = l +/- 1/2.  Rewriting eq.type alone leaves that table the wrong
    # shape and ADPACK stops with "Format error for log.deri.R" -- pointing at
    # a block nobody touched.  The deck is used with its own solver setting,
    # and a mismatch with the run is reported instead.
    eq=$(awk '/^[[:space:]]*eq\.type/ { print $2; exit }' "$src")
    case $eq in
        dirac)  deck_rel=full ;;
        sdirac) deck_rel=scalar ;;
        sch)    deck_rel=nonrel ;;
        *)      deck_rel=$eq ;;
    esac
    if [ "$deck_rel" != "$(rel_canon "${SPEC[rel]}")" ]; then
        warn "$el: ADPACK ships this deck as $deck_rel ($eq); it is used as published."
        warn "  Its log-derivative and projector blocks are shaped for that solver."
    fi

    deck=$outdir/$el.adpack.inp
    mkdir -p "$outdir" || return 1
    # Only the functional is retargeted: LDA and GGA are scalar keywords with
    # no structural coupling.  System.Name is left alone because ADPACK
    # derives its output file names from it.
    awk -v xc="$xc" '
        /^[[:space:]]*xc\.type/ { printf "xc.type               %s            # set by PseudoForge\n", xc; next }
        { print }
    ' "$src" > "$deck" || return 1

    IB_PROVENANCE=library
    IB_SOURCE=$src
    printf '%s\x1f%s\x1f%s\x1f%s\n' "$deck" "$el" "$IB_PROVENANCE" "$IB_SOURCE"
}

# ---------------------------------------------------------------------------
# gth -- there is no deck to write, only one to point at.
#
# The other builders synthesise a namelist.  GTH cannot be synthesised: the
# whole content of a GTH pseudopotential is a coefficient table someone fitted,
# and the fit needs a published all-electron reference configuration, confining
# radius and weight set to be meaningful.  Inventing those would produce a file
# that looks like a GTH potential and is not one.  So this locates published
# inputs and refuses when there are none, rather than falling back to a
# PseudoForge construction the way the norm-conserving builders do.
# ---------------------------------------------------------------------------
ib_build_gth() {
    local el=$1 outdir=$2 kw inputs tbl deck expected

    if ! kw=$(gth_xc_keyword "${SPEC[xc]}"); then
        IB_MESSAGE="GTH has no table for $(upper "$(xc_qe_string "${SPEC[xc]}")") (it covers pade, pbe, pbesol, blyp, bp, olyp, hcth120, hcth407)"
        return 1
    fi

    expected=$(exec_upf_name "$el"); expected=${expected%.UPF}.gth

    if [ "${GTH_REFIT:-0}" = 1 ]; then
        if ! inputs=$(gth_inputs "${SPEC[xc]}" "$el" "${SPEC[variant]:-}"); then
            IB_MESSAGE="no published GTH generation inputs for $el with $kw"
            return 1
        fi
        # Copy the input set into the project so the run is reproducible from
        # what it kept, not from what happened to be bundled at the time.
        deck=$outdir/$el.gth-inputs
        mkdir -p "$deck" || return 1
        cp -r "$inputs"/. "$deck"/ 2>/dev/null || return 1
        # The starting parameters are the library's, but the coefficients that
        # come out of the fit are this tool's, and the PARAMS column describes
        # the file that was produced rather than what it was seeded from.
        IB_PROVENANCE=pseudoforge
        IB_SOURCE="refit from $inputs"
    else
        if ! tbl=$(gth_table cp2k "${SPEC[xc]}" "$el" "${SPEC[variant]:-}"); then
            IB_MESSAGE="no published GTH table for $el with $kw"
            return 1
        fi
        deck=$outdir/$el.gth-source
        cp -f "$tbl" "$deck" || return 1
        IB_PROVENANCE=library
        IB_SOURCE=$tbl
    fi
    printf '%s\x1f%s\x1f%s\x1f%s\n' "$deck" "$expected" "$IB_PROVENANCE" "$IB_SOURCE"
}

# ---------------------------------------------------------------------------
# AtomPAW.
#
# The deck is not a namelist -- it is an ordered answer sheet to a fixed
# interview, and the number of answers depends on the element's shell
# structure.  Getting the count wrong does not produce an error: atompaw reads
# the next line along as the answer to a different question, and writes a PAW
# data set built from the wrong radii.  So the shell table is computed once and
# every section is written from it.
#
# Layout, with the Li and F examples in the distribution as the reference:
#
#   El Z
#   <XC> loggridv4 2001
#   ns np nd nf 0 0          highest n present for each l (0 = that l absent)
#   n l occ                  each valence shell, one per line
#   0 0 0                    end of the valence list
#   c|v                      one per shell, in l-major then n order
#   lmax                     highest l to build projectors for
#   rc                       matching radius
#   n|y ...                  one extra-projector question per l, 0..lmax
#   VANDERBILT
#   lmax 0
#   rc                       one per projector
#   ABINITOUT / XMLOUT / PWSCFOUT ...
#   END
# ---------------------------------------------------------------------------

# AtomPAW's spelling of a functional.  It has no libxc in this build, so the
# list is short and anything outside it has to be refused rather than mapped to
# a neighbour: a PAW data set carries its functional in the file, and handing
# back LDA under a PBE name is exactly the substitution this tool refuses to
# make elsewhere.
ib_atompaw_xc() {
    # AtomPAW is the one engine here that genuinely makes meta-GGA.  It carries
    # its own r2SCAN implementation (src/excor.F90, r2scanmod) rather than
    # relying on libxc for it, and the two keywords differ only in the
    # regularisation parameter eta.  Verified by generating Li: the log says
    # "R2SCAN MGGA with eta=0.001" and "mGGA kinetic energy functional : YES",
    # and the SCF converges to 4e-13.
    #
    # Note what it does NOT write: UPF.  A meta-GGA run produces PAW-XML and
    # ABINIT only.  That is a property of AtomPAW, not a gap here, and the
    # caller is told rather than handed a UPF that is secretly PBE.
    #
    # The unqualified name maps to eta=0.001, the tighter of the two.
    case $(xc_generator "${SPEC[xc]}") in
        pz|lda)   printf 'LDA-PW\n' ;;
        pw)       printf 'LDA-PW\n' ;;
        pbe)      printf 'GGA-PBE\n' ;;
        pbesol)   printf 'GGA-PBESOL\n' ;;
        r2scan)   printf 'MGGA-R2SCAN-001\n' ;;
        r2scan-01) printf 'MGGA-R2SCAN-01\n' ;;
        *) return 1 ;;
    esac
}

# Scalar-relativistic is the default; atompaw spells the other two out.
ib_atompaw_rel() {
    case $(rel_canon "${SPEC[rel]:-scalar}") in
        full)   printf 'diracrelativistic\n' ;;
        nonrel) printf 'nonrelativistic\n' ;;
        *)      printf 'scalarrelativistic\n' ;;
    esac
}

# ---------------------------------------------------------------------------
# ib_build_atompaw <element> <outdir>
# ---------------------------------------------------------------------------
ib_build_atompaw() {
    local el=$1 outdir=$2
    local deck z rows xc rel maxn nsh rc_val lmax upf

    if ! xc=$(ib_atompaw_xc); then
        IB_MESSAGE="AtomPAW in this build offers LDA-PW, GGA-PBE and GGA-PBESOL; '$(xc_generator "${SPEC[xc]}")' is not among them"
        return 1
    fi
    rel=$(ib_atompaw_rel)
    z=${EL_Z[$el]}
    deck=$outdir/$el.atompaw.input
    upf=$(exec_upf_name "$el")

    rows=$(ib_shell_rows "$el" "${SPEC[config]:-${EL_CONFIG[$el]}}") || return 1
    [ -n "$rows" ] || { IB_MESSAGE="$el: no shell table"; return 1; }

    # Highest n present for each l.  atompaw wants a zero where an l is absent,
    # and counts the shells it must ask about from these four numbers.
    maxn=$(printf '%s\n' "$rows" | awk '
        { if ($1 + 0 > m[$2 + 0]) m[$2 + 0] = $1 + 0 }
        END { printf "%d %d %d %d 0 0\n", m[0], m[1], m[2], m[3] }')

    rc_val=$(ib_atompaw_rc "$el")
    lmax=$(printf '%s\n' "$rows" | awk '$4 == "valence" { if ($2 + 0 > m) m = $2 + 0 } END { print m + 0 }')

    mkdir -p "$outdir" || return 1
    {
        printf '%s %s\n' "$el" "$z"
        printf '%s %s loggridv4 2001\n' "$xc" "$rel"
        printf '%s\n' "$maxn"
        # the valence shells, then the terminator
        printf '%s\n' "$rows" | awk '$4 == "valence" { printf "%d %d %g\n", $1, $2, $3 }'
        printf '0 0 0\n'
        # one c/v marker per shell, l-major: all s, then all p, then d, then f
        ib_atompaw_markers "$rows" "$maxn"
        # ---- projectors ----------------------------------------------
        # Two rules, both learned by sweeping the periodic table rather than
        # reasoned from the manual.
        #
        # A channel that already holds a valence shell must NOT be given an
        # extra projector.  Adding one at a fixed reference energy produces a
        # basis function nearly identical to the one already there; the
        # overlap matrix comes out singular and atompaw stops with "failure of
        # ovlp diagonalization".  Calcium showed it plainly -- two identical
        # rows in the printed overlap.  Topping every channel up to two took a
        # sweep that passed 21 of 22 elements down to 10 of 47.
        #
        # But a basis of a single function is also not enough: sodium has only
        # 3s, atompaw builds one projector, and the overlap operator comes out
        # with a negative eigenvalue ("your PAW basis is incomplete").  So when
        # the valence has just one shell, an empty p channel is added to
        # scatter into -- which is what the Li example in the distribution does.
        local nval l lmax_p
        nval=$(printf '%s\n' "$rows" | awk '$4 == "valence"' | grep -c .)
        if [ "$nval" -le 1 ]; then lmax_p=1; else lmax_p=$lmax; fi

        printf '%s\n' "$lmax_p"
        printf '%s\n' "$rc_val"

        local nval_l extra nbasis=0 k
        for l in $(seq 0 "$lmax_p"); do
            nval_l=$(printf '%s\n' "$rows" | awk -v L="$l" '$4 == "valence" && $2 + 0 == L' | grep -c .)
            # only an empty channel earns an extra projector
            if [ "$nval_l" -eq 0 ]; then extra=1; else extra=0; fi
            k=0
            while [ "$k" -lt "$extra" ]; do
                printf 'y\n%s\n' "${ATOMPAW_REF_ENERGY:-0.0}"
                k=$((k + 1))
            done
            printf 'n\n'
            nbasis=$(( nbasis + nval_l + extra ))
        done

        printf 'VANDERBILT Besselshape\n'
        # The l channel the local potential comes from: one above the highest
        # projector l.  The examples all do this -- Li and F stop at l=1 and
        # write 2, Au stops at l=2 and writes 3.
        printf '%s 0\n' "$((lmax_p + 1))"
        # One radius per basis function, and the count has to be exact.
        # atompaw does not check it: one too many is read as the answer to the
        # next question -- the output-format menu -- and the run dies with
        # "Option not recognized 1.78".  One too few eats "ABINITOUT".
        local i=0
        while [ "$i" -lt "$nbasis" ]; do printf '%s\n' "$rc_val"; i=$((i + 1)); done
        printf 'ABINITOUT\ndefault\n'
        printf 'XMLOUT\ndefault\n'
        printf 'PWSCFOUT\n'
        printf 'UPFDX  0.008d0   UPFXMIN   -7.d0     UPFZMESH %s.d0\n' "$z"
        printf 'END\n'
    } > "$deck"

    IB_PROVENANCE=pseudoforge
    IB_SOURCE="PseudoForge construction from the ground-state configuration"
    printf '%s\x1f%s\x1f%s\x1f%s\n' "$deck" "$upf" "$IB_PROVENANCE" "$IB_SOURCE"
}

# One c/v marker per shell, ordered the way atompaw reads them: every s shell
# from 1s up, then every p from 2p, then d from 3d, then f from 4f.
ib_atompaw_markers() {
    local rows=$1 maxn=$2
    printf '%s\n' "$rows" | awk -v maxn="$maxn" '
        { v[$1 "," $2] = $4 }
        END {
            split(maxn, m, " ")
            for (l = 0; l <= 3; l++) {
                top = m[l + 1] + 0
                if (top == 0) continue
                for (n = l + 1; n <= top; n++)
                    print (v[n "," l] == "valence") ? "v" : "c"
            }
        }'
}

# The matching radius.  Inside the covalent radius, as for the other engines,
# and clamped so a very small or very large atom still lands somewhere atompaw
# can solve.
ib_atompaw_rc() {
    local el=$1
    local r=${EL_RCOV[$1]:-}
    [ -n "$r" ] && [ "$r" != - ] || { printf '2.0\n'; return; }
    awk -v r="$r" -v b=1.8897259886 'BEGIN {
        rc = 0.85 * r * b
        if (rc < 1.20) rc = 1.20
        if (rc > 2.80) rc = 2.80
        printf "%.2f\n", rc
    }'
}

# ---------------------------------------------------------------------------
# APE.
#
# The friendliest deck of any engine here: named keys and named blocks, no
# positional answer sheet.  Two things still have to be right.
#
# The file must be called inp.ape and sit in the working directory.  APE takes
# no command-line argument and reads nothing from standard input; given a file
# name as an argument it silently parses nothing, writes a parser.log in which
# every value reads "# default", and then stops on "Wrong or absent value for
# the nuclear charge" -- an error that points at the input rather than at the
# fact that the input was never opened.
#
# And functionals are named by their libxc identifier, not chosen from a table.
# That is APE's real advantage and it is why the mapping below is explicit
# rather than clever: an unrecognised name would otherwise reach libxc and come
# back as something else.
# ---------------------------------------------------------------------------

# libxc names for the functionals PseudoForge knows.  Echoes "<exchange> <correlation>".
ib_ape_xc() {
    case $(xc_generator "${SPEC[xc]}") in
        pz)      printf 'lda_x lda_c_pz\n' ;;
        pw|lda)  printf 'lda_x lda_c_pw\n' ;;
        pbe)     printf 'gga_x_pbe gga_c_pbe\n' ;;
        pbesol)  printf 'gga_x_pbe_sol gga_c_pbe_sol\n' ;;
        blyp)    printf 'gga_x_b88 gga_c_lyp\n' ;;
        bp)      printf 'gga_x_b88 gga_c_p86\n' ;;
        revpbe)  printf 'gga_x_pbe_r gga_c_pbe\n' ;;
        pw91)    printf 'gga_x_pw91 gga_c_pw91\n' ;;
        wc)      printf 'gga_x_wc gga_c_pbe\n' ;;
        *) return 1 ;;
    esac
}

# APE solves the Schrodinger equation by default and the Dirac equation for a
# fully relativistic run; there is no separate scalar-relativistic switch, so
# scalar maps to the scalar-relativistic Schrodinger form APE calls "scalar_rel".
ib_ape_waveeq() {
    case $(rel_canon "${SPEC[rel]:-scalar}") in
        full)   printf 'dirac\n' ;;
        nonrel) printf 'schrodinger\n' ;;
        *)      printf 'scalar_rel\n' ;;
    esac
}

# ---------------------------------------------------------------------------
# ib_build_ape <element> <outdir>
# ---------------------------------------------------------------------------
ib_build_ape() {
    local el=$1 outdir=$2
    local deck z rows xc core rc_val upf

    if ! xc=$(ib_ape_xc); then
        IB_MESSAGE="no libxc mapping for '$(xc_generator "${SPEC[xc]}")' in the APE builder"
        return 1
    fi
    z=${EL_Z[$el]}
    rows=$(ib_ape_shells "$el") || return 1
    [ -n "$rows" ] || { IB_MESSAGE="$el: no shell table"; return 1; }

    # A note on scope, established by sweeping 28 elements: 21 generate
    # cleanly and 7 fail -- Ti, Fe, Cu, Zn, Br, Ag and Au, every one of them
    # with an open or semicore d shell being pseudised.  Bromine dies inside
    # GSL's multiroot solver; iron aborts outright, at every matching radius
    # tried.  That is a crash in this build of APE rather than a parameter to
    # tune, and tightening the d radius to the usual 0.6 of the s/p value made
    # it worse, not better (21 down to 17).
    #
    # These elements are NOT refused up front.  An earlier version did that and
    # it was wrong: the guard also caught gallium, germanium, selenium and tin,
    # which carry a filled d shell and generate perfectly well.  A refusal that
    # broad costs more than the failures it prevents, and APE's own error is
    # clear when it does fail.  Use --engine oncvpsp, ld1 or opium for the
    # elements it cannot do.

    core=$(el_core "${SPEC[config]:-${EL_CONFIG[$el]}}" 2>/dev/null)
    rc_val=$(ib_ape_rc "$el")
    upf=$(exec_upf_name "$el")

    # APE writes into the working directory under a name it chooses, so the
    # deck goes to the project's inputs and the executor copies it in as
    # inp.ape.
    deck=$outdir/$el.inp.ape
    mkdir -p "$outdir" || return 1
    {
        printf 'Title = "%s"\n' "$el"
        printf 'CalculationMode = ae + pp\n'
        printf 'Verbose = 30\n'
        printf 'WaveEquation = %s\n' "$(ib_ape_waveeq)"
        printf 'SpinMode = unpolarized\n\n'
        printf '%%XCFunctionals\n %s\n %s\n%%\n\n' "${xc%% *}" "${xc##* }"
        printf 'NuclearCharge = %s\n\n' "$z"
        printf '%%Orbitals\n'
        [ -n "$core" ] && printf '"%s"\n' "$core"
        # Every shell ib_ape_shells returns, including an empty one it added to
        # close an angular-momentum gap -- see that function for why both the
        # "no empty shells" and the "no gaps" rules have to hold at once.
        printf '%s\n' "$rows" | awk '{ printf "  %d  |  %d  |  %g\n", $1, $2, $3 }'
        printf '%%\n\n'
        printf '%%PPComponents\n'
        printf '%s\n' "$rows" | while read -r n l occ; do
            [ -n "$l" ] || continue
            printf '  %d  |  %d  |  %s | tm
' "$n" "$l" "$(ib_ape_rc_for "$el" "$l")"
        done
        printf '%%\n\n'
        printf 'PPCalculationTolerance = 1e-6\n'
        printf 'EigenSolverTolerance = 1e-8\n'
        printf 'ODEIntTolerance = 1e-12\n'
    } > "$deck"

    IB_PROVENANCE=pseudoforge
    IB_SOURCE="PseudoForge construction from the ground-state configuration"
    printf '%s\x1f%s\x1f%s\x1f%s\n' "$deck" "$upf" "$IB_PROVENANCE" "$IB_SOURCE"
}

# ---------------------------------------------------------------------------
# ib_ape_shells <element>
#
# The valence shells an APE deck should list, as "n l occ" rows.
#
# Two rules, and they pull against each other, which is why this is its own
# function rather than a filter inline.
#
#   1. Do not list empty shells that nothing needs.  APE's own silicon sample
#      lists empty 3d and 4f states; under anything but LDA the SCF drives them
#      unbound and APE stops with "State: 3p is unbound".
#
#   2. But the angular-momentum channels must run 0..lmax with no gap.  A
#      transition metal has occupied s and d and no occupied p, so applying
#      rule 1 alone leaves l = {0, 2}.  APE then aborts inside GSL --
#      cspline_alloc, which needs at least three points -- with SIGABRT and no
#      message of its own.  That was the whole of APE's failure list: Ti, Fe,
#      Cu, Zn, Br, Ag, Au.
#
# So an empty shell is listed exactly when it is needed to close a gap, and
# never otherwise.  Its principal quantum number is the outermost valence n,
# which is what makes it the natural empty partner of the occupied shell at
# that n (4p beside 4s for titanium).
#
# Checked both ways on Ti: without the empty 4p, SIGABRT in cspline_alloc; with
# it, a pseudopotential under both LDA and PBE.
# ---------------------------------------------------------------------------
ib_ape_shells() {
    local el=$1 rows
    rows=$(ib_shell_rows "$el" "${SPEC[config]:-${EL_CONFIG[$el]}}") || return 1
    printf '%s\n' "$rows" | awk '
        $4 == "valence" && $3 + 0 > 0 {
            n[$2] = $1; occ[$2] = $3; have[$2] = 1
            if ($2 + 0 > lmax) lmax = $2 + 0
            if ($1 + 0 > nmax) nmax = $1 + 0
            next
        }
        END {
            for (l = 0; l <= lmax; l++) {
                if (have[l]) printf "%d %d %s\n", n[l], l, occ[l]
                # a gap: list the shell empty so the channel exists, using the
                # outermost valence n
                else         printf "%d %d 0\n", nmax, l
            }
        }'
}

# ---------------------------------------------------------------------------
# Cut-off radii for a PseudoForge-constructed APE deck.
#
# The covalent-radius heuristic -- 0.9 x r_cov, one value for every channel --
# is fine for main-group elements and wrong for transition metals, which was
# APE's entire failure list.  For titanium it gives 2.72 bohr where SG15 uses
# 2.25-2.44, and APE's Troullier-Martins construction aborts inside GSL
# (SIGABRT, exit 134).
#
# Two things were learned by measuring rather than reasoning:
#
#   - Scaling the radius down per angular momentum, on the grounds that a 3d
#     orbital is compact, is wrong.  Across the SG15 decks this tool already
#     bundles, the d/s ratio for Ti, Fe, Cu, Zn, Br, Ag and Au runs 0.89 to
#     1.06 -- essentially one.
#
#   - But a single radius for all channels is also wrong, and not only for
#     metals: SG15's silicon uses rc = 2.38 for s and 3.56 for p.  Collapsing
#     those to one number would have changed the result for elements that
#     already worked.
#
# So each channel gets its own published radius where one exists, and the
# heuristic fills in only where nothing is published.  The deck is still a
# PseudoForge construction and is labelled as one -- the radii are adapted from
# SG15, the rest of the deck is not SG15 -- which is the rule prof_auto_source
# already follows.
# ---------------------------------------------------------------------------

# ib_ape_sg15_deck <element> -- the newest SG15 deck we ship for it, if any.
ib_ape_sg15_deck() {
    ls "$PF_DATA/params/sg15/elements"/*_"$1"/*.dat 2>/dev/null | sort -V | tail -1
}

# ib_ape_rc_l <element> <l> -- published rc for one channel, empty if none.
#
# The block is "l, rc, ep, ncon, nbas, qcut", one line per l in order, ending
# at the next comment line.  Stopping at that comment matters: the LOCAL
# POTENTIAL section right below carries its own "rc(5)" in the same column
# shape, and reading into it returns a radius belonging to a different thing.
ib_ape_rc_l() {
    local el=$1 l=$2 f
    f=$(ib_ape_sg15_deck "$el")
    [ -n "$f" ] || return 1
    awk -v want="$l" '
        /l, rc, ep, ncon, nbas, qcut/ { g = 1; next }
        g && /^[[:space:]]*#/ { exit }
        g && $1 + 0 == want && NF >= 2 { printf "%.2f\n", $2; found = 1; exit }
        END { exit !found }
    ' "$f"
}

# ib_ape_rc <element> -- the fallback, used per channel when nothing is published.
ib_ape_rc() {
    local el=$1
    local r=${EL_RCOV[$1]:-}
    if [ -z "$r" ] || [ "$r" = - ]; then printf '2.0\n'; return 0; fi
    awk -v r="$r" -v b=1.8897259886 '
        BEGIN {
            rc = 0.9 * r * b
            if (rc < 1.10) rc = 1.10
            if (rc > 3.00) rc = 3.00
            printf "%.2f\n", rc
        }'
}

# ib_ape_rc_for <element> <l> -- what the deck should use for this channel.
ib_ape_rc_for() {
    local rc
    rc=$(ib_ape_rc_l "$1" "$2" 2>/dev/null) && [ -n "$rc" ] && { printf '%s\n' "$rc"; return 0; }
    ib_ape_rc "$1"
}

# Copy a deck, replacing the [XC] and [Relativity] sections.
ib_opium_retarget() {
    local src=$1 dst=$2 xc rel
    # Guard here as well as in the synthesised path: an unsupported functional
    # would otherwise leave the [XC] section blank and OPIUM would fall back to
    # its own default, silently giving the user a different functional.
    if ! xc=$(ib_opium_xc); then
        error "OPIUM has no $(upper "$(xc_generator "${SPEC[xc]}")") functional."
        error "  It offers pzlda, pwlda, pw91gga, pbegga, wcgga, pbesol and hf."
        error "  Use --engine oncvpsp or --engine ld1 for this functional."
        return 1
    fi
    rel=$(ib_opium_rel)
    awk -v xc="$xc" -v rel="$rel" '
        /^\[XC\]/         { print; skip = 1; print xc;  next }
        /^\[Relativity\]/ { print; skip = 1; print rel; seen_rel = 1; next }
        /^\[/             { skip = 0 }
        skip && NF        { next }
        skip && !NF       { skip = 0 }
        { print }
        END { if (!seen_rel) { printf "\n[Relativity]\n%s\n", rel } }
    ' "$src" > "$dst"
    # Hartree-Fock segfaults in this build; never carry it over silently
    if grep -qiE '^[[:space:]]*hf[[:space:]]*$' "$dst"; then
        sed -i 's/^[[:space:]]*hf[[:space:]]*$/gga/I' "$dst"
        warn "$(basename "$dst"): the source deck used Hartree-Fock, which crashes this OPIUM build; switched to GGA"
    fi
    [ -s "$dst" ]
}

# ---------------------------------------------------------------------------
# PseudoForge's own OPIUM deck.  A starting point, labelled as such in the file.
# ---------------------------------------------------------------------------
ib_opium_synthesise() {
    local el=$1 deck=$2
    local rows norb nval rc qc lmax
    rows=$(ib_shell_rows "$el" "${SPEC[config]:-${EL_CONFIG[$el]}}") || return 1
    [ -n "$rows" ] || return 1

    norb=$(printf '%s\n' "$rows" | grep -c .)
    nval=$(printf '%s\n' "$rows" | awk '$4 == "valence"' | grep -c .)
    [ "$nval" -gt 0 ] || { error "$el: no valence shells identified"; return 1; }

    rc=$(ib_rc_from_radius "$el")
    # OPIUM's optimisation cut-off wavevector; 7 Ry^1/2 is its own documented
    # starting value and is what the shipped decks use for second-row elements.
    qc=7.07

    {
        printf '# Generated by %s %s.\n' "$PSEUDOFORGE_NAME" "$PSEUDOFORGE_VERSION"
        printf '# NOT a published parameter set: built from the ground-state\n'
        printf '# configuration of %s with PseudoForge cut-off radii.  Validate it\n' "$el"
        printf '# before relying on it.\n\n'
        printf '[Atom]\n%s\n%s\n' "$el" "$norb"
        printf '%s\n' "$rows" | awk '{ printf "%d%d0   %.2f   -\n", $1, $2, $3 }'
        printf '\n[Pseudo]\n%s' "$nval"
        local i=0
        while [ "$i" -lt "$nval" ]; do printf ' %s' "$rc"; i=$((i + 1)); done
        printf '\nopt\n'
        printf '\n[Optinfo]\n'
        i=0
        while [ "$i" -lt "$nval" ]; do printf '%s  10\n' "$qc"; i=$((i + 1)); done
        printf '\n[XC]\n%s\n' "$(ib_opium_xc)"
        printf '\n[Relativity]\n%s\n' "$(ib_opium_rel)"
        # Two ionised configurations, so that `opium tc` has something to
        # solve.  Without them the transferability check can only re-report
        # the configuration the pseudopotential was fitted to, which measures
        # nothing.  Taking a quarter and then half an electron off the
        # outermost shell is the standard probe and is what OPIUM's own decks
        # do; it affects only `tc`, never the pseudopotential itself, which is
        # built from the [Atom] block alone.
        printf '\n[Configs]\n2\n'
        local shift
        for shift in 0.25 0.50; do
            printf '#\n'
            printf '%s\n' "$rows" | awk -v s="$shift" '
                $4 == "valence" { k++; N[k] = $1; L[k] = $2; F[k] = $3 }
                END {
                    F[k] = F[k] - s
                    if (F[k] < 0) F[k] = 0
                    for (i = 1; i <= k; i++) printf "%d%d0  %.2f  -\n", N[i], L[i], F[i]
                }'
        done
    } > "$deck"
    [ -s "$deck" ]
}

# ---------------------------------------------------------------------------
# ib_ld1_adopt <deck> <element> <outdir>
#
# Take a published ld1.x deck and run it as-is, changing only what this run
# actually chose: the functional, the relativity, and the output file name.
# Everything that makes the deck that library's -- radii, projectors, augmentation
# settings -- is left exactly as published.
# ---------------------------------------------------------------------------
ib_ld1_adopt() {
    local src=$1 el=$2 outdir=$3
    local deck upf fct gfun nrel

    fct=$(xc_tag "${SPEC[xc]}" "${SPEC[rel]}")
    gfun=$(xc_qe_string "${SPEC[xc]}")
    nrel=$(rel_code "${SPEC[rel]}")

    upf="$el.$fct-$(recipe_flavour "${SPEC[family]}")_${SPEC[profile]}"
    [ -n "${SPEC[tag_suffix]:-}" ] && upf="$upf${SPEC[tag_suffix]}"
    deck=$outdir/$upf.in

    mkdir -p "$outdir" || return 1
    cp -f "$src" "$deck" || return 1

    nml_set "$deck" input  dft   "'$gfun'"
    nml_set "$deck" input  rel   "$nrel"
    nml_set "$deck" inputp file_pseudopw "'$upf.UPF'"
    recipe_apply "$deck" "$el" || return 1

    IB_PROVENANCE=library
    IB_SOURCE=$src
    printf '%s\x1f%s\x1f%s\x1f%s\n' "$deck" "$upf.UPF" "$IB_PROVENANCE" "$IB_SOURCE"
}

# ---------------------------------------------------------------------------
# --rcut-scale for the non-ld1 engines.
#
# Until this existed the flag was applied in exactly one place -- recipe.sh,
# on ld1's card block -- and every other engine ignored it. Worse than
# ignored: recipe_auto_suffix still added "-rc1p2" to the file name, so
# oncvpsp, opium, uspp and atompaw each produced a file *named* as having
# its radii scaled by 1.2 that was byte-for-byte the unscaled construction.
# Measured by building Si with and without the flag and diffing the decks.
#
# Each engine below is scaled only where its deck labels the radius field
# unambiguously. Where it does not, the flag is refused before anything runs,
# with the reason -- never accepted and dropped.
# ---------------------------------------------------------------------------

# ib_rc_scalable <engine> -- succeeds when --rcut-scale is implemented.
ib_rc_scalable() {
    case $1 in
        ld1|oncvpsp|opium|ape) return 0 ;;
        *) return 1 ;;
    esac
}

# ib_rc_refusal <engine> -- why it is not.
ib_rc_refusal() {
    case $1 in
        gth)     printf 'GTH copies published analytic coefficients; there are no cut-off radii to scale.\n' ;;
        adpack)  printf 'ADPACK runs its published decks unmodified; changing their radii would issue a new construction under ADPACK'"'"'s name.\n' ;;
        uspp)    printf 'not implemented for USPP: its deck carries radii for each beta, for the augmentation (rinner) and for the local channel, and scaling them together has not been verified here.\n' ;;
        atompaw) printf 'not implemented for AtomPAW: r_paw and the shape-function and projector radii are coupled, and scaling them together has not been verified here.\n' ;;
        fhi98pp) printf 'not implemented for fhi98PP: its radii sit in a positional control file whose layout has not been verified field by field here.\n' ;;
        *)       printf 'not implemented for this engine.\n' ;;
    esac
}

# ib_scale_rc <engine> <deck> <factor> -- scale the radii in place.
#
# Only the fields each engine's own deck labels as radii are touched:
#   oncvpsp  column 2 under "# l, rc, ep, ncon, nbas, qcut", and rc(5), the
#            third field under "# lloc, lpopt, rc(5), dvloc0";
#   opium    the radii on the line after [Pseudo] -- the first field there is
#            the channel count, not a radius;
#   ape      the third |-separated column of %PPComponents.
# A deck that does not contain the expected block is an error, not a no-op:
# silently leaving it unscaled is the bug this replaces.
ib_scale_rc() {
    local eng=$1 deck=$2 f=$3 tmp n
    awk -v f="$f" 'BEGIN { exit !(f + 0 > 0) }' || { error "--rcut-scale must be a positive number, not '$f'"; return 1; }
    tmp=$deck.rcs.$$
    case $eng in
        oncvpsp)
            awk -v f="$f" '
                /^# *l, *rc, *ep/            { blk = 1; print; next }
                /^# *lloc, *lpopt, *rc\(5\)/ { loc = 1; print; next }
                /^# *rlmax/                  { rl = 1; print; next }
                blk && /^#/                  { blk = 0 }
                blk && NF >= 6 {
                    $2 = sprintf("%.4f", $2 * f); n++
                    if ($2 + 0 > rcmax) rcmax = $2 + 0
                    printf "    %s\n", $0; next
                }
                loc && NF >= 4 {
                    $3 = sprintf("%.4f", $3 * f); n++; loc = 0
                    printf "    %s\n", $0; next
                }
                rl && NF >= 2 { rlmax = $1 + 0; rl = 0 }
                { print }
                END {
                    if (n < 2) exit 2
                    # ONCVPSP tabulates the pseudopotential out to rlmax; a
                    # radius beyond it is not a softer construction, it is a
                    # broken one. Refused, not "fixed" by moving rlmax.
                    if (rlmax > 0 && rcmax >= rlmax) exit 3
                }' "$deck" > "$tmp"
            ;;
        opium)
            awk -v f="$f" '
                tolower($0) ~ /^\[pseudo\]/ { p = 1; print; next }
                p == 1 && NF >= 2 {
                    for (i = 2; i <= NF; i++) $i = sprintf("%.4f", $i * f)
                    n = NF - 1; p = 2; print; next
                }
                { print }
                END { if (n < 1) exit 2 }' "$deck" > "$tmp"
            ;;
        ape)
            awk -v f="$f" '
                /^%PPComponents/ { g = 1; print; next }
                g && /^%/        { g = 0; print; next }
                g && /\|/ {
                    k = split($0, a, "|")
                    a[3] = sprintf(" %.4f ", a[3] * f)
                    out = a[1]; for (i = 2; i <= k; i++) out = out "|" a[i]
                    n++; print out; next
                }
                { print }
                END { if (n < 1) exit 2 }' "$deck" > "$tmp"
            ;;
        *)
            error "--rcut-scale: $(ib_rc_refusal "$eng")"
            return 1 ;;
    esac
    n=$?
    case $n in
        0) mv -f "$tmp" "$deck" ;;
        2) rm -f "$tmp"; error "--rcut-scale: the $eng deck has no radius block where one was expected ($(basename "$deck"))"; return 1 ;;
        3) rm -f "$tmp"; error "--rcut-scale $f puts a radius at or beyond ONCVPSP's output grid (rlmax); use a smaller factor"; return 1 ;;
        *) rm -f "$tmp"; error "--rcut-scale: could not rewrite $(basename "$deck")"; return 1 ;;
    esac
}
