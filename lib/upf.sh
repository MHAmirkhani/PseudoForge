# shellcheck shell=bash
# ---------------------------------------------------------------------------
# upf.sh -- read and sanity-check UPF pseudopotential files.
#
# Handles both formats ld1.x can emit:
#   UPF v1  a text file with a fixed-layout <PP_HEADER> block
#   UPF v2  XML, with the same information as attributes on <PP_HEADER/>
#
# Everything here is read-only and pure text processing: no QE binary needed,
# so imported third-party files (SG15, GBRV, PseudoDojo, ...) go through the
# very same checks as files pseudoforge generated itself.
# ---------------------------------------------------------------------------

# upf_format <file> -> v1 | v2 | unknown
upf_format() {
    local f=$1
    grep -qi '<UPF[[:space:]]*version' "$f" 2>/dev/null && { echo v2; return 0; }
    grep -qi '<PP_HEADER>' "$f" 2>/dev/null && { echo v1; return 0; }
    echo unknown
}

# upf_attr <file> <attribute>   (UPF v2 only)
upf_attr() {
    awk -v key="$2" '
        /<PP_HEADER/ { inhdr = 1 }
        inhdr {
            if (match($0, key "[[:space:]]*=[[:space:]]*\"[^\"]*\"")) {
                s = substr($0, RSTART, RLENGTH)
                sub(/^[^"]*"/, "", s); sub(/"$/, "", s)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
                print s; exit
            }
            if (/\/>/ || /<\/PP_HEADER>/) exit
        }' "$1"
}

# upf_v1_field <file> <label regex>  -- v1 headers are "value   Label" lines
upf_v1_field() {
    awk -v pat="$2" '
        /<PP_HEADER>/ { inhdr = 1; next }
        /<\/PP_HEADER>/ { exit }
        inhdr && $0 ~ pat {
            line = $0
            sub(pat ".*$", "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            print line; exit
        }' "$1"
}

# ---------------------------------------------------------------------------
# upf_info <file> -- print "key=value" lines for whichever fields are present.
# Keys: format element type nlcc functional z_valence ecutwfc ecutrho
#       n_proj n_wfc l_max generated author date
# ---------------------------------------------------------------------------
upf_info() {
    local f=$1 fmt v
    [ -f "$f" ] || return 1
    fmt=$(upf_format "$f")
    printf 'format=%s\n' "$fmt"

    case $fmt in
    v2)
        for v in element pseudo_type core_correction functional z_valence \
                 ecutwfc ecutrho number_of_proj number_of_wfc l_max \
                 generated author date relativistic is_ultrasoft is_paw has_so; do
            local val; val=$(upf_attr "$f" "$v")
            [ -n "$val" ] || continue
            case $v in
                pseudo_type)     printf 'type=%s\n' "$val" ;;
                core_correction) printf 'nlcc=%s\n' "$val" ;;
                number_of_proj)  printf 'n_proj=%s\n' "$val" ;;
                number_of_wfc)   printf 'n_wfc=%s\n' "$val" ;;
                *)               printf '%s=%s\n' "$v" "$val" ;;
            esac
        done
        ;;
    v1)
        printf 'element=%s\n'   "$(upf_v1_field "$f" 'Element')"
        printf 'type=%s\n'      "$(upf_v1_field "$f" '[Uu]ltrasoft pseudopotential|pseudopotential')"
        printf 'nlcc=%s\n'      "$(upf_v1_field "$f" 'Nonlinear Core Correction')"
        printf 'functional=%s\n' "$(upf_v1_field "$f" 'Exchange-Correlation functional')"
        printf 'z_valence=%s\n' "$(upf_v1_field "$f" 'Z valence')"
        local cut; cut=$(upf_v1_field "$f" 'Suggested cutoff for wfc and rho')
        if [ -n "$cut" ]; then
            printf 'ecutwfc=%s\n' "$(printf '%s\n' "$cut" | awk '{print $1}')"
            printf 'ecutrho=%s\n' "$(printf '%s\n' "$cut" | awk '{print $2}')"
        fi
        printf 'n_proj=%s\n'  "$(upf_v1_field "$f" 'Number of Projectors')"
        printf 'n_wfc=%s\n'   "$(upf_v1_field "$f" 'Number of Wavefunctions')"
        printf 'l_max=%s\n'   "$(upf_v1_field "$f" 'Max angular momentum component')"
        printf 'generated=%s\n' "$(grep -m1 -A1 '<PP_INFO>' "$f" | tail -1 | sed 's/^[[:space:]]*//')"
        ;;
    esac
}

