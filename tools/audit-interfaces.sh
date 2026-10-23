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
export LD1_BIN=${LD1_BIN:-$ROOT/tests/mock/ld1.x}

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
--template --tui --type --which-augfun --why --yes
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
check_key "$out" beta 0.1 ui_advanced
check_key "$out" tr2 1.0d-14 ui_advanced

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
section "J. recipe round-trip across the interfaces"

# The recipe file is the one serialized form both interfaces agree on.
# The CLI writes one with `recipe save` and reads one with `--recipe`;
# the TUI writes one with "Save these choices" and reads one with
# "Load a recipe".  Both call rcp_save / rcp_load.  If the SPEC that
# comes back differs from the SPEC that went in, one of the two is
# describing a run it will not produce -- and the user, told to
# "reload it later with --recipe <name>", is being lied to.

RECIPE_DIR=$TMP/recipes
export RECIPE_DIR
mkdir -p "$RECIPE_DIR"

RECIPE_LIBS="core sink config deps elements xc namelist profiles metadata
             formats gth sssp convert doctor params engines build recipe
             input_builder executor project run upf testing validate
             report cli ui tui wizard"

# Every user-settable key, so a field that goes missing in either
# direction shows up as a difference in the canonical line.
spec_fixture() {
    SPEC[family]=paw
    SPEC[profile]=psl-high
    SPEC[xc]=pbe
    SPEC[rel]=scalar
    SPEC[engine]=ld1
    SPEC[source]=local
    SPEC[formats]=upf
    SPEC[core_hole]=1s
    SPEC[zval]=4
    SPEC[nlcc]=1
    SPEC[rcore]=1.20
    SPEC[rho0]=0.015
    SPEC[which_augfun]=BESSEL
    SPEC[rmatch_augfun]=1.10
    SPEC[lloc]=s
    SPEC[rcloc]=1.00
    SPEC[rcut_scale]=1.05
    SPEC[beta]=0.30
    SPEC[tr2]=1e-12
    SPEC[lsd]=0
    SPEC[gipaw]=0
    SPEC[extra_projectors]='d l=2'
    SPEC[xmin]=-7.0
    SPEC[dx]=0.01
    SPEC[rmax]=100.0
}

# A fresh shell with every module loaded; "$@" runs inside it.
recipe_shell() {
    (
        for m in $RECIPE_LIBS; do
            . "$PF_LIB/$m.sh" 2>/dev/null || true
        done
        pf_config_defaults
        pf_elements_load; pf_xc_load; pf_profiles_load
        pf_engines_load; pf_metadata_load; pf_formats_load
        spec_init
        CLI_ELEMENTS=Si
        "$@"
    )
}

save_fixture() { spec_fixture; rcp_save "$1" "round-trip fixture" >/dev/null 2>&1; spec_cmdline; }
load_fixture() { rcp_load "$1" >/dev/null 2>&1 || { echo LOADFAIL; return 1; }; spec_cmdline; }

before=$(recipe_shell save_fixture roundtrip 2>/dev/null)
after=$(recipe_shell load_fixture roundtrip 2>/dev/null)

if [ -n "$before" ] && [ "$before" = "$after" ]; then
    ok_ "recipe: CLI save -> CLI load is byte-identical"
else
    bad_ "recipe: CLI save -> CLI load differs" "before: $before
        after:  $after"
fi

# The file itself must be a real recipe: header, elements, custom keys.
rf=$RECIPE_DIR/roundtrip.recipe
if [ -f "$rf" ] \
   && grep -q '^elements=Si$' "$rf" \
   && grep -qE '^spec\.rcore=1\.20' "$rf" \
   && grep -qE '^spec\.extra_projectors=d l=2' "$rf"; then
    ok_ "recipe file: header, elements and custom keys are on disk"
else
    bad_ "recipe file is missing header or custom keys" "$(head -20 "$rf" 2>&1)"
fi

# --- TUI save -> CLI load ------------------------------------------------

drive_tui_save_recipe() {
    local name=$1
    printf '%s\nok\n' "$name" > "$TMP/ans-recipe-save"
    PATH="$ROOT/tests/mock:$PATH"
    export MOCK_WT_LOG=$TMP/wt-recipe-save.log MOCK_WT_ANSWERS=$TMP/ans-recipe-save
    : > "$MOCK_WT_LOG"
    (
        for m in $RECIPE_LIBS; do
            . "$PF_LIB/$m.sh" 2>/dev/null || true
        done
        pf_config_defaults
        pf_elements_load; pf_xc_load; pf_profiles_load
        pf_engines_load; pf_metadata_load; pf_formats_load
        spec_init
        CLI_ELEMENTS=Si
        spec_fixture
        ui_term_size() { UI_ROWS=40; UI_COLS=120; }
        ui_init
        exec < /dev/null
        tui_save_recipe
    ) 2>/dev/null
}

drive_tui_load_recipe() {
    local name=$1
    printf '%s\nok\n' "$name" > "$TMP/ans-recipe-load"
    PATH="$ROOT/tests/mock:$PATH"
    export MOCK_WT_LOG=$TMP/wt-recipe-load.log MOCK_WT_ANSWERS=$TMP/ans-recipe-load
    : > "$MOCK_WT_LOG"
    (
        for m in $RECIPE_LIBS; do
            . "$PF_LIB/$m.sh" 2>/dev/null || true
        done
        pf_config_defaults
        pf_elements_load; pf_xc_load; pf_profiles_load
        pf_engines_load; pf_metadata_load; pf_formats_load
        spec_init
        ui_term_size() { UI_ROWS=40; UI_COLS=120; }
        ui_init
        exec < /dev/null
        tui_load_recipe >/dev/null 2>&1
        spec_cmdline
    ) 2>/dev/null
}

