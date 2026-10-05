#!/usr/bin/env bash
# Creates Rubric's production infrastructure on Oracle Cloud, inside the
# Always Free limits. Idempotent: every resource is found by name before
# it is created, so re-running only fills in what is missing.
#
#   tool/deploy/oci/provision_oci.sh [ssh public key]
#   default key: ~/.ssh/id_supposedlysam.pub
#
# Needs the OCI CLI and an API key, both in .contrib/oci/ (gitignored); see
# docs/DEPLOY.md. Creates, in a dedicated `rubric` compartment:
#   - VCN 10.0.0.0/16, an internet gateway, and a default route to it
#   - security list: TCP 22, 80 and 443 in; everything out
#   - public subnet 10.0.0.0/24
#   - instance rubric-prod: VM.Standard.A1.Flex, 1 OCPU, 6 GB, Ubuntu 24.04
#     (aarch64). On "Out of host capacity" it tries every availability
#     domain, then waits and tries again.
#   - a RESERVED public IPv4 (free) on the instance, so its address and the
#     app's server URL survive rebuilding the instance
# Prints the IP and the sslip.io domain for tool/deploy/deploy.sh.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../../.." && pwd)"
cfg="$repo/.contrib/oci/config"
cli="$repo/.contrib/oci/venv/bin/oci"
ssh_key="${1:-$HOME/.ssh/id_supposedlysam.pub}"
[ -x "$cli" ] && [ -f "$cfg" ] || { echo "oci: CLI or config missing in .contrib/oci (docs/DEPLOY.md)" >&2; exit 1; }
[ -f "$ssh_key" ] || { echo "oci: no SSH public key at $ssh_key" >&2; exit 1; }
export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True SUPPRESS_LABEL_WARNING=True

# Every CLI call. stdout carries only the result (progress chatter goes to
# stderr, so it can never leak into a captured id). Two errors are retried
# with backoff, because both mean "not yet" rather than "no": NotAuthenticated
# (a new API key reaches Oracle's identity servers gradually) and
# NotAuthorizedOrNotFound (a new compartment takes a while to be usable).
# Anything else fails at once, with Oracle's message.
O() {
  local out rc attempt err
  err="$(mktemp)"
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    rc=0
    out="$("$cli" --config-file "$cfg" "$@" 2>"$err")" || rc=$?
    if [ "$rc" = 0 ]; then rm -f "$err"; printf '%s\n' "$out"; return 0; fi
    if grep -q -e '"NotAuthenticated"' -e '"NotAuthorizedOrNotFound"' "$err" && [ "$attempt" -lt 10 ]; then
      echo "oci: $(grep -o -m1 -e NotAuthenticated -e NotAuthorizedOrNotFound "$err") on '$1 $2 $3' (attempt $attempt); retrying in $((attempt * 6))s" >&2
      sleep $((attempt * 6))
      continue
    fi
    cat "$err" >&2; rm -f "$err"; return "$rc"
  done
}
# A lookup's single value, or empty when the answer is "none" (null). A lookup
# that FAILS stops the script: "could not ask" is never the same as "not
# found", or a 401 makes us create duplicates of things that already exist.
q() {
  local v
  v="$(O "$@" --raw-output)" || { echo "oci: lookup failed: $*" >&2; exit 1; }
  [ "$v" = null ] && v=""
  printf '%s\n' "$v"
}
say() { echo "oci: $*"; }

tenancy="$(awk -F= '/^tenancy=/{print $2}' "$cfg")"

# --- compartment ---------------------------------------------------------
comp="$(q iam compartment list -c "$tenancy" --name rubric --lifecycle-state ACTIVE --query 'data[0].id')"
if [ -z "$comp" ]; then
  say "creating compartment rubric"
  comp="$(O iam compartment create -c "$tenancy" --name rubric \
    --description "Rubric production" --wait-for-state ACTIVE --query data.id --raw-output)"
  sleep 20 # a new compartment takes a moment to be usable everywhere
fi
say "compartment $comp"

# --- network -------------------------------------------------------------
vcn="$(q network vcn list -c "$comp" --display-name rubric-vcn --lifecycle-state AVAILABLE --query 'data[0].id')"
if [ -z "$vcn" ]; then
  say "creating VCN"
  vcn="$(O network vcn create -c "$comp" --display-name rubric-vcn --cidr-blocks '["10.0.0.0/16"]' \
    --dns-label rubric --wait-for-state AVAILABLE --query data.id --raw-output)"
fi
igw="$(q network internet-gateway list -c "$comp" --vcn-id "$vcn" --display-name rubric-igw --query 'data[0].id')"
if [ -z "$igw" ]; then
  say "creating internet gateway"
  igw="$(O network internet-gateway create -c "$comp" --vcn-id "$vcn" --display-name rubric-igw \
    --is-enabled true --wait-for-state AVAILABLE --query data.id --raw-output)"
fi
rt="$(O network vcn get --vcn-id "$vcn" --query 'data."default-route-table-id"' --raw-output)"
O network route-table update --rt-id "$rt" --force --route-rules \
  "[{\"destination\":\"0.0.0.0/0\",\"destinationType\":\"CIDR_BLOCK\",\"networkEntityId\":\"$igw\"}]" >/dev/null
