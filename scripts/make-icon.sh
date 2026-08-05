#!/usr/bin/env bash
# Regenerate Support/Ward.icns from scripts/make-icon.swift.
#
# The .icns is committed so building the app needs no icon step; this script is
# only for changing the icon. Run it after editing the drawing code, and commit
# the result alongside.

set -euo pipefail

cd "$(dirname "$0")/.."

ICONSET_DIR="$(mktemp -d)/Ward.iconset"
trap 'rm -rf "$(dirname "${ICONSET_DIR}")"' EXIT

swift scripts/make-icon.swift "${ICONSET_DIR}"
iconutil --convert icns "${ICONSET_DIR}" --output Support/Ward.icns

echo "Wrote Support/Ward.icns ($(du -h Support/Ward.icns | cut -f1))"
echo "Rebuild the app to see it:  bash scripts/make-app.sh"
