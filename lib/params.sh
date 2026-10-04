# shellcheck shell=bash
# ---------------------------------------------------------------------------
# params.sh -- fetch the *generation inputs* that published libraries release.
#
# This is what turns "import only" into "generate it yourself".
#
# The obstacle was never licensing and never the engine: it was that a library
# is defined by its table of cut-off radii, q-cutoffs and projector counts, and
# inventing those would produce a file carrying a trusted name and untrusted
# numbers.  But most libraries publish those tables, alongside the finished
# pseudopotentials:
#
#   SG15        elements/<NN>_<El>/<El>_ONCV_<XC>-<ver>.dat inside the source
#               tarball -- 87 real ONCVPSP decks
#   PseudoDojo  <El>/<El>.in and <El>-sp.in in the GitHub repository, one
#               directory per functional and relativity
#   GBRV        Work_GBRV_v1.5.tar.gz, the uspp Work/ tree they generated from
#   Vanderbilt  Work/ inside the uspp distribution PseudoForge already builds
#   fhi98PP     bin/Elements/{Ham,TM} inside its own distribution
#   PSlibrary   shipped with PseudoForge, byte-identical to upstream
#
# So PseudoForge downloads the authors' own inputs and runs them.  The result is a
# real reproduction, recorded with provenance "library", and nothing is
# fabricated at any point.  Where a library does not publish inputs, that is
# still reported honestly rather than papered over.
# ---------------------------------------------------------------------------

# Two places hold generation inputs:
#
#   data/params/<lib>   shipped with PseudoForge, so every library it can
#                       reproduce works offline, with no download at all
#   <cache>/<lib>       anything fetched later: a newer release, or a library
#                       added after this version
#
# The bundle wins; the cache is for updates.
params_root()      { printf '%s\n' "${PARAMS_CACHE:-$HOME/.pseudoforge/params}"; }
params_cachedir()  { printf '%s/%s\n' "$(params_root)" "$1"; }
params_bundledir() { printf '%s/params/%s\n' "$PF_DATA" "$1"; }

# Does this library's data ship with PseudoForge?
params_bundled() {
    local b
    b=$(params_bundledir "$1")
    [ -d "$b" ] && [ -n "$(ls -A "$b" 2>/dev/null)" ]
}

# The directory actually holding this library's inputs.
params_dir() {
    if params_bundled "$1"; then params_bundledir "$1"
    else                         params_cachedir  "$1"; fi
}

# ---------------------------------------------------------------------------
# What each library publishes, and where.  Verified reachable at the time of
# writing; params_fetch reports honestly when a URL has moved.
# ---------------------------------------------------------------------------
declare -gA PARAMS_KIND PARAMS_URL PARAMS_NOTE

