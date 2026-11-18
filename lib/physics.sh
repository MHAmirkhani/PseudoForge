# shellcheck shell=bash
# Native physics controls shared by builders, CLI, TUI and HTTP capabilities.
# No evaluation of shell text or arbitrary Fortran/keyword assignments.

physics_copy() {
    [ "$(realpath "$1")" = "$(realpath -m "$2")" ] && return 0
    cp -f "$1" "$2"
}

physics_source_check() {
    [ -n "${PARAMS_DIR:-}" ] || return 0
    local source_dir target_dir
    source_dir=$(realpath "$PARAMS_DIR") || return 1
    target_dir=$(realpath -m "$1") || return 1
    case "$source_dir/" in "$target_dir/"*) error "native source overlaps project inputs; choose a separate output project"; return 1 ;; esac
    case "$target_dir/" in "$source_dir/"*) error "project inputs are inside the native source; choose a separate output project"; return 1 ;; esac
}

physics_schema() {
    awk -F'\t' -v e="$1" '$1==e {sub(/^[^\t]*\t/, ""); print}' "$PF_DATA/physics-controls.tsv"
}

physics_options_check() {
    local eng=$1 entry key value row type min max unit label seen=' '
    for entry in ${SPEC[engine_options]:-}; do
        [[ "$entry" = *=* ]] || { error "--engine-option needs KEY=VALUE"; return 1; }
        key=${entry%%=*}; value=${entry#*=}
        row=$(physics_schema "$eng" | awk -F'\t' -v k="$key" '$1==k {print;exit}')
        [ -n "$row" ] || { error "unknown physics control '$key' for $eng; inspect pseudoforge physics $eng"; return 1; }
        [[ "$seen" != *" $key "* ]] || { error "duplicate physics control '$key'"; return 1; }
        seen="$seen$key "
        IFS=$'\t' read -r key type min max unit label <<< "$row"
        case $type in
            enum)
                case ",$min," in *",$value,"*) ;; *) error "$key must be one of: $min"; return 1 ;; esac ;;
            integer)
                [[ "$value" =~ ^[0-9]+$ ]] && [ "${#value}" -le 8 ] || { error "$key must be an integer"; return 1; } ;&
            number|positive)
                ib_number "$value" || { error "$key must be finite"; return 1; }
                if ! awk -v v="${value//[dD]/e}" -v lo="$min" -v hi="$max" -v t="$type" 'BEGIN {exit !((lo=="-" || v>=lo) && (hi=="-" || v<=hi) && (t!="positive" || v>0))}'; then
                    error "$key is outside its supported range ($min .. $max $unit)"; return 1
                fi ;;
            *) error "invalid physics schema for $eng/$key"; return 1 ;;
        esac
    done
    if [ "$eng" = gth ] && [ -n "${SPEC[engine_options]:-}${SPEC[channel_radii]:-}${SPEC[rcloc]:-}${SPEC[rcut_scale]:-}" ] && [ "${GTH_REFIT:-0}" != 1 ]; then
        error "GTH physics controls require --refit; coefficient-table reproduction performs no fit"; return 1
    fi
}

