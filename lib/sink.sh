# shellcheck shell=bash
# ---------------------------------------------------------------------------
# sink.sh -- where the core's messages go, and who decides how they look.
#
# The rule this file enforces: **no module in lib/ knows which interface is
# calling it.** A core function reports what happened; it does not print.
# Printing is a rendering decision, and rendering belongs to the interface.
#
# The design is a sink. Every message the core produces goes through one
# function, `pf_emit`, which hands a structured record to whichever sink the
# interface installed:
#
#     core module            sink.sh              interface
#     ------------           -------              ---------
#     warn "no deck"   -->   pf_emit warn ... -->  pf_sink_cli      prints
#                                              |  pf_sink_capture   records
#                                              |  pf_sink_json      serialises
#                                              \  pf_sink_null      discards
#
# Why a sink rather than return values threaded through every function: there
# are 551 call sites across seven reporting verbs in lib/, and they already
# funnel through a single `_log`. Replacing that one function decouples the
# whole core. Rewriting 551 call sites to pass status upward would touch every
# module, risk a silent behaviour change in each, and buy nothing the sink does
# not already give.
#
# The verbs -- info, ok, warn, error, debug, banner -- stay. They are the
# core's reporting API, not printing calls. What changed is that they no longer
# decide where anything goes.
#
# Data is separate and already structured: core functions write their results
# to stdout as records (tab-separated fields, one per line) and signal success
# with an exit status. Messages go to the sink; data goes to stdout; status is
# the return code. An interface reads all three.
# ---------------------------------------------------------------------------

# The installed sink.  Interfaces set this; the core never reads it.
PF_SINK=${PF_SINK:-pf_sink_cli}

# Captured records, for the sinks that keep them.  One record per line:
#   <level>\t<message>
PF_SINK_RECORDS=${PF_SINK_RECORDS:-}

# ---------------------------------------------------------------------------
# pf_emit <level> <message...>
#
# The one place a core message passes through.  Levels: info, ok, warn, error,
# debug, banner.
# ---------------------------------------------------------------------------
pf_emit() {
    local level=$1; shift
    local message
    printf -v message '%s' "$*"

    # The log file is a property of the run, not of the interface, so it is
    # written here rather than in a sink -- every interface wants the same
    # record on disk.
    if [ -n "${PF_LOGFILE:-}" ]; then
        printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" \
            "$(upper "$level")" "$message" >> "$PF_LOGFILE"
    fi

    "$PF_SINK" "$level" "$message"
}

# ---------------------------------------------------------------------------
# pf_sink_cli -- the terminal.  This is what the CLI installs, and the default,
# so a script that loads the core and calls nothing else behaves as it always
# did.
# ---------------------------------------------------------------------------
pf_sink_cli() {
    local level=$1 message=$2 colour tag

    case $level in
        banner)
            [ "${PF_QUIET:-0}" = 1 ] && return 0
            printf '\n%s== %s ==%s\n' "$C_BOLD$C_CYAN" "$message" "$C_RESET" >&2
            return 0 ;;
        debug)
            [ "${PF_VERBOSE:-0}" = 1 ] || return 0
            colour=$C_DIM; tag=DEBUG ;;
        info)  colour=$C_BLUE;   tag=INFO ;;
        ok)    colour=$C_GREEN;  tag=OK ;;
        warn)  colour=$C_YELLOW; tag=WARN ;;
        error) colour=$C_RED;    tag=ERROR ;;
        *)     colour=$C_RESET;  tag=$(upper "$level") ;;
    esac

    # Quiet suppresses everything except errors: a run redirected to a file
    # still has to say why it failed.
    [ "${PF_QUIET:-0}" = 1 ] && [ "$tag" != ERROR ] && return 0
    printf '%s%-5s%s %s\n' "$colour" "$tag" "$C_RESET" "$message" >&2
}

# ---------------------------------------------------------------------------
# pf_sink_capture -- keep the records, print nothing.
#
# What a test harness and the TUI both want: the TUI renders the captured
# records into a panel when an operation finishes, rather than letting them
# scribble over a whiptail screen mid-draw.
# ---------------------------------------------------------------------------
pf_sink_capture() {
    PF_SINK_RECORDS="${PF_SINK_RECORDS}$1	$2
"
}