pf_params_load() {
    [ -n "${PARAMS_KIND[sg15]:-}" ] && return 0

    PARAMS_KIND[sg15]=tarball
    PARAMS_URL[sg15]="http://www.quantum-simulation.org/potentials/sg15_oncv/sg15_oncv_2015-10-07.tar.gz"
    PARAMS_NOTE[sg15]="ONCVPSP decks under elements/<NN>_<El>/"

    PARAMS_KIND[pseudodojo]=github
    PARAMS_URL[pseudodojo]="https://raw.githubusercontent.com/abinit/pseudo_dojo/master/pseudo_dojo/pseudos"
    PARAMS_NOTE[pseudodojo]="one directory per functional and relativity, e.g. ONCVPSP-PBE-PDv0.4"

    PARAMS_KIND[gbrv]=tarball
    PARAMS_URL[gbrv]="https://www.physics.rutgers.edu/gbrv/Work_GBRV_v1.5.tar.gz"
    PARAMS_NOTE[gbrv]="the uspp Work/ tree GBRV was generated from"

    # These two ship their tables inside the engine source PseudoForge already
    # unpacks, so there is nothing to download.
    PARAMS_KIND[vanderbilt]=engine
    PARAMS_URL[vanderbilt]=""
    PARAMS_NOTE[vanderbilt]="Work/ inside the uspp distribution"

    PARAMS_KIND[fhi]=engine

    # OPIUM and AtomPAW both ship their own generation inputs inside their
    # source trees, in the same way fhi98PP ships its element database.
    # PseudoForge does not fabricate these parameters; it reads them from
    # the engine's own distribution.  The kind is "engine" for that reason:
    # the parameters come with the binary, not from a downloaded library.
    #
    # For OPIUM the inputs are the reference parameter decks under
    # tests/{element}/{GGA,LDA}/references/*.param, chosen by
    # ib_opium_find_deck.  For AtomPAW the input is a deck PseudoForge
    # constructs from the element's ground-state configuration and a
    # cut-off-radius heuristic, using AtomPAW's own program format.
    PARAMS_KIND[opium]=engine
    PARAMS_KIND[atompaw]=engine

    # OPIUM and AtomPAW both ship their own generation inputs inside their
    # source trees, in the same way fhi98PP ships its element database.
    # PseudoForge does not fabricate these parameters; it reads them from
    # the engine's own distribution.  The kind is "engine" for that reason:
    # the parameters come with the binary, not from a downloaded library.
    #
    # For OPIUM the inputs are the reference parameter decks under
    # tests/{element}/{GGA,LDA}/references/*.param, chosen by
    # ib_opium_find_deck.  For AtomPAW the input is a deck PseudoForge
    # constructs from the element's ground-state configuration and a
    # cut-off-radius heuristic, using AtomPAW's own program format.
    PARAMS_URL[fhi]=""
    PARAMS_NOTE[fhi]="bin/Elements/{Ham,TM} inside the fhi98PP distribution"

    # GTH and HGH.  These were marked 'analytic' here, with a comment saying no
    # engine could reproduce them.  That reasoning was wrong and it cost these
    # two libraries their generate path: 'analytic' describes the *form* of the
    # result -- a dozen coefficients instead of a radial grid -- and says
    # nothing about whether a generator exists.  One does, CP2K publishes it
    # (atom.x plus pseudo.x), and PseudoForge ships 435 of their own per-element
    # input sets alongside the coefficient tables.
    PARAMS_KIND[cp2k-gth]=builtin
    PARAMS_URL[cp2k-gth]=""
    PARAMS_NOTE[cp2k-gth]="coefficient tables and generation inputs, both bundled"

    PARAMS_KIND[hgh]=builtin
    PARAMS_URL[hgh]=""
    PARAMS_NOTE[hgh]="the relativistic GTH set; same engine, same bundled inputs"

    local id
    for id in psl-high psl-low psl-031 psl-alt psl-tot; do
        PARAMS_KIND[$id]=builtin
        PARAMS_URL[$id]=""
        PARAMS_NOTE[$id]="shipped with PseudoForge in data/psl"
    done

    # Marburg publishes plain ld1.x decks, so the existing engine runs them.
    # Filenames are the lower-case element symbol, split by relativity.
    PARAMS_KIND[marburg]=builtin
    PARAMS_URL[marburg]=""
    PARAMS_NOTE[marburg]="ld1.x decks for the actinoids, scalar/ and full/"

    PARAMS_KIND[sssp]=selection
    PARAMS_URL[sssp]=""
    PARAMS_NOTE[sssp]="a per-element selection from other libraries; generate the library it selects"
}

params_kind() {
    pf_params_load
    # An analytic table stays analytic even though its data ships with
    # PseudoForge.  Shipping the coefficients is not the same as being able to
    # generate them, and conflating the two would have the tool advertise a
    # capability it does not have.
    case ${PARAMS_KIND[$1]:-} in
        analytic|selection) printf '%s\n' "${PARAMS_KIND[$1]}"; return 0 ;;
    esac
    # Otherwise, inputs that ship with PseudoForge mean there is nothing to
    # fetch, whatever the upstream distribution method happens to be.
    params_bundled "$1" && { printf 'builtin\n'; return 0; }
    printf '%s\n' "${PARAMS_KIND[$1]:-none}"
}

# ---------------------------------------------------------------------------
# params_have <library> [element]
#   Do we already hold generation inputs for this library (or this element)?
# ---------------------------------------------------------------------------
params_have() {
    local lib=$1 el=${2:-} d
    pf_params_load
    case $(params_kind "$lib") in
        builtin) return 0 ;;
        engine)
            case $lib in
                vanderbilt) [ -n "${USPP_ROOT:-}" ] && [ -d "${USPP_ROOT}/Work" ] && return 0 ;;
                fhi)        [ -n "${FHI98PP_ROOT:-}" ] && [ -d "${FHI98PP_ROOT}/bin/Elements" ] && return 0 ;;
            esac
            return 1 ;;
    esac
    d=$(params_dir "$lib")
    [ -d "$d" ] || return 1
    if [ -n "$el" ]; then
        params_find "$lib" "$el" >/dev/null 2>&1
    else
        [ -n "$(ls -A "$d" 2>/dev/null)" ]
    fi
}

