#!/usr/bin/env bash
# Tests backup.sh and restore.sh against a real WAL-mode SQLite database.
# Run by tool/check.sh. It needs bash and sqlite3, nothing from zonai.
#
# A fake `systemctl` on PATH records what the scripts ask of the service
# manager, so the "the service always comes back up" promise is checked
# without a real systemd.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

if ! command -v sqlite3 >/dev/null; then
  echo "test_backup_restore: SKIPPED, sqlite3 is not installed (these scripts were NOT tested)"
  exit 0
fi

root="$(mktemp -d)"
data="$root/data"; backups="$root/backups"; bin="$root/bin"
mkdir -p "$data" "$backups" "$bin"
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }

# A fake systemctl: knows a unit called "rubric", logs every call.
cat > "$bin/systemctl" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$root/systemctl.log"
case "\$1" in list-unit-files) [ "\$2" = "rubric.service" ] ;; *) exit 0 ;; esac
EOF
chmod +x "$bin/systemctl"
export PATH="$bin:$PATH"

db="$data/zonai.sqlite"
sqlite3 "$db" "PRAGMA journal_mode=WAL; CREATE TABLE users(id TEXT PRIMARY KEY);
  INSERT INTO users VALUES ('a'),('b'),('c');" >/dev/null

# 1. Backups taken while a writer holds the database open, and rotation.
( sqlite3 "$db" "BEGIN; INSERT INTO users VALUES ('in-flight'); SELECT 1; " >/dev/null; sleep 2 ) &
writer=$!
for _ in 1 2 3; do "$here/backup.sh" "$data" "$backups" 2 >/dev/null; sleep 1; done
wait "$writer" || true
count="$(ls -1 "$backups"/zonai-*.sqlite.gz | wc -l | tr -d ' ')"
[ "$count" = 2 ] && ok "rotation keeps exactly 2" || bad "rotation kept $count, want 2"
extra="$(ls -A "$backups" | grep -v '^zonai-.*\.sqlite\.gz$' || true)"
[ -z "$extra" ] && ok "backup leaves no side files" || bad "backup left: $extra"

# 2. Restore swaps the backup in, keeps the old database, cycles the service.
sqlite3 "$db" "INSERT INTO users VALUES ('after-backup');"
latest="$(ls -1t "$backups"/zonai-*.sqlite.gz | head -1)"
: > "$root/systemctl.log"
"$here/restore.sh" "$latest" "$data" rubric >/dev/null
users="$(sqlite3 "$db" 'SELECT count(*) FROM users;')"
[ "$users" = 3 ] && ok "restore brings back the backed-up rows" || bad "restored users=$users, want 3"
ls "$data"/zonai.sqlite.before-restore-* >/dev/null 2>&1 &&
  ok "the previous database is kept aside" || bad "previous database not kept"
grep -q '^stop rubric$' "$root/systemctl.log" && grep -q '^start rubric$' "$root/systemctl.log" &&
  ok "the service is stopped, then started again" || bad "systemctl calls: $(tr '\n' ';' < "$root/systemctl.log")"

# 3. A corrupt backup is refused before the service is touched.
echo "not a database" | gzip > "$root/corrupt.sqlite.gz"
: > "$root/systemctl.log"
if "$here/restore.sh" "$root/corrupt.sqlite.gz" "$data" rubric >/dev/null 2>&1; then
  bad "a corrupt backup was restored"
else
  ok "a corrupt backup is refused"
fi
[ ! -s "$root/systemctl.log" ] && ok "the refusal never touched the service" ||
  bad "systemctl was called: $(tr '\n' ';' < "$root/systemctl.log")"

# 4. A restore that fails after stopping the service still restarts it.
chmod 555 "$data"   # moving files in or out now fails
: > "$root/systemctl.log"
"$here/restore.sh" "$latest" "$data" rubric >/dev/null 2>&1 && bad "restore into a read-only dir succeeded" || true
chmod 755 "$data"
grep -q '^start rubric$' "$root/systemctl.log" &&
  ok "a failed restore still starts the service again" || bad "service left stopped: $(tr '\n' ';' < "$root/systemctl.log")"

# 5. Off-host: a checked backup is uploaded through the link, byte for byte,
# under its own name; a failed upload fails the run but keeps the local copy;
# a required link that is missing fails the run.
chmod 755 "$data"
uploads="$root/uploads"; mkdir -p "$uploads"
port_file="$root/port"
python3 - "$uploads" "$port_file" <<'PY' &
import http.server, os, sys
out, port_file = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_PUT(self):
        n = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(n)
        if '/broken/' in self.path:
            self.send_response(500); self.end_headers(); return
        with open(os.path.join(out, os.path.basename(self.path)), 'wb') as f:
            f.write(body)
        self.send_response(200); self.end_headers()
    def log_message(self, *a): pass
s = http.server.HTTPServer(('127.0.0.1', 0), H)
open(port_file, 'w').write(str(s.server_port))
s.serve_forever()
PY
sink=$!
for _ in $(seq 1 50); do [ -s "$port_file" ] && break; sleep 0.1; done
port="$(cat "$port_file")"
offhost="$root/offhost-backups"
if BACKUP_PAR_URL="http://127.0.0.1:$port/p/token/n/ns/b/rubric-backups/o/" \
    "$here/backup.sh" "$data" "$offhost" 2 >/dev/null; then
  local_copy="$(ls -1t "$offhost"/zonai-*.sqlite.gz | head -1)"
  uploaded="$uploads/$(basename "$local_copy")"
  [ -f "$uploaded" ] && cmp -s "$uploaded" "$local_copy" &&
    ok "the backup is uploaded off-host, byte for byte, under its name" ||
    bad "upload missing or different ($(ls "$uploads"))"
else
  bad "backup with an upload link failed"
fi
# Backups are named to the second; wait one so the next is a new file.
sleep 1
before="$(ls -1 "$offhost" | wc -l | tr -d ' ')"
if BACKUP_PAR_URL="http://127.0.0.1:$port/broken/" \
    "$here/backup.sh" "$data" "$offhost" 5 >/dev/null 2>&1; then
  bad "a failed upload did not fail the run"
else
  after="$(ls -1 "$offhost" | wc -l | tr -d ' ')"
  [ "$after" -gt "$before" ] && ok "a failed upload fails the run, keeping the local copy" ||
    bad "a failed upload lost the local copy"
fi
if BACKUP_OFFHOST=required "$here/backup.sh" "$data" "$offhost" 5 >/dev/null 2>&1; then
  bad "a required off-host copy with no link did not fail the run"
else
  ok "a required off-host copy with no link fails the run"
fi
kill "$sink" 2>/dev/null || true

echo "test_backup_restore: $([ "$fails" = 0 ] && echo passed || echo "$fails FAILED") ($root)"
[ "$fails" = 0 ]
