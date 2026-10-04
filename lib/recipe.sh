# shellcheck shell=bash
# ---------------------------------------------------------------------------
# recipe.sh -- turn (profile, element, family, functional, options) into a
# complete ld1.x input deck.
#
# Two paths:
#   * a shipped library recipe (psl-*)  -- render the stored template, then
#     apply only the overrides the user actually asked for, so an untouched
#     run reproduces the published deck exactly;
#   * pseudoforge-auto                      -- build a deck from a neighbouring
#     recipe plus a documented radius heuristic.
#
# Every knob in the specification maps onto a real ld1.x variable; where ld1.x
# has no such variable (core holes, extra projectors) the effect is produced by
# editing the configuration string or the card block, which is how the atomic
# code expects it to be done.
# ---------------------------------------------------------------------------

# The spec is a single associative array so it can be passed around, dumped
# into the run manifest and diffed between runs.
declare -gA SPEC

# recipe_build also publishes its result here, so callers in per-element loops
# do not need a command substitution to read it back.
RB_DECK='' RB_UPF='' RB_SET='' RB_TAG=''

spec_init() {
    SPEC=()
    SPEC[profile]=${DEFAULT_PROFILE:-psl-high}
    SPEC[family]=${DEFAULT_PSEUDOTYPE:-paw}
    SPEC[xc]=${DEFAULT_XC:-PBE}; SPEC[xc]=${SPEC[xc],,}
    SPEC[rel]=${DEFAULT_RELATIVITY:-scalar}
    SPEC[upf]=${DEFAULT_UPF_VERSION:-2}
    SPEC[author]=${AUTHOR:-}

    SPEC[variant]=          # explicit PSlibrary variant tag, else the first match
    SPEC[nlcc]=             # on | off | (empty = leave the recipe alone)
    SPEC[rcore]=
    SPEC[rho0]=
    SPEC[which_augfun]=     # AE | PSQ | BESSEL | GAUSS | BG
    SPEC[rmatch_augfun]=
    SPEC[lloc]=
    SPEC[rcloc]=
    SPEC[zed]=              # fractional nuclear charge override
    SPEC[zval]=             # explicit valence charge
    SPEC[config]=           # full override of the atomic configuration
    SPEC[core_hole]=        # e.g. 1s -- one electron removed from that shell
    SPEC[lsd]=              # 1 for a spin-polarised generation run
    SPEC[gipaw]=            # 1 -> lgipaw_reconstruction for NMR/EPR
    SPEC[xmin]=             # radial grid: r(i) = exp(xmin + (i-1) dx) / zed
    SPEC[dx]=
    SPEC[rmax]=
    SPEC[beta]=             # SCF mixing factor
    SPEC[tr2]=              # SCF convergence threshold
    SPEC[rcut_scale]=       # multiply every rcut/rcutus by this factor
    SPEC[extra_projectors]= # "3D:0.5 4P:1.0" -> extra card lines
    SPEC[nc_form]=          # semilocal | separable (norm-conserving only)
    SPEC[formats]=upf
    SPEC[tag_suffix]=       # appended to the generated file name

    # Declared here, filled by cli_check_spec once the profile is known.  They
    # belong to the specification -- a run that used ONCVPSP is not the same
    # run as one that used ld1.x -- so a saved recipe has to carry them, and
    # carrying them means declaring them.
    SPEC[engine]=
    SPEC[source]=

    # Remember what a default looks like, so spec_cmdline can print the
    # overrides a user asked for instead of the whole specification.
    spec_defaults_snapshot
}


# Dump the spec into a run manifest so a run can be reproduced or diffed.
spec_dump() {
    local k
    # shellcheck disable=SC2178,SC2128
    for k in $(printf '%s\n' "${!SPEC[@]}" | sort); do
        [ -n "${SPEC[$k]}" ] && printf '%s=%s\n' "$k" "${SPEC[$k]}"
    done
    return 0
}

# ---------------------------------------------------------------------------
recipe_flavour() {          # UPF name fragment for a family
    case $1 in
        paw) echo kjpaw_psl ;;
        us)  echo rrkjus_psl ;;
        nc)  echo nc ;;
    esac
}

recipe_pseudotype_code() {  # ld1.x pseudotype=
    case $1 in
        # 1 = semilocal: one potential per angular momentum, no separable form.
        #     Bigger files and slower in pw.x, but free of ghost states by
        #     construction, which is why it is still worth having.
        # 2 = separable Kleinman-Bylander form -- the norm-conserving default.
        nc)  case ${SPEC[nc_form]:-} in semilocal) echo 1 ;; *) echo 2 ;; esac ;;
        us)  echo 3 ;;
        paw) echo 3 ;;
    esac
}


