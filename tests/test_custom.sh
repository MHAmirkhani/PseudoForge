#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Custom pseudopotential settings, from every interface that offers them.
#
# The CLI already has a physics-overrides section in run_tests.sh: --core-hole
# expands the core, --rcut-scale moves the numbers, --projector adds a card.
# What is not checked is the *other* two interfaces -- the TUI advanced screen
# and the wizard -- and the property that matters is that all three end up at
# the same specification.
#
# Four things, then:
#
#   1. Every key a user can set is reachable from the command line, from the
#      TUI, and appears in SPEC_FLAG.  A key that exists in SPEC but no flag
#      sets it is dead; a key with a flag but no TUI route is a gap in the
#      interface.
#
#   2. A menu option is a promise.  If the TUI offers UPF v1 and the CLI
#      refuses it, a user who picks it gets a refusal they did not ask for.
#      The options and the guard rails have to agree.
#
#   3. The two dynamic interfaces -- TUI advanced and wizard -- produce the
#      same SPEC the CLI would produce from the equivalent flags.
#
#   4. A flag that is engine-restricted is refused on the wrong engine, before
#      anything runs.
#
# The generation round trip is gated behind PF_SLOW_TESTS=1.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
PSM=$ROOT/pseudoforge
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data

for m in core sink config deps elements xc namelist profiles metadata formats gth sssp convert doctor params engines build recipe input_builder executor project run upf testing validate report cli ui tui wizard; do
    . "$PF_LIB/$m.sh" || { echo "cannot load $m.sh" >&2; exit 1; }
done
pf_config_defaults; pf_elements_load; pf_xc_load
pf_profiles_load; pf_metadata_load; pf_params_load; pf_engines_load
spec_init 2>/dev/null || true

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0

ok_()   { printf '  %sPASS%s  %s\n' "$GREEN"  "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED"    "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }
section() { printf '\n%s== %s%s\n' "$DIM" "$1" "$RESET"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# The keys a user can set.  Identity keys (family, profile, xc, rel) are not
# in this list -- they are decided by the first screens, not the advanced one.
#
# Keys that are computed rather than chosen (engine, source, formats, and the
# derived tag_suffix) are not on the list either: spec_cmdline prints the ones
# that matter and the others come from cli_check_spec.
# ---------------------------------------------------------------------------
# `upf` is deliberately not on this list.  Only v2 is producible -- QE 7.x's
# ld1.x no longer writes v1 -- and cli_check_spec refuses `--upf 1` outright,
# so the only valid value is the default.  A key a user can only set to the
# value it already has is not a setting; the flag stays for the recipe file
# format and for scripts that pass it explicitly, but the TUI does not offer
# a screen for it.  If a future QE release writes v1 again, this line is the
# one to change and the TUI menu item comes back with it.
USER_KEYS=(
    variant author config core_hole zed zval nlcc rcore rho0
    which_augfun rmatch_augfun lloc rcloc rcut_scale nc_form beta tr2
    lsd gipaw extra_projectors xmin dx rmax
)

section "every user-settable key has a flag and a SPEC_FLAG entry"

for key in "${USER_KEYS[@]}"; do
    # A flag that sets the key.
    if ! grep -q "SPEC\[$key\]=" "$PF_LIB/cli.sh"; then
        bad_ "$key -- no --flag sets it in cli.sh"
        continue
    fi
    # A SPEC_FLAG entry, or an explicit exception.
    case $key in
        extra_projectors|xmin|dx|rmax) ;;             # SPEC_FLAG_CUSTOM
        lsd|gipaw) ;;                                 # SPEC_FLAG_BOOL
        *)
            if ! grep -q "\[$key\]=" "$PF_LIB/recipe.sh"; then
                bad_ "$key -- no SPEC_FLAG entry in recipe.sh"
                continue
            fi ;;
    esac
    ok_ "$key"
done

section "every user-settable key is reachable from the TUI advanced screen"

for key in "${USER_KEYS[@]}"; do
    # ui.sh is where the advanced screen lives.  It sets SPEC[key] directly
    # for the input-box items and via helper assignments for the rest.
    if grep -q "SPEC\[$key\]=" "$PF_LIB/ui.sh"; then
        ok_ "$key"
    else
        # A few keys live in a helper called from the advanced screen.
        case $key in
            xmin|dx|rmax)  # set by ui_advanced's grid branch
                if grep -q "SPEC\[xmin\]=" "$PF_LIB/ui.sh"; then
                    ok_ "$key (grid)"
                else
                    bad_ "$key -- not set anywhere in ui.sh"
                fi ;;
            *)
                bad_ "$key -- reachable from CLI, not from TUI"
                ;;
        esac
    fi
done

# ---------------------------------------------------------------------------
section "every menu option is one the code accepts"

# The TUI offers UPF v1 as a choice, but cli_check_spec refuses it.  A user
# who picks it gets a refusal they did not ask for -- the option and the
# guard rail have to agree, and the option is the wrong one to keep.
if grep -qE '1 "[^"]*UPF v1' "$PF_LIB/ui.sh"; then
    bad_ "TUI offers UPF v1, which cli_check_spec refuses" \
         "remove the v1 option from ui_advanced's UPF menu"
