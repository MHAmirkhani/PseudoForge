#!/usr/bin/env bash
# add-xml-to-store.sh -- add XML beside every UPF in the native store.
#
# XML is a conversion from UPF by QE's upfconv.x -x, never a native engine
# output.  Doing it once over the store is cheaper than a full rebuild, and
# the produced files sit beside their UPF with the same stem.
#
# Idempotent: a UPF that already has a .xml (or .xml.gz) next to it is
# skipped, so it is safe to run again after adding more profiles.
#
# Usage:  tools/add-xml-to-store.sh [store-dir] [--exclude PATTERN]
# Env:    JOBS=N          parallelism (default 4)
#         UPFCONV_BIN=... override upfconv.x location

set -uo pipefail

STORE=${PF_NATIVE_DIR:-$HOME/pf-native}
EXCLUDE=""
while [ $# -gt 0 ]; do
    case $1 in
        --exclude) EXCLUDE=$2; shift 2 ;;
        -*) echo "unknown option: $1" >&2; exit 1 ;;
        *)  STORE=$1; shift ;;
    esac
done

JOBS=${JOBS:-4}
UPFCONV=${UPFCONV_BIN:-$(command -v upfconv.x || echo /opt/espresso/7.6/upfconv.x)}

[ -x "$UPFCONV" ] || { echo "upfconv.x not found (tried $UPFCONV)" >&2; exit 1; }
[ -d "$STORE" ]   || { echo "store not found: $STORE" >&2; exit 1; }

export UPFCONV LC_ALL=C

process_one() {
    local upf=$1 tmpd xmlout
    local xml_try
    case $upf in
        *.UPF.gz)  xml_try="${upf%.UPF.gz}.xml.gz" ;;
        *.UPF)     xml_try="${upf%.UPF}.xml" ;;
        *) return 0 ;;
    esac
    [ -e "$xml_try" ] && return 0

    tmpd=$(mktemp -d)
    case $upf in
        *.UPF.gz) gzip -dc "$upf" > "$tmpd/in.UPF" 2>/dev/null || { rm -rf "$tmpd"; return 1; } ;;
        *.UPF)    cp "$upf" "$tmpd/in.UPF" ;;
    esac

    ( cd "$tmpd" && OMP_NUM_THREADS=1 timeout 120 "$UPFCONV" -x in.UPF ) >/dev/null 2>&1
    xmlout="$tmpd/in.xml"
    if [ ! -s "$xmlout" ]; then rm -rf "$tmpd"; return 1; fi

    case $upf in
        *.UPF.gz) gzip -c "$xmlout" > "${upf%.UPF.gz}.xml.gz" || { rm -rf "$tmpd"; return 1; } ;;
        *.UPF)    mv "$xmlout" "${upf%.UPF}.xml"           || { rm -rf "$tmpd"; return 1; } ;;
    esac
    rm -rf "$tmpd"
}
export -f process_one

echo "store:   $STORE"
echo "jobs:    $JOBS"
echo "upfconv: $UPFCONV"
[ -n "$EXCLUDE" ] && echo "exclude: $EXCLUDE"
echo

# Count what we are about to do
count=$(find "$STORE" -path '*/pseudos/*' \( -name '*.UPF' -o -name '*.UPF.gz' \) \
    ${EXCLUDE:+! -path "$EXCLUDE"} -print 2>/dev/null | wc -l)
echo "UPF files in scope: $count"
echo

find "$STORE" -path '*/pseudos/*' \( -name '*.UPF' -o -name '*.UPF.gz' \) \
    ${EXCLUDE:+! -path "$EXCLUDE"} -print0 \
  | xargs -0 -r -P "$JOBS" -n 1 bash -c 'process_one "$@"' _

echo
echo "done. xml files now present:"
find "$STORE" -path '*/pseudos/*' \( -name '*.xml' -o -name '*.xml.gz' \) -type f 2>/dev/null | wc -l
