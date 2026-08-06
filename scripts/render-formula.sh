#!/usr/bin/env bash
set -euo pipefail

# Renders the Homebrew formula for a released tag.
#
# The formula is never hand-edited: its url and sha256 describe one specific
# release tarball, and a checked-in checksum is either redundant or wrong. The
# template holds everything a human writes; this fills in the two lines only a
# tag can answer.
#
# Usage: render-formula.sh <tag> <output-path>

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <tag> <output-path>" >&2
    exit 2
fi

TAG="$1"
OUTPUT_PATH="$2"

cd "$(dirname "$0")/.."

TEMPLATE="packaging/homebrew/ward.rb.template"
REPO="${WARD_REPO:-shelupets89/ward}"
TARBALL_URL="https://github.com/${REPO}/archive/refs/tags/${TAG}.tar.gz"

echo "Fetching ${TARBALL_URL}…"
TARBALL="$(mktemp -t ward-formula-tarball)"
trap 'rm -f "${TARBALL}"' EXIT

if ! curl --fail --silent --show-error --location --output "${TARBALL}" "${TARBALL_URL}"; then
    echo "error: no tarball at ${TARBALL_URL} — is ${TAG} pushed?" >&2
    exit 1
fi

SHA256="$(shasum -a 256 "${TARBALL}" | awk '{print $1}')"
echo "sha256: ${SHA256}"

mkdir -p "$(dirname "${OUTPUT_PATH}")"
sed -e "s|__URL__|${TARBALL_URL}|" -e "s|__SHA256__|${SHA256}|" "${TEMPLATE}" > "${OUTPUT_PATH}"

if grep -q "__URL__\|__SHA256__" "${OUTPUT_PATH}"; then
    echo "error: ${OUTPUT_PATH} still contains placeholders" >&2
    exit 1
fi

echo "Wrote ${OUTPUT_PATH}"
