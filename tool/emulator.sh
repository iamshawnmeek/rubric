#!/usr/bin/env bash
# Starts or stops rubric-owner's Android emulator (AVD rubric_owner_pixel,
# port 5580). This is the only supported way to run it.
#
#   tool/emulator.sh start    boot it (hardware GPU) and wait until ready
#   tool/emulator.sh stop     shut it down
#
# Hardware rendering only (-gpu host). On 2026-10-01 it was started headless
# with -gpu swiftshader_indirect after a Vulkan crash. Software rendering
# then burned about 5 CPU cores for two days and pushed the shared machine's
# load to 15-50, stalling other agents' emulators. Stop it when a run is
# done: an idle emulator still costs the whole machine.
set -euo pipefail
emulator="$HOME/Library/Android/sdk/emulator/emulator"
serial=emulator-5580

case "${1:-}" in
  start)
    if adb -s "$serial" get-state >/dev/null 2>&1; then echo "already running"; exit 0; fi
    nohup "$emulator" -avd rubric_owner_pixel -port 5580 -gpu host \
      -no-snapshot-save -no-boot-anim >/tmp/rubric_owner_pixel.log 2>&1 &
    for _ in $(seq 1 120); do
      [ "$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] &&
        { echo "booted $serial"; exit 0; }
      sleep 3
    done
    echo "emulator did not boot; see /tmp/rubric_owner_pixel.log" >&2; exit 1 ;;
  stop)
    adb -s "$serial" emu kill 2>/dev/null || echo "not running" ;;
  *)
    echo "usage: tool/emulator.sh start|stop" >&2; exit 64 ;;
esac
