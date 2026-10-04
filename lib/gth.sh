# shellcheck shell=bash
# ---------------------------------------------------------------------------
# gth.sh -- Goedecker-Teter-Hutter pseudopotentials.
#
# GTH is unlike every other engine PseudoForge drives.  The others produce a
# pseudopotential as a table of numbers on a radial grid, megabytes long.  GTH
# produces an *analytic* one: a local part built from an error function and a
# short polynomial, plus Gaussian projectors, with the whole thing specified by
# a handful of coefficients (Goedecker/Teter/Hutter 1996; Hartwigsen/Goedecker/
# Hutter 1998, which extends it to the full periodic table with relativistic
# reference states).  That is why a GTH pseudopotential fits on four lines.
#
# Two consequences shape this file.
#
# First, "generating" a GTH potential can mean two genuinely different things,
# and conflating them would be dishonest:
#
#   published   The coefficients were fitted and published by the CP2K group.
#               Writing them out in CP2K, CPMD or ABINIT layout is a format
#               conversion of somebody else's numbers, exact to the last
#               digit.  This is the default, and the provenance is 'library'.
#
#   refit       atom.x re-solves the all-electron atom and pseudo.x re-runs the
#               simplex fit from the published starting point and weights.  The
#               answer lands near the published one but is not bit-identical --
#               a simplex minimisation is not reproducible to ten digits -- so
#               it is a different pseudopotential and is labelled as one.
#
# Second, there is no UPF here, and pretending otherwise would be worse than
# offering nothing.  The codes that read GTH read the coefficient block; the
# native layouts are the deliverable, not an intermediate.
# ---------------------------------------------------------------------------

# The eight functionals the published GTH tables actually cover.  Anything
# else has to be refused: a GTH fit is functional-specific, and handing back a
# PBE table for a PBEsol request would silently be the wrong physics.
gth_xc_keyword() {
    case $(lower "${1:-}") in
        pz|lda|pade|pade-lda|pz-lda) printf 'pade\n' ;;
        pbe)                         printf 'pbe\n' ;;
        pbesol)                      printf 'pbesol\n' ;;
        blyp)                        printf 'blyp\n' ;;
        bp|b88-p86)                  printf 'bp\n' ;;
        olyp)                        printf 'olyp\n' ;;
        hcth120)                     printf 'hcth120\n' ;;
        hcth407)                     printf 'hcth407\n' ;;
        *) return 1 ;;
    esac
}

gth_data_root() { printf '%s/params/cp2k-gth\n' "$PF_DATA"; }

# ---------------------------------------------------------------------------
# gth_table <layout> <xc> <element> [charge]
#
# Locate a published coefficient file.  Entries are named <El>-q<N>; when no
# charge is asked for, take the smallest valence count, which is the
# conventional default set.
# ---------------------------------------------------------------------------
gth_table() {
    local layout=$1 xc=$2 el=$3 q=${4:-} kw dir f
    kw=$(gth_xc_keyword "$xc") || return 1
    dir=$(gth_data_root)/tables/$layout/$kw
    [ -d "$dir" ] || return 1
    if [ -n "$q" ]; then
        [ -f "$dir/$el-q$q" ] && { printf '%s\n' "$dir/$el-q$q"; return 0; }
        return 1
    fi
    f=$(ls "$dir" 2>/dev/null | awk -v e="$el" -F'-q' '$1==e{print $2"\t"$0}' | sort -n | head -1 | cut -f2)
    [ -n "$f" ] || return 1
    printf '%s\n' "$dir/$f"
}


# ---------------------------------------------------------------------------
# gth_inputs <xc> <element> [charge]
#
# Locate a published *generation* input set -- atom.dat plus the fit's starting
# parameters, weights and free-parameter mask.  These are what make a refit
# defensible rather than invented: the radii, the confining potential and the
# reference configuration all come from the people who published the library.
#
# Echoes the directory holding atom/ and psp_<xc>/.
# ---------------------------------------------------------------------------
gth_inputs() {
    local xc=$1 el=$2 q=${3:-} kw base d
    kw=$(gth_xc_keyword "$xc") || return 1
    base=$(gth_data_root)/generate/$kw/$el
    [ -d "$base" ] || return 1
    # Some elements are stored flat, others under a q<N> subdirectory.
    if [ -d "$base/atom" ]; then printf '%s\n' "$base"; return 0; fi
    if [ -n "$q" ] && [ -d "$base/q$q/atom" ]; then printf '%s\n' "$base/q$q"; return 0; fi
    d=$(ls -d "$base"/q* 2>/dev/null | sed 's/.*\/q//' | sort -n | head -1)
    [ -n "$d" ] && [ -d "$base/q$d/atom" ] && { printf '%s\n' "$base/q$d"; return 0; }
    return 1
}


