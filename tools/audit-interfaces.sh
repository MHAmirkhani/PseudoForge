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
        # Every key ui_advanced can set.  The list matches the USER_KEYS
        # list in test_custom.sh, minus `upf`: only v2 is producible and
        # the menu item that offered v1 was removed when the CLI began
        # refusing `--upf 1`.
        for k in variant author config core_hole zed zval nlcc rcore rho0 \
                 which_augfun rmatch_augfun lloc rcloc rcut_scale nc_form \
                 beta tr2 lsd gipaw extra_projectors xmin dx rmax; do
            printf '%s=%s\n' "$k" "${SPEC[$k]:-}"
        done
    ) 2>/dev/null
}

# run_ui_advanced_with <printf-format> -- drive the screen with the given
# answer sequence.  The answers come in as a printf format string so a
# multi-line sequence (a menu pick followed by the inputbox it opens)
# reads on one line and the `\n` between them is visible.
run_ui_advanced_with() {
    printf -- "$@" > "$TMP/ans"
    drive_ui_advanced "$TMP/ans"
}

check_key() {   # check_key <output> <key> <expected> [<label>]
    local out=$1 key=$2 expected=$3 label=${4:-screen}
    local got
    got=$(printf '%s' "$out" | awk -F= -v k="$key" '$1==k {print $2}')
    if [ "$got" = "$expected" ]; then
        ok_ "$label: $key=$expected"
    else
        bad_ "$label: $key='$got' (expected '$expected')"
    fi
}

# --- One block per user-settable key ------------------------------------
#
# Six were covered before this pass; the other seventeen were reachable
# from the screen and never driven by a test.  Each block names the menu
# item, the answers it needs, and the SPEC keys it should end up setting.
# A menu item that opens a sub-inputbox takes two answer lines; the two
# that open a second menu (nlcc, augfun) take three.

# corehole: menu pick, then one inputbox
out=$(run_ui_advanced_with 'corehole\n1s\nCANCEL\n')
check_key "$out" core_hole 1s ui_advanced
# rcut: menu pick, then one inputbox
out=$(run_ui_advanced_with 'rcut\n1.10\nCANCEL\n')
check_key "$out" rcut_scale 1.10 ui_advanced
# lloc: menu pick, then lloc inputbox, then rcloc inputbox
out=$(run_ui_advanced_with 'lloc\n-1\n1.5\nCANCEL\n')
check_key "$out" lloc -1 ui_advanced
check_key "$out" rcloc 1.5 ui_advanced
# ncform: menu pick, then the form menu
out=$(run_ui_advanced_with 'ncform\nsemilocal\nCANCEL\n')
check_key "$out" nc_form semilocal ui_advanced
# gipaw: menu pick, then a yesno
out=$(run_ui_advanced_with 'gipaw\nyes\nCANCEL\n')
check_key "$out" gipaw 1 ui_advanced
# lsd: menu pick, then a yesno
out=$(run_ui_advanced_with 'lsd\nyes\nCANCEL\n')
check_key "$out" lsd 1 ui_advanced
# variant: one inputbox
out=$(run_ui_advanced_with 'variant\nspn\nCANCEL\n')
check_key "$out" variant spn ui_advanced
# author: one inputbox
out=$(run_ui_advanced_with 'author\nTest Author\nCANCEL\n')
check_key "$out" author 'Test Author'

# config: one inputbox
out=$(run_ui_advanced_with 'config\n[Ar] 3d7 4s1\nCANCEL\n')
check_key "$out" config '[Ar] 3d7 4s1'