# ---------------------------------------------------------------------------
# recipe_select_r <profile> <family> <element> <rel>
#   Sets R_SET / R_TAG / R_KEY / R_COND.  Fork-free: this runs once per element
#   in batches that can span the whole periodic table.
# ---------------------------------------------------------------------------
R_SET='' R_TAG='' R_KEY='' R_COND=''
recipe_select_r() {
    local prof=$1 fam=$2 el=$3 rel=$4
    local relword want line tag key cond

    prof_psl_set_r "$prof" "$fam" || return 1
    R_SET=$REPLY
    rel_canon_r "$rel" || return 1
    [ "$REPLY" = full ] && relword=fr || relword=sr
    want=${SPEC[variant]:-}

    psl_recipes_r "$R_SET" "$el" || return 1
    for line in "${PSL_R[@]}"; do
        tag=${line%%	*}
        cond=${line##*	}
        key=${line#*	}; key=${key%%	*}
        [ "$cond" = any ] || [ "$cond" = "$relword" ] || continue
        if [ -n "$want" ] && [ "$tag" != "$want" ] && [ "${tag%%.*}" != "$want" ]; then
            continue
        fi
        R_TAG=$tag; R_KEY=$key; R_COND=$cond
        return 0
    done
    return 1
}

# recipe_select <profile> <family> <element> <rel>
#   -> "set<TAB>tag<TAB>upfkey<TAB>cond", or non-zero if the profile has no
#      recipe for that element.  Honours SPEC[variant] when set.
recipe_select() {
    recipe_select_r "$@" || return 1
    printf '%s\t%s\t%s\t%s\n' "$R_SET" "$R_TAG" "$R_KEY" "$R_COND"
}


# recipe_render <template> <outfile> <fct> <gfun> <nrel>
# Pure bash: this runs once per element and sed would cost a fork each time.
recipe_render() {
    local line
    local -a out=()
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line//\{\{FCT\}\}/$3}
        line=${line//\{\{GFUN\}\}/$4}
        line=${line//\{\{NREL\}\}/$5}
        out+=("$line")
    done < "$1"
    printf '%s\n' "${out[@]}" > "$2"
}

# ---------------------------------------------------------------------------
# Configuration-string surgery.
# ---------------------------------------------------------------------------

# cfg_occ <config> <shell>  -> occupation of e.g. "3d", or empty if absent
cfg_occ() {
    local shell
    shell=${2,,}
    printf '%s\n' "$1" | tr ' ' '\n' | awk -v s="$shell" '
        tolower(substr($0, 1, length(s))) == s {
            v = substr($0, length(s) + 1)
            if (v ~ /^-?[0-9.]+$/) { print v; exit }
        }'
}

# cfg_set_occ <config> <shell> <occ>
cfg_set_occ() {
    local shell
    shell=${2,,}
    printf '%s\n' "$1" | awk -v s="$shell" -v o="$3" '{
        n = split($0, t, " ")
        out = ""
        for (i = 1; i <= n; i++) {
            if (tolower(substr(t[i], 1, length(s))) == s && substr(t[i], length(s) + 1) ~ /^-?[0-9.]+$/)
                t[i] = s o
            out = out (i > 1 ? " " : "") t[i]
        }
        print out
    }'
}

# Expand a noble-gas core into explicit shells, so a core hole can be punched
# into a state the recipe would otherwise keep frozen and unnamed.
cfg_expand_core() {
    local cfg=$1 core shells
    core=$(el_core "$cfg")
    case $core in
        He) shells="1s2" ;;
        Ne) shells="1s2 2s2 2p6" ;;
        Ar) shells="1s2 2s2 2p6 3s2 3p6" ;;
        Kr) shells="1s2 2s2 2p6 3s2 3p6 3d10 4s2 4p6" ;;
        Xe) shells="1s2 2s2 2p6 3s2 3p6 3d10 4s2 4p6 4d10 5s2 5p6" ;;
        Rn) shells="1s2 2s2 2p6 3s2 3p6 3d10 4s2 4p6 4d10 5s2 5p6 4f14 5d10 6s2 6p6" ;;
        *)  printf '%s\n' "$cfg"; return 0 ;;
    esac
    printf '%s\n' "${cfg/\[$core\]/$shells}"
}

# ---------------------------------------------------------------------------
# Card-block helpers.
# ---------------------------------------------------------------------------

# Scale rcut (column 6) and rcutus (column 7) on every card line.
cards_scale_rcut() {
    awk -v f="$1" '{
        if (NF >= 7) { $6 = sprintf("%.2f", $6 * f); $7 = sprintf("%.2f", $7 * f) }
        printf "%-4s %2s %2s %6s %6s %6s %6s %5s\n", $1, $2, $3, $4, $5, $6, $7, ($8 == "" ? "0.0" : $8)
    }'
}

# Append an extra projector: the same shell at a new reference energy, which is
# exactly how ld1.x is asked for a second projector in that channel.
cards_add_projector() {   # <cardfile> <SHELL:energy> [lloc]
    local file=$1 spec=$2 lloc=${3:-}
    local shell ener sh_l base_lineno base_line new_line

    shell=${spec%%:*}; shell=${shell^^}
    ener=${spec##*:}

    # ld1.x allows only one card for the local channel.  The local channel
    # is set by `lloc` in the &inputp namelist; a supplementary card on
    # that channel is read as a "second local channel" and stops the run
    # with "ld1_readin: only one local channel".  Refuse early with a
    # message that names the cause, rather than let ld1 abort on a deck
    # the builder produced.
    sh_l=$(printf '%s' "$shell" | sed -E 's/^[0-9]+([SPDF])$/\1/')
    case $sh_l in
        S) sh_l=0 ;; P) sh_l=1 ;; D) sh_l=2 ;; F) sh_l=3 ;;
    esac
    if [ -n "$lloc" ] && [ "$sh_l" = "$lloc" ]; then
        RB_ERROR="--projector $spec: $shell is the local channel (lloc=$lloc); ld1.x allows only one card per local channel.  Pick a different shell, or change --lloc first."
        warn "$RB_ERROR"
        return 1
    fi

    # Locate the base card.  Cards are one per line; the first column is
    # the shell label (for example 3P or 4F).
    base_lineno=$(awk -v s="$shell" 'toupper($1) == s { print NR; exit }' "$file")
    if [ -z "$base_lineno" ]; then
        RB_ERROR="--projector $spec: no card for shell $shell in the deck"
        warn "$RB_ERROR"
        return 1
    fi
    base_line=$(awk -v s="$shell" 'toupper($1) == s { print; exit }' "$file")

    # The supplementary card goes *immediately after* the base card, not at
    # the end of the block.  ld1.x walks the card list in order and the
    # second reference energy has to sit on the channel it belongs to.
    #
    # The occupation is the negative of the base's: PSlibrary's own
    # multi-projector templates (for example us-alt/Mg.sp.0.2.5.tpl) write
    # the second 3D line with -2.00 when the first carries +2.00.  A
    # positive occupation there produces "unbound states must be empty",
    # and a zero occupation produces "mismatch between lloc and l of the
    # wavefunction chosen for local potential".
    new_line=$(printf '%s\n' "$base_line" | awk -v e="$ener" '{
        $4 = sprintf("%.2f", -1.0 * ($4 + 0))
        $5 = sprintf("%.2f", e)
        printf "%-4s %2s %2s %6s %6s %6s %6s %5s\n", $1, $2, $3, $4, $5, $6, $7, ($8 == "" ? "0.0" : $8)
    }')

    awk -v ln="$base_lineno" -v new="$new_line" '
        NR == ln { print; print new; next }
        { print }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

