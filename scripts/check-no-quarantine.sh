#!/usr/bin/env bash
set -euo pipefail

# Asserts an app bundle carries no com.apple.quarantine attribute.
#
# This is the one claim the Homebrew install path exists to make, so the check
# has to fail when it cannot answer — a missing bundle or an unreadable xattr
# both produce no output, and "no output" is indistinguishable from "no
# quarantine attribute" unless the failures are caught separately.
#
# Usage: check-no-quarantine.sh <app-bundle>

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <app-bundle>" >&2
    exit 2
fi

APP_BUNDLE="$1"

if [ ! -d "${APP_BUNDLE}" ]; then
    echo "::error::${APP_BUNDLE} does not exist — the install produced no app bundle." >&2
    exit 1
fi

if ! ATTRIBUTES="$(xattr -r "${APP_BUNDLE}" 2>&1)"; then
    echo "::error::Could not read extended attributes on ${APP_BUNDLE}: ${ATTRIBUTES}" >&2
    exit 1
fi

# Matched in-shell rather than piped to `grep -q`: grep exits at the first hit,
# the write end takes SIGPIPE, and `pipefail` reports that as a failed pipeline
# — which reads as "no match" and passes the check on a bundle that is in fact
# quarantined. Only shows up once the listing is long enough to still be
# writing, so it survives every small test case.
case "${ATTRIBUTES}" in
    *com.apple.quarantine*)
        echo "::error::${APP_BUNDLE} carries com.apple.quarantine — the install path no longer avoids Gatekeeper." >&2
        exit 1
        ;;
esac

echo "No quarantine attribute on ${APP_BUNDLE}"
