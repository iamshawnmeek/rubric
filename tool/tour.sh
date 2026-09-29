#!/usr/bin/env bash
# Runs the on-device tour (integration_test/tour_test.dart) and writes
# screenshots to build/screens/. Usage: tool/tour.sh <device-id>
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf build/screens
tool/flutter drive --driver test_driver/integration_test.dart \
  --target integration_test/tour_test.dart -d "$1"