# ---------------------------------------------------------------------------
# recipe_apply <deck> <element> -- apply every SPEC override to a rendered deck.
# Anything the user did not set is left untouched, byte for byte.
# ---------------------------------------------------------------------------
recipe_apply() {
    RB_ERROR=""
    local deck=$1 el=$2
    local v cfg sh occ cards

    [ -n "${SPEC[author]:-}" ] && nml_set "$deck" inputp author "'${SPEC[author]}'"

    # --- UPF output format -------------------------------------------------
    case ${SPEC[upf]:-2} in
        1) nml_set "$deck" inputp upf_v1_format ".true." ;;
        2) nml_unset "$deck" inputp upf_v1_format ;;
    esac

    # --- nuclear / valence charge -----------------------------------------
    [ -n "${SPEC[zed]:-}" ]  && nml_set "$deck" input  zed  "${SPEC[zed]}"
    [ -n "${SPEC[zval]:-}" ] && nml_set "$deck" inputp zval "${SPEC[zval]}"

    # --- atomic configuration ---------------------------------------------
    cfg=$(nml_get "$deck" input config)
    [ -n "${SPEC[config]:-}" ] && cfg=${SPEC[config]}

    if [ -n "${SPEC[core_hole]:-}" ]; then
        # XSpectra-style core-hole pseudopotential: take one electron out of the
        # named core shell.  The shell has to be named explicitly, so expand any
        # noble-gas shorthand first.
        sh=${SPEC[core_hole]}
        cfg=$(cfg_expand_core "$cfg")
        occ=$(cfg_occ "$cfg" "$sh")
        if [ -z "$occ" ]; then
            # Refused, not warned past.  Carrying on produced a file tagged
            # -ch<shell> that had no core hole in it at all, reported as ok --
            # a pseudopotential whose name is a claim its contents do not
            # support.
            error "$el: core-hole shell $sh is not present in configuration '$cfg'"
            return 1
        else
            cfg=$(cfg_set_occ "$cfg" "$sh" "$(awk -v o="$occ" 'BEGIN { printf "%g", o - 1 }')")
            nml_set "$deck" inputp author "'${SPEC[author]} (core hole in $sh)'"
            # No warning when zval is absent: ld1.x gets this right on its own.
            # A core hole leaves one fewer electron in the core, so ld1 computes
            # valence = Z - (core electrons remaining), which is one MORE than
            # the neutral pseudopotential.  Copper spn is 19 without a hole and
            # 20 with a 1s hole -- checked both ways.
            #
            # Supplying zval by hand is where this goes wrong, and the shipped
            # example used to do exactly that: "--core-hole 1s --zval 12" was
            # documented in the help text and fails with
            #   ld1_readin: supplied (12.00) and calculated (20.00) valence
            if [ -n "${SPEC[zval]:-}" ]; then
                warn "$el: --zval given with --core-hole."
                warn "  A core hole raises the valence charge by exactly one, because the"
                warn "  electron removed from the core is no longer screening the nucleus."
                warn "  Unless you know you need a different value, leave --zval off and let"
                warn "  ld1.x count it."
            fi
        fi
    fi
    [ -n "$cfg" ] && nml_set "$deck" input config "'$cfg'"

    # --- spin polarisation -------------------------------------------------
    [ "${SPEC[lsd]:-}" = 1 ] && nml_set "$deck" input lsd 1

    # --- nonlinear core correction ----------------------------------------
    case ${SPEC[nlcc]:-} in
        on)
            nml_set "$deck" inputp nlcc ".true."
            nml_set "$deck" inputp new_core_ps ".true."
            ;;
        off)
            nml_set "$deck" inputp nlcc ".false."
            nml_unset "$deck" inputp new_core_ps
            nml_unset "$deck" inputp rcore
            ;;
    esac
    [ -n "${SPEC[rcore]:-}" ] && nml_set "$deck" inputp rcore "${SPEC[rcore]}"
    [ -n "${SPEC[rho0]:-}" ]  && nml_set "$deck" inputp rho0  "${SPEC[rho0]}"

    # --- augmentation functions (US/PAW only) ------------------------------
    if [ "${SPEC[family]}" != nc ]; then
        [ -n "${SPEC[which_augfun]:-}" ] && \
            nml_set "$deck" inputp which_augfun "'${SPEC[which_augfun]^^}'"
        [ -n "${SPEC[rmatch_augfun]:-}" ] && \
            nml_set "$deck" inputp rmatch_augfun "${SPEC[rmatch_augfun]}"
    fi

    # --- norm-conserving form ---------------------------------------------
    if [ "${SPEC[family]}" = nc ] && [ -n "${SPEC[nc_form]:-}" ]; then
        nml_set "$deck" inputp pseudotype "$(recipe_pseudotype_code nc)"
    fi

    # --- local channel -----------------------------------------------------
    [ -n "${SPEC[lloc]:-}" ]  && nml_set "$deck" inputp lloc  "${SPEC[lloc]}"
    [ -n "${SPEC[rcloc]:-}" ] && nml_set "$deck" inputp rcloc "${SPEC[rcloc]}"

    # --- GIPAW reconstruction (NMR / EPR) ----------------------------------
    if [ "${SPEC[gipaw]:-}" = 1 ]; then
        nml_set "$deck" inputp lgipaw_reconstruction ".true."
        [ "${SPEC[family]}" = paw ] && nml_set "$deck" inputp use_paw_as_gipaw ".true."
    fi

    # --- radial grid and SCF controls --------------------------------------
    for v in xmin dx rmax beta tr2; do
        [ -n "${SPEC[$v]:-}" ] && nml_set "$deck" input "$v" "${SPEC[$v]}"
    done

    # --- card block: radii scaling and extra projectors --------------------
    if [ -n "${SPEC[rcut_scale]:-}" ] || [ -n "${SPEC[extra_projectors]:-}" ]; then
        cards=$(mktemp)
        nml_cards "$deck" > "$cards"
        if [ -n "${SPEC[rcut_scale]:-}" ]; then
            cards_scale_rcut "${SPEC[rcut_scale]}" < "$cards" | write_atomic "$cards"
        fi
        # Read lloc from the deck's &inputp namelist: the value in SPEC is
        # what we asked for, but a template may set it and this deck is what
        # will run.
        local lloc_val
        lloc_val=$(nml_get "$deck" inputp lloc 2>/dev/null || true)
        lloc_val=${lloc_val:-${SPEC[lloc]:-}}
        for v in ${SPEC[extra_projectors]:-}; do
            cards_add_projector "$cards" "$v" "$lloc_val" || return 1
        done
        nml_set_cards "$deck" "$cards"
        rm -f "$cards"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# recipe_build <element> <outdir>
