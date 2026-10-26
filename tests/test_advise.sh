#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test_advise.sh -- test suite for the advisory system
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data

for m in core sink config deps elements xc namelist profiles metadata formats gth sssp params engines recipe advise; do
    # shellcheck disable=SC1090
    . "$PF_LIB/$m.sh" || { echo "cannot load $m.sh" >&2; exit 1; }
done

pf_config_defaults 2>/dev/null || true
pf_elements_load; pf_xc_load; pf_profiles_load; pf_engines_load; pf_metadata_load; pf_params_load; pf_advice_load

GREEN=$'\033[32m'; RED=$'\033[31m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  SKIP  %s\n' "$1"; skip=$((skip + 1)); }

# ---------------------------------------------------------------------------
# 1. Knowledge Base TSV checks
# ---------------------------------------------------------------------------
check_tsv() {
    local f=$1 expected_cols=$2 expected_rows=$3
    [ -f "$f" ] || { bad_ "$f exists" "file missing"; return; }
    ok_ "$f exists"

    local rows
    rows=$(awk 'END {print NR}' "$f")
    local data_rows=$((rows - 1))
    if [ "$data_rows" -eq "$expected_rows" ]; then
        ok_ "$f row count ($data_rows)"
    else
        bad_ "$f row count" "got $data_rows, expected $expected_rows"
    fi

    local col_err
    col_err=$(awk -F'\t' -v cols="$expected_cols" '
        NR > 1 && NF != cols { print "line " NR ": NF=" NF " expected " cols }
    ' "$f")
    if [ -z "$col_err" ]; then
        ok_ "$f column count ($expected_cols)"
    else
        bad_ "$f column count" "$col_err"
    fi

    local empty_err
    empty_err=$(awk -F'\t' '
        NR > 1 {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[[:space:]]*$/) {
                    print "line " NR " col " i " is empty"
                }
            }
        }
    ' "$f")
    if [ -z "$empty_err" ]; then
        ok_ "$f has no empty fields"
    else
        bad_ "$f has no empty fields" "$empty_err"
    fi
}

check_tsv "$PF_DATA/advice/calculations.tsv" 6 12
check_tsv "$PF_DATA/advice/calculation-material.tsv" 5 8
check_tsv "$PF_DATA/advice/element-notes.tsv" 2 6

# ---------------------------------------------------------------------------
# 2. Material class detection
# ---------------------------------------------------------------------------
[ "$(el_material_class Fe)" = "transition-metal" ] && ok_ "el_material_class Fe is transition-metal" || bad_ "el_material_class Fe"
[ "$(el_material_class Si)" = "metalloid" ]        && ok_ "el_material_class Si is metalloid" || bad_ "el_material_class Si"
[ "$(el_material_class U)" = "actinide" ]          && ok_ "el_material_class U is actinide" || bad_ "el_material_class U"
[ "$(el_material_class Eu)" = "lanthanide" ]       && ok_ "el_material_class Eu is lanthanide" || bad_ "el_material_class Eu"
[ "$(el_material_class Na)" = "alkali-metal" ]     && ok_ "el_material_class Na is alkali-metal" || bad_ "el_material_class Na"
[ "$(el_material_class Ca)" = "alkaline-earth" ]   && ok_ "el_material_class Ca is alkaline-earth" || bad_ "el_material_class Ca"
[ "$(el_material_class Cl)" = "halogen" ]          && ok_ "el_material_class Cl is halogen" || bad_ "el_material_class Cl"
[ "$(el_material_class Ne)" = "noble-gas" ]        && ok_ "el_material_class Ne is noble-gas" || bad_ "el_material_class Ne"
[ "$(el_material_class O)" = "main-group" ]        && ok_ "el_material_class O is main-group" || bad_ "el_material_class O"

# ---------------------------------------------------------------------------
# 3. advise_for logic checks
# ---------------------------------------------------------------------------
if advise_for Fe phonons qe; then
    ok_ "advise_for Fe phonons exits 0"
else
    bad_ "advise_for Fe phonons" "exited non-zero"
fi