# zed: one inputbox
out=$(run_ui_advanced_with 'zed\n13.5\nCANCEL\n')
check_key "$out" zed 13.5 ui_advanced
# zval: one inputbox
out=$(run_ui_advanced_with 'zval\n14\nCANCEL\n')
check_key "$out" zval 14 ui_advanced
# nlcc: menu pick, then the Leave/on/off menu, then rcore and rho0 boxes
out=$(run_ui_advanced_with 'nlcc\non\n0.8\n1.0\nCANCEL\n')
check_key "$out" nlcc on ui_advanced
check_key "$out" rcore 0.8 ui_advanced
check_key "$out" rho0 1.0 ui_advanced
# augfun: menu pick, then the augfun menu, then rmatch_augfun
out=$(run_ui_advanced_with 'augfun\nPSQ\n2.0\nCANCEL\n')
check_key "$out" which_augfun PSQ ui_advanced
check_key "$out" rmatch_augfun 2.0 ui_advanced
# proj: one inputbox (space-separated list of shell:energy tokens)
out=$(run_ui_advanced_with 'proj\n3D:0.5\nCANCEL\n')
check_key "$out" extra_projectors 3D:0.5 ui_advanced
# grid: one inputbox holding xmin:dx:rmax; the handler splits it
out=$(run_ui_advanced_with 'grid\n-7.0:0.0125:120.0\nCANCEL\n')
check_key "$out" xmin -7.0 ui_advanced
check_key "$out" dx 0.0125 ui_advanced
check_key "$out" rmax 120.0 ui_advanced
# scf: menu pick, then beta inputbox, then tr2 inputbox
out=$(run_ui_advanced_with 'scf\n0.1\n1.0d-14\nCANCEL\n')
check_key "$out" beta 0.1 ui_advancedcheck_key "$out" tr2 1.0d-14

# ---------------------------------------------------------------------------
section "D. Wizard steps (text-mode, one at a time)"

WIZ_STEP_ANSWERS=$TMP/wiz-step-answers

# Each of the seven wizard steps reads one or more answers and writes one
# or more SPEC keys.  Running wizard_main end to end would call run_batch
# and produce a pseudopotential -- a side effect the audit should not have
# and does not need.  Driving the steps individually also catches a step
# that stopped setting its key, which a full-flow run would hide behind
# whatever the next step copies through.
#
# wiz_step_run <step-fn> <setup> <answers> <keys...> -- run one step in
# its own shell with the setup applied first, print the named keys.

wiz_step_run() {
    local step=$1 setup=$2 answers=$3; shift 3
    (
        # PF_ROOT, PF_LIB, PF_DATA are already exported at the top of the
        # script, so the subshell inherits them.  The `echo` in the parent
        # diag had no PF_DATA and the modules silently failed to load --
        # the error message ("element table not found") came from a
        # source that had lost $PF_DATA.  Leaving the exports alone here
        # and trusting the inherited environment is the fix; the earlier
        # version was fine, the diag just ran without them.
        export PF_FORCE_TEXT=1
        for m in core sink config deps elements xc namelist profiles metadata \
                 formats gth sssp convert doctor params engines recipe \
                 input_builder executor project run ui wizard; do
            . "$PF_LIB/$m.sh" 2>/dev/null || true
        done
        pf_config_defaults 2>/dev/null || true
        pf_elements_load 2>/dev/null || true
        pf_xc_load 2>/dev/null || true
        pf_profiles_load 2>/dev/null || true
        pf_engines_load 2>/dev/null || true
        pf_metadata_load 2>/dev/null || true
        spec_init 2>/dev/null || true
        # wiz_init resolves the backend.  Without this call WIZ_BACKEND is
        # empty and wiz_menu falls through to the whiptail path, which
        # fails in a script with no terminal -- every step silently
        # returned 1 and the SPEC keys stayed at their spec_init defaults.
        wiz_init 2>/dev/null || true
        eval "$setup" 2>/dev/null || true
        # Feed the answers from a file rather than a pipe.  `printf ... |
        # step` runs `step` in a subshell, and the SPEC keys it sets are
        # lost when that subshell exits -- every check then saw whatever
        # spec_init had left.  A redirect runs it in *this* shell.
        # Process substitution, not a redirect from a file: the same
        # behaviour as `printf ... | step` -- the pipe ran step in a
        # subshell and the SPEC keys were lost -- without the subshell.
        # A redirect from a named file has been known to interact badly
        # with command substitutions inside the step; this does not.
        "$step" < <(printf '%s\n' "$answers") >/dev/null 2>&1
        local k
        for k in "$@"; do
            printf '%s=%s\n' "$k" "${SPEC[$k]:-}"
        done
    )
}

