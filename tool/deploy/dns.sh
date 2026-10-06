#!/usr/bin/env bash
# Makes a Cloudflare DNS record say what it should. Idempotent: it creates the
# record, fixes one that differs, or leaves a correct one alone.
#
#   tool/deploy/dns.sh <name> <ipv4>               # an A record
#   tool/deploy/dns.sh A|CNAME|TXT <name> <content>
#   e.g. tool/deploy/dns.sh api.yourrubric.com 147.224.152.185
#        tool/deploy/dns.sh TXT yourrubric.com "v=spf1 include:rp.oracleemaildelivery.com ~all"
#
# Which record is "the" record: A and CNAME, the one with that name. TXT, the
# one with that name and the same leading tag (`v=spf1`, `v=DMARC1`), because
# a name holds several TXT records and a domain must have exactly one SPF.
#
# The token lives in .contrib/cloudflare/token (gitignored, 0600). It is a
# Cloudflare API token limited to Zone > DNS > Edit for yourrubric.com, and
# is never printed. The record is "DNS only" (not proxied): the server's
# Caddy gets its own Let's Encrypt certificate, and Cloudflare's proxy would
# sit in front of that.
set -euo pipefail
cd "$(dirname "$0")/../.."

usage='usage: dns.sh <name> <ipv4> | dns.sh A|CNAME|TXT <name> <content>'
case "${1:-}" in
  A|CNAME|TXT) type="$1"; name="${2:?$usage}"; content="${3:?$usage}" ;;
  *) type=A; name="${1:?$usage}"; content="${2:?$usage}" ;;
esac
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

# Never proxied: A records serve Caddy's own certificate, and DKIM's CNAME
# must resolve to Oracle's key, not to Cloudflare.
want="$(jq -nc --arg t "$type" --arg n "$name" --arg c "$content" \
  '{type:$t,name:$n,content:$c,ttl:1} + (if $t=="TXT" then {} else {proxied:false} end)')"
# Cloudflare may hand TXT content back wrapped in quotes; compare without.
unquote='(.content | ltrimstr("\"") | rtrimstr("\""))'
existing="$(cf GET "/zones/$zone/dns_records?type=$type&name=$name")"
if [ "$type" = TXT ]; then
  tag="${content%% *}"
  match="$(jq -c --arg tag "$tag" "[.result[] | select($unquote | startswith(\$tag + \" \") or . == \$tag)][0] // empty" <<<"$existing")"
  others="$(jq --arg tag "$tag" "[.result[] | select($unquote | startswith(\$tag + \" \") or . == \$tag)] | length" <<<"$existing")"
  [ "$others" -le 1 ] || { echo "dns: $name has $others $tag TXT records; fix by hand" >&2; exit 1; }
else
  match="$(jq -c '.result[0] // empty' <<<"$existing")"
fi
id="$(jq -r '.id // empty' <<<"${match:-null}")"
if [ -z "$id" ]; then
  cf POST "/zones/$zone/dns_records" "$want" >/dev/null
  echo "dns: created $name $type $content"
elif [ "$(jq -r "$unquote" <<<"$match")" != "$content" ] ||
     { [ "$type" != TXT ] && [ "$(jq -r .proxied <<<"$match")" != false ]; }; then
  cf PUT "/zones/$zone/dns_records/$id" "$want" >/dev/null
  echo "dns: updated $name $type $content"
else
  echo "dns: $name $type already correct"
fi
