#!/usr/bin/env bash
# Build the embedded Go music core for mobile platforms with gomobile.
#
#   ./scripts/build_mobile_core.sh android   # -> app/android/app/libs/musiccore.aar
#   ./scripts/build_mobile_core.sh ios       # -> app/ios/Frameworks/MusicCore.xcframework
#
# Requirements:
#   * Go >= 1.26
#   * gomobile + gobind on PATH (go install golang.org/x/mobile/cmd/...@latest)
#   * ANDROID_HOME + ANDROID_NDK_HOME for Android
#   * Xcode for iOS (macOS only)
#
# gomobile needs golang.org/x/mobile in the module graph. The backend go.mod
# keeps it as a tool dependency, so no extra setup is required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-android}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

need go
need gomobile
need gobind

cd "$ROOT/backend"

case "$TARGET" in
  android)
    : "${ANDROID_HOME:?ANDROID_HOME is not set}"
    : "${ANDROID_NDK_HOME:?ANDROID_NDK_HOME is not set}"
    OUT="$ROOT/app/android/app/libs/musiccore.aar"
    mkdir -p "$(dirname "$OUT")"
    # arm64-v8a covers essentially every Android phone still in use. Add
    # android/arm or android/amd64 only for legacy 32-bit devices or emulators.
    gomobile bind \
      -target=android/arm64 \
      -androidapi 24 \
      -javapkg=app.soundisle.core \
      -ldflags "-s -w" \
      -o "$OUT" \
      ./mobile
    echo "built $OUT"
    ;;
  ios)
    OUT="$ROOT/app/ios/Frameworks/MusicCore.xcframework"
    mkdir -p "$(dirname "$OUT")"
    rm -rf "$OUT"
    gomobile bind \
      -target=ios/arm64,ios/amd64 \
      -o "$OUT" \
      ./mobile
    echo "built $OUT"
    ;;
  *)
    echo "usage: $0 [android|ios]" >&2
    exit 2
    ;;
esac
