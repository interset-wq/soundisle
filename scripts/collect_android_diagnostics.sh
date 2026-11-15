#!/usr/bin/env bash
# Collect Android diagnostics for Soundisle (声屿).
#
#   ./scripts/collect_android_diagnostics.sh [output-dir]
#
# Requires: adb on PATH, one authorized device connected over USB/Wi-Fi.
# The script never modifies app data; it only reads system state and logs.
set -u

PKG="app.soundisle.music"
OUT="${1:-soundisle-diag-$(date +%Y%m%d-%H%M%S)}"

if ! command -v adb >/dev/null 2>&1; then
  echo "error: adb not found. Install Android platform-tools and add it to PATH." >&2
  exit 1
fi

if [ "$(adb get-state 2>/dev/null)" != "device" ]; then
  echo "error: no authorized device. Enable USB debugging and accept the prompt on the phone." >&2
  adb devices >&2
  exit 1
fi

mkdir -p "$OUT"

collect() {
  local name="$1"
  shift
  {
    echo "# command: $*"
    echo "# collected: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo
    "$@"
  } >"$OUT/$name" 2>&1 || true
}

echo "collecting into $OUT ..."

collect device.txt adb shell getprop
collect version.txt adb shell dumpsys package "$PKG"
collect process.txt adb shell pidof "$PKG"
collect activity.txt adb shell dumpsys activity activities
collect media-session.txt adb shell dumpsys media_session
collect notifications.txt adb shell dumpsys notification
collect audio.txt adb shell dumpsys audio
collect crash.txt adb logcat -d -b crash -v threadtime
collect logcat-full.txt adb logcat -d -v threadtime

# Package-specific and framework lines that matter for playback/download bugs.
adb logcat -d -v threadtime 2>/dev/null |
  grep -iE "flutter|soundisle|goLog|just_audio|audio_service|AndroidRuntime|MediaStore|exportAudio|ActivityManager.*soundisle" \
  >"$OUT/logcat-key.txt" 2>/dev/null || true

# Files exported to the shared music collection.
adb shell "ls -l '/sdcard/Music/声屿'" >"$OUT/music-files.txt" 2>&1 || true
adb shell "content query --uri content://media/external/audio/media --projection _display_name:relative_path" 2>/dev/null |
  grep -i "声屿" >"$OUT/media-store-soundisle.txt" 2>/dev/null || true

# Current screen; ignore failures on locked devices.
adb exec-out screencap -p >"$OUT/screenshot.png" 2>/dev/null || rm -f "$OUT/screenshot.png"

cat >"$OUT/README.txt" <<EOF
Soundisle diagnostics
=====================
Collected: $(date '+%Y-%m-%d %H:%M:%S %z')
Package:   $PKG
Output:    $OUT

Contents
--------
device.txt                System properties / model / Android version
version.txt               Installed package version and path
process.txt               PID (empty = app not running)
activity.txt              Current activity stack
media-session.txt         Media session / lock-screen controls
notifications.txt         Posted notifications
audio.txt                 Audio focus and output state
logcat-full.txt           Full logcat buffer at collection time
logcat-key.txt            Filtered playback/download/Flutter lines
crash.txt                 Crash buffer
music-files.txt           Files under /sdcard/Music/声屿
media-store-soundisle.txt MediaStore rows matching 声屿
screenshot.png            Screen at collection time (if available)

Before sending
--------------
1. Reproduce the bug, then run this script immediately.
2. Add a short note: page, song (name/artist/source), network type, frequency.
3. Zip this folder and attach it to the report.
EOF

if command -v zip >/dev/null 2>&1; then
  zip -qr "$OUT.zip" "$OUT" && echo "done: $OUT.zip"
else
  echo "done: $OUT (zip not installed; attach the folder)"
fi
