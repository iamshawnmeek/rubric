#!/usr/bin/env bash
# Renders the App Store and Google Play listing from the real app
# (test/store_screenshots, app_deploy_screenshots 1.2).
# Output: build/store_screenshots/<platform>/<slot>/NN_name.png, plus
# contact sheets in build/store_screenshots/_review/ and a manifest.json.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf build/store_screenshots
tool/flutter test test/store_screenshots --run-skipped --tags store_screenshots "$@"
echo "store screenshots: build/store_screenshots (review: build/store_screenshots/_review)"
