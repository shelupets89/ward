#!/usr/bin/env bash
set -euo pipefail

# The formula is never hand-edited: its url and sha256 describe one specific
# release tarball, and a checked-in checksum is either redundant or wrong. The
# template holds everything a human writes; this fills in the two lines only a
# tag can answer.
#
# Two sources for that tarball, one renderer. A tag is fetched from GitHub —
# what a release publishes. A local tarball covers CI proving *this commit*
# installs, where no tag exists yet. CI used to inline its own `sed` for that,
# so the formula it audited and the formula it installed were produced by two
# implementations of the same substitution, and only one of them was guarded.

usage() {
    cat >&2 <<EOF
usage: $0 <tag> <output-path>
       $0 --local-tarball <path> <output-path>
EOF
    exit 2
}

# MODE is what the caller asked for, recorded once. Deciding it here and then
# re-deriving it further down from `[ -n "${LOCAL_TARBALL}" ]` would let the two
# disagree: `--local-tarball ""` would take this branch and then fall into the
# tag branch below, fetching whatever TAG happened to be in the environment —
# and release.yml exports one.
MODE=tag
LOCAL_TARBALL=""
if [ "${1:-}" = "--local-tarball" ]; then
    [ "$#" -eq 3 ] || usage
    MODE=local
    LOCAL_TARBALL="$2"
    OUTPUT_PATH="$3"
else
    [ "$#" -eq 2 ] || usage
    TAG="$1"
    OUTPUT_PATH="$2"
fi

cd "$(dirname "$0")/.."

TEMPLATE="packaging/homebrew/ward.rb.template"

if [ "${MODE}" = local ]; then
    # Screened before the file is looked for, like the tag below: a malformed
    # argument is wrong whatever the filesystem says. Same reason as the tag,
    # plus one worse case — `&` on sed's replacement side expands to the whole
    # match, so a path containing one corrupts the url silently rather than
    # failing.
    case "${LOCAL_TARBALL}" in
        *[\|\&\\]*)
            echo "error: refusing tarball path '${LOCAL_TARBALL}' — it contains one of | & \\, which sed would mangle" >&2
            exit 2
            ;;
    esac

    if [ ! -f "${LOCAL_TARBALL}" ]; then
        echo "error: no tarball at ${LOCAL_TARBALL}" >&2
        exit 1
    fi
    TARBALL="${LOCAL_TARBALL}"
    # Homebrew reads the version out of the url's filename, so naming the
    # archive ward-<version>.tar.gz is what lets the formula's own test compare
    # it against Info.plist. That naming is the caller's job.
    TARBALL_URL="file://${LOCAL_TARBALL}"
    echo "Rendering against ${TARBALL_URL}"
else
    # The tag lands inside a sed replacement whose delimiter is `|`, and git
    # permits that character in a tag name. Rejecting it here turns a baffling
    # "bad flag in substitute command" into a sentence that names the problem.
    case "${TAG}" in
        *[!A-Za-z0-9._-]*)
            echo "error: refusing tag '${TAG}' — expected only letters, digits, dot, underscore or dash" >&2
            exit 2
            ;;
    esac

    TARBALL_URL="https://github.com/shelupets89/ward/archive/refs/tags/${TAG}.tar.gz"

    echo "Fetching ${TARBALL_URL}…"
    # GNU mktemp needs the Xs spelled out; only BSD mktemp invents them from a
    # bare prefix. Written the portable way so moving a job to a Linux runner
    # doesn't break a script shellcheck cannot flag.
    TARBALL="$(mktemp "${TMPDIR:-/tmp}/ward-formula-tarball.XXXXXX")"
    trap 'rm -f "${TARBALL}"' EXIT

    if ! curl --fail --silent --show-error --location --output "${TARBALL}" "${TARBALL_URL}"; then
        echo "error: no tarball at ${TARBALL_URL} — is ${TAG} pushed?" >&2
        exit 1
    fi
fi

SHA256="$(shasum -a 256 "${TARBALL}" | awk '{print $1}')"
echo "sha256: ${SHA256}"

# `brew audit` validates that the license stanza is a well-formed SPDX id, never
# that it is true: the cross-check against the repository is gated on `@core_tap`
# and is unreachable for a third-party tap, so `license "MIT"` against a GPL
# project audits clean. This runs on the real tarball in both workflows and
# cannot 404 into a pass, which makes it the one place the claim can be checked.
#
# Listed into a variable rather than piped to `grep -q`: grep exits at the first
# hit, tar takes SIGPIPE, and `pipefail` reports that as a failed pipeline —
# which would read here as "no LICENSE" and fail a release that is perfectly
# fine. Only bites once the listing outgrows the pipe buffer, so it would
# survive every tarball this project has today.
# Anchored to the archive's one top-level directory, which both sources add —
# `git archive --prefix=` here, and GitHub's own convention for a tag tarball.
# A bare `/LICENSE$` would also accept a nested `ThirdParty/LICENSE` while the
# root one was missing, and it is the root one make-app.sh copies.
TARBALL_CONTENTS="$(tar tzf "${TARBALL}")"
if ! grep -q '^[^/]*/LICENSE$' <<< "${TARBALL_CONTENTS}"; then
    echo "error: ${TARBALL_URL} contains no LICENSE, but ${TEMPLATE} claims one" >&2
    exit 1
fi

mkdir -p "$(dirname "${OUTPUT_PATH}")"
sed -e "s|__URL__|${TARBALL_URL}|" -e "s|__SHA256__|${SHA256}|" "${TEMPLATE}" > "${OUTPUT_PATH}"

if grep -q "__URL__\|__SHA256__" "${OUTPUT_PATH}"; then
    echo "error: ${OUTPUT_PATH} still contains placeholders" >&2
    exit 1
fi

# The check above proves only that two tokens are gone, which an empty file also
# manages — `grep -q` over `: > empty.rb` exits 1, so truncation, a failed write
# or the wrong template all passed it and the script still printed "Wrote".
#
# So the render is derived a second time and compared byte for byte. What lands
# on disk has to be the template with exactly these two lines filled in, which
# says what the render *is* rather than what it lacks, and covers every line
# added to the template later — the license stanza included — for free.
#
# Two things this deliberately does not do. It does not substitute the
# placeholders back: that would put TARBALL_URL on sed's *pattern* side, where
# its dots match any character, so a corruption landing on a dot would restore
# cleanly and pass. And it compares with `cmp` rather than two `$(…)` strings,
# because command substitution strips trailing newlines from both sides, which
# would make "byte for byte" untrue of exactly the bytes at the end.
#
# The placeholder grep above still earns its place: this check is blind to a
# placeholder the template itself left behind, since the second derivation
# reproduces it too.
if [ ! -s "${OUTPUT_PATH}" ]; then
    echo "error: ${OUTPUT_PATH} is empty — nothing was rendered" >&2
    exit 1
fi

if ! cmp -s "${OUTPUT_PATH}" \
    <(sed -e "s|__URL__|${TARBALL_URL}|" -e "s|__SHA256__|${SHA256}|" "${TEMPLATE}"); then
    echo "error: ${OUTPUT_PATH} is not ${TEMPLATE} with only the url and sha256 filled in" >&2
    exit 1
fi

echo "Wrote ${OUTPUT_PATH}"