#   writes the deck and echoes "<deck>\t<upfname>\t<set>\t<tag>"
# ---------------------------------------------------------------------------
recipe_build() {
    local el=$1 outdir=$2
    local prof=${SPEC[profile]} fam=${SPEC[family]} xc=${SPEC[xc]} rel=${SPEC[rel]}
    local tpl deck fct gfun nrel upf

    xc_tag_r       "$xc" "$rel"; fct=$REPLY
    xc_qe_string_r "$xc";        gfun=$REPLY
    rel_code_r     "$rel";       nrel=$REPLY

    # A profile may publish its own ld1.x decks instead of being backed by the
    # PSlibrary recipe database -- Marburg does exactly that for the actinoids.
    # Those are the library's real numbers, so they take precedence.  This lives
    # here rather than in the input builder because the ld1 engine reaches
    # generation through recipe_build directly, carrying its own auto-fix loop.
    local _libdeck
    if _libdeck=$(params_find "$prof" "$el" 2>/dev/null) && [ -n "$_libdeck" ]; then
        case $_libdeck in
            *.in) recipe_adopt_deck "$_libdeck" "$el" "$outdir" && return 0 ;;
        esac
    fi

    if [ "$prof" = pseudoforge-auto ]; then
        recipe_build_auto "$el" "$outdir" "$fct" "$gfun" "$nrel"
        return $?
    fi

    recipe_select_r "$prof" "$fam" "$el" "$rel" || return 1
    psl_template_r "$R_SET" "$el" "$R_TAG" "$R_COND" || return 1
    tpl=$REPLY

    upf=${R_KEY//\{\{FCT\}\}/$fct}
    [ -n "${SPEC[tag_suffix]:-}" ] && upf="$upf${SPEC[tag_suffix]}"
    deck=$outdir/$upf.in

    [ -d "$outdir" ] || mkdir -p "$outdir"
    recipe_render "$tpl" "$deck" "$fct" "$gfun" "$nrel"
    # keep file_pseudopw in step with the deck name
    nml_set "$deck" inputp file_pseudopw "'$upf.UPF'"
    recipe_apply "$deck" "$el" || return 1

    RB_DECK=$deck; RB_UPF=$upf.UPF; RB_SET=$R_SET; RB_TAG=$R_TAG
    printf '%s\t%s\t%s\t%s\n' "$RB_DECK" "$RB_UPF" "$RB_SET" "$RB_TAG"
}

