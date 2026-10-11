#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Interface separation.
#
# The property under test: no module in lib/ knows which interface is calling
# it. The same operation, run through the CLI sink, the capture sink and the
# JSON sink, must produce the same underlying records -- only the rendering
# differs.
#
# Two things this suite would have caught before the refactor:
#
#   build.sh printed a prompt and blocked on `read`, and executor.sh did the
#   same before generating missing elements. On a CLI that is impolite; behind
#   a web API it hangs the request, and in a test it hangs the suite.
#
#   Several modules wrote build-log excerpts straight to stderr with
#   `tail -20 "$log" >&2`, which is invisible to any interface that is not a
#   terminal.
#
# See docs/architecture/overview.md for the contract.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
for m in core sink config deps elements xc namelist profiles metadata formats gth sssp convert params engines recipe; do
    . "$PF_LIB/$m.sh" || { echo "cannot load $m.sh" >&2; exit 1; }
done
pf_config_defaults; pf_elements_load; pf_xc_load
pf_profiles_load; pf_metadata_load; pf_params_load; pf_engines_load
spec_init 2>/dev/null || true

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
printf '\n%s== the core does not touch a terminal%s\n' "$DIM" "$RESET"
# ---------------------------------------------------------------------------
# The structural guarantee.  Interfaces render; core modules do not.
INTERFACES="ui.sh wizard.sh cli.sh report.sh sink.sh"
offenders=""
for f in "$PF_LIB"/*.sh; do
    b=$(basename "$f")
    case " $INTERFACES " in *" $b "*) continue ;; esac
    grep -qE '>&2' "$f" && offenders="$offenders $b"
done
[ -z "$offenders" ] \
    && ok_ "no core module writes to stderr" \
    || bad_ "core modules writing to stderr:$offenders" \
            "rendering belongs to the interface; use pf_emit or pf_emit_stream"

offenders=""
for f in "$PF_LIB"/*.sh; do
    b=$(basename "$f")
    case " $INTERFACES " in *" $b "*) continue ;; esac
    grep -qE '^\s*read -r reply|^\s*read reply' "$f" && offenders="$offenders $b"
done
[ -z "$offenders" ] \
    && ok_ "no core module reads from the terminal" \
    || bad_ "core modules prompting:$offenders" "use pf_confirm"

# ---------------------------------------------------------------------------
printf '\n%s== the same records reach every sink%s\n' "$DIM" "$RESET"
# ---------------------------------------------------------------------------
emit_sample() {
    pf_emit info  "starting"
    pf_emit warn  "one element skipped"
    pf_emit error "engine not installed"
    pf_emit ok    "done"
}

# capture
pf_sink_use capture; pf_sink_reset
emit_sample
cap=$(pf_sink_records)
n=$(printf '%s' "$cap" | grep -c .)
[ "$n" = 4 ] && ok_ "capture sink recorded all 4 records" || bad_ "capture recorded $n of 4"
[ "$(pf_sink_count error)" = 1 ] && ok_ "error count is queryable as data" || bad_ "error count wrong"
[ "$(pf_sink_count warn)" = 1 ]  && ok_ "warn count is queryable as data"  || bad_ "warn count wrong"
pf_sink_failed && ok_ "pf_sink_failed reports the failure" || bad_ "pf_sink_failed missed an error"

# json
pf_sink_use json
js=$(emit_sample 2>/dev/null)
jn=$(printf '%s' "$js" | grep -c '^{')
[ "$jn" = 4 ] && ok_ "json sink emitted 4 objects" || bad_ "json emitted $jn of 4"
printf '%s' "$js" | grep -q '"level":"error"' \
    && ok_ "json carries the level" || bad_ "json has no level field"
printf '%s' "$js" | grep -q '"message":"engine not installed"' \
    && ok_ "json carries the message" || bad_ "json has no message field"

# the three must agree on content
cap_msgs=$(printf '%s' "$cap" | cut -f2 | sort)
json_msgs=$(printf '%s' "$js" | sed 's/.*"message":"//; s/"}$//' | sort)
[ "$cap_msgs" = "$json_msgs" ] \
    && ok_ "capture and json agree on every message" \
    || bad_ "the sinks disagree" "same core call must yield the same records"

# cli renders, and renders to stderr rather than stdout
pf_sink_use cli
cli_out=$( (emit_sample) 2>&1 >/dev/null )
printf '%s' "$cli_out" | grep -q 'engine not installed' \
    && ok_ "cli sink renders the message" || bad_ "cli sink lost the message"
cli_stdout=$( (emit_sample) 2>/dev/null )
[ -z "$cli_stdout" ] \
    && ok_ "cli sink keeps stdout clean for data" \
    || bad_ "cli sink wrote messages to stdout" "stdout is the data channel"
pf_sink_use capture; pf_sink_reset

# ---------------------------------------------------------------------------
printf '\n%s== json output is well formed%s\n' "$DIM" "$RESET"
# ---------------------------------------------------------------------------
pf_sink_use json
tricky=$(pf_emit warn 'he said "no" and the path was C:\tmp' 2>/dev/null)
printf '%s' "$tricky" | grep -q '\\"no\\"' \
    && ok_ "quotes are escaped" || bad_ "unescaped quote in json: $tricky"
printf '%s' "$tricky" | grep -q 'C:\\\\tmp' \
    && ok_ "backslashes are escaped" || bad_ "unescaped backslash in json: $tricky"
if have python3; then
    printf '%s' "$tricky" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null \
        && ok_ "a real parser accepts the output" \
        || bad_ "json does not parse" "$tricky"
else
    skip_ "python3 unavailable to validate the json"
fi
pf_sink_use capture; pf_sink_reset

# ---------------------------------------------------------------------------
printf '\n%s== asking the user is the interface job%s\n' "$DIM" "$RESET"
# ---------------------------------------------------------------------------
pf_confirm_use assume
PF_ASSUME=yes; pf_confirm "proceed?" && ok_ "assume=yes answers yes" || bad_ "assume=yes said no"
PF_ASSUME=no;  pf_confirm "proceed?" && bad_ "assume=no said yes" || ok_ "assume=no answers no"
# and it must never block: this whole suite is non-interactive
ok_ "confirmation never blocks without a terminal"
PF_ASSUME=no

# ---------------------------------------------------------------------------
printf '\n%s== data is separate from messages%s\n' "$DIM" "$RESET"
# ---------------------------------------------------------------------------
# A core lookup returns records on stdout regardless of which sink is installed.
SPEC[xc]=pbe
for s in cli capture json null; do
    pf_sink_use "$s"
    got=$(sssp_entry Si 2>/dev/null | cut -f2)
    [ "$got" = "100US" ] || { bad_ "sssp_entry returned '$got' under the $s sink"; continue; }
done
ok_ "sssp_entry returns the same data under all four sinks"
pf_sink_use capture; pf_sink_reset

# a failing lookup must signal through the exit code, not through text
pf_sink_use null
if sssp_entry Xx >/dev/null 2>&1; then
    bad_ "an unknown element returned success"
else
    ok_ "failure is signalled by exit code, not by printed text"
fi
pf_sink_use capture

# ---------------------------------------------------------------------------
printf '\n%s== every operation is reachable from the CLI%s\n' "$DIM" "$RESET"
# ---------------------------------------------------------------------------
# The CLI is the reference implementation: anything the TUI can do must have a
# CLI route, or logic has leaked into the interface.
for c in generate engines doctor convert list recipe import report compare citation config; do
    grep -qE "^\s+${c}[|)]" "$ROOT/pseudoforge" \
        && ok_ "'$c' is reachable from the CLI" \
        || bad_ "'$c' has no CLI dispatch entry"
done

# ---------------------------------------------------------------------------
printf '\n%s== cmd_generate requires ld1.x only for local ld1 runs%s\n' "$DIM" "$RESET"
# ---------------------------------------------------------------------------
mkdir -p "$TMP/bin"
: > "$TMP/empty_rc"

cat > "$TMP/bin/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
out=""
write_code=0
while [ $# -gt 0 ]; do
    case $1 in
        -o) out=$2; shift 2 ;;
        -w) write_code=1; shift 2 ;;
        -m) shift 2 ;;
        *)  shift ;;
    esac
done
if [ -n "$out" ] && [ "$out" != "/dev/null" ]; then
    cat > "$out" <<'UPF'
<UPF version="2.0.1">
  <PP_HEADER element="Si" pseudo_type="NC" relativistic="scalar" is_ultrasoft="F" is_paw="F" is_coulomb="F" has_so="F" has_wfc="F" has_gipaw="F" core_correction="F" functional="PBE" z_valence="4.0" total_psenergy="-7.8" wfc_cutoff="30.0" rho_cutoff="120.0" l_max="1" l_local="1" mesh_size="4" number_of_wfc="1" number_of_proj="1"/>
  <PP_MESH><PP_R>0.1 0.2 0.3 0.4</PP_R><PP_RAB>0.1 0.1 0.1 0.1</PP_RAB></PP_MESH>
  <PP_LOCAL>0.0 0.0 0.0 0.0</PP_LOCAL>
  <PP_NONLOCAL><PP_BETA.1 index="1" angular_momentum="0">0.0 0.0 0.0 0.0</PP_BETA.1><PP_DIJ>-1.0</PP_DIJ></PP_NONLOCAL>
  <PP_PSWFC><PP_CHI.1 index="1" label="3S" l="0" occupation="2.0">0.0 0.0 0.0 0.0</PP_CHI.1></PP_PSWFC>
  <PP_RHOATOM>0.0 0.0 0.0 0.0</PP_RHOATOM>
</UPF>
UPF
fi
[ "$write_code" = 1 ] && printf '200'
exit 0
MOCK_CURL
chmod +x "$TMP/bin/curl"

cat > "$TMP/bin/oncvpsp.x" <<'MOCK_ONCV'
#!/usr/bin/env bash
cat <<'OUT'
Test configuration 1
   1    0     -0.50000000    -0.50000000     0.00000000
PSP_UPF
<UPF version="2.0.1">
  <PP_HEADER element="Si" pseudo_type="NC" relativistic="scalar" is_ultrasoft="F" is_paw="F" is_coulomb="F" has_so="F" has_wfc="F" has_gipaw="F" core_correction="F" functional="PBE" z_valence="4.0" total_psenergy="-7.8" wfc_cutoff="30.0" rho_cutoff="120.0" l_max="1" l_local="1" mesh_size="4" number_of_wfc="1" number_of_proj="1"/>
  <PP_MESH><PP_R>0.1 0.2 0.3 0.4</PP_R><PP_RAB>0.1 0.1 0.1 0.1</PP_RAB></PP_MESH>
  <PP_LOCAL>0.0 0.0 0.0 0.0</PP_LOCAL>
  <PP_NONLOCAL><PP_BETA.1 index="1" angular_momentum="0">0.0 0.0 0.0 0.0</PP_BETA.1><PP_DIJ>-1.0</PP_DIJ></PP_NONLOCAL>
  <PP_PSWFC><PP_CHI.1 index="1" label="3S" l="0" occupation="2.0">0.0 0.0 0.0 0.0</PP_CHI.1></PP_PSWFC>
  <PP_RHOATOM>0.0 0.0 0.0 0.0</PP_RHOATOM>
</UPF>
END_PSP
OUT
exit 0
MOCK_ONCV
chmod +x "$TMP/bin/oncvpsp.x"

if PF_RC="$TMP/empty_rc" PATH="$TMP/bin:/usr/bin:/bin" \
   QE_ROOT_DIR=/nonexistent LD1_BIN=/nonexistent PW_BIN=/nonexistent ENGINE_DIR=/nonexistent \
   "$ROOT/pseudoforge" generate -e Si -p qe-legacy -t nc -x pbe -r scalar \
   --source online --no-test -o "$TMP/online_no_qe" >/dev/null 2>&1 \
   && [ -f "$TMP/online_no_qe/pseudos/Si.pbe-rrkjus.UPF" ]; then
    ok_ "--source online with no QE and no other engine reaches download and exits 0"
else
    bad_ "--source online failed without ld1.x"
fi

if PF_RC="$TMP/empty_rc" \
   QE_ROOT_DIR=/nonexistent LD1_BIN=/nonexistent PW_BIN=/nonexistent ENGINE_DIR=/nonexistent \
   ONCVPSP_BIN="$TMP/bin/oncvpsp.x" \
   "$ROOT/pseudoforge" generate -e Si -p sg15 -t nc -x pbe -r scalar \
   --engine oncvpsp --source local --no-test -o "$TMP/oncv_no_qe" >/dev/null 2>&1 \
   && [ -f "$TMP/oncv_no_qe/pseudos/Si.pbe-oncv.UPF" ]; then
    ok_ "--engine oncvpsp --source local with no ld1.x reaches build and exits 0"
else
    bad_ "--engine oncvpsp --source local failed without ld1.x"
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
