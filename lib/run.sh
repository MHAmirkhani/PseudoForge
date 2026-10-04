# shellcheck shell=bash
# ---------------------------------------------------------------------------
# run.sh -- executing ld1.x, diagnosing what went wrong, and the auto-fix loop.
#
# ld1.x reads its deck from stdin and writes the .UPF into the current working
# directory, so every run happens inside a private scratch directory and the
# result is moved into pseudos/ only after it has been validated.  That way a
# half-written UPF from a crashed run can never be picked up by a later pw.x.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# qe_run <binary> <deck> <logfile> <timeout> [workdir]
# ---------------------------------------------------------------------------
qe_run() {
    local bin=$1 deck=$2 log=$3 tmo=$4 wd=${5:-.}
    local rc

    if [ ! -x "$bin" ] && ! have "$bin"; then
        printf 'pseudoforge: %s is not executable\n' "$bin" > "$log"
        return 127
    fi

    (
        cd "$wd" || exit 126
        # Clamp threading exactly as exec_run does.  These are single-atom
        # radial solvers: a threaded BLAS spends far longer spin-waiting on
        # barriers than computing, and on a machine that is already busy an
        # ld1.x run that should take a second can fail to finish at all.
        # PseudoForge parallelises over elements instead.
        export OMP_NUM_THREADS="${OMP_THREADS:-1}"
        export OPENBLAS_NUM_THREADS="${OMP_THREADS:-1}"
        export MKL_NUM_THREADS="${OMP_THREADS:-1}"
        if [ "${tmo:-0}" -gt 0 ] && have timeout; then
            timeout --preserve-status "$tmo" "$bin" < "$deck" > "$log" 2>&1
        else
            "$bin" < "$deck" > "$log" 2>&1
        fi
    )
    rc=$?
    [ $rc -eq 124 ] && printf '\npseudoforge: killed after %ss (timeout)\n' "$tmo" >> "$log"
    return $rc
}

ld1_run() {   # ld1_run <deck> <log> <workdir>
    local prefix=""
    [ "${LD1_PARA:-0}" = 1 ] && prefix=$PARA_PREFIX
    if [ -n "$prefix" ]; then
        # shellcheck disable=SC2086
        ( cd "$3" && $prefix "$LD1_BIN" $PARA_POSTFIX < "$1" > "$2" 2>&1 )
        return $?
    fi
    qe_run "$LD1_BIN" "$1" "$2" "${LD1_TIMEOUT:-0}" "$3"
}

# ---------------------------------------------------------------------------
# ld1_diagnose <log> -> a short machine-readable cause tag
#
# Tags (also used to pick an auto-fix strategy):
#   ok               no error found
#   augmentation     find_qi / augmentation function trouble  (US, PAW)
#   chi              pseudo-wavefunction construction failed
#   scf              the all-electron or pseudo SCF did not converge
#   grid             radial grid / rmax trouble
#   local            local channel (lloc / rcloc) trouble
#   occupation       inconsistent configuration or occupations
#   paw              PAW-specific setup failure
#   timeout          killed by the wall-clock limit
#   missing-binary   ld1.x not found
#   unknown          ld1.x reported an error we do not recognise
# ---------------------------------------------------------------------------
ld1_diagnose() {
    local log=$1
    [ -f "$log" ] || { echo missing-binary; return; }

    grep -q 'not executable' "$log"                       && { echo missing-binary; return; }
    grep -q 'killed after .*timeout'  "$log"              && { echo timeout;        return; }

    # A supplied/calculated valence mismatch is its own cause: retrying with
    # wider radii or damped mixing cannot fix an arithmetic disagreement, and
    # the auto-fix loop used to burn both attempts on it before failing.
    grep -qi "supplied.*and calculated.*valence" "$log" && { echo valence; return; }

    if grep -qi 'Error in routine' "$log"; then
        local routine
        routine=$(grep -i -m1 'Error in routine' "$log" | sed 's/.*[Ee]rror in routine *//; s/ *(.*//')
        case $(lower "$routine") in
            find_qi|compute_q*|set_qf*|pseudovloc_q*) echo augmentation ; return ;;
            compute_chi*|chi*|nodenum*)               echo chi          ; return ;;
            ascheq|lschps|integrate_out*|start_scheq) echo scf          ; return ;;
            do_mesh|import_upf|grid*)                 echo grid         ; return ;;
            pseudovloc|set_psi_in|compute_potps)      echo local        ; return ;;
            occ*|read_config*|el_config*)             echo occupation   ; return ;;
            *paw*)                                   echo paw          ; return ;;
        esac
        echo unknown; return
    fi

    grep -qi 'convergence *\(is\)\? *not *achieved' "$log" && { echo scf; return; }
    grep -qi 'too many iterations'                  "$log" && { echo scf; return; }
    grep -qi 'wrong occupations\|occupation.*wrong' "$log" && { echo occupation; return; }
    grep -qi 'stopping'                             "$log" && { echo unknown; return; }
    echo ok
}

