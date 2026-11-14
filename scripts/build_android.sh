#!/usr/bin/env bash
# One-shot Android build: embedded Go core + Flutter APK.
#
#   ./scripts/build_android.sh            # debug APK
#   ./scripts/build_android.sh release    # release APK (debug signing by default)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-debug}"

"$ROOT/scripts/build_mobile_core.sh" android

cd "$ROOT/app"
if [[ "$MODE" == "release" ]]; then
  flutter build apk --release
else
  flutter build apk --debug
fi
