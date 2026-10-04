#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# install.sh -- put pseudoforge on your PATH.
#
#   ./install.sh                 symlink into ~/.local/bin
#   ./install.sh /usr/local/bin  symlink somewhere else
#
# pseudoforge runs perfectly well straight out of the source tree; this only saves
# you typing the full path.
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEST=${1:-$HOME/.local/bin}

mkdir -p "$DEST"
ln -sf "$ROOT/pseudoforge" "$DEST/pseudoforge"
echo "linked $DEST/pseudoforge -> $ROOT/pseudoforge"

case ":$PATH:" in
    *":$DEST:"*) ;;
    *) echo
       echo "$DEST is not on your PATH. Add this to your shell profile:"
       echo "    export PATH=\"$DEST:\$PATH\"" ;;
esac

echo
"$ROOT/pseudoforge" doctor