# ld1_message <log> -- a one-line human summary of why a run failed.
# ld1.x wraps its errors in a banner of % signs; keep the routine and the
# reason, drop the decoration.
ld1_message() {
    awk '
        /Error in routine/ {
            routine = $0
            sub(/.*[Ee]rror in routine[[:space:]]*/, "", routine)
            sub(/[[:space:]]*\(.*/, "", routine)
            getline reason
            while (reason ~ /^[[:space:]]*%+[[:space:]]*$/ || reason ~ /^[[:space:]]*$/) {
                if ((getline reason) <= 0) break
            }
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", reason)
            printf "%s: %s\n", routine, reason
            exit
        }' "$1" 2>/dev/null | cut -c1-200
}

ld1_warnings() {
    grep -h '^ *!' "$1" 2>/dev/null | sed 's/^ *//' | sort -u
}

# ---------------------------------------------------------------------------
# The auto-fix engine.
#
# autofix_strategy <cause> <attempt> -> "description|SPEC key=value ..."
#
# Each strategy is a documented, physically motivated relaxation, not a random
# parameter jiggle.  They are applied in order and the first one that produces
# a valid UPF wins; the strategy that worked is recorded in the report so the
# result stays reproducible.
# ---------------------------------------------------------------------------
autofix_strategy() {
    local cause=$1 attempt=$2
    case $cause:$attempt in
        valence:*)
            # Not retryable, and saying so is the useful answer.  A supplied
            # zval that disagrees with the configuration is arithmetic, not
            # convergence; widening radii cannot reconcile it.  The common
            # cause is --zval given alongside --core-hole: a core hole raises
            # the valence charge by one, because the removed electron is no
            # longer screening the nucleus.
            return 1 ;;
        augmentation:1)
            echo "switch augmentation functions to Bessel|which_augfun=BESSEL" ;;
        augmentation:2)
            echo "pull the augmentation matching radius inside the smallest rcut|which_augfun=PSQ rmatch_augfun=0.9" ;;
        chi:1)
            echo "widen all cut-off radii by 5%|rcut_scale=1.05" ;;
        chi:2)
            echo "widen all cut-off radii by 12% and soften the local channel|rcut_scale=1.12 lloc=-1" ;;
        scf:1)
            echo "damp the SCF mixing|beta=0.1" ;;
        scf:2)
            echo "damp the mixing further and loosen the threshold|beta=0.05 tr2=1.0d-13" ;;
        grid:1)
            echo "extend the radial grid|rmax=120.0" ;;
        grid:2)
            echo "extend and refine the radial grid|rmax=150.0 dx=0.0080" ;;
        local:1)
            echo "generate the local channel from an all-electron potential|lloc=-1 rcloc=1.2" ;;
        local:2)
            echo "use l=0 as the local channel|lloc=0" ;;
        paw:1)
            echo "use PSQ augmentation with norm-conserving matching|which_augfun=PSQ" ;;
        paw:2)
            echo "widen cut-off radii by 8%|rcut_scale=1.08" ;;
        occupation:1)
            echo "fall back to the tabulated ground-state configuration|config=GROUNDSTATE" ;;
        timeout:1)
            echo "damp the SCF mixing to converge in fewer, steadier iterations|beta=0.1" ;;
        unknown:1)
            echo "widen all cut-off radii by 5%|rcut_scale=1.05" ;;
        unknown:2)
            echo "damp the SCF mixing|beta=0.1" ;;
        *) return 1 ;;
    esac
}