sl="$(O network vcn get --vcn-id "$vcn" --query 'data."default-security-list-id"' --raw-output)"
tcp_in() { echo "{\"protocol\":\"6\",\"source\":\"0.0.0.0/0\",\"tcpOptions\":{\"destinationPortRange\":{\"min\":$1,\"max\":$1}}}"; }
O network security-list update --security-list-id "$sl" --force \
  --ingress-security-rules "[$(tcp_in 22),$(tcp_in 80),$(tcp_in 443)]" \
  --egress-security-rules '[{"protocol":"all","destination":"0.0.0.0/0"}]' >/dev/null
say "routes: 0.0.0.0/0 to the internet gateway; ingress: TCP 22, 80, 443"
subnet="$(q network subnet list -c "$comp" --vcn-id "$vcn" --display-name rubric-public --query 'data[0].id')"
if [ -z "$subnet" ]; then
  say "creating public subnet"
  subnet="$(O network subnet create -c "$comp" --vcn-id "$vcn" --display-name rubric-public \
    --cidr-block 10.0.0.0/24 --dns-label pub --route-table-id "$rt" \
    --security-list-ids "[\"$sl\"]" --wait-for-state AVAILABLE --query data.id --raw-output)"
fi

# --- instance ------------------------------------------------------------
inst="$(q compute instance list -c "$comp" --display-name rubric-prod --query \
  'data[?"lifecycle-state"!=`TERMINATED` && "lifecycle-state"!=`TERMINATING`] | [0].id')"
if [ -z "$inst" ]; then
  image="$(O compute image list -c "$comp" --operating-system "Canonical Ubuntu" \
    --operating-system-version "24.04" --shape VM.Standard.A1.Flex \
    --sort-by TIMECREATED --sort-order DESC --query 'data[0].id' --raw-output)"
  [ -n "$image" ] && [ "$image" != null ] || { echo "oci: no Ubuntu 24.04 aarch64 image found" >&2; exit 1; }
  say "image $(O compute image get --image-id "$image" --query 'data."display-name"' --raw-output)"
  ads=() # bash 3.2 (macOS) has no mapfile
  while IFS= read -r ad; do ads+=("$ad"); done < <(
    O iam availability-domain list -c "$comp" --query 'data[].name' --output json | jq -r '.[]')
  [ "${#ads[@]}" -gt 0 ] || { echo "oci: no availability domains listed" >&2; exit 1; }
  for round in $(seq 1 40); do
    for ad in "${ads[@]}"; do
      say "launching in $ad (round $round)"
      err="$(mktemp)"; rc=0
      out="$("$cli" --config-file "$cfg" compute instance launch -c "$comp" --availability-domain "$ad" \
          --display-name rubric-prod --shape VM.Standard.A1.Flex \
          --shape-config '{"ocpus":1,"memoryInGBs":6}' --image-id "$image" \
          --subnet-id "$subnet" --assign-public-ip false \
          --ssh-authorized-keys-file "$ssh_key" \
          --wait-for-state RUNNING --max-wait-seconds 900 2>"$err")" || rc=$?
      # Whatever the CLI reported, ask Oracle whether rubric-prod now exists
      # before trying again. A launch can succeed and still exit non-zero
      # (a wait that timed out, an output we failed to parse), and a second
      # launch would then make a duplicate instance and exceed the free tier.
      inst="$(q compute instance list -c "$comp" --display-name rubric-prod --query \
        'data[?"lifecycle-state"!=`TERMINATED` && "lifecycle-state"!=`TERMINATING`] | [0].id')"
      if [ -n "$inst" ]; then rm -f "$err"; break 2; fi
      if grep -qi -e "out of host capacity" -e "OutOfCapacity" "$err"; then
        say "no capacity in $ad"; rm -f "$err"
      else
        cat "$err" >&2; echo "$out" >&2; rm -f "$err"; exit "${rc:-1}"
      fi
    done
    say "every availability domain is full; retrying in 5 minutes"
    sleep 300
  done
  [ -n "$inst" ] || { echo "oci: no capacity after 40 rounds" >&2; exit 1; }
fi
say "instance $inst ($(O compute instance get --instance-id "$inst" --query 'data."lifecycle-state"' --raw-output))"

# --- reserved public IP ----------------------------------------------------
vnic="$(O compute vnic-attachment list -c "$comp" --instance-id "$inst" --query 'data[0]."vnic-id"' --raw-output)"
private_ip="$(O network private-ip list --vnic-id "$vnic" --query 'data[0].id' --raw-output)"
pip="$(q network public-ip list -c "$comp" --scope REGION --lifetime RESERVED \
  --query 'data[?"display-name"==`rubric-ip`] | [0].id')"
if [ -z "$pip" ]; then
  say "reserving a public IP"
  pip="$(O network public-ip create -c "$comp" --lifetime RESERVED --display-name rubric-ip \
    --query data.id --raw-output)"
fi
assigned="$(q network public-ip get --public-ip-id "$pip" --query 'data."private-ip-id"')"
if [ "$assigned" != "$private_ip" ]; then
  O network public-ip update --public-ip-id "$pip" --private-ip-id "$private_ip" >/dev/null
fi
ip="$(O network public-ip get --public-ip-id "$pip" --query 'data."ip-address"' --raw-output)"
say "public IP $ip (reserved)"
echo "IP=$ip"
echo "DOMAIN=${ip//./-}.sslip.io"
echo "SSH=ubuntu@$ip"