[ "$ADV_OUT_COUNT" -ge 1 ] && ok_ "Fe phonons has recommendations ($ADV_OUT_COUNT)" || bad_ "Fe phonons has recommendations"
[ "${ADV_OUT_PROFILE[0]}" = "pseudodojo" ] && ok_ "Fe phonons top profile is pseudodojo" || bad_ "Fe phonons top profile: ${ADV_OUT_PROFILE[0]:-}"
[ "${ADV_OUT_FAMILY[0]}" = "nc" ]          && ok_ "Fe phonons top family is nc" || bad_ "Fe phonons top family: ${ADV_OUT_FAMILY[0]:-}"
[ "${ADV_OUT_XC[0]}" = "pbesol" ]          && ok_ "Fe phonons top xc is pbesol" || bad_ "Fe phonons top xc: ${ADV_OUT_XC[0]:-}"
[ "${ADV_OUT_SCORE[0]}" -eq 18 ]           && ok_ "Fe phonons top score is 18" || bad_ "Fe phonons top score: ${ADV_OUT_SCORE[0]:-}"
[ -n "${ADV_OUT_CUTOFF_VAL[0]}" ]          && ok_ "Fe phonons has cutoff (${ADV_OUT_CUTOFF_VAL[0]} Ry)" || bad_ "Fe phonons missing cutoff"

# Check that material override why is attached only to the profile hint (PseudoDojo)
dojo_why_matches=0
other_why_matches=0
for ((i=0; i<ADV_OUT_COUNT; i++)); do
    if [[ "${ADV_OUT_WHY[i]}" == *"PseudoDojo's stringent NC sets have been validated"* ]]; then
        if [ "${ADV_OUT_PROFILE[i]}" = "pseudodojo" ]; then
            dojo_why_matches=$((dojo_why_matches + 1))
        else
            other_why_matches=$((other_why_matches + 1))
        fi
    fi
done
[ "$dojo_why_matches" -eq 1 ] && [ "$other_why_matches" -eq 0 ] \
    && ok_ "material override why attached to pseudodojo only" \
    || bad_ "material override why attached incorrectly (dojo=$dojo_why_matches, other=$other_why_matches)"

# Avoid list checks
has_psl_low=0
has_psl_tot=0
for ((i=0; i<ADV_OUT_AVOID_COUNT; i++)); do
    [ "${ADV_OUT_AVOID_WHAT[i]}" = "psl-low" ] && has_psl_low=1
    [ "${ADV_OUT_AVOID_WHAT[i]}" = "psl-tot" ] && has_psl_tot=1
done
[ "$has_psl_low" -eq 1 ] && ok_ "avoid list includes psl-low for phonons" || bad_ "avoid list missing psl-low"
[ "$has_psl_tot" -eq 1 ] && ok_ "avoid list includes psl-tot" || bad_ "avoid list missing psl-tot"

# JSON rendering check
fe_json=$(advise_render_json)
if printf '%s\n' "$fe_json" | python3 -m json.tool >/dev/null 2>&1; then
    ok_ "advise_render_json emits valid JSON"
else
    bad_ "advise_render_json emits valid JSON" "$fe_json"
fi

# Check schema keys
python3 -c '
import json, sys
data = json.loads(sys.stdin.read())
req_top = ["element", "element_name", "material_class", "calculation", "code", "recommendations", "avoid", "related"]
for k in req_top:
    assert k in data, f"missing top key: {k}"
assert len(data["recommendations"]) > 0, "empty recommendations"
rec = data["recommendations"][0]
req_rec = ["rank", "score", "profile", "profile_label", "family", "xc", "engine", "engine_label", "format", "why", "caveats", "citations", "cli_command"]
for k in req_rec:
    assert k in rec, f"missing rec key: {k}"
' <<< "$fe_json" && ok_ "Fe phonons JSON matches schema keys exactly" || bad_ "JSON schema key validation failed"

# Si gw check
if advise_for Si gw; then
    ok_ "advise_for Si gw exits 0"
    [ "${ADV_OUT_PROFILE[0]}" = "pseudodojo" ] && ok_ "Si gw top profile is pseudodojo" || bad_ "Si gw top profile: ${ADV_OUT_PROFILE[0]:-}"
    [ "${ADV_OUT_XC[0]}" = "pbe" ]              && ok_ "Si gw top xc is pbe" || bad_ "Si gw top xc: ${ADV_OUT_XC[0]:-}"
    [ -n "${ADV_OUT_CUTOFF_VAL[0]}" ]           && ok_ "Si gw has cutoff (${ADV_OUT_CUTOFF_VAL[0]} Ry)" || bad_ "Si gw missing cutoff"
