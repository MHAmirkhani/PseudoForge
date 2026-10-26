#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test_advise.sh -- test suite for the advisory system
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data

GREEN=$'\033[32m'; RED=$'\033[31m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  SKIP  %s\n' "$1"; skip=$((skip + 1)); }

# ---------------------------------------------------------------------------
# 1. Knowledge Base TSV checks
# ---------------------------------------------------------------------------
check_tsv() {
    local f=$1 expected_cols=$2 expected_rows=$3
    [ -f "$f" ] || { bad_ "$f exists" "file missing"; return; }
    ok_ "$f exists"

    local rows
    rows=$(awk 'END {print NR}' "$f")
    local data_rows=$((rows - 1))
    if [ "$data_rows" -eq "$expected_rows" ]; then
        ok_ "$f row count ($data_rows)"
    else
        bad_ "$f row count" "got $data_rows, expected $expected_rows"
    fi

    local col_err
    col_err=$(awk -F'\t' -v cols="$expected_cols" '
        NR > 1 && NF != cols { print "line " NR ": NF=" NF " expected " cols }
    ' "$f")
    if [ -z "$col_err" ]; then
        ok_ "$f column count ($expected_cols)"
    else
        bad_ "$f column count" "$col_err"
    fi

    local empty_err
    empty_err=$(awk -F'\t' '
        NR > 1 {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[[:space:]]*$/) {
                    print "line " NR " col " i " is empty"
                }
            }
        }
    ' "$f")
    if [ -z "$empty_err" ]; then
        ok_ "$f has no empty fields"
    else
        bad_ "$f has no empty fields" "$empty_err"
    fi
}

check_tsv "$PF_DATA/advice/calculations.tsv" 6 12
check_tsv "$PF_DATA/advice/calculation-material.tsv" 5 8
check_tsv "$PF_DATA/advice/element-notes.tsv" 2 6

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
