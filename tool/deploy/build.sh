#!/usr/bin/env bash
# Builds Rubric's production server bundle for a Linux host.
#
#   tool/deploy/build.sh <public base url> [arm64|x64] [out dir]
#   e.g. tool/deploy/build.sh https://203-0-113-7.sslip.io arm64
#
# It builds from a scratch copy of server/, so the cross-compile settings
# never touch the zonai.yaml a developer serves from. The bundle carries NO
# signing secrets. It is compiled with RUBRIC_RELEASE=true, so it refuses to
# start until the host supplies JWT_SECRET and PASSWORD_SECRET at runtime
# (see server/lib/src/config/app_config.dart and docs/DEPLOY.md).
set -euo pipefail
cd "$(dirname "$0")/../.."

base_url="${1:?usage: build.sh <public base url> [arm64|x64] [out dir]}"
arch="${2:-arm64}"
out="${3:-build/server-linux-$arch}"
case "$arch" in arm64|x64) ;; *) echo "build: arch must be arm64 or x64" >&2; exit 64 ;; esac
case "$base_url" in https://*) ;; *) echo "build: the base url must be https://" >&2; exit 64 ;; esac

zonai=".contrib/bin/zonai"
[ -x "$zonai" ] || { echo "build: no zonai CLI at $zonai (see docs/DEPLOY.md)" >&2; exit 1; }

scratch="$(mktemp -d)"
# Source, migrations and config only: no local database, no dev build output.
rsync -a --exclude '.zonai/data' --exclude '.zonai/executables' \
  --exclude '.zonai/lib' --exclude '.zonai/gen' --exclude 'build' \
  --exclude '.dart_tool' --exclude '.env*' server/ "$scratch/"
printf '\nbuildSettings:\n  targetOs: linux\n  targetArch: %s\n' "$arch" >> "$scratch/zonai.yaml"
# Not secret: the release switch and the public URL. Secrets stay off disk.
printf 'RUBRIC_RELEASE=true\nRUBRIC_BASE_URL=%s\n' "$base_url" > "$scratch/.env.prod"

(cd "$scratch" && "$OLDPWD/tool/dart" pub get >/dev/null &&
  "$OLDPWD/$zonai" build --flavor prod --release)

mkdir -p "$(dirname "$out")"
rsync -a --delete "$scratch/build/" "$out/"
echo "build: $out ($(du -sh "$out" | cut -f1)) for linux-$arch, serving $base_url"