# ---------------------------------------------------------------------------
# gth_valence_from_atom_dat <atom.dat>
#
# Sum the occupations per angular momentum, which is the "2 4" line CP2K wants
# at the head of a potential block.  Trailing empty channels are dropped, the
# way the published files do it.
# ---------------------------------------------------------------------------
gth_valence_from_atom_dat() {
    # The orbital table always begins on the seventh non-empty line: element,
    # functional, relativity, grid, radii, orbital counts, then the orbitals.
    # Keying off the trailing "number of core and valence orbitals" comment
    # instead looks tidier and silently yields nothing for the many files that
    # do not carry it -- every heavy PADE element, among others.
    awk '
        NF == 0 { next }
        { nline++ }
        nline > 6 && NF >= 3 && $1 ~ /^[0-9]+$/ { occ[$2 + 0] += $3 + 0 }
        END {
            last = 0
            for (l = 0; l <= 3; l++) if (occ[l] > 0) last = l
            line = ""
            for (l = 0; l <= last; l++) line = line sprintf("%5d", occ[l] + 0.0001)
            print line
        }' "$1"
}

# ---------------------------------------------------------------------------
# gth_psp_to_cp2k <psp.par> <element> <label> <valence-line>
#
# Convert a fitted psp.par into the CP2K potential block.
#
# The one piece of real physics here is the spin-orbit average.  psp.par holds
# a fully relativistic fit: for every l > 0 there are two sets of h coefficients,
# one for j = l - 1/2 and one for j = l + 1/2.  CP2K's scalar-relativistic
# format wants the j-degeneracy-weighted average of eq. (16) of Hartwigsen,
# Goedecker and Hutter (1998):
#
#     V_l = ( l * V_{l-1/2} + (l+1) * V_{l+1/2} ) / (2l + 1)
#
# This is checked against the published tables in tests/: applying it to the
# shipped Si psp.par reproduces CP2K's own 2.43127673 exactly.
#
# hsep() is stored as h11, h12, h22, h13, h23, h33 -- upper triangle by column,
# not by row -- while CP2K prints the upper triangle by row.
# ---------------------------------------------------------------------------
gth_psp_to_cp2k() {
    local psp=$1 el=$2 label=$3 valence=$4
    awk -v el="$el" -v label="$label" -v valence="$valence" '
        # GTH coefficients are published to eight decimals, so anything
        # smaller than that is not a coefficient -- it is the residue of the
        # spin-orbit average cancelling, and must not create a projector.
        function nz(x) { return (x < 0 ? -x : x) >= 5e-9 }
        function num(s) { gsub(/[dD]/, "E", s); return s + 0 }
        BEGIN { stage = 0; l = 0 }
        /znuc,zion,rloc,gpot/ {
            rloc = num($3)
            for (i = 1; i <= 4; i++) c[i] = num($(3 + i))
            ncoef = 0
            for (i = 1; i <= 4; i++) if (nz(c[i])) ncoef = i
            stage = 1; next
        }
        stage >= 1 && /lpx/ { lpx = $1 + 0; stage = 2; next }
        # lpx is the file own statement of how many l channels it holds
        # (l = 0..lpx).  Trusting the line count instead is what made Au come
        # out with a spurious third channel: its upstream psp.par carries a
        # Fortran field-overflow-mangled trailing line that still parses as
        # plausible numbers.  lpx says two, and lpx is what pseudo.x reads.
        stage == 2 && /so=\+0\.5/ && l <= lpx {
            rl[l] = num($1)
            for (i = 1; i <= 6; i++) hp[l, i] = num($(1 + i))
            l++; next
        }
        # Each channel has exactly one j = l - 1/2 partner.  The guard on
        # have_minus matters for the same mangled Au line: it too ends in
        # "so=-0.5", and without this it silently overwrites the real
        # coefficients with zeros, which shows up as a plausible-looking but
        # wrong l = 1 block rather than as an error.
        stage == 2 && /so=-0\.5/ && l >= 1 && l <= lpx + 1 && !have_minus[l - 1] {
            m = l - 1
            for (i = 1; i <= 6; i++) hm[m, i] = num($i)
            have_minus[m] = 1
            next
        }
        END {
            nl = l
            printf "%s %s\n", el, label
            print valence
            printf "%15.8f%5d", rloc, ncoef
            for (i = 1; i <= ncoef; i++) printf "%15.8f", c[i]
            printf "\n%5d\n", nl
            for (m = 0; m < nl; m++) {
                for (i = 1; i <= 6; i++) {
                    if (m > 0 && have_minus[m])
                        h[i] = (m * hm[m, i] + (m + 1) * hp[m, i]) / (2 * m + 1)
                    else
                        h[i] = hp[m, i]
                }
                t[1, 1] = h[1]; t[1, 2] = h[2]; t[1, 3] = h[4]
                t[2, 2] = h[3]; t[2, 3] = h[5]
                t[3, 3] = h[6]
                nprj = 0
                for (k = 1; k <= 3; k++) if (nz(t[k, k])) nprj = k
                printf "%15.8f%5d", rl[m], nprj
                for (r = 1; r <= nprj; r++) {
                    # continuation rows line the diagonal up under itself:
                    # 15 for r_l, 5 for nprj, then one 15-wide column per
                    # entry already skipped on this row.
                    if (r > 1) printf "%*s", 20 + 15 * (r - 1), ""
                    for (cc = r; cc <= nprj; cc++) printf "%15.8f", t[r, cc]
                    printf "\n"
                }
                if (nprj == 0) printf "\n"
            }
        }' "$psp"
}