# ---------------------------------------------------------------------------
# pseudoforge-auto: no published recipe exists for this element/family/settings, so
# build one from the closest shipped recipe.
#
# Preference order:
#   1. the same element in another PSlibrary set of the same family
#   2. the same element in another family, with the pseudotype swapped
#   3. the same-group neighbour, with every cut-off radius scaled by the ratio
#      of covalent radii
#
# Case 3 is a heuristic; it is labelled as such in the UPF author field, in the
# log and in every report, and validation is forced on for it.
# ---------------------------------------------------------------------------
recipe_build_auto() {
    local el=$1 outdir=$2 fct=$3 gfun=$4 nrel=$5
    local fam=${SPEC[family]} rel=${SPEC[rel]}
    local -a sets_same sets_other
    local set tag key cond tpl relword nb deck upf flavour
    local src_el='' src_set='' scale=1 provenance=''

    case $fam in
        paw) sets_same=(paw-high paw-low paw-alt paw-031 paw-tot)
             sets_other=(us-high us-low us-031) ;;
        us)  sets_same=(us-high us-low us-alt us-031 us-tot)
             sets_other=(paw-high paw-low paw-031) ;;
        nc)  sets_same=(nc)
             sets_other=(us-high paw-high) ;;
    esac
    case $(rel_canon "$rel") in full) relword=fr ;; *) relword=sr ;; esac

    for set in "${sets_same[@]}" "${sets_other[@]}"; do
        while IFS=$'\t' read -r tag key cond; do
            [ "$cond" = any ] || [ "$cond" = "$relword" ] || continue
            src_set=$set; src_el=$el
            provenance="adapted from $set/$el.$tag"
            break 2
        done < <(psl_recipes "$set" "$el")
    done

    if [ -z "$src_set" ]; then
        nb=$(el_group_neighbour "$el") || {
            error "$el: no shipped recipe, and no same-group neighbour to adapt from"
            return 1
        }
        for set in "${sets_same[@]}" "${sets_other[@]}"; do
            while IFS=$'\t' read -r tag key cond; do
                [ "$cond" = any ] || [ "$cond" = "$relword" ] || continue
                src_set=$set; src_el=$nb
                scale=$(el_radius_ratio "$el" "$nb")
                provenance="heuristic: $set/$nb.$tag with cut-off radii scaled by $scale"
                break 2
            done < <(psl_recipes "$set" "$nb")
        done
    fi
    [ -n "$src_set" ] || { error "$el: nothing to adapt from"; return 1; }

    tpl=$(psl_template "$src_set" "$src_el" "$tag" "$cond") || return 1

    flavour=$(recipe_flavour "$fam")
    upf="$el.$fct-psm-$flavour.1.0.0"
    [ -n "${SPEC[tag_suffix]:-}" ] && upf="$upf${SPEC[tag_suffix]}"
    deck=$outdir/$upf.in

    [ -d "$outdir" ] || mkdir -p "$outdir"
    recipe_render "$tpl" "$deck" "$fct" "$gfun" "$nrel"

    # retarget the deck at the requested element and family
    nml_set "$deck" input  title "'$el'"
    nml_set "$deck" input  zed   "${EL_Z[$el]}."
    nml_set "$deck" inputp file_pseudopw "'$upf.UPF'"
    nml_set "$deck" inputp pseudotype "$(recipe_pseudotype_code "$fam")"
    case $fam in
        paw) nml_set "$deck" inputp lpaw ".true." ;;
        us)  nml_set "$deck" inputp lpaw ".false." ;;
        nc)  nml_set "$deck" inputp lpaw ".false."
             nml_unset "$deck" inputp which_augfun
             nml_unset "$deck" inputp rmatch_augfun
             nml_unset "$deck" inputp rmatch_augfun_nc ;;
    esac
    if [ "$src_el" != "$el" ]; then
        nml_set "$deck" input config "'$(cfg_adapt "$(nml_get "$deck" input config)" "$el")'"
        [ -n "${SPEC[rcut_scale]:-}" ] || SPEC[rcut_scale]=$scale
        warn "$el: $provenance -- validate before use"
    fi
    nml_set "$deck" inputp author "'${SPEC[author]:+${SPEC[author]} / }pseudoforge-auto: $provenance'"

    recipe_apply "$deck" "$el" || return 1
    RB_DECK=$deck; RB_UPF=$upf.UPF; RB_SET=pseudoforge-auto; RB_TAG=auto
    printf '%s\t%s\t%s\t%s\n' "$RB_DECK" "$RB_UPF" "$RB_SET" "$RB_TAG"
}

# ---------------------------------------------------------------------------
# recipe_auto_suffix -- derive a file-name suffix from whatever the user changed.
#
# A core-hole or virtual-crystal pseudopotential is a different object from the
# library one it was derived from, and must never end up sharing its file name:
# dropping both into one pseudo_dir would silently give the wrong physics.  So
# any override that changes what the pseudopotential *is* earns a tag, while
# purely cosmetic ones (author, UPF format) do not.
# ---------------------------------------------------------------------------
recipe_auto_suffix() {
    local s="" v
    [ -n "${SPEC[core_hole]:-}" ]  && s="$s-ch${SPEC[core_hole],,}"
    if [ -n "${SPEC[zed]:-}" ];  then v=${SPEC[zed]//./p}; s="$s-z$v"; fi
    if [ -n "${SPEC[zval]:-}" ]; then v=${SPEC[zval]//./p}; s="$s-zv$v"; fi
    [ -n "${SPEC[config]:-}" ]     && s="$s-cfg"
    if [ -n "${SPEC[rcut_scale]:-}" ]; then v=${SPEC[rcut_scale]//./p}; s="$s-rc$v"; fi
    [ -n "${SPEC[extra_projectors]// /}" ] && s="$s-xp"
    [ -n "${SPEC[which_augfun]:-}" ] && s="$s-${SPEC[which_augfun],,}"
    case ${SPEC[nlcc]:-} in
        on)  s="$s-nlcc" ;;
        off) s="$s-nonlcc" ;;
    esac
    [ -n "${SPEC[rcore]:-}" ] && [ -z "${SPEC[nlcc]:-}" ] && s="$s-nlcc"
    [ -n "${SPEC[lloc]:-}" ]  && s="$s-l${SPEC[lloc]}"
    [ "${SPEC[nc_form]:-}" = semilocal ] && s="$s-sl"
    [ "${SPEC[lsd]:-}" = 1 ]   && s="$s-sp"
    [ "${SPEC[gipaw]:-}" = 1 ] && s="$s-gipaw"
    printf '%s\n' "$s"
}

# Fill SPEC[tag_suffix] unless the user set one explicitly.
recipe_apply_auto_suffix() {
    [ -n "${SPEC[tag_suffix]:-}" ] && return 0
    local s; s=$(recipe_auto_suffix)
    [ -n "$s" ] || return 0
    SPEC[tag_suffix]=$s
    info "modified recipe: generated files are tagged '$s' so they cannot be confused with the stock library files"
}

# ---------------------------------------------------------------------------
# cfg_adapt <source-config> <target-element>
#
# When pseudoforge-auto borrows a recipe from a neighbour, the card block names the
# shells the neighbour treats as valence -- including semicore shells that sit
# inside the noble-gas core.  Replacing the configuration wholesale with the
# target's ground state would drop those shells and ld1.x would refuse the deck.
# So keep the source's shell list and only move the occupations across.
# ---------------------------------------------------------------------------
cfg_adapt() {
    local src=$1 el=$2
    local gs=${EL_CONFIG[$el]:-}
    local src_core tgt_core tok shell occ new=""

    src_core=$(el_core "$src")
    tgt_core=$(el_core "$gs")
    if [ -z "$src_core" ] || [ "$src_core" != "$tgt_core" ]; then
        # different core structure: nothing safe to carry over
        printf '%s\n' "$gs"
        return 1
    fi

    for tok in $src; do
        case $tok in
            \[*\]) new="$new$tok"; continue ;;
        esac
        # split "6d1.0" into shell "6d" and occupation "1.0"
        shell=${tok:0:2}
        occ=$(cfg_occ "$gs" "$shell")
        if [ -n "$occ" ]; then new="$new $shell$occ"; else new="$new $tok"; fi
    done
    printf '%s\n' "$new"
    return 0
}