upf_get() {   # upf_get <file> <key>
    upf_info "$1" | awk -F= -v k="$2" '$1 == k { sub(/^[^=]*=/, ""); print; exit }'
}

# ---------------------------------------------------------------------------
# upf_validate <file> -- structural sanity checks.
# Prints one "LEVEL: message" line per problem; returns 1 if any are errors.
# ---------------------------------------------------------------------------
upf_validate() {
    local f=$1 fmt zval nproj bad=0

    if [ ! -f "$f" ]; then echo "ERROR: file does not exist"; return 1; fi
    if [ ! -s "$f" ]; then echo "ERROR: file is empty"; return 1; fi

    fmt=$(upf_format "$f")
    if [ "$fmt" = unknown ]; then
        echo "ERROR: no <PP_HEADER> found -- not a UPF file"
        return 1
    fi

    # ld1.x writes the file incrementally; a truncated run leaves the closing
    # tags missing, which pw.x reports much later and far less clearly.
    case $fmt in
        v2) grep -q '</UPF>'      "$f" || { echo "ERROR: truncated file -- no closing </UPF> tag"; bad=1; } ;;
        v1) grep -q '</PP_RHOATOM>' "$f" || { echo "ERROR: truncated file -- no </PP_RHOATOM> block"; bad=1; } ;;
    esac

    # NaN / Infinity in the radial data means the atomic solver diverged. In
    # a tag's attributes it means something else -- a converter computed a
    # header value from a quantity the source never recorded, as upfconv does
    # for PP_MESH xmin from an RRKJ3 file -- and saying "did not converge"
    # about that sent the diagnosis the wrong way.
    local badattr
    badattr=$(grep -oE '[A-Za-z_]+="[-+]?(Infinity|NaN|nan|inf)"' "$f" | head -3 | tr '\n' ' ')
    if [ -n "$badattr" ]; then
        echo "ERROR: header attribute(s) not a number: ${badattr% } -- written by a converter, not by an atomic solve"
        bad=1
    fi
    if grep -vE '<[^>]*>' "$f" | grep -qiE '(^|[^A-Za-z])(nan|-?inf(inity)?)([^A-Za-z]|$)'; then
        echo "ERROR: file contains NaN or Infinity in its data -- the atomic solve did not converge"
        bad=1
    fi

    # A pseudopotential that does not name its functional cannot be used:
    # pw.x stops with "Error in routine set_dft_from_name: unrecognized dft".
    # APE wrote every UPF this way -- the v1 functional field blank -- and
    # this validator passed them.
    local dft=""
    case $fmt in
        v1) dft=$(upf_v1_field "$f" 'Exchange-Correlation functional') ;;
        v2) dft=$(awk '/<PP_HEADER/,/\/>/' "$f" | grep -oE 'functional="[^"]*"' | head -1 | sed 's/^functional="//; s/"$//') ;;
    esac
    if [ -z "${dft// /}" ]; then
        echo "ERROR: no exchange-correlation functional named in the header -- pw.x stops with 'unrecognized dft'"
        bad=1
    fi

    # QE's XML reader holds one line at a time and stops at 1024 characters:
    #
    #     INTEGER, PARAMETER :: maxline=1024, maxdim=maxline+16
    #     if ( ll > maxline ) then
    #        print *, 'xmlr_opentag: severe error, line too long'
    #
    # (upflib/xmltools.f90). upfconv.x itself writes longer rows -- a 2,496-
    # character PP_QFCOEF line from an ordinary Vanderbilt file -- and this
    # validator used to pass them, so a file pw.x refuses to open was reported
    # valid. Checked against QE's own number, not a guess.
    #
    # That reader is QE's XML parser, which reads UPF v2. A v1 file goes
    # through the Fortran v1 reader, and pw.x read a v1 file from APE with a
    # 1,028-character PP_INFO line without complaint -- so the rule is applied
    # where the measured limit is, not to every file with a long line.
    local longest=0
    [ "$fmt" = v2 ] && longest=$(awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }' "$f")
    if [ "$longest" -gt 1024 ]; then
        echo "ERROR: a line of $longest characters -- Quantum ESPRESSO's reader stops at 1024 (xmlr_opentag: line too long)"
        bad=1
    fi
    if grep -q '\*\*\*\*' "$f"; then
        echo "ERROR: file contains Fortran overflow markers (****) -- numbers exceeded their format"
        bad=1
    fi

    zval=$(upf_get "$f" z_valence)
    if [ -z "$zval" ]; then
        echo "WARN: no z_valence in the header"
    else
        awk -v z="$zval" 'BEGIN { exit (z > 0 && z <= 100) ? 0 : 1 }' \
            || { echo "ERROR: implausible z_valence=$zval"; bad=1; }
    fi

    nproj=$(upf_get "$f" n_proj)
    if [ -n "$nproj" ] && [ "$nproj" = 0 ]; then
        echo "WARN: zero projectors -- the pseudopotential is purely local"
    fi

    # Required data blocks
    local blk
    for blk in PP_MESH PP_LOCAL PP_NONLOCAL PP_RHOATOM; do
        grep -q "<$blk" "$f" || { echo "WARN: missing <$blk> block"; }
    done
    if [ "$(upf_get "$f" nlcc)" = T ] || [ "$(upf_get "$f" nlcc)" = TRUE ]; then
        grep -q '<PP_NLCC' "$f" || { echo "ERROR: header claims NLCC but there is no <PP_NLCC> block"; bad=1; }
    fi

    return $bad
}

