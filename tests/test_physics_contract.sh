#!/usr/bin/env bash
# Verify effects on native decks, not merely that flags reach SPEC.
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
for module in core sink config deps elements xc namelist profiles metadata formats gth sssp convert doctor params engines build recipe input_builder executor project run upf testing validate report cli http; do
    . "$PF_LIB/$module.sh" || exit 1
done
pf_config_defaults; pf_elements_load; pf_xc_load; pf_profiles_load; pf_metadata_load; pf_engines_load
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf '# isolated test config\n' > "$tmp/rc"
export PF_RC=$tmp/rc
pass=0 fail=0
ok() { printf 'PASS %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL %s\n' "$1"; fail=$((fail+1)); }
for engine in "${ENG_ORDER[@]}"; do
    while IFS= read -r key; do
        [ "$(ib_option_mode "$engine" "$key")" = unsupported ] || continue
        spec_init; SPEC[engine]=$engine; SPEC[$key]=1
        if ib_check_options "$engine" >/dev/null 2>&1; then bad "$engine accepted unsupported $key"; else ok "$engine refuses $key"; fi
    done < <(ib_option_keys)
done
for pair in 'rcut_scale:1junk' 'rcore:nan' 'tr2:inf' 'xmin:1e999' 'beta:1.1' 'nlcc:maybe' 'lloc:1.5' 'nc_form:wrong' 'config:Si;echo' 'core_hole:no' 'channel_radii:s:NaN' 'channel_radii:s:1.0 s:2.0'; do
    key=${pair%%:*}; value=${pair#*:}
    spec_init; SPEC[family]=nc; SPEC[$key]=$value
    if ib_check_options ld1 >/dev/null 2>&1; then bad "accepted $pair"; else ok "refuses $pair"; fi
done
spec_init; GTH_CYCLES_EXPLICIT=1; GTH_CYCLES=5
if ib_check_options ld1 >/dev/null 2>&1; then bad 'refit cycles silently ignored by ld1'; else ok 'refit cycles refused outside GTH refitting'; fi
GTH_REFIT=1; GTH_CYCLES=not-a-number
if ib_check_options gth >/dev/null 2>&1; then bad 'nonnumeric refit cycles'; else ok 'nonnumeric refit cycles refused'; fi
unset GTH_CYCLES_EXPLICIT GTH_REFIT GTH_CYCLES
profiles_json=$(http_h_profiles)
if printf '%s' "$profiles_json" | python3 -c 'import json,sys; p={x["id"]:x for x in json.load(sys.stdin)}; assert p["sg15"]["generatable"] and p["atompaw"]["generatable"]'; then
    ok 'web profiles include generation inputs beyond ld1'
else bad 'non-ld1 profiles missing from command builder'; fi
spec_init; SPEC[source]=online; SPEC[rcut_scale]=1.1
if ib_check_options ld1 >/dev/null 2>&1; then bad 'downloads accepted physics overrides'; else ok 'downloads refuse physics overrides'; fi

cat > "$tmp/oncv.dat" <<'DECK'
# comments and blank lines do not change positional parsing
Si 14 3 2 4 upf
1 0 2
2 0 2
2 1 6
3 0 2
3 1 2
1
0 2.0 0.0 5 8 6.0
1 2.1 0.0 5 8 6.0
4 5 2.1 0.0
0 2 1.0
1 2 1.0
3 5.0 1.3
-2 2 0.02
6 0.01
0
DECK
spec_init; SPEC[lloc]=4; SPEC[rcloc]=1.6; SPEC[nlcc]=off; SPEC[channel_radii]='s:1.7 p:1.8'
if ib_oncv_overrides "$tmp/oncv.dat" && awk '
    /^[[:space:]]*(#|$)/ {next}
    {n++; if(n==8 && $2!=1.7)exit 1; if(n==9 && $2!=1.8)exit 1;
     if(n==10 && ($1!=4 || $3!=1.6))exit 1; if(n==13 && $1!=0)exit 1}
' "$tmp/oncv.dat"; then ok 'ONCV radii, local potential and NLCC affect their actual records'; else bad 'ONCV overrides'; fi
cp "$tmp/oncv.dat" "$tmp/original.dat"
SPEC[rcloc]=7
if ib_oncv_overrides "$tmp/oncv.dat" >/dev/null 2>&1; then bad 'ONCV radius beyond output grid'; else ok 'ONCV radius beyond output grid refused'; fi
cmp -s "$tmp/oncv.dat" "$tmp/original.dat" && ok 'failed override preserves the original deck' || bad 'failed override damaged input'
SPEC[rcloc]=1.6; SPEC[lloc]=0
if ib_oncv_overrides "$tmp/oncv.dat" >/dev/null 2>&1; then bad 'unused ONCV rcloc accepted'; else ok 'unused ONCV rcloc refused'; fi

spec_init; SPEC[family]=paw; SPEC[profile]=psl-high; SPEC[channel_radii]='s:1.6:1.9'
if recipe_build Si "$tmp/ld1" >/dev/null && nml_cards "$RB_DECK" | awk '$3==0 {n++; if($6!=1.6 || $7!=1.9)exit 1} END {if(!n)exit 1}'; then
    ok 'ld1 per-channel radii affect every projector in that channel'
else bad 'ld1 channel override'; fi

for flag in --config --grid --rcut-scale --engine --projector --scales; do
    command=generate; [ "$flag" = --scales ] && command=optimise
    if timeout 5 "$ROOT/pseudoforge" "$command" "$flag" > "$tmp/err" 2>&1; then bad "$flag missing argument accepted"
    elif grep -q 'missing argument' "$tmp/err"; then ok "$flag missing argument is diagnosed"; else bad "$flag missing argument hangs or crashes"; fi
done
spec_init; SPEC[author]='O'"'"'Brien $(touch /tmp/pf-should-not-exist); literal'
CLI_ELEMENTS=Si
line=$(spec_cmdline)
# Parsing the rendered command must recover the literal string without running
# any expansion embedded in it. Replace the command with printf in a subshell.
recovered=$(bash -c "set -- ${line#pseudoforge generate }; while [ \"\$#\" -gt 0 ]; do if [ \"\$1\" = --author ]; then printf '%s' \"\$2\"; break; fi; shift; done")
[ "$recovered" = "${SPEC[author]}" ] && ok 'copyable commands preserve literal shell metacharacters' || bad 'command quoting'
PARAMS_DIR="$tmp/native inputs"; GTH_REFIT=1; GTH_CYCLES=500
line=$(spec_cmdline)
if [[ "$line" = *"--params '$tmp/native inputs'"* && "$line" = *'--refit --refit-cycles 500'* ]]; then
    ok 'copyable commands preserve native input sources and GTH refitting'
else bad 'copyable command dropped input source or refit physics'; fi
rcp_save "$tmp/native.recipe" >/dev/null
PARAMS_DIR=; unset GTH_REFIT GTH_CYCLES
rcp_load "$tmp/native.recipe" >/dev/null
if [ "$PARAMS_DIR" = "$tmp/native inputs" ] && [ "$GTH_REFIT" = 1 ] && [ "$GTH_CYCLES" = 500 ]; then
    ok 'saved recipes preserve native input sources and GTH refitting'
else bad 'saved recipe dropped input source or refit physics'; fi
PARAMS_DIR=; unset GTH_REFIT GTH_CYCLES GTH_CYCLES_EXPLICIT

# A clean exit code and valid UPF cannot redeem a bound ghost. Optional tests
# being disabled must not disable the generator diagnostic either.
cat > "$tmp/oncv-ghost" <<'GHOST'
#!/usr/bin/env bash
printf 'WARNING - GHOST(-)\nPSP_UPF\n'
cat "$PF_TEST_UPF"
printf '\nEND_PSP\n'
GHOST
chmod +x "$tmp/oncv-ghost"
if PF_TEST_UPF="$ROOT/tests/fixtures/upf/Si.pbe-oncv.UPF" ONCVPSP_BIN="$tmp/oncv-ghost" \
    "$ROOT/pseudoforge" generate -e Si -t nc -p sg15 --engine oncvpsp --format upf --no-test -o "$tmp/ghost-run" > "$tmp/ghost-log" 2>&1; then
    bad 'bound ghost accepted with --no-test'
elif grep -q 'bound ghost' "$tmp/ghost-log" && [ -z "$(find "$tmp/ghost-run/pseudos" -maxdepth 1 -iname '*.upf' -print -quit)" ]; then
    ok 'bound ghosts fail generation even with --no-test and are not installed'
else bad 'bound ghost refusal did not preserve the diagnostic'; fi

mkdir -p "$tmp/supplied"
cp "$tmp/original.dat" "$tmp/supplied/Si.dat"
spec_init; SPEC[family]=nc; SPEC[profile]=sg15; SPEC[engine]=oncvpsp
PARAMS_DIR=$tmp/supplied
SPEC[xc]=pbesol; ONCVPSP_LIBXC=0
mkdir -p "$tmp/no-libxc"
if ib_build_oncvpsp Si "$tmp/no-libxc" >/dev/null 2>&1; then
    bad 'PBEsol retargeting accepted without Libxc'
else ok 'PBEsol retargeting refuses a generator without Libxc'; fi
SPEC[xc]=pbe; unset ONCVPSP_LIBXC
located=$(params_find sg15 Si)
[ "$located" = "$tmp/supplied/Si.dat" ] && ok 'explicit --params wins over bundled and cached library inputs' || bad 'custom parameters ignored'
PARAMS_DIR=$tmp/nonexistent
if params_find sg15 Si >/dev/null 2>&1; then bad 'missing explicit --params fell back to a library'; else ok 'missing explicit --params does not fall back'; fi
PARAMS_DIR=

# Rejected artifacts remain inspectable on disk, but neither a rebuilt index
# nor a stale pre-quarantine index may make them available as downloads.
PF_NATIVE_DIR=$tmp/native; PF_CACHE_DIR=$tmp/cache
mkdir -p "$PF_NATIVE_DIR/project/pseudos/rejected" "$PF_CACHE_DIR"
cp "$ROOT/tests/fixtures/upf/Si.pbe-oncv.UPF" "$PF_NATIVE_DIR/Si.UPF"
cp "$PF_NATIVE_DIR/Si.UPF" "$PF_NATIVE_DIR/project/pseudos/rejected/Si.UPF"
if native_index_build "$PF_NATIVE_DIR" >/dev/null 2>&1 && ! grep -q '/rejected/' "$PF_NATIVE_DIR/index.tsv"; then
    ok 'native indexing excludes quarantined files'
else bad 'quarantined files entered the index'; fi
printf 'quarantine_fixture\tSi\tpbe\tnc\tscalar\toncvpsp\tupf\tsg15\tplain\tproject/pseudos/rejected/Si.UPF\t1\tunused\t\n' >> "$PF_NATIVE_DIR/index.tsv"
if http_h_native_list | grep -q quarantine_fixture; then bad 'stale quarantine entry listed'; else ok 'stale quarantine entry excluded from listing'; fi
HTTP_PARAM=quarantine_fixture; HTTP_STATUS=200
http_h_native_one >/dev/null
[ "$HTTP_STATUS" = 404 ] && ok 'stale quarantine entry cannot be retrieved' || bad 'quarantined file retrievable'
printf '%d passed, %d failed, 0 skipped\n' "$pass" "$fail"
[ "$fail" = 0 ]
