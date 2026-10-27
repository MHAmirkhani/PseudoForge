# shellcheck shell=bash
# ---------------------------------------------------------------------------
# http.sh -- the REST interface.
#
# The fourth interface, and the same core. A request is routed to a handler,
# the handler calls the functions the CLI calls, and the answer is JSON.
# Nothing here computes anything a command-line user could not get from
# `pseudoforge`; if it did, that logic would belong in another module.
#
# The HTTP server itself is not this file. It is a transport -- see server/ --
# and it shells out to:
#
#     pseudoforge api <METHOD> <PATH> [body-file]
#
# which prints JSON on stdout and the status code on HTTP_STATUS. That keeps
# the routing, the shapes and the refusals in Bash, where the rest of the core
# is, and leaves the server with nothing to reimplement and nothing to drift
# from.
#
# ---------------------------------------------------------------------------
# What this interface deliberately cannot do
#
# **It cannot generate.** The deployment target is a 1-core, 1 GB VPS that does
# not have the engines, does not have Quantum ESPRESSO, and is not going to.
# POST /api/generate answers 501 with instructions for running it locally.
#
# That is the honest answer rather than a limitation being worked around.
# Queuing a job that no worker will ever collect would be worse than refusing:
# it would look like it worked.
# ---------------------------------------------------------------------------

HTTP_STATUS=200
HTTP_PARAM=
HTTP_HANDLER=

# Where the served files live.  Overridable so a test can point at a fixture
# tree without a VPS.
: "${PF_VAR_DIR:=/var/lib/pseudoforge}"
: "${PF_NATIVE_DIR:=$PF_VAR_DIR/native}"
: "${PF_CACHE_DIR:=$PF_VAR_DIR/cache}"

