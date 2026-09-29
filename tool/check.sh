#!/usr/bin/env bash
# The same gate CI runs (.github/workflows/ci.yaml): format check, analyze with
# infos fatal over the whole tree, full test suite. Run before every commit.
set -euo pipefail
cd "$(dirname "$0")/.."
tool/flutter pub get > /dev/null
tool/flutter analyze --fatal-infos
tool/flutter test
