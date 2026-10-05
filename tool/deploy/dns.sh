#!/usr/bin/env bash
# Makes a Cloudflare DNS A record point at an IP. Idempotent: it creates the
# record, fixes one that differs, or leaves a correct one alone.
#
#   tool/deploy/dns.sh <name> <ipv4>
#   e.g. tool/deploy/dns.sh api.yourrubric.com 147.224.152.185
#
# The token lives in .contrib/cloudflare/token (gitignored, 0600). It is a
# Cloudflare API token limited to Zone > DNS > Edit for yourrubric.com, and
# is never printed. The record is "DNS only" (not proxied): the server's
# Caddy gets its own Let's Encrypt certificate, and Cloudflare's proxy would
# sit in front of that.
set -euo pipefail
cd "$(dirname "$0")/../.."

name="${1:?usage: dns.sh <name> <ipv4>}"
ip="${2:?usage: dns.sh <name> <ipv4>}"
token_file=.contrib/cloudflare/token
[ -f "$token_file" ] || { echo "dns: no token at $token_file (docs/DEPLOY.md)" >&2; exit 1; }
api=https://api.cloudflare.com/client/v4

cf() { # method path [json]
  local res
  res="$(curl -sS -X "$1" "$api$2" \
    -H "Authorization: Bearer $(tr -d '[:space:]' < "$token_file")" \
    -H "Content-Type: application/json" ${3:+--data "$3"})"
  if [ "$(jq -r .success <<<"$res")" != true ]; then
    echo "dns: Cloudflare refused $1 $2: $(jq -c .errors <<<"$res")" >&2; exit 1
  fi
  printf '%s\n' "$res"
}

# The zone is the registrable domain: the last two labels of the name.
zone_name="$(awk -F. '{print $(NF-1)"."$NF}' <<<"$name")"
zone="$(cf GET "/zones?name=$zone_name" | jq -r '.result[0].id // empty')"
[ -n "$zone" ] || { echo "dns: the token cannot see zone $zone_name" >&2; exit 1; }

want="{\"type\":\"A\",\"name\":\"$name\",\"content\":\"$ip\",\"ttl\":1,\"proxied\":false}"
existing="$(cf GET "/zones/$zone/dns_records?type=A&name=$name")"
id="$(jq -r '.result[0].id // empty' <<<"$existing")"
if [ -z "$id" ]; then
  cf POST "/zones/$zone/dns_records" "$want" >/dev/null
  echo "dns: created $name A $ip"
elif [ "$(jq -r '.result[0].content' <<<"$existing")" != "$ip" ] ||
     [ "$(jq -r '.result[0].proxied' <<<"$existing")" != false ]; then
  cf PUT "/zones/$zone/dns_records/$id" "$want" >/dev/null
  echo "dns: updated $name A $ip (DNS only)"
else
  echo "dns: $name A $ip already correct"
fi