PF_INSTALL_URL=${PF_INSTALL_URL:-https://pseudo.amirkhani.me/docs/getting-started/installation/}

# ---------------------------------------------------------------------------
# The route table.
#
# METHOD <TAB> PATH <TAB> HANDLER <TAB> SUMMARY
#
# A `:name` segment is a parameter and is bound to HTTP_PARAM. This table is
# the single source for the routing, for docs/reference/http-api.md (generated
# by tools/gen_reference.sh) and for the server's own route list, so the three
# cannot disagree about what exists.
# ---------------------------------------------------------------------------
http_routes() {
    cat <<'EOF'
GET	/api/health	http_h_health	Environment and engine availability, as doctor records
GET	/api/version	http_h_version	Tool version and name
GET	/api/routes	http_h_routes	Every route in the REST API
GET	/api/engines	http_h_engines	Every engine in the registry
GET	/api/engines/:name	http_h_engine	One engine: families, formats, licence, upstream
GET	/api/formats	http_h_formats	Every format, and every conversion path with its cost
GET	/api/profiles	http_h_profiles	Every library profile
GET	/api/xc	http_h_xc	Every exchange-correlation functional
GET	/api/elements	http_h_elements	The element table
GET	/api/elements/:symbol	http_h_element	Native files and profiles for one element
GET	/api/advise	http_h_advise	Physics-reasoned pseudopotential recommendation
POST	/api/advise	http_h_advise	Physics-reasoned pseudopotential recommendation
GET	/api/coverage	http_h_coverage	Element x profile coverage matrix
GET	/api/recent	http_h_recent	Recently added files in the store
GET	/api/capabilities	http_h_capabilities	Honest capability matrix across deployment tiers
GET	/api/native	http_h_native_list	Native files available on this server
GET	/api/native/:id	http_h_native_one	One native file: metadata and provenance
GET	/api/provenance/:id	http_h_provenance	Show provenance for a native file
POST	/api/convert	http_h_convert	Convert a native file to another format
GET	/api/download/:id...	http_h_download	Serve a native or converted file
POST	/api/validate	http_h_validate	Validate an uploaded pseudopotential
POST	/api/generate	http_h_generate	Refused here: generation is a local operation
EOF
}

# ---------------------------------------------------------------------------
# JSON helpers.  pf_json_escape comes from sink.sh; these are the shapes.
# ---------------------------------------------------------------------------
http_json_str() { printf '"%s"' "$(pf_json_escape "$1")"; }

# Wrap newline-delimited JSON objects into an array.
http_json_array() {
    local first=1 line
    printf '['
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        [ "$first" = 1 ] && first=0 || printf ','
        printf '%s' "$line"
    done
    printf ']'
}

http_error() {   # http_error <status> <code> <message> [extra-json]
    HTTP_STATUS=$1
    printf '{"error":%s,"message":%s' \
        "$(http_json_str "$2")" "$(http_json_str "$3")"
    [ -n "${4:-}" ] && printf ',%s' "$4"
    printf '}\n'
}

# ---------------------------------------------------------------------------
# Routing.
# ---------------------------------------------------------------------------
http_match() {   # http_match <method> <path>
    local method=$1 path=$2 m p h _s
    HTTP_HANDLER='' HTTP_PARAM='' HTTP_QUERY=''
    if [[ "$path" == *\?* ]]; then
        HTTP_QUERY="${path#*\?}"
        path="${path%%\?*}"
    fi
    path=${path%/}; [ -n "$path" ] || path=/

    while IFS=$'\t' read -r m p h _s; do
        [ "$m" = "$method" ] || continue
        case $p in
            *:*)
                local prefix=${p%%:*} rest=0
                # ":id..." is a rest parameter: it may contain slashes,
                # because a cached conversion lives at <source-id>/<name>.
                # ":id" may not, so a path cannot be smuggled through an id.
                case $p in *...) rest=1 ;; esac
                case $path in
                    "$prefix"?*)
                        HTTP_PARAM=${path#"$prefix"}
                        if [ "$rest" = 0 ]; then
                            case $HTTP_PARAM in */*) continue ;; esac
                        fi
                        HTTP_HANDLER=$h; return 0 ;;
                esac ;;
            "$path") HTTP_HANDLER=$h; return 0 ;;
        esac
    done < <(http_routes)
    return 1
}

# ---------------------------------------------------------------------------
# http_handle <method> <path> [body-file]
#
# The entry point.  JSON on stdout, status in HTTP_STATUS.  Always exits 0:
# an HTTP status is the status, and a non-zero exit would make the transport
# guess at what went wrong.
# ---------------------------------------------------------------------------
http_handle() {
    local method=$1 path=$2 body=${3:-}
    local HTTP_QUERY=''
    HTTP_STATUS=200

    # The registries the handlers read.  Each loader returns early when it has
    # already run, so this costs nothing on the second request and means a
    # handler never has to remember which table it depends on.
    pf_elements_load 2>/dev/null || true
    pf_xc_load       2>/dev/null || true
    pf_profiles_load 2>/dev/null || true
    pf_metadata_load 2>/dev/null || true
    pf_engines_load  2>/dev/null || true
    pf_convert_load  2>/dev/null || true
    pf_formats_load  2>/dev/null || true
    pf_advice_load   2>/dev/null || true

    # Messages must never reach the body; only the handler's JSON does.
    pf_sink_use null

    if ! http_match "$method" "$path"; then
        # A path that exists under another method is a 405, not a 404 -- the
        # difference tells a client whether to fix the verb or the URL.
        local m p h _s found=0
        local check_path=$path
        [[ "$check_path" == *\?* ]] && check_path="${check_path%%\?*}"
        check_path=${check_path%/}; [ -n "$check_path" ] || check_path=/
        while IFS=$'\t' read -r m p h _s; do
            [ "$p" = "$check_path" ] && found=1
        done < <(http_routes)
        if [ "$found" = 1 ]; then
            http_error 405 method_not_allowed "That path does not accept $method."
        else
            http_error 404 not_found "No such endpoint: $method $path"
        fi
        pf_sink_use cli
        return 0
    fi

    "$HTTP_HANDLER" "$body"
    pf_sink_use cli
    return 0
}

# ---------------------------------------------------------------------------
# Read handlers.  Every one of these calls the same function the CLI calls.
# ---------------------------------------------------------------------------

http_h_health() {
    doctor_render_json "$(doctor_checks)" | http_json_array
    printf '\n'
}

http_h_version() {
    printf '{"tool":%s,"version":%s}\n' \
        "$(http_json_str "PseudoForge")" \
        "$(http_json_str "$PSEUDOFORGE_VERSION")"
}

http_h_routes() {
    local m p h sm
    printf '{"routes":'
    while IFS=$'\t' read -r m p h sm; do
        [ -n "$m" ] || continue
        printf '{"method":%s,"path":%s,"summary":%s}\n' \
            "$(http_json_str "$m")" \
            "$(http_json_str "$p")" \
            "$(http_json_str "$sm")"
    done < <(http_routes) | http_json_array
    printf '}\n'
}

http_h_engines() {
    local e
    for e in $(eng_list); do http_engine_json "$e"; done | http_json_array
    printf '\n'
}

http_engine_json() {
    local e=$1 avail=false
    eng_available "$e" 2>/dev/null && avail=true
    printf '{"id":%s,"label":%s,"families":%s,"native_upf":%s,"licence":%s,"upstream":%s,"available":%s,"note":%s}\n' \
        "$(http_json_str "$e")" \
        "$(http_json_str "${ENG_LABEL[$e]:-$e}")" \
        "$(http_json_str "${ENG_FAMILIES[$e]:-}")" \
        "$(http_json_str "${ENG_NATIVE_UPF[$e]:-no}")" \
        "$(http_json_str "${ENG_LICENSE[$e]:-unrecorded}")" \
        "$(http_json_str "${ENG_UPSTREAM[$e]:-unrecorded}")" \
        "$avail" \
        "$(http_json_str "${ENG_NOTE[$e]:-}")"
}

http_h_engine() {
    local id=$HTTP_PARAM
    if ! eng_exists "$id" 2>/dev/null; then
        http_error 404 unknown_engine "No such engine: $id" \
            "\"known\":$(eng_list | while read -r e; do http_json_str "$e"; printf '\n'; done | http_json_array)"
        return 0
    fi
    http_engine_json "$id"
}

http_h_formats() {
    printf '{"formats":'
    awk -F'\t' '!/^#/ && NF >= 4 {
        printf "{\"id\":\"%s\",\"label\":\"%s\",\"engines\":\"%s\",\"extension\":\"%s\"}\n", $1, $2, $3, $4
    }' "$PF_DATA/formats.tsv" | http_json_array
    printf ',"conversions":'
    local k
    for k in "${CVT_ORDER[@]:-}"; do
        [ -n "$k" ] || continue
        local dem=true
        [ "${CVT_KIND[$k]:-}" = refused ] && dem=false
        [ -n "${CVT_CAVEAT[$k]:-}" ] && dem=false
        printf '{"from":%s,"to":%s,"kind":%s,"refusal":%s,"tool":%s,"note":%s,"demonstrated":%s,"caveat":%s}\n' \
            "$(http_json_str "${k%%:*}")" "$(http_json_str "${k##*:}")" \
            "$(http_json_str "${CVT_KIND[$k]:-}")" \
            "$(http_json_str "${CVT_REFUSAL[$k]:-}")" \
            "$(http_json_str "${CVT_TOOL[$k]:-}")" \
            "$(http_json_str "${CVT_NOTE[$k]:-}")" \
            "$dem" "$(http_json_str "${CVT_CAVEAT[$k]:-}")"
    done | http_json_array
    printf '}\n'
}

http_h_profiles() {
    local p gen
    for p in $(prof_list 2>/dev/null | sort); do
        if prof_is_generatable "$p" 2>/dev/null; then gen=true; else gen=false; fi
        printf '{"id":%s,"label":%s,"families":%s,"generatable":%s}\n' \
            "$(http_json_str "$p")" \
            "$(http_json_str "${PROF_LABEL[$p]:-$p}")" \
            "$(http_json_str "${PROF_FAMILIES[$p]:-}")" \
            "$gen"
    done | http_json_array
    printf '\n'
}

http_h_xc() {
    local id
    for id in $(printf '%s\n' "${!XC_LABEL[@]}" | sort); do
        printf '{"id":%s,"label":%s,"family":%s,"status":%s,"qe":%s,"proxy":%s}\n' \
            "$(http_json_str "$id")" \
            "$(http_json_str "${XC_LABEL[$id]:-}")" \
            "$(http_json_str "${XC_FAMILY[$id]:-}")" \
            "$(http_json_str "${XC_STATUS[$id]:-}")" \
            "$(http_json_str "${XC_QE[$id]:-}")" \
            "$(http_json_str "${XC_PROXY[$id]:-}")"
    done | http_json_array
    printf '\n'
}

http_h_elements() {
    local s
    for s in "${EL_ORDER[@]}"; do
        printf '{"symbol":%s,"z":%s,"name":%s,"period":%s,"group":%s,"block":%s,"series":%s}\n' \
            "$(http_json_str "$s")" "${EL_Z[$s]:-0}" \
            "$(http_json_str "${EL_NAME[$s]:-}")" \
            "${EL_PERIOD[$s]:-0}" "${EL_GROUP[$s]:-0}" \
            "$(http_json_str "${EL_BLOCK[$s]:-}")" \
            "$(http_json_str "${EL_SERIES[$s]:-}")"
    done | http_json_array
    printf '\n'
}

http_h_element() {
    local sym=$HTTP_PARAM
    [ -n "$sym" ] || {
        http_error 400 bad_request "An element symbol is required."
        return 0
    }
    if ! element_summary_for "$sym"; then
        http_error 404 not_found "Unknown element: $sym"
        return 0
    fi
    element_render_json
}

# ---------------------------------------------------------------------------
# Query string helper
# ---------------------------------------------------------------------------
http_query_param() {   # http_query_param <query_string> <param_name>
    local q="${1:-}" key="$2"
    local pair k v
    local old_ifs=$IFS
    IFS='&'
    for pair in $q; do
        k="${pair%%=*}"
        v="${pair#*=}"
        if [ "$k" = "$key" ]; then
            IFS=$old_ifs
            v="${v//+/ }"
            printf '%b' "${v//%/\\x}"
            return 0
        fi
    done
    IFS=$old_ifs
    return 1
}

# ---------------------------------------------------------------------------
# Advise -- physics-reasoned pseudopotential recommendations.
#
# GET  /api/advise?element=Fe&calculation=phonons&code=qe&accuracy=balanced
# POST /api/advise (body: {"element":"Fe","calculation":"phonons",...})
# ---------------------------------------------------------------------------
http_h_advise() {
    local body=${1:-}
    local el="" calc="" code="" mat="" xc="" acc="balanced"

    if [ -n "$body" ] && [ -f "$body" ]; then
        el=$(http_body_field "$body" element)
        [ -n "$el" ] || el=$(http_body_field "$body" el)
        calc=$(http_body_field "$body" calculation)
        [ -n "$calc" ] || calc=$(http_body_field "$body" calc)
        code=$(http_body_field "$body" code)
        mat=$(http_body_field "$body" material)
        [ -n "$mat" ] || mat=$(http_body_field "$body" mat)
        xc=$(http_body_field "$body" functional)
        [ -n "$xc" ] || xc=$(http_body_field "$body" xc)
        acc=$(http_body_field "$body" accuracy)
        [ -n "$acc" ] || acc=$(http_body_field "$body" acc)
    fi

    if [ -n "${HTTP_QUERY:-}" ]; then
        local q_el; q_el=$(http_query_param "$HTTP_QUERY" element)
        [ -n "$q_el" ] || q_el=$(http_query_param "$HTTP_QUERY" el)
        [ -n "$q_el" ] && el=$q_el

        local q_calc; q_calc=$(http_query_param "$HTTP_QUERY" calculation)
        [ -n "$q_calc" ] || q_calc=$(http_query_param "$HTTP_QUERY" calc)
        [ -n "$q_calc" ] && calc=$q_calc

        local q_code; q_code=$(http_query_param "$HTTP_QUERY" code)
        [ -n "$q_code" ] && code=$q_code

        local q_mat; q_mat=$(http_query_param "$HTTP_QUERY" material)
        [ -n "$q_mat" ] || q_mat=$(http_query_param "$HTTP_QUERY" mat)
        [ -n "$q_mat" ] && mat=$q_mat

        local q_xc; q_xc=$(http_query_param "$HTTP_QUERY" functional)
        [ -n "$q_xc" ] || q_xc=$(http_query_param "$HTTP_QUERY" xc)
        [ -n "$q_xc" ] && xc=$q_xc

        local q_acc; q_acc=$(http_query_param "$HTTP_QUERY" accuracy)
        [ -n "$q_acc" ] || q_acc=$(http_query_param "$HTTP_QUERY" acc)
        [ -n "$q_acc" ] && acc=$q_acc
    fi

    if [ -z "$el" ]; then
        http_error 400 missing_element "The 'element' parameter is required."
        return 0
    fi

    if ! advise_for "$el" "$calc" "$code" "$mat" "$xc" "$acc"; then
        http_error 400 advise_failed "Could not generate advice for element '$el'."
        return 0
    fi

    advise_render_json
}

http_h_coverage() {
    local prof el
    prof=$(http_query_param "$HTTP_QUERY" profile)
    el=$(http_query_param "$HTTP_QUERY" element)
    if ! coverage_matrix "$prof" "$el"; then
        http_error 400 coverage_failed "Could not compute coverage matrix."
        return 0
    fi
    coverage_render_json
}

http_h_recent() {
    local count
    count=$(http_query_param "$HTTP_QUERY" count)
    count=${count:-10}
    if ! recent_files "$count"; then
        http_error 500 recent_failed "Could not retrieve recent files."
        return 0
    fi
    recent_render_json
}

http_h_capabilities() {
    if ! capabilities_for; then
        http_error 500 capabilities_failed "Could not load capabilities."
        return 0
    fi
    capabilities_render_json
}

# ---------------------------------------------------------------------------
# The native-file index.
#
# The served files are the source of truth; this index is derived from them by
# `pseudoforge native index`, and the server's SQLite table is in turn loaded
# from the index.  One scan, two consumers, no third opinion.
#
#   id <TAB> element <TAB> xc <TAB> family <TAB> rel <TAB> engine
#      <TAB> format <TAB> path <TAB> size <TAB> sha256 <TAB> provenance
# ---------------------------------------------------------------------------
http_native_index() {
    if [ -f "$PF_NATIVE_DIR/index.tsv" ]; then
        printf '%s/index.tsv\n' "$PF_NATIVE_DIR"
    elif [ -f "$HOME/pf-native/index.tsv" ]; then
        printf '%s/index.tsv\n' "$HOME/pf-native"
    elif [ -f "$HOME/pf-var/native/index.tsv" ]; then
        printf '%s/index.tsv\n' "$HOME/pf-var/native"
    else
        printf '%s/index.tsv\n' "$PF_NATIVE_DIR"
    fi
}

# The index columns, by name.  Five call sites used to reach into an index
# line with `cut -f8`, and adding two columns moved `path` to field 10 --
# which does not fail loudly.  It makes the download endpoint hand out the
# contents of the size column as a file path, and every download 404s.  One
# declaration, looked up by name, so a new column is a one-line change here
# and nothing else moves.
declare -gA NAT_COL=(
    [id]=1 [element]=2 [xc]=3 [family]=4 [relativity]=5 [engine]=6
    [format]=7 [profile]=8 [encoding]=9 [path]=10 [size]=11 [sha256]=12
    [provenance]=13
)

# native_field <name> <index-line>
native_field() {
    local n=${NAT_COL[$1]:-}
    [ -n "$n" ] || { printf '' ; return 1; }
    printf '%s' "$2" | cut -f"$n"
}

native_index_build() {   # native_index_build [dir] -- rescan and rewrite
    local dir=${1:-$PF_NATIVE_DIR} f rel size sha id prov
    [ -d "$dir" ] || { error "no native directory: $dir"; return 1; }

    # Everything expensive is done once here, not per file.
    #
    # The earlier version of this function was O(3-4 hours) for 13k files.
    # Two reasons, both fixed here:
    #
    #   1. The old per-file attribute lookup called pf_profiles_load()
    #      internally, which reads every *.profile from disk.  With
    #      ~80,000 attribute lookups per rebuild that was the bulk of the
    #      time.  Profiles are loaded exactly once, below.  (That helper
    #      is gone now -- this loop is its inlined replacement.)
    #
    #   2. Every PROVENANCE.txt was re-read from disk for every attribute
    #      of every file underneath it.  All of them (a few hundred files)
    #      are read once into a flat associative array, keyed by
    #      <directory>|<key>.  Lookup becomes a bash parameter expansion.
    #
    # The sha256 of a file whose size has not changed since the last index
    # is reused.  The store is immutable once written, so this is safe.
    pf_profiles_load 2>/dev/null

    declare -A OLD_SHA OLD_SIZE
    if [ -f "$dir/index.tsv" ]; then
        while IFS=$'\t' read -r _id _el _xc _fam _rl _eng _fmt _prof _enc _path _size _sha _prov; do
            case "$_id" in "#"*|"") continue ;; esac
            [ -n "$_path" ] || continue
            OLD_SHA[$_path]=$_sha
            OLD_SIZE[$_path]=$_size
        done < "$dir/index.tsv"
    fi

    declare -A PROV_KV
    local _pf _line _k _v _pd
    while IFS= read -r -d '' _pf; do
        _pd=${_pf%/PROVENANCE.txt}
        while IFS= read -r _line; do
            case "$_line" in ""|\#*) continue ;; esac
            case "$_line" in *=*) ;; *) continue ;; esac
            _k=${_line%%=*}
            _v=${_line#*=}
            PROV_KV["$_pd|$_k"]=$_v
        done < "$_pf"
    done < <(find "$dir" -name PROVENANCE.txt -type f -print0 2>/dev/null)

    # Look up a key in the cached provenance of the nearest ancestor dir.
    # Pure bash; no subshell, no awk, no find.
    _idx_prov() {   # _idx_prov <file> <key>
        local d=${1%/*}
        local stop=${PF_NATIVE_DIR:-}
        local depth=0
        while [ -n "$d" ] && [ "$d" != "/" ] && [ "$depth" -lt 5 ]; do
            local hit=${PROV_KV["$d|$2"]:-}
            if [ -n "$hit" ]; then printf '%s' "$hit"; return; fi
            [ -n "$stop" ] && [ "$d" = "$stop" ] && break
            d=${d%/*}
            depth=$((depth + 1))
        done
    }

    # Per-profile extension -> format-id, from the registry.  A profile
    # declares its formats, and each format declares its extension; the pair
    # (profile, extension) is what names a file.  Without this the index
    # fell back to the bare extension, and "abinit" was one format-id for
    # two very different things -- atompaw's PAW dataset and (when it is
    # present) cp2k-gth's coefficient table -- while "cpmd" could be either
    # opium's CPMD writer or gth's CPMD layout, and "psf" and "xml" the
    # same.  A single extension namespace cannot tell those apart; the
    # profile can.
    declare -A PF_EXT2FMT
    local _fid _flabel _feng _fext _fkw _fnote _p _pfmts
    while IFS=$'\t' read -r _fid _flabel _feng _fext _fkw _fnote; do
        case "$_fid" in ""|\#*) continue ;; esac
        [ -n "$_fext" ] || continue
        for _p in "${!PROF_FORMATS[@]}"; do
            _pfmts=" ${PROF_FORMATS[$_p]:-} "
            case "$_pfmts" in
                *" $_fid "*) PF_EXT2FMT["$_p|$_fext"]=$_fid ;;
            esac
        done
    done < "${PF_DATA:-$PF_ROOT/data}/formats.tsv"

    local total=0 computed=0 reused=0
    {
        printf '#id\telement\txc\tfamily\trelativity\tengine\tformat\tprofile\tencoding\tpath\tsize\tsha256\tprovenance\n'

        # find -printf returns size and path in a single pass.  The old loop
        # called stat separately for every file; this is one process.
        while IFS=$'\t' read -r size f; do
            rel=${f#"$dir"/}
            [ -f "$f" ] || continue

            local name=${rel##*/}
            name=${name%.gz}
            local el=${name%%.*}
            if declare -F el_exists >/dev/null 2>&1; then
                el_exists "$el" 2>/dev/null || el=unknown
            fi

            # sha256: reuse when size is unchanged.
            if [ -n "${OLD_SIZE[$rel]:-}" ] && [ "${OLD_SIZE[$rel]}" = "$size" ] \
               && [ -n "${OLD_SHA[$rel]:-}" ]; then
                sha=${OLD_SHA[$rel]}
                reused=$((reused + 1))
            else
                sha=$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1)
                computed=$((computed + 1))
            fi

            # Attributes from the path first.
            local _prof _fam _xc _rl _mid
            IFS=/ read -r _prof _fam _xc _rl _mid _ <<< "$rel"
            [ -n "$_prof" ] || _prof=unknown
            [ -n "$_fam" ]  || _fam=unknown
            [ -n "$_xc" ]   || _xc=unknown
            [ -n "$_rl" ]   || _rl=unknown

            # Then overridden by the run's PROVENANCE.txt, when present.
            local v
            v=$(_idx_prov "$f" functional.requested); [ -n "$v" ] && _xc=$v
            v=$(_idx_prov "$f" family);               [ -n "$v" ] && _fam=$v
            v=$(_idx_prov "$f" relativity);           [ -n "$v" ] && _rl=$v
            v=$(_idx_prov "$f" profile);              [ -n "$v" ] && _prof=$v
            v=$(_idx_prov "$f" engine.id)

            local _eng
            if [ -n "$v" ]; then
                _eng=$v
            else
                _eng=${PROF_ENGINE[$_prof]:-${PROF_GENERATOR[$_prof]:-unknown}}
            fi

            # Format from the file name suffix, disambiguated by the profile.
            # cvt_detect reads the file to be certain; the index does not
            # need that, and calling it per file was one more cost on top of
            # the ones above.
            #
            # The profile's own declaration wins: a profile that asks for
            # paw-xml and writes a .xml gets paw-xml, not the generic xml.
            # When the extension is not one the profile declares -- a stray
            # file, or one from an older run -- the generic map below is the
            # fallback, and if that misses too the extension itself is used.
            local ext=${name##*.}
            local fmt=unknown
            if [ -n "${PF_EXT2FMT["$_prof|$ext"]:-}" ]; then
                fmt=${PF_EXT2FMT["$_prof|$ext"]}
            else
                case $ext in
                    UPF|upf|UPF1|upf1) fmt=upf ;;
                    psp8)              fmt=psp8 ;;
                    psml)              fmt=psml ;;
                    vps)               fmt=vps ;;
                    gth)               fmt=gth ;;
                    cpi)               fmt=cpi ;;
                    fhi)               fmt=fhi ;;
                    xml)               fmt=xml ;;
                    abinit)            fmt=abinit ;;
                    cpmd)              fmt=cpmd ;;
                    psp)               fmt=psp ;;
                    psf)               fmt=psf ;;
                    recpot)            fmt=recpot ;;
                    ncpp)              fmt=ncpp ;;
                    teter)             fmt=teter ;;
                    casino)            fmt=casino ;;
                    champ)             fmt=champ ;;
                    uspp)              fmt=uspp ;;
                    van)               fmt=van ;;
                    pao)               fmt=pao ;;
                    *)                 fmt=$ext ;;
                esac
            fi

            prov=""
            [ -f "$f.provenance" ] && prov="$rel.provenance"

            # How the bytes sit on disk, from the file itself.  A .gz suffix
            # is the only signal this needs: build-native-store.sh writes the
            # extension when it compresses, and nothing else adds or removes
            # one.  Hardcoding "gzip" here claimed every file was compressed
            # even when the format's extension was not one the build script
            # knew to compress -- and the server sets Content-Encoding from
            # this field, so a download of a .abinit or .cpmd file would have
            # been announced as gzip and arrived as plaintext.
            local enc=plain
            case $rel in *.gz) enc=gzip ;; esac

            id=${rel//\//_}
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$id" "$el" "$_xc" "$_fam" "$_rl" "$_eng" "$fmt" "$_prof" \
                "$enc" "$rel" "$size" "$sha" "$prov"
            total=$((total + 1))
        done < <(find -L "$dir" -type f \
                     ! -name '*.provenance' \
                     ! -name 'index.tsv*' \
                     ! -name 'PROVENANCE.txt' \
                     ! -name 'CITATION.txt' \
                     ! -name '.rejected*' \
                     ! -name '.*.tsv' \
                     ! -name 'LICENSE.txt' \
                     ! -name 'manifest' \
                     ! -name 'state.tsv' \
                     ! -name '*.log' \
                     ! -name '*.in' \
                     ! -name '*.out' \
                     ! -path '*/.rejected/*' \
                     ! -path '*/.stamps/*' \
                     ! -path '*/logs/*' \
                     ! -path '*/reports/*' \
                     ! -path '*/tests/*' \
                     ! -path '*/inputs/*' \
                     -printf '%s\t%p\n' 2>/dev/null | sort -t$'\t' -k2)
    } > "$dir/index.tsv.new" && mv "$dir/index.tsv.new" "$dir/index.tsv"

    ok "indexed $total native file(s) (sha256: $computed computed, $reused reused)"
}