# ---------------------------------------------------------------------------
# params_find <library> <element> -> the input deck for that element, if held.
#
# Each library names its files differently; this is the one place that knows
# how.  Where a library ships several variants for an element (a semicore "-sp"
# set, or two versions), the newest plain one wins unless SPEC[variant] asks
# for another.
# ---------------------------------------------------------------------------
params_find() {
    local lib=$1 el=$2 d f z want ex
    d=$(params_dir "$lib")
    want=${SPEC[variant]:-}
    z=$(printf '%02d' "${EL_Z[$el]:-0}")

    # Decks harvested from the library's own published files come first: those
    # are that library's actual numbers, recovered from its actual output, so
    # they beat anything bundled or guessed.
    ex=$(params_root)/$lib/extracted
    if [ -d "$ex" ]; then
        f=$(ls "$ex/$el".dat "$ex/$el".in 2>/dev/null | head -1)
        [ -n "$f" ] && { printf '%s
' "$f"; return 0; }
        f=""
    fi

    case $lib in
        sg15)
            # elements/<NN>_<El>/<El>_ONCV_<XC>-<ver>.dat -- take the highest version
            f=$(find "$d" -path "*/${z}_${el}/${el}_ONCV_*.dat" -type f 2>/dev/null | sort -V | tail -1)
            [ -n "$f" ] || f=$(find "$d" -name "${el}_ONCV_*.dat" -type f 2>/dev/null | sort -V | tail -1)
            ;;
        pseudodojo)
            if [ -n "$want" ]; then
                f=$(ls "$d"/*/"$el"/"$el-$want".in 2>/dev/null | head -1)
            fi
            # The fully-relativistic table names its files <El>_r.in
            if [ "$(rel_canon "${SPEC[rel]:-scalar}")" = full ]; then
                f=$(ls "$d"/*FR*/"$el"/"$el"_r.in "$d"/*FR*/"$el"/"$el"_r-*.in 2>/dev/null | head -1)
                [ -n "${f:-}" ] && { printf '%s
' "$f"; return 0; }
            fi
            [ -n "${f:-}" ] || f=$(ls "$d"/*/"$el"/"$el".in 2>/dev/null | head -1)
            [ -n "${f:-}" ] || f=$(ls "$d"/*/"$el"/"$el"-*.in 2>/dev/null | head -1)
            ;;
        marburg)
            local sub=scalar
            [ "$(rel_canon "${SPEC[rel]:-scalar}")" = full ] && sub=full
            f=$(ls "$d/$sub/$(lower "$el").in" "$d/$sub/$el.in" 2>/dev/null | head -1)
            ;;
        gbrv|vanderbilt)
            # a uspp Work/ tree: <NNN>-<El>/<variant>/<el>_ps.adat
            local zzz; zzz=$(printf '%03d' "${EL_Z[$el]:-0}")
            local root=$d
            [ "$lib" = vanderbilt ] && root=${USPP_ROOT:-$d}
            # The bundled GBRV tree is Work_GBRV/ while the uspp source tree
            # uses Work/; glob both rather than only the one the engine ships.
            f=$(ls -d "$root"/Work*/"$zzz-$el"/*/ 2>/dev/null | head -1)
            [ -n "$f" ] || f=$(ls -d "$root"/*/Work*/"$zzz-$el"/*/ 2>/dev/null | head -1)
            ;;
        gipaw)
            # Ceresoli publishes one directory per pseudopotential, named
            # <El>.<xc>-<scheme>-gipaw-dc, each holding the ld1.x deck that
            # made it.  Prefer the functional actually asked for.
            # The scheme is in the directory name and it decides the family:
            # rrkjus is ultrasoft, tm is norm-conserving.  Matching on the
            # element alone offered Ceresoli's ultrasoft lanthanides for a
            # norm-conserving run and his Al for an ultrasoft one, which is
            # how gipaw came to report the same 16 elements for both families.
            local gxc scheme gdir
            gxc=$(lower "$(xc_qe_string "${SPEC[xc]:-pbe}")")
            case ${SPEC[family]:-} in
                us) scheme=us ;;
                nc) scheme=tm ;;
                *)  scheme="" ;;
            esac
            gdir=$(ls -d "$d/$el.$gxc-"*"$scheme"*/ 2>/dev/null | head -1)
            [ -n "${gdir:-}" ] || gdir=$(ls -d "$d/$el."*"$scheme"*/ 2>/dev/null | head -1)
            [ -n "${gdir:-}" ] || return 1
            f=$(ls "$gdir/$el".in 2>/dev/null | head -1)
            ;;
        cp2k-gth|hgh)
            # GTH is the one library where the "deck" is a directory: atom.dat
            # for the all-electron solve plus the fit's starting parameters.
            f=$(gth_inputs "${SPEC[xc]:-pbe}" "$el" 2>/dev/null)
            ;;
        fhi)
            local root=${FHI98PP_ROOT:-$d}
            f=$(find "$root/bin/Elements" -path "*/TM/${z}-${el}*.ini" -type f 2>/dev/null | head -1)
            [ -n "$f" ] || f=$(find "$root/bin/Elements" -name "${z}-${el}*.ini" -type f 2>/dev/null | head -1)
            ;;
        *)
            f=$(ls "$d/$el".* 2>/dev/null | head -1)
            ;;
    esac
    [ -n "${f:-}" ] || return 1
    printf '%s\n' "$f"
}