rm -f "$RECIPE_DIR/from-tui.recipe"
drive_tui_save_recipe from-tui >/dev/null
if [ -f "$RECIPE_DIR/from-tui.recipe" ]; then
    after=$(recipe_shell load_fixture from-tui 2>/dev/null)
    if [ -n "$after" ] && [ "$after" = "$before" ]; then
        ok_ "recipe: TUI save -> CLI load is byte-identical"
    else
        bad_ "recipe: TUI save -> CLI load differs" "expected: $before
        got:      $after"
    fi
else
    bad_ "recipe: tui_save_recipe did not write a file"
fi

# --- CLI save -> TUI load ------------------------------------------------

recipe_shell save_fixture cli-to-tui >/dev/null 2>&1
after=$(drive_tui_load_recipe cli-to-tui)
if [ -n "$after" ] && [ "$after" = "$before" ]; then
    ok_ "recipe: CLI save -> TUI load is byte-identical"
else
    bad_ "recipe: CLI save -> TUI load differs" "expected: $before
        got:      $after"
fi

# --- refusals ------------------------------------------------------------

# rcp_list shows what was saved.
listing=$(recipe_shell rcp_list 2>/dev/null)
if printf '%s' "$listing" | grep -q '^roundtrip'; then
    ok_ "recipe list: saved recipes appear"
else
    bad_ "recipe list: roundtrip not listed" "$listing"
fi

# A file that claims a newer format must be refused, not read with the
# older one.
magic_line=$(grep -m1 -E '^[a-zA-Z]' "$rf" 2>/dev/null)
magic_key=${magic_line%%=*}; magic_val=${magic_line#*=}
future=$RECIPE_DIR/future.recipe
sed "s/^$magic_key=.*$/$magic_key=$((magic_val + 100))/" "$rf" > "$future"
if recipe_shell load_fixture future >/dev/null 2>&1; then
    bad_ "recipe: future format was accepted"
else
    ok_ "recipe: future format refused"
fi

# An unknown spec.* key is a setting this version does not know.  Refuse
# rather than generate a run that silently drops it.
unknown=$RECIPE_DIR/unknown.recipe
{ cat "$rf"; printf 'spec.what_is_this=42\n'; } > "$unknown"
if recipe_shell load_fixture unknown >/dev/null 2>&1; then
    bad_ "recipe: unknown spec key was accepted"
else
    ok_ "recipe: unknown spec key refused"
fi

# An unknown top-level key, same rule.
stranger=$RECIPE_DIR/stranger.recipe
{ cat "$rf"; printf 'mystery=1\n'; } > "$stranger"
if recipe_shell load_fixture stranger >/dev/null 2>&1; then
    bad_ "recipe: unknown top-level key was accepted"
else
    ok_ "recipe: unknown top-level key refused"
fi
# ---------------------------------------------------------------------------
section "K. engine-specific menus"

# Two menus narrow the choice: the format picker (only what the chosen
# engine writes) and the engine picker (only what the library's own
# decks can drive).  A format the engine cannot write is refused three
# screens later; a format it does write but the menu hides is one the
# user cannot ask for.  Either way the interface and the core disagree.

ENGINES="ld1 oncvpsp uspp fhi98pp opium gth atompaw ape adpack"

# What each engine writes, in the registry's own order.  Kept here so a
# change to data/formats.tsv that alters the menu shows up as a diff and
# not as a silent shift in what the TUI offers.
expected_formats() {
    case $1 in
        ld1)      printf 'upf xml\n' ;;
        oncvpsp)  printf 'upf psp8 xml\n' ;;
        uspp)     printf 'upf xml uspp van\n' ;;
        fhi98pp)  printf 'xml cpi\n' ;;
        opium)    printf 'upf fhi recpot siesta cpmd casino champ teter qso ncpp xml\n' ;;
        gth)      printf 'gth gth-cpmd gth-abinit\n' ;;
        atompaw)  printf 'upf paw-abinit paw-xml\n' ;;
        ape)      printf 'upf\n' ;;
        adpack)   printf 'openmx openmx-pao\n' ;;
    esac
}

fmt_shell() {
    (
        for m in core sink config deps elements xc namelist profiles metadata \
                 formats gth sssp convert doctor params engines recipe; do
            . "$PF_LIB/$m.sh" 2>/dev/null || true
        done
        pf_formats_load
        "$@"
    )
}

