#!/usr/bin/env bash
# tests/test_repair.sh -- test defect taxonomy and automated repair subsystem
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PF="$ROOT/pseudoforge"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

check() {
    local label=$1; shift
    if "$@"; then
        printf 'PASS  %s\n' "$label"
        pass=$((pass + 1))
    else
        printf 'FAIL  %s\n' "$label"
        fail=$((fail + 1))
    fi
}

# 1. Taxonomy file exists and has expected header and entries
check "taxonomy file exists" [ -f "$ROOT/data/defects/taxonomy.tsv" ]
check "taxonomy has at least 8 defects" [ "$(grep -cv '^#' "$ROOT/data/defects/taxonomy.tsv")" -ge 8 ]

# 2. Setup mock fixture projects
MOCK_APE="$TMP/mock_ape"
mkdir -p "$MOCK_APE/reports" "$MOCK_APE/inputs" "$MOCK_APE/pseudos"
cat > "$MOCK_APE/PROVENANCE.txt" <<'EOF'
tool.name=PseudoForge
tool.version=1.4.0
engine.id=ape
engine.label=APE
profile=pseudoforge-auto
family=nc
functional=pbe
relativity=scalar
source=local
EOF
cat > "$MOCK_APE/reports/summary.txt" <<'EOF'
# element	family	status	message
Si	nc	ok-warn	APE reported bound ghost state in s channel
EOF
cat > "$MOCK_APE/inputs/Si.inp.ape" <<'EOF'
# APE input
local_channel = 1
EOF
cat > "$MOCK_APE/pseudos/Si.pbe-ape.UPF" <<'EOF'
<UPF version="2.0.1">
<PP_HEADER>
element="Si"
</PP_HEADER>
</UPF>
EOF

# 3. Test repair --help
check "repair --help exits 0" bash -c "'$PF' repair --help >/dev/null"

# 4. Test repair --dry-run produces no filesystem changes
files_before=$(find "$MOCK_APE" | sort)
dry_out=$("$PF" repair "$MOCK_APE" --dry-run)
check "repair --dry-run detects defect" grep -q "ape-si-ghost" <<< "$dry_out"
files_after=$(find "$MOCK_APE" | sort)
check "repair --dry-run leaves filesystem untouched" [ "$files_before" = "$files_after" ]

# 5. Test executing repair creates distinct directory and preserves original
"$PF" repair "$MOCK_APE" --strategy single_engine_repair >/dev/null
check "repair directory created" [ -d "$MOCK_APE/repair/ape-si-ghost" ]
check "original UPF preserved" [ -f "$MOCK_APE/pseudos/Si.pbe-ape.UPF" ]

# Check repair report
repair_report=$(find "$MOCK_APE/repair/ape-si-ghost" -name "repair-report.json" | head -1)
check "repair-report.json exists" [ -f "$repair_report" ]
check "repair report contains defect_id" grep -q '"defect_id": "ape-si-ghost"' "$repair_report"
check "repair report contains outcome" grep -q '"outcome": "improved"' "$repair_report"
check "project repairs registry updated" [ -f "$MOCK_APE/reports/repairs.json" ]

# 6. Test USPP QFCOEF concatenation defect fixture
MOCK_USPP="$TMP/mock_uspp"
mkdir -p "$MOCK_USPP/pseudos"
cat > "$MOCK_USPP/PROVENANCE.txt" <<'EOF'
engine.id=uspp
family=us
EOF
cat > "$MOCK_USPP/pseudos/Si.pbe-gbrv.UPF" <<'EOF'
<UPF version="2.0.1">
<PP_QFCOEF>
 1.234567891.23456789
</PP_QFCOEF>
</UPF>
EOF

uspp_out=$("$PF" repair "$MOCK_USPP" --dry-run)
check "uspp qfcoef defect detected" grep -q "uspp-qfcoef-concatenation" <<< "$uspp_out"
"$PF" repair "$MOCK_USPP" --strategy single_engine_repair >/dev/null
repaired_upf=$(find "$MOCK_USPP/repair/uspp-qfcoef-concatenation" -name "Si.pbe-gbrv.UPF" | head -1)
check "repaired USPP UPF created" [ -f "$repaired_upf" ]
check "qfcoef concatenation repaired with delimiters" grep -q "1.23456789  1.23456789" "$repaired_upf"

# 7. Test summary report schema integration with repairs
# Mock a project state and run report command
cat > "$MOCK_APE/state.tsv" <<'EOF'
Si	nc	pseudoforge-auto	pbe	scalar	-	Si.pbe-ape.UPF	ok	1	10	repaired
EOF
SPEC_engine=ape SPEC_profile=pseudoforge-auto SPEC_family=nc SPEC_xc=pbe SPEC_rel=scalar SPEC_upf=2 "$PF" report "$MOCK_APE" >/dev/null
check "summary.json contains repairs array" grep -q '"repairs": \[' "$MOCK_APE/reports/summary.json"

# 8. Test repair where defect persists records inconclusive
MOCK_FAIL="$TMP/mock_fail"
mkdir -p "$MOCK_FAIL/pseudos"
cat > "$MOCK_FAIL/PROVENANCE.txt" <<'EOF'
engine.id=uspp
family=us
EOF
cat > "$MOCK_FAIL/pseudos/bad.UPF" <<'EOF'
<UPF version="2.0.1">
CONCATENATED_QFCOEF
</UPF>
EOF
"$PF" repair "$MOCK_FAIL" --strategy single_engine_repair >/dev/null
fail_report=$(find "$MOCK_FAIL/repair/uspp-qfcoef-concatenation" -name "repair-report.json" | head -1)
check "repair-report.json exists for persisting defect" [ -f "$fail_report" ]
check "persisting defect records inconclusive outcome" grep -q '"outcome": "inconclusive"' "$fail_report"

# 9. Test cross-engine repair (APE Si using ONCVPSP donor)
MOCK_CROSS="$TMP/mock_cross"
mkdir -p "$MOCK_CROSS/pseudos" "$MOCK_CROSS/inputs"
cat > "$MOCK_CROSS/PROVENANCE.txt" <<'EOF'
engine.id=ape
family=nc
EOF
cat > "$MOCK_CROSS/inputs/Si.inp.ape" <<'EOF'
Title = "Si"
CalculationMode = ae + pp
local_channel = 1
EOF
cat > "$MOCK_CROSS/pseudos/Si.pbe-ape.UPF" <<'EOF'
<UPF version="2.0.1">
<!-- Unrepaired APE with ghost in s channel -->
</UPF>
EOF

"$PF" repair "$MOCK_CROSS" --strategy cross_engine_repair --donor-engine oncvpsp >/dev/null
cross_dir=$(find "$MOCK_CROSS/repair/ape-si-ghost" -type d -name "cross-oncvpsp-*" | head -1)
check "cross-engine repair directory created" [ -d "$cross_dir" ]
cross_report="$cross_dir/repair-report.json"
check "cross-engine repair report exists" [ -f "$cross_report" ]
check "cross-engine strategy recorded" grep -q '"strategy_applied": "cross_engine_repair"' "$cross_report"
check "donor engine recorded" grep -q '"donor_engine": "oncvpsp"' "$cross_report"
check "cross-engine outcome improved" grep -q '"outcome": "improved"' "$cross_report"
check "cross-repaired UPF created" [ -f "$cross_dir/pseudos/Si.pbe-ape.UPF" ]
check "translated APE input has LLocal=0" grep -q "LLocal = 0" "$cross_dir/inputs/Si.inp.ape"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
