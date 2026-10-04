#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# upload-native.sh -- push generated pseudopotentials to the VPS.
#
# This runs on YOUR machine, where the engines are. It is the other half of
# the architecture: generation happens here, serving happens there.
#
#   deploy/scripts/upload-native.sh ./psl-paw-pbe
#   deploy/scripts/upload-native.sh ./psl-paw-pbe --dry-run
#
# The provenance sidecar travels with each file. Without it the server has to
# guess an element's functional from its name, and a guessed functional on a
# pseudopotential is the kind of error that survives into someone's paper.
# ---------------------------------------------------------------------------
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
[ -f "$ROOT/deploy/local/config" ] && . "$ROOT/deploy/local/config"

PF_REMOTE=${PF_REMOTE:-}
PF_VAR_DIR=${PF_VAR_DIR:-/var/lib/pseudoforge}

project=${1:-}
shift || true
DRY=""
for a in "$@"; do [ "$a" = "--dry-run" ] && DRY="--dry-run"; done

[ -n "$project" ] || { echo "usage: upload-native.sh <project-dir> [--dry-run]" >&2; exit 2; }
[ -d "$project/pseudos" ] || { echo "not a PseudoForge project: $project" >&2; exit 1; }
[ -n "$PF_REMOTE" ] || { echo "set PF_REMOTE in deploy/local/config (user@host)" >&2; exit 1; }

stage=$(mktemp -d); trap 'rm -rf "$stage"' EXIT

# Each file, plus a provenance sidecar built from the run's own PROVENANCE.txt.
# Not invented: what is not recorded is left out, and the server reports it as
# unknown rather than filling it in.
n=0
for f in "$project"/pseudos/*; do
    case $f in *CITATION.txt|*LICENSE.txt) continue ;; esac
    [ -f "$f" ] || continue
    b=$(basename "$f")
    cp "$f" "$stage/$b"
    {
        printf 'element=%s\n' "${b%%.*}"
        grep -E '^(functional|relativity|family|engine|profile)=' \
             "$project/PROVENANCE.txt" 2>/dev/null || true
        grep -E '^recipe.erratum=' "$project/PROVENANCE.txt" 2>/dev/null || true
    } > "$stage/$b.provenance"
    n=$((n + 1))
done
echo "staged $n file(s) with provenance"

rsync -avz --partial $DRY "$stage/" "$PF_REMOTE:$PF_VAR_DIR/native/"

if [ -z "$DRY" ]; then
    # The index is derived on the server, from the files that are now there.
    ssh "$PF_REMOTE" "pseudoforge native index $PF_VAR_DIR/native && \
                      pseudoforge native size  $PF_VAR_DIR"
fi
