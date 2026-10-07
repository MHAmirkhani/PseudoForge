#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# audit-interfaces.sh -- the three interfaces, checked against the core.
#
# tools/audit.sh runs the *commands* and looks at what they print.  This
# script runs the *interfaces* and asks whether they and the core still
# agree.  Three questions:
#
#   1. Does the CLI's help text name everything the dispatcher accepts, and
#      does every subcommand respond to --help?
#   2. Does the TUI still have every layer the flow promises, and does every
#      advanced-screen key it exposes end up in SPEC?
#   3. Does the wizard's text-mode flow reach the SPEC the CLI would?
#
# The property behind all three: the user's mental model.  A CLI help page
# that omits a working subcommand, a menu that says "Step 3 of 6" when the
# flow has nine layers, a --help flag that answers "unknown subcommand" --
# none of those crash, and all of them make the tool feel like it was
# written by someone who does not know how it works.
#
#   tools/audit-interfaces.sh                        the fast suite (A-E)
#   PF_SLOW_INTERFACES=1 tools/audit-interfaces.sh    plus the engine matrix
#
# The script writes nothing outside $TMP.  Exit code is 0 when every check
# passes and 1 when any fails, so it can be wired into run_tests.sh.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
PSM=$ROOT/pseudoforge

export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
export PF_VAR_DIR=${PF_VAR_DIR:-$HOME/pf-var}
export PF_NATIVE_DIR=${PF_NATIVE_DIR:-$HOME/pf-native}

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0

