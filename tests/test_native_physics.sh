#!/usr/bin/env bash
# Native-input round-trips and physical effects; no installed solvers required.
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
for m in core sink config deps elements xc namelist profiles metadata formats gth sssp convert doctor params engines build recipe input_builder executor project run upf testing validate report build_command cli http; do . "$PF_LIB/$m.sh" || exit 1; done
pf_config_defaults; pf_elements_load; pf_xc_load; pf_profiles_load; pf_metadata_load; pf_engines_load
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
printf '# isolated\n' > "$tmp/rc"; export PF_RC=$tmp/rc
OPIUM_ROOT=$tmp/no-vendor-opium
pass=0 fail=0
ok() { printf 'PASS %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL %s\n' "$1"; fail=$((fail+1)); }
mkdir -p "$tmp/fhi-source"
# A minimal atomic configuration fixture, not a physical benchmark.
cat > "$tmp/fhi-source/Si.ini" <<'FHI'
14 3 2 8 0
1 0 2
2 0 2
2 1 6
3 0 2
3 1 2
2 t
FHI
FHI98PP_ROOT=$tmp/fhi-source
for row in 'ld1 psl-high paw Si pbe scalar' 'oncvpsp sg15 nc Si pbe scalar' 'uspp gbrv us Si pbe scalar' 'fhi98pp fhi nc Si pw scalar' 'opium opium nc Si pbe scalar' 'gth cp2k-gth nc Si pbe scalar' 'atompaw atompaw paw Si pbe scalar' 'ape pseudoforge-auto nc Si pbe scalar' 'adpack adpack nc He pz full'; do
    read -r eng profile family el xc rel <<< "$row"
    spec_init; SPEC[engine]=$eng; SPEC[profile]=$profile; SPEC[family]=$family; SPEC[xc]=$xc; SPEC[rel]=$rel
    PARAMS_DIR=; GTH_REFIT=0
    [ "$eng" != gth ] || GTH_REFIT=1
    [ "$eng" != fhi98pp ] || PARAMS_DIR=$tmp/fhi-source
    if line=$(ib_build "$eng" "$el" "$tmp/first/$eng"); then
        IFS=$'\x1f' read -r deck expected prov src <<< "$line"
        ok "$eng prepares a native input"
    else bad "$eng preparation"; continue; fi
    PARAMS_DIR=$tmp/first/$eng
    if line=$(ib_build "$eng" "$el" "$tmp/second/$eng"); then
        IFS=$'\x1f' read -r imported expected prov src <<< "$line"
        [ "$prov" = supplied ] && ok "$eng adopts its prepared input as supplied" || bad "$eng provenance"
        if [ "$eng" = ld1 ]; then
            diff <(nml_cards "$deck") <(nml_cards "$imported") >/dev/null && ok 'ld1 preserves all wavefunction matching cards' || bad 'ld1 changed native wavefunction cards'
        elif [ "$eng" = gth ]; then
            diff -r "$deck" "$imported" >/dev/null && ok 'GTH preserves all four coupled fit inputs' || bad 'GTH changed native fit inputs'
        else
            cmp -s "$deck" "$imported" && ok "$eng native physical input survives round-trip" || bad "$eng changed native physical input"
        fi
    else bad "$eng could not read its own prepared input"; fi
done
PARAMS_DIR=; GTH_REFIT=0

spec_init; SPEC[engine]=uspp; SPEC[family]=us; SPEC[engine_options]='thresh=2e-11 tol=3e-9 damp=0.4'
cp "$tmp/first/uspp/Si.ps.adat" "$tmp/ps.original"
physics_apply uspp Si "$tmp/first/uspp/Si.ps.adat" >/dev/null 2>&1
ps=$(sed -n '3p' "$tmp/first/uspp/Si.ps.adat" | cut -c1-30)
ae=$(sed -n '3p' "$tmp/first/uspp/Si.ae.adat" | cut -c1-30)
if [ "$ps" = "$ae" ] && awk -v s="$ps" 'BEGIN {exit !(substr(s,1,10)+0==2e-11 && substr(s,11,10)+0==3e-9 && substr(s,21,10)+0==0.4)}'; then
    ok 'USPP uses the same requested SCF settings in both fixed-width stages'