# ---------------------------------------------------------------------------
# recipe_adopt_deck <deck> <element> <outdir>
#
# Run a published ld1.x deck as-is, changing only what this run actually chose:
# the functional, the relativity and the output name.  Everything that makes it
# that library's deck -- radii, projectors, augmentation settings -- is left
# exactly as published.
# ---------------------------------------------------------------------------
recipe_adopt_deck() {
    local src=$1 el=$2 outdir=$3
    local deck upf fct gfun nrel

    fct=$(xc_tag "${SPEC[xc]}" "${SPEC[rel]}")
    gfun=$(xc_qe_string "${SPEC[xc]}")
    nrel=$(rel_code "${SPEC[rel]}")

    upf="$el.$fct-$(recipe_flavour "${SPEC[family]}").${SPEC[profile]}"
    [ -n "${SPEC[tag_suffix]:-}" ] && upf="$upf${SPEC[tag_suffix]}"
    deck=$outdir/$upf.in

    mkdir -p "$outdir" || return 1
    cp -f "$src" "$deck" || return 1

    nml_set "$deck" input  dft "'$gfun'"
    nml_set "$deck" input  rel "$nrel"
    nml_set "$deck" inputp file_pseudopw "'$upf.UPF'"
    recipe_apply "$deck" "$el" || return 1

    # recipe_build's contract is these globals; the printed line is for humans.
    RB_DECK=$deck; RB_UPF=$upf.UPF; RB_SET=${SPEC[profile]}; RB_TAG=published
    printf '%s	%s	%s	%s
' "$RB_DECK" "$RB_UPF" "$RB_SET" "$RB_TAG"
}

# ---------------------------------------------------------------------------
# The specification as a command line, and as a file.
#
# Two representations of the same thing, and they are not interchangeable:
#
#   * **the file** is authoritative.  It stores every non-empty key directly,
#     so reloading it restores the specification exactly, including keys that
#     no flag can set.
#   * **the command line** is for reading.  It is what the wizard's review
#     screen shows and what `recipe load` prints, and it is the thing a user
#     pastes into a paper's methods section.  If a setting is in force that no
#     flag can express, saying so is the only honest option -- printing a
#     command that quietly does less than the run did would be a downgrade the
#     output does not admit to.
#
# The table below is what keeps the two from drifting.  Adding a key to SPEC
# without adding it here, or to one of the two exception lists, is caught by
# tests/test_recipe_roundtrip.sh rather than discovered by a user whose
# reloaded recipe generated something else.
# ---------------------------------------------------------------------------

# SPEC key -> the flag that sets it, for flags that take a value.
declare -gA SPEC_FLAG=(
    [family]=-t            [profile]=-p           [xc]=-x
    [rel]=-r               [upf]=--upf            [variant]=--variant
    [author]=--author      [config]=--config      [core_hole]=--core-hole
    [zed]=--zed            [zval]=--zval          [nlcc]=--nlcc
    [rcore]=--rcore        [rho0]=--rho0          [which_augfun]=--augfun
    [rmatch_augfun]=--rmatch                      [lloc]=--lloc
    [rcloc]=--rcloc        [rcut_scale]=--rcut-scale
    [nc_form]=--nc-form    [beta]=--beta          [tr2]=--tr2
    [engine]=--engine      [source]=--source      [formats]=--formats
)

# Flags that take no value; emitted when the key is 1.
declare -gA SPEC_FLAG_BOOL=( [lsd]=--lsd [gipaw]=--gipaw )

# Keys the command line expresses in a shape of their own: --projector repeats,
# and --grid carries xmin, dx and rmax in one argument.
declare -gA SPEC_FLAG_CUSTOM=( [extra_projectors]=1 [xmin]=1 [dx]=1 [rmax]=1 )

# Keys a run computes for itself rather than a user choosing them.  Saved in
# the file (so a reload reproduces the same file names) but never printed as a
# flag, because there is no flag.
declare -gA SPEC_DERIVED=( [tag_suffix]=1 )