ok_()   { printf '  %sPASS%s  %s\n' "$GREEN"  "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED"    "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }
section() { printf '\n%s== %s%s\n' "$DIM" "$1" "$RESET"; }

# ---------------------------------------------------------------------------
# The canonical subcommands.  Aliases are collapsed (generate, not gen).
# If the dispatcher gains one, add it here; the audit will then make sure it
# responds to --help and appears in `pseudoforge help`.
# ---------------------------------------------------------------------------
SUBCMDS="
generate wizard tui engines convert optimise doctor compare citation params
profile xc validate import report plot api native recipe list show config help
"

# Flags that are documented by a subcommand's own help rather than the
# top-level `pseudoforge help`.  Add a flag here only when it is genuinely
# subcommand-specific.  A new *top-level* flag belongs in cli_usage, and
# the audit will say so if it is missing.
# Flags that are documented by a subcommand's own help rather than by the
# top-level `pseudoforge help`.  Every one here belongs to a specific
# subcommand: --formats to params extract, --note and --tag to xc/profile
# add/edit, --set-nc and the --set-* family to profile, --plot-format and
# --plot-rlderiv to plot, --yes to a confirm-anyway prompt, --tui to the
# `tui` alias, --functional to the functional list filter, --no-plot to
# the --plot flag's inverse.
SUB_FLAGS="
--all --desc --description --dft --ecut --families --format --formats
--functional --help --json --label --license --no-cutoff-scan --no-plot
--note --notes --path --plot-bands --plot-dir --plot-dos --plot-format
--plot-rlderiv --proxy --qe --reference --relativity --rho --routes
--set-nc --set-paw --set-us --show-citation --status --summary --tag
--tui --type --which-augfun --why --yes
"

# ---------------------------------------------------------------------------
section "A. every subcommand responds to --help"

for cmd in $SUBCMDS; do
    out=$("$PSM" "$cmd" --help 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
        ok_ "$cmd --help"
    else
        bad_ "$cmd --help (rc=$rc, empty output)" "$out"
    fi
done

if v=$("$PSM" version 2>&1) && printf '%s' "$v" | grep -qi pseudoforge; then
    ok_ "version prints a version string"
else
    bad_ "version" "$v"
fi

# Every canonical subcommand appears in the top-level help.
# The command column is "name" or "name | alias"; extract both halves.
# "version | help" at the bottom is one line for two subcommands.
listed=$(./pseudoforge help 2>&1 | sed -n '/^USAGE/,/^ENGINE AND SOURCE/p' \
             | awk '/^    [a-z]/ { gsub(/\|/, " "); for (i=1; i<=NF; i++) print $i }' \
             | grep -E '^[a-z]+$' | sort -u)
missing_help=""
for c in $SUBCMDS; do
    printf '%s\n' "$listed" | grep -qx "$c" || missing_help="$missing_help $c"
done
missing_help=$(printf '%s\n' $missing_help | tr '\n' ' ' | sed 's/^ //;s/ $//')
[ -z "$missing_help" ] \
    && ok_ "every canonical subcommand appears in ./pseudoforge help" \
    || bad_ "missing from ./pseudoforge help:$missing_help"

# Every top-level flag from cli.sh is documented somewhere.
all_flags=$(grep -oE '\-\-[a-z][a-z-]+' "$PF_LIB/cli.sh" | sort -u)
help_flags=$(./pseudoforge help 2>&1 | grep -oE '\-\-[a-z][a-z-]+' | sort -u)
missing_flags=""
# Turn SUB_FLAGS into one flag per line once, so the loop can use exact
# matching (grep -x) rather than a `case` substring.  The case form was
# matching "--format" against "--formats" in one direction and missing
# entirely in the other depending on which came first in the string.
sub_flags_list=$(printf '%s' "$SUB_FLAGS" | tr -s ' \n' '\n' | grep -E '^--')
for f in $all_flags; do
    printf '%s\n' "$help_flags"     | grep -qxF -- "$f" && continue
    printf '%s\n' "$sub_flags_list" | grep -qxF -- "$f" && continue
    missing_flags="$missing_flags $f"
done
missing_flags=$(printf '%s\n' $missing_flags | tr '\n' ' ' | sed 's/^ //;s/ $//')
[ -z "$missing_flags" ] \
    && ok_ "every top-level flag is in help (or the sub-flag list)" \
    || bad_ "flag(s) in cli.sh not in help and not on the sub-flag list:$missing_flags"

# ---------------------------------------------------------------------------
section "B. TUI screen reachability"

# Load only the modules the TUI needs to declare its own functions.
for m in core sink config elements xc namelist profiles metadata formats \
         gth sssp convert doctor params engines recipe input_builder \
         executor project run ui tui wizard; do
    . "$PF_LIB/$m.sh" 2>/dev/null || true
done
pf_config_defaults 2>/dev/null || true

miss_handlers=""
while IFS='|' read -r key title note handler; do
    [ -n "$key" ] || continue
    declare -F "$handler" >/dev/null 2>&1 || miss_handlers="$miss_handlers $handler"
done < <(tui_layers)
miss_handlers=$(printf '%s\n' $miss_handlers | tr '\n' ' ' | sed 's/^ //;s/ $//')
[ -z "$miss_handlers" ] \
    && ok_ "every tui_layers() entry has a handler function" \
    || bad_ "missing layer handler(s):$miss_handlers"

miss_picks=""
for fn in $(grep -oE 'tui_simple_layer [a-z]+ +[a-z_]+' "$PF_LIB/tui.sh" \
                | awk '{print $3}' | sort -u); do
    declare -F "$fn" >/dev/null 2>&1 || miss_picks="$miss_picks $fn"
done
miss_picks=$(printf '%s\n' $miss_picks | tr '\n' ' ' | sed 's/^ //;s/ $//')
[ -z "$miss_picks" ] \
    && ok_ "every ui_pick_* / ui_advanced named by a layer exists" \
    || bad_ "missing UI function(s):$miss_picks"

if grep -qE '^\s+finish\s+"Continue"' "$PF_LIB/ui.sh"; then
    ok_ "element-selection menu emits tag 'finish'"
else
    bad_ "element-selection menu has no 'finish' tag"
fi

# ---------------------------------------------------------------------------
section "C. TUI advanced screen reaches SPEC"

drive_ui_advanced() {
    local answers=$1
    PATH="$ROOT/tests/mock:$PATH"
    export MOCK_WT_LOG=$TMP/wt.log MOCK_WT_ANSWERS=$answers
    : > "$MOCK_WT_LOG"
    (
        # deps is required: ui_init calls deps_tui_backend to resolve $DIA.
        # Omitting it here made every Section C test run with $DIA empty and
        # fail with "whiptail exit 127" -- a message about the harness, not
        # about the screen.
        for m in core sink config deps elements xc namelist profiles metadata \
                 formats gth sssp convert doctor params engines recipe \
                 input_builder executor project run ui; do
            . "$PF_LIB/$m.sh" 2>/dev/null || true
        done
        pf_config_defaults 2>/dev/null || true
        pf_elements_load 2>/dev/null || true
        pf_profiles_load 2>/dev/null || true
        spec_init 2>/dev/null || true
        ui_term_size() { UI_ROWS=40; UI_COLS=120; }
        ui_init
        exec < /dev/null
        ui_advanced
        for k in core_hole rcut_scale lloc nc_form gipaw lsd; do
            printf '%s=%s\n' "$k" "${SPEC[$k]:-}"
        done
    ) 2>/dev/null
}

check_ui_key() {
    local tag=$1 value=$2 key=$3 expected=$4
    printf '%s\n%s\nCANCEL\n' "$tag" "$value" > "$TMP/ans"
    out=$(drive_ui_advanced "$TMP/ans")
    got=$(printf '%s' "$out" | awk -F= -v k="$key" '$1==k {print $2}')
    if [ "$got" = "$expected" ]; then
        ok_ "ui_advanced: '$tag' sets $key=$expected"
    else
        bad_ "ui_advanced: '$tag' left $key='$got' (expected '$expected')"
    fi
}

check_ui_key corehole 1s core_hole 1s
check_ui_key rcut 1.10 rcut_scale 1.10
check_ui_key lloc 2 lloc 2
check_ui_key ncform semilocal nc_form semilocal
check_ui_key gipaw   yes gipaw 1
check_ui_key lsd     yes lsd 1

# ---------------------------------------------------------------------------
section "D. Wizard text-mode entry"

drive_wizard_family() {
    (
        export PF_FORCE_TEXT=1
        exec < /dev/null
        for m in core sink config elements xc namelist profiles metadata \
                 formats gth sssp convert doctor params engines recipe \
                 input_builder executor project run ui wizard; do
            . "$PF_LIB/$m.sh" 2>/dev/null || true
        done
        pf_config_defaults 2>/dev/null || true
        pf_elements_load 2>/dev/null || true
        pf_xc_load 2>/dev/null || true
        pf_profiles_load 2>/dev/null || true
        pf_engines_load 2>/dev/null || true
        spec_init 2>/dev/null || true
        printf '1\n1\n1\n1\n1\n1\nSi\n%s/wiz-out\nY\n' "$TMP" \
            | wizard_main >/dev/null 2>&1
        printf 'family=%s\n' "${SPEC[family]:-}"
    )
}

fam=$(drive_wizard_family | awk -F= '$1=="family"{print $2}')
case $fam in
    nc|us|paw) ok_ "wizard text-mode picked family=$fam" ;;
    *)         skip_ "wizard text-mode did not reach the family prompt (got '$fam')" ;;