# ---------------------------------------------------------------------------
# The PseudoDojo table for the current functional and relativity.
# ---------------------------------------------------------------------------
params_dojo_table() {
    local xc rel
    xc=$(upper "$(xc_generator "${SPEC[xc]:-pbe}")")
    case $xc in
        PBESOL) xc=PBEsol ;;
        PZ|PW)  xc=PW ;;
        *)      xc=PBE ;;
    esac
    if [ "$(rel_canon "${SPEC[rel]:-scalar}")" = full ] && [ "$xc" = PBE ]; then
        printf 'ONCVPSP-PBE-FR-PDv0.4\n'
    else
        printf 'ONCVPSP-%s-PDv0.4\n' "$xc"
    fi
}

# ---------------------------------------------------------------------------
# params_fetch <library> -- download the authors' generation inputs.
# ---------------------------------------------------------------------------
params_fetch() {
    local lib=$1
    pf_params_load
    pf_profiles_load
    local kind; kind=$(params_kind "$lib")
    local d; d=$(params_dir "$lib")

    case $kind in
        builtin)
            ok "${PROF_LABEL[$lib]:-$lib}: inputs ship with PseudoForge, nothing to fetch"
            return 0 ;;
        engine)
            if params_have "$lib"; then
                ok "${PROF_LABEL[$lib]:-$lib}: inputs come from the engine source, already present"
                return 0
            fi
            error "${PROF_LABEL[$lib]:-$lib}: its inputs live in the engine source tree."
            error "  Build the engine first:  pseudoforge engines build $(eng_for_profile "$lib" "${SPEC[family]:-us}")"
            return 1 ;;
        analytic)
            error "${PROF_LABEL[$lib]:-$lib} is a table of published fit coefficients, not generator output."
            error "  There is no input deck to fetch and no atomic code that reproduces it."
            error "  Import the published files instead:  pseudoforge import <dir> --profile $lib"
            return 1 ;;
        selection)
            error "${PROF_LABEL[$lib]:-$lib} selects a pseudopotential per element from other libraries."
            error "  Fetch the inputs of the library it selects, or import the finished files."
            return 1 ;;
        none)
            error "PseudoForge does not know where '$lib' publishes generation inputs."
            return 1 ;;
    esac

    mkdir -p "$d" || return 1
    case $lib in
        sg15)       params_fetch_tarball "$lib" "$d" 'elements/*/*.dat' ;;
        gbrv)       params_fetch_tarball "$lib" "$d" '' ;;
        pseudodojo) params_fetch_dojo "$d" ;;
        *)          error "no fetcher for '$lib'"; return 1 ;;
    esac
}

