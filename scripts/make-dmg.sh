#!/usr/bin/env bash
# Build a distributable disk image containing Ward.app.
#
# The DMG is only a container — it does not change Ward's signing status. An
# ad-hoc signed app still trips Gatekeeper on the receiving Mac; see the
# Read Me First file this script stages into the image.
#
# Usage: bash scripts/make-dmg.sh

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Ward"
APP_BUNDLE="dist/${APP_NAME}.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Support/Info.plist)"
DMG_PATH="dist/${APP_NAME}-${VERSION}.dmg"

bash scripts/make-app.sh > /dev/null
echo "Built ${APP_BUNDLE}"

STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "${STAGING_DIR}"' EXIT

cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

cat > "${STAGING_DIR}/Read Me First.txt" <<'GUIDE'
Ward — first run
================

0. THE .DMG ITSELF WILL BE BLOCKED FIRST.

   macOS says: "Apple could not verify Ward-x.y.z.dmg is free of malware."
   That dialog offers only "Move to Trash" and "Done" — there is no Open button
   in it. This is expected: Ward is not notarized (that needs a paid Apple
   Developer ID). It is not a sign that anything is wrong with the file.

   Two ways past it, pick one:

   a) Terminal, one command:
        xattr -d com.apple.quarantine ~/Downloads/Ward-*.dmg
      Then open the .dmg normally.

   b) No Terminal: click Done, then open
        System Settings -> Privacy & Security -> scroll to Security
      The blocked file is listed there with an "Open Anyway" button.

   Either way you are consciously telling macOS to trust a file it cannot
   verify. Only do that because you trust whoever sent it to you.

1. Drag Ward to the Applications folder.

2. Open it. The same block may appear once more, now for the app itself. Use
   the same two options as step 0 — for the app the Terminal form is:

        xattr -dr com.apple.quarantine /Applications/Ward.app

   (On macOS 15 and later, Control-clicking the app and choosing Open no longer
   bypasses Gatekeeper. System Settings is the only click-through route.)

3. Ward lives in the menu bar, not the Dock. Look for the bubbles icon.

4. Cleaning Mode needs Accessibility access. Click "Start Cleaning Mode" once;
   Ward will prompt and appear in System Settings -> Privacy & Security ->
   Accessibility. Enable it there, then click Start Cleaning Mode again.
   Exit cleaning mode by holding the esc key, alone, for 5 seconds.

5. Keep Awake with Lid Closed offers a one-time setup the first time you use it.
   It explains exactly what it changes before changing anything.

Nothing here phones home, and Ward has no network code at all.
GUIDE

hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}" > /dev/null

codesign --force --sign - "${DMG_PATH}" 2>/dev/null || true

# Also written OUTSIDE the image: macOS blocks the unnotarized DMG itself, so
# instructions sealed inside it are unreachable exactly when they are needed.
cp "${STAGING_DIR}/Read Me First.txt" "dist/Ward-${VERSION}-INSTRUCTIONS.txt"

echo "Built ${DMG_PATH} ($(du -h "${DMG_PATH}" | cut -f1))"
echo "Built dist/Ward-${VERSION}-INSTRUCTIONS.txt — send this ALONGSIDE the .dmg."
echo
echo "macOS will block the .dmg on arrival ('Apple could not verify...'). The"
echo "instructions cover it. Only a Developer ID + notarization removes that step."
