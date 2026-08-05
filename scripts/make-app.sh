#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Ward"

echo "Building ${APP_NAME} (release)…"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)"
APP_BUNDLE="dist/${APP_NAME}.app"

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp Support/Info.plist "${APP_BUNDLE}/Contents/Info.plist"
cp "Support/${APP_NAME}.icns" "${APP_BUNDLE}/Contents/Resources/${APP_NAME}.icns"
cp "${BIN_PATH}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')"
if [ -n "${SIGNING_IDENTITY}" ]; then
    echo "Signing with identity: ${SIGNING_IDENTITY}"
    codesign --force --options runtime --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}"
else
    echo "No signing identity found — ad-hoc signing."
    echo "(After each rebuild macOS treats the app as new: re-grant Accessibility.)"
    codesign --force --sign - "${APP_BUNDLE}"
fi

echo
echo "Done: ${APP_BUNDLE}"
echo "Launch with:  open ${APP_BUNDLE}"
echo "Launch the bundle, not 'swift run', so the Accessibility grant attaches to Ward."