http_native_json() {   # from one index line on stdin
    local id el xc fam rl eng fmt profile enc path size sha prov
    IFS=$'\t' read -r id el xc fam rl eng fmt profile enc path size sha prov
    # `encoding` is how the bytes sit on disk, not what they are: a client
    # that does not know the file is gzipped will save gzip bytes under a
    # .UPF name. `profile` is what makes "the same thing SSSP ships" an
    # answerable question.
    printf '{"id":%s,"element":%s,"xc":%s,"family":%s,"relativity":%s,"engine":%s,"format":%s,"profile":%s,"encoding":%s,"size":%s,"sha256":%s,"has_provenance":%s}\n' \
        "$(http_json_str "$id")" "$(http_json_str "$el")" "$(http_json_str "$xc")" \
        "$(http_json_str "$fam")" "$(http_json_str "$rl")" "$(http_json_str "$eng")" \
        "$(http_json_str "$fmt")" "$(http_json_str "$profile")" \
        "$(http_json_str "$enc")" "${size:-0}" "$(http_json_str "$sha")" \
        "$( [ -n "$prov" ] && echo true || echo false )"
}


http_h_native_list() {
    local idx; idx=$(http_native_index)
    if [ ! -f "$idx" ]; then
        # Degrading the way doctor does: say what is missing and why.
        http_error 503 native_index_unavailable \
            "No native-file index on this server." \
            '"fix":"run: pseudoforge native index"'
        return 0
    fi
    # One awk process for all lines.  The previous version forked ~14
    # subprocesses per line (http_native_json -> 13 http_json_str -> printf
    # + pf_json_escape).  With 13,117 files that is ~180,000 forks and
    # ~47 seconds per request; measured on a full store.  The fields are
    # tab-separated, have no quotes or backslashes in practice (element
    # symbols, xc names, format names), and the only field that could
    # contain anything interesting is `path`, which we escape.
    awk -F'\t' '
        function esc(s) {
            gsub(/\\/, "\\\\", s)
            gsub(/"/, "\\\"", s)
            gsub(/\r/, "\\r", s)
            gsub(/\t/, "\\t", s)
            return s
        }
        BEGIN { printf "[" ; first = 1 }
        !/^#/ && $1 !~ /_rejected_/ {
            if (!first) printf ","
            first = 0
            printf "\n{\"id\":\"%s\",\"element\":\"%s\",\"xc\":\"%s\",\"family\":\"%s\",\"relativity\":\"%s\",\"engine\":\"%s\",\"format\":\"%s\",\"profile\":\"%s\",\"encoding\":\"%s\",\"size\":%s,\"sha256\":\"%s\",\"has_provenance\":%s}",
                esc($1), esc($2), esc($3), esc($4), esc($5), esc($6),
                esc($7), esc($8), esc($9), ($11==""?0:$11), esc($12),
                ($13==""?"false":"true")
        }
        END { printf "\n]\n" }
    ' "$idx"
}