else
    bad_ "advise_for Si gw failed"
fi

# Overview mode check
if advise_for Fe; then
    ok_ "advise_for Fe (overview) exits 0"
    [ "$ADV_OUT_IS_OVERVIEW" -eq 1 ] && ok_ "overview flag set" || bad_ "overview flag not set"
    [ "$ADV_OVERVIEW_COUNT" -eq 12 ] && ok_ "overview covered 12 calculations" || bad_ "overview count: $ADV_OVERVIEW_COUNT"
    fe_over_json=$(advise_render_json)
    if printf '%s\n' "$fe_over_json" | python3 -m json.tool >/dev/null 2>&1; then
        ok_ "overview JSON is valid"
    else
        bad_ "overview JSON invalid"
    fi
else
    bad_ "advise_for Fe overview failed"
fi

# ---------------------------------------------------------------------------
# 4. CLI Dispatcher & flag parsing
# ---------------------------------------------------------------------------
help_out=$("$ROOT/pseudoforge" advise --help 2>&1)
[ $? -eq 0 ] && [[ "$help_out" =~ "usage: pseudoforge advise" ]] && ok_ "pseudoforge advise --help exits 0" || bad_ "pseudoforge advise --help"

err_out=$("$ROOT/pseudoforge" advise 2>&1 || true)
[[ "$err_out" =~ "usage: pseudoforge advise" ]] && ok_ "pseudoforge advise without -e fails with usage" || bad_ "pseudoforge advise missing -e"

quiet_cmd=$("$ROOT/pseudoforge" advise -e Fe --calculation phonons -q 2>&1)
[[ "$quiet_cmd" =~ ^pseudoforge\ generate\ -e\ Fe ]] && ok_ "pseudoforge advise -q returns cli command" || bad_ "pseudoforge advise -q: $quiet_cmd"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Run quiet command with --dry-run
read -r -a dry_args <<< "${quiet_cmd#pseudoforge }"
if ( cd "$TMP_DIR" && "$ROOT/pseudoforge" "${dry_args[@]}" --dry-run -q ); then
    ok_ "recommended CLI command runs cleanly under --dry-run -q"
else
    bad_ "recommended CLI command failed under --dry-run"
fi

# CLI --json flag
cli_json=$("$ROOT/pseudoforge" advise -e Fe --calculation phonons --json 2>&1)
if printf '%s\n' "$cli_json" | python3 -m json.tool >/dev/null 2>&1; then
    ok_ "pseudoforge advise --json outputs valid JSON"
else
    bad_ "pseudoforge advise --json emitted invalid JSON"
fi

# ---------------------------------------------------------------------------
# 5. REST API (/api/advise)
# ---------------------------------------------------------------------------
api_get_json=$("$ROOT/pseudoforge" api GET '/api/advise?element=Fe&calculation=phonons' 2>"$TMP_DIR/api_get.err")
api_get_st=$(grep '^status:' "$TMP_DIR/api_get.err" | awk '{print $2}')
[ "$api_get_st" = "200" ] && ok_ "GET /api/advise returns status 200" || bad_ "GET /api/advise status: $api_get_st"
if printf '%s\n' "$api_get_json" | python3 -m json.tool >/dev/null 2>&1; then
    ok_ "GET /api/advise outputs valid JSON"
else
    bad_ "GET /api/advise invalid JSON"
fi

cat <<'EOF' > "$TMP_DIR/post_body.json"
{
  "element": "Si",
  "calculation": "gw"
}
EOF
api_post_json=$("$ROOT/pseudoforge" api POST /api/advise "$TMP_DIR/post_body.json" 2>"$TMP_DIR/api_post.err")
api_post_st=$(grep '^status:' "$TMP_DIR/api_post.err" | awk '{print $2}')
[ "$api_post_st" = "200" ] && ok_ "POST /api/advise returns status 200" || bad_ "POST /api/advise status: $api_post_st"
if printf '%s\n' "$api_post_json" | python3 -m json.tool >/dev/null 2>&1; then
    ok_ "POST /api/advise outputs valid JSON"
else
    bad_ "POST /api/advise invalid JSON"
