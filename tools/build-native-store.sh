#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# build-native-store.sh -- pre-build everything the website serves.
#
# The website was shipped with an empty store, so "Download from this site"
# had nothing behind it and every request fell through to "build locally".
# That is what this fixes, and it is the only honest way to fix it: the VPS
# does not run engines -- not as an optimisation, not as a fallback -- so
# anything the site serves has to have been built somewhere else first. Here.
#
# What gets built
#
#   Every *library* profile, crossed with every family, functional and
#   relativity mode that profile declares for itself, for every element it
#   covers. Roughly 20,700 files.
#
# What does not, and why
#
#   `pseudoforge-auto` is the derived profile -- PseudoForge's own
#   construction, used when no published library covers the case. Pre-building
#   it would be pre-building the answer to "I want something custom", which is
#   not a thing that can be enumerated in advance. It stays a build-locally
#   answer.
#
#   Profiles marked `external` or `import-only` are other people's files. The
#   site links to the authors' own copy rather than rehosting it.
#
# Storage
#
#   Files are stored gzipped. They are text, they compress about 3x, and the
#   whole set drops from ~16 GB to ~5.5 GB -- which is the difference between
#   fitting on the 10 GB VPS disk and not. Nginx serves them with
#   `Content-Encoding: gzip` straight off disk, so the server spends no CPU
#   decompressing and the browser gets the original file.
#
# Running it
#
#   tools/build-native-store.sh                    build into the default store
#   tools/build-native-store.sh -o /srv/native     somewhere else
#   tools/build-native-store.sh -j 12              parallelism (default: nproc)
#   tools/build-native-store.sh --dry-run          print the plan, build nothing
#   tools/build-native-store.sh -p psl-high        one profile only
#
# It is resumable. Each (profile, family, xc, rel) combination writes a stamp
# when it finishes, and a re-run skips finished combinations; within a
# combination `generate --resume` skips elements that already have a file. Kill
# it and start it again and it picks up where it stopped.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
PSM=$ROOT/pseudoforge

STORE=${PF_NATIVE_DIR:-/var/lib/pseudoforge/native}
JOBS=$(nproc 2>/dev/null || echo 4)
DRY=0
ONLY=""
KEEP_UNCOMPRESSED=0

# Internal: `--check-file <store> <file>` checks one stored file against the
# label its directory gives it (<profile>/<family>/<xc>/<rel>/pseudos/) and
# prints "<file>\t<reason>" when they disagree. Used by the verify pass below
# through xargs, so 13,000 files are checked in parallel.
if [ "${1:-}" = --check-file ]; then
    store=$2 f=$3
    rel=${f#"$store"/}                     # profile/fam/xc/rel/pseudos/name
    IFS=/ read -r _p _fam xc rl _ <<<"$rel"
    export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
    for m in core sink config elements xc validate; do . "$ROOT/lib/$m.sh"; done
    pf_config_defaults >/dev/null 2>&1; pf_xc_load 2>/dev/null
    tmp=$(mktemp -d); name=${f##*/}
    case $f in *.gz) gunzip -c "$f" > "$tmp/${name%.gz}"; x=$tmp/${name%.gz} ;; *) x=$f ;; esac
    why=$(label_mismatch "$x" "$xc" "$rl")
    rm -rf "$tmp"
    [ -n "$why" ] && printf '%s\t%s\n' "$f" "$why"
    exit 0
fi

while [ $# -gt 0 ]; do
    case $1 in
        -o|--output)  shift; STORE=${1:-} ;;
        -j|--jobs)    shift; JOBS=${1:-4} ;;
        -p|--profile) shift; ONLY=${1:-} ;;
        --dry-run)    DRY=1 ;;
        --no-gzip)    KEEP_UNCOMPRESSED=1 ;;
        -h|--help)    sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)            printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
