# shellcheck shell=bash
# ---------------------------------------------------------------------------
# core.sh -- logging, error handling and small shared helpers.
# ---------------------------------------------------------------------------

# Version 1.3.x -- x increments with each revision of the tool.
PSEUDOFORGE_VERSION="1.3.3"
PSEUDOFORGE_NAME="PseudoForge"
PSEUDOFORGE_TAGLINE="multi-engine pseudopotential generator and validator"
PSEUDOFORGE_AUTHOR="Mohammad H. Amirkhani"
PSEUDOFORGE_URL="https://amirkhani.me"

# ---- terminal colours (disabled when not a tty or when NO_COLOR is set) ----
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m';  C_BOLD=$'\033[1m';   C_DIM=$'\033[2m'
    C_RED=$'\033[31m';   C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m';  C_CYAN=$'\033[36m'
else
    C_RESET=; C_BOLD=; C_DIM=; C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=; C_CYAN=
fi

PF_QUIET=${PF_QUIET:-0}
PF_VERBOSE=${PF_VERBOSE:-0}
PF_LOGFILE=${PF_LOGFILE:-}

# ---------------------------------------------------------------------------
# Reporting.
#
# These six are the core's reporting API.  They do not print: every one hands a
# structured record to pf_emit, which passes it to whichever sink the interface
# installed (see lib/sink.sh).  That is what lets the same core back the CLI,
# the TUI and the web API without any module knowing which is calling.
#
# The bodies used to write to stderr directly.  Nothing else changed -- all 551
# call sites across lib/ keep their names and their arguments -- because they
# already funnelled through a single _log, and replacing that one function was
# enough to decouple the whole core.
# ---------------------------------------------------------------------------
# core.sh owns the reporting verbs, so it guarantees the sink they depend on.
# Without this, anything that sources core.sh alone -- and several test
# harnesses do, in one-line subshells -- gets "pf_emit: command not found" the
# first time it reports anything.
if ! declare -F pf_emit >/dev/null 2>&1; then
    _pf_core_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    # shellcheck source=sink.sh
    [ -f "$_pf_core_dir/sink.sh" ] && . "$_pf_core_dir/sink.sh"
fi

info()   { pf_emit info   "$@"; }
ok()     { pf_emit ok     "$@"; }
warn()   { pf_emit warn   "$@"; }
error()  { pf_emit error  "$@"; }
debug()  { pf_emit debug  "$@"; return 0; }
banner() { pf_emit banner "$@"; }

# die stays a control-flow decision rather than a rendering one: it reports and
# stops.  An interface that must not exit the process (the web API) installs a
# sink and calls the operation in a subshell.
die() { error "$@"; exit 1; }

# ---- small utilities ------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

# Absolute path of a possibly relative path, without requiring realpath.
abspath() {
    local p=$1
    case $p in
        /*|[A-Za-z]:[/\]*) printf '%s\n' "$p" ;;
        *)                  printf '%s\n' "$PWD/$p" ;;
    esac
}

# Case conversion.  PseudoForge requires bash 4, so use the builtins rather than
# forking tr: these run inside tight loops over the whole periodic table.
lower() { printf '%s\n' "${1,,}"; }
upper() { printf '%s\n' "${1^^}"; }

# trim leading/trailing whitespace
trim() { printf '%s\n' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

# Is $1 present in the remaining arguments?
in_list() {
    local needle=$1; shift
    local x
    for x in "$@"; do [ "$x" = "$needle" ] && return 0; done
    return 1
}

# Portable epoch seconds.
now() { date +%s; }

# Human-readable duration from a number of seconds.
human_time() {
    local s=$1
    if   [ "$s" -lt 60 ];   then printf '%ds\n' "$s"
    elif [ "$s" -lt 3600 ]; then printf '%dm%02ds\n' $((s/60)) $((s%60))
    else                         printf '%dh%02dm\n' $((s/3600)) $(((s%3600)/60))
    fi
}

# Escape a string for safe inclusion in HTML text nodes / attributes.
html_escape() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

# Escape a field for CSV (RFC 4180).
csv_escape() {
    case $1 in
        *[,\"$'\n']*) printf '"%s"' "$(printf '%s' "$1" | sed 's/"/""/g')" ;;
        *)            printf '%s' "$1" ;;
    esac
}

# Atomically replace a file with content read from stdin.
write_atomic() {
    local dest=$1 tmp="$1.tmp.$$"
    cat > "$tmp" && mv -f "$tmp" "$dest"
}

# Fork-free absolute path: sets REPLY instead of writing to stdout.
REPLY=
abspath_r() {
    case $1 in
        /*|[A-Za-z]:[/\]*) REPLY=$1 ;;
        *)                  REPLY=$PWD/$1 ;;
    esac
}

# Where a user own profiles and functionals live.  Kept apart from PF_DATA
# so that updating PseudoForge cannot overwrite them, and so "pseudoforge profile
# new" never has to write into the installation.
PF_USER_DATA=${PF_USER_DATA:-$HOME/.pseudoforge}
