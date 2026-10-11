#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Fetch candidate names and mirror URL construction.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
for m in core sink config deps elements xc namelist profiles metadata recipe fetch; do
    . "$PF_LIB/$m.sh" || { echo "cannot load $m.sh" >&2; exit 1; }
done
pf_config_defaults; pf_elements_load; pf_xc_load
pf_profiles_load; pf_metadata_load; spec_init

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export TMPDIR=$TMP

cache=$(fetch_index_cache sg15)
cat > "$cache" <<'EOF'
Si_ONCV_PBE-1.0.upf
Si_ONCV_PBE-1.2.upf
Si_ONCV_PBE_FR-1.1.upf
EOF
touch "$cache"

printf '\n%s== fetch_candidate_names sg15 returns bare filenames%s\n' "$DIM" "$RESET"
cands=$(base="https://pseudo.amirkhani.me/library/" fetch_candidate_names sg15 Si)
[ -n "$cands" ] \
    && ok_ "fetch_candidate_names sg15 Si returned candidates" \
    || bad_ "fetch_candidate_names sg15 Si returned empty"

bad_cand=""
while IFS= read -r line; do
    [ -n "$line" ] || continue
    case $line in
        *://* | */*) bad_cand=$line ;;
    esac
done <<<"$cands"
[ -z "$bad_cand" ] \
    && ok_ "every line from fetch_candidate_names sg15 Si contains no scheme and no slash ($cands)" \
    || bad_ "candidate name contained scheme or slash: $bad_cand"

printf '\n%s== fetch_mirror_urls sg15 prefixes MIRROR_URL once%s\n' "$DIM" "$RESET"
murls=$(fetch_mirror_urls sg15 Si)
[ -n "$murls" ] \
    && ok_ "fetch_mirror_urls sg15 Si returned URLs" \
    || bad_ "fetch_mirror_urls sg15 Si returned empty"

bad_url=""
prefix="${MIRROR_URL%/}/"
while IFS= read -r url; do
    [ -n "$url" ] || continue
    case $url in
        "$prefix"*)
            rest=${url#"$prefix"}
            case $rest in
                *http://* | *https://*) bad_url=$url ;;
            esac
            ;;
        *) bad_url=$url ;;
    esac
done <<<"$murls"
[ -z "$bad_url" ] \
    && ok_ "every URL from fetch_mirror_urls sg15 Si begins with MIRROR_URL once" \
    || bad_ "malformed mirror URL: $bad_url"

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
