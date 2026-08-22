#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# One shellcheck, one version, in CI and on a laptop.
#
# CI used to `apt-get install shellcheck`, which on ubuntu-latest is 0.9.0,
# while `brew install shellcheck` gets whatever is current. The two disagree:
# 0.9.0 raises SC2120 for a function whose only argument-passing call site goes
# through a dispatcher, and 0.11.0 does not. A tree that linted clean locally
# went red on the runner. That is the harmless direction — the other one is a
# check that quietly stopped running because the local copy was newer and had
# dropped a diagnostic the runner still had.
#
# So the version is pinned, by checksum, the way the formula pins its tarball.
# The file list lives here too, so a workflow edit cannot silently lint less
# than a developer does.

SHELLCHECK_VERSION="0.11.0"
SEVERITY="warning"

# packaging/homebrew/ward is named separately because it is spelled the way a
# user types it — no .sh for the glob to find — and of every shell script here
# it is the only one that installs onto other people's machines.
TARGETS=(scripts/*.sh packaging/homebrew/ward)

die() {
    sed -e '1s/^/shellcheck.sh: /' -e '2,$s/^/               /' >&2
    exit 1
}

# `--version` prints a block; the line that matters is `version: X.Y.Z`.
version_of() {
    "$1" --version 2>/dev/null | awk '/^version:/ { print $2; exit }'
}

sha256_of() {
    if command -v shasum > /dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{ print $1 }'
    else
        sha256sum "$1" | awk '{ print $1 }'
    fi
}

# Checksums are GitHub's published digests for the v0.11.0 assets, re-derived
# from the downloaded tarball before being written down rather than copied on
# trust. 0.9.0 is deliberately not an option to pin back to: it shipped no
# darwin.aarch64 asset at all, so an Apple silicon machine could not run it.
case "$(uname -s)/$(uname -m)" in
    Darwin/arm64)
        PLATFORM="darwin.aarch64"
        EXPECTED_SHA256="339b930feb1ea764467013cc1f72d09cd6b869ebf1013296ba9055ab2ffbd26f"
        ;;
    Darwin/x86_64)
        PLATFORM="darwin.x86_64"
        EXPECTED_SHA256="c2c15e08df0e8fbc374c335b230a7ee958c313fa5714817a59aa59f1aa594f51"
        ;;
    Linux/aarch64)
        PLATFORM="linux.aarch64"
        EXPECTED_SHA256="68a8133197a50beb8803f8d42f9908d1af1c5540d4bb05fdfca8c1fa47decefc"
        ;;
    Linux/x86_64)
        PLATFORM="linux.x86_64"
        EXPECTED_SHA256="b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6"
        ;;
    *)
        die <<EOF
no pinned shellcheck ${SHELLCHECK_VERSION} for $(uname -s)/$(uname -m).
Add that platform's asset name and checksum to the case above, from
  https://github.com/koalaman/shellcheck/releases/tag/v${SHELLCHECK_VERSION}
EOF
        ;;
esac

CACHE_DIR="${HOME}/.cache/ward-shellcheck/${SHELLCHECK_VERSION}"
CACHED_BIN="${CACHE_DIR}/shellcheck"

# Set by the tests to point the version guard below at a binary of their
# choosing. It cannot weaken that guard — whatever it names is still held to the
# pin — which is the whole reason it can exist safely.
SHELLCHECK_BIN="${WARD_SHELLCHECK_BIN:-}"

if [ -z "${SHELLCHECK_BIN}" ]; then
    if command -v shellcheck > /dev/null 2>&1 &&
        [ "$(version_of "$(command -v shellcheck)")" = "${SHELLCHECK_VERSION}" ]; then
        # Already the pinned version — no download, no cache, nothing to clean.
        SHELLCHECK_BIN="$(command -v shellcheck)"
    elif [ -x "${CACHED_BIN}" ] && [ "$(version_of "${CACHED_BIN}")" = "${SHELLCHECK_VERSION}" ]; then
        SHELLCHECK_BIN="${CACHED_BIN}"
    else
        URL="https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.${PLATFORM}.tar.gz"
        echo "Fetching shellcheck ${SHELLCHECK_VERSION} (${PLATFORM})…"

        # .tar.gz rather than the .tar.xz these releases also carry: xz needs a
        # tool that is not guaranteed on a minimal runner, and gzip is. Bumping
        # the pin below 0.11.0 would break this — those releases published only
        # .tar.xz.
        WORK="$(mktemp -d "${TMPDIR:-/tmp}/ward-shellcheck.XXXXXX")"
        trap 'rm -rf "${WORK}"' EXIT

        if ! curl --fail --silent --show-error --location \
            --output "${WORK}/shellcheck.tar.gz" "${URL}"; then
            die <<EOF
could not download ${URL}
Linting was not run. If this machine is offline, so be it — but a lint that
skipped itself must not look like a lint that passed.
EOF
        fi

        DOWNLOADED_SHA256="$(sha256_of "${WORK}/shellcheck.tar.gz")"
        if [ "${DOWNLOADED_SHA256}" != "${EXPECTED_SHA256}" ]; then
            die <<EOF
${URL}
hashes to ${DOWNLOADED_SHA256}, not the pinned ${EXPECTED_SHA256}.
Refusing to run it. Nothing was installed.
EOF
        fi

        tar xzf "${WORK}/shellcheck.tar.gz" -C "${WORK}"
        mkdir -p "${CACHE_DIR}"
        mv "${WORK}/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" "${CACHED_BIN}"
        chmod +x "${CACHED_BIN}"
        SHELLCHECK_BIN="${CACHED_BIN}"
    fi
fi

# The guard the rest of this exists to reach. Every branch above believes it
# produced the pinned version; this is the only line that checks, and it runs
# whichever branch was taken.
RESOLVED_VERSION="$(version_of "${SHELLCHECK_BIN}")"
if [ "${RESOLVED_VERSION}" != "${SHELLCHECK_VERSION}" ]; then
    die <<EOF
${SHELLCHECK_BIN} reports version '${RESOLVED_VERSION}', not ${SHELLCHECK_VERSION}.
Refusing to lint with a version CI does not use — that drift is what this
script exists to stop.
EOF
fi

echo "shellcheck ${RESOLVED_VERSION} — ${SHELLCHECK_BIN}"
"${SHELLCHECK_BIN}" --severity="${SEVERITY}" "${TARGETS[@]}"
echo "clean: ${#TARGETS[@]} targets"
