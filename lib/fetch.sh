# shellcheck shell=bash
# ---------------------------------------------------------------------------
# fetch.sh -- obtain a ready-made pseudopotential instead of generating one.
#
# Order of attempts:
#   1. the library's own official directory -- the definitive copy for the
#      configuration asked for
#   2. the mirror in MIRROR_URL -- the fallback when upstream is unreachable
#   3. neither: say which step failed, and offer to generate it locally
#
# What arrives is validated exactly like something pseudoforge generated itself:
# same UPF structural checks, same optional cutoff scan, same report.  A
# downloaded file is a fine thing to use -- it is usually *better* tested than
# anything generated on the spot -- but it should not be trusted sight unseen.
#
# Nothing here guesses at a URL scheme it has not been told about.  If a
# library's layout is unknown, PseudoForge says so rather than fabricating a path
# and reporting a 404 as if the element did not exist.
# ---------------------------------------------------------------------------

FETCH_MESSAGE=
FETCH_ORIGIN=
FETCH_TRIED=

# ---------------------------------------------------------------------------
# Downloader, curl or wget, whichever is present.
# fetch_url <url> <outfile> -> 0 on a successful download of a non-empty file
# ---------------------------------------------------------------------------
fetch_url() {
    local url=$1 out=$2 tmo=${DOWNLOAD_TIMEOUT:-120} code
    mkdir -p "$(dirname "$out")" || return 1
    if have curl; then
        code=$(curl -sSL --fail-with-body -m "$tmo" -o "$out" -w '%{http_code}' "$url" 2>/dev/null)
        [ "$code" = 200 ] && [ -s "$out" ] && return 0
        rm -f "$out"; return 1
    elif have wget; then
        wget -q -T "$tmo" -O "$out" "$url" 2>/dev/null && [ -s "$out" ] && return 0
        rm -f "$out"; return 1
    fi
    FETCH_MESSAGE="neither curl nor wget is installed"
    return 1
}

# Is a URL reachable at all?  Used to tell "mirror is down" from "file missing".
fetch_host_reachable() {
    local url=$1 code
    have curl || return 0     # cannot probe; assume yes and let the fetch fail
    code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' -L "$url" 2>/dev/null)
    [ -n "$code" ] && [ "$code" != 000 ]
}

# ---------------------------------------------------------------------------
# Candidate file names for an element under a given profile.
#
# Libraries do not agree on naming, so try the forms each actually uses rather
# than inventing one.  The list is deliberately short and specific.
# ---------------------------------------------------------------------------
fetch_candidate_names() {
    local prof=$1 el=$2 fct
    fct=$(xc_tag "${SPEC[xc]}" "${SPEC[rel]}")
    case $prof in
        psl-*)
            printf '%s.%s-n-kjpaw_psl.1.0.0.UPF\n' "$el" "$fct"
            printf '%s.%s-n-rrkjus_psl.1.0.0.UPF\n' "$el" "$fct"
            printf '%s.%s-kjpaw_psl.1.0.0.UPF\n'   "$el" "$fct"
            ;;
        sg15)
            # read the published listing rather than guessing version numbers
            local hit
            if hit=$(fetch_index_match "$prof" "$el" 2>/dev/null) && [ -n "$hit" ]; then
                printf '%s\n' "$hit"
            fi ;;
        gbrv)
            printf '%s_%s_v1.uspp.F.UPF\n' "$(lower "$el")" "$(lower "$(xc_generator "${SPEC[xc]}")")"
            printf '%s_%s_v1.2.uspp.F.UPF\n' "$(lower "$el")" "$(lower "$(xc_generator "${SPEC[xc]}")")"
            ;;
        qe-legacy)
            # Historical names, in the order the old tables used them.
            local x; x=$(lower "$(xc_generator "${SPEC[xc]}")")
            printf '%s.%s-rrkjus.UPF
'  "$el" "$x"
            printf '%s.%s-vbc.UPF
'     "$el" "$x"
            printf '%s.%s-rrkj.UPF
'    "$el" "$x"
            printf '%s.%s-van.UPF
'     "$el" "$x"
            printf '%s.%s-mt.UPF
'      "$el" "$x"
            ;;
        gipaw)
            # Ceresoli's repository names files by element and flavour; try the
            # ultrasoft one first, then the Troullier-Martins variants.
            printf '%s.pbe-rrkjus-gipaw-dc.UPF