physics_adopt() {
    local eng=$1 el=$2 deck=$3 expected=$4 src z header xc rel got want
    src=$(params_find "${SPEC[profile]}" "$el") || return 1
    [ -z "${SPEC[config]:-}" ] || { error "$eng: edit the reference configuration in the supplied native input; --config would replace it"; return 1; }
    case $eng in
        atompaw)
            z=$(awk 'NF && $1 !~ /^#/ {print $2;exit}' "$src")
            [ "$(awk 'NF && $1 !~ /^#/ {print $1;exit}' "$src")" = "$el" ] || { error "AtomPAW input is not for $el"; return 1; }
            header=$(awk 'NF && $1 !~ /^#/ {n++;if(n==2){print toupper($0);exit}}' "$src")
            xc=$(ib_atompaw_xc) || { error "AtomPAW does not natively support requested ${SPEC[xc]}; PZ and PW are different functionals"; return 1; }; rel=$(ib_atompaw_rel)
            case " $header " in *" $(upper "$xc") "*) ;; *) error "AtomPAW native XC line does not match $xc; use a prepared explicit XC header"; return 1 ;; esac
            case " $header " in *" $(upper "$rel") "*) ;; *) error "AtomPAW native relativity must explicitly match $rel"; return 1 ;; esac ;;
        ape)
            z=$(awk -F= 'tolower($1) ~ /^[ \t]*nuclearcharge[ \t]*$/ {sub(/#.*/,"",$2);gsub(/[ \t]/,"",$2);print $2;exit}' "$src")
            got=$(awk -F= 'tolower($1) ~ /^[ \t]*waveequation[ \t]*$/ {sub(/#.*/,"",$2);gsub(/[ \t]/,"",$2);print tolower($2);exit}' "$src")
            [ "${got:-schrodinger}" = "$(ib_ape_waveeq)" ] || { error "APE native WaveEquation does not match requested relativity"; return 1; }
            got=$(awk '/^[ \t]*%XCFunctionals/ {g=1;next} g && /^[ \t]*%/ {exit} g && NF && $1!~/^#/ {printf "%s ",tolower($1)}' "$src")
            want="$(ib_ape_xc) "
            [ "$got" = "$want" ] || { error "APE native XCFunctionals block does not match requested ${SPEC[xc]}; use the prepared explicit functional pair"; return 1; } ;;
    esac
    ib_number "${z:-}" && awk -v z="$z" -v want="${EL_Z[$el]}" 'BEGIN{exit !(z==want)}' || { error "$eng input nuclear charge does not match $el"; return 1; }
    mkdir -p "$(dirname "$deck")" || return 1
    physics_copy "$src" "$deck" || return 1
    printf '%s\x1f%s\x1f%s\x1f%s\n' "$deck" "$expected" supplied "$src"
}

physics_gth_check() {
    local dir=$1 el=$2 kw file got
    kw=$(gth_xc_keyword "${SPEC[xc]}") || return 1
    for file in atom/atom.dat "psp_$kw/psp.par" "psp_$kw/FITPAR" "psp_$kw/weights.par"; do
        [ -s "$dir/$file" ] || { error "GTH fit input missing: $dir/$file"; return 1; }
    done
    got=$(awk 'NF {print $1;exit}' "$dir/atom/atom.dat")
    [ "$got" = "$el" ] || { error "GTH atomic input is for $got, not $el"; return 1; }
    got=$(awk 'NF {n++;if(n==2){print tolower($1);exit}}' "$dir/atom/atom.dat")
    [ "$got" = "$kw" ] || { error "GTH atomic input functional $got does not match $kw"; return 1; }
    got=$(awk 'NF {n++;if(n==3){print tolower($1);exit}}' "$dir/atom/atom.dat")
    case "$(rel_canon "${SPEC[rel]}"):$got" in
        scalar:relativistic|nonrel:nonrelativistic|nonrel:non-relativistic) ;;
        *) error "GTH atomic relativity $got does not match ${SPEC[rel]}"; return 1 ;;
    esac
}