# ---------------------------------------------------------------------------
# gth_run_fit <workdir> <element> <inputs-dir> [cycles]
#
# The two-stage GTH generation.  Both stages need OMP_NUM_THREADS=1: the
# fitting code spin-waits otherwise, the same trap ld1.x falls into here.
# ---------------------------------------------------------------------------
gth_run_fit() {
    local work=$1 el=$2 inputs=$3 cycles=${4:-200} bin dir rc declared blocks

    bin=$(eng_resolve gth) || { error "GTH engine not installed -- run: pseudoforge engines build gth"; return 1; }
    dir=$(dirname "$bin")
    [ -x "$dir/atom.x" ] || { error "GTH: atom.x missing beside pseudo.x"; return 1; }

    # The two stages get separate directories, and that is not tidiness.
    # atom.x writes a starter psp.par of its own next to atom.ae -- all zeros,
    # a template to be filled in.  Run both stages in one directory and that
    # template lands on top of the published starting parameters, so pseudo.x
    # reads zion = 0, refuses to fit, and leaves behind a psp.par that looks
    # like output but is the template.  Keeping them apart is what the
    # published build trees do.
    mkdir -p "$work/atom" "$work/psp" || return 1
    cp "$inputs/atom/atom.dat" "$work/atom/" || return 1
    cp "$inputs"/psp_*/psp.par "$inputs"/psp_*/weights.par "$inputs"/psp_*/FITPAR "$work/psp/" || return 1

    ( cd "$work/atom" && OMP_NUM_THREADS=1 timeout "${GTH_ATOM_TIMEOUT:-600}" "$dir/atom.x" "$el" ) \
        > "$work/atom/atom.log" 2>&1
    rc=$?
    if [ $rc -ne 0 ] || [ ! -s "$work/atom/atom.ae" ]; then
        error "GTH: the all-electron solve failed for $el (see $work/atom/atom.log)"
        return 1
    fi
    # atom.x can stop early and still exit 0, leaving atom.ae shorter than its
    # own header claims; pseudo.x would then die on EOF with a useless message.
    declared=$(awk 'NR==1{print $1}' "$work/atom/atom.ae")
    blocks=$(grep -c 'n l s z eval' "$work/atom/atom.ae")
    if [ "${declared:-0}" != "${blocks:-0}" ]; then
        error "GTH: atom.ae is truncated for $el ($blocks of $declared orbitals)."
        error "  That is the -fno-automatic trap; rebuild with: pseudoforge engines build gth"
        return 1
    fi
    cp "$work/atom/atom.ae" "$work/psp/" || return 1

    ( cd "$work/psp" && OMP_NUM_THREADS=1 timeout "${GTH_FIT_TIMEOUT:-1800}" \
        "$dir/pseudo.x" -orth -c"$cycles" -n400 ) > "$work/psp/fit.log" 2>&1
    rc=$?
    [ $rc -eq 0 ] || { error "GTH: the fit failed for $el (see $work/psp/fit.log)"; return 1; }
    [ -s "$work/psp/psp.par" ] || { error "GTH: no psp.par after the fit"; return 1; }

    # pseudo.x reports a refusal on stdout and still exits 0, leaving the input
    # psp.par in place, so a zero exit status is not on its own evidence of a fit.
    if grep -qiE 'not identical|no fitting|cannot' "$work/psp/fit.log"; then
        error "GTH: pseudo.x declined to fit $el -- $(grep -iE 'not identical|no fitting|cannot' "$work/psp/fit.log" | head -1 | sed 's/^ *//')"
        return 1
    fi
    grep -qi 'penalty' "$work/psp/fit.log" || {
        error "GTH: the fit for $el produced no penalty values, so nothing was minimised"
        return 1
    }
    printf '%s\n' "$work/psp/psp.par"
}

