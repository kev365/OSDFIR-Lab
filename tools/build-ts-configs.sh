#!/usr/bin/env bash
set -euo pipefail

TS_REF="${TS_REF:-master}"
DFIQ_REF="${DFIQ_REF:-main}"
CUSTOM_DIR="${CUSTOM_DIR:-configs/timesketch}"
OUT_FILE="${OUT_FILE:-helm-addons/files/ts-configs.tgz.b64}"

WORK="$(mktemp -d)"
ETC="$WORK/etc/timesketch"
mkdir -p "$ETC"

# 1) Upstream Timesketch data/
git clone --depth 1 --branch "$TS_REF" https://github.com/google/timesketch "$WORK/ts"
cp -a "$WORK/ts/data/." "$ETC/"
rm -rf "$WORK/ts"

# 2) Upstream DFIQ data/
git clone --depth 1 --branch "$DFIQ_REF" https://github.com/google/dfiq "$WORK/dfiq"
mkdir -p "$ETC/dfiq"
cp -a "$WORK/dfiq/dfiq/data/." "$ETC/dfiq/"
rm -rf "$WORK/dfiq"

# 3) Your overrides (wins)
if [ -d "$CUSTOM_DIR" ]; then
  cp -a "$CUSTOM_DIR/." "$ETC/"
fi

# 4) Tar+base64
pushd "$WORK" >/dev/null
tar -czf ts-configs.tgz etc
base64 -w0 ts-configs.tgz > "$(pwd)/ts-configs.tgz.b64"
popd >/dev/null

mkdir -p "$(dirname "$OUT_FILE")"
mv "$WORK/ts-configs.tgz.b64" "$OUT_FILE"

echo "Wrote $(du -h "$OUT_FILE" | awk '{print $1" "$2}'): $OUT_FILE"