# Suggested cutoffs, honouring the file's own hints when it has them.
# upf_suggested_cutoffs <file> <family>  ->  "ecutwfc ecutrho"
upf_suggested_cutoffs() {
    local f=$1 fam=$2 wfc rho dual
    wfc=$(upf_get "$f" ecutwfc)
    rho=$(upf_get "$f" ecutrho)
    case $fam in
        nc)  dual=${DUAL_NC:-4} ;;
        us)  dual=${DUAL_US:-8} ;;
        *)   dual=${DUAL_PAW:-8} ;;
    esac
    # ld1.x writes 0.0 when it has nothing to suggest
    awk -v w="${wfc:-0}" 'BEGIN { exit (w > 0) ? 0 : 1 }' 2>/dev/null || wfc=
    awk -v r="${rho:-0}" 'BEGIN { exit (r > 0) ? 0 : 1 }' 2>/dev/null || rho=
    [ -n "$wfc" ] || wfc=$([ "$fam" = nc ] && echo 80 || echo 60)
    [ -n "$rho" ] || rho=$(awk -v w="$wfc" -v d="$dual" 'BEGIN { printf "%d", w * d }')
    printf '%s %s\n' "$wfc" "$rho"
}

# One-line summary for tables and reports.
upf_summary() {
    local f=$1
    local el ty zv wfc rho nl
    el=$(upf_get "$f" element);    ty=$(upf_get "$f" type)
    zv=$(upf_get "$f" z_valence);  nl=$(upf_get "$f" nlcc)
    # Only the file's own suggestion is shown. This used to print
    # upf_suggested_cutoffs, which fills a missing value with a built-in
    # default -- so APE's copper, which states no cutoff and measurably needs
    # 150-200 Ry, was summarised as "ecut~60/480 Ry", a number nobody had
    # measured or written.
    local ec
    wfc=$(upf_get "$f" ecutwfc); rho=$(upf_get "$f" ecutrho)
    if awk -v w="${wfc:-0}" 'BEGIN { exit !(w + 0 > 0) }' 2>/dev/null; then
        ec="ecut~${wfc}/${rho:-?} Ry (from the file)"
    else
        ec="no cutoff stated in the file"
    fi
    printf '%-4s %-6s Zval=%-7s NLCC=%-2s %s\n' \
           "${el:-?}" "${ty:-?}" "${zv:-?}" "${nl:-?}" "$ec"
}