# The fit's final penalty, for the report.  Lower is a closer reproduction of
# the all-electron atom; it is the only quality number this engine emits.
gth_final_penalty() {
    grep -i 'penalty' "$1" 2>/dev/null | tail -1 | awk '{print $NF}'
}

# ---------------------------------------------------------------------------
# gth_validate_block <file>
#
# A GTH file is two hundred bytes, so the generic "too small to be a
# pseudopotential" floor rejects every valid one.  Size is the wrong question
# for an analytic form; structure is the right one, and unlike a radial grid
# this format is small enough to check completely:
#
#   El LABEL
#   <valence occupations, one integer per l>
#   <rloc> <n> <C1..Cn>
#   <number of l channels>
#   <r_l> <nprj> <first row of the h upper triangle>
#   <the remaining nprj-1 rows>                       x number of channels
#
# Every count is checked against the numbers that follow it, which is what
# catches a truncated or half-written file that a byte count waves through.
# ---------------------------------------------------------------------------
gth_validate_block() {
    awk '
        function bad(m) { print "ERROR: " m; errs++ }
        /[Nn][Aa][Nn]|[Ii]nfinity|\*\*\*\*/ { nanline = 1 }
        NF { line[++n] = $0 }
        END {
            errs = 0
            if (nanline) { bad("contains NaN, Infinity or Fortran overflow markers"); exit errs ? 1 : 0 }
            if (n < 4) { bad("only " n " line(s) -- a GTH block needs at least four"); exit 1 }

            split(line[1], a, " ")
            if (a[1] !~ /^[A-Z][a-z]?$/) bad("line 1 does not start with an element symbol")
            if (a[2] == "")              bad("line 1 carries no potential label")

            zv = 0
            nf = split(line[2], v, " ")
            for (i = 1; i <= nf; i++) {
                if (v[i] !~ /^[0-9]+$/) { bad("valence occupations are not integers: " line[2]); break }
                zv += v[i]
            }
            if (zv <= 0) bad("valence charge is zero")

            nf = split(line[3], p, " ")
            if (p[1] + 0 <= 0) bad("local radius is not positive: " p[1])
            nc = p[2] + 0
            if (nf != 2 + nc) bad("line 3 announces " nc " local coefficient(s) but carries " (nf - 2))

            nl = line[4] + 0
            if (nl < 0 || nl > 4) bad("implausible number of projector channels: " line[4])

            r = 5
            for (c = 0; c < nl; c++) {
                if (r > n) { bad("ends after " c " of " nl " channel(s)"); break }
                nf = split(line[r], q, " ")
                if (q[1] + 0 <= 0) bad("channel " c " has a non-positive radius: " q[1])
                nprj = q[2] + 0
                if (nprj < 0 || nprj > 3) { bad("channel " c " claims " nprj " projectors"); break }
                if (nprj > 0 && nf != 2 + nprj)
                    bad("channel " c " announces " nprj " projector(s) but its first row carries " (nf - 2) " coefficient(s)")
                r++
                for (row = 2; row <= nprj; row++) {
                    if (r > n) { bad("channel " c " is truncated"); break }
                    nf = split(line[r], q, " ")
                    if (nf != nprj - row + 1)
                        bad("channel " c " row " row " carries " nf " coefficient(s), expected " (nprj - row + 1))
                    r++
                }
            }
            if (!errs)
                print "NOTE: GTH coefficient block, structure checked; not readable by Quantum ESPRESSO"
            exit errs ? 1 : 0
        }' "$1"
}