else bad 'USPP paired SCF controls'; fi
SPEC[engine_options]='rinner=1e-20'
before=$(sha256sum "$tmp/first/uspp/Si.ps.adat")
if physics_apply uspp Si "$tmp/first/uspp/Si.ps.adat" >/dev/null 2>&1; then bad 'USPP radius rounded to its record-layout sentinel'; else ok 'USPP refuses radii smaller than fixed-field precision'; fi
[ "$(sha256sum "$tmp/first/uspp/Si.ps.adat")" = "$before" ] && ok 'USPP precision refusal preserves the native layout' || bad 'USPP precision refusal rewrote its input'

spec_init; SPEC[engine]=oncvpsp; SPEC[family]=nc; SPEC[engine_options]='qcut.f=5'
before=$(sha256sum "$tmp/first/oncvpsp/Si.dat")
if physics_apply oncvpsp Si "$tmp/first/oncvpsp/Si.dat" >/dev/null 2>&1; then bad 'absent ONCV channel accepted'; else ok 'absent ONCV optimization channel is refused'; fi
[ "$(sha256sum "$tmp/first/oncvpsp/Si.dat")" = "$before" ] && ok 'failed native override preserves its input byte for byte' || bad 'failed native override changed its input'
awk '$0 !~ /^[[:space:]]*(#|$)/' "$tmp/first/oncvpsp/Si.dat" > "$tmp/no-comments.dat"
if ib_scale_rc oncvpsp "$tmp/no-comments.dat" 1.01 >/dev/null 2>&1; then ok 'ONCV scaling does not depend on optional comments'; else bad 'comment-free ONCV scaling'; fi
for entry in qcut.s=nan qcut.s=5junk nproj.s=0 ncon.s=6 'qcut.s=5 qcut.s=6' 'unknown=1'; do
    SPEC[engine_options]=$entry
    if physics_options_check oncvpsp >/dev/null 2>&1; then bad "accepted $entry"; else ok "refuses $entry"; fi
done
SPEC[engine_options]='ncon.s=3 nbas.s=5 nproj.s=2'
if physics_apply oncvpsp Si "$tmp/first/oncvpsp/Si.dat" >/dev/null 2>&1; then bad 'ONCV accepted too few basis functions for two projectors'; else ok 'ONCV checks basis size against continuity and projector count'; fi
SPEC[engine_options]='ncon.s=3 nbas.s=5 nproj.s=1'
if physics_apply oncvpsp Si "$tmp/first/oncvpsp/Si.dat" >/dev/null 2>&1; then ok 'ONCV accepts the native one-projector basis bound'; else bad 'ONCV one-projector basis bound'; fi

spec_init; SPEC[engine]=adpack
for entry in grid.num=20001 scf.maxIter=2001; do
    SPEC[engine_options]=$entry
    if physics_options_check adpack >/dev/null 2>&1; then bad "ADPACK accepted an array overflow: $entry"; else ok "ADPACK refuses array overflow: $entry"; fi
done
printf 'grid.num 20001\n' > "$tmp/adpack-overflow.inp"
if physics_adpack_check "$tmp/adpack-overflow.inp" >/dev/null 2>&1; then bad 'unsafe raw ADPACK grid accepted'; else ok 'ADPACK raw inputs also enforce the native grid array limit'; fi
printf 'GRID.NUM 20001\n' > "$tmp/adpack-overflow.inp"
if physics_adpack_check "$tmp/adpack-overflow.inp" >/dev/null 2>&1; then bad 'uppercase ADPACK grid bypassed its limit'; else ok 'ADPACK array guard follows native case-insensitive keyword parsing'; fi
printf 'grid.num 20000\nscf.maxIter 2000\n' > "$tmp/adpack-limits.inp"
physics_adpack_check "$tmp/adpack-limits.inp" && ok 'ADPACK accepts documented array boundaries' || bad 'ADPACK array boundaries'

