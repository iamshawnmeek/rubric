#!/usr/bin/env bash
# Captures the website screenshots the tour can't reach (a graded student).
# Usage: tool/site_screens.sh <device-id>. Output lands in build/screens/.
set -euo pipefail
cd "$(dirname "$0")/.."
tool/flutter drive --driver test_driver/integration_test.dart \
  --target integration_test/site_screens_test.dart -d "$1"