for eng in $ENGINES; do
    want=$(expected_formats "$eng")
    got=$(fmt_shell fmt_for_engine "$eng" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
    if [ "$got" = "$want" ]; then
        ok_ "fmt_for_engine $eng -> $want"
    else
        bad_ "fmt_for_engine $eng differs" "want: $want
        got:  $got"
    fi
done

accept_format() {   # accept_format <engine> <formats> <expected>
    local eng=$1 fmt=$2 want=$3 got
    got=$(fmt_shell fmt_validate "$eng" "$fmt" 2>/dev/null)
    if [ "$got" = "$want" ]; then
        ok_ "fmt_validate $eng '$fmt' -> '$want'"
    else
        bad_ "fmt_validate $eng '$fmt' -> '$got' (expected '$want')"
    fi
}
refuse_format() {   # refuse_format <engine> <formats>
    local eng=$1 fmt=$2
    if fmt_shell fmt_validate "$eng" "$fmt" >/dev/null 2>&1; then
        bad_ "fmt_validate $eng '$fmt' was accepted"
    else
        ok_ "fmt_validate $eng '$fmt' refused"
    fi
}

accept_format ld1 upf upf
accept_format ld1 'upf xml' 'upf xml'
accept_format ape upf upf
accept_format adpack 'openmx openmx-pao' 'openmx openmx-pao'
refuse_format ld1 cpi
refuse_format ape psp8
refuse_format fhi98pp upf
refuse_format adpack upf
refuse_format uspp psp8

# --- ui_pick_format -------------------------------------------------------
#
# The mock whiptail records every dialog it was asked to show, one per
# line, as `<kind>\t<title>\t<tag1> <tag2> ...`.  A single-format engine
# must not open a dialog at all: it takes its one format from the
# registry, sets SPEC[formats] and returns 3.
PICK_LIBS="core sink config deps elements xc namelist profiles metadata
           formats gth sssp convert doctor params engines build recipe
           input_builder executor project run upf testing validate
           report cli ui tui wizard"

run_pick_format() {
    local eng=$1 answer=$2
    printf '%s\n' "$answer" > "$TMP/pf.ans"
    PATH="$ROOT/tests/mock:$PATH"
    export MOCK_WT_LOG=$TMP/pf.log MOCK_WT_ANSWERS=$TMP/pf.ans
    : > "$MOCK_WT_LOG"
    (
        for m in $PICK_LIBS; do . "$PF_LIB/$m.sh" 2>/dev/null || true; done
        pf_config_defaults
        pf_elements_load; pf_xc_load; pf_profiles_load
        pf_engines_load; pf_metadata_load; pf_formats_load
        spec_init
        SPEC[engine]=$eng
        SPEC[source]=local
        ui_term_size() { UI_ROWS=40; UI_COLS=120; }
        ui_init
        exec < /dev/null
        ui_pick_format >/dev/null 2>&1
        printf 'rc=%s\n' "$?"
        printf 'formats=%s\n' "${SPEC[formats]:-}"
    ) 2>/dev/null
}

# APE writes only upf; no menu, and SPEC must carry what the engine writes.
out=$(run_pick_format ape CANCEL)
rc=$(printf '%s\n' "$out" | awk -F= '$1=="rc"{print $2}')
fmt=$(printf '%s\n' "$out" | awk -F= '$1=="formats"{print $2}')
if [ "$rc" = 3 ] && [ "$fmt" = upf ]; then
    ok_ "ui_pick_format ape: SPEC[formats]=upf, rc=3"
else
    bad_ "ui_pick_format ape: rc=$rc formats=$fmt (expected rc=3 formats=upf)"
fi
if grep -qE '^menu\t' "$TMP/pf.log"; then
    bad_ "ui_pick_format ape opened a menu" "$(cat "$TMP/pf.log")"
else
    ok_ "ui_pick_format ape opened no menu"
fi

# ld1 writes upf and xml.  The menu offers both, plus the "more" item.
out=$(run_pick_format ld1 xml)
rc=$(printf '%s\n' "$out" | awk -F= '$1=="rc"{print $2}')
fmt=$(printf '%s\n' "$out" | awk -F= '$1=="formats"{print $2}')
if [ "$rc" = 0 ] && [ "$fmt" = xml ]; then
    ok_ "ui_pick_format ld1/xml: SPEC[formats]=xml, rc=0"
else
    bad_ "ui_pick_format ld1/xml: rc=$rc formats=$fmt"
fi
if awk -F'\t' '$1=="menu" && $3=="upf xml more"' "$TMP/pf.log" | grep -q .; then
    ok_ "ui_pick_format ld1 offers upf, xml, more"
else
    bad_ "ui_pick_format ld1 menu is wrong" "$(cat "$TMP/pf.log")"
fi

# oncvpsp writes upf, psp8, xml -- not cpi, not uspp.
out=$(run_pick_format oncvpsp upf)
if awk -F'\t' '$1=="menu" && $3=="upf psp8 xml more"' "$TMP/pf.log" | grep -q .; then
    ok_ "ui_pick_format oncvpsp offers exactly upf, psp8, xml, more"
else
    bad_ "ui_pick_format oncvpsp menu is wrong" "$(cat "$TMP/pf.log")"
fi

# --- ui_pick_engine -------------------------------------------------------
#
# eng_available is stubbed so the audit is deterministic whether or not
# the engines happen to be installed on this machine.  What is being
# checked is the profile+family filter, not the filesystem.
run_pick_engine() {
    local prof=$1 fam=$2 answer=$3
    printf '%s\n' "$answer" > "$TMP/pe.ans"
    PATH="$ROOT/tests/mock:$PATH"
    export MOCK_WT_LOG=$TMP/pe.log MOCK_WT_ANSWERS=$TMP/pe.ans
    : > "$MOCK_WT_LOG"
    (
        for m in $PICK_LIBS; do . "$PF_LIB/$m.sh" 2>/dev/null || true; done
        pf_config_defaults
        pf_elements_load; pf_xc_load; pf_profiles_load
        pf_engines_load; pf_metadata_load; pf_formats_load
        spec_init
        SPEC[profile]=$prof
        SPEC[family]=$fam
        SPEC[source]=local
        eng_available() { return 0; }
        ui_term_size() { UI_ROWS=40; UI_COLS=120; }
        ui_init
        exec < /dev/null
        ui_pick_engine >/dev/null 2>&1
        printf 'rc=%s\n' "$?"
        printf 'engine=%s\n' "${SPEC[engine]:-}"
    ) 2>/dev/null
}

# psl-high + paw: only ld1 makes PAW data sets from a PSlibrary deck.
out=$(run_pick_engine psl-high paw ld1)
rc=$(printf '%s\n' "$out" | awk -F= '$1=="rc"{print $2}')
eng=$(printf '%s\n' "$out" | awk -F= '$1=="engine"{print $2}')
if [ "$rc" = 3 ] && [ "$eng" = ld1 ]; then
    ok_ "ui_pick_engine psl-high/paw: only ld1, rc=3"
else
    bad_ "ui_pick_engine psl-high/paw: rc=$rc engine=$eng"
fi

# sg15 + nc: oncvpsp or opium.  A menu appears; nothing else is offered.
out=$(run_pick_engine sg15 nc oncvpsp)
if awk -F'\t' '$1=="menu" && $3=="oncvpsp opium"' "$TMP/pe.log" | grep -q .; then
    ok_ "ui_pick_engine sg15/nc offers exactly oncvpsp and opium"
else
    bad_ "ui_pick_engine sg15/nc menu is wrong" "$(cat "$TMP/pe.log")"
fi

# gbrv + us: only uspp writes the US family.
out=$(run_pick_engine gbrv us uspp)
rc=$(printf '%s\n' "$out" | awk -F= '$1=="rc"{print $2}')
eng=$(printf '%s\n' "$out" | awk -F= '$1=="engine"{print $2}')
if [ "$rc" = 3 ] && [ "$eng" = uspp ]; then
    ok_ "ui_pick_engine gbrv/us: only uspp, rc=3"
else
    bad_ "ui_pick_engine gbrv/us: rc=$rc engine=$eng"
fi
# ---------------------------------------------------------------------------
section "L. refusal matrix in the TUI"

# cli_check_spec refuses a spec that cannot run: --projector on an engine
# whose deck builder ignores it, --upf 1 (no engine here writes v1),
# --rcut-scale on an engine that does not implement it, a family the
# engine cannot make, an engine path that cannot express the functional.
#
# The TUI reaches that refusal through cmd_generate, after the review
# screen and the Start prompt.  These checks drive tui_review with the
# scripted whiptail and assert that (a) the subshell exits non-zero,
# (b) nothing is written to the chosen output directory, and (c) the
# CLI refuses the same SPEC -- so the two interfaces are not deciding
# differently about the same run.

run_tui_refusal() {
    local tag=$1 specset=$2
    local outdir=$TMP/refuse-$tag
    rm -rf "$outdir"

    printf 'run\n%s\nyes\n' "$outdir" > "$TMP/rf-$tag.ans"
    PATH="$ROOT/tests/mock:$PATH"
    export MOCK_WT_LOG=$TMP/rf-$tag.log MOCK_WT_ANSWERS=$TMP/rf-$tag.ans
    : > "$MOCK_WT_LOG"

    local rc=0
    (
        for m in $PICK_LIBS; do . "$PF_LIB/$m.sh" 2>/dev/null || true; done
        pf_config_defaults
        pf_elements_load; pf_xc_load; pf_profiles_load
        pf_engines_load; pf_metadata_load; pf_formats_load
        spec_init
        CLI_ELEMENTS=Si
        SPEC[profile]=pseudoforge-auto
        SPEC[family]=nc
        SPEC[xc]=pbe
        SPEC[rel]=scalar
        SPEC[source]=local
        SPEC[engine]=oncvpsp
        SPEC[formats]=upf
        case $specset in
            projector)   SPEC[extra_projectors]='d l=2' ;;
            upf1)        SPEC[upf]=1 ;;
            wrongfam)    SPEC[family]=paw; SPEC[engine]=oncvpsp ;;
            rcutscale)   SPEC[family]=us; SPEC[engine]=uspp
                         SPEC[rcut_scale]=1.10 ;;
            metagga)     SPEC[family]=paw; SPEC[engine]=atompaw
                         SPEC[xc]=tpss ;;
        esac
        RUN_LD1_TESTS=0
        ui_term_size() { UI_ROWS=40; UI_COLS=120; }
        ui_init
        exec < /dev/null
        tui_review
    ) > "$TMP/rf-$tag.out" 2>&1
    rc=$?

    if [ "$rc" -ne 0 ]; then
        ok_ "TUI refuses $tag (exit $rc)"
    else
        bad_ "TUI accepted $tag -- exit 0" "$(tail -5 "$TMP/rf-$tag.out")"
    fi

    if [ -d "$outdir" ] && find "$outdir" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
        bad_ "TUI wrote files for $tag before refusing" "$(find "$outdir" -type f | head -3)"
    else
        ok_ "TUI wrote nothing for $tag"
    fi

    # The mock log: the review menu was shown, so the user saw what was
    # about to run before the refusal.  That is the point of refusing
    # here rather than silently fixing it.
    if grep -q $'^menu\tReview' "$TMP/rf-$tag.log"; then
        ok_ "TUI showed the Review screen before refusing $tag"
    else
        bad_ "TUI refused $tag without showing the Review screen" "$(cat "$TMP/rf-$tag.log")"
    fi
}