# The four that identify the run are always printed, even when they match the
# defaults: a command line that omits them reads as "whatever is configured",
# which is not what was run.
SPEC_IDENTITY="family profile xc rel"

# Defaults as spec_init left them, so spec_cmdline can print the overrides the
# user actually asked for rather than the entire specification every time.
declare -gA SPEC_DEFAULT=()
spec_defaults_snapshot() {
    local k
    SPEC_DEFAULT=()
    for k in "${!SPEC[@]}"; do SPEC_DEFAULT[$k]=${SPEC[$k]}; done
}

# ---------------------------------------------------------------------------
# spec_cmdline -- the `pseudoforge generate` command equivalent to the current
# specification.  Pure: reads SPEC and the run options, writes a string.  Both
# the CLI and the TUI use it, so the command a user is shown before a run is
# the command that would reproduce it.
# ---------------------------------------------------------------------------
# ShellCheck reads `${!SPEC[@]}` as a keys expansion and then reports
# every string the loop touches -- `k`, `v`, `p`, `miss`, `els` -- as if
# each were the same array.  They are not: `k` takes each key in turn,
# `v` is its value, `p` is one entry of `extra_projectors`, and `miss`
# and `els` are strings throughout.  Rewriting the loop with `mapfile`
# did not quiet it because the inference runs from the earlier expansion
# to the whole function.  Disabled here, with the reason next to it.
# shellcheck disable=SC2178,SC2128
spec_cmdline() {
    local out="pseudoforge generate" k v p miss='' els=
    els=$(el_expand $CLI_ELEMENTS 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    [ -n "$els" ] && out="$out -e $els"

    # Sorted, so the same specification always renders the same string -- the
    # round-trip test compares these by equality.
    # The keys go through an array before the loop.  A bare
    # `for k in $(printf ... ${!SPEC[@]} ...)` reads correctly but
    # ShellCheck sees the command substitution as a word-splitting
    # expansion of the associative array and then reports every
    # string the loop touches as an array used as a string.  Collecting
    # into `keys` first removes the ambiguity and does not change the
    # order or the result.
    local -a keys=()
    mapfile -t keys < <(printf '%s\n' "${!SPEC[@]}" | sort)
    for k in "${keys[@]}"; do
        v=${SPEC[$k]:-}
        [ -n "$v" ] || continue
        [ -n "${SPEC_DERIVED[$k]:-}" ] && continue
        # An override is worth printing; a default is noise -- except for the
        # four that say what was made.
        case " $SPEC_IDENTITY " in
            *" $k "*) ;;
            *) [ "$v" = "${SPEC_DEFAULT[$k]:-}" ] && continue ;;
        esac
        if [ -n "${SPEC_FLAG_BOOL[$k]:-}" ]; then
            [ "$v" = 1 ] && out="$out ${SPEC_FLAG_BOOL[$k]}"
            continue
        fi
        if [ -n "${SPEC_FLAG[$k]:-}" ]; then
            case $v in
                *[[:space:]]*) out="$out ${SPEC_FLAG[$k]} '$v'" ;;
                *)             out="$out ${SPEC_FLAG[$k]} $v" ;;
            esac
            continue
        fi
        case $k in
            extra_projectors) for p in $v; do out="$out --projector $p"; done ;;
            xmin|dx|rmax)     ;;   # emitted together, below
            *)                miss="$miss $k" ;;
        esac
    done

    [ -n "${SPEC[xmin]:-}${SPEC[dx]:-}${SPEC[rmax]:-}" ] && \
        out="$out --grid ${SPEC[xmin]:-}:${SPEC[dx]:-}:${SPEC[rmax]:-}"

    # Options outside SPEC that still change what comes out.
    [ "${RUN_LD1_TESTS:-1}" = 0 ]     && out="$out --no-test"
    [ "${RUN_CUTOFF_SCAN:-0}" = 1 ]   && out="$out --cutoff-scan"
    [ "${AUTOFIX_ENABLED:-1}" = 0 ]   && out="$out --no-autofix"
    out="$out -j ${MAX_PARALLEL_JOBS:-4}"

    printf '%s\n' "$out"
    [ -z "$miss" ] || \
        warn "no command-line flag for:$miss -- the saved recipe file carries them, this command does not"
    return 0
}

# ---------------------------------------------------------------------------
# Saved recipes.
#
# A recipe is the physics plus the element list: everything that decides what
# comes out.  Deliberately not included:
#
#   * the output directory -- where, not what;
#   * the worker count -- a performance knob.  tests/test_batch_isolation.sh
#     shows -j 1 and -j 8 produce byte-identical pseudopotentials, so putting
#     it in a recipe would imply it mattered.
#
# The file is plain `key=value` text: readable, diffable, and safe to accept
# from someone else, because loading **parses** it rather than sourcing it.
# A recipe arriving by email must not be able to run commands, so every key is
# checked against the specification and an unknown one is refused rather than
# ignored -- a typo that silently does nothing is how a shared recipe quietly
# generates something other than what its author ran.
# ---------------------------------------------------------------------------
RCP_MAGIC=pseudoforge.recipe
RCP_FORMAT=1

rcp_dir() {
    local d=${RECIPE_DIR:-$HOME/.pseudoforge/recipes}
    mkdir -p "$d" 2>/dev/null || return 1
    printf '%s\n' "$d"
}

# Names become file names, so keep them boring.
rcp_name_ok() {
    case ${1:-} in
        ''|.|..)          return 1 ;;
        *[!A-Za-z0-9._-]*) return 1 ;;
        *)                return 0 ;;
    esac
}

