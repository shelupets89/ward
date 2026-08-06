#!/usr/bin/env bash
set -euo pipefail

# The formula is never hand-edited: its url and sha256 describe one specific
# release tarball, and a checked-in checksum is either redundant or wrong. The
# template holds everything a human writes; this fills in the two lines only a
# tag can answer.

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <tag> <output-path>" >&2
    exit 2
fi

TAG="$1"
OUTPUT_PATH="$2"

# The tag lands inside a sed replacement whose delimiter is `|`, and git permits
# that character in a tag name. Rejecting it here turns a baffling "bad flag in
# substitute command" into a sentence that names the problem.
case "${TAG}" in
    *[!A-Za-z0-9._-]*)
        echo "error: refusing tag '${TAG}' — expected only letters, digits, dot, underscore or dash" >&2
        exit 2
        ;;
esac

cd "$(dirname "$0")/.."

TEMPLATE="packaging/homebrew/ward.rb.template"
TARBALL_URL="https://github.com/shelupets89/ward/archive/refs/tags/${TAG}.tar.gz"

echo "Fetching ${TARBALL_URL}…"
# GNU mktemp needs the Xs spelled out; only BSD mktemp invents them from a bare
# prefix. Written the portable way so moving a job to a Linux runner doesn't
# break a script shellcheck cannot flag.
TARBALL="$(mktemp "${TMPDIR:-/tmp}/ward-formula-tarball.XXXXXX")"
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
