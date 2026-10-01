# Deploying Rubric's server

Rubric's backend is a single zonai server with a SQLite database on local disk
(`server/`, see D11 in DESIGN.md). Production runs on one small Linux host for
**$0 a month**. Everything below is scripted in `tool/deploy/`.

```
 app ──HTTPS──▶ Caddy :443 ──▶ zonai serve --release 127.0.0.1:8792 ──▶ /opt/rubric/.zonai/data/zonai.sqlite
                (auto TLS)       systemd: rubric.service                   ▲
                                 timer:   rubric-backup.timer (daily) ─────┘──▶ /var/backups/rubric (14 kept)
```

## Why this shape

- **One host, never two.** zonai keeps everything in one SQLite file, so a
  second instance would mean two databases. The things that scale to zero or
  wipe their disk (Firebase Hosting, Cloud Functions, Cloud Run's free tier)
  can't run it.
- **$0.** The host is Oracle Cloud's *Always Free* Ampere A1 (ARM) VM with a
  persistent boot volume. Caddy gets a real Let's Encrypt certificate for
  `<ip-with-dashes>.sslip.io`, a free DNS name that resolves to the IP, so no
  domain purchase is needed. A real domain can replace it later through the
  `domain` argument alone.
- **Nothing here is Oracle-specific** except the firewall notes. Any Ubuntu
  host with SSH and sudo works (`x64` or `arm64`).

## One-time: the host (the human's part)

Creating the cloud account needs a person and a card (Always Free resources
are never charged).

1. Create an Oracle Cloud account. Pick a home region with Ampere A1
   capacity.
2. Create a Compute instance: image **Ubuntu 24.04**, shape
   **VM.Standard.A1.Flex** (1 OCPU and 6 GB is plenty; Always Free allows up
   to 4 and 24), your SSH public key, and a public IPv4.
3. In the instance's VCN **security list**, add ingress rules for TCP **80**
   and **443** from `0.0.0.0/0`. Caddy needs 80 for the certificate challenge.
   `provision.sh` opens the host's own iptables. The cloud firewall is a
   separate layer and can only be changed in the console.
4. Note the public IP, for example `203.0.113.7`. The domain is then
   `203-0-113-7.sslip.io`.

## Deploying (every release)

```bash
tool/deploy/deploy.sh ubuntu@203.0.113.7 203-0-113-7.sslip.io arm64
```

This builds the linux-arm64 bundle, provisions the host (idempotent), backs
up the live database, swaps the bundle in (never touching `.zonai/data`),
starts the service, and only reports success once `https://<domain>/health`
answers and `tool/deploy/smoke.dart` passes against it. Run the smoke test
alone at any time:

```bash
tool/dart run tool/deploy/smoke.dart https://203-0-113-7.sslip.io
```

Then point the app at it:

```bash
tool/flutter build ipa --dart-define=RUBRIC_SERVER=https://203-0-113-7.sslip.io
tool/flutter build appbundle --dart-define=RUBRIC_SERVER=https://203-0-113-7.sslip.io
```

## Secrets

- `JWT_SECRET` and `PASSWORD_SECRET` exist only in `/etc/rubric/secrets.env`
  on the host (root, 0600). `provision.sh` generates them on the first run
  and never overwrites them.
- The bundle carries no secrets. It's built with `RUBRIC_RELEASE=true`, which
  compiles empty ones in, so zonai refuses to start unless the host supplies
  them. A production server can't run on the dev secrets in source. Tested:
  the bundle exits with `jwtSecret is empty`, and a `strings` scan of every
  binary finds no dev secret.
- **Losing `PASSWORD_SECRET` locks every teacher out**, because it's mixed into
  every password hash. Keep a copy somewhere safe (a password manager), not
  in this repo.
- Rotation: move the old value to `PREVIOUS_JWT_SECRETS` /
  `PREVIOUS_PASSWORD_SECRETS` in the same file, set the new one, and run
  `sudo systemctl restart rubric`. Existing sessions and hashes keep working.

## Backups and restore

- **Daily** at 03:30 UTC, plus one before every deploy: `backup.sh` takes an
  online, WAL-safe `.backup`, rejects it unless `PRAGMA integrity_check` says
  `ok`, gzips it, and keeps the newest 14 in `/var/backups/rubric`.
- **Off-host copy.** A backup on the same disk doesn't survive losing the
  host. Pull them somewhere else regularly; it costs nothing:
  `rsync -a ubuntu@203.0.113.7:/var/backups/rubric/ ~/rubric-backups/` (the
  directory is `rubric`-owned, so add `--rsync-path="sudo rsync"`).
- **Restore / roll back:**
  `ssh <host> sudo /opt/rubric/ops/restore.sh /var/backups/rubric/zonai-<time>.sqlite.gz`.
  It checks the backup before touching the server, keeps the current
  database aside as `zonai.sqlite.before-restore-<time>`, and always starts
  the service again, even if the restore fails part-way.
- `tool/deploy/test_backup_restore.sh` (run by `tool/check.sh`) proves all of
  this against a real WAL database: a backup taken with a writer active, the
  rotation, no leftover files, refusing a corrupt backup without touching the
  service, and a restore that fails part-way still restarting it.
  Mutation-checked.

## What has been verified, and what hasn't

| Piece | Verified how |
|---|---|
| Release config fails closed without secrets | Real bundle, no env: refuses to start |
| Bundle serves with injected secrets, migrations apply | Real bundle on macOS, same layout: health 200, `smoke.dart` passes |
| Cross-compiled linux-arm64 bundle | Builds; every binary is an aarch64 ELF; no dev secrets in `strings` |
| Backup, rotation, restore, failure paths | `test_backup_restore.sh`, plus a round trip against the real bundle |
| systemd units, Caddy, `provision.sh`, `deploy.sh` | **Not yet run on Linux.** They pass `bash -n`. Their first real proof is the first deploy, which gates on health plus the smoke test. `shellcheck` isn't installed on the dev machine. |