# ---------------------------------------------------------------------------
# pf_sink_json -- one JSON object per record, on stdout.
#
# Line-delimited rather than one array, so a long operation streams instead of
# buffering, and a truncated response is still parseable up to the cut.
# ---------------------------------------------------------------------------
pf_sink_json() {
    printf '{"level":"%s","message":"%s"}\n' "$1" "$(pf_json_escape "$2")"
}

pf_sink_null() { :; }

# Minimal JSON string escaping: the characters a message can actually contain.
# Paths carry backslashes on some systems and messages carry quotes, and either
# unescaped produces output no parser will read.
pf_json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
                           -e 's/	/\\t/g' -e 's/\r//g'
}

# ---------------------------------------------------------------------------
# Interface control.
# ---------------------------------------------------------------------------

# pf_sink_use <cli|capture|json|null> -- install a sink.
pf_sink_use() {
    case $1 in
        cli)     PF_SINK=pf_sink_cli ;;
        capture) PF_SINK=pf_sink_capture ;;
        json)    PF_SINK=pf_sink_json ;;
        null)    PF_SINK=pf_sink_null ;;
        *) return 1 ;;
    esac
    return 0
}

pf_sink_reset()   { PF_SINK_RECORDS=""; }
pf_sink_records() { printf '%s' "$PF_SINK_RECORDS"; }

# Records of one level, messages only.  Used by interfaces that want to show
# "3 warnings" without re-parsing.
pf_sink_filter() {
    local want=$1
    printf '%s' "$PF_SINK_RECORDS" | awk -F'\t' -v w="$want" '$1 == w { print $2 }'
}

pf_sink_count() {
    local want=${1:-}
    if [ -z "$want" ]; then printf '%s\n' "$(printf '%s' "$PF_SINK_RECORDS" | grep -c .)"
    else printf '%s\n' "$(pf_sink_filter "$want" | grep -c .)"; fi
}

# Did anything go wrong?  An interface asks this instead of scraping text.
pf_sink_failed() { [ "$(pf_sink_count error)" -gt 0 ]; }

# ---------------------------------------------------------------------------
# pf_emit_stream <level> [< file]
#
# Report many lines at once -- a build log excerpt, a tool's output.  Core
# modules used to do `tail -20 "$log" >&2`, which writes straight to a terminal
# and is invisible to any interface that is not one.
# ---------------------------------------------------------------------------
pf_emit_stream() {
    local level=${1:-debug} line
    while IFS= read -r line; do
        pf_emit "$level" "$line"
    done
}

# ---------------------------------------------------------------------------
# pf_confirm <question>
#
# Ask a yes/no question -- or rather, ask the *interface* to ask it.
#
# A core module must never read from the terminal.  build.sh and executor.sh
# both did: they printed a prompt and blocked on `read`.  On a CLI that is
# merely impolite; behind a web API it hangs the request, and in a test it
# hangs the suite.
#
# The interface supplies the answer:
#
#   PF_CONFIRM=pf_confirm_tty      ask on the terminal   (CLI, default)
#   PF_CONFIRM=pf_confirm_assume   never ask; use PF_ASSUME (TUI, API, tests)
#
# The default when nothing is installed and there is no terminal is "no",
# because the questions guarded by this are installs and overwrites.
# ---------------------------------------------------------------------------
PF_CONFIRM=${PF_CONFIRM:-pf_confirm_tty}
PF_ASSUME=${PF_ASSUME:-no}

pf_confirm() { "$PF_CONFIRM" "$*"; }

pf_confirm_tty() {
    local reply
    [ -t 0 ] || { pf_emit debug "not a terminal; assuming no: $*"; return 1; }
    printf '%s [y/N] ' "$*" >&2
    read -r reply || return 1
    case $reply in [Yy]*) return 0 ;; *) return 1 ;; esac
}

pf_confirm_assume() {
    pf_emit debug "assuming ${PF_ASSUME}: $*"
    case $(lower "$PF_ASSUME") in yes|y|1|true) return 0 ;; *) return 1 ;; esac
}

pf_confirm_use() {
    case $1 in
        tty)    PF_CONFIRM=pf_confirm_tty ;;
        assume) PF_CONFIRM=pf_confirm_assume ;;
        *) return 1 ;;
    esac
}
