#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# check-psp8-tools.sh -- what can and cannot produce an ABINIT psp8 here.
#
# This exists instead of the `tools/install-pspconvert.sh` it replaces. There
# is nothing to install: `pspconvert` is not a program that exists, in ABINIT
# or anywhere else. Three conversion paths were registered as performed by it,
# and `convert --list` reported them as "AVAILABLE: no", which reads as one
# install away.
#
# A claim like that should not have to be taken on trust a second time, so this
# script re-runs the check rather than asserting the conclusion. Run it against
# any ABINIT you have and it will tell you what it found.
#
#   tools/check-psp8-tools.sh                  look on PATH
#   tools/check-psp8-tools.sh /opt/abinit      look in a specific prefix too
#
# Exit status is 0 when psp8 can be produced by *some* route on this machine,
# which today means ONCVPSP writing it natively, and 1 when it cannot.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
PREFIX=${1:-}

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
yes_() { printf '  %sfound%s    %s\n'    "$GREEN"  "$RESET" "$*"; }
no_()  { printf '  %sabsent%s   %s\n'    "$RED"    "$RESET" "$*"; }
note_(){ printf '  %s         %s%s\n'    "$DIM"    "$*"     "$RESET"; }
head_(){ printf '\n%s== %s%s\n'          "$DIM"    "$*"     "$RESET"; }

search() {          # search <name> -> prints the path, or fails
    local n=$1 c
    c=$(command -v "$n" 2>/dev/null) && [ -x "$c" ] && { printf '%s\n' "$c"; return 0; }
    if [ -n "$PREFIX" ]; then
        for c in "$PREFIX/bin/$n" "$PREFIX/$n"; do
            [ -x "$c" ] && { printf '%s\n' "$c"; return 0; }
        done
        c=$(find "$PREFIX" -maxdepth 4 -name "$n" -type f -perm -u+x 2>/dev/null | head -1)
        [ -n "$c" ] && { printf '%s\n' "$c"; return 0; }
    fi
    return 1
}

# ---------------------------------------------------------------------------
head_ "the converter that does not exist"

if p=$(search pspconvert); then
    yes_ "pspconvert: $p"
    note_ "This contradicts what was measured when the psp8 paths were removed."
    note_ "If it converts psp8, the three refusals in lib/convert.sh can become"
    note_ "real paths again -- with a test that runs them on a real file first."
else
    no_ "pspconvert"
    note_ "Checked here, and previously in the ABINIT 8.10.3 and 9.10.3 source"
    note_ "trees and the conda-forge binaries of 8.10.2 and 10.0.3. Absent from"
    note_ "all of them; abitk has no pseudopotential subcommand either."
fi

if p=$(search abitk); then
    yes_ "abitk: $p"
    if "$p" --help 2>&1 | grep -qiE 'pseudo|psp8|psp_'; then
        note_ "It names a pseudopotential subcommand -- worth reading."
    else
        note_ "No pseudopotential subcommand in its help."
    fi
fi

# ---------------------------------------------------------------------------
head_ "upfconv.x, and what it actually reads"

# Resolved by the core, not re-searched here: cvt_upfconv_bin already knows
# about UPFCONV_BIN, PATH and QE_ROOT_DIR, and a second copy of that search
# would drift from the first.
if p=$(
    export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
    for m in core sink config deps convert; do . "$PF_LIB/$m.sh" || exit 1; done
    pf_config_defaults >/dev/null 2>&1
    cvt_upfconv_bin 2>/dev/null
) && [ -n "$p" ]; then
    yes_ "upfconv.x: $p"
    if "$p" -h 2>&1 | grep -qi 'psp8'; then
        note_ "This build lists psp8. That would be new -- test it on a real file."
    else
        note_ "Formats it lists: $("$p" -h 2>&1 | grep -oE '\*\.[a-zA-Z0-9]+' | tr '\n' ' ')"
        note_ "psp8 is not among them."
    fi
else
    no_ "upfconv.x"
    note_ "Ships with Quantum ESPRESSO; set QE_ROOT_DIR or UPFCONV_BIN."
fi

# ---------------------------------------------------------------------------
head_ "the route that works"

rc=1
if p=$("$ROOT/pseudoforge" engines path oncvpsp 2>/dev/null) && [ -x "$p" ]; then
    yes_ "oncvpsp.x: $p"
    if strings "$p" 2>/dev/null | grep -q 'psfile must =='; then
        note_ "It writes psp8 natively, and accepts psfile=both."
    else
        note_ "It writes psp8 natively."
    fi
    printf '\n  %spsp8 is generated, not converted to:%s\n\n' "$GREEN" "$RESET"
    printf '    pseudoforge generate -e Si -t nc -x pbe \\\n'
    printf '        --engine oncvpsp --format psp8 -o ./out\n\n'
    printf '    pseudoforge generate ... --format upf,psp8     # both files\n'
    rc=0
else
    no_ "oncvpsp.x"
    note_ "Build it: pseudoforge engines build oncvpsp"
    printf '\n  %sNo route to psp8 on this machine.%s\n' "$YELLOW" "$RESET"
fi

printf '\n'
exit $rc