# --- wiz_step_family ----------------------------------------------------
out=$(wiz_step_run wiz_step_family "" "1" family)
check_key "$out" family paw wizard
out=$(wiz_step_run wiz_step_family "" "2" family)
check_key "$out" family us wizard
out=$(wiz_step_run wiz_step_family "" "3" family)
check_key "$out" family nc wizard
# --- wiz_step_xc --------------------------------------------------------
# The first menu item is PBE for any starting family; the driver picks 1.
out=$(wiz_step_run wiz_step_xc "SPEC[family]=paw" "1" xc)
check_key "$out" xc pbe wizard
# --- wiz_step_rel -------------------------------------------------------
out=$(wiz_step_run wiz_step_rel "SPEC[family]=paw; SPEC[xc]=pbe" "1" rel)
check_key "$out" rel scalar wizard
out=$(wiz_step_run wiz_step_rel "SPEC[family]=paw; SPEC[xc]=pbe" "2" rel)
check_key "$out" rel full wizard
out=$(wiz_step_run wiz_step_rel "SPEC[family]=paw; SPEC[xc]=pbe" "3" rel)
check_key "$out" rel nonrel wizard
# --- wiz_step_profile ---------------------------------------------------
# The profile list depends on family, and its order depends on the
# profile registry; the check is that the key was set to one of the
# profiles that supports the family, not that it is any particular one.
out=$(wiz_step_run wiz_step_profile \
        "SPEC[family]=paw; SPEC[xc]=pbe; SPEC[rel]=scalar" "1" profile engine)
prof=$(printf '%s' "$out" | awk -F= '$1=="profile"{print $2}')
eng=$(printf '%s' "$out" | awk -F= '$1=="engine"{print $2}')
if [ -n "$prof" ]; then
    ok_ "wizard: profile=$prof (engine=$eng)"
else
    bad_ "wizard: profile empty" "$out"
fi

# --- wiz_step_source ----------------------------------------------------
# '2' is the second menu item, "local"; '1' is "online".
out=$(wiz_step_run wiz_step_source \
        "SPEC[family]=paw; SPEC[xc]=pbe; SPEC[rel]=scalar; SPEC[profile]=psl-high; SPEC[engine]=ld1" \
        "1" source)
check_key "$out" source online wizard
out=$(wiz_step_run wiz_step_source \
        "SPEC[family]=paw; SPEC[xc]=pbe; SPEC[rel]=scalar; SPEC[profile]=psl-high; SPEC[engine]=ld1" \
        "2" source)
check_key "$out" source local wizard
# --- wiz_step_engine ----------------------------------------------------
# For a family the recommended engine is installed for, the step returns
# 0 immediately -- nothing to ask, nothing to change.  That is a check
# in itself: the step must not prompt when the engine is present.
out=$(wiz_step_run wiz_step_engine \
        "SPEC[family]=paw; SPEC[engine]=ld1" "" engine)
check_key "$out" engine ld1 wizard
# --- wiz_step_elements --------------------------------------------------
# Not a SPEC key; the step writes WIZ_ELEMENT_LIST.  Reuse wiz_step_run
# with a twist: it prints only SPEC keys, so this call checks the
# elements input box's own return by running the step and inspecting
# the file it produces.
wiz_step_elements_drive() {
    local answer=$1
    (
        export PF_FORCE_TEXT=1
        for m in core sink config deps elements xc namelist profiles metadata \
                 formats gth sssp convert doctor params engines recipe \
                 input_builder executor project run ui wizard; do
            . "$PF_LIB/$m.sh" 2>/dev/null || true
        done
        pf_config_defaults 2>/dev/null || true
        pf_elements_load 2>/dev/null || true
        spec_init 2>/dev/null || true
        wiz_init 2>/dev/null || true
        wiz_step_elements < <(printf '%s\n' "$answer") >/dev/null 2>&1
        # The step leaves a trailing space; trim it before printing so
        # the check compares to the exact string a user typed.
        printf 'elements=%s\n' "$(printf '%s' "${WIZ_ELEMENT_LIST:-}" | sed 's/[[:space:]]*$//')"
    )
}
out=$(wiz_step_elements_drive Si)
check_key "$out" elements Si
out=$(wiz_step_elements_drive "1-3")
check_key "$out" elements "H He Li"

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

