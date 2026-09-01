#!/usr/bin/env bash
#
# Builds a seeded database on this machine and installs it on a connected
# device, replacing whatever that device currently holds.
#
#   tool/seed_device.sh 20            # 20 years, default seed
#   tool/seed_device.sh 20 7          # …with seed 7, so the data is repeatable
#
# `tool/seed_years.dart` remains the honest path for a real phone: it writes a
# backup file, and the person restores it through Settings. This exists for an
# emulator, where decoding a large file inside the app is impractically slow.
# The rows still go through the app's own importer — see
# tool/test/seed_device_test.dart — so a file the app would reject is rejected
# here too.
#
# Requires a debuggable build on the device, because the app's data directory is
# only reachable through `run-as`.

set -euo pipefail

years="${1:-20}"
seed="${2:-7}"
package="com.deltoid.deltoid"
db="/data/data/$package/app_flutter/deltoid.sqlite"
staged="/data/local/tmp/deltoid-seed.sqlite"
out="build/deltoid-seed-${years}y.sqlite"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

echo "Building $years years of history…"
SEED_YEARS="$years" SEED_SEED="$seed" SEED_OUT="$out" \
  flutter test tool/test/seed_device_test.dart

echo "Installing on the device…"
adb shell am force-stop "$package"
adb push "$out" "$staged" > /dev/null

# The write-ahead log and shared-memory file must go with the database they
# belong to. A stale -wal left beside a replaced database reports the old
# contents, which looks exactly like a copy that silently failed.
adb shell "run-as $package sh -c 'cat $staged > $db; rm -f $db-wal $db-shm'"
adb shell rm -f "$staged"

echo -n "Workouts now on the device: "
adb shell "run-as $package sqlite3 $db 'select count(*) from workouts'"
echo "Launch with: adb shell am start -n $package/.MainActivity"