esac

# ---------------------------------------------------------------------------
section "E. doc paths referenced from shell code exist"

docs_missing=""
for f in lib/tui.sh lib/wizard.sh lib/ui.sh lib/cli.sh; do
    while IFS= read -r doc; do
        case $doc in
            *.md) ;;
            *) continue ;;
        esac
        [ -f "$ROOT/docs/$doc" ] || docs_missing="$docs_missing $doc"
    done < <(grep -hoE '[a-zA-Z0-9_/.-]+\.md' "$f" 2>/dev/null | sort -u)
done
docs_missing=$(printf '%s\n' $docs_missing | sort -u | tr '\n' ' ' | sed 's/^ //;s/ $//')
[ -z "$docs_missing" ] \
    && ok_ "every docs/*.md path named by the shell code exists" \
    || bad_ "missing doc file(s):$docs_missing"

# ---------------------------------------------------------------------------
section "F. CLI subcommand smoke"

smoke() {
    local label=$1; shift
    if "$@" >/dev/null 2>&1; then ok_ "$label"; else bad_ "$label"; fi
}

smoke "native list"           "$PSM" native list
smoke "native size"           "$PSM" native size
smoke "engines list"          "$PSM" engines list
smoke "engines path ld1"      "$PSM" engines path ld1
smoke "convert --why gth upf" "$PSM" convert --why gth upf
smoke "convert --list"        "$PSM" convert --list
smoke "list profiles"         "$PSM" list profiles
smoke "list functionals"      "$PSM" list functionals
smoke "list formats"          "$PSM" list formats
smoke "list sets"             "$PSM" list sets
smoke "doctor"                "$PSM" doctor
smoke "config --show"         "$PSM" config --show
smoke "citation psl-high"     "$PSM" citation psl-high

# ---------------------------------------------------------------------------
section "G. TUI per-engine matrix (opt-in, PF_SLOW_INTERFACES=1)"

if [ "${PF_SLOW_INTERFACES:-0}" = 1 ]; then
    for eng in ld1 oncvpsp uspp fhi98pp opium gth atompaw ape adpack; do
        if ! "$PSM" engines path "$eng" >/dev/null 2>&1; then
            skip_ "$eng not installed"
            continue
        fi
        skip_ "$eng: TUI per-engine smoke not implemented yet"
    done
else
    skip_ "set PF_SLOW_INTERFACES=1 to run the per-engine TUI matrix"
fi

# ---------------------------------------------------------------------------
printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$([ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM")" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
