#!/usr/bin/env bash
# Two-device sync check against a local zonai server (server/README.md).
# Usage: tool/sync_e2e.sh <device-A> <device-B>
#
# Plays integration_test/sync_two_device_test.dart as writer on A, reader on
# B, then checker on A. Both apps are uninstalled first, so each leg starts
# from a fresh install; A keeps its session between writer and checker.
# Screenshots land in build/sync_e2e/. The run passes only if every leg
# passes AND the two devices end up holding the same data. Each leg's own
# assertions are about the device it runs on; the script is what compares
# the two devices.
set -euo pipefail
cd "$(dirname "$0")/.."
a="$1"; b="$2"
nonce="$(date +%s)"
email="e2e-$nonce@rubric.test"
out="build/sync_e2e"; rm -rf "$out"; mkdir -p "$out"

# Any HTTP answer at all means a server is listening (/_ redirects to the UI).
code="$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8792/_ || true)"
[ "$code" != "000" ] ||
  { echo "no zonai server on :8792 (see server/README.md)" >&2; exit 1; }

uninstall() {
  if [[ "$1" == emulator-* || "$1" =~ ^[0-9a-f]{10,}$ ]]; then
    adb -s "$1" uninstall com.supposedlysam.rubric >/dev/null 2>&1 || true
  else
    xcrun simctl uninstall "$1" com.supposedlysam.rubric >/dev/null 2>&1 || true
  fi
}

leg() { # device role
  echo "== $2 on $1"
  rm -rf build/screens
  tool/flutter drive --driver test_driver/integration_test.dart \
    --target integration_test/sync_two_device_test.dart -d "$1" \
    --dart-define=ROLE="$2" --dart-define=EMAIL="$email" \
    --dart-define=NONCE="$nonce" >"$out/$2.log" 2>&1 || true
  grep -E "SYNC_E2E|timed out|Expected:|Actual:|nothing to tap" "$out/$2.log" || true
  grep -q "All tests passed" "$out/$2.log" ||
    { echo "$2 leg FAILED (log: $out/$2.log)"; exit 1; }
  if [ -d build/screens ]; then cp build/screens/*.png "$out/" 2>/dev/null || true; fi
}

uninstall "$a"; uninstall "$b"
leg "$a" writer
leg "$b" reader
leg "$a" checker

python3 - "$out" <<'PY'
import json, sys
out = sys.argv[1]
def last(role):
    lines = [l for l in open(f"{out}/{role}.log") if "SYNC_E2E " in l]
    if not lines:
        sys.exit(f"{role} printed no SYNC_E2E line")
    return json.loads(lines[-1].split("SYNC_E2E ", 1)[1])
reader, checker = last("reader"), last("checker")
keys = ["courses", "students", "assignments", "evaluations", "rubrics",
        "snippets", "class_names"]
print("reader :", {k: reader[k] for k in keys})
print("checker:", {k: checker[k] for k in keys})
diff = {k: (reader[k], checker[k]) for k in keys if reader[k] != checker[k]}
work = [r["role"] for r in (reader, checker) if r["pending"] or r["dead"]]
if diff or work:
    sys.exit(f"DEVICES DIFFER {diff} / work left on {work}")
if reader["students"] == 0 or reader["evaluations"] == 0:
    sys.exit("nothing substantial synced (no students or evaluations)")
print("SYNC E2E PASSED: both devices hold the same classroom")
PY
