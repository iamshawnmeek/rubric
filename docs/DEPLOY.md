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
  persistent boot volume (200 GB of block storage and 10 TB a month of
  outbound transfer are free). Measured footprint: the server and its four
  workers use about 75 MB of memory together.
- **Why not Google Cloud?** It was checked on 2026-10-01. The Always Free
  `e2-micro` (1 GB, `us-west1`/`us-central1`/`us-east1`, 30 GB disk) would fit
  in memory. But Google bills every in-use external IPv4 at $0.005/hour
  (about $3.65 a month) with no free-tier exemption on its pricing page, and
  free egress is only 1 GB a month. Firebase can't run the server at all
  (Hosting is static; Functions, App Hosting and Cloud Run scale to zero and
  lose the disk). The tooling here is host-agnostic (`x64` builds work
  too), so moving to an `e2-micro` is one command if it's ever worth $3.65 a
  month. Caddy gets a real Let's Encrypt certificate for
  `<ip-with-dashes>.sslip.io`, a free DNS name that resolves to the IP, so no
  domain purchase is needed. A real domain can replace it later through the
  `domain` argument alone.
- **Nothing here is Oracle-specific** except the firewall notes. Any Ubuntu
  host with SSH and sudo works (`x64` or `arm64`).

## Production (since 2026-10-05)

- **URL:** https://api.yourrubric.com (Let's Encrypt; Caddy renews it). The
  first name, https://147-224-152-185.sslip.io, is still served too, so
  nothing that used it breaks.
- **Domain:** `yourrubric.com`, registered at Cloudflare (at cost, auto-renew
  on). DNS is on Cloudflare: `api` is an A record to the reserved IP,
  **DNS only** (not proxied), so Caddy gets its own certificate. Managed by
  `tool/deploy/dns.sh <name> <ip>`, an idempotent upsert, with an API token
  limited to Zone > DNS > Edit for yourrubric.com, in
  `.contrib/cloudflare/token` (gitignored, 0600, never printed).
- **Host:** Oracle Cloud, US Midwest (Chicago), `VM.Standard.A1.Flex`
  (1 OCPU, 6 GB), Ubuntu 24.04 aarch64. Reserved public IP
  `147.224.152.185`. Everything is in the `rubric` compartment.
- **SSH:** `ubuntu@147.224.152.185`, key `~/.ssh/id_supposedlysam`
- **Deploy:** `DEPLOY_SSH_KEY=~/.ssh/id_supposedlysam DEPLOY_EXTRA_DOMAINS=147-224-152-185.sslip.io tool/deploy/deploy.sh ubuntu@147.224.152.185 api.yourrubric.com arm64`
  (the health check resolves through public DNS and pins it, so a stale
  local DNS cache can't fail a good deploy)
- **App:** release builds default to this URL (`productionServer` in
  `lib/main.dart`); `--dart-define=RUBRIC_SERVER=...` overrides it. Debug
  builds use the local server.

## Public website

https://yourrubric.com (`www.` redirects to it) is a static site in
`website/`: hand-written HTML, CSS and one small script, with no framework,
build step, cookies, analytics or third-party requests. The same Caddy
serves it from `/var/www/rubric`, so it costs nothing extra.

```bash
DEPLOY_SSH_KEY=~/.ssh/id_supposedlysam tool/deploy/site.sh ubuntu@147.224.152.185 yourrubric.com
```

`site.sh` upserts the apex and `www` DNS records, replaces the files whole,
installs the Caddy site (`host/website.caddy.template`: strict CSP, HSTS,
nosniff, a week's cache on `/assets/`), reloads Caddy, then checks every
page and asset through public DNS. It never touches the API server.

- **Brand:** colours and card shapes come from `lib/design_system`. The
  font stack asks for Avenir Next, which is built into Apple devices, and
  falls back to self-hosted Figtree (OFL, license in
  `website/assets/fonts/`). The app's Avenir TTFs are not served: their web
  license is unknown.
- **Motion:** slowly drifting background glows, a hero that rises in on load
  (CSS only), sections that rise and fade in once on scroll, and a few
  pixels of parallax on the hero device. All of it is off under
  `prefers-reduced-motion`.
- **Screenshots** are the real app: `tool/tour.sh` plus
  `tool/site_screens.sh` (`integration_test/site_screens_test.dart`, which
  opens the sample class's best-graded paper). Exported at 2× and
  JPEG-compressed into `website/assets/img/`.

## Infrastructure as code

`tool/deploy/oci/provision_oci.sh` creates the whole Oracle side and is
safe to re-run: every resource is found by name before it's created.
It creates the compartment, the VCN, an internet gateway, the route,
ingress for TCP 22/80/443, the subnet, the A1 instance (it retries every
availability domain on "Out of host capacity", and checks by name after
each attempt so it can never launch a duplicate), and the reserved IP.

It uses the OCI CLI and an API key, both in `.contrib/oci/` (gitignored;
the private key never leaves the dev machine). To set it up on another
machine:
1. Create a venv: `python3 -m venv .contrib/oci/venv && .contrib/oci/venv/bin/pip install oci-cli`.
2. Generate a key pair with openssl into `.contrib/oci/`.
3. In the console, add the public key under My profile → API keys.
4. Write `.contrib/oci/config` from the preview it shows, setting
   `key_file` to the private key.

A new key takes a few minutes to reach every Oracle identity server. The
script retries `NotAuthenticated` (and `NotAuthorizedOrNotFound`, for a
just-created compartment) with backoff.

## One-time: the host (the human's part)

Creating the cloud account needs a person and a card (Always Free resources
are never charged).

1. Create an Oracle Cloud account. Pick a home region with Ampere A1
   capacity.
2. **Upgrade the account to Pay As You Go.** It stays $0: Oracle doesn't
   charge for Always Free resources after the upgrade. Without it, Oracle
   reclaims Always Free VMs that look idle (CPU, network and memory all
   under 20% at the 95th percentile over 7 days). Rubric's server uses about
   75 MB and almost no CPU, so it would be reclaimed. Set a budget alert at
   $1 to catch any mistake early.
3. Create a Compute instance: image **Ubuntu 24.04**, shape
   **VM.Standard.A1.Flex** (1 OCPU and 6 GB is plenty; Always Free covers
   2 OCPUs and 12 GB), and your SSH public key. Give it a **reserved** public
   IPv4 (free, up to 2). A reserved IP outlives the instance, so the
   `sslip.io` name, and the app's `RUBRIC_SERVER`, survive rebuilding the host.
4. In the instance's VCN **security list**, add ingress rules for TCP **80**
   and **443** from `0.0.0.0/0`. Caddy needs 80 for the certificate challenge.
   `provision.sh` opens the host's own iptables. The cloud firewall is a
   separate layer and can only be changed in the console.
5. Note the public IP, for example `203.0.113.7`. The domain is then
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
| systemd units, Caddy, `provision.sh`, `deploy.sh` | First production deploy (2026-10-05): HTTPS with a Let's Encrypt cert, smoke test passed. The backup unit ran under its hardening and produced a verified snapshot; the timer is scheduled. Secrets file is root 0600. Server memory is 65 MB. |
| Survives a reboot | `systemctl reboot`: healthy about 50 s later, all three units active, smoke test passed again, firewall rules persisted |
| `provision_oci.sh` | Built the production infrastructure. A re-run found every existing resource and created only what was missing (the reserved IP). |