physics_fhi_check() {
    local el=$1 deck=$2 control=$3 z code xc mode spin nc nv
    read -r z nc nv code _ < "$deck"
    awk -v z="$z" -v want="${EL_Z[$el]}" 'BEGIN{exit !(z==want)}' || { error "fhi98PP input nuclear charge does not match $el"; return 1; }
    case $code in 3) xc=pz ;; 8) xc=pw ;; 6) xc=pbe ;; 4) xc=pw91 ;; 5) xc=bp ;; 9) xc=blyp ;; 14) xc=rpbe ;; 15) xc=revpbe ;; *) xc=unknown ;; esac
    [ "$xc" = "$(xc_generator "${SPEC[xc]}")" ] || { error "fhi98PP iexc=$code ($xc) does not match requested ${SPEC[xc]}"; return 1; }
    mode=$(awk 'NR==1{print tolower($2)}' "$control")
    case "$(rel_canon "${SPEC[rel]}"):$mode" in
        scalar:.f.|scalar:.false.|scalar:f|nonrel:.t.|nonrel:.true.|nonrel:t) ;;
        *) error "fhi98PP fort20 relativity does not match ${SPEC[rel]}"; return 1 ;;
    esac
    spin=$(awk 'NR==2{print tolower($1)}' "$control")
    case $spin in .t.|.true.|t)
        awk -v nc="$nc" -v nv="$nv" 'NR>1 && NR<=nc+nv+1 {if(NF<4 || $4 !~ /^[-+0-9.eEdD]+$/)exit 1}' "$deck" || {
            error "spin-polarized fhi98PP needs explicit up/down occupations in each native orbital row"; return 1;
        } ;;
    esac
}

physics_adpack_check() {
    # Also protect standalone upstream binaries without the readfile.c fix.
    awk '
        BEGIN {minimum["grid.num"]=2;minimum["scf.maxiter"]=1;limit["grid.num"]=20000;limit["scf.maxiter"]=2000}
        tolower($1) in limit {
            key=tolower($1)
            if(seen[key]++ || $2 !~ /^[0-9]+$/ || $2<minimum[key] || $2>limit[key]) {
                print "ADPACK " $1 " must be an integer in " minimum[key] ".." limit[key] " (2.2 array limit)" > "/dev/stderr";bad=1
            }
        }
        END {exit bad}
    ' "$1"
}

physics_gth_snapshot() {
    local source_dir=$1 target_dir=$2 kw file
    kw=$(gth_xc_keyword "${SPEC[xc]}") || return 1
    mkdir -p "$target_dir/atom" "$target_dir/psp_$kw" || return 1
    for file in atom/atom.dat "psp_$kw/psp.par" "psp_$kw/FITPAR" "psp_$kw/weights.par"; do
        physics_copy "$source_dir/$file" "$target_dir/$file" || return 1
    done
}

physics_apply() {
    local eng=$1 el=$2 deck=$3 tmp=$3.physics.$$ rc
    [ -n "${SPEC[engine_options]:-}${SPEC[channel_radii]:-}${SPEC[nlcc]:-}${SPEC[rcore]:-}${SPEC[rcloc]:-}${SPEC[lloc]:-}${SPEC[beta]:-}${SPEC[tr2]:-}${SPEC[rcut_scale]:-}" ] || return 0
    case $eng in ld1) return 0 ;; gth) physics_gth_apply "$el" "$deck"; return $? ;; esac
    awk -v eng="$eng" -v opts="${SPEC[engine_options]:-}" -v radii="${SPEC[channel_radii]:-}" \
        -v nlcc="${SPEC[nlcc]:-}" -v rcore="${SPEC[rcore]:-}" -v rcloc="${SPEC[rcloc]:-}" \
        -v lloc="${SPEC[lloc]:-}" -v beta="${SPEC[beta]:-}" -v tr2="${SPEC[tr2]:-}" \
        -v scale="${SPEC[rcut_scale]:-}" -f "$PF_ROOT/tools/awk/native-controls.awk" "$deck" > "$tmp"
    rc=$?
    if [ "$rc" != 0 ]; then
        rm -f "$tmp"; error "$eng: native control mapping failed ($rc); input was preserved"; return 1
    fi
    if [ "$eng" = uspp ] && [[ " ${SPEC[engine_options]:-} " =~ (thresh|tol|damp)= ]]; then
        local ae=${deck%.ps.adat}.ae.adat ae_tmp=${deck%.ps.adat}.ae.adat.physics.$$
        if ! awk -v eng=uspp-ae -v opts="${SPEC[engine_options]:-}" -f "$PF_ROOT/tools/awk/native-controls.awk" "$ae" > "$ae_tmp"; then
            rm -f "$tmp" "$ae_tmp"; error "USPP all-electron SCF controls could not be applied"; return 1
        fi
        mv -f "$ae_tmp" "$ae" || return 1
    fi
    mv -f "$tmp" "$deck"
}