# ---------------------------------------------------------------------------
# upf_validate_any <file>
#
# Not every engine writes UPF, and running UPF structural checks over a .cpi or
# a CASTEP recpot rejects a perfectly good file for the wrong reason.  Dispatch
# on what the file actually is: full structural checking where the format is
# understood, and a basic integrity check -- non-empty, no NaN, no Fortran
# overflow markers -- everywhere else, said plainly rather than dressed up as
# more than it is.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# psp8_validate <file>  -- ABINIT's psp8, checked against its own header.
#
# The layout is fixed and self-describing, which is what makes it checkable
# without reading the tables:
#
#   1  title
#   2  zatom zion pspdat
#   3  pspcod pspxc lmax lloc mmax r2well
#   4  rchrg fchrg qchrg            (pspcod 8 only)
#   5  nproj(0..lmax)               lmax+1 integers
#   6  extension_switch
#
# Everything after that is the radial tables, mmax rows per channel. The
# checks below are the ones the header licenses: that it says it is a psp8,
# that the charges are consistent with each other and with the element the
# filename claims, and that there are as many projector counts as there are
# channels. Nothing here inspects the physics of the tables -- that is what
# the transferability run is for, and claiming otherwise would be the kind of
# unearned reassurance this tree does not print.
# ---------------------------------------------------------------------------
psp8_validate() {
    local f=$1 bad=0
    [ -s "$f" ] || { echo "ERROR: file is empty"; return 1; }

    local zatom zion pspcod pspxc lmax lloc mmax nproj_n
    read -r zatom zion _ < <(sed -n '2p' "$f")
    read -r pspcod pspxc lmax lloc mmax _ < <(sed -n '3p' "$f")
    nproj_n=$(sed -n '5p' "$f" | awk '{ n = 0; for (i = 1; i <= NF; i++) if ($i ~ /^-?[0-9]+$/) n++; print n }')

    case ${pspcod:-} in
        8) ;;
        '') echo "ERROR: no readable psp8 header -- line 3 should carry pspcod"; return 1 ;;
        *)  echo "ERROR: pspcod is $pspcod, not 8 -- this is not a psp8 file"; bad=1 ;;
    esac

    # zatom and zion are printed as reals; compare them as such.
    if ! awk -v a="${zatom:-0}" -v i="${zion:-0}" 'BEGIN { exit !(a > 0 && i > 0 && i <= a + 1e-6) }'; then
        echo "ERROR: zatom=$zatom zion=$zion -- a valence charge must be positive and no larger than the nuclear one"
        bad=1
    fi

    # The element in the filename is a claim; the header is the measurement.
    local sym=${f##*/}; sym=${sym%%.*}
    if declare -F pf_elements_load >/dev/null 2>&1; then
        pf_elements_load
        local z_want=${EL_Z[$sym]:-}
        if [ -n "$z_want" ] && ! awk -v a="${zatom:-0}" -v z="$z_want" 'BEGIN { exit !(a > z - 0.5 && a < z + 0.5) }'; then
            echo "ERROR: the file is named $sym (Z=$z_want) but its header says zatom=$zatom"
            bad=1
        fi
    fi

    case ${lmax:-} in
        0|1|2|3|4) ;;
        *) echo "ERROR: lmax=$lmax is outside 0-4"; bad=1 ;;
    esac
    if [ -n "${lmax:-}" ] && [ -n "${nproj_n:-}" ] && [ "$nproj_n" -gt 0 ] 2>/dev/null; then
        [ "$nproj_n" -ge $((lmax + 1)) ] 2>/dev/null             || { echo "ERROR: $nproj_n projector counts for $((lmax + 1)) channels (lmax=$lmax)"; bad=1; }
    fi
    if ! [ "${mmax:-0}" -gt 0 ] 2>/dev/null; then
        echo "ERROR: mmax=$mmax -- the radial grid has no points"; bad=1
    else
        # One line per grid point per channel, plus the six header lines and
        # one channel-marker line before each block. Fewer than a single
        # block's worth means the tables were truncated.
        local lines; lines=$(wc -l < "$f")
        [ "$lines" -ge $((mmax + 6)) ]             || { echo "ERROR: $lines lines for mmax=$mmax -- the tables are truncated"; bad=1; }
    fi

    if grep -qiE '(^|[^A-Za-z])(nan|-?inf(inity)?)([^A-Za-z]|$)' "$f"; then
        echo "ERROR: file contains NaN or Infinity -- the solve did not converge"; bad=1
    fi
    if grep -q '\*\*\*\*' "$f"; then
        echo "ERROR: file contains Fortran overflow markers (****)"; bad=1
    fi

    [ "$bad" = 0 ] && echo "NOTE: ABINIT psp8, pspxc=$pspxc, lmax=$lmax, lloc=$lloc, $mmax grid points"
    return $bad
}