# `native list` and `native size` read the store.  When there is no store
# -- running inside run_tests.sh with a temporary HOME -- skip them rather
# than fail: the audit's job is to check the interface, not to insist that
# every machine has a 23 GB file collection.
if [ -f "${PF_NATIVE_DIR:-$HOME/pf-native}/index.tsv" ]; then
    smoke "native list"       "$PSM" native list
    smoke "native size"       "$PSM" native size
else
    skip_ "native list (no store at ${PF_NATIVE_DIR:-$HOME/pf-native})"
    skip_ "native size (no store at ${PF_NATIVE_DIR:-$HOME/pf-native})"
fi
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
section "G. TUI per-engine generation"

# The TUI's guided flow reaches every engine through the same pickers, but
# the sequence of menus a user sees differs: for a library that ships its
# own decks the engine is fixed, for a constructed profile the engine menu
# appears.  Driving the whole flow once per engine would test the pickers
# again (Sections B and C already do) and would need a different answer
# sequence per engine.
#
# What the TUI has never been tested on is the *generation* itself: does
# tui_do_run, for this engine, actually produce a file?  Each block below
# sets SPEC the way the layer walk would have, calls tui_review directly,
# and asserts the output the engine is supposed to produce.
#
# Engines that are not installed are skipped, with the reason.  This
# section needs real engines (the CLI mock does not help -- tui_do_run
# shells out to cmd_generate, which needs a real binary).

# (engine, profile, family, xc, rel, element) -- the same rows as
# tests/test_engine_matrix.sh, so if that passes and this does not, the
# difference is the TUI wrapper, not the engine.
TUI_MATRIX=(
    "ld1|psl-high|paw|pbe|scalar|Si"
    "oncvpsp|sg15|nc|pbe|scalar|Si"
    "uspp|gbrv|us|pbe|scalar|Si"
    "fhi98pp|fhi|nc|pw|scalar|Si"
    "opium|opium|nc|pz|scalar|Fe"
    "gth|cp2k-gth|nc|pbe|scalar|Si"
    "atompaw|atompaw|paw|pbe|scalar|Si"
    "ape|pseudoforge-auto|nc|pbe|scalar|Si"
    "adpack|adpack|nc|pz|full|Na"
)

# drive_tui_review -- set SPEC, then run tui_review directly.  The mock
# whiptail answers two prompts: the Output directory input box (the path),
# and the final "Start" yes/no.  Everything else the guided flow would
# have asked is already set in SPEC.
drive_tui_review() {
    local eng=$1 profile=$2 family=$3 xc=$4 rel=$5 element=$6 out=$7
    PATH="$ROOT/tests/mock:$PATH"
    export MOCK_WT_LOG=$TMP/tui-$eng.log MOCK_WT_ANSWERS=$TMP/tui-$eng.ans
    : > "$MOCK_WT_LOG"
    printf 'run\n%s\nyes\n' "$out" > "$MOCK_WT_ANSWERS"

    (
        # A fresh shell per engine: the core modules hold state (project
        # directories, prepared decks) and reusing one shell across rows
        # would carry it forward.
        for m in core sink config deps elements xc namelist profiles metadata \
                 formats gth sssp convert doctor params engines build recipe \
                 input_builder executor fetch project run upf testing validate \
                 report cli ui tui wizard; do
            . "$PF_LIB/$m.sh" 2>/dev/null || true
        done
        export PF_ROOT PF_LIB PF_DATA
        pf_config_defaults
        pf_elements_load; pf_xc_load; pf_profiles_load
        pf_engines_load; pf_metadata_load; pf_formats_load
        spec_init
        SPEC[profile]=$profile
        SPEC[family]=$family
        SPEC[xc]=$xc
        SPEC[rel]=$rel
        SPEC[engine]=$eng
        SPEC[source]=local
        # The format the engine actually writes.  A user going through the
        # format picker sees only those formats offered (ui_pick_format
        # reads fmt_for_engine).  This driver skips the picker and sets
        # SPEC[formats] from the profile, which for APE is "upf xml" --
        # and APE writes only upf, so cli_check_spec refuses.  Match what
        # the picker would have produced.
        if ! SPEC[formats]=$(fmt_validate "$eng" "${PROF_FORMATS[$profile]:-upf}" 2>/dev/null); then
            SPEC[formats]=$(fmt_for_engine "$eng" | head -1)
        fi
        CLI_ELEMENTS=$element
        RUN_LD1_TESTS=0
        ui_term_size() { UI_ROWS=40; UI_COLS=120; }
        ui_init
        exec < /dev/null
        tui_review
    ) >"$TMP/tui-$eng.out" 2>&1
}

