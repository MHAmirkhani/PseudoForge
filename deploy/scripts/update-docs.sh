#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# update-docs.sh -- build the documentation and deploy it to /docs/.
#
# Built here, not on the VPS: MkDocs is a Python toolchain and the server has
# 1 GB of RAM to serve with. What arrives is static HTML.
#
#   deploy/scripts/update-docs.sh            build and upload
#   deploy/scripts/update-docs.sh --local    build only, into ./site
# ---------------------------------------------------------------------------
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
[ -f "$ROOT/deploy/local/config" ] && . "$ROOT/deploy/local/config"

PF_REMOTE=${PF_REMOTE:-}
PF_VAR_DIR=${PF_VAR_DIR:-/var/lib/pseudoforge}
MKDOCS=${MKDOCS_BIN:-$(command -v mkdocs || true)}

[ -n "$MKDOCS" ] || { echo "mkdocs not found; set MKDOCS_BIN" >&2; exit 1; }

cd "$ROOT"
# --strict: a broken link fails the build rather than shipping a dead one.
"$MKDOCS" build --strict --site-dir "$ROOT/site"
echo "built $(find "$ROOT/site" -name '*.html' | wc -l) pages"

[ "${1:-}" = "--local" ] && { echo "site/ is ready"; exit 0; }
[ -n "$PF_REMOTE" ] || { echo "set PF_REMOTE in deploy/local/config" >&2; exit 1; }

rsync -avz --delete "$ROOT/site/" "$PF_REMOTE:$PF_VAR_DIR/docs/"
echo "deployed to $PF_REMOTE:$PF_VAR_DIR/docs/"
