#!/usr/bin/env bash
# Deploys Rubric's server to a Linux host over SSH. Safe to re-run.
#
#   tool/deploy/deploy.sh <ssh target> <domain> [arm64|x64]
#   e.g. tool/deploy/deploy.sh ubuntu@203.0.113.7 203-0-113-7.sslip.io arm64
#
# The ssh user needs passwordless sudo (the default on cloud images). Steps:
#   1. build the bundle for the host (build.sh)
#   2. provision the host (idempotent: packages, user, units, Caddy, firewall)
#   3. back up the live database, if there is one, before touching anything
#   4. stop, swap the bundle in (never touching .zonai/data), start
#   5. gate on https://<domain>/health and the smoke test (smoke.dart)
# A failure at 5 leaves the new bundle running and says so, so you can roll
# back from the backup taken at 3 (docs/DEPLOY.md, "Rolling back").
set -euo pipefail
cd "$(dirname "$0")/../.."

target="${1:?usage: deploy.sh <ssh target> <domain> [arm64|x64]}"
domain="${2:?usage: deploy.sh <ssh target> <domain> [arm64|x64]}"
arch="${3:-arm64}"
url="https://$domain"
bundle="build/server-linux-$arch"
# Host keys go to a repo-local file (gitignored), not ~/.ssh/known_hosts. A
# new host is accepted on first contact, and a CHANGED key is still refused.
# DEPLOY_SSH_KEY picks the identity (default: ssh's own choice).
# DEPLOY_EXTRA_DOMAINS: more names Caddy also serves (space-separated), so an
# old name keeps working after a move to a new primary domain.
ssh_opts=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=.contrib/known_hosts)
if [ -n "${DEPLOY_SSH_KEY:-}" ]; then ssh_opts+=(-i "$DEPLOY_SSH_KEY"); fi
ssh() { command ssh "${ssh_opts[@]}" "$@"; }
rsync() { command rsync -e "ssh ${ssh_opts[*]}" "$@"; }
mkdir -p .contrib

echo "== 1/5 build"
tool/deploy/build.sh "$url" "$arch" "$bundle"

echo "== 2/5 provision $target"
# Mail settings first: the new unit requires /etc/rubric/smtp.env, and a
# release server refuses to start without them. The file is copied over ssh
# into a root-only file and never printed. Without a local copy, the host's
# existing one is kept; with neither, stop here rather than at the swap.
smtp_env=.contrib/oci/smtp.env
if [ -f "$smtp_env" ]; then
  ssh "$target" 'sudo install -d -m 0755 /etc/rubric &&
    sudo sh -c "umask 077 && cat > /etc/rubric/smtp.env.new" &&
    sudo mv /etc/rubric/smtp.env.new /etc/rubric/smtp.env' < "$smtp_env"
  echo "mail settings: copied from $smtp_env"
elif ! ssh "$target" 'sudo test -s /etc/rubric/smtp.env'; then
  echo "deploy: no mail settings in $smtp_env or on the host (docs/DEPLOY.md, \"Email\")" >&2
  exit 1
fi
rsync -a --delete tool/deploy/ "$target:/tmp/rubric-deploy/"
ssh "$target" "sudo bash /tmp/rubric-deploy/host/provision.sh $domain ${DEPLOY_EXTRA_DOMAINS:-}"

echo "== 3/5 backup before deploy"
ssh "$target" 'if sudo test -f /opt/rubric/.zonai/data/zonai.sqlite; then
  sudo systemctl start rubric-backup.service && sudo ls -1t /var/backups/rubric | head -1
else echo "no database yet: first deploy"; fi'

echo "== 4/5 swap"
ssh "$target" 'sudo systemctl stop rubric.service || true'
rsync -a --delete --rsync-path="sudo rsync" \
  --exclude '/.zonai/data/' --exclude '/ops/' \
  "$bundle/" "$target:/opt/rubric/"
ssh "$target" 'sudo chown -R rubric:rubric /opt/rubric/.zonai &&
  sudo chown root:root /opt/rubric/zonai && sudo systemctl start rubric.service'

echo "== 5/5 verify $url"
# Resolve through public DNS and pin it. This Mac's resolver can hold a
# cached "no such name" for up to 30 minutes after a new record is created
# (seen 2026-10-05), and that would fail a deploy that is actually fine.
public_ip="$(dig +short A "$domain" @1.1.1.1 | tail -1)"
[ -n "$public_ip" ] || { echo "deploy: $domain does not resolve in public DNS (tool/deploy/dns.sh)" >&2; exit 1; }
local_ip="$(dscacheutil -q host -a name "$domain" 2>/dev/null | awk '/ip_address/{print $2; exit}' || true)"
if [ "$local_ip" != "$public_ip" ]; then
  echo "deploy: note: this machine resolves $domain to '${local_ip:-nothing}', public DNS says $public_ip (a stale local cache)"
fi
pin=(--resolve "$domain:443:$public_ip")
for _ in $(seq 1 60); do
  curl -fsS -o /dev/null "${pin[@]}" "$url/health" && break
  sleep 2
done
curl -fsS -o /dev/null "${pin[@]}" "$url/health" ||
  { echo "deploy: $url/health never answered. See: ssh $target sudo journalctl -u rubric -n 100" >&2; exit 1; }
if [ "$local_ip" != "$public_ip" ]; then
  echo "deploy: skipping the smoke test from here until this machine's DNS cache catches up; run: tool/dart run tool/deploy/smoke.dart $url"
  exit 0
fi
tool/dart run tool/deploy/smoke.dart "$url"
echo "deploy: $url is live"