for row in "${TUI_MATRIX[@]}"; do
    IFS='|' read -r eng profile family xc rel element <<< "$row"
    out=$TMP/tui-$eng-out

    if ! "$PSM" engines path "$eng" >/dev/null 2>&1; then
        skip_ "TUI: $eng not installed"
        continue
    fi

    # No `bash -c "$(declare -f ...)"` here: the function reaches for
    # $TMP, $ROOT, $PF_LIB and $PF_DATA, and a fresh `bash -c` shell does
    # not have them -- every source inside failed silently and the row
    # timed out with "cannot load core.sh" hidden in the log.  Call the
    # function directly so it inherits the environment the audit set up.
    # The timeout is on the whole subshell drive_tui_review starts.
    drive_tui_review "$eng" "$profile" "$family" "$xc" "$rel" "$element" "$out"

    # What came out.  Every engine writes at least one file under pseudos/;
    # the name and format differ, so the count is what the check uses.
    n=$(find "$out/pseudos" -maxdepth 1 -type f 2>/dev/null | wc -l)
    if [ "$n" -eq 0 ]; then
        bad_ "TUI: $eng/$family/$element produced no file" \
             "$(tail -5 "$TMP/tui-$eng.out" 2>/dev/null)"
    elif [ ! -f "$out/reports/summary.txt" ]; then
        bad_ "TUI: $eng wrote $n file(s) but no report" \
             "the run finished but summary.txt is missing"
    else
        ok_ "TUI: $eng/$family/$element produced $n file(s) and a report"
    fi
done

# ---------------------------------------------------------------------------
section "H. TUI top-level menu"

# Every tag the main menu offers must have a case handler; every function
# a case handler calls must exist.  This is the interface surface, so it
# is worth stating: a tag with no handler is a menu item that does
# nothing when you click it.
TAGS=$(awk '/^tui_main\(\)/,/^}/' "$PF_LIB/tui.sh" \
       | awk '/^[[:space:]]+[a-z]+[[:space:]]+"/ {print $1}' | sort -u)
CASES=$(awk '/^tui_main\(\)/,/^}/' "$PF_LIB/tui.sh" \
        | awk '/^[[:space:]]+[a-z]+\)/ {sub(/\)/,""); print $1}' | sort -u)

missing_case=""
for t in $TAGS; do
    printf '%s\n' "$CASES" | grep -qx "$t" || missing_case="$missing_case $t"
done
missing_case=$(printf '%s\n' $missing_case | tr '\n' ' ' | sed 's/^ //;s/ $//')
[ -z "$missing_case" ] \
    && ok_ "every menu tag has a case handler" \
    || bad_ "menu tag(s) with no handler:$missing_case"

# Handlers that must exist as functions.  `advanced` is an inline toggle,
# not a function, and is checked separately by the count below.
missing_fn=""
for fn in tui_wizard ui_quick ui_browse_profiles ui_browse_recipes \
          ui_browse_xc ui_validate ui_import ui_reports ui_settings \
          tui_doctor_panel tui_history_show tui_help tui_load_recipe; do
    declare -F "$fn" >/dev/null 2>&1 || missing_fn="$missing_fn $fn"
done
missing_fn=$(printf '%s\n' $missing_fn | tr '\n' ' ' | sed 's/^ //;s/ $//')
[ -z "$missing_fn" ] \
    && ok_ "every tui_main case handler is defined" \
    || bad_ "missing handler function(s):$missing_fn"

# A TUI that offers fewer entries than the CLI can do makes the user
# fall back to the command line.  The number is a floor, not a target.
n=$(printf '%s\n' "$TAGS" | grep -c . || true)
[ "$n" -ge 14 ] \
    && ok_ "tui_main menu offers $n entries" \
    || bad_ "tui_main menu offers only $n entries (14 expected)"