http_h_native_one() {
    local idx line; idx=$(http_native_index)
    [ -f "$idx" ] || { http_error 503 native_index_unavailable "No native-file index on this server."; return 0; }
    line=$(awk -F'\t' -v id="$HTTP_PARAM" '$1 == id { print; exit }' "$idx")
    if [ -z "$line" ]; then
        http_error 404 not_found "No native file with id: $HTTP_PARAM"
        return 0
    fi
    printf '%s' "$line" | http_native_json
}

http_h_provenance() {
    local id=$HTTP_PARAM
    [ -n "$id" ] || {
        http_error 400 bad_request "A file id is required."
        return 0
    }
    if ! provenance_for "$id"; then
        http_error 404 not_found "No native file or provenance found for: $id"
        return 0
    fi
    provenance_render_json
}

# ---------------------------------------------------------------------------
# Convert.  The converter runs here; the engines do not.
#
# Body: {"id":"<native id>","to":"<format>"}
# ---------------------------------------------------------------------------
http_h_convert() {
    local body=${1:-} id to idx line kind note from path outdir made
    [ -n "$body" ] && [ -f "$body" ] || {
        http_error 400 bad_request "A JSON body with \"id\" and \"to\" is required."; return 0; }

    id=$(http_body_field "$body" id)
    to=$(http_body_field "$body" to)
    [ -n "$id" ] && [ -n "$to" ] || {
        http_error 400 bad_request "Both \"id\" and \"to\" are required."; return 0; }

    idx=$(http_native_index)
    [ -f "$idx" ] || { http_error 503 native_index_unavailable "No native-file index on this server."; return 0; }
    line=$(awk -F'	' -v i="$id" '$1 == i { print; exit }' "$idx")
    [ -n "$line" ] || { http_error 404 not_found "No native file with id: $id"; return 0; }

    from=$(native_field format "$line")
    path=$PF_NATIVE_DIR/$(native_field path "$line")

    # The registry is consulted only to choose a status code -- which is an
    # HTTP concern and belongs here.  Whether the conversion is possible, and
    # whether it is refused, is cvt_convert's decision, and it is not taken
    # twice: a second copy of that judgement here is exactly the duplication
    # the four-interface rule exists to prevent.
    kind=${CVT_KIND[$from:$to]:-}
    note=${CVT_NOTE[$from:$to]:-}
    if [ -z "$kind" ]; then
        http_error 400 no_such_path "There is no conversion from $from to $to."             "\"known\":$(cvt_list_paths | while IFS= read -r k; do http_json_str "$k"; printf '
'; done | http_json_array)"
        return 0
    fi
    if [ "$kind" = refused ]; then
        HTTP_STATUS=409
        printf '{"error":%s,"from":%s,"to":%s,"kind":"refused","refusal":%s,"reason":%s}
'             "$(http_json_str conversion_refused)"             "$(http_json_str "$from")" "$(http_json_str "$to")"             "$(http_json_str "${CVT_REFUSAL[$from:$to]:-physics}")"             "$(http_json_str "$note")"
        return 0
    fi
    if ! cvt_tool_available "${CVT_TOOL[$from:$to]:-}" 2>/dev/null; then
        http_error 503 converter_unavailable             "The tool for $from to $to is not installed on this server."             "\"tool\":$(http_json_str "${CVT_TOOL[$from:$to]:-unknown}")"
        return 0
    fi

    # One directory per source id, so two conversions of different files to
    # the same format cannot collide on a name.
    outdir=$PF_CACHE_DIR/$id
    mkdir -p "$outdir" 2>/dev/null

    pf_sink_use capture; pf_sink_reset
    made=$(cvt_convert "$path" "$to" "$outdir" 2>/dev/null)
    local rc=$?
    local warns; warns=$(pf_sink_filter warn | paste -sd'; ' -)
    local errs;  errs=$(pf_sink_filter error | head -1)
    pf_sink_use null

    if [ "$rc" != 0 ] || [ -z "$made" ] || [ ! -f "$made" ]; then
        http_error 500 conversion_failed "The conversion did not produce a file."             "\"detail\":$(http_json_str "${errs:-unknown}")"
        return 0
    fi

    HTTP_STATUS=200
    printf '{"id":%s,"from":%s,"to":%s,"kind":%s,"tool":%s,"size":%s,"download":%s,"warnings":%s}
'         "$(http_json_str "$id")" "$(http_json_str "$from")" "$(http_json_str "$to")"         "$(http_json_str "$kind")" "$(http_json_str "${CVT_TOOL[$from:$to]:-}")"         "$(stat -c%s "$made" 2>/dev/null || echo 0)"         "$(http_json_str "/api/download/$id/$(basename "$made")")"         "$(http_json_str "${warns:-}")"
}