# ---------------------------------------------------------------------------
# upf_normalise <file>  -- make upfconv.x output readable by QE.
#
# Moved here from executor.sh, and the move is the fix. The engine path's own
# upfconv wrapper called this; convert.sh's wrapper -- which is what
# `pseudoforge convert` and the website's /api/convert run -- did not. So the
# same conversion produced a readable file from `generate` and an unreadable
# one from `convert`: Vanderbilt .van -> UPF wrote a 2,496-character row of
# PP_QFCOEF, QE's XML reader stopped at "xmlr_opentag: severe error, line too
# long", and pw.x refused the file. PseudoForge's UPF validator had passed it.
# Two wrappers for one tool is how a fix lands in one of them.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# upf_normalise <file>
#
# QE's own converter emits a UPF that QE cannot always read back:
#
#   * the whole <PP_HEADER .../> is written as one very long line, and the XML
#     reader has a fixed line buffer -- it fails with "xmlr_opentag: severe
#     error, line too long"
#   * pseudo_type comes out empty, though is_ultrasoft/is_paw are set
#   * the element symbol keeps the lower case of the generator's input ("si")
#
# None of these change the physics; all three stop the file being loaded.  This
# rewrites the header onto several lines and fills in what is missing, leaving
# every numeric block untouched.
# ---------------------------------------------------------------------------
upf_normalise() {
    local f=$1 tmp
    [ -s "$f" ] || return 1
    grep -q '<PP_HEADER' "$f" || return 0
    tmp=$f.norm.$$

    awk '
        /<PP_HEADER/ { inhdr = 1; hdr = "" }
        inhdr {
            hdr = hdr " " $0
            if ($0 !~ /\/>/) next
            inhdr = 0

            # Pull out key="value" pairs.  Splitting on whitespace would tear
            # apart values that contain spaces, which the generated-by string
            # always does.
            n = 0
            rest = hdr
            while (match(rest, /[A-Za-z_][A-Za-z_0-9]*="[^"]*"/)) {
                pair = substr(rest, RSTART, RLENGTH)
                rest = substr(rest, RSTART + RLENGTH)
                eq = index(pair, "=")
                k = substr(pair, 1, eq - 1)
                v = substr(pair, eq + 2, length(pair) - eq - 2)
                n++; key[n] = k; val[n] = v
                if (k == "is_ultrasoft") us = v
                if (k == "is_paw")       paw = v
            }

            printf "  <PP_HEADER\n"
            for (i = 1; i <= n; i++) {
                if (key[i] == "element")
                    val[i] = toupper(substr(val[i], 1, 1)) tolower(substr(val[i], 2))
                if (key[i] == "pseudo_type" && val[i] == "")
                    val[i] = (paw == "true" || paw == "T") ? "PAW" : \
                             ((us == "true" || us == "T") ? "USPP" : "NC")
                printf "     %s=\"%s\"\n", key[i], val[i]
            }
            printf "     />\n"
            next
        }
        { print }
    ' "$f" > "$tmp" || { rm -f "$tmp"; return 1; }

    [ -s "$tmp" ] || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$f"

    # Numeric blocks are whitespace-separated, so re-wrapping them changes
    # nothing a reader cares about -- but QE's XML parser has a fixed line
    # buffer and refuses anything longer, and its own converter happily writes
    # 2500-character rows.  Wrap those at four values per line, which is what
    # every hand-written UPF uses.
    #
    # A line that is long only because of trailing padding -- APE pads its
    # PP_INFO banner to 1,028 characters -- is trimmed rather than wrapped:
    # it is text, and wrapping it four "values" to a line would chop a
    # sentence into columns.
    awk '
        length($0) > 900 { sub(/[[:space:]]+$/, "") }
        length($0) > 900 && $0 !~ /[<>]/ {
            n = split($0, v, /[[:space:]]+/)
            out = ""; c = 0
            for (i = 1; i <= n; i++) {
                if (v[i] == "") continue
                out = out sprintf("%22s", v[i])
                if (++c % 4 == 0) { print out; out = "" }
            }
            if (out != "") print out
            next
        }
        { print }
    ' "$f" > "$tmp" || { rm -f "$tmp"; return 1; }
    [ -s "$tmp" ] || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$f"

    # An RRKJ3 file does not record where its logarithmic mesh starts, so
    # upfconv writes PP_MESH with zmesh="0" and therefore xmin="-Infinity"
    # (xmin = log(zmesh * r1)). The grid itself, PP_R, is exact -- pw.x gives
    # identical energies from the .RRKJ3 and the converted file -- but an
    # attribute holding -Infinity breaks any reader that rebuilds the mesh
    # from xmin, and a validator cannot tell it from a diverged solve.
    #
    # The value is not recoverable from the file: r1 = exp(xmin)/zmesh is one
    # equation in two unknowns. So the undefined attributes are *removed*,
    # not filled with a plausible guess. Both are optional in UPF v2 and QE
    # uses PP_R when it is present.
    if grep -qE '<PP_MESH[^>]*(xmin="[-+]?(Infinity|NaN)"|zmesh="0(\.0*)?")' "$f"; then
        sed -E '/<PP_MESH/ {
                  s/ xmin="[-+]?(Infinity|NaN)"//
                  s/ zmesh="0(\.0*)?"//
                }' "$f" > "$tmp" || { rm -f "$tmp"; return 1; }
        [ -s "$tmp" ] || { rm -f "$tmp"; return 1; }
        mv -f "$tmp" "$f"
    fi
}

