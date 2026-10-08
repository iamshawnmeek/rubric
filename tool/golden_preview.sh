#!/usr/bin/env bash
# Renders every golden test to build/golden_preview/ to look at, without
# comparing anything and without touching the committed baselines. Those
# come only from the "Golden baselines" workflow on a pinned Linux image
# (.github/workflows/goldens.yaml); a Mac renders text slightly differently.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf build/golden_preview
RUBRIC_GOLDEN_PREVIEW=1 tool/flutter test test/goldens --run-skipped --tags golden "$@"
echo "golden preview: build/golden_preview/goldens ($(find build/golden_preview -name '*.png' | wc -l | tr -d ' ') images)"