# A field from a small JSON body, without a JSON parser in the core.  The
# bodies this accepts are flat objects of string values; anything else is
# rejected rather than half-understood.
http_body_field() {   # http_body_field <file> <key>
    awk -v k="$2" '
        { gsub(/\r/, ""); line = line $0 }
        END {
            pat = "\"" k "\"[[:space:]]*:[[:space:]]*\""
            if (match(line, pat)) {
                rest = substr(line, RSTART + RLENGTH)
                if (match(rest, /^[^"]*/)) print substr(rest, 1, RLENGTH)
            }
        }' "$1"
}

http_h_download() {
    # The transport serves the bytes; this says where they are and how big,
    # so the server never builds a path out of an id itself -- which is how a
    # download endpoint turns into a directory traversal.
    local id=$HTTP_PARAM idx line path
    case $id in
        *..*|/*) http_error 400 bad_request "Bad file id."; return 0 ;;
    esac

    # A conversion lands in cache/<source-id>/<name>; a native file is in the
    # index.  Try the cache first, since that is what /api/convert hands out.
    if [ -f "$PF_CACHE_DIR/$id" ]; then
        path=$PF_CACHE_DIR/$id
        HTTP_STATUS=200
        printf '{"id":%s,"path":%s,"size":%s,"cached":true}
'             "$(http_json_str "$id")" "$(http_json_str "$path")"             "$(stat -c%s "$path" 2>/dev/null || echo 0)"
        return 0
    fi

    idx=$(http_native_index)
    [ -f "$idx" ] || { http_error 503 native_index_unavailable "No native-file index on this server."; return 0; }
    line=$(awk -F'	' -v i="$id" '$1 == i { print; exit }' "$idx")
    [ -n "$line" ] || { http_error 404 not_found "No file with id: $id"; return 0; }
    path=$PF_NATIVE_DIR/$(native_field path "$line")
    HTTP_STATUS=200
    printf '{"id":%s,"path":%s,"size":%s,"cached":false}
'         "$(http_json_str "$id")" "$(http_json_str "$path")"         "$(stat -c%s "$path" 2>/dev/null || echo 0)"
}

# ---------------------------------------------------------------------------
# Validate.  Structural checks only -- they need no engine, which is why this
# endpoint can exist on a machine that has none.
# ---------------------------------------------------------------------------
http_h_validate() {
    local body=${1:-}
    [ -n "$body" ] && [ -f "$body" ] || {
        http_error 400 bad_request "Upload a pseudopotential file as the request body."; return 0; }

    pf_sink_use capture; pf_sink_reset
    local rc=0 out line
    out=$(upf_validate_any "$body" 2>&1) || rc=$?
    while IFS= read -r line; do
        case $line in
            ERROR:*)   pf_emit error "$(trim "${line#ERROR:}")" ;;
            WARNING:*) pf_emit warn  "$(trim "${line#WARNING:}")" ;;
            WARN:*)    pf_emit warn  "$(trim "${line#WARN:}")" ;;
            NOTE:*)    pf_emit info  "$(trim "${line#NOTE:}")" ;;
        esac
    done <<< "$out"
    local errs warns
    errs=$(pf_sink_filter error | while IFS= read -r l; do http_json_str "$l"; printf '\n'; done | http_json_array)
    warns=$(pf_sink_filter warn | while IFS= read -r l; do http_json_str "$l"; printf '\n'; done | http_json_array)
    pf_sink_use null

    HTTP_STATUS=200
    printf '{"valid":%s,"errors":%s,"warnings":%s}\n' \
        "$( [ "$rc" = 0 ] && echo true || echo false )" "$errs" "$warns"
}

# ---------------------------------------------------------------------------
# Generate -- refused, and the refusal is the feature.
# ---------------------------------------------------------------------------
http_h_generate() {
    HTTP_STATUS=501
    printf '{"error":"generation_not_available_here","message":"Generation runs on your machine, not on this server.","instructions":"Install PseudoForge and run: pseudoforge generate -e <element> -t <family> -p <profile> -x <functional>","install_url":%s}\n' \
        "$(http_json_str "$PF_INSTALL_URL")"
}
