#!/usr/bin/env bash
# The same gate CI runs (.github/workflows/ci.yaml): format check, analyze with
# infos fatal over the whole tree, full test suite. Run before every commit.
set -euo pipefail
cd "$(dirname "$0")/.."
tool/flutter pub get > /dev/null
tool/flutter analyze --fatal-infos
tool/flutter test

# Local packages
for pkg in packages/*/; do
  [ -f "$pkg/pubspec.yaml" ] || continue
  (cd "$pkg" && ../../tool/dart pub get > /dev/null && ../../tool/dart analyze --fatal-infos && ../../tool/dart test)
done

# The zonai backend
(cd server && ../tool/dart pub get > /dev/null && ../tool/dart analyze --fatal-infos)
