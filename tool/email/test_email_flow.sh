#!/usr/bin/env bash
# Runs tool/email/email_flow.dart against a local development server whose
# mail goes to a local catcher, so the account emails are tested end to end
# without sending anything real, and the pages those links open in real
# Chrome, served as production serves them (site_server.py). About two
# minutes, most of it zonai compiling. Needs node 22+ and Chrome.
#
#   tool/email/test_email_flow.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

server_port=8793
sink_port=2525
site_port=8794
work="$(mktemp -d)"
pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT

# `zonai serve` reuses the last compiled config and rules even after their
# source changed (observed with zonai 0.10.1), so compile first or this would
# test yesterday's server.
(cd server && ../.contrib/bin/zonai compile > "$work/compile.log" 2>&1) ||
  { echo "email flow: zonai compile failed (log: $work/compile.log)" >&2; exit 1; }

tool/email/smtp_sink.py "$sink_port" "$work/mail" & pids+=($!)
tool/email/site_server.py "$site_port" "$server_port" & pids+=($!)

(cd server && SMTP_HOST=127.0.0.1 SMTP_PORT=$sink_port SMTP_USERNAME=sink \
  SMTP_PASSWORD=sink SMTP_ALLOW_INSECURE=true \
  exec ../.contrib/bin/zonai serve --port $server_port --host 127.0.0.1 \
  > "$work/server.log" 2>&1) & pids+=($!)

for _ in $(seq 1 120); do
  curl -s -o /dev/null "http://127.0.0.1:$server_port/" && break
  sleep 1
done
curl -s -o /dev/null "http://127.0.0.1:$server_port/" ||
  { echo "email flow: the server did not start (log: $work/server.log)" >&2; exit 1; }

tool/dart run tool/email/email_flow.dart "http://127.0.0.1:$server_port" "$work/mail" \
  "http://127.0.0.1:$site_port" || {
  echo "email flow: server log $work/server.log" >&2
  grep -v "CRON\|Deleted 0\|push jobs" "$work/server.log" | tail -25 >&2
  exit 1
}
