#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# doctor, through all three interfaces.
#
# The property under test: the checks run once and produce records; the CLI,
# the TUI and the JSON endpoint render the same records differently. If any
# renderer disagrees with another about what was found, the split has failed
# and one of them is running its own checks.
#
# Before the split, cmd_doctor interleaved printf with the checks themselves.
# A TUI panel or a JSON endpoint could only have been built by running the
# checks again and scraping printed text -- which is how two interfaces end up
# disagreeing about the same machine.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
for m in core sink config deps elements xc namelist profiles metadata formats gth sssp convert doctor params engines build recipe; do
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

RECS=$(doctor_checks)

printf '\n%s== the checks produce records, not output%s\n' "$DIM" "$RESET"
n=$(printf '%s\n' "$RECS" | grep -c .)
[ "$n" -gt 10 ] && ok_ "$n records produced" || bad_ "only $n records"

# Every record must have all five fields.
bad_rows=$(printf '%s\n' "$RECS" | awk -F'\t' 'NF != 5 { n++ } END { print n + 0 }')
[ "$bad_rows" = 0 ] \
    && ok_ "every record has all five fields" \
    || bad_ "$bad_rows record(s) are malformed" "category/name/status/detail/fix"

# Status must be one of the four.
bad_st=$(printf '%s\n' "$RECS" | awk -F'\t' \
    '$3 != "ok" && $3 != "missing" && $3 != "optional" && $3 != "info" { n++ } END { print n + 0 }')
[ "$bad_st" = 0 ] && ok_ "every status is one of ok/missing/optional/info" \
    || bad_ "$bad_st record(s) carry an unknown status"

# doctor_checks must not report through the sink: a finding is not a warning.
pf_sink_use capture; pf_sink_reset
doctor_checks >/dev/null
[ "$(pf_sink_count)" = 0 ] \
    && ok_ "the checks emit nothing through the sink" \
    || bad_ "the checks reported $(pf_sink_count) message(s)" \
            "whether a finding deserves a yellow line is the interface's decision"
pf_sink_use cli

printf '\n%s== all three renderers see the same findings%s\n' "$DIM" "$RESET"
cli=$(doctor_render_cli "$RECS" 2>&1)
jsn=$(doctor_render_json "$RECS")
tui=$(doctor_render_tui "$RECS")

[ -n "$cli" ] && ok_ "cli renderer produced output"  || bad_ "cli renderer produced nothing"
[ -n "$jsn" ] && ok_ "json renderer produced output" || bad_ "json renderer produced nothing"
[ -n "$tui" ] && ok_ "tui renderer produced output"  || bad_ "tui renderer produced nothing"

# The JSON must carry exactly the records, one object each.
nj=$(printf '%s\n' "$jsn" | grep -c '^{')
[ "$nj" = "$n" ] \
    && ok_ "json has one object per record ($nj)" \
    || bad_ "json has $nj objects for $n records"

# and every engine the records name must appear in the CLI report
missing=""
while IFS=$'\t' read -r cat name st detail fix; do
    [ "$cat" = engine ] || continue
    printf '%s' "$cli" | grep -qF "$name" || missing="$missing|$name"
done <<< "$RECS"
[ -z "$missing" ] \
    && ok_ "every engine in the records appears in the cli report" \
    || bad_ "cli report omits:$missing"

# The counts the three agree on: engines ok.
eng_ok=$(doctor_count "$RECS" engine ok)
json_eng_ok=$(printf '%s\n' "$jsn" | grep -c '"category":"engine","name":"[^"]*","status":"ok"')
[ "$eng_ok" = "$json_eng_ok" ] \
    && ok_ "cli and json agree on engines available ($eng_ok)" \
    || bad_ "records say $eng_ok engines ok, json says $json_eng_ok"

tui_eng=$(printf '%s\n' "$tui" | awk '/^Engines/ { print $2 }')
[ "$tui_eng" = "$eng_ok" ] \
    && ok_ "tui agrees on engines available ($tui_eng)" \
    || bad_ "tui says $tui_eng engines ok, records say $eng_ok"

printf '\n%s== json is machine readable%s\n' "$DIM" "$RESET"
if have python3; then
    out=$(printf '%s\n' "$jsn" | python3 -c '
import json,sys
n=0
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    d=json.loads(line)
    for k in ("category","name","status","detail","fix"):
        assert k in d, "missing key "+k
    n+=1
print(n)' 2>&1)
    case $out in
        ''|*[!0-9]*) bad_ "json does not parse" "$(printf '%s' "$out" | head -1)" ;;
        *)           ok_ "a real parser accepts all $out objects with every key" ;;
    esac
else
    skip_ "python3 unavailable"
fi

# Paths with spaces are the usual way this breaks -- this tree has one.
printf '%s\n' "$jsn" | grep -q '"detail":"[^"]*Pseudo Maker' \
    && ok_ "a path containing a space survives serialisation" \
    || skip_ "no spaced path in this environment to check"

printf '\n%s== the tui panel fits in 80x24%s\n' "$DIM" "$RESET"
IFS=$'\t' read -r rows cols < <(doctor_tui_size "$tui")
# whiptail takes about 6 columns and 7 rows for frame, title and button
[ "$rows" -le 16 ] \
    && ok_ "panel is $rows rows (16 usable in an 80x24 terminal)" \
    || bad_ "panel is $rows rows -- it would scroll off an 80x24 terminal"