fi

api_bad_json=$("$ROOT/pseudoforge" api GET '/api/advise' 2>"$TMP_DIR/api_bad.err" || true)
api_bad_st=$(grep '^status:' "$TMP_DIR/api_bad.err" | awk '{print $2}')
[ "$api_bad_st" = "400" ] && ok_ "GET /api/advise without element returns status 400" || bad_ "GET /api/advise without element status: $api_bad_st"

# ---------------------------------------------------------------------------
# 6. Comprehensive coverage
# ---------------------------------------------------------------------------
# Every calculation ID produces a recommendation for Fe and Si
for c in "${ADV_CALC_ORDER[@]}"; do
    advise_for Fe "$c" >/dev/null 2>&1
    [ "${#ADV_OUT_PROFILE[@]}" -gt 0 ] && ok_ "Fe $c produces recommendation (${ADV_OUT_PROFILE[0]})" || bad_ "Fe $c has no recommendations"

    advise_for Si "$c" >/dev/null 2>&1
    [ "${#ADV_OUT_PROFILE[@]}" -gt 0 ] && ok_ "Si $c produces recommendation (${ADV_OUT_PROFILE[0]})" || bad_ "Si $c has no recommendations"
done

# Sample of 10 elements produces at least one recommendation
for el in H C Si Fe Ni Cu Ag Au U Ce; do
    advise_for "$el" eos >/dev/null 2>&1
    [ "${#ADV_OUT_PROFILE[@]}" -gt 0 ] && ok_ "element $el produces recommendation (${ADV_OUT_PROFILE[0]})" || bad_ "element $el produces no recommendation"
done

# ---------------------------------------------------------------------------
# 7. End-to-end smoke — advise, render, and dry-run every recommendation
# ---------------------------------------------------------------------------
smoke_txt=$("$ROOT/pseudoforge" advise -e Fe --calculation phonons 2>&1)
[[ "$smoke_txt" == *"For Fe, phonons:"* ]] && ok_ "smoke: human text contains element and calculation" || bad_ "smoke: human text header missing"
[[ "$smoke_txt" == *"1. "* && "$smoke_txt" == *"2. "* && "$smoke_txt" == *"3. "* ]] && ok_ "smoke: human text renders 3 ranked recommendations" || bad_ "smoke: missing ranked recommendations"
[[ "$smoke_txt" == *"Why:"* ]] && ok_ "smoke: human text renders Why explanation" || bad_ "smoke: Why explanation missing"
[[ "$smoke_txt" == *"Engine:"* && "$smoke_txt" == *"Library:"* ]] && ok_ "smoke: human text renders citations" || bad_ "smoke: citations missing"
[[ "$smoke_txt" == *"pseudoforge generate"* ]] && ok_ "smoke: human text renders cli command" || bad_ "smoke: cli command missing"
[[ "$smoke_txt" == *"Avoid:"* ]] && ok_ "smoke: human text renders avoid section" || bad_ "smoke: avoid section missing"

smoke_cases=(
    "Fe phonons"
    "Si gw"
    "C eos"
    "Ni magnetism"
    "Ti elastic"
)

for case_spec in "${smoke_cases[@]}"; do
    el="${case_spec%% *}"
    calc="${case_spec#* }"
    json_out=$("$ROOT/pseudoforge" advise -e "$el" --calculation "$calc" --json 2>&1)
    cmd_count=0
    while IFS= read -r rcmd; do
        [ -n "$rcmd" ] || continue
        cmd_count=$((cmd_count + 1))
        read -r -a rargs <<< "${rcmd#pseudoforge }"
        if ( cd "$TMP_DIR" && "$ROOT/pseudoforge" "${rargs[@]}" --dry-run -q ); then
            ok_ "smoke: dry-run passed for: $rcmd"
        else
            bad_ "smoke: dry-run failed for: $rcmd"
        fi
    done < <(printf '%s\n' "$json_out" | python3 -c '
import sys, json
data = json.load(sys.stdin)
for r in data.get("recommendations", []):
    print(r.get("cli_command", ""))
')
    [ "$cmd_count" -gt 0 ] && ok_ "smoke: $el $calc generated $cmd_count recommendations" || bad_ "smoke: $el $calc generated 0 recommendations"
done

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