' "$el"
            printf '%s.pbe-tm-gipaw.UPF
' "$el"
            printf '%s.pbe-tm-gipaw-dc.UPF
' "$el"
            ;;
        pseudodojo)
            printf '%s.upf\n' "$el"
            printf '%s_r.upf\n' "$el"
            ;;
        *)
            printf '%s.UPF\n' "$el"
            printf '%s.upf\n' "$el"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# The fallback chain, in order:
#
#   1. the library's official directory   MD_OFFICIAL_URL[<profile>]
#   2. the user's mirror        MIRROR_URL/<library-path>/<functional>/<file>
#   3. nothing -- say so, and say what to do instead
#
# Each step reports which one it is on, because "the mirror is down" and "that
# element was never published" need different responses from the user.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Directory-index discovery.
#
# Guessing file names does not work.  SG15 alone publishes three version
# numbers (1.0, 1.1, 1.2) that differ per element, marks fully-relativistic
# files with an _FR infix, and offers PBE only -- so a guessed
# "Tl_ONCV_PBESOL-1.2.upf" is two mistakes at once and reports back as a plain
# 404, which reads as "that element does not exist" rather than "you asked for
# a functional this library never published".
#
# Where a library serves a browsable directory, PseudoForge reads it once,
# caches it, and picks the file that is actually there.
# ---------------------------------------------------------------------------

fetch_index_cache() { printf '%s/index-%s.txt\n' "${TMPDIR:-/tmp}" "$1"; }

# fetch_index_names <profile> -> one file name per line, or non-zero
fetch_index_names() {
    local prof=$1 url cache
    pf_metadata_load
    url=${MD_INDEX_URL[$prof]:-}
    [ -n "$url" ] || return 1
    cache=$(fetch_index_cache "$prof")

    # re-read at most once an hour; a listing that changes mid-run is not a
    # problem worth solving
    if [ -s "$cache" ] && [ -n "$(find "$cache" -mmin -60 2>/dev/null)" ]; then
        cat "$cache"; return 0
    fi

    local html
    html=$(curl -sSL -m "${DOWNLOAD_TIMEOUT:-120}" "$url" 2>/dev/null) || return 1
    [ -n "$html" ] || return 1
    printf '%s' "$html" \
        | grep -oE '[A-Za-z0-9._+-]+\.(upf|UPF)' \
        | sort -u > "$cache"
    [ -s "$cache" ] || return 1
    cat "$cache"
}

# ---------------------------------------------------------------------------
# fetch_index_match <profile> <element> -> the best file name, or non-zero
#
# "Best" = the element's own file, for the requested functional and relativity,
# at the highest version published.
# ---------------------------------------------------------------------------
fetch_index_match() {
    local prof=$1 el=$2 xc rel want_fr names
    xc=$(upper "$(xc_generator "${SPEC[xc]}")")
    case $(rel_canon "${SPEC[rel]}") in full) want_fr=1 ;; *) want_fr=0 ;; esac

    names=$(fetch_index_names "$prof") || return 1

    printf '%s\n' "$names" | awk -v el="$el" -v xc="$xc" -v fr="$want_fr" '
        BEGIN { best = ""; bestv = "" }
        {
            name = $0
            # <El>_..., anchored so Ti does not match TiO or Tl
            if (index(name, el "_") != 1) next
            up = toupper(name)
            if (index(up, "_" xc "-") == 0 && index(up, "_" xc "_") == 0) next
            isfr = (index(up, "_FR-") > 0) ? 1 : 0
            if (isfr != fr) next
            # trailing version, e.g. -1.2.upf
            v = name
            sub(/^.*-/, "", v); sub(/\.[uU][pP][fF]$/, "", v)
            if (best == "" || v > bestv) { best = name; bestv = v }
        }
        END { if (best != "") print best }
    ' | head -1 | grep . || return 1
}

# Which functionals does this library actually publish?  Used to explain a miss
# instead of reporting it as a missing element.
fetch_index_functionals() {
    local prof=$1
    fetch_index_names "$prof" 2>/dev/null \
        | grep -oE '_ONCV_[A-Za-z_]+-' \
        | sed -e 's/^_ONCV_//' -e 's/_\?FR-$//' -e 's/-$//' \
        | grep . | sort -u | tr '\n' ' '
}

