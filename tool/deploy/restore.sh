#!/usr/bin/env bash
# Restore a Rubric server's database from a backup made by backup.sh. Runs ON
# the server, as root.
#
#   restore.sh <backup.sqlite.gz> [data_dir] [service]
#   defaults: /opt/rubric/.zonai/data  rubric
#
# The backup is checked BEFORE the server is touched. The current database
# is kept beside it (zonai.sqlite.before-restore-<time>), not overwritten, so
# a wrong restore can be undone. The WAL and shared-memory files of the old
# database are moved aside too: left in place, SQLite would replay the old
# database's WAL over the restored one.
set -euo pipefail

backup="${1:?usage: restore.sh <backup.sqlite.gz> [data_dir] [service]}"
data_dir="${2:-/opt/rubric/.zonai/data}"
service="${3:-rubric}"

[ -f "$backup" ] || { echo "restore: no such backup: $backup" >&2; exit 1; }
work="$(mktemp -d)"
gunzip -c "$backup" > "$work/zonai.sqlite"
check="$(sqlite3 "$work/zonai.sqlite" 'PRAGMA integrity_check;')"
[ "$check" = "ok" ] || { echo "restore: backup fails integrity_check: $check" >&2; exit 1; }

has_systemd() { command -v systemctl >/dev/null && systemctl list-unit-files "$service.service" >/dev/null 2>&1; }
if has_systemd; then
  systemctl stop "$service"
  # Whatever happens from here, the service comes back up: a restore that
  # fails half-way must not also take Rubric down.
  trap 'systemctl start "$service"' EXIT
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
for f in zonai.sqlite zonai.sqlite-wal zonai.sqlite-shm; do
  if [ -f "$data_dir/$f" ]; then mv "$data_dir/$f" "$data_dir/$f.before-restore-$stamp"; fi
done
mv "$work/zonai.sqlite" "$data_dir/zonai.sqlite"
rm -f "$work"/zonai.sqlite-wal "$work"/zonai.sqlite-shm
rmdir "$work"
if id rubric >/dev/null 2>&1; then chown rubric:rubric "$data_dir/zonai.sqlite"; fi

echo "restore: $backup is live; the previous database is at $data_dir/zonai.sqlite.before-restore-$stamp"
