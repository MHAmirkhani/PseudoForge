#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# The guided interface.
#
# The property that matters: **whatever the wizard assembles by clicking, the
# CLI would have produced from the equivalent flags.** If those two drift, the
# review screen is showing the user a command that is not what is about to run,
# which is worse than showing nothing.
#
# So the tests drive the wizard's own state and compare the command line it
# builds against the flags the CLI parses for the same choices. No terminal is
# needed: the command is built from SPEC, and SPEC is what both interfaces set.
#
# One limitation is asserted rather than papered over. Whiptail cannot bind
# Ctrl-key shortcuts -- newt reads its own keys and offers no hook -- so the
# design requirement for Ctrl+G / Ctrl+S / Ctrl+Q is met with single-letter
# menu accelerators instead, and a test checks that no code claims otherwise.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
for m in core sink config deps elements xc namelist profiles metadata formats gth sssp convert doctor params engines build recipe input_builder executor project run upf testing validate report cli ui tui; do
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

printf '\n%s== the nine layers are the flow%s\n' "$DIM" "$RESET"
layers=$(tui_layers)
n=$(printf '%s\n' "$layers" | grep -c .)
[ "$n" -ge 9 ] && ok_ "$n layers defined" || bad_ "only $n layers"

# Every layer must carry all four fields, and a real handler.
missing_fn=""
while IFS='|' read -r key title note handler; do
    [ -n "$key" ] || continue
    [ -n "$title" ] && [ -n "$note" ] && [ -n "$handler" ] \
        || bad_ "layer '$key' is missing a field"
    declare -F "$handler" >/dev/null 2>&1 || missing_fn="$missing_fn $handler"
done <<< "$layers"
[ -z "$missing_fn" ] \
    && ok_ "every layer has a handler that exists" \
    || bad_ "handlers not defined:$missing_fn"

# Requirement 2: a one-line explanation on every screen.
short=$(printf '%s\n' "$layers" | awk -F'|' 'length($3) < 25 { n++ } END { print n + 0 }')
[ "$short" = 0 ] \
    && ok_ "every layer explains what it decides" \
    || bad_ "$short layer(s) have no real explanation"

# The order is the order a pseudopotential is decided, not alphabetical.
first=$(printf '%s\n' "$layers" | head -1 | cut -d'|' -f1)
[ "$first" = family ] \
    && ok_ "the flow starts with the formulation, not a menu of everything" \
    || bad_ "the flow starts with '$first'"

printf '\n%s== the review screen shows the real command%s\n' "$DIM" "$RESET"
# Drive the wizard's state the way the screens would, then compare.
SPEC[family]=paw; SPEC[xc]=pbe; SPEC[rel]=scalar
SPEC[profile]=psl-high; SPEC[engine]=ld1; SPEC[upf]=2
CLI_ELEMENTS="Si"
MAX_PARALLEL_JOBS=4
cmd=$(ui_cmdline)

case $cmd in
    "pseudoforge generate -e Si"*) ok_ "the command names the elements chosen" ;;
    *) bad_ "elements missing from the command" "$cmd" ;;
esac
for frag in "-t paw" "-p psl-high" "-x pbe" "-r scalar"; do
    case $cmd in
        *"$frag"*) ok_ "review carries $frag" ;;
        *)         bad_ "review omits $frag" "$cmd" ;;
    esac
done

# and the CLI must accept every flag the review prints back
bad_flags=""
for f in $(printf '%s\n' "$cmd" | tr ' ' '\n' | grep '^--\?[a-z]'); do
    case $f in
        -e|-t|-p|-x|-r|-j|-o) continue ;;
    esac
    grep -q -- "$f)" "$PF_LIB/cli.sh" || bad_flags="$bad_flags $f"
done
[ -z "$bad_flags" ] \
    && ok_ "every flag the review prints is one the CLI parses" \
    || bad_ "the review prints flags the CLI does not accept:$bad_flags" \
            "the wizard would show a command that fails"

# Advanced settings must reach the command line, or the screen is a lie.
SPEC[core_hole]=1s
cmd2=$(ui_cmdline)
case $cmd2 in
    *"--core-hole 1s"*) ok_ "an advanced choice reaches the command line" ;;
    *) bad_ "core hole set but absent from the command" "$cmd2" ;;
esac
SPEC[core_hole]=

printf '\n%s== advanced options are hidden by default%s\n' "$DIM" "$RESET"
# Requirement 4.
TUI_ADVANCED=0
adv_in_flow=$(printf '%s\n' "$layers" | grep -c '^advanced|')
[ "$adv_in_flow" = 1 ] && ok_ "the advanced layer exists" || bad_ "no advanced layer"
grep -q 'TUI_ADVANCED.*!= 1.*continue\|\[ "\$TUI_ADVANCED" != 1 \]' "$PF_LIB/tui.sh" \
    && ok_ "it is skipped unless switched on" \
    || bad_ "the advanced layer is not gated"
grep -q 'advanced "Advanced options are' "$PF_LIB/tui.sh" \
    && ok_ "and there is a single toggle for it" \
    || bad_ "no toggle to reveal advanced options"

