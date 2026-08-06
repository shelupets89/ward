#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Ward"

# SwiftPM evaluates Package.swift inside its own sandbox-exec sandbox. The
# Homebrew formula already builds inside one, and the kernel refuses to nest
# them — "sandbox_apply: Operation not permitted", surfacing as an unexplained
# "Invalid manifest". The formula sets this to opt out of the inner sandbox.
SANDBOX_FLAGS=()
if [ -n "${WARD_DISABLE_SWIFTPM_SANDBOX:-}" ]; then
    SANDBOX_FLAGS+=(--disable-sandbox)
fi

# `${arr[@]+"${arr[@]}"}` rather than plain `"${arr[@]}"`: macOS still ships
# bash 3.2, where expanding an empty array under `set -u` aborts the script.
# Collapsing this back to the obvious form breaks every build that doesn't set
# the variable above — which is all of them except Homebrew's.

echo "Building ${APP_NAME} (release)…"
swift build -c release "${SANDBOX_FLAGS[@]+"${SANDBOX_FLAGS[@]}"}"

BIN_PATH="$(swift build -c release --show-bin-path "${SANDBOX_FLAGS[@]+"${SANDBOX_FLAGS[@]}"}")"
APP_BUNDLE="dist/${APP_NAME}.app"

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp Support/Info.plist "${APP_BUNDLE}/Contents/Info.plist"
cp "Support/${APP_NAME}.icns" "${APP_BUNDLE}/Contents/Resources/${APP_NAME}.icns"
cp "${BIN_PATH}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# MIT asks that the notice travel with every copy, and every channel ships this
# bundle — the DMG stages it, the formula installs it. It has to precede
# signing: `codesign --verify --strict`, which the formula's test runs, rejects
# a file added to a sealed bundle.
cp LICENSE "${APP_BUNDLE}/Contents/Resources/LICENSE"

# `security` reaches for the login keychain, which isn't there over SSH or on a
# CI runner. Under `pipefail` its failure would abort the script before the
# ad-hoc fallback below — the opposite of what this block is for — so its exit
# status is caught rather than propagated, and the error is reported rather
# than discarded.
IDENTITY_LIST=""
if ! IDENTITY_LIST="$(security find-identity -v -p codesigning 2>&1)"; then
    echo "Could not read the keychain, so no signing identity is available:"
    echo "${IDENTITY_LIST}"
    IDENTITY_LIST=""
fi
SIGNING_IDENTITY="$(printf '%s\n' "${IDENTITY_LIST}" | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')"
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