# fetch_mirror_urls <profile> <element>
fetch_mirror_urls() {
    local prof=$1 el=$2 base path fct name
    base=${MIRROR_URL%/}
    [ -n "$base" ] || return 0
    pf_metadata_load
    path=${MD_MIRROR_PATH[$prof]:-$prof}
    fct=$(xc_tag "${SPEC[xc]}" "${SPEC[rel]}")
    while read -r name; do
        [ -n "$name" ] || continue
        printf '%s/%s/%s/%s\n' "$base" "$path" "$fct" "$name"
        printf '%s/%s/%s\n'    "$base" "$path" "$name"
    done < <(fetch_candidate_names "$prof" "$el")
}

# fetch_official_urls <profile> <element>
#
# Only emitted for libraries whose per-element layout is public and stable.
# Where a library ships one archive instead (SG15, PseudoDojo), no URL is
# guessed -- fetch_explain tells the user how to get it properly.
fetch_official_urls() {
    local prof=$1 el=$2 base name
    pf_metadata_load
    base=${MD_OFFICIAL_URL[$prof]:-}
    [ -n "$base" ] || return 0
    case $prof in
        gipaw)
            while read -r name; do
                printf '%s/%s
' "${base%/}" "$name"
            done < <(fetch_candidate_names "$prof" "$el") ;;
        psl-*|gbrv|qe-legacy)
            while read -r name; do
                printf '%s%s\n' "${base%/}/" "$name"
            done < <(fetch_candidate_names "$prof" "$el") ;;
        sg15)
            # read the published listing rather than guessing version numbers
            local hit
            if hit=$(fetch_index_match "$prof" "$el" 2>/dev/null) && [ -n "$hit" ]; then
                printf '%s%s\n' "${base%/}/upf/" "$hit"
            fi ;;
        *)
            # single-archive or interactive distributions: nothing addressable,
            # and PseudoForge does not invent a path it has not been told about
            return 0 ;;
    esac
}

# ---------------------------------------------------------------------------
# fetch_pseudo <profile> <element> <destdir>
#   -> echoes the downloaded file, sets FETCH_ORIGIN, or fails with
#      FETCH_MESSAGE explaining what to do instead.
# ---------------------------------------------------------------------------
fetch_pseudo() {
    local prof=$1 el=$2 dest=$3
    local url out n_official=0 n_mirror=0 mirror_state=untried
    FETCH_MESSAGE=; FETCH_ORIGIN=; FETCH_TRIED=""

    # ---- 1. the library's own official directory ---------------------------
    #
    # The authors' copy is checked first on purpose: it is the definitive file
    # for the configuration asked for, and a mirror can be stale.  The mirror
    # is the fallback for when upstream is unreachable or rate-limited.
    while read -r url; do
        [ -n "$url" ] || continue
        n_official=$((n_official + 1))
        out=$dest/$(basename "$url")
        info "  [official] $url"
        if fetch_url "$url" "$out"; then
            ok "  found at the official source"
            FETCH_ORIGIN="official: $url"
            printf '%s\n' "$out"
            return 0
        fi
        FETCH_TRIED="$FETCH_TRIED$url"$'\n'
    done < <(fetch_official_urls "$prof" "$el")

    if [ "$n_official" = 0 ]; then
        info "  [official] $(md_official "$prof") publishes no per-element URL"
    else
        info "  not at the official source ($n_official name(s) tried)"
    fi

    # ---- 2. the configured mirror -----------------------------------------
    if [ -n "${MIRROR_URL:-}" ]; then
        if fetch_host_reachable "$MIRROR_URL"; then
            mirror_state=reachable
            while read -r url; do
                [ -n "$url" ] || continue
                n_mirror=$((n_mirror + 1))
                out=$dest/$(basename "$url")
                info "  [mirror]   $url"
                if fetch_url "$url" "$out"; then
                    ok "  found on the mirror"
                    FETCH_ORIGIN="mirror: $url"
                    printf '%s\n' "$out"
                    return 0
                fi
                FETCH_TRIED="$FETCH_TRIED$url"$'\n'
            done < <(fetch_mirror_urls "$prof" "$el")
            [ "$n_mirror" -gt 0 ] && info "  not on the mirror ($n_mirror name(s) tried)"
        else
            mirror_state=unreachable
            info "  [mirror]   $MIRROR_URL is not reachable"
        fi
    else
        mirror_state='unset'
    fi

    # ---- 3. nothing -- say exactly which step failed ----------------------
    if [ "$n_official" = 0 ] && [ "$mirror_state" != reachable ]; then
        FETCH_MESSAGE="no per-element URL is published for '$prof', and the mirror is $mirror_state"
    elif [ "$n_official" = 0 ]; then
        FETCH_MESSAGE="no per-element URL is published for '$prof', and it is not on the mirror"
    elif [ "$mirror_state" = reachable ]; then
        FETCH_MESSAGE="not published for $el, and not on the mirror"
    else
        FETCH_MESSAGE="not published for $el (mirror $mirror_state)"
    fi
    return 1
}