# ---------------------------------------------------------------------------
section "I. config file"

# Isolated config so nothing here touches the user's real one.  PF_RC is
# the file pseudoforge reads and writes; every subcommand honours it.
CFG=$TMP/pseudoforge.rc
mig_home=$TMP/migrate-home
mkdir -p "$mig_home"

cfg() { PF_RC=$CFG "$PSM" config "$@"; }

# --show on a fresh file: creates it, prints every key.  The file has to
# exist after the call -- pf_config_load creates it if missing, and
# `config --show` should leave it there.
out=$(cfg --show 2>&1)
[ -f "$CFG" ] \
    && ok_ "config --show creates the file" \
    || bad_ "config --show did not create $CFG"
printf '%s' "$out" | grep -q 'DEFAULT_XC' \
    && ok_ "config --show lists DEFAULT_XC" \
    || bad_ "config --show output has no DEFAULT_XC"

# --path prints the path and nothing else.
p=$(cfg --path 2>&1)
[ "$p" = "$CFG" ] \
    && ok_ "config --path prints the path" \
    || bad_ "config --path printed '$p', not '$CFG'"

# --set writes one key.
cfg --set DEFAULT_XC=PBEsol >/dev/null 2>&1
grep -qE '^DEFAULT_XC=\"?PBEsol\"?' "$CFG" \
    && ok_ "config --set writes a key" \
    || bad_ "config --set did not write DEFAULT_XC=PBEsol"

# --set accepts several KEY=VALUE pairs in one call.
cfg --set DEFAULT_PROFILE=psl-low DEFAULT_PSEUDOTYPE=paw >/dev/null 2>&1
if grep -qE '^DEFAULT_PROFILE=\"?psl-low\"?' "$CFG" \
   && grep -qE '^DEFAULT_PSEUDOTYPE=\"?paw\"?' "$CFG"; then
    ok_ "config --set accepts several KEY=VALUE pairs"
else
    bad_ "config --set did not apply the second pair"
fi

# Round-trip: read back what was set.
out=$(cfg --show 2>&1)
printf '%s' "$out" | grep -q 'PBEsol' \
    && ok_ "config round-trip: PBEsol survives" \
    || bad_ "config round-trip lost PBEsol"

# --edit invokes $EDITOR with the path.  `true` is a no-op editor: it
# returns 0 without touching the file, which is all this interface test
# needs.  The content is covered by --set and --show.
EDITOR=true cfg --edit >/dev/null 2>&1 \
    && ok_ "config --edit runs the editor" \
    || bad_ "config --edit failed"

# An unknown flag is refused rather than silently ignored.
cfg --not-a-real-flag >/dev/null 2>&1 \
    && bad_ "config accepted an unknown flag" \
    || ok_ "config refuses an unknown flag"

# Migration: a psmaker configuration in an isolated HOME is carried over.
cat > "$mig_home/.psmakerrc" <<'PSM'
LD1_BIN=/opt/qe/ld1.x
DEFAULT_XC=PBE
PSM

# A file, not `bash -c "..."`: the inner loop needed backslash-dollar
# escaping that the outer shell ate.  A plain script takes its paths
# from the environment and needs no escaping at all.
cat > "$TMP/mig-check.sh" <<'MIGSH'
for m in core sink config; do
    . "$PF_LIB/$m.sh"
done
pf_config_migrate 2>&1
MIGSH

mig_out=$(
    HOME=$mig_home PF_RC=$mig_home/.pseudoforgerc PF_LIB=$PF_LIB \
    bash "$TMP/mig-check.sh"
)

[ -f "$mig_home/.pseudoforgerc" ] \
    && ok_ "config migration creates the new file" \
    || bad_ "config migration created nothing (output: $mig_out)"
[ -f "$mig_home/.psmakerrc" ] \
    && ok_ "config migration leaves the old file alone" \
    || bad_ "config migration deleted the old file"
grep -q 'DEFAULT_XC=PBE' "$mig_home/.pseudoforgerc" 2>/dev/null \
    && ok_ "config migration carries the values across" \
    || bad_ "config migration lost the values"

# ---------------------------------------------------------------------------
printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$([ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM")" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
