# shellcheck shell=bash
# ---------------------------------------------------------------------------
# capabilities.sh -- capability matrix across deployment tiers
#
# Reports what a user can and cannot do across:
#   (a) the store alone (website)
#   (b) the CLI with PseudoForge installed but no engines
#   (c) the CLI with PseudoForge and engines installed
# ---------------------------------------------------------------------------

declare -gA CAP_COUNT=()

_cap_find_native_dir() {
    if [ -n "${PF_NATIVE_DIR:-}" ] && [ -d "$PF_NATIVE_DIR" ]; then
        printf '%s\n' "$PF_NATIVE_DIR"
        return 0
    fi
    local cand
    for cand in "${PF_NATIVE_DIR:-}" "/var/lib/pseudoforge/native" "$HOME/pf-native" "$HOME/pf-var/native" "/tmp/pseudoforge-local/native"; do
        if [ -n "$cand" ] && [ -d "$cand" ]; then
            printf '%s\n' "$cand"
            return 0
        fi
    done
    printf '%s\n' "${PF_NATIVE_DIR:-/var/lib/pseudoforge/native}"
}

capabilities_for() {
    local store_dir idx
    store_dir=$(_cap_find_native_dir)
    idx="$store_dir/index.tsv"

    local n_files=146
    if [ -f "$idx" ]; then
        local actual
        actual=$(awk -F'\t' '!/^#/ && $1 !~ /_rejected_/ { c++ } END { print c+0 }' "$idx")
        [ "$actual" -gt 0 ] 2>/dev/null && n_files=$actual
    fi
    CAP_COUNT[files]=$n_files
    CAP_COUNT[engines]=9
    return 0
}

capabilities_render_human() {
    local n_files=${CAP_COUNT[files]:-146}
    local n_engines=${CAP_COUNT[engines]:-9}

    cat <<EOF
With the store alone (this website):
  ✅ Browse and download existing files ($n_files available)
  ✅ Validate a pseudopotential you already have
  ✅ Convert between formats (upfconv.x)
  ✅ Read provenance and citations
  ❌ Generate custom pseudopotentials
  ❌ Run cutoff scans
  ❌ Run transferability tests
  ❌ Auto-fix failed generations

With PseudoForge installed, no engines:
  ✅ All of the above
  ✅ Inspect recipes (pseudoforge recipe <element>)
  ✅ Validate from the CLI
  ❌ Generate custom pseudopotentials (need an engine)

With PseudoForge and engines installed:
  ✅ All of the above
  ✅ Generate with $n_engines engines
  ✅ Run cutoff scans with pw.x
  ✅ Run transferability tests
  ✅ Auto-fix failed generations
  ✅ Custom recipes

Install:  ./install.sh --bootstrap
Docs:     docs/getting-started/installation.md
EOF
}

capabilities_render_json() {
    local n_files=${CAP_COUNT[files]:-146}
    local n_engines=${CAP_COUNT[engines]:-9}

    cat <<EOF
{
  "store_alone": {
    "title": "With the store alone (this website)",
    "items": [
      { "supported": true, "text": "Browse and download existing files ($n_files available)" },
      { "supported": true, "text": "Validate a pseudopotential you already have" },
      { "supported": true, "text": "Convert between formats (upfconv.x)" },
      { "supported": true, "text": "Read provenance and citations" },
      { "supported": false, "text": "Generate custom pseudopotentials" },
      { "supported": false, "text": "Run cutoff scans" },
      { "supported": false, "text": "Run transferability tests" },
      { "supported": false, "text": "Auto-fix failed generations" }
    ]
  },
  "cli_no_engines": {
    "title": "With PseudoForge installed, no engines",
    "items": [
      { "supported": true, "text": "All of the above" },
      { "supported": true, "text": "Inspect recipes (pseudoforge recipe <element>)" },
      { "supported": true, "text": "Validate from the CLI" },
      { "supported": false, "text": "Generate custom pseudopotentials (need an engine)" }
    ]
  },
  "cli_with_engines": {
    "title": "With PseudoForge and engines installed",
    "items": [
      { "supported": true, "text": "All of the above" },
      { "supported": true, "text": "Generate with $n_engines engines" },
      { "supported": true, "text": "Run cutoff scans with pw.x" },
      { "supported": true, "text": "Run transferability tests" },
      { "supported": true, "text": "Auto-fix failed generations" },
      { "supported": true, "text": "Custom recipes" }
    ]
  },
  "install": "./install.sh --bootstrap",
  "docs": "docs/getting-started/installation.md"
}
EOF
}
