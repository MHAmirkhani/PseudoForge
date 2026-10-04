#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Saved recipes.
#
# The property: **a recipe that is saved, reloaded and run again produces the
# same pseudopotentials.** Anything less makes a saved recipe a liability
# rather than a record -- a file that claims to describe a run and quietly
# describes a different one is worse than no file at all.
#
# Three things have to hold for that, and each is tested separately because
# each fails differently:
#
#   **The specification survives the file.** Every key goes out and comes back
#   with the same value. Writing this test found two real defects: `engine`
#   and `source` were never declared in spec_init, so the loader rejected the
#   very keys it had just written, and cli_check_spec assigned
#   `SPEC[engine]=${CLI_ENGINE:-}` unconditionally, which threw away a loaded
#   recipe's engine without a word.
#
#   **The table does not drift.** SPEC_FLAG maps specification keys onto the
#   flags that set them. A key added to SPEC and forgotten here would round-
#   trip through the file but vanish from the command line the review screen
#   shows -- so the check is that every key is accounted for somewhere, either
#   as a flag or as an explicit exception.
#
#   **A recipe cannot run commands.** Recipes are meant to be shared, so a
#   recipe from someone else is untrusted input. It is parsed, never sourced.
#
# The generation comparison needs ld1.x and is gated behind PF_SLOW_TESTS=1.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
for m in core sink config deps elements xc namelist profiles metadata formats gth sssp convert doctor params engines build recipe input_builder executor project run upf testing validate report cli; do
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
export RECIPE_DIR=$TMP/recipes

printf '\n%s== every specification key is accounted for%s\n' "$DIM" "$RESET"
# The anti-drift check.  A key nobody mapped is a key that silently disappears
# from the command line the review screen prints.
orphan=""
for k in $(printf '%s\n' "${!SPEC[@]}" | sort); do
    [ -n "${SPEC_FLAG[$k]:-}" ]        && continue
    [ -n "${SPEC_FLAG_BOOL[$k]:-}" ]   && continue
    [ -n "${SPEC_FLAG_CUSTOM[$k]:-}" ] && continue
    [ -n "${SPEC_DERIVED[$k]:-}" ]     && continue
    orphan="$orphan $k"
done
[ -z "$orphan" ] \
    && ok_ "all ${#SPEC[@]} specification keys map to a flag or a declared exception" \
    || bad_ "unmapped key(s):$orphan" \
            "add them to SPEC_FLAG, or to SPEC_DERIVED if a run computes them"

# and nothing is claimed twice, which would make the rendering order matter
dupe=""
for k in "${!SPEC_FLAG[@]}"; do
    [ -n "${SPEC_FLAG_BOOL[$k]:-}${SPEC_DERIVED[$k]:-}${SPEC_FLAG_CUSTOM[$k]:-}" ] && dupe="$dupe $k"
done
[ -z "$dupe" ] && ok_ "no key is in two tables" || bad_ "key(s) in two tables:$dupe"

printf '\n%s== every mapped flag is one the CLI parses%s\n' "$DIM" "$RESET"
unknown=""
for k in "${!SPEC_FLAG[@]}" ; do
    grep -qE -- "(^|[ |(])${SPEC_FLAG[$k]}[)|]" "$PF_LIB/cli.sh" || unknown="$unknown ${SPEC_FLAG[$k]}"
done
for k in "${!SPEC_FLAG_BOOL[@]}"; do
    grep -qE -- "(^|[ |(])${SPEC_FLAG_BOOL[$k]}[)|]" "$PF_LIB/cli.sh" || unknown="$unknown ${SPEC_FLAG_BOOL[$k]}"
done
[ -z "$unknown" ] \
    && ok_ "every flag in the table is accepted by cli_parse" \
    || bad_ "the table names flags the CLI rejects:$unknown" \
            "spec_cmdline would print a command that fails"