# ---------------------------------------------------------------------------
# fetch_explain <profile> -- what a user should do when a download fails.
# Kept separate so the wizard and the CLI give the same advice.
# ---------------------------------------------------------------------------
fetch_explain() {
    local prof=$1
    pf_profiles_load
    printf '%s\n' "${FETCH_MESSAGE:-download failed}"
    case $prof in
        sg15)
            local have
            have=$(fetch_index_functionals sg15 2>/dev/null)
            if [ -n "$have" ]; then
                printf 'SG15 publishes these functionals only: %s\n' "$have"
                printf 'You asked for %s, so there is no file to download.\n' \
                       "$(upper "$(xc_generator "${SPEC[xc]}")")"
                printf 'Either pick a functional SG15 has, or generate locally --\n'
                printf 'PseudoForge ships SG15 own ONCVPSP decks and can run them.\n'
            else
                printf 'The SG15 file listing could not be read; the site may be down.\n'
                printf 'A full archive is available from %s\n' \
                       "${PROF_REFERENCE[sg15]:-http://www.quantum-simulation.org/potentials/sg15_oncv/}"
            fi ;;
        pseudodojo)
            printf 'PseudoDojo serves its tables from a web interface rather than from\n'
            printf 'predictable per-element URLs.  Download the table you want from\n'
            printf '%s, then:\n' "${PROF_REFERENCE[pseudodojo]:-http://www.pseudo-dojo.org/}"
            printf '    pseudoforge import <unpacked-dir> --profile pseudodojo\n'
            printf 'PseudoDojo also publishes the ONCVPSP input files.  Point PseudoForge at\n'
            printf 'those with --params <dir> and it will regenerate the table locally.\n' ;;
        gbrv)
            printf 'GBRV publishes per-functional archives at %s.\n' "${PROF_REFERENCE[gbrv]:-https://www.physics.rutgers.edu/gbrv/}"
            printf 'Download one and use:  pseudoforge import <dir> --profile gbrv\n' ;;
        *)
            printf 'Either import files you already have:\n'
            printf '    pseudoforge import <dir> --profile %s\n' "$prof"
            printf 'or generate locally:\n'
            printf '    pseudoforge generate -e <elements> --source local\n' ;;
    esac
}

# ---------------------------------------------------------------------------
# fetch_and_install <profile> <element> <project>
#   The whole online path: download, validate, install, record.
# ---------------------------------------------------------------------------
fetch_and_install() {
    local prof=$1 el=$2 project=$3
    local tmp file dest problems
    tmp=$project/logs/download
    mkdir -p "$tmp" "$project/pseudos"

    # Everything travels back on one line: the caller reads this through a
    # command substitution, so anything left in a FETCH_* variable would be
    # discarded along with the subshell.
    if ! file=$(fetch_pseudo "$prof" "$el" "$tmp"); then
        printf '%s\x1f%s\x1f%s\n' "" "" "$FETCH_MESSAGE"
        return 1
    fi

    if ! problems=$(upf_validate "$file" 2>&1); then
        printf '%s\x1f%s\x1f%s\n' "" "" \
            "downloaded $(basename "$file") but it failed validation: $(printf '%s' "$problems" | head -1)"
        return 1
    fi

    dest=$project/pseudos/$(basename "$file")
    mv -f "$file" "$dest" || return 1

    # Published files carry their own generation deck inside <PP_INPUTFILE>.
    # Harvest it now, so this library can later be *generated* locally from its
    # real parameters rather than from anything PseudoForge made up.
    params_extract_upf "$dest" "$prof" "$el" >/dev/null 2>&1 || true

    printf '%s\x1f%s\x1f%s\n' "$dest" "$FETCH_ORIGIN" ""
}
