#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# install-vps.sh -- set up the VPS. Idempotent: run it twice, get the same
# machine.
#
# What this deliberately does not install: gfortran, cmake, ninja, GSL, LAPACK,
# Quantum ESPRESSO, or any of the nine engines. **The VPS does not generate
# pseudopotentials.** It serves pre-built native files and converts them on
# demand, and the architecture depends on that rather than merely tolerating
# it. See docs/architecture/http.md.
#
#   sudo deploy/scripts/install-vps.sh            first run, needs root
#   deploy/scripts/install-vps.sh --check         afterwards, needs nobody
#
# Machine-specific values -- the real domain, paths, tokens -- come from
# deploy/local/config, which is gitignored. Copy deploy/local/.example to
# deploy/local/config and edit it.
# ---------------------------------------------------------------------------
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)

# ---- configuration --------------------------------------------------------
LOCAL_CONF=$ROOT/deploy/local/config
if [ -f "$LOCAL_CONF" ]; then
    # shellcheck source=/dev/null
    . "$LOCAL_CONF"
else
    printf 'note: no deploy/local/config; using defaults\n' >&2
    printf '      cp deploy/local/.example deploy/local/config\n' >&2
fi

PF_DOMAIN=${PF_DOMAIN:-pseudo.example.org}
PF_VAR_DIR=${PF_VAR_DIR:-/var/lib/pseudoforge}
PF_OPT_DIR=${PF_OPT_DIR:-/opt/pseudoforge}
PF_USER=${PF_USER:-pseudoforge}
PF_PORT=${PF_PORT:-8099}

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

say()  { printf '  %s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
need_root() {
    [ "$(id -u)" = 0 ] || { printf 'this step needs root: sudo %s\n' "$0" >&2; exit 1; }
}

# ---------------------------------------------------------------------------
if [ "$CHECK_ONLY" = 1 ]; then
    step "checking"
    rc=0
    for d in native converter cache db docs www; do
        if [ -d "$PF_VAR_DIR/$d" ]; then say "ok      $PF_VAR_DIR/$d"
        else say "MISSING $PF_VAR_DIR/$d"; rc=1; fi
    done
    command -v nginx   >/dev/null && say "ok      nginx"   || { say "MISSING nginx"; rc=1; }
    command -v python3 >/dev/null && say "ok      python3" || { say "MISSING python3"; rc=1; }
    command -v sqlite3 >/dev/null && say "ok      sqlite3" || { say "MISSING sqlite3"; rc=1; }
    systemctl is-active --quiet pseudoforge-api 2>/dev/null \
        && say "ok      pseudoforge-api is running" \
        || say "note    pseudoforge-api is not running"
    # The budget the architecture depends on.
    if [ -d "$PF_VAR_DIR" ]; then
        used=$(du -sm "$PF_VAR_DIR" 2>/dev/null | cut -f1)
        say "used    ${used}M of ${PF_VPS_BUDGET_MB:-8192}M"
        [ "${used:-0}" -gt "${PF_VPS_BUDGET_MB:-8192}" ] && { say "OVER BUDGET"; rc=1; }
    fi
    exit $rc
fi

need_root

step "packages"
# Nginx, Python, SQLite. Nothing that could build an engine.
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq nginx python3 python3-venv python3-pip sqlite3 rsync
say "installed"

step "user"
if id "$PF_USER" >/dev/null 2>&1; then
    say "$PF_USER exists"
else
    useradd --system --home "$PF_VAR_DIR" --shell /usr/sbin/nologin "$PF_USER"
    say "created $PF_USER"
fi

step "directories"
for d in native converter cache db docs www; do
    install -d -o "$PF_USER" -g "$PF_USER" -m 0755 "$PF_VAR_DIR/$d"
    say "$PF_VAR_DIR/$d"
done
# Only these two are written to at run time; ProtectSystem=strict in the unit
# depends on that being true.
chmod 0775 "$PF_VAR_DIR/cache" "$PF_VAR_DIR/db"

step "the core"
install -d -m 0755 "$PF_OPT_DIR"
rsync -a --delete \
    --exclude '.git' --exclude 'deploy/local' --exclude 'site' --exclude '__pycache__' \
    "$ROOT/" "$PF_OPT_DIR/"
chown -R "$PF_USER:$PF_USER" "$PF_OPT_DIR"
say "$PF_OPT_DIR"

step "the transport"
if [ ! -d "$PF_OPT_DIR/server/.venv" ]; then
    python3 -m venv "$PF_OPT_DIR/server/.venv"
fi
"$PF_OPT_DIR/server/.venv/bin/pip" install -q --upgrade pip
"$PF_OPT_DIR/server/.venv/bin/pip" install -q -r "$PF_OPT_DIR/server/requirements.txt"
chown -R "$PF_USER:$PF_USER" "$PF_OPT_DIR/server/.venv"
say "virtualenv ready"

step "the database"
sqlite3 "$PF_VAR_DIR/db/pseudoforge.db" < "$PF_OPT_DIR/server/migrations/001_initial.sql"
chown "$PF_USER:$PF_USER" "$PF_VAR_DIR/db/pseudoforge.db"
say "schema applied (idempotent)"

step "systemd"
install -m 0644 "$ROOT/deploy/systemd/pseudoforge-api.service"   /etc/systemd/system/
install -m 0644 "$ROOT/deploy/systemd/pseudoforge-cache.service" /etc/systemd/system/
install -m 0644 "$ROOT/deploy/systemd/pseudoforge-cache.timer"   /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now pseudoforge-api.service
systemctl enable --now pseudoforge-cache.timer
say "units installed and enabled"

step "nginx"
conf=/etc/nginx/sites-available/pseudoforge.conf
sed -e "s|PSEUDOFORGE_DOMAIN|$PF_DOMAIN|g" \
    -e "s|127.0.0.1:8099|127.0.0.1:$PF_PORT|g" \
    "$ROOT/deploy/nginx/pseudoforge.conf" > "$conf"
ln -sfn "$conf" /etc/nginx/sites-enabled/pseudoforge.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx
say "serving $PF_DOMAIN"

step "done"
say "check it:    deploy/scripts/install-vps.sh --check"
say "upload files: deploy/scripts/upload-native.sh"
say "deploy docs:  deploy/scripts/update-docs.sh"
say ""
say "TLS is not configured here. Run certbot, or terminate TLS upstream:"
say "    certbot --nginx -d $PF_DOMAIN"