printf '\n%s== the specification survives a save and a load%s\n' "$DIM" "$RESET"
spec_init
SPEC[family]=us; SPEC[profile]=psl-low; SPEC[xc]=pbesol; SPEC[rel]=full
SPEC[rcut_scale]=1.1; SPEC[core_hole]=1s; SPEC[lloc]=2; SPEC[gipaw]=1
SPEC[config]='[Ne] 3s2 3p2'      # a value with spaces, the usual way this breaks
SPEC[engine]=ld1; SPEC[source]=local
CLI_ELEMENTS="Si O"
RUN_LD1_TESTS=0; AUTOFIX_MAX_ATTEMPTS=5

declare -A BEFORE=()
for k in "${!SPEC[@]}"; do BEFORE[$k]=${SPEC[$k]}; done
before_els=$(el_expand $CLI_ELEMENTS | tr '\n' ',' | sed 's/,$//')

f=$(rcp_save rt "a round-trip test") \
    && ok_ "rcp_save wrote $(basename "$f")" || bad_ "rcp_save failed"

# Wipe everything, the way a fresh process would start.
spec_init; CLI_ELEMENTS=""; RUN_LD1_TESTS=1; AUTOFIX_MAX_ATTEMPTS=2

if rcp_load rt; then
    ok_ "rcp_load accepted the file it had just written"
else
    bad_ "rcp_load rejected our own file"
fi

drift=""
for k in "${!BEFORE[@]}"; do
    [ "${SPEC[$k]:-}" = "${BEFORE[$k]}" ] || drift="$drift $k(${BEFORE[$k]}->${SPEC[$k]:-})"
done
[ -z "$drift" ] \
    && ok_ "every specification key came back unchanged" \
    || bad_ "value(s) changed across the round trip:$drift"

[ "$(el_expand $CLI_ELEMENTS | tr '\n' ',' | sed 's/,$//')" = "$before_els" ] \
    && ok_ "the element list came back unchanged ($before_els)" \
    || bad_ "elements became '$CLI_ELEMENTS', expected '$before_els'"
[ "${RUN_LD1_TESTS}" = 0 ] \
    && ok_ "a run option that changes the result came back too" \
    || bad_ "RUN_LD1_TESTS came back as $RUN_LD1_TESTS, not 0"
[ "${AUTOFIX_MAX_ATTEMPTS}" = 5 ] \
    && ok_ "the auto-fix budget came back" \
    || bad_ "AUTOFIX_MAX_ATTEMPTS came back as $AUTOFIX_MAX_ATTEMPTS"
[ "${SPEC[config]}" = '[Ne] 3s2 3p2' ] \
    && ok_ "a value containing spaces survived" \
    || bad_ "config came back as '${SPEC[config]}'"

printf '\n%s== the command line is stable and complete%s\n' "$DIM" "$RESET"
c1=$(spec_cmdline 2>/dev/null)
c2=$(spec_cmdline 2>/dev/null)
[ "$c1" = "$c2" ] \
    && ok_ "rendering the same specification twice gives the same string" \
    || bad_ "spec_cmdline is not deterministic"
missing=""
for frag in "-t us" "-p psl-low" "-x pbesol" "-r full"; do
    case $c1 in *"$frag"*) ;; *) missing="$missing $frag" ;; esac
done
[ -z "$missing" ] \
    && ok_ "the four identity flags are always printed" \
    || bad_ "identity flag(s) missing:$missing" "a command without them means 'whatever is configured'"
case $c1 in
    *"--core-hole 1s"*) ok_ "an override reaches the command line" ;;
    *) bad_ "core hole set but absent from the command" "$c1" ;;
esac
case $c1 in
    *"--no-test"*) ok_ "a run option that changes the result is printed" ;;
    *) bad_ "--no-test is in force but not printed" "$c1" ;;
esac

