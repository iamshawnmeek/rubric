#!/usr/bin/env bash
# One-time, per-clone setup. Repo-local only: writes .git/config, never ~/.gitconfig.
set -euo pipefail
cd "$(dirname "$0")/.."
git config merge.arbunion.name "union of ARB keys"
git config merge.arbunion.driver "python3 tool/arb_merge.py %O %A %B"
echo "arb merge driver registered in .git/config"
tool/flutter pub get