spec_init; SPEC[engine]=gth; SPEC[family]=nc; SPEC[profile]=cp2k-gth; SPEC[xc]=pbe; SPEC[rel]=scalar; SPEC[formats]=gth
GTH_REFIT=1; SPEC[rcloc]=0.46; SPEC[channel_radii]='s:0.43'; SPEC[engine_options]='atom.rcov=2.1 atom.rprb=4.2'
gth_dir=$tmp/first/gth/Si.gth-inputs
if physics_gth_apply Si "$gth_dir"; then
    awk 'NR==2 {exit !($1=="f")}' "$gth_dir/psp_pbe/FITPAR" && ok 'an explicitly selected GTH local radius is fixed during fit' || bad 'GTH local radius not fixed'
    awk 'NR==4 {exit !($1=="f")}' "$gth_dir/psp_pbe/FITPAR" && ok 'an explicitly selected GTH projector radius is fixed during fit' || bad 'GTH projector radius not fixed'
    if awk 'NR==5 {exit !($1==2.1 && $2==4.2)}' "$gth_dir/atom/atom.dat" && awk 'NR==2 {exit !($1==2.1 && $2==4.2)}' "$gth_dir/psp_pbe/psp.par"; then
        ok 'GTH atom and fit inputs agree on the changed covalent and probe radii'
    else bad 'GTH coupled radii disagree'; fi
else bad 'GTH native radius changes'; fi
# Verify executor data flow independently of the expensive native minimizer.
# A library lookup here would deliberately fail; the fit must use the snapshot.
gth_inputs() { return 99; }
gth_run_fit() { mkdir -p "$1/psp"; cp "$3/psp_pbe/psp.par" "$1/psp/psp.par"; printf 'penalty: 0.01\n' > "$1/psp/fit.log"; printf '%s\n' "$1/psp/psp.par"; }
PROJECT_DIR=$tmp/execution; mkdir -p "$PROJECT_DIR/pseudos"
out=$(exec_gth Si "$gth_dir" ignored "$tmp/gth-work" "$tmp/gth.log")
if [ -s "$out" ] && awk 'NR==3 {exit !($1==0.46)}' "$out"; then ok 'GTH executor uses edited project inputs rather than looking up a library again'; else bad 'GTH executor ignored native snapshot'; fi
GTH_REFIT=0; SPEC[engine_options]=
PARAMS_DIR=$tmp/first/gth
if physics_source_check "$tmp/first/gth" >/dev/null 2>&1; then bad 'in-place import could truncate its own inputs'; else ok 'in-place native source/output overlap is refused'; fi
PARAMS_DIR=
# Native identity is part of the physical request, not a label applied later.
for eng in atompaw ape; do
    spec_init; SPEC[engine]=$eng; SPEC[family]=paw; SPEC[profile]=atompaw
    [ "$eng" != ape ] || { SPEC[family]=nc; SPEC[profile]=pseudoforge-auto; }
    SPEC[xc]=pz; SPEC[rel]=scalar; PARAMS_DIR=$tmp/first/$eng
    if ib_build "$eng" Si "$tmp/wrong-xc/$eng" >/dev/null 2>&1; then bad "$eng accepted a mislabeled native functional"; else ok "$eng refuses a native functional mismatch"; fi
    SPEC[xc]=pbe; SPEC[rel]=nonrel
    if ib_build "$eng" Si "$tmp/wrong-rel/$eng" >/dev/null 2>&1; then bad "$eng accepted mislabeled native relativity"; else ok "$eng refuses a native relativity mismatch"; fi
