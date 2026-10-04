# shellcheck shell=bash
# ---------------------------------------------------------------------------
# project.sh -- the on-disk layout of a PseudoForge run, and its state database.
#
#   <project>/
#     inputs/     generated ld1.x decks (.in)
#     pseudos/    finished .UPF files            <- the deliverable
#     tests/      transferability results and pw.x cutoff scans
#     logs/       one log per element, plus PseudoForge.log
#     reports/    summary.txt / summary.csv / summary.html / summary.json
#     manifest    the exact settings this project was created with
#     state.tsv   per-element status, so a re-run can resume
#
# The layout is flat and predictable on purpose: `cp pseudos/*.UPF` into a QE
# pseudo_dir is the whole "installation" step.
# ---------------------------------------------------------------------------

PROJECT_DIR=
PROJECT_STATE=

# Columns of state.tsv
STATE_COLS="element family profile xc rel variant upf status attempts seconds message"

project_init() {   # project_init <dir>
    PROJECT_DIR=$(abspath "$1")
    PROJECT_STATE=$PROJECT_DIR/state.tsv
    mkdir -p "$PROJECT_DIR"/{inputs,pseudos,tests,logs,reports} || die "cannot create $PROJECT_DIR"
    [ -f "$PROJECT_STATE" ] || printf '#%s\n' "$(printf '%s\t' $STATE_COLS | sed 's/\t$//')" > "$PROJECT_STATE"
    PF_LOGFILE=$PROJECT_DIR/logs/pseudoforge.log
}

# A default project name that encodes the physics, so several runs can live
# side by side without colliding.
project_default_name() {
    printf '%s-%s-%s-%s\n' "${SPEC[profile]}" "${SPEC[family]}" \
           "$(xc_tag "${SPEC[xc]}" "${SPEC[rel]}")" "$(date +%Y%m%d-%H%M%S)"
}

project_write_manifest() {
    {
        printf '# PseudoForge %s run manifest\n' "$PSEUDOFORGE_VERSION"
        printf 'created=%s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
        printf 'host=%s\n' "$(uname -n 2>/dev/null || echo unknown)"
        printf 'ld1_bin=%s\n' "${LD1_BIN:-}"
        printf 'ld1_version=%s\n' "$(deps_ld1_version 2>/dev/null || echo unknown)"
        printf 'pw_bin=%s\n' "${PW_BIN:-}"
        printf 'elements=%s\n' "$*"
        spec_dump
        printf 'xc_generator=%s\n' "$(xc_generator "${SPEC[xc]}")"
        printf 'xc_qe_string=%s\n' "$(xc_qe_string "${SPEC[xc]}")"
        printf 'xc_status=%s\n' "${XC_STATUS[${SPEC[xc]}]}"
        printf 'profile_provenance=%s\n' "${PROF_PROVENANCE[${SPEC[profile]}]}"
    } > "$PROJECT_DIR/manifest"
}

# ---------------------------------------------------------------------------
# State database.  One line per element; last write wins.  Parallel workers
# each append to their own shard and the parent merges, which avoids relying on
# atomic appends from many processes at once.
# ---------------------------------------------------------------------------

state_shard() { printf '%s/logs/.state.%s\n' "$PROJECT_DIR" "$1"; }

state_record() {   # state_record <element> <family> <profile> <xc> <rel> <variant> <upf> <status> <attempts> <seconds> <message>
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
           "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" >> "$(state_shard "$1")"
}

state_merge() {
    local shard
    for shard in "$PROJECT_DIR"/logs/.state.*; do
        [ -e "$shard" ] || continue
        cat "$shard" >> "$PROJECT_STATE"
        rm -f "$shard"
    done
    # Collapse to the last record per element, then order by atomic number so
    # reports read like a periodic table rather than like a completion race.
    local el keys=""
    for el in "${EL_ORDER[@]}"; do keys="$keys$el ${EL_Z[$el]}"$'\n'; done
    printf '%s' "$keys" | awk -F'\t' '
        NR == FNR { z[$1] = $2; next }
        /^#/      { if (!hdr++) print; next }
        NF        { line[$1] = $0 }
        END { n = 0
              for (k in line) { order[++n] = k }
              # insertion sort on Z; the list is at most the periodic table
              for (i = 2; i <= n; i++) {
                  v = order[i]; j = i - 1
                  while (j >= 1 && (z[order[j]] + 0) > (z[v] + 0)) { order[j+1] = order[j]; j-- }
                  order[j+1] = v
              }
              for (i = 1; i <= n; i++) print line[order[i]]
        }' FS=' ' - FS='\t' "$PROJECT_STATE" | write_atomic "$PROJECT_STATE"
}

state_status() {   # state_status <element> -> status or empty
    awk -F'\t' -v el="$1" '$1 == el { print $8 }' "$PROJECT_STATE" 2>/dev/null | tail -1
}

state_field() {    # state_field <element> <column-index>
    awk -F'\t' -v el="$1" -v c="$2" '$1 == el { print $c }' "$PROJECT_STATE" 2>/dev/null | tail -1
}

state_list() {     # state_list [status] -> element names
    local want=${1:-}
    awk -F'\t' -v w="$want" '!/^#/ && NF && (w == "" || $8 == w) { print $1 }' "$PROJECT_STATE" 2>/dev/null
}

state_count() { state_list "${1:-}" | wc -l | tr -d ' '; }

# Should this element be (re)run?  Resume skips elements whose UPF is on disk
# and passed validation last time.
state_should_run() {   # state_should_run <element>
    local el=$1 st upf
    [ "${RESUME:-1}" = 1 ] || return 0
    st=$(state_status "$el")
    case $st in
        ok|ok-warn)
            upf=$(state_field "$el" 7)
            # A .gz beside the plain name counts as the same file: the store
            # build gzips its output after the fact, and a later --resume
            # pass that looked only for the plain name saw the file missing
            # and regenerated it.  The gzip step then refused to overwrite
            # the existing .gz and the plaintext stayed behind, doubling the
            # store and making the index disagree with the disk.
            if [ -n "$upf" ] && {
                [ -f "$PROJECT_DIR/pseudos/$upf" ] ||
                [ -f "$PROJECT_DIR/pseudos/$upf.gz" ]
            }; then
                return 1
            fi
            ;;
    esac
    return 0
}