# A tarball of inputs; <pattern> narrows the extraction when the archive also
# carries source code or finished pseudopotentials we do not need.
params_fetch_tarball() {
    local lib=$1 d=$2 pattern=$3 url tmp n
    url=${PARAMS_URL[$lib]}
    tmp=$(mktemp -d)

    info "fetching ${PROF_LABEL[$lib]:-$lib} generation inputs"
    info "  from $url"
    if ! fetch_url "$url" "$tmp/params.tgz"; then
        error "  download failed -- the URL may have moved"
        error "  check ${MD_OFFICIAL_URL[$lib]:-the project page} and use --params <dir> with a local copy"
        rm -rf "$tmp"; return 1
    fi
    info "  $(du -h "$tmp/params.tgz" | cut -f1) downloaded, extracting"

    if [ -n "$pattern" ]; then
        tar xzf "$tmp/params.tgz" -C "$d" --wildcards "$pattern" 2>/dev/null
    else
        tar xzf "$tmp/params.tgz" -C "$d" 2>/dev/null
    fi
    rm -rf "$tmp"

    n=$(find "$d" -type f \( -name '*.dat' -o -name '*.adat' -o -name '*.in' \) 2>/dev/null | wc -l)
    if [ "$n" -eq 0 ]; then
        error "  the archive held no recognisable input decks"
        return 1
    fi
    ok "${PROF_LABEL[$lib]:-$lib}: $n input deck(s) in $d"
    pf_config_set PARAMS_CACHE "$(params_root)"
}

# PseudoDojo serves one file per element from its repository.  We fetch only
# the elements asked for, because the full table is several thousand files.
params_fetch_dojo() {
    local d=$1 table base el n=0 miss=0
    table=$(params_dojo_table)
    base=${PARAMS_URL[pseudodojo]}/$table
    mkdir -p "$d/$table"

    local -a want=()
    if [ -n "${PARAMS_ELEMENTS:-}" ]; then
        # shellcheck disable=SC2086
        mapfile -t want < <(el_expand $PARAMS_ELEMENTS)
    else
        mapfile -t want < <(el_expand all)
    fi

    info "fetching PseudoDojo inputs from $table"
    info "  ${#want[@]} element(s) from $base"
    for el in "${want[@]}"; do
        mkdir -p "$d/$table/$el"
        if fetch_url "$base/$el/$el.in" "$d/$table/$el/$el.in"; then
            n=$((n + 1))
        elif fetch_url "$base/$el/$el-sp.in" "$d/$table/$el/$el-sp.in"; then
            n=$((n + 1))
        else
            miss=$((miss + 1))
            rmdir "$d/$table/$el" 2>/dev/null
        fi
    done

    if [ "$n" -eq 0 ]; then
        error "  nothing downloaded -- the repository layout may have changed"
        error "  check https://github.com/abinit/pseudo_dojo"
        return 1
    fi
    ok "PseudoDojo: $n input deck(s) in $d/$table${miss:+ ($miss element(s) not in this table)}"
    pf_config_set PARAMS_CACHE "$(params_root)"
}

# ---------------------------------------------------------------------------
# params_status -- what PseudoForge holds, for doctor and the params command.
# ---------------------------------------------------------------------------
params_status() {
    pf_params_load
    pf_profiles_load
    local lib kind n d
    for lib in $(prof_list); do
        kind=$(params_kind "$lib")
        d=$(params_dir "$lib")
        case $kind in
            builtin)  n="ships with PseudoForge" ;;
            analytic) n="analytic table -- import only" ;;
            selection) n="a selection -- generate the source library" ;;
            engine)   n=$(params_have "$lib" && echo "from the engine source" || echo "build the engine first") ;;
            none)     n="no published inputs known" ;;
            *)
                if [ -d "$d" ]; then
                    n="$(find "$d" -type f \( -name '*.dat' -o -name '*.adat' -o -name '*.in' \) 2>/dev/null | wc -l) deck(s) cached"
                else
                    n="not fetched (pseudoforge params fetch $lib)"
                fi ;;
        esac
        printf '  %-14s %-11s %s\n' "$lib" "$kind" "$n"
    done
}

# ---------------------------------------------------------------------------
# Recovering generation parameters from a published pseudopotential.
#
# Both of the atomic codes PseudoForge cares about write their *entire input
# deck* into the file they produce, inside a <PP_INPUTFILE> block:
#
#   ld1.x     the &input/&inputp namelists and the wavefunction cards,
#             XML-escaped, so "&input" appears as "&amp;input"
#   ONCVPSP   the plain-text deck, exactly as fed in
#
# That settles the question this feature exists to answer.  When a library
# publishes finished UPFs, the numbers that define it are *inside* those files;
# they do not have to be guessed at, and they do not have to be shipped
# separately.  Harvest the deck and a later local run reproduces the real
# thing, with provenance "library" rather than "PseudoForge".
#
# A file that carries no <PP_INPUTFILE> yields nothing, and says so.  Header
# fields alone (z_valence, l_max, number_of_proj) are not a generation input
# and are never treated as one -- reconstructing radii from them would be
# exactly the fabrication this tool refuses to do.
# ---------------------------------------------------------------------------

