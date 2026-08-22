#!/usr/bin/env bash
set -uo pipefail

# There is one thing scripts/shellcheck.sh exists to stop: linting with a
# version CI does not use. Every path through it believes it produced the pinned
# version, and only the final guard checks.
#
# (That opening sentence is phrased the long way round on purpose — a comment
# whose first word is "shellcheck" is parsed as a directive, not prose, and
# fails the file with SC1073. Found by this very lint, on this very file.) In normal use that guard never fires, so if it became
# vacuous — an inverted test, a comparison against an empty string — nothing
# would say so, and the drift it was written to catch would be back with the
# script still reporting "clean".
#
# So the guards get exercised directly: a wrong version, a wrong checksum, and a
# platform with no pin at all, each fed in deliberately.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
SCRIPT="${REPO_ROOT}/scripts/shellcheck.sh"
PINNED="$(awk -F'"' '/^SHELLCHECK_VERSION=/ { print $2; exit }' "${SCRIPT}")"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/shellcheck-tests.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

PASSED=0
FAILED=0

expect() {
    local label="$1" expectation="$2" wanted_text="$3"
    shift 3
    local output status verdict
    output="$("$@" 2>&1)"
    status=$?
    verdict=ok
    case "${expectation}" in
        accepts) [ "${status}" -eq 0 ] || verdict="exit ${status}, wanted 0" ;;
        rejects) [ "${status}" -ne 0 ] || verdict="exit 0, wanted non-zero" ;;
    esac
    if [ "${verdict}" = ok ] && ! printf '%s\n' "${output}" | grep -qF "${wanted_text}"; then
        verdict="never said '${wanted_text}'"
    fi
    if [ "${verdict}" = ok ]; then
        PASSED=$((PASSED + 1)); printf 'ok   %s\n' "${label}"
    else
        FAILED=$((FAILED + 1)); printf 'FAIL %s — %s\n' "${label}" "${verdict}"
        printf '%s\n' "${output}" | sed 's/^/       /'
    fi
}

check() {
    local label="$1"
    shift
    if "$@" 2> /dev/null; then
        PASSED=$((PASSED + 1)); printf 'ok   %s\n' "${label}"
    else
        FAILED=$((FAILED + 1)); printf 'FAIL %s\n' "${label}"
    fi
}

# A binary that answers --version however the caller wants, so the guard can be
# shown refusing something specific rather than merely failing to run.
fake_shellcheck() {
    local path="$1" reply="$2"
    cat > "${path}" <<EOF
#!/bin/sh
if [ "\$1" = "--version" ]; then
    printf '%s\n' "${reply}"
fi
exit 0
EOF
    chmod +x "${path}"
}

echo "# the version guard"
fake_shellcheck "${WORK}/old-shellcheck" "version: 0.9.0"
expect "refuses the version CI used to install" rejects "not ${PINNED}" \
    env WARD_SHELLCHECK_BIN="${WORK}/old-shellcheck" bash "${SCRIPT}"

fake_shellcheck "${WORK}/mute-shellcheck" "no version line here"
expect "refuses a binary that reports no version at all" rejects "not ${PINNED}" \
    env WARD_SHELLCHECK_BIN="${WORK}/mute-shellcheck" bash "${SCRIPT}"

# The control. Without it the two refusals above could be passing because the
# script is broken for every input, not because the guard works.
REAL="$(command -v shellcheck 2> /dev/null || true)"
if [ -z "${REAL}" ] || [ "$("${REAL}" --version | awk '/^version:/ { print $2 }')" != "${PINNED}" ]; then
    REAL="${HOME}/.cache/ward-shellcheck/${PINNED}/shellcheck"
fi
if [ -x "${REAL}" ]; then
    expect "accepts the pinned version, so the refusals were the guard" accepts "clean:" \
        env WARD_SHELLCHECK_BIN="${REAL}" bash "${SCRIPT}"
else
    echo "skip (no pinned shellcheck present to use as a control)"
fi

echo
echo "# the checksum guard, reached by doctoring the pin"
DOCTORED_DIR="${WORK}/doctored/scripts"
mkdir -p "${DOCTORED_DIR}"
sed 's/^        EXPECTED_SHA256=.*/        EXPECTED_SHA256="0000000000000000000000000000000000000000000000000000000000000000"/' \
    "${SCRIPT}" > "${DOCTORED_DIR}/shellcheck.sh"
FAKE_HOME="${WORK}/home"
mkdir -p "${FAKE_HOME}"
# An empty HOME means an empty cache, and a PATH without shellcheck means no
# fast path — together they force the download the checksum guards.
expect "refuses a tarball that does not match the pinned checksum" rejects "not the pinned" \
    env HOME="${FAKE_HOME}" PATH=/usr/bin:/bin bash "${DOCTORED_DIR}/shellcheck.sh"
check "  and it installed nothing" test ! -e "${FAKE_HOME}/.cache/ward-shellcheck/${PINNED}/shellcheck"

echo
echo "# a platform with no pin"
FAKE_BIN="${WORK}/fakebin"
mkdir -p "${FAKE_BIN}"
cat > "${FAKE_BIN}/uname" <<'EOF'
#!/bin/sh
case "$1" in
    -s) echo Plan9 ;;
    -m) echo pdp11 ;;
    *) echo Plan9 ;;
esac
EOF
chmod +x "${FAKE_BIN}/uname"
expect "refuses a platform it holds no checksum for" rejects "no pinned shellcheck" \
    env PATH="${FAKE_BIN}:/usr/bin:/bin" bash "${SCRIPT}"

echo
printf '%s passed, %s failed\n' "${PASSED}" "${FAILED}"
[ "${FAILED}" -eq 0 ]