# ---------------------------------------------------------------------------
# upf_v1_set_functional <file> <qe-name>
#
# Write a functional name into a v1 header whose field is blank. QE reads the
# first 20 columns of that line as the name (read_upf_v1: '(a20,t24,a)'), so
# the name goes in columns 2-20 and the label keeps its place at column 24.
# ---------------------------------------------------------------------------
upf_v1_set_functional() {
    local f=$1 name=$2 tmp
    [ -n "$name" ] || return 1
    tmp=$f.fn.$$
    awk -v n="$name" '
        /<PP_HEADER>/   { h = 1 }
        /<\/PP_HEADER>/ { h = 0 }
        h && !done && /Exchange-Correlation functional/ {
            printf " %-19s   Exchange-Correlation functional\n", n
            done = 1; next
        }
        { print }
        END { exit !done }' "$f" > "$tmp" || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$f"
}

upf_validate_any() {
    local f=$1 bad=0
    [ -f "$f" ] || { echo "ERROR: file does not exist"; return 1; }
    [ -s "$f" ] || { echo "ERROR: file is empty"; return 1; }

    case $(lower "${f##*.}") in
        upf) upf_validate "$f"; return $? ;;
        gth) gth_validate_block "$f"; return $? ;;
        xml) pawxml_validate "$f"; return $? ;;
        vps) vps_validate "$f"; return $? ;;
        psp8) psp8_validate "$f"; return $? ;;
    esac

    # Generic checks that apply to any numeric pseudopotential tabulation.
    if grep -qiE '(^|[^A-Za-z])(nan|-?inf(inity)?)([^A-Za-z]|$)' "$f"; then
        echo "ERROR: file contains NaN or Infinity -- the solve did not converge"
        bad=1
    fi
    if grep -q '\*\*\*\*' "$f"; then
        echo "ERROR: file contains Fortran overflow markers (****)"
        bad=1
    fi
    # A *tabulated* pseudopotential of a few hundred bytes is a stub, not a
    # result.  Analytic ones are exempt and are checked by structure instead;
    # they are handled above, before this point.
    local sz; sz=$(wc -c < "$f")
    if [ "$sz" -lt 500 ]; then
        echo "ERROR: only $sz bytes -- too small to be a pseudopotential"
        bad=1
    fi
    [ "$bad" = 0 ] && echo "NOTE: ${f##*.} format -- checked for integrity only, not structure"
    return $bad
}

