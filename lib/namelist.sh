# shellcheck shell=bash
# ---------------------------------------------------------------------------
# namelist.sh -- surgical editing of Fortran namelists inside ld1.x decks.
#
# An ld1.x generation deck looks like
#
#      &input
#        title='Fe',
#        ...
#      /
#      &inputp
#        ...
#      /
#      6
#      3S  1  0  2.00  0.00  0.70  1.20  0.0
#      ...
#
# so the file is "two namelists plus a card block".  Everything here operates
# on that structure without disturbing a single byte it was not asked to
# change, which is what keeps PSlibrary-derived decks faithful.
#
# The implementation is pure bash on purpose.  A deck is a few dozen lines, but
# a full periodic-table run edits hundreds of them; forking awk and mv for every
# keyword turns a few seconds of work into minutes.
# ---------------------------------------------------------------------------

declare -ga NML_LINES=()

# nml_read <file> -- load a deck into NML_LINES
nml_read() {
    NML_LINES=()
    mapfile -t NML_LINES < "$1"
}

# nml_write <file> -- write NML_LINES back out
nml_write() {
    printf '%s\n' "${NML_LINES[@]}" > "$1"
}

# Is this line "<key> = ..." for the given key?  Fortran is case-insensitive.
_nml_is_key() {
    local line=${1#"${1%%[![:space:]]*}"}   # strip leading blanks
    local key=${2,,}
    line=${line,,}
    case $line in
        "$key"=*|"$key"' '*=*)
            # guard against a prefix match: rcut= must not match rcutus=
            line=${line#"$key"}
            line=${line#"${line%%[![:space:]]*}"}
            [ "${line:0:1}" = "=" ] ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# nml_get <file> <namelist> <key>  -> value, quotes and trailing comma stripped
# ---------------------------------------------------------------------------
nml_get() {
    local file=$1 nml=$2 key=$3
    local line stripped inside=0 v
    while IFS= read -r line; do
        stripped=${line#"${line%%[![:space:]]*}"}
        stripped=${stripped%"${stripped##*[![:space:]]}"}
        if [ "${stripped,,}" = "&${nml,,}" ]; then inside=1; continue; fi
        [ "$inside" = 1 ] || continue
        [ "$stripped" = "/" ] && break
        if _nml_is_key "$line" "$key"; then
            v=${stripped#*=}
            v=${v%,}
            v=${v#"${v%%[![:space:]]*}"}
            v=${v%"${v##*[![:space:]]}"}
            v=${v#\'}; v=${v%\'}
            printf '%s\n' "$v"
            return 0
        fi
    done < "$file"
    return 1
}


# ---------------------------------------------------------------------------
# nml_set <file> <namelist> <key> <value>
#   Replaces the key in place if present, otherwise appends it as the last
#   entry of the namelist.  <value> is written verbatim, so quote strings
#   yourself:  nml_set deck inputp author "'PseudoForge'"
# ---------------------------------------------------------------------------
nml_set() {
    local file=$1 nml=$2 key=$3 val=$4
    local i n line stripped indent inside=0 replaced=0
    nml_read "$file"
    n=${#NML_LINES[@]}
    for ((i = 0; i < n; i++)); do
        line=${NML_LINES[i]}
        stripped=${line#"${line%%[![:space:]]*}"}
        stripped=${stripped%"${stripped##*[![:space:]]}"}
        if [ "$inside" = 0 ]; then
            [ "${stripped,,}" = "&${nml,,}" ] && inside=1
            continue
        fi
        if [ "$stripped" = "/" ]; then
            [ "$replaced" = 1 ] || NML_LINES=("${NML_LINES[@]:0:i}" "   $key=$val," "${NML_LINES[@]:i}")
            nml_write "$file"
            return 0
        fi
        if _nml_is_key "$line" "$key"; then
            indent=${line%%[![:space:]]*}
            NML_LINES[i]="$indent$key=$val,"
            replaced=1
        fi
    done
    nml_write "$file"
    return 0
}

# nml_unset <file> <namelist> <key>
nml_unset() {
    local file=$1 nml=$2 key=$3
    local i n line stripped inside=0 changed=0
    local -a out=()
    nml_read "$file"
    n=${#NML_LINES[@]}
    for ((i = 0; i < n; i++)); do
        line=${NML_LINES[i]}
        stripped=${line#"${line%%[![:space:]]*}"}
        stripped=${stripped%"${stripped##*[![:space:]]}"}
        if [ "$inside" = 1 ]; then
            [ "$stripped" = "/" ] && inside=0
            if [ "$inside" = 1 ] && _nml_is_key "$line" "$key"; then changed=1; continue; fi
        elif [ "${stripped,,}" = "&${nml,,}" ]; then
            inside=1
        fi
        out+=("$line")
    done
    [ "$changed" = 1 ] || return 0
    NML_LINES=("${out[@]}")
    nml_write "$file"
}

# ---------------------------------------------------------------------------
# The card block: everything after the final "/" line.  The first non-blank
# line there is the card count; the rest are the wavefunction cards.
# ---------------------------------------------------------------------------

# _nml_split <file> -- fills NML_HEAD (through the last "/") and NML_CARDS
declare -ga NML_HEAD=() NML_CARDS=()
_nml_split() {
    local i n last=-1 line stripped
    nml_read "$1"
    n=${#NML_LINES[@]}
    for ((i = 0; i < n; i++)); do
        stripped=${NML_LINES[i]}
        stripped=${stripped#"${stripped%%[![:space:]]*}"}
        stripped=${stripped%"${stripped##*[![:space:]]}"}
        [ "$stripped" = "/" ] && last=$i
    done
    NML_HEAD=(); NML_CARDS=()
    [ "$last" -ge 0 ] || return 1
    for ((i = 0; i <= last; i++)); do NML_HEAD+=("${NML_LINES[i]}"); done
    local seen_count=0
    for ((i = last + 1; i < n; i++)); do
        line=${NML_LINES[i]}
        [ -n "${line//[[:space:]]/}" ] || continue
        if [ "$seen_count" = 0 ]; then seen_count=1; continue; fi   # the count line
        NML_CARDS+=("$line")
    done
    return 0
}

# nml_cards <file> -> the wavefunction card lines, without the leading count
nml_cards() {
    _nml_split "$1" || return 1
    [ ${#NML_CARDS[@]} -gt 0 ] && printf '%s\n' "${NML_CARDS[@]}"
    return 0
}

# nml_card_count <file>
nml_card_count() {
    _nml_split "$1" || return 1
    printf '%s\n' "${#NML_CARDS[@]}"
}

# nml_set_cards <file> <cardfile> -- replace the card block, rewriting the count
nml_set_cards() {
    local file=$1 cards=$2 line
    local -a new=()
    _nml_split "$file" || return 1
    while IFS= read -r line; do
        [ -n "${line//[[:space:]]/}" ] && new+=("$line")
    done < "$cards"
    NML_LINES=("${NML_HEAD[@]}" "${#new[@]}")
    [ ${#new[@]} -gt 0 ] && NML_LINES+=("${new[@]}")
    nml_write "$file"
}

# nml_add_card <file> <card line>
nml_add_card() {
    local file=$1 line=$2
    _nml_split "$file" || return 1
    NML_CARDS+=("$line")
    NML_LINES=("${NML_HEAD[@]}" "${#NML_CARDS[@]}" "${NML_CARDS[@]}")
    nml_write "$file"
}
