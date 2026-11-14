#!/usr/bin/env bash
# Build the Soundisle Go sidecar used by the desktop Flutter shells.
#
#   ./scripts/build_backend.sh              # build for the host platform
#   GOOS=windows ./scripts/build_backend.sh # cross compile
#
# The binary is written to backend/bin/soundisle-core (or .exe on Windows).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT/backend/bin"
NAME="soundisle-core"
if [[ "${GOOS:-$(go env GOOS)}" == "windows" ]]; then
  NAME="soundisle-core.exe"
fi

mkdir -p "$OUT_DIR"
cd "$ROOT/backend"
go build -trimpath -ldflags "-s -w" -o "$OUT_DIR/$NAME" .

echo "built $OUT_DIR/$NAME"