say()  { printf '  %s\n' "$*"; }
step() { printf '\n%s== %s%s\n' "$DIM" "$*" "$RESET"; }
warn_() { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$*"; }

export OMP_NUM_THREADS=1        # see memory: ld1.x spin-waits forever without it

# netlink_alive -- does the kernel still answer a network-configuration query?
# Asked the same way the probe it guards against must be: in the background,
# polled, abandoned if stuck -- `ip` blocked on rtnl_lock ignores signals too.
netlink_alive() {
    local p n=0
    ip -br link >/dev/null 2>&1 &
    p=$!
    while kill -0 "$p" 2>/dev/null && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
    if kill -0 "$p" 2>/dev/null; then
        kill -9 "$p" 2>/dev/null; disown "$p" 2>/dev/null
        return 1
    fi
    wait "$p" 2>/dev/null
    return 0
}

# Checked once before starting, so a machine that is already wedged is told
# so now rather than after the first hour.
if ! netlink_alive; then
    printf "  ! the kernel's networking lock is wedged ('ip link' does not return).\n" >&2
    printf '    Every engine that starts Open MPI would hang. From PowerShell run\n' >&2
    printf '    `wsl --shutdown`, then run this script again.\n' >&2
    exit 3
fi

# ---------------------------------------------------------------------------
# The plan, read off the profile declarations rather than hardcoded here. A
# list of combinations baked into this script would drift from the profiles
# the moment one gained a functional.
# ---------------------------------------------------------------------------
# Functionals the tool can actually select, from data/xc.tsv. A profile may
# declare more than that -- cp2k-gth lists olyp, hcth120 and hcth407, which
# CP2K does publish tables for and which the XC registry does not carry -- and
# a plan built from the declaration alone spends its time failing. The
# difference is reported rather than silently dropped: adding a functional to
# the registry is a physics change and not something a build script decides.
XC_KNOWN=$(awk -F'	' '!/^#/ && NF >= 1 { print $1 }' "$ROOT/data/xc.tsv" 2>/dev/null | tr '
' ' ')

# Family of each registered functional, read from the same file.  plan() uses
# this to apply the same engine constraints the CLI enforces, so a combination
# the CLI would refuse is not scheduled in the first place.
declare -A XC_FAMILY_OF
while IFS=$'\t' read -r id _tag _qe fam _rest; do
    [ -n "$id" ] || continue
    case $id in \#*) continue ;; esac
    XC_FAMILY_OF[$id]=$fam
done < "$ROOT/data/xc.tsv"
XC_DROPPED_FILE=$(mktemp)
trap 'rm -f "$XC_DROPPED_FILE"' EXIT

# Families each engine can make, read from the engine registry itself rather
# than restated here. A profile's `families` says what the *library publishes*;
# whether PseudoForge can *generate* one is a property of the profile's engine.
# The first full build tried gbrv/paw with USPP and pseudodojo/paw with
# ONCVPSP -- neither makes PAW -- and failed nine combinations that were never
# possible. GBRV's and PseudoDojo's PAW sets come from other codes.
eng_families() {   # eng_families <engine>
    sed -n "s/^ *ENG_FAMILIES\[$1\]=\"\([^\"]*\)\".*/\1/p" "$ROOT/lib/engines.sh" | head -1
}
FAM_DROPPED_FILE=$(mktemp)
trap 'rm -f "$XC_DROPPED_FILE" "$FAM_DROPPED_FILE"' EXIT

plan() {
    local f id fams xcs rels prov fam xc rel eng can
    for f in "$ROOT"/data/profiles/*.profile; do
        id=$(sed -n 's/^id=//p'            "$f")
        fams=$(sed -n 's/^families=//p'    "$f")
        eng=$(sed -n 's/^engine=//p'       "$f" | head -1)
        can=$(eng_families "$eng")
        xcs=$(sed -n 's/^xc_available=//p' "$f")
        rels=$(sed -n 's/^rel_available=//p' "$f")
        prov=$(sed -n 's/^provenance=//p'  "$f")

        [ -n "$ONLY" ] && [ "$id" != "$ONLY" ] && continue

        # Other people's files. See the header.
        #
        # `derived` profiles are not pre-built on a full run -- see the
        # header for why -- but they ARE built when the caller names one
        # explicitly with -p. That is the case for a derived profile whose
        # output is enumerable in advance (a specific element, xc and rel,
        # from a specific engine) as opposed to the pseudoforge-auto case,
        # which is the answer to "I want something custom".
        case $prov in
            external|import-only) continue ;;
            derived) [ -z "$ONLY" ] && continue ;;
        esac
        # A profile that will not say what it covers cannot be enumerated.
        case " $xcs " in *" varies "*) continue ;; esac
        [ -n "$fams" ] && [ -n "$xcs" ] && [ -n "$rels" ] || continue

        for fam in $fams; do
            # Unknown engine: no filter, the old behaviour. Known engine that
            # cannot make this family: recorded and skipped.
            if [ -n "$can" ]; then
                case " $can " in
                    *" $fam "*) ;;
                    *) printf '%s\t%s\t%s\n' "$id" "$fam" "$eng" >> "$FAM_DROPPED_FILE"
                       continue ;;
                esac
            fi
            for xc in $xcs; do
                case " $XC_KNOWN " in
                    *" $xc "*) ;;
                    *) printf '%s	%s
' "$id" "$xc" >> "$XC_DROPPED_FILE"
                       continue ;;
                esac
                for rel in $rels; do
                    # AtomPAW's meta-GGA path is non-relativistic only: its
                    # relativistic solver has no meta-GGA branch, and cli.sh
                    # refuses the combination with a die().  Apply the same
                    # rule here so the plan does not schedule a run that will
                    # immediately fail.  Same source of truth -- data/xc.tsv.
                    if [ "$eng" = atompaw ] \
                       && [ "${XC_FAMILY_OF[$xc]:-}" = metaGGA ] \
                       && [ "$rel" != nonrel ]; then
                        continue
                    fi
                    printf '%s\t%s\t%s\t%s\n' "$id" "$fam" "$xc" "$rel"
                done
            done
        done
    done
}

# ---------------------------------------------------------------------------
step "the plan"

PLAN=$(plan)
n_combos=$(printf '%s\n' "$PLAN" | grep -c . || true)
[ "$n_combos" -gt 0 ] || { printf 'nothing to build\n' >&2; exit 1; }

say "store:   $STORE"
say "combos:  $n_combos  (profile x family x functional x relativity)"
say "jobs:    $JOBS"
say "gzip:    $( [ "$KEEP_UNCOMPRESSED" = 1 ] && echo no || echo yes )"

if [ -s "$FAM_DROPPED_FILE" ]; then
    printf '\n'
    warn_ "published by the library, not generatable by its engine here -- not built:"
    sort -u "$FAM_DROPPED_FILE" | while IFS="$(printf '\t')" read -r a b c; do
        say "      $a: $b (engine $c makes $(eng_families "$c" | tr ' ' ','))"
    done
    say "  The site links to the authors' own copy for these."
fi

if [ -s "$XC_DROPPED_FILE" ]; then
    printf '\n'
    warn_ "declared by a profile, absent from data/xc.tsv -- not built:"
    sort -u "$XC_DROPPED_FILE" | while IFS="	" read -r a b; do
        say "      $a: $b"
    done
    say "  These are real upstream functionals. Adding one to the registry is"
    say "  a physics change, and not this script's call."
fi

if [ "$DRY" = 1 ]; then
    printf '\n'
    printf '%s\n' "$PLAN" | awk -F'\t' '{ printf "  %-18s %-4s %-8s %s\n", $1, $2, $3, $4 }'
    exit 0
fi

mkdir -p "$STORE" || { printf 'cannot create %s\n' "$STORE" >&2; exit 1; }
STAMPS=$STORE/.stamps
mkdir -p "$STAMPS"

# ---------------------------------------------------------------------------
# Before building: the store is checked against the plan and against itself.
#
# 1. Prune. A combination on disk that is no longer in the plan -- because a
#    profile was corrected to declare only what its inputs produce -- is
#    removed with its stamp. Only on a full run: `-p X` must not delete other
#    profiles' work.
# 2. Verify. Every stored file is compared with the label its directory gives
#    it (label_mismatch in lib/validate.sh). One that disagrees is moved to
#    .rejected/ -- kept for inspection, never indexed -- and its combination
#    loses its stamp, so the build below makes it again, correctly.
#
# This is how the first store's 1,493 mislabelled files, and every VWN file
# built without exchange, leave it: by being checked, not by being remembered.
# ---------------------------------------------------------------------------
step "verifying the store"
if [ -z "$ONLY" ]; then
    pruned=0
    for d in "$STORE"/*/*/*/*/; do
        [ -d "$d" ] || continue
        c=${d#"$STORE"/}; c=${c%/}
        IFS=/ read -r p fa x r <<<"$c"
        if ! printf '%s\n' "$PLAN" | grep -qxF "$(printf '%s\t%s\t%s\t%s' "$p" "$fa" "$x" "$r")"; then
            rm -rf "$d" "${d%/}.log" "$STAMPS/$p.$fa.$x.$r"
            pruned=$((pruned + 1))
        fi
    done
    say "pruned:   $pruned combination(s) no longer in the plan"
fi

bad=$STORE/.rejected.tsv
find "$STORE" -path '*/pseudos/*' ! -path '*/rejected/*' -type f \
     \( -name '*.UPF' -o -name '*.upf' -o -name '*.vps' -o -name '*.gth' \
        -o -name '*.UPF.gz' -o -name '*.upf.gz' -o -name '*.vps.gz' -o -name '*.gth.gz' \) -print0 2>/dev/null \
    | xargs -0 -r -P "$JOBS" -n 1 "$0" --check-file "$STORE" > "$bad" 2>/dev/null
nbad=$(grep -c . "$bad" 2>/dev/null || true); nbad=${nbad:-0}
if [ "$nbad" -gt 0 ]; then
    while IFS=$'\t' read -r f why; do
        c=${f#"$STORE"/}; IFS=/ read -r p fa x r _ <<<"$c"
        mkdir -p "$STORE/.rejected/$p/$fa/$x/$r"
        mv -f "$f" "$STORE/.rejected/$p/$fa/$x/$r/" 2>/dev/null
        rm -f "$STAMPS/$p.$fa.$x.$r"
    done < "$bad"
    warn_ "rejected: $nbad file(s) whose header disagrees with their label (moved to .rejected/)"
    cut -f2 "$bad" | sed -E 's/[A-Z][a-z]?\.[^ ]*//g' | sort | uniq -c | sort -rn | head -8 \
        | while read -r n why; do say "      $n x  $why"; done
    say "  their combinations are rebuilt below"
else
    say "verified: every stored file matches its label"
fi

# ---------------------------------------------------------------------------
step "building"

t_all=$(date +%s)
done_n=0 skip_n=0 fail_n=0 i=0

while IFS=$'\t' read -r id fam xc rel; do
    [ -n "$id" ] || continue
    i=$((i + 1))
    key="$id.$fam.$xc.$rel"
    out=$STORE/$id/$fam/$xc/$rel

    if [ -f "$STAMPS/$key" ]; then
        skip_n=$((skip_n + 1))
        continue
    fi

    printf '  [%3d/%3d] %-18s %-4s %-8s %-7s ' "$i" "$n_combos" "$id" "$fam" "$xc" "$rel"
    t0=$(date +%s)
    # The log sits beside the project directory, so its parent has to exist
    # before the redirect -- `generate -o` creates $out, but not until after
    # the shell has already opened $out.log and failed.
    mkdir -p "$(dirname "$out")" 2>/dev/null

    # `-e all` means "every element this profile covers"; a profile that
    # covers none for this family says so and the combination is skipped
    # rather than counted as a failure.
    #
    # Run under a watchdog. One combination sat for three hours after all its
    # elements were built: a version probe in the report step had started
    # Open MPI, which blocked in the kernel on rtnl_lock -- WSL's networking
    # lock had wedged -- and a process in that state ignores every signal,
    # timeout(1) included. Nothing downstream moved.
    #
    # So the combination runs in its own session (setsid) and is polled, not
    # waited on. Past COMBO_TIMEOUT it is killed as a group; if the kernel's
    # networking lock is what is stuck, the build stops and says so, because
    # every later combination would hang the same way until WSL restarts.
    setsid "$PSM" generate -e all -p "$id" -t "$fam" -x "$xc" -r "$rel" \
        -j "$JOBS" --resume -o "$out" >"$out.log" 2>&1 < /dev/null &
    gpid=$!
    waited=0 timed_out=0
    while kill -0 "$gpid" 2>/dev/null; do
        sleep 2; waited=$((waited + 2))
        if [ "$waited" -ge "${COMBO_TIMEOUT:-3600}" ]; then timed_out=1; break; fi
    done
    if [ "$timed_out" = 1 ]; then
        kill -TERM -- -"$gpid" 2>/dev/null; sleep 3; kill -KILL -- -"$gpid" 2>/dev/null
        disown "$gpid" 2>/dev/null
        rc=124
        if ! netlink_alive; then
            printf '%stimed out%s\n\n' "$RED" "$RESET"
            warn_ "the kernel's networking lock (rtnl_lock) is wedged: 'ip link' does not"
            warn_ "return, and every engine that starts Open MPI will hang the same way."
            warn_ "This is WSL, not the build. From PowerShell:"
            say ""
            say "    wsl --shutdown"
            say ""
            say "then run this script again. Finished combinations are kept and skipped."
            exit 3
        fi
    else
        wait "$gpid"; rc=$?
    fi

    made=$(find "$out/pseudos" -type f ! -name '*.txt' ! -name '*.provenance' 2>/dev/null | wc -l)
    dt=$(( $(date +%s) - t0 ))

    if [ "$made" -gt 0 ]; then
        printf '%s%4d files%s  %ds\n' "$GREEN" "$made" "$RESET" "$dt"
        : > "$STAMPS/$key"
        done_n=$((done_n + 1))
    elif [ "$rc" = 124 ]; then
        printf '%stimed out%s after %ss (see %s)\n' "$RED" "$RESET" "${COMBO_TIMEOUT:-3600}" "$out.log"
        fail_n=$((fail_n + 1))
    elif [ "$rc" = 0 ]; then
        printf '%s   no elements%s\n' "$DIM" "$RESET"
        : > "$STAMPS/$key"
        skip_n=$((skip_n + 1))
    else
        printf '%sfailed%s (exit %s, see %s)\n' "$RED" "$RESET" "$rc" "$out.log"
        fail_n=$((fail_n + 1))
    fi
done < <(printf '%s\n' "$PLAN")

# ---------------------------------------------------------------------------
if [ "$KEEP_UNCOMPRESSED" = 0 ]; then
    step "compressing"
    # -n so the gzip header carries no name or timestamp: the same input then
    # gives the same bytes, which keeps the store diffable and rsync-able.
    #
    # Every engine output is text, so everything under pseudos/ is compressed
    # except the two metadata files -- the browser renders CITATION.txt and
    # LICENSE.txt inline.  The previous version listed seven extensions by
    # name and quietly missed .abinit, .cpmd, .fhi, .psf, .recpot, .ncpp,
    # .teter, .qso, .casino, .champ, .uspp, .van and .pao; those files were
    # left uncompressed while the index went on calling them "gzip".
    before=$(du -sb "$STORE" 2>/dev/null | cut -f1)
    find "$STORE" -type f -path '*/pseudos/*' \
        ! -name '*.gz' \
        ! -name 'CITATION.txt' \
        ! -name 'LICENSE.txt' \
        -print0 | xargs -0 -r -P "$JOBS" -n 64 gzip -9 -n
    after=$(du -sb "$STORE" 2>/dev/null | cut -f1)
    [ -n "$before" ] && [ -n "$after" ] && [ "$after" -gt 0 ] && \
        say "$(( before / 1048576 )) MB -> $(( after / 1048576 )) MB"

    # A plain file whose .gz sibling already exists means an earlier run
    # wrote the plaintext before this pass, gzip refused to overwrite, and
    # the plaintext stayed.  Remove it -- the .gz is the same content, and
    # keeping both doubles the store and makes the index ambiguous.
    #
    # This should not happen once state_should_run checks for .gz, but a
    # store built by an older version still needs the cleanup, and a guard
    # here is cheaper than asking every user to rebuild from scratch.
    removed=0
    while IFS= read -r -d '' f; do
        if [ -f "$f.gz" ]; then
            rm -f "$f"
            removed=$((removed + 1))
        fi
    done < <(find "$STORE" -type f -path '*/pseudos/*' \
                  ! -name '*.gz' \
                  ! -name 'CITATION.txt' \
                  ! -name 'LICENSE.txt' \
                  -print0)
    [ "$removed" -gt 0 ] && say "removed $removed stale plaintext file(s)"
fi

# ---------------------------------------------------------------------------
step "indexing"
"$PSM" native index "$STORE" || warn_ "the index did not build"

# ---------------------------------------------------------------------------
step "done"
say "built:   $done_n combination(s)"
say "skipped: $skip_n"
[ "$fail_n" -gt 0 ] && warn_ "failed:  $fail_n  (re-run to retry; finished work is kept)"
say "size:    $(du -sh "$STORE" 2>/dev/null | cut -f1)"
say "time:    $(( ( $(date +%s) - t_all ) / 60 )) min"
printf '\n'
[ "$fail_n" -eq 0 ]
