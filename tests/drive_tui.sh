#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Drive pseudoforge's menus with the scripted whiptail stand-in.
#
# The entry point gates the TUI behind a real terminal, which a test harness
# does not have, so this sources the library directly and calls tui_main.
#
# tui_main is what `pseudoforge tui` runs, and what `pseudoforge wizard`
# runs when whiptail is available.  One flow, one set of nine layers, one
# source of truth.
#
#   tests/drive_tui.sh <pseudoforge-root>
#
# Answers come from MOCK_WT_ANSWERS, one per line; the dialogs that were shown
# are appended to MOCK_WT_LOG.
# ---------------------------------------------------------------------------
set -uo pipefail

ROOT=${1:?usage: drive_tui.sh <pseudoforge-root>}
PF_ROOT=$ROOT
PF_LIB=$ROOT/lib
PF_DATA=$ROOT/data
export PF_ROOT PF_LIB PF_DATA

for m in core sink config deps elements xc namelist profiles metadata formats gth sssp convert doctor params engines build recipe input_builder executor fetch project run upf testing validate report cli ui tui wizard; do
    # shellcheck disable=SC1090
    . "$PF_LIB/$m.sh" || { echo "cannot load $m.sh" >&2; exit 1; }
done

pf_config_load
pf_elements_load
pf_xc_load
pf_profiles_load
pf_engines_load
pf_metadata_load
spec_init

# nothing here has a terminal; a prompt that waits for Enter must fail
# rather than hang the suite
exec < /dev/null

tui_main
