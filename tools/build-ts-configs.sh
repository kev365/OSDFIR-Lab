#!/usr/bin/env bash
set -euo pipefail

TS_REF="${TS_REF:-master}"
DFIQ_REF="${DFIQ_REF:-main}"
CUSTOM_DIR="${CUSTOM_DIR:-configs/timesketch}"
OUT_FILE="${OUT_FILE:-helm-addons/files/ts-configs.tgz.b64}"

WORK="$(mktemp -d)"
TIMESKETCH_DIR="$WORK/timesketch"
mkdir -p "$TIMESKETCH_DIR"

# 1) Upstream Timesketch data/
git clone --depth 1 --branch "$TS_REF" https://github.com/google/timesketch "$WORK/ts"
cp -a "$WORK/ts/data/." "$TIMESKETCH_DIR/"
rm -rf "$WORK/ts"

# 2) Upstream DFIQ data/
git clone --depth 1 --branch "$DFIQ_REF" https://github.com/google/dfiq "$WORK/dfiq"
mkdir -p "$TIMESKETCH_DIR/dfiq"
cp -a "$WORK/dfiq/dfiq/data/." "$TIMESKETCH_DIR/dfiq/"
rm -rf "$WORK/dfiq"

# 3) Your overrides (wins) - Copy files directly to TIMESKETCH_DIR
if [ -d "$CUSTOM_DIR" ]; then
  # Copy all files from custom directory directly to TIMESKETCH_DIR
  cp -a "$CUSTOM_DIR"/* "$TIMESKETCH_DIR/" 2>/dev/null || true
fi

# 4) Tar+base64 - Tar the contents of timesketch directory, not the directory itself
pushd "$TIMESKETCH_DIR" >/dev/null
tar -czf "$WORK/ts-configs.tgz" .
popd >/dev/null

# Create base64 version
pushd "$WORK" >/dev/null
base64 -w0 ts-configs.tgz > ts-configs.tgz.b64
popd >/dev/null

mkdir -p "$(dirname "$OUT_FILE")"
mv "$WORK/ts-configs.tgz.b64" "$OUT_FILE"

echo "Wrote $(du -h "$OUT_FILE" | awk '{print $1" "$2}'): $OUT_FILE"