done
. "$PF_LIB/ui.sh"
SPEC[engine]=gth; SPEC[engine_options]='atom.rcov=2.1'; SPEC[formats]=gth
PARAMS_DIR=$tmp/first/gth; GTH_REFIT=1; GTH_CYCLES_EXPLICIT=1
ui_set_engine gth
[ "$GTH_REFIT" = 1 ] && [ -n "$PARAMS_DIR" ] && ok 'returning to the same engine preserves the manual input' || bad 'same-engine navigation lost native inputs'
ui_set_engine oncvpsp
if [ "$GTH_REFIT" = 0 ] && [ "$GTH_CYCLES_EXPLICIT" = 0 ] && [ -z "$PARAMS_DIR${SPEC[engine_options]}${SPEC[formats]}" ]; then
    ok 'changing engine clears the previous native source, controls, format and GTH fit'
else bad 'engine change retained incompatible native state'; fi
mkdir -p "$tmp/coefficient-source"
cp "$out" "$tmp/coefficient-source/Si.gth-source"
spec_init; SPEC[engine]=gth; SPEC[profile]=cp2k-gth; SPEC[family]=nc; SPEC[formats]=gth
PARAMS_DIR=$tmp/coefficient-source; GTH_REFIT=0
SPEC[xc]=pbesol; SPEC[rel]=scalar
if ib_build gth Si "$tmp/wrong-gth-xc" >/dev/null 2>&1; then bad 'GTH coefficient XC mismatch accepted'; else ok 'GTH supplied coefficient header must match the functional'; fi
SPEC[xc]=pbe; SPEC[rel]=nonrel
if ib_build gth Si "$tmp/wrong-gth-rel" >/dev/null 2>&1; then bad 'GTH coefficient table claimed a different atomic solver'; else ok 'GTH coefficient import refuses an unverifiable nonrel solver claim'; fi
SPEC[rel]=scalar
if ib_build gth Si "$tmp/copied-gth" >/dev/null 2>&1 && cmp -s "$tmp/coefficient-source/Si.gth-source" "$tmp/copied-gth/Si.gth-source"; then ok 'GTH matching supplied coefficients are copied unchanged'; else bad 'GTH coefficient import'; fi
PARAMS_DIR=
spec_init; SPEC[engine_options]='qcut.s=5.12'
[[ "$(recipe_auto_suffix)" == *-phys* ]] && ok 'typed native overrides tag the output name' || bad 'native override output looked like a stock file'
SPEC[xc]=pz
if ib_atompaw_xc >/dev/null 2>&1; then bad 'AtomPAW silently mapped PZ to PW'; else ok 'AtomPAW refuses PZ instead of emitting native PW under its name'; fi
if eng_compatible atompaw paw pz scalar pseudoforge-auto; then bad 'TUI offered native AtomPAW PZ'; else ok 'engine filtering excludes unsupported AtomPAW PZ'; fi
if (
    eng_available() { return 1; }
    params_fetch() { touch "$tmp/unexpected-fetch"; return 1; }
    PARAMS_DIR=
    build_command_for -e Si -t paw -p atompaw --engine atompaw -x pbe --params ./on-client-only --no-autofix &&
        [[ "$BUILD_CMD" == *'--params ./on-client-only'* ]]
) && [ ! -e "$tmp/unexpected-fetch" ]; then
    ok 'a server without engines renders native commands without reading client files or fetching inputs'
else bad 'command rendering depended on a server engine, client directory or download'; fi
if (
    eng_available() { return 1; }
    spec_init; SPEC[engine]=atompaw; SPEC[profile]=atompaw; SPEC[family]=paw; SPEC[xc]=pbe; SPEC[rel]=scalar
    PARAMS_DIR=; CLI_ELEMENTS=Si; CLI_OUTPUT=$tmp/no-engine-preparation
    CLI_ENGINE=atompaw; CLI_FORMATS=upf
    cmd_prepare > "$tmp/no-engine-preparation.log" 2>&1
) && [ -s "$tmp/no-engine-preparation/inputs/Si.atompaw.input" ]; then
    ok 'preparing editable native inputs does not require an installed solver'
else bad 'preparation required a solver binary'; fi
printf '%d passed, %d failed, 0 skipped\n' "$pass" "$fail"
[ "$fail" = 0 ]