run_tui_refusal projector projector
run_tui_refusal upf1      upf1
run_tui_refusal wrongfam  wrongfam
run_tui_refusal rcutscale rcutscale
run_tui_refusal metagga   metagga

# The CLI refuses the same SPEC.  Same cli_check_spec, but reached from
# the command line rather than from cmd_generate; if the two ever
# disagree, the audit says so here.
cli_refusal() {   # cli_refusal <tag> <args...>
    local tag=$1; shift
    local outdir=$TMP/cli-refuse-$tag
    rm -rf "$outdir"
    if "$PSM" generate -e Si -o "$outdir" --no-test -q "$@" >/dev/null 2>&1; then
        bad_ "CLI accepted $tag"
    else
        ok_ "CLI refuses $tag"
    fi
}

cli_refusal projector -p pseudoforge-auto --engine oncvpsp --projector 'd l=2'
cli_refusal upf1      -p pseudoforge-auto --upf 1
cli_refusal wrongfam  -p pseudoforge-auto --engine oncvpsp -t paw
cli_refusal rcutscale -p pseudoforge-auto --engine uspp -t us --rcut-scale 1.10
cli_refusal metagga   -p pseudoforge-auto --engine atompaw -t paw -x tpss
# ---------------------------------------------------------------------------
section "M. sub-subcommand --help"

