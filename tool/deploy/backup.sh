#!/usr/bin/env bash
# Online backup of a Rubric server's database. Runs ON the server, from the
# rubric-backup systemd timer (daily), and can be run by hand at any time.
#
#   backup.sh [data_dir] [backup_dir] [keep]
#   defaults: /opt/rubric/.zonai/data  /var/backups/rubric  14
#
# Only zonai.sqlite is backed up; it holds every account and every synced
# row. zonai_log.sqlite (request log) and zonai_rate_limit.sqlite (counters)
# are disposable: a restored server recreates them empty.
#
# `.backup` takes a consistent snapshot while the server keeps serving (it is
# WAL-safe; copying the file is not). Each backup must pass
# PRAGMA integrity_check before it counts, and an unreadable one is deleted
# and the run fails: a backup that was never checked is a hope, not a backup.
#
# Off the host: a backup on the same disk doesn't survive losing the host.
# With BACKUP_PAR_URL set (a write-only pre-authenticated request on the
# private, versioned `rubric-backups` bucket in Oracle Object Storage), each
# checked backup is uploaded too. The host holds no Oracle credentials, only
# that link, and it can write but not read or delete: with versioning on, even
# a leaked link can't destroy earlier backups. A failed upload fails the run
# (the local copy stays). With BACKUP_OFFHOST=required (the production unit
# sets it), a missing link fails the run too, so a host can't silently fall
# back to local-only. Recipe from gravity-brew-owner.
set -euo pipefail

data_dir="${1:-/opt/rubric/.zonai/data}"
backup_dir="${2:-/var/backups/rubric}"
keep="${3:-14}"

db="$data_dir/zonai.sqlite"
[ -f "$db" ] || { echo "backup: no database at $db" >&2; exit 1; }
command -v sqlite3 >/dev/null || { echo "backup: sqlite3 not installed" >&2; exit 1; }
mkdir -p "$backup_dir"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
tmp="$backup_dir/.zonai-$stamp.sqlite"
out="$backup_dir/zonai-$stamp.sqlite.gz"

sqlite3 "$db" ".backup '$tmp'"
# The snapshot inherits WAL mode from the live database, so checking it
# creates -wal/-shm files beside it (32 KB a run, left behind forever unless
# removed). Every exit path below removes them.
check="$(sqlite3 "$tmp" 'PRAGMA integrity_check;')"
if [ "$check" != "ok" ]; then
  rm -f "$tmp" "$tmp-wal" "$tmp-shm"
  echo "backup: integrity_check failed on the snapshot: $check" >&2
  exit 1
fi
gzip -9 -c "$tmp" > "$out.part" && mv "$out.part" "$out"
rm -f "$tmp" "$tmp-wal" "$tmp-shm"

# Newest first; keep the newest $keep, delete the rest.
ls -1t "$backup_dir"/zonai-*.sqlite.gz 2>/dev/null | tail -n +"$((keep + 1))" |
  while read -r old; do rm -f "$old"; done

if [ -n "${BACKUP_PAR_URL:-}" ]; then
  if ! curl -fsS --retry 3 --retry-delay 5 -X PUT --upload-file "$out" \
      "${BACKUP_PAR_URL%/}/$(basename "$out")" >/dev/null; then
    echo "backup: kept $out locally, but the off-host upload FAILED" >&2
    exit 1
  fi
  echo "backup: $out ($(du -h "$out" | cut -f1)), uploaded off-host, keeping $keep locally"
elif [ "${BACKUP_OFFHOST:-}" = required ]; then
  echo "backup: kept $out locally, but BACKUP_PAR_URL is not set and an off-host copy is required" >&2
  exit 1
else
  echo "backup: $out ($(du -h "$out" | cut -f1)), keeping $keep; no off-host copy (BACKUP_PAR_URL unset)"
fi
