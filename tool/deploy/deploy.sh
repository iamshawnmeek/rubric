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

echo "== 1/5 build"
tool/deploy/build.sh "$url" "$arch" "$bundle"

echo "== 2/5 provision $target"
rsync -a --delete tool/deploy/ "$target:/tmp/rubric-deploy/"
ssh "$target" "sudo bash /tmp/rubric-deploy/host/provision.sh '$domain'"

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
for _ in $(seq 1 60); do
  curl -fsS -o /dev/null "$url/health" && break
  sleep 2
done
curl -fsS -o /dev/null "$url/health" ||
  { echo "deploy: $url/health never answered. See: ssh $target sudo journalctl -u rubric -n 100" >&2; exit 1; }
tool/dart run tool/deploy/smoke.dart "$url"
echo "deploy: $url is live"