# A subcommand that answers `--help` when asked on its own (`native --help`)
# and treats `--help` as a real argument one level deeper (`native index
# --help`) is half a help system.  The user typing the second form is
# asking the same question and deserves the same answer -- not "no native
# directory: --help", and certainly not a --help.prof created in their
# profile directory.

# EDITOR points at a no-op.  `profile edit --help` used to run $EDITOR
# against a file named --help; without this it would block in vim.
EDITOR=/bin/true
export EDITOR

# A fresh $HOME so a run that ignores `--help` and does what it was told
# cannot write into the user's real configuration.
hh=$TMP/help-home
mkdir -p "$hh"

# Each entry: `<sub> <subsub>`.
SUBSUB="
native index
native list
native size
params status
params fetch
params path
params extract
profile list
profile new
profile edit
profile remove
xc list
xc add
xc remove
recipe save
recipe load
recipe list
recipe export
recipe import
recipe path
engines list
engines build
engines show
engines path
"

# while read, not `for spec in $SUBSUB`: the loop variable is per line,
# so `native index` stays two fields instead of collapsing to the word
# "native" and the word "index" as separate iterations.
while IFS= read -r spec; do
    [ -n "$spec" ] || continue
    sub=${spec%% *}
    ssub=${spec#* }
    out=$(HOME=$hh PF_USER_DATA=$hh/.pseudoforge "$PSM" "$sub" "$ssub" --help 2>&1)
    rc=$?
    if [ "$rc" != 0 ]; then
        bad_ "$sub $ssub --help: exit $rc" "$(printf '%s\n' "$out" | head -3)"
        continue
    fi
    if ! printf '%s\n' "$out" | grep -q '^usage:'; then
        bad_ "$sub $ssub --help: no usage line" "$(printf '%s\n' "$out" | head -3)"
        continue
    fi
    ok_ "$sub $ssub --help"
done <<< "$SUBSUB"

# The side-effect check.  A sub-subcommand that runs the command rather
# than printing help leaves something behind; the audit is the place
# that says so.
# `pf_config_load` creates $HOME/.pseudoforgerc on any run; that is by
# design.  What must not appear is a file or directory named after the
# sub-subcommand the user asked to see help for -- `--help.prof`,
# `--help/index.tsv`, and so on.
if find "$hh" -name '*--help*' -print -quit 2>/dev/null | grep -q .; then
    bad_ "a sub-subcommand --help wrote a file named after itself" \
         "$(find "$hh" -name '*--help*' | head -5)"
else
    ok_ "sub-subcommand --help wrote nothing named after itself"
fi
# ---------------------------------------------------------------------------
section "N. every flag parses into the variable it names"

# cli_parse is where a flag becomes a variable, and that variable is what
# every stage after it reads.  A flag that is documented and does not
# reach its destination is a silent no-op: the user asked for something,
# the tool accepted the argument, and nothing happened.  This is the
# failure mode the audit exists to make loud.

parse_show() {
    local var=$1; shift
    (
        for m in $PICK_LIBS; do . "$PF_LIB/$m.sh" 2>/dev/null || true; done
        pf_config_defaults
        pf_elements_load; pf_xc_load; pf_profiles_load
        pf_engines_load; pf_metadata_load; pf_formats_load
        spec_init
        CLI_ELEMENTS=
        cli_parse "$@" 2>/dev/null || true
        eval "printf '%s\n' \"\${$var:-}\""
    )
}

check_flag() {   # <varname> <expected> <label> <flag> [value]
    local var=$1 want=$2 label=$3; shift 3
    local got
    got=$(parse_show "$var" "$@" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ "$got" = "$want" ]; then
        ok_ "flag $label: $var = $want"
    else
        bad_ "flag $label: $var = '$got' (want '$want')"
    fi
}

# Spec identity -------------------------------------------------------
check_flag SPEC[family]  nc      "family (-t)"          -t nc
check_flag SPEC[family]  paw     "family (--family)"    --family paw
check_flag SPEC[family]  us      "family (--type)"      --type us
check_flag SPEC[profile] psl-high "profile"             -p psl-high
check_flag SPEC[xc]      pbe     "xc (-x)"              -x pbe
check_flag SPEC[xc]      pbesol  "xc (--functional)"    --functional pbesol
check_flag SPEC[rel]     scalar  "rel (-r)"             -r scalar
check_flag SPEC[rel]     full    "rel (--relativity)"   --relativity full
check_flag SPEC[variant] dn      "variant"              --variant dn
check_flag SPEC[upf]     2       "upf"                  --upf 2

# Output and run shape ------------------------------------------------
check_flag CLI_ELEMENTS  "Fe"    "elements (-e)"        -e Fe
check_flag CLI_ELEMENTS  "Fe Si" "elements (-e twice)"  -e Fe -e Si
check_flag CLI_OUTPUT    /tmp/x  "output"               -o /tmp/x
check_flag MAX_PARALLEL_JOBS 8   "jobs (-j)"            -j 8

# User-settable keys on the advanced screen ---------------------------
check_flag SPEC[author]        "Me"          "author"       --author Me
check_flag SPEC[config]        "[Ne] 3s2"    "config"       --config "[Ne] 3s2"
check_flag SPEC[core_hole]     1s            "core-hole"    --core-hole 1s
check_flag SPEC[zed]           13.5          "zed"          --zed 13.5
check_flag SPEC[zval]          4             "zval"         --zval 4
check_flag SPEC[nlcc]          1             "nlcc"         --nlcc 1
check_flag SPEC[rcore]         1.25          "rcore"        --rcore 1.25
check_flag SPEC[rho0]          0.015         "rho0"         --rho0 0.015
check_flag SPEC[which_augfun]  BESSEL        "augfun"       --augfun BESSEL
check_flag SPEC[which_augfun]  GAUSS         "which-augfun" --which-augfun GAUSS
check_flag SPEC[rmatch_augfun] 1.10          "rmatch"       --rmatch 1.10
check_flag SPEC[lloc]          s             "lloc"         --lloc s
check_flag SPEC[rcloc]         1.0           "rcloc"        --rcloc 1.0
check_flag SPEC[extra_projectors] "d l=2"    "projector"    --projector "d l=2"
check_flag SPEC[rcut_scale]    1.05          "rcut-scale"   --rcut-scale 1.05
check_flag SPEC[nc_form]       separable     "nc-form"      --nc-form separable
check_flag SPEC[lsd]           1             "lsd"          --lsd
check_flag SPEC[gipaw]         1             "gipaw"        --gipaw
check_flag SPEC[beta]          0.3           "beta"         --beta 0.3
check_flag SPEC[tr2]           1e-12         "tr2"          --tr2 1e-12

# --grid carries three keys in one argument ---------------------------
check_flag SPEC[xmin] -7    "grid xmin" --grid -7:0.01:100
check_flag SPEC[dx]   0.01  "grid dx"   --grid -7:0.01:100
check_flag SPEC[rmax] 100   "grid rmax" --grid -7:0.01:100

# Engine, source, format ----------------------------------------------
check_flag CLI_ENGINE   ld1     "engine"    --engine ld1
check_flag CLI_SOURCE   online  "source"    --source online
check_flag CLI_FORMATS  upf     "format"    --format upf
check_flag CLI_FORMATS  "upf xml" "formats" --formats "upf xml"

# Execution toggles ---------------------------------------------------
check_flag RUN_LD1_TESTS      0  "no-test"          --no-test
check_flag RUN_LD1_TESTS      1  "test"             --test
check_flag RUN_CUTOFF_SCAN    1  "cutoff-scan"      --cutoff-scan
check_flag RUN_CUTOFF_SCAN    0  "no-cutoff-scan"   --no-cutoff-scan
check_flag CUTOFF_SCAN_LIST   "60,80,100" "cutoffs" --cutoffs 60,80,100
check_flag AUTOFIX_ENABLED    0  "no-autofix"       --no-autofix
check_flag AUTOFIX_ENABLED    1  "autofix"          --autofix
check_flag AUTOFIX_MAX_ATTEMPTS 5 "attempts"        --attempts 5
check_flag RESUME             1  "resume"           --resume
check_flag RESUME             0  "no-resume"        --no-resume
check_flag PF_QUIET           1  "quiet"            -q
check_flag PF_VERBOSE         1  "verbose"          -v

# Sanity: with no flags, spec_init still leaves a value in SPEC[family].
out=$(parse_show SPEC[family])
if [ -n "$out" ]; then
    ok_ "no flags: spec_init sets SPEC[family]"
else
    bad_ "no flags: SPEC[family] is empty"
fi
# ---------------------------------------------------------------------------
section "O. wizard text-mode, end to end"

# The wizard's flow, driven through PF_FORCE_TEXT so no terminal is
# needed.  tests/test_custom.sh has a shallow version that stops at the
# first prompt.  This one answers every question, then checks the whole
# identity the user picked and the file layout the confirm screen would
# create -- or not, when the user says no.

WIZ_LIBS="core sink config deps elements xc namelist profiles metadata
          formats gth sssp convert doctor params engines build recipe
          input_builder executor fetch project run upf testing validate
          report cli ui tui wizard"

drive_wizard_full() {
    local input=$1
    (
        export PF_FORCE_TEXT=1
        for m in $WIZ_LIBS; do . "$PF_LIB/$m.sh" 2>/dev/null || true; done
        pf_config_defaults
        pf_elements_load; pf_xc_load; pf_profiles_load
        pf_engines_load; pf_metadata_load; pf_formats_load
        spec_init
        wiz_init
        # Process substitution, not a pipe: `printf ... | wizard_main`
        # runs wizard_main in a subshell, and every SPEC value it sets
        # is lost when that subshell exits -- the caller then reads the
        # spec_init defaults and reports them as the wizard's answer.
        wizard_main < <(printf -- "$input") >/dev/null 2>&1
        printf 'wrc=%s\n' "$?"
        for k in family xc rel profile source; do
            printf 'SPEC[%s]=%s\n' "$k" "${SPEC[$k]:-}"
        done
    ) 2>/dev/null
}

# --- Cancel at confirmation ----------------------------------------------
#
# Answers land in the order the prompts appear:
#   1: family (3 = nc)
#   2: functional (1 = pbe, always first in the short list)
#   3: relativity (1 = scalar)
#   4: profile (1 = first the family offers; checked as non-empty)
#   5: source (1 = online; skips the engine prompt)
#   6: elements (Si)
#   7: output directory
#   8: confirm (n)
wiz_out=$TMP/wiz-cancel
rm -rf "$wiz_out"

out=$(drive_wizard_full "3\n1\n1\n1\n1\nSi\n$wiz_out\nn\n")

fam=$(printf '%s\n' "$out" | awk -F= '$1=="SPEC[family]"{print $2}')
xc=$(printf '%s\n'  "$out" | awk -F= '$1=="SPEC[xc]"{print $2}')
rel=$(printf '%s\n' "$out" | awk -F= '$1=="SPEC[rel]"{print $2}')
prof=$(printf '%s\n' "$out" | awk -F= '$1=="SPEC[profile]"{print $2}')
src=$(printf '%s\n' "$out" | awk -F= '$1=="SPEC[source]"{print $2}')

[ "$fam" = nc ]       && ok_ "wizard: family=nc"      || bad_ "wizard: family='$fam' (want nc)"
[ "$xc"  = pbe ]      && ok_ "wizard: xc=pbe"         || bad_ "wizard: xc='$xc' (want pbe)"
[ "$rel" = scalar ]   && ok_ "wizard: rel=scalar"     || bad_ "wizard: rel='$rel' (want scalar)"
[ -n "$prof" ]        && ok_ "wizard: profile=$prof"  || bad_ "wizard: profile is empty"
[ "$src" = online ]   && ok_ "wizard: source=online"  || bad_ "wizard: source='$src' (want online)"

# Cancel must not leave a project behind.  The wizard only calls
# project_init after wiz_confirm returns 0.
if [ -d "$wiz_out" ] && find "$wiz_out" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
    bad_ "wizard: Cancel wrote a project" "$(find "$wiz_out" -mindepth 1 | head -3)"
else
    ok_ "wizard: Cancel wrote nothing"
fi

# --- A second pass, different answers ------------------------------------
#
# The same flow with a different family and functional.  If the wizard
# is only right for the answers above, the audit should say so.

wiz_out2=$TMP/wiz-cancel2
rm -rf "$wiz_out2"

out=$(drive_wizard_full "1\n2\n2\n1\n1\nFe\n$wiz_out2\nn\n")

fam=$(printf '%s\n' "$out" | awk -F= '$1=="SPEC[family]"{print $2}')
xc=$(printf '%s\n'  "$out" | awk -F= '$1=="SPEC[xc]"{print $2}')
rel=$(printf '%s\n' "$out" | awk -F= '$1=="SPEC[rel]"{print $2}')
src=$(printf '%s\n' "$out" | awk -F= '$1=="SPEC[source]"{print $2}')

[ "$fam" = paw ]      && ok_ "wizard: family=paw"      || bad_ "wizard: family='$fam' (want paw)"
[ "$xc"  = pbesol ]   && ok_ "wizard: xc=pbesol"       || bad_ "wizard: xc='$xc' (want pbesol)"
[ "$rel" = full ]     && ok_ "wizard: rel=full"        || bad_ "wizard: rel='$rel' (want full)"
[ "$src" = online ]   && ok_ "wizard: source=online"   || bad_ "wizard: source='$src' (want online)"

if [ -d "$wiz_out2" ] && find "$wiz_out2" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
    bad_ "wizard: second Cancel wrote a project" "$(find "$wiz_out2" -mindepth 1 | head -3)"
else
    ok_ "wizard: second Cancel wrote nothing"
fi

# --- Bad answers leave SPEC alone ----------------------------------------
#
# An answer that is not on the menu is not a choice.  If the wizard
# accepts "9" for a four-item menu it will pick garbage rather than ask
# again; if it leaves SPEC at its previous value the run is at least
# not silently wrong.

out=$(DEFAULT_PSEUDOTYPE=nc drive_wizard_full "9\n")

fam=$(printf '%s\n' "$out" | awk -F= '$1=="SPEC[family]"{print $2}')
if [ "$fam" = nc ]; then
    ok_ "wizard: refused 9 for family (kept '$fam')"
else
    bad_ "wizard: accepted 9 for family as '$fam' (want nc)"
fi
# ---------------------------------------------------------------------------
section "P. store browse API"

# The HTTP interface is the fourth way a user meets the core, and the one
# a web front-end or a script would use.  Its read endpoints have to
# answer what the CLI answers, refuse what it refuses, and -- for the
# download route -- never turn an id into a path.

# A small, self-contained native store.  Building one from real files
# would need a run; the endpoints only look at the index and the path
# column, so a two-line index and a two-byte file are enough.
nat=$TMP/native
mkdir -p "$nat/UPF"
printf '<UPF version="2.0.1"/>' > "$nat/UPF/Si.pbe-n-nc.UPF"
printf '<UPF version="2.0.1"/>' > "$nat/UPF/Fe.pbe-spn-kjpaw.UPF"

# The columns are the ones NAT_COL declares; keep them in that order.
{
    printf '#id\telement\txc\tfamily\trelativity\tengine\tformat\tprofile\tencoding\tpath\tsize\tsha256\tprovenance\n'
    size1=$(stat -c%s "$nat/UPF/Si.pbe-n-nc.UPF")
    size2=$(stat -c%s "$nat/UPF/Fe.pbe-spn-kjpaw.UPF")
    sha1=$(sha256sum "$nat/UPF/Si.pbe-n-nc.UPF" | cut -d' ' -f1)
    sha2=$(sha256sum "$nat/UPF/Fe.pbe-spn-kjpaw.UPF" | cut -d' ' -f1)
    printf 'Si.pbe-n-nc.UPF\tSi\tpbe\tnc\tscalar\toncvpsp\tupf\tpsl-high\tplain\tUPF/Si.pbe-n-nc.UPF\t%s\t%s\t-\n' "$size1" "$sha1"
    printf 'Fe.pbe-spn-kjpaw.UPF\tFe\tpbe\tpaw\tscalar\tld1\tupf\tpsl-high\tplain\tUPF/Fe.pbe-spn-kjpaw.UPF\t%s\t%s\t-\n' "$size2" "$sha2"
} > "$nat/index.tsv"

# A request helper: PF_NATIVE_DIR points at the fixture, so the check is
# the same on a machine with a full store and on one with none.
api_status() {   # api_status <method> <path> [body]
    local m=$1 p=$2 b=${3:-} err
    err=$TMP/apierr
    PF_NATIVE_DIR=$nat "$PSM" api "$m" "$p" ${b:+"$b"} >/dev/null 2>"$err"
    awk '/^status:/ { print $2; exit }' "$err"
}
api_body() {   # api_body <method> <path> [body]
    local m=$1 p=$2 b=${3:-}
    PF_NATIVE_DIR=$nat "$PSM" api "$m" "$p" ${b:+"$b"} 2>/dev/null
}

# --- GET /api/native ------------------------------------------------------
st=$(api_status GET /api/native)
[ "$st" = 200 ] && ok_ "GET /api/native is 200" || bad_ "GET /api/native -> $st"

body=$(api_body GET /api/native)
if printf '%s' "$body" | grep -q 'Si.pbe-n-nc.UPF' \
   && printf '%s' "$body" | grep -q 'Fe.pbe-spn-kjpaw.UPF'; then
    ok_ "GET /api/native lists both fixture files"
else
    bad_ "GET /api/native missing a fixture file" "$(printf '%s' "$body" | head -c 400)"
fi

# Every advertised field is one of the index columns.  A new column the
# JSON does not carry is a field a script cannot read.
for field in id element xc family relativity engine format profile encoding size sha256; do
    printf '%s' "$body" | grep -q "\"$field\"" \
        && ok_ "GET /api/native carries '$field'" \
        || bad_ "GET /api/native has no '$field' field"
done

# --- GET /api/native/:id --------------------------------------------------
st=$(api_status GET /api/native/Si.pbe-n-nc.UPF)
[ "$st" = 200 ] && ok_ "GET /api/native/<known id> is 200" || bad_ "native one -> $st"

body=$(api_body GET /api/native/Si.pbe-n-nc.UPF)
if printf '%s' "$body" | grep -q '"element":"Si"' \
   && printf '%s' "$body" | grep -q '"family":"nc"'; then
    ok_ "GET /api/native/<id> returns the row's fields"
else
    bad_ "native one body is missing fields" "$(printf '%s' "$body" | head -c 300)"
fi

st=$(api_status GET /api/native/no-such-file.UPF)
[ "$st" = 404 ] && ok_ "GET /api/native/<unknown> is 404" || bad_ "unknown id -> $st"

# --- GET /api/download/:id -----------------------------------------------
st=$(api_status GET /api/download/Si.pbe-n-nc.UPF)
[ "$st" = 200 ] && ok_ "GET /api/download/<known id> is 200" || bad_ "download -> $st"

body=$(api_body GET /api/download/Si.pbe-n-nc.UPF)
# The transport serves the bytes; this only says where they are.  The
# path must be inside PF_NATIVE_DIR, not the caller's cwd or "/".
if printf '%s' "$body" | grep -q "\"path\":\"$nat/UPF/Si.pbe-n-nc.UPF\""; then
    ok_ "GET /api/download points inside PF_NATIVE_DIR"
else
    bad_ "download path is wrong" "$(printf '%s' "$body" | head -c 300)"
fi

st=$(api_status GET /api/download/no-such-file.UPF)
[ "$st" = 404 ] && ok_ "GET /api/download/<unknown> is 404" || bad_ "download unknown -> $st"

# Path traversal.  The handler checks for ".." and a leading "/" before
# it looks anywhere; a missing check would turn the endpoint into an
# arbitrary-file read.
for bad_id in "..%2Fetc%2Fpasswd" "../etc/passwd" "/etc/passwd" ".."; do
    st=$(api_status GET "/api/download/$bad_id")
    case $st in
        400|404) ok_ "GET /api/download/$bad_id refused ($st)" ;;
        *)       bad_ "GET /api/download/$bad_id accepted ($st)" ;;
    esac
