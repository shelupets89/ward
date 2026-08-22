#!/usr/bin/env bash
set -uo pipefail

# The guards in release-tag.sh only ever fire when a release is going wrong,
# which is never during a normal one. So none of them would run in CI on the
# happy path, and a guard that quietly stopped guarding — an inverted
# comparison, a regex that matches everything — would be discovered by a bad
# release rather than by a red build.
#
# Each case below therefore drives it at a scratch repository with tags chosen
# to reach one guard. Plain bash, no framework, runs on Linux — which is also
# where the real workflow cannot run it, since PlistBuddy is macOS-only and the
# version arrives as an argument for exactly that reason.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${SCRIPT_DIR}/release-tag.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/release-tag-tests.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

PASSED=0
FAILED=0
CASE_SERIAL=0

# A throwaway repository per case, so one case's tags cannot decide another's.
new_repo() {
    CASE_SERIAL=$((CASE_SERIAL + 1))
    REPO="${WORK}/repo-${CASE_SERIAL}"
    mkdir -p "${REPO}"
    git -C "${REPO}" init --quiet
    git -C "${REPO}" -c user.email=t@t -c user.name=t commit --quiet --allow-empty -m base
    for tag in "$@"; do
        git -C "${REPO}" tag "${tag}"
    done
}

run_in_repo() {
    ( cd "${REPO}" && bash "${SCRIPT}" "$@" )
}

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

echo "# the version it was handed"
new_repo v0.3.0
expect "rejects a version that is not three numbers" rejects "is not a version this can tag" \
    run_in_repo 0.3
expect "rejects a version with a suffix" rejects "is not a version this can tag" \
    run_in_repo 0.3.1-beta
# `[ 08 -gt 7 ]` is an error in some shells, so a version the comparison cannot
# handle has to be refused before it reaches the comparison.
expect "rejects leading zeros rather than comparing them" rejects "is not a version this can tag" \
    run_in_repo 0.03.1
expect "rejects no arguments" rejects "usage:" run_in_repo
expect "rejects two arguments" rejects "usage:" run_in_repo 0.3.1 0.3.2

echo
echo "# whether there is anything to do"
new_repo v0.3.0
expect "says nothing to do when the version is already tagged" accepts "already exists" \
    run_in_repo 0.3.0
new_repo v0.3.0
expect "tags a version ahead of the newest release" accepts "is new and ahead of 0.3.0" \
    run_in_repo 0.3.1
new_repo
expect "tags the first release, with nothing to compare against" accepts "nothing released yet" \
    run_in_repo 0.1.0

echo
echo "# refusing to go backwards"
new_repo v0.3.0 v0.2.0 v0.1.0
expect "refuses a version older than the newest release" rejects "is not newer than the released 0.3.0" \
    run_in_repo 0.2.5
# "Equal to the newest release" is unreachable, and worth pinning as such: a
# version equal to the newest tag *is* that tag, so idempotence answers first and
# the backwards guard never sees it. An earlier version of this suite asserted a
# refusal here and failed, because the script was right and the case was not.
new_repo v0.2.0 v0.3.0
expect "answers 'already tagged' before it ever weighs going backwards" accepts "already exists" \
    run_in_repo 0.3.0

# A tag deleted with the version left in place: the newest release is now older,
# so re-tagging restores it rather than going backwards. Deliberate — this is how
# a mistakenly deleted tag is recovered.
new_repo v0.2.0 v0.3.0
git -C "${REPO}" tag -d v0.3.0 > /dev/null
expect "re-tags a version whose tag was deleted" accepts "is new and ahead of 0.2.0" \
    run_in_repo 0.3.0

# Lexicographically "0.9.0" sorts after "0.10.0", so a string comparison here
# would call 0.10.0 the older one and wave 0.9.1 through as a new release.
new_repo v0.9.0 v0.10.0
expect "compares by number, not as text" rejects "is not newer than the released 0.10.0" \
    run_in_repo 0.9.1
new_repo v0.9.0 v0.10.0
expect "and still accepts a genuine bump past the numeric newest" accepts "is new and ahead of 0.10.0" \
    run_in_repo 0.10.1

echo
echo "# what it reports to the workflow"
new_repo v0.3.0
OUTPUT_FILE="${WORK}/gh-output"
: > "${OUTPUT_FILE}"
( cd "${REPO}" && GITHUB_OUTPUT="${OUTPUT_FILE}" bash "${SCRIPT}" 0.3.1 ) > /dev/null
check "  reports should-tag=true" grep -qx "should-tag=true" "${OUTPUT_FILE}"
check "  reports the tag it decided on" grep -qx "tag=v0.3.1" "${OUTPUT_FILE}"

new_repo v0.3.0
: > "${OUTPUT_FILE}"
( cd "${REPO}" && GITHUB_OUTPUT="${OUTPUT_FILE}" bash "${SCRIPT}" 0.3.0 ) > /dev/null
check "  reports should-tag=false when already tagged" grep -qx "should-tag=false" "${OUTPUT_FILE}"
# A workflow gating on should-tag alone would push an empty tag name if this
# leaked through, so the absence matters as much as the presence.
check "  and names no tag to push" test "$(grep -c '^tag=' "${OUTPUT_FILE}")" -eq 0

echo
printf '%s passed, %s failed\n' "${PASSED}" "${FAILED}"
[ "${FAILED}" -eq 0 ]