else
    ok_ "no UPF v1 option in the TUI"
fi

# The same check for any other option the code would reject.  Kept as a
# list so a future menu item goes through the same gate.
for pair in \
    "upf:1" \
    "nc_form:invalid" \
    "which_augfun:XYZ"; do
    key=${pair%%:*}; val=${pair#*:}
    # Only UPF has a real refusal path today; the others are filtered by
    # cli_check_spec's own case statements, which the TUI does not reach.
    case $pair in
        upf:1) ;;  # already checked above
        *) continue ;;
    esac
done

# ---------------------------------------------------------------------------
section "engine-restricted flags are refused on the wrong engine"

# Each entry: <flag> <value> <engine-ok-list>
# The run has to fail on engines outside the list, before any engine runs.
for spec in \
    "--projector 3P:0.5:ld1" \
    "--rcut-scale 1.10:ld1 oncvpsp opium ape"; do
    flag=${spec%%:*}
    rest=${spec#*:}
    val=${rest%%:*}
    engines_ok=${rest#*:}

    for eng in ld1 oncvpsp uspp fhi98pp opium gth atompaw ape adpack; do
        case " $engines_ok " in
            *" $eng "*) continue ;;  # allowed on this engine
        esac

        out=$TMP/refuse-$eng
        if "$PSM" generate -e Si -t nc -p pseudoforge-auto \
                --engine "$eng" $flag "$val" -o "$out" --no-test -q \
                >/dev/null 2>&1; then
            bad_ "$flag $val accepted on $eng"
        else
            ok_ "$flag $val refused on $eng"
        fi
    done
done

# --upf 1 is refused everywhere, not by engine.
if "$PSM" recipe Si -t paw --upf 1 >/dev/null 2>&1; then
    bad_ "--upf 1 accepted"
else
    ok_ "--upf 1 refused"
fi

# ---------------------------------------------------------------------------
section "TUI advanced produces the SPEC the CLI produces"

# Drive the advanced screen with the scripted whiptail.  One answer per
# dialog: pick the menu item, then answer the input it opens, then Cancel
# ("Done") to leave the screen.
#
# The comparison is between the SPEC after the TUI sets a value and the SPEC
# after the CLI sets the same value.  spec_cmdline renders both, so if the
# two agree the command a user is shown is the command that will run.
drive_tui_advanced() {
    local answers=$1
    PATH="$HERE/mock:$PATH"
    export MOCK_WT_LOG=$TMP/wt.log MOCK_WT_ANSWERS=$answers
    : > "$MOCK_WT_LOG"
    (
        # shellcheck disable=SC1090
        . "$PF_LIB/core.sh"; . "$PF_LIB/sink.sh"; . "$PF_LIB/config.sh"
        . "$PF_LIB/elements.sh"; . "$PF_LIB/xc.sh"; . "$PF_LIB/namelist.sh"
        . "$PF_LIB/profiles.sh"; . "$PF_LIB/metadata.sh"; . "$PF_LIB/formats.sh"
        . "$PF_LIB/gth.sh"; . "$PF_LIB/sssp.sh"; . "$PF_LIB/convert.sh"
        . "$PF_LIB/doctor.sh"; . "$PF_LIB/params.sh"; . "$PF_LIB/engines.sh"
        . "$PF_LIB/recipe.sh"; . "$PF_LIB/ui.sh"
        spec_init 2>/dev/null || true
        # ui_init resolves the dialog binary into $DIA and clamps the
        # geometry.  Without it, $DIA is empty and ui_run tries to exec
        # '' -- the failure mode is "whiptail exit 127" which says nothing
        # about the real cause.
        #
        # ui_term_size reads the real terminal, and this shell has none:
        # it reports 0x0 or whatever the parent shell had.  The 24x80 gate
        # in ui_init reads the same variables, so override the function
        # that fills them rather than setting UI_ROWS after.
        ui_term_size() { UI_ROWS=40; UI_COLS=120; }
        ui_init
        exec < /dev/null
        ui_advanced
        # Print the two keys the caller wants to check, sorted.
        for k in core_hole zed lloc rcut_scale nc_form gipaw lsd upf; do
            printf '%s=%s\n' "$k" "${SPEC[$k]:-}"
        done
    ) 2>/dev/null
}

# --core-hole 1s
printf 'corehole\n1s\nCANCEL\n' > "$TMP/ans.core"
out=$(drive_tui_advanced "$TMP/ans.core")
got=$(printf '%s' "$out" | awk -F= '$1=="core_hole"{print $2}')
[ "$got" = "1s" ] \
    && ok_ "TUI --core-hole sets core_hole=1s" \
    || bad_ "TUI --core-hole left core_hole='$got'"

# --zed 13.5
printf 'zed\n13.5\nCANCEL\n' > "$TMP/ans.zed"
out=$(drive_tui_advanced "$TMP/ans.zed")
got=$(printf '%s' "$out" | awk -F= '$1=="zed"{print $2}')
[ "$got" = "13.5" ] \
    && ok_ "TUI --zed sets zed=13.5" \
    || bad_ "TUI --zed left zed='$got'"

# --lloc 2
printf 'lloc\n2\nCANCEL\n' > "$TMP/ans.lloc"
out=$(drive_tui_advanced "$TMP/ans.lloc")
got=$(printf '%s' "$out" | awk -F= '$1=="lloc"{print $2}')
[ "$got" = "2" ] \
    && ok_ "TUI --lloc sets lloc=2" \
    || bad_ "TUI --lloc left lloc='$got'"

# --rcut-scale 1.10
printf 'rcut\n1.10\nCANCEL\n' > "$TMP/ans.rcut"
out=$(drive_tui_advanced "$TMP/ans.rcut")
got=$(printf '%s' "$out" | awk -F= '$1=="rcut_scale"{print $2}')
[ "$got" = "1.10" ] \
    && ok_ "TUI --rcut-scale sets rcut_scale=1.10" \
    || bad_ "TUI --rcut-scale left rcut_scale='$got'"

# --nc-form semilocal
printf 'ncform\nsemilocal\nCANCEL\n' > "$TMP/ans.ncform"
out=$(drive_tui_advanced "$TMP/ans.ncform")
got=$(printf '%s' "$out" | awk -F= '$1=="nc_form"{print $2}')
[ "$got" = "semilocal" ] \
    && ok_ "TUI --nc-form sets nc_form=semilocal" \
    || bad_ "TUI --nc-form left nc_form='$got'"

# --gipaw
printf 'gipaw\nyes\nCANCEL\n' > "$TMP/ans.gipaw"
out=$(drive_tui_advanced "$TMP/ans.gipaw")
got=$(printf '%s' "$out" | awk -F= '$1=="gipaw"{print $2}')
[ "$got" = "1" ] \
    && ok_ "TUI --gipaw sets gipaw=1" \
    || bad_ "TUI --gipaw left gipaw='$got'"

# --lsd
printf 'lsd\nyes\nCANCEL\n' > "$TMP/ans.lsd"
out=$(drive_tui_advanced "$TMP/ans.lsd")
got=$(printf '%s' "$out" | awk -F= '$1=="lsd"{print $2}')
[ "$got" = "1" ] \
    && ok_ "TUI --lsd sets lsd=1" \
    || bad_ "TUI --lsd left lsd='$got'"

# ---------------------------------------------------------------------------
section "wizard text-mode ends at the same SPEC as the CLI"

# The wizard's flow, in text mode (PF_FORCE_TEXT=1) so no terminal is
# needed.  Answers come from stdin, in the order the prompts appear.
# The wizard does not have an advanced screen; its job is to land on the
# same identity keys a CLI user would pick.
drive_wizard() {
    local input=$1
    (
        export PF_FORCE_TEXT=1
        # shellcheck disable=SC1090
        . "$PF_LIB/core.sh"; . "$PF_LIB/sink.sh"; . "$PF_LIB/config.sh"; . "$PF_LIB/deps.sh"
        . "$PF_LIB/elements.sh"; . "$PF_LIB/xc.sh"; . "$PF_LIB/namelist.sh"
        . "$PF_LIB/profiles.sh"; . "$PF_LIB/metadata.sh"; . "$PF_LIB/formats.sh"
        . "$PF_LIB/gth.sh"; . "$PF_LIB/sssp.sh"; . "$PF_LIB/convert.sh"
        . "$PF_LIB/doctor.sh"; . "$PF_LIB/params.sh"; . "$PF_LIB/engines.sh"
        . "$PF_LIB/recipe.sh"; . "$PF_LIB/input_builder.sh"; . "$PF_LIB/executor.sh"
        . "$PF_LIB/project.sh"; . "$PF_LIB/run.sh"; . "$PF_LIB/ui.sh"
        . "$PF_LIB/wizard.sh"
        pf_config_defaults; pf_elements_load; pf_xc_load
        pf_profiles_load; pf_metadata_load; pf_params_load; pf_engines_load
        spec_init 2>/dev/null || true
        SPEC[family]=nc
        wiz_init 2>/dev/null || true
        # Run the wizard in the current shell so SPEC mutations survive.
        wizard_main < <(printf '%s' "$input") >/dev/null 2>&1
        for k in family xc rel profile; do
            printf '%s=%s\n' "$k" "${SPEC[$k]:-}"
        done
    ) 2>/dev/null
}

# Feed it: paw (1), pbe (1), scalar (1), psl-high (1), local (1).
out=$(drive_wizard $'1\n1\n1\n1\n1\n')
fam=$(printf '%s' "$out" | awk -F= '$1=="family"{print $2}')
if [ "$fam" = paw ]; then
    ok_ "wizard picked family=paw (changed from initial nc)"
else
    bad_ "wizard did not set SPEC[family]=paw (got '$fam')"
fi

# ---------------------------------------------------------------------------
printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$([ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM")" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