done

# --- no index on this server ---------------------------------------------
#
# A machine that has not built a store is a normal state, not a crash.
# The endpoint says 503 and names the command that fixes it.
empty=$TMP/native-empty
mkdir -p "$empty"
err=$TMP/apierr2
PF_NATIVE_DIR=$empty "$PSM" api GET /api/native >/dev/null 2>"$err"
st=$(awk '/^status:/ { print $2; exit }' "$err")
[ "$st" = 503 ] \
    && ok_ "GET /api/native with no index is 503" \
    || bad_ "empty store -> $st (want 503)"

# The fix hint is part of the contract: an endpoint that says only
# "unavailable" makes the user guess.
body=$(PF_NATIVE_DIR=$empty "$PSM" api GET /api/native 2>/dev/null)
if printf '%s' "$body" | grep -q 'pseudoforge native index'; then
    ok_ "the 503 body names the fix"
else
    bad_ "the 503 body does not say how to fix it" "$(printf '%s' "$body" | head -c 300)"
fi

# --- the routes endpoint lists what is served ----------------------------
#
# `/api --routes` is the source of truth for what the API claims to be.
# The four store routes have to appear in it, or a client reads a route
# list that omits the endpoint it is about to call.
routes=$("$PSM" api --routes 2>/dev/null)
for r in /api/native /api/native/:id /api/download/:id...; do
    printf '%s\n' "$routes" | grep -q -- "$r" \
        && ok_ "route $r is declared" \
        || bad_ "route $r is missing from /api --routes"
done
# ---------------------------------------------------------------------------
printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$([ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM")" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