# ---------------------------------------------------------------------------
# pawxml_validate <file>
#
# PAW-XML from AtomPAW, with one guard that exists because of a specific
# upstream defect: AtomPAW 4.2.0.6 writes
#
#   <xc_functional type="LDA" name="MGGA-R2SCAN-001"/>
#
# on a meta-GGA data set.  Only "name" is right.  A consumer that reads "type"
# -- the obvious attribute to read, and what it is for -- treats an r2SCAN data
# set as LDA and gets wrong answers with nothing to show for it.
#
# This cannot be fixed in the file without editing someone else's output, so it
# is reported loudly instead.
# ---------------------------------------------------------------------------
pawxml_validate() {
    local f=$1 type name bad=0
    [ -s "$f" ] || { echo "ERROR: file is empty"; return 1; }

    grep -q '<paw_' "$f" || grep -q 'paw_setup' "$f" || {
        echo "ERROR: does not look like a PAW-XML data set"; return 1; }

    type=$(grep -m1 -oE 'xc_functional[^>]*type="[^"]*"' "$f" | grep -oE 'type="[^"]*"' | cut -d'"' -f2)
    name=$(grep -m1 -oE 'xc_functional[^>]*name="[^"]*"' "$f" | grep -oE 'name="[^"]*"' | cut -d'"' -f2)

    if printf '%s' "$name" | grep -qiE 'mgga|r2scan|rscan|scan'; then
        case $(lower "${type:-}") in
            mgga|metagga|'') ;;
            *)
                echo "WARNING: this file says xc_functional type=\"$type\" but name=\"$name\"."
                echo "WARNING:   It is a meta-GGA data set.  AtomPAW 4.2.0.6 mislabels the type"
                echo "WARNING:   attribute; read 'name', not 'type'.  See docs/reference/engines.md."
                ;;
        esac
    fi

    if grep -qiE '(^|[^A-Za-z])(nan|-?inf(inity)?)([^A-Za-z]|$)' "$f"; then
        echo "ERROR: file contains NaN or Infinity -- the solve did not converge"
        bad=1
    fi
    grep -q '\*\*\*\*' "$f" && { echo "ERROR: Fortran overflow markers (****)"; bad=1; }

    [ "$bad" = 0 ] && [ -n "$name" ] && \
        echo "NOTE: PAW-XML data set, functional $name; not readable by Quantum ESPRESSO"
    return $bad
}

# ---------------------------------------------------------------------------
# vps_validate <file> -- ADPACK's OpenMX format.
#
# Structural rather than size-based: a .vps is a keyword block followed by
# tabulated radial data, so the keywords that OpenMX requires can be checked
# directly, which catches a truncated file that a byte count would pass.
# ---------------------------------------------------------------------------
vps_validate() {
    local f=$1 bad=0 k
    [ -s "$f" ] || { echo "ERROR: file is empty"; return 1; }
    # These three are read from a real ADPACK .vps, not guessed: the file
    # echoes its input block, then declares the grid, then the potential
    # table itself under "Pseudo.Potentials".  An earlier version of this
    # check looked for a "Vps.public" keyword that does not exist in the
    # format, and rejected every valid file.
    for k in valence.electron grid.num; do
        grep -qi "$k" "$f" || { echo "ERROR: no '$k' keyword -- not a complete .vps"; bad=1; }
    done
    # The potential table is matched by its opening delimiter, case-sensitively.
    # A loose "Pseudo.Potentials" search is not enough: the same words appear in
    # a comment banner ("DATA for factorized norm conserving pseudo
    # potentials") and inside a different keyword
    # (j.dependent.pseudo.potentials), so a file whose actual data block had
    # been truncated away still passed.
    grep -qF '<Pseudo.Potentials' "$f"         || { echo "ERROR: no <Pseudo.Potentials block -- the potential table is missing"; bad=1; }
    if grep -qiE '(^|[^A-Za-z])(nan|-?inf(inity)?)([^A-Za-z]|$)' "$f"; then
        echo "ERROR: file contains NaN or Infinity -- the solve did not converge"; bad=1
    fi
    # A bare "****" search is wrong for this format: an ADPACK .vps opens with
    # a banner of asterisks around the echoed input file, and every valid file
    # was being rejected as overflowed.  A real Fortran overflow appears inside
    # a numeric row, so require digits on the same line.
    if awk '/\*\*\*\*/ && /[0-9]\./ { found = 1 } END { exit !found }' "$f"; then
        echo "ERROR: Fortran overflow markers (****) inside numeric data"
        bad=1
    fi
    [ "$bad" = 0 ] && echo "NOTE: OpenMX .vps; read by OpenMX, not by Quantum ESPRESSO"
    return $bad
}