printf '\n%s== a recipe is data, not a script%s\n' "$DIM" "$RESET"
# Recipes are meant to be shared.  One arriving by email is untrusted input.
canary=$TMP/canary
cat > "$TMP/evil.recipe" <<EOF
pseudoforge.recipe=1
elements=Si
spec.family=paw
spec.config=\$(touch $canary)
spec.author=\`touch $canary\`
EOF
spec_init; CLI_ELEMENTS=""
rcp_load "$TMP/evil.recipe" >/dev/null 2>&1
[ ! -e "$canary" ] \
    && ok_ "a substitution in a recipe is not executed" \
    || bad_ "loading a recipe ran a command" "recipes must be parsed, never sourced"
[ "${SPEC[config]}" = '$(touch '"$canary"')' ] \
    && ok_ "it is kept as the literal text it is" \
    || bad_ "the value was transformed: '${SPEC[config]}'"
grep -q 'source\|^\s*\.\s' <(awk '/^rcp_load\(\)/,/^}/' "$PF_LIB/recipe.sh") \
    && bad_ "rcp_load sources the file" \
    || ok_ "rcp_load contains no sourcing of its input"

printf '\n%s== bad input is refused, not guessed at%s\n' "$DIM" "$RESET"
printf 'spec.family=paw\n' > "$TMP/nomagic.recipe"
rcp_load "$TMP/nomagic.recipe" >/dev/null 2>&1 \
    && bad_ "a file with no magic line was accepted" \
    || ok_ "a file that is not a recipe is refused"

printf 'pseudoforge.recipe=1\nspec.no_such_key=1\n' > "$TMP/unknown.recipe"
rcp_load "$TMP/unknown.recipe" >/dev/null 2>&1 \
    && bad_ "an unknown specification key was ignored" \
            "a silently dropped key generates something other than the recipe says" \
    || ok_ "an unknown specification key is refused"

printf 'pseudoforge.recipe=99\nspec.family=paw\n' > "$TMP/future.recipe"
rcp_load "$TMP/future.recipe" >/dev/null 2>&1 \
    && bad_ "a newer format version was accepted" \
    || ok_ "a recipe from a newer PseudoForge is refused, not half-read"

for n in '../escape' '/etc/passwd' '' 'has space'; do
    rcp_name_ok "$n" \
        && bad_ "the name '$n' was accepted" "recipe names become file names" \
        || ok_ "the name '$n' is refused"
done

printf '\n%s== the two senses of "recipe" cannot collide%s\n' "$DIM" "$RESET"
# `recipe <element>` prints a deck; `recipe save` saves a configuration.
clash=""
for sub in save load show list ls delete rm export import path; do
    el_canon "$sub" >/dev/null 2>&1 && clash="$clash $sub"
done
[ -z "$clash" ] \
    && ok_ "no subcommand name is an element symbol" \
    || bad_ "ambiguous:$clash" "'pseudoforge recipe $clash' would mean two things"
grep -q 'cmd_recipe_store' "$ROOT/pseudoforge" \
    && ok_ "the dispatch routes subcommands to the store" \
    || bad_ "the entry point does not know about the subcommands"

printf '\n%s== one implementation of the command line, not two%s\n' "$DIM" "$RESET"
# The review screen and `recipe load` must agree, which they cannot do if each
# builds the string itself.
awk '/^ui_cmdline\(\)/,/^}/' "$PF_LIB/ui.sh" | grep -q 'spec_cmdline' \
    && ok_ "ui_cmdline delegates to spec_cmdline" \
    || bad_ "ui.sh builds its own command line" "the two will drift"
n=$(grep -c 'pseudoforge generate -e' "$PF_LIB/ui.sh" "$PF_LIB/recipe.sh" 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')
[ "$n" -le 1 ] \
    && ok_ "only one place builds the generate command" \
    || bad_ "$n places build it"

printf '\n%s== export and import%s\n' "$DIM" "$RESET"
spec_init; SPEC[family]=paw; CLI_ELEMENTS="Si"
rcp_save shareme "" >/dev/null
src=$(rcp_path shareme)
cp "$src" "$TMP/out.recipe"
[ -s "$TMP/out.recipe" ] && ok_ "a recipe can be copied out as a plain file" \
                         || bad_ "export produced nothing"
spec_init; CLI_ELEMENTS=""
rcp_load "$TMP/out.recipe" >/dev/null 2>&1 \
    && ok_ "and loaded back from an arbitrary path" \
    || bad_ "a recipe exported to a file would not load"
[ "${SPEC[family]}" = paw ] \
    && ok_ "with its contents intact" \
    || bad_ "family came back as '${SPEC[family]}'"

printf '\n%s== an explicit flag overrides the recipe, wherever it sits%s\n' "$DIM" "$RESET"
spec_init; CLI_ELEMENTS="Fe Co Ni"; SPEC[family]=paw; SPEC[xc]=pbe
rcp_save ovr "" >/dev/null

# after the recipe
spec_init; CLI_ELEMENTS=""; CLI_ELEMENTS_FROM_RECIPE=
cli_parse --recipe ovr -x pbesol >/dev/null 2>&1
[ "${SPEC[xc]}" = pbesol ] \
    && ok_ "a flag after --recipe wins" \
    || bad_ "xc came out as '${SPEC[xc]}', expected pbesol"

# before the recipe -- position must not change meaning
spec_init; CLI_ELEMENTS=""; CLI_ELEMENTS_FROM_RECIPE=
cli_parse -x pbesol --recipe ovr >/dev/null 2>&1
[ "${SPEC[xc]}" = pbesol ] \
    && ok_ "a flag before --recipe wins too" \
    || bad_ "order changed the outcome: xc = '${SPEC[xc]}'"

# elements: an explicit -e replaces the recipe's list rather than adding to it
spec_init; CLI_ELEMENTS=""; CLI_ELEMENTS_FROM_RECIPE=
cli_parse --recipe ovr -e Fe >/dev/null 2>&1
got=$(el_expand $CLI_ELEMENTS | tr '\n' ',' | sed 's/,$//')
[ "$got" = Fe ] \
    && ok_ "-e replaces the recipe's element list" \
    || bad_ "-e Fe gave '$got'" "appending would generate elements nobody asked for"

# but several -e on one line still accumulate, as they always have
spec_init; CLI_ELEMENTS=""; CLI_ELEMENTS_FROM_RECIPE=
cli_parse -e Si -e O >/dev/null 2>&1
got=$(el_expand $CLI_ELEMENTS | tr '\n' ',' | sed 's/,$//')
[ "$got" = "O,Si" ] \
    && ok_ "several -e without a recipe still accumulate ($got)" \
    || bad_ "-e Si -e O gave '$got'"

# and with no -e at all, the recipe's list stands
spec_init; CLI_ELEMENTS=""; CLI_ELEMENTS_FROM_RECIPE=
cli_parse --recipe ovr >/dev/null 2>&1
got=$(el_expand $CLI_ELEMENTS | tr '\n' ',' | sed 's/,$//')
[ "$got" = "Fe,Co,Ni" ] \
    && ok_ "with no -e the recipe's list stands ($got)" \
    || bad_ "the recipe's elements came back as '$got'"


printf '\n%s== the wizard and the CLI share one store%s\n' "$DIM" "$RESET"
# The review screen has offered "save these choices as a recipe" for a while,
# and told the user to reload it with `pseudoforge generate --recipe <name>`.
# It wrote a bare command line into a directory of its own, in a format that
# loader cannot read -- and the flag did not exist at all. Two interfaces, two
# formats, and one promise that could not be kept.
awk '/^tui_save_recipe\(\)/,/^}/' "$PF_LIB/tui.sh" | grep -q 'rcp_save' \
    && ok_ "the wizard saves through rcp_save" \
    || bad_ "the wizard writes its own recipe format" \
            "a recipe saved in the wizard would not load in the CLI"
awk '/^tui_save_recipe\(\)/,/^}/' "$PF_LIB/tui.sh" | grep -q 'PF_RECIPE_DIR' \
    && bad_ "the wizard still uses a directory variable of its own" \
    || ok_ "both interfaces resolve the directory the same way"
grep -q 'tui_load_recipe' "$PF_LIB/tui.sh" \
    && ok_ "the wizard can load one back" \
    || bad_ "the wizard can save recipes it cannot open"
awk '/^tui_main\(\)/,/^}/' "$PF_LIB/tui.sh" | grep -q 'tui_load_recipe' \
    && ok_ "and it is reachable from the main menu" \
    || bad_ "tui_load_recipe exists but nothing calls it"
grep -q -- '--recipe)' "$PF_LIB/cli.sh" \
    && ok_ "the --recipe flag the wizard promises exists" \
    || bad_ "the wizard tells users to run a flag the CLI does not accept"

printf '\n%s== saved, reloaded, and it generates the same files%s\n' "$DIM" "$RESET"
if [ "${PF_SLOW_TESTS:-0}" != 1 ]; then
    skip_ "generation gated behind PF_SLOW_TESTS=1 (measured: 4 files byte-identical, decks identical)"
else
    [ -f "${PF_RC:-$HOME/.pseudoforgerc}" ] && . "${PF_RC:-$HOME/.pseudoforgerc}"
fi
if [ "${PF_SLOW_TESTS:-0}" = 1 ] \
   && [ ! -x "${LD1_BIN:-}" ] && ! command -v "${LD1_BIN:-ld1.x}" >/dev/null 2>&1; then
    skip_ "ld1.x not available (LD1_BIN=${LD1_BIN:-unset})"
elif [ "${PF_SLOW_TESTS:-0}" = 1 ]; then
    export OMP_NUM_THREADS=1
    ( cd "$ROOT" && RECIPE_DIR=$RECIPE_DIR ./pseudoforge recipe save live \
          -e Si,O -t paw -p psl-high -x pbe -r scalar --rcut-scale 1.05 >/dev/null 2>&1 )
    ( cd "$ROOT" && ./pseudoforge generate -e Si,O -t paw -p psl-high -x pbe \
          -r scalar --rcut-scale 1.05 -o "$TMP/a" >/dev/null 2>&1 )
    ( cd "$ROOT" && RECIPE_DIR=$RECIPE_DIR ./pseudoforge generate --recipe live \
          -o "$TMP/b" >/dev/null 2>&1 )

    na=$(ls "$TMP/a"/pseudos/*.UPF 2>/dev/null | wc -l)
    nb=$(ls "$TMP/b"/pseudos/*.UPF 2>/dev/null | wc -l)
    [ "$na" -gt 0 ] && [ "$na" = "$nb" ] \
        && ok_ "both runs produced $na file(s)" \
        || bad_ "flags produced $na files, the recipe produced $nb"

    differing=""
    for f in "$TMP"/a/pseudos/*.UPF; do
        b=$(basename "$f")
        [ -f "$TMP/b/pseudos/$b" ] || { differing="$differing $b(missing)"; continue; }
        cmp -s <(grep -v 'date=' "$f") <(grep -v 'date=' "$TMP/b/pseudos/$b") \
            || differing="$differing $b"
    done
    [ -z "$differing" ] \
        && ok_ "every pseudopotential is identical to the one the flags made" \
        || bad_ "the reloaded recipe generated something else:$differing"

    diff -r "$TMP/a/inputs" "$TMP/b/inputs" >/dev/null 2>&1 \
        && ok_ "the ld1.x decks are identical too" \
        || bad_ "the decks differ" "$(diff -r "$TMP/a/inputs" "$TMP/b/inputs" | head -4)"
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