rcp_path() {
    local d; d=$(rcp_dir) || return 1
    rcp_name_ok "$1" || return 1
    printf '%s/%s.recipe\n' "$d" "$1"
}

rcp_list() {
    local d f n
    d=$(rcp_dir) || return 1
    for f in "$d"/*.recipe; do
        [ -e "$f" ] || continue
        n=$(basename "$f" .recipe)
        printf '%s\t%s\t%s\n' "$n" \
               "$(rcp_field "$f" elements)" \
               "$(rcp_field "$f" description)"
    done
}

rcp_field() {   # rcp_field <file> <key>
    awk -F= -v k="$2" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# rcp_save <name-or-path> [description]
#
# Writes every non-empty specification key plus the run options that change the
# result.  Nothing is interpreted on the way out: what the run would use is
# what gets written.
# ---------------------------------------------------------------------------
rcp_save() {
    local target=$1 desc=${2:-} f k
    case $target in
        */*|*.recipe) f=$target ;;
        *)            f=$(rcp_path "$target") || { error "bad recipe name: $target"; return 1; } ;;
    esac
    mkdir -p "$(dirname "$f")" 2>/dev/null

    {
        printf '# PseudoForge saved recipe\n'
        printf '# Reload with: pseudoforge generate --recipe %s\n' \
               "$(basename "$f" .recipe)"
        printf '#\n'
        printf '# This file is parsed, never sourced.  It cannot run commands.\n\n'
        printf '%s=%s\n' "$RCP_MAGIC" "$RCP_FORMAT"
        printf 'tool.version=%s\n' "${PSEUDOFORGE_VERSION:-unknown}"
        printf 'saved=%s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
        [ -n "$desc" ] && printf 'description=%s\n' "$desc"
        printf 'elements=%s\n' \
               "$(el_expand $CLI_ELEMENTS 2>/dev/null | tr '\n' ',' | sed 's/,$//')"
        printf '\n# specification\n'
        for k in $(printf '%s\n' "${!SPEC[@]}" | sort); do
            [ -n "${SPEC[$k]:-}" ] && printf 'spec.%s=%s\n' "$k" "${SPEC[$k]}"
        done
        printf '\n# run options that change the result\n'
        printf 'run.tests=%s\n'        "${RUN_LD1_TESTS:-1}"
        printf 'run.cutoff_scan=%s\n'  "${RUN_CUTOFF_SCAN:-0}"
        printf 'run.cutoffs=%s\n'      "${CUTOFF_SCAN_LIST:-}"
        printf 'run.cutoff_tol=%s\n'   "${CUTOFF_TOL_MRY:-}"
        printf 'run.autofix=%s\n'      "${AUTOFIX_ENABLED:-1}"
        printf 'run.attempts=%s\n'     "${AUTOFIX_MAX_ATTEMPTS:-2}"
    } > "$f" || { error "cannot write $f"; return 1; }
    printf '%s\n' "$f"
}

# ---------------------------------------------------------------------------
# rcp_load <name-or-path>
#
# Restores SPEC, CLI_ELEMENTS and the run options.  Refuses anything it does
# not recognise: a key that is silently dropped is a recipe that generates
# something other than what its author ran.
# ---------------------------------------------------------------------------
rcp_load() {
    local target=$1 f line k v bad='' n=0
    case $target in
        */*|*.recipe) f=$target ;;
        *)            f=$(rcp_path "$target") || { error "bad recipe name: $target"; return 1; } ;;
    esac
    [ -f "$f" ] || { error "no such recipe: $target"; return 1; }

    if [ "$(rcp_field "$f" "$RCP_MAGIC")" = "" ]; then
        error "$f is not a PseudoForge recipe (no $RCP_MAGIC line)"
        return 1
    fi
    local fmt; fmt=$(rcp_field "$f" "$RCP_MAGIC")
    if [ "$fmt" -gt "$RCP_FORMAT" ] 2>/dev/null; then
        error "$f is format $fmt; this PseudoForge understands up to $RCP_FORMAT"
        return 1
    fi

    while IFS= read -r line; do
        case $line in ''|\#*) continue ;; esac
        k=${line%%=*}; v=${line#*=}
        case $k in
            "$RCP_MAGIC"|tool.version|saved|description) continue ;;
            elements) CLI_ELEMENTS=$v; continue ;;
            spec.*)
                k=${k#spec.}
                if [ -z "${SPEC[$k]+set}" ]; then bad="$bad $k"; continue; fi
                SPEC[$k]=$v; n=$((n + 1)) ;;
            run.tests)        RUN_LD1_TESTS=$v ;;
            run.cutoff_scan)  RUN_CUTOFF_SCAN=$v ;;
            run.cutoffs)      CUTOFF_SCAN_LIST=$v ;;
            run.cutoff_tol)   CUTOFF_TOL_MRY=$v ;;
            run.autofix)      AUTOFIX_ENABLED=$v ;;
            run.attempts)     AUTOFIX_MAX_ATTEMPTS=$v ;;
            *)                bad="$bad $k" ;;
        esac
    done < "$f"

    if [ -n "$bad" ]; then
        error "$f carries settings this version does not know:$bad"
        error "  refusing rather than generating something other than what it says"
        return 1
    fi
    [ "$n" -gt 0 ] || { error "$f sets nothing"; return 1; }
    RCP_LOADED=$f
    return 0
}

rcp_delete() {
    local f; f=$(rcp_path "$1") || { error "bad recipe name: $1"; return 1; }
    [ -f "$f" ] || { error "no such recipe: $1"; return 1; }
    rm -f "$f" && printf '%s\n' "$f"
}