physics_gth_apply() {
    local el=$1 deck=$2 kw file tmp cleanup_file
    [ "${GTH_REFIT:-0}" = 1 ] || { error "GTH controls need --refit"; return 1; }
    physics_gth_check "$deck" "$el" || return 1
    kw=$(gth_xc_keyword "${SPEC[xc]}") || return 1
    # Each transformation is checked before any of the four files is replaced.
    local -a files=(atom/atom.dat "psp_$kw/psp.par" "psp_$kw/FITPAR" "psp_$kw/weights.par")
    for file in "${files[@]}"; do
        tmp=$deck/$file.physics.$$
        if ! awk -v eng=gth -v kind="${file##*/}" -v opts="${SPEC[engine_options]:-}" \
            -v radii="${SPEC[channel_radii]:-}" -v scale="${SPEC[rcut_scale]:-}" -v rcloc="${SPEC[rcloc]:-}" \
            -f "$PF_ROOT/tools/awk/native-controls.awk" "$deck/$file" > "$tmp"; then
            for cleanup_file in "${files[@]}"; do rm -f "$deck/$cleanup_file.physics.$$"; done
            error "GTH: controls could not be applied; native files were preserved"; return 1
        fi
    done
    for file in "${files[@]}"; do mv -f "$deck/$file.physics.$$" "$deck/$file" || return 1; done
}

cmd_physics() {
    case ${1:-} in -h|--help) printf 'usage: pseudoforge physics [ENGINE]\n\nShow mapped physics controls, units and native-input support.\n'; return 0 ;; esac
    local engine key mode
    for engine in ${1:-${ENG_ORDER[*]}}; do
        eng_exists "$engine" || { error "unknown engine: $engine"; return 1; }
        printf '\n%s -- native input preparation, editing and --params supported\n' "$engine"
        while IFS= read -r key; do
            mode=$(ib_option_mode "$engine" "$key")
            [ "$mode" = unsupported ] || printf '  %-22s %s\n' "$key" "$mode"
        done < <(ib_option_keys)
        printf '\n  Native KEY=VALUE controls (--engine-option):\n'
        physics_schema "$engine" | awk -F'\t' '{printf "  %-26s %-14s %-12s %s\n",$1,$2,$5,$6}'
    done
}

cmd_prepare() {
    # Build the same files a real run uses; no solver or editor is launched.
    [ -n "${CLI_OUTPUT:-}" ] || { error "prepare needs -o DIR (a new or empty directory)"; return 1; }
    if [ -e "$CLI_OUTPUT" ] && { [ ! -d "$CLI_OUTPUT" ] || [ -n "$(find "$CLI_OUTPUT" -mindepth 1 -print -quit)" ]; }; then
        error "prepare output must be new or empty; existing inputs are never overwritten"; return 1
    fi
    [ "${SPEC[source]:-${CLI_SOURCE:-local}}" != online ] || { error "prepare requires local generation"; return 1; }
    CLI_DRYRUN=1
    cmd_generate || return 1
    local input_dir key
    input_dir=$PROJECT_DIR/inputs
    # The snapshot already contains every requested control. Do not apply its
    # global scale a second time when generating from those edited files.
    while IFS= read -r key; do SPEC[$key]=; done < <(ib_option_keys)
    SPEC[tag_suffix]=
    PARAMS_DIR=$input_dir
    AUTOFIX_ENABLED=0
    CLI_DRYRUN=0
    info "edit native files in $input_dir; keep XC/relativity consistent with the command"
    info "generate into a separate project, preserving the edited inputs:"
    spec_cmdline
}