[ "$cols" -le 72 ] \
    && ok_ "panel is $cols columns (72 usable)" \
    || bad_ "panel is $cols columns -- it would wrap or be cut"

# And it must stay within bounds when everything is broken, which is when the
# panel is longest and when a user most needs to read it.
worst=$(for i in 1 2 3 4 5 6 7 8 9; do
            doctor_record engine "Very Long Engine Name Number $i" missing \
                "not built" "pseudoforge engines build engine$i"
        done
        for t in gfortran gcc make awk sed; do
            doctor_record toolchain "$t" missing "not on PATH" "install $t from your package manager"
        done)
wt=$(doctor_render_tui "$worst")
IFS=$'\t' read -r wrows wcols < <(doctor_tui_size "$wt")
[ "$wcols" -le 72 ] \
    && ok_ "stays within 72 columns even with everything missing ($wcols)" \
    || bad_ "panel reaches $wcols columns when everything is missing"

printf '\n%s== the cli command exposes options%s\n' "$DIM" "$RESET"
for flag in '--json' '--tui' '--check'; do
    grep -q -- "$flag" "$PF_LIB/cli.sh" \
        && ok_ "pseudoforge doctor $flag is wired" \
        || bad_ "$flag is not accepted by cmd_doctor"
done
grep -q 'deps_report' "$PF_LIB/cli.sh" \
    && ok_ "the cli path still includes deps_report" \
    || bad_ "deps_report was dropped from doctor" "it was part of this command before the split"

printf '\n%s== a fix is a field, not a sentence%s\n' "$DIM" "$RESET"
# So an interface can offer it as a button without parsing prose.
nfix=$(printf '%s\n' "$RECS" | awk -F'\t' '$5 != "" { n++ } END { print n + 0 }')
if [ "$nfix" -gt 0 ]; then
    runnable=$(printf '%s\n' "$RECS" | awk -F'\t' '$5 ~ /^(pseudoforge|install|sudo|brew) / { n++ } END { print n + 0 }')
    [ "$runnable" = "$nfix" ] \
        && ok_ "all $nfix fix fields are runnable commands" \
        || bad_ "$((nfix - runnable)) fix field(s) are prose, not commands"
else
    ok_ "nothing is missing on this machine, so no fix fields to check"
fi

printf '\n%s== Phase 1 doctor requirements%s\n' "$DIM" "$RESET"
# BLAS/LAPACK probe is called
printf '%s\n' "$RECS" | grep -q 'BLAS/LAPACK' \
    && ok_ "BLAS/LAPACK probe is called" \
    || bad_ "BLAS/LAPACK probe missing from records"

# unzip and python3 probes are called
printf '%s\n' "$RECS" | grep -q $'\tunzip\t' \
    && ok_ "unzip probe is called" \
    || bad_ "unzip probe missing from records"

printf '%s\n' "$RECS" | grep -q $'\tpython3\t' \
    && ok_ "python3 probe is called" \
    || bad_ "python3 probe missing from records"

# Simulated missing dep: doctor --check exits 1 naming missing curl
missing_sim=$(
    fake_dir=$(mktemp -d)
    for c in bash sh awk sed grep sort cut tr find mkdir mktemp date dirname pwd readlink cat head tail wc uname rm ls ps sleep gfortran gcc make; do
        p=$(command -v "$c" 2>/dev/null) && [ -n "$p" ] && ln -sf "$p" "$fake_dir/$c"
    done
    out=$(PATH="$fake_dir" "$ROOT/pseudoforge" doctor --check 2>&1)
    rc=$?
    rm -rf "$fake_dir"
    printf '%s\n__EXIT_CODE__=%d' "$out" "$rc"
)
sim_rc=$(printf '%s\n' "$missing_sim" | awk -F'=' '/^__EXIT_CODE__=/ { print $2 }')
if [ "$sim_rc" = "1" ] && printf '%s\n' "$missing_sim" | grep -q 'curl'; then
    ok_ "doctor --check exits 1 naming missing curl"
else
    bad_ "doctor --check did not exit 1 or name missing curl (rc=$sim_rc)" "$missing_sim"
fi

# deps_report offers adpack as buildable
adpack_rep=$(
    (
        eng_available() { [ "$1" != adpack ] && command eng_available "$@"; }
        deps_report 2>&1
    )
)
if printf '%s\n' "$adpack_rep" | grep -F "ADPACK" -A2 | grep -q "pseudoforge engines build adpack"; then
    ok_ "deps_report offers adpack as buildable"
else
    bad_ "deps_report did not offer adpack as buildable" "$adpack_rep"
fi

printf '\n%s== doctor leaves no stray files in working directory%s\n' "$DIM" "$RESET"
clean_dir=$(mktemp -d)
(
    cd "$clean_dir" || exit 1
    "$ROOT/pseudoforge" doctor >/dev/null 2>&1
)
if [ -e "$clean_dir/input_tmp.in" ]; then
    bad_ "doctor created input_tmp.in in CWD"
else
    ok_ "doctor leaves no input_tmp.in in CWD"
fi
rm -rf "$clean_dir"

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