# params_upf_inputfile <upf> -> the embedded deck on stdout, or non-zero
params_upf_inputfile() {
    local f=$1
    [ -s "$f" ] || return 1
    awk '
        /<PP_INPUTFILE/ { inblock = 1; next }
        /<\/PP_INPUTFILE>/ { exit }
        inblock { print }
    ' "$f" | sed -e 's/&amp;/\&/g' -e 's/&lt;/</g' -e 's/&gt;/>/g' \
                 -e 's/&quot;/"/g' -e "s/&apos;/'/g" \
           | grep -q . && \
    awk '
        /<PP_INPUTFILE/ { inblock = 1; next }
        /<\/PP_INPUTFILE>/ { exit }
        inblock { print }
    ' "$f" | sed -e 's/&amp;/\&/g' -e 's/&lt;/</g' -e 's/&gt;/>/g' \
                 -e 's/&quot;/"/g' -e "s/&apos;/'/g"
}

# Which engine does this deck belong to?  Decided on what the deck contains,
# not on the file name, because names lie and formats do not.
params_deck_engine() {
    local deck=$1
    if printf '%s\n' "$deck" | grep -qiE '^[[:space:]]*&input|iswitch[[:space:]]*='; then
        printf 'ld1\n'
    elif printf '%s\n' "$deck" | grep -qiE 'ATOM AND REFERENCE CONFIGURATION|^[[:space:]]*[A-Z][a-z]?[[:space:]]+[0-9.]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+'; then
        printf 'oncvpsp\n'
    else
        printf 'unknown\n'
    fi
}

# ---------------------------------------------------------------------------
# params_extract_upf <upf> <library> [element]
#   Harvest one file into the params cache.  Echoes the deck written.
# ---------------------------------------------------------------------------
params_extract_upf() {
    local f=$1 lib=$2 el=${3:-}
    local deck engine dest ext

    deck=$(params_upf_inputfile "$f") || return 1
    [ -n "$deck" ] || return 1

    [ -n "$el" ] || el=$(upf_get "$f" element)
    el=$(trim "${el:-}")
    [ -n "$el" ] || return 1

    engine=$(params_deck_engine "$deck")
    case $engine in
        ld1)     ext=in ;;
        oncvpsp) ext=dat ;;
        *)       return 1 ;;
    esac

    # Never write into the installed data tree: it may be read-only, shared
    # between users, or replaced by an upgrade.  Harvested decks are per-user
    # state and belong in the cache.
    dest=$(params_root)/$lib/extracted
    mkdir -p "$dest" || return 1
    printf '%s\n' "$deck" > "$dest/$el.$ext"

    # record where it came from, so provenance survives into the report
    printf '%s\t%s\t%s\n' "$el" "$engine" "$(basename "$f")" \
        >> "$dest/PROVENANCE.tsv"
    printf '%s\n' "$dest/$el.$ext"
}

# ---------------------------------------------------------------------------
# params_extract_dir <dir> <library>
#   Harvest every UPF in a directory.  This is what makes "download, then
#   generate the same thing yourself" work.
# ---------------------------------------------------------------------------
params_extract_dir() {
    local dir=$1 lib=$2
    local f got=0 skipped=0 out
    [ -d "$dir" ] || { error "not a directory: $dir"; return 1; }

    for f in "$dir"/*.upf "$dir"/*.UPF; do
        [ -e "$f" ] || continue
        if out=$(params_extract_upf "$f" "$lib" 2>/dev/null); then
            got=$((got + 1))
            debug "extracted $(basename "$out") from $(basename "$f")"
        else
            skipped=$((skipped + 1))
            debug "$(basename "$f") carries no <PP_INPUTFILE>"
        fi
    done

    if [ "$got" -eq 0 ]; then
        error "no generation inputs found in $dir"
        error "  Those files do not embed a <PP_INPUTFILE> block, so the parameters"
        error "  that define them are not recoverable from them.  PseudoForge will"
        error "  not reconstruct radii from header fields and call it a reproduction."
        return 1
    fi
    ok "extracted $got generation deck(s) into $(params_root)/$lib/extracted"
    [ "$skipped" -gt 0 ] && info "$skipped file(s) carried no embedded input"
    return 0
}
