#!/usr/bin/env bash
# One-time (and safely re-runnable) setup of a fresh Ubuntu host for Rubric.
# Run ON the host as root. tool/deploy/deploy.sh uploads and runs it for you:
#
#   provision.sh <domain> [more domains...]
#   e.g. provision.sh api.yourrubric.com 147-224-152-185.sslip.io
#   The first is the primary name; Caddy serves, and gets a certificate for,
#   every name given.
#
# It installs the runtime (libsqlite3, sqlite3 for backups, Caddy for HTTPS),
# creates the `rubric` system user and its directories, generates the signing
# secrets ONCE (never overwritten: rotating them is a deliberate act, see
# docs/DEPLOY.md), installs the systemd units and the Caddy site, and opens
# ports 80 and 443 in the host firewall.
set -euo pipefail
domain="${1:?usage: provision.sh <domain> [more domains...]}"
sites="$(printf '%s, ' "$@")"; sites="${sites%, }"
here="$(cd "$(dirname "$0")" && pwd)"
[ "$(id -u)" = 0 ] || { echo "provision: run as root" >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q --no-install-recommends \
  ca-certificates curl rsync sqlite3 libsqlite3-0 caddy

# FFI loaders look for the unversioned name, which only the much larger -dev
# package ships. The same symlink zonai's own deployment guide makes.
lib="$(dpkg -L libsqlite3-0 | grep -m1 '/libsqlite3\.so\.0$')"
ln -sf "$lib" "$(dirname "$lib")/libsqlite3.so"

id rubric >/dev/null 2>&1 ||
  useradd --system --home-dir /opt/rubric --shell /usr/sbin/nologin rubric
# The bundle is root's: the service reads and runs it (group rubric) but can
# change none of it, not even its own compiled rules. Only the data
# directory is the service's. deploy.sh re-applies this after every swap.
install -d -o root -g rubric -m 0750 /opt/rubric /opt/rubric/.zonai
install -d -o rubric -g rubric -m 0750 /opt/rubric/.zonai/data
install -d -o rubric -g rubric -m 0750 /var/backups/rubric
install -d -o root -g rubric -m 0750 /opt/rubric/ops
install -d -o root -g root -m 0700 /etc/rubric

if [ ! -f /etc/rubric/secrets.env ]; then
  umask 077
  {
    echo "JWT_SECRET=$(openssl rand -base64 48 | tr -d '\n')"
    echo "PASSWORD_SECRET=$(openssl rand -base64 48 | tr -d '\n')"
  } > /etc/rubric/secrets.env
  echo "provision: generated new signing secrets in /etc/rubric/secrets.env"
fi
chmod 0600 /etc/rubric/secrets.env

install -o root -g rubric -m 0750 "$here/../backup.sh" "$here/../restore.sh" /opt/rubric/ops/
install -m 0644 "$here/rubric.service" "$here/rubric-backup.service" \
  "$here/rubric-backup.timer" /etc/systemd/system/
sed "s/__DOMAIN__/$sites/" "$here/Caddyfile.template" > /etc/caddy/Caddyfile
install -d -o caddy -g caddy /var/log/caddy
install -d -m 0755 /etc/caddy/sites /var/www/rubric

# Oracle's Ubuntu images ship iptables rules that drop everything but SSH.
# The cloud's own security list must allow 80/443 too (docs/DEPLOY.md).
if command -v iptables >/dev/null; then
  for port in 80 443; do
    iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null ||
      iptables -I INPUT 5 -p tcp --dport "$port" -j ACCEPT
  done
  if command -v netfilter-persistent >/dev/null; then netfilter-persistent save; fi
fi

systemctl daemon-reload
systemctl enable rubric.service rubric-backup.timer caddy.service
systemctl restart caddy
systemctl start rubric-backup.timer
echo "provision: done for $sites"