# Apply a strategy string to SPEC, in a subshell-safe way.
autofix_apply() {   # autofix_apply <element> <"k=v k=v">
    local el=$1 kv
    for kv in $2; do
        local k=${kv%%=*} v=${kv#*=}
        [ "$v" = GROUNDSTATE ] && v=${EL_CONFIG[$el]}
        SPEC[$k]=$v
    done
}

# ---------------------------------------------------------------------------
# generate_one <element> -- the whole pipeline for a single element.
#
# Runs in a subshell of its own (one per parallel slot), so mutating SPEC here
# cannot leak into the other workers.
# ---------------------------------------------------------------------------
generate_one() {
    local el=$1
    # Only ld1 goes through this routine: it owns the auto-fix loop, which is
    # written against ld1's error messages.  The other engines have their own
    # path in executor.sh.
    if [ "${SPEC[engine]:-ld1}" != ld1 ]; then
        generate_one_engine "$el"
        return $?
    fi
    local t0 deck upf tag rc cause work log attempt maxatt strategy desc kv
    local status=fail message="" seconds=0

    t0=$(now)
    work=$SCRATCH_DIR/$$-$el
    log=$PROJECT_DIR/logs/$el.log
    mkdir -p "$work"

    attempt=0
    maxatt=${AUTOFIX_MAX_ATTEMPTS:-2}
    [ "${AUTOFIX_ENABLED:-1}" = 1 ] || maxatt=0

    while : ; do
        # ---- build the deck ----------------------------------------------
        if ! recipe_build "$el" "$PROJECT_DIR/inputs" >/dev/null; then
            # recipe_build may have failed because the deck builder refused
            # a user flag (--projector on the local channel, for instance).
            # In that case RB_ERROR carries the reason, and the element
            # fails rather than being reported as a skip with a generic
            # "no recipe" message.
            if [ -n "${RB_ERROR:-}" ]; then
                status=fail
                message="$RB_ERROR"
            else
                status=skip
                message="no recipe in profile ${SPEC[profile]} for ${SPEC[family]}"
            fi
            break
        fi
        deck=$RB_DECK; upf=$RB_UPF; tag=$RB_TAG

        # ---- run ld1.x ----------------------------------------------------
        ld1_run "$deck" "$log" "$work"
        rc=$?
        cause=$(ld1_diagnose "$log")

        if [ "$cause" = missing-binary ]; then
            status=fail; message="ld1.x not executable: $LD1_BIN"; break
        fi

        # ---- collect and validate the result ------------------------------
        if [ "$cause" = ok ] && [ -f "$work/$upf" ]; then
            local problems
            problems=$(upf_validate "$work/$upf")
            if [ $? -eq 0 ]; then
                mv -f "$work/$upf" "$PROJECT_DIR/pseudos/$upf"
                # XML is not native to any engine: it is a conversion from
                # UPF by QE's upfconv.x -x.  The non-ld1 path does this in
                # exec_generate; ld1 has its own loop here, so repeat the
                # same hook.  exec_upf_to_xml is idempotent and silent on
                # failure -- a missing upfconv.x does not fail the run.
                case " ${SPEC[formats]:-upf} " in
                    *" xml "*)
                        exec_upf_to_xml "$PROJECT_DIR/pseudos/$upf" "$el" >/dev/null 2>&1 ;;
                esac
                local warns; warns=$(ld1_warnings "$log")
                if [ -n "$problems" ] || [ -n "$warns" ]; then
                    status=ok-warn
                    message=$(printf '%s %s' "$problems" "$warns" | tr '\n' '; ' | cut -c1-200)
                else
                    status=ok
                    message=""
                fi
                [ "$attempt" -gt 0 ] && message="auto-fixed ($desc)${message:+; $message}"
                break
            fi
            cause=invalid-upf
            message=$(printf '%s' "$problems" | tr '\n' '; ' | cut -c1-200)
        elif [ "$cause" = ok ]; then
            cause=no-output
            message="ld1.x reported no error but wrote no $upf (exit $rc)"
        else
            message=$(ld1_message "$log")
            [ -n "$message" ] || message="ld1.x failed with exit code $rc ($cause)"
        fi

        # ---- auto-fix ------------------------------------------------------
        attempt=$((attempt + 1))
        if [ "$attempt" -gt "$maxatt" ]; then
            status=fail
            break
        fi
        strategy=$(autofix_strategy "$cause" "$attempt") || { status=fail; break; }
        desc=${strategy%%|*}
        kv=${strategy#*|}
        warn "$el: $cause -> retry $attempt/$maxatt: $desc"
        autofix_apply "$el" "$kv"
        cp -f "$log" "$PROJECT_DIR/logs/$el.attempt$attempt.log" 2>/dev/null
    done

    seconds=$(( $(now) - t0 ))
    rm -rf "$work"

    state_record "$el" "${SPEC[family]}" "${SPEC[profile]}" "${SPEC[xc]}" "${SPEC[rel]}" \
                 "${tag:-}" "${upf:-}" "$status" "$attempt" "$seconds" "$message"

    case $status in
        ok)      ok      "$el  ->  ${upf}  ($(human_time "$seconds"))" ;;
        ok-warn) warn    "$el  ->  ${upf}  ($(human_time "$seconds")) -- $message" ;;
        skip)    info    "$el  skipped: $message" ;;
        *)       error   "$el  FAILED: $message" ;;
    esac
    [ "$status" = fail ] && return 1
    return 0
}

# ---------------------------------------------------------------------------
# run_batch <element>... -- schedule the elements across MAX_PARALLEL_JOBS
# workers.  A failing element never stops the batch.
# ---------------------------------------------------------------------------
run_batch() {
    local -a todo=()
    local el slots running=0 done=0 total

    # Absorb any shards left by a run that was interrupted.
    #
    # Each element writes its result to logs/.state.<El> and they are merged
    # into state.tsv when the batch finishes.  Kill a batch halfway and the
    # shards survive but the merge never happens, so a restart saw an empty
    # state file and rebuilt everything it had already done -- 22 elements,
    # in the run that found this.  Merging first makes resume survive the
    # interruption it exists for.
    state_merge

    for el in "$@"; do
        if ! state_should_run "$el"; then
            info "$el  already done (resume) -- use --no-resume to force"
            continue
        fi
        todo+=("$el")
    done
    total=${#todo[@]}
    [ "$total" -gt 0 ] || { info "nothing to do"; return 0; }

    slots=${MAX_PARALLEL_JOBS:-4}
    [ "$slots" -ge 1 ] 2>/dev/null || slots=1
    info "generating $total element(s) with $slots parallel job(s)"

    for el in "${todo[@]}"; do
        while [ "$(jobs -rp | wc -l)" -ge "$slots" ]; do wait -n 2>/dev/null || sleep 1; done
        generate_one "$el" &
        running=$((running + 1))
    done
    wait

    state_merge
    return 0
}
