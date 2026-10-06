#!/usr/bin/env bash
# Publishes the public website (website/) to the production host. Safe to
# re-run; it never touches the API server or its data.
#
#   tool/deploy/site.sh <ssh target> <apex domain>
#   e.g. tool/deploy/site.sh ubuntu@147.224.152.185 yourrubric.com
#
# 1. points <apex> and www.<apex> at the host (tool/deploy/dns.sh)
# 2. copies website/ to /var/www/rubric, replacing the old copy whole
# 3. installs the Caddy site (host/website.caddy.template) and reloads Caddy
# 4. checks https://<apex>/ and its assets through public DNS
# DEPLOY_SSH_KEY picks the ssh identity, as in deploy.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."

target="${1:?usage: site.sh <ssh target> <apex domain>}"
apex="${2:?usage: site.sh <ssh target> <apex domain>}"
ip="${target#*@}"

ssh_opts=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=.contrib/known_hosts)
if [ -n "${DEPLOY_SSH_KEY:-}" ]; then ssh_opts+=(-i "$DEPLOY_SSH_KEY"); fi
ssh() { command ssh "${ssh_opts[@]}" "$@"; }
rsync() { command rsync -e "ssh ${ssh_opts[*]}" "$@"; }

echo "== 1/4 DNS"
tool/deploy/dns.sh "$apex" "$ip"
tool/deploy/dns.sh "www.$apex" "$ip"

echo "== 2/4 files"
ssh "$target" 'sudo install -d -m 0755 /var/www/rubric /etc/caddy/sites'
# Permissions are set on the host afterwards: the rsync macOS ships has no
# --chmod. Caddy only needs to read; nothing there should be executable.
rsync -a --delete --rsync-path="sudo rsync" website/ "$target:/var/www/rubric/"
ssh "$target" 'sudo chown -R root:root /var/www/rubric && sudo chmod -R u=rwX,go=rX /var/www/rubric'


echo "== 3/4 Caddy"
sed "s/__APEX__/$apex/g" tool/deploy/host/website.caddy.template |
  ssh "$target" 'sudo tee /etc/caddy/sites/website.caddy >/dev/null &&
    (grep -q "^import /etc/caddy/sites/\*.caddy" /etc/caddy/Caddyfile ||
      echo "import /etc/caddy/sites/*.caddy" | sudo tee -a /etc/caddy/Caddyfile >/dev/null) &&
    sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null &&
    sudo systemctl reload caddy'

echo "== 4/4 verify"
# Through public DNS, pinned: a new record can sit in this machine's
# negative cache for a while (see deploy.sh).
for host in "$apex" "www.$apex"; do
  for _ in $(seq 1 30); do
    [ "$(dig +short A "$host" @1.1.1.1 | tail -1)" = "$ip" ] && break
    sleep 2
  done
done
pin=(--resolve "$apex:443:$ip" --resolve "www.$apex:443:$ip")
check() { # url expected-status
  local code
  for _ in $(seq 1 30); do
    code="$(curl -s -o /dev/null -w '%{http_code}' "${pin[@]}" "$1" || true)"
    [ "$code" = "$2" ] && { echo "ok   $1 -> $code"; return 0; }
    sleep 2
  done
  echo "FAIL $1 -> $code (want $2)" >&2; return 1
}
check "https://$apex/" 200
check "https://$apex/privacy.html" 200
check "https://$apex/assets/styles.css" 200
check "https://$apex/assets/fonts/figtree-latin.woff2" 200
check "https://www.$apex/" 301
# The pages the account emails link to, and the one API path they call.
check "https://$apex/reset-password" 200
check "https://$apex/verify-email" 200
check "https://$apex/assets/account.js" 200
# A made-up token must reach zonai and be refused there (4xx). A 404 or 405
# would mean Caddy served it as a file, and every emailed link would fail.
confirm="$(curl -s -o /dev/null -w '%{http_code}' "${pin[@]}" -X POST \
  -H 'Content-Type: application/json' \
  --data '{"type":"confirmVerifyEmail","token":"c21va2U6c21va2VAcnVicmljLmludmFsaWQ="}' \
  "https://$apex/api/auth/confirm")"
case "$confirm" in
  404|405|5*|000) echo "FAIL https://$apex/api/auth/confirm -> $confirm (want zonai's 4xx)" >&2; exit 1 ;;
  4*) echo "ok   https://$apex/api/auth/confirm -> $confirm (refused by zonai)" ;;
  *) echo "FAIL https://$apex/api/auth/confirm accepted a made-up token ($confirm)" >&2; exit 1 ;;
esac
echo "site: https://$apex is live"
