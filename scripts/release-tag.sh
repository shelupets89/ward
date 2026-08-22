#!/usr/bin/env bash
set -euo pipefail

# Decides whether the version in Info.plist still needs a tag, and refuses the
# ways that decision can go wrong.
#
# The version is an argument rather than something this reads, so the decision
# is testable on any machine: PlistBuddy is macOS-only, and every guard below
# would otherwise only ever run on a macOS runner during a real release — which
# is the one situation where finding out it was broken is most expensive.
#
# "Nothing to do" is exit 0 with no tag, not a failure. The workflow runs on
# every change to Info.plist, and most of them are not version bumps.

usage() {
    cat >&2 <<EOF
usage: $0 <version>
       e.g. $0 0.3.1
EOF
    exit 2
}

[ "$#" -eq 1 ] || usage
VERSION="$1"

say() {
    printf '%s\n' "$*"
}

die() {
    sed -e '1s/^/release-tag.sh: /' -e '2,$s/^/                /' >&2
    exit 1
}

# Proper semver numeric identifiers: no leading zeros. That is not pedantry —
# `[ 08 -gt 7 ]` is a "value too great for base" error in some shells, so a
# version this accepts has to be one the comparison below can handle.
SEMVER='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
if ! [[ "${VERSION}" =~ $SEMVER ]]; then
    die <<EOF
'${VERSION}' is not a version this can tag.
Expected three dot-separated numbers with no leading zeros, e.g. 0.3.1.
Info.plist's CFBundleShortVersionString is what this reads, so fix it there.
EOF
fi

TAG="v${VERSION}"

# Idempotence, and the reason this can run on every Info.plist change: a version
# that is already tagged has already been released, so there is nothing to do —
# whatever else changed in that file.
if git rev-parse -q --verify "refs/tags/${TAG}" > /dev/null 2>&1; then
    say "${TAG} already exists — nothing to tag."
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        say "should-tag=false" >> "${GITHUB_OUTPUT}"
    fi
    exit 0
fi

# 0 when $1 is strictly newer than $2.
is_newer() {
    local lhs_major lhs_minor lhs_patch rhs_major rhs_minor rhs_patch
    IFS=. read -r lhs_major lhs_minor lhs_patch <<< "$1"
    IFS=. read -r rhs_major rhs_minor rhs_patch <<< "$2"
    if [ "${lhs_major}" -ne "${rhs_major}" ]; then
        [ "${lhs_major}" -gt "${rhs_major}" ]
        return
    fi
    if [ "${lhs_minor}" -ne "${rhs_minor}" ]; then
        [ "${lhs_minor}" -gt "${rhs_minor}" ]
        return
    fi
    [ "${lhs_patch}" -gt "${rhs_patch}" ]
}

# The newest tag that already exists, by version rather than by date — a tag
# pushed out of order would otherwise decide this.
NEWEST_RELEASED=""
for existing in $(git tag -l 'v*'); do
    candidate="${existing#v}"
    [[ "${candidate}" =~ $SEMVER ]] || continue
    if [ -z "${NEWEST_RELEASED}" ] || is_newer "${candidate}" "${NEWEST_RELEASED}"; then
        NEWEST_RELEASED="${candidate}"
    fi
done

# A bump that goes backwards would publish an older build as the newest release,
# and the formula's livecheck follows GitHub's idea of latest — so the tap would
# start offering it to everyone. Refused rather than tagged.
if [ -n "${NEWEST_RELEASED}" ] && ! is_newer "${VERSION}" "${NEWEST_RELEASED}"; then
    die <<EOF
${VERSION} is not newer than the released ${NEWEST_RELEASED}.
Tagging it would publish an older build as the latest release, and the Homebrew
tap follows that. Nothing was tagged.
EOF
fi

say "${TAG} is new and ahead of ${NEWEST_RELEASED:-nothing released yet}."
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    say "should-tag=true" >> "${GITHUB_OUTPUT}"
    say "tag=${TAG}" >> "${GITHUB_OUTPUT}"
fi