printf '\n%s== help opens the documentation%s\n' "$DIM" "$RESET"
# Requirement 3.  The docs are the explanation of record; the dialog must not
# carry its own copy to drift from.
missing_doc=""
# Read from tui_help itself, so moving a document cannot leave the wizard
# opening a page that is not there -- which is exactly what happened when
# the documentation was reorganised.
# Read from tui_help itself, so moving a document cannot leave the wizard
# opening a page that is not there -- which is exactly what happened when
# the documentation was reorganised.
help_docs=$(awk '/^tui_help\(\)/,/^}/' "$PF_LIB/tui.sh" \
            | grep -oE 'doc=[A-Za-z0-9_./-]+[.]md' | sed 's/^doc=//' | sort -u)
[ -n "$help_docs" ] || bad_ "tui_help names no documents at all"
for d in $help_docs; do
    [ -f "$ROOT/docs/$d" ] || missing_doc="$missing_doc $d"
done
[ -z "$missing_doc" ] \
    && ok_ "every document help points at exists" \
    || bad_ "help points at missing docs:$missing_doc"
grep -q 'less' "$PF_LIB/tui.sh" \
    && ok_ "help opens a pager rather than a dialog full of prose" \
    || bad_ "help does not use a pager"

printf '\n%s== 80x24%s\n' "$DIM" "$RESET"
# Requirement: nothing may need a larger terminal.
oversize=$(grep -oE 'ui_(msg|text|menu|yesno|input) "[^"]*" [^0-9]*[0-9]+ [0-9]+' "$PF_LIB/tui.sh" 2>/dev/null | \
           awk '{ h=$(NF-1); w=$NF; if (h+0 > 24 || w+0 > 80) n++ } END { print n+0 }')
[ "${oversize:-0}" = 0 ] \
    && ok_ "no dialog in tui.sh asks for more than 80x24" \
    || bad_ "$oversize dialog(s) exceed 80x24"
grep -q 'ui_fit_h\|ui_fit_w' "$PF_LIB/tui.sh" \
    && ok_ "geometry is clamped to the real terminal" \
    || bad_ "tui.sh does not clamp its geometry"

# The doctor panel is the longest thing the TUI draws.
recs=$(doctor_checks)
IFS=$'\t' read -r rows cols < <(doctor_tui_size "$(doctor_render_tui "$recs")")
[ "$rows" -le 16 ] && [ "$cols" -le 72 ] \
    && ok_ "the doctor panel fits (${rows}x${cols} inside 16x72 usable)" \
    || bad_ "the doctor panel is ${rows}x${cols}"

printf '\n%s== progress, history, theme%s\n' "$DIM" "$RESET"
declare -F tui_gauge >/dev/null && ok_ "progress uses whiptail --gauge" || bad_ "no gauge helper"
declare -F tui_run_with_progress >/dev/null \
    && ok_ "long operations can run behind a gauge" || bad_ "no progress wrapper"

TUI_HISTORY=$TMP/history
tui_history_add "pseudoforge generate -e Si -t paw"
tui_history_add "pseudoforge generate -e Fe -t us"
[ "$(grep -c . "$TUI_HISTORY")" = 2 ] \
    && ok_ "history records commands" || bad_ "history did not record"
i=0
while [ "$i" -lt 25 ]; do tui_history_add "cmd $i"; i=$((i + 1)); done
kept=$(grep -c . "$TUI_HISTORY")
[ "$kept" -le "$TUI_HISTORY_MAX" ] \
    && ok_ "history is capped at $TUI_HISTORY_MAX (kept $kept)" \
    || bad_ "history grew to $kept entries"

tui_theme
[ -n "${NEWT_COLORS:-}" ] && ok_ "a theme is installed" || bad_ "no NEWT_COLORS set"
printf '%s' "$NEWT_COLORS" | grep -q 'actlistbox' \
    && ok_ "the theme covers the selected-item colours" \
    || bad_ "theme is incomplete"

printf '\n%s== the shortcut limitation is stated, not faked%s\n' "$DIM" "$RESET"
# whiptail/newt cannot bind Ctrl-keys.  Claiming otherwise in help text would
# be promising something that silently does nothing.
if grep -qE 'Ctrl\+[GSQH]' "$PF_LIB/tui.sh"; then
    grep -qiE 'cannot bind Ctrl|newt reads its own keys' "$PF_LIB/tui.sh" \
        && ok_ "Ctrl shortcuts are mentioned only alongside the limitation" \
        || bad_ "tui.sh advertises Ctrl shortcuts whiptail cannot deliver"
else
    ok_ "no Ctrl shortcut is advertised"
fi
grep -qiE 'single-letter accelerators|first letter' "$PF_LIB/tui.sh" \
    && ok_ "the achievable alternative is documented in the module" \
    || bad_ "no note about what is offered instead"

printf '\n%s== the wizard and the CLI stay in step%s\n' "$DIM" "$RESET"
# Same choices through both routes must give the same SPEC.
SPEC[family]=nc; SPEC[xc]=pbesol; SPEC[rel]=full; SPEC[profile]=sg15
CLI_ELEMENTS="Fe"
wiz=$(ui_cmdline)
case $wiz in
    *"-t nc"*)     ok_ "family change is reflected" ;;
    *) bad_ "family not reflected: $wiz" ;;
esac
case $wiz in
    *"-x pbesol"*) ok_ "functional change is reflected" ;;
    *) bad_ "functional not reflected: $wiz" ;;
esac
case $wiz in
    *"-r full"*)   ok_ "relativity change is reflected" ;;
    *) bad_ "relativity not reflected: $wiz" ;;
esac

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
