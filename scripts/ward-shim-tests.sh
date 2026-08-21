#!/usr/bin/env bash
set -uo pipefail

# packaging/homebrew/ward writes a symlink into /Applications, next to whatever
# is already there — a DMG install, a colleague's copy, a link left dangling by
# `brew uninstall`. Its guards decide which of those it may touch, and the
# formula's own `test do` can only ever reach the easy one: a scratch directory
# with nothing in it. Every refusal branch would go unrun there, so a guard that
# became vacuously permissive — an inverted test, a comparison that never
# matches — would keep CI green while `ward` quietly replaced someone's app.
#
# The interesting half of a refusal is also what it did *not* touch, which no
# exit status can show, so these cases assert against the tree afterwards.
#
# Plain bash and no framework, matching the repo's zero-dependency posture. Runs
# on Linux, where the symlink handling this depends on is a different
# implementation than macOS's — `ln -sfn` in particular is spelled the same by
# BSD and GNU ln, and that is worth proving rather than assuming.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
SHIM="${REPO_ROOT}/packaging/homebrew/ward"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ward-shim-tests.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

# Records what it was asked to open, so a case can assert both that the shim
# opened the thing it linked and that a refusal opened nothing at all. Reads its
# log path from the environment because each case gets its own.
FAKE_OPEN="${WORK}/fake-open"
cat > "${FAKE_OPEN}" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "${WARD_TEST_OPEN_LOG}"
EOF
chmod +x "${FAKE_OPEN}"

PASSED=0
FAILED=0
CASE_SERIAL=0

# A fresh tree per case: a leftover link from an earlier one could stand in for
# a link this run never made.
new_case() {
    CASE_SERIAL=$((CASE_SERIAL + 1))
    CASE_DIR="${WORK}/case-${CASE_SERIAL}"
    KEG_APP="${CASE_DIR}/keg/Ward.app"
    APPS="${CASE_DIR}/Applications"
    LINK="${APPS}/Ward.app"
    OPEN_LOG="${CASE_DIR}/open.log"
    mkdir -p "${KEG_APP}/Contents/MacOS" "${APPS}"
    printf 'the keg build\n' > "${KEG_APP}/Contents/MacOS/Ward"
    : > "${OPEN_LOG}"
}

# The optional argument overrides the launcher, for the one case that needs a
# failing one. Spelled as a default rather than a second copy of this wiring, so
# there is only one place the four variables can drift out of step.
#
# The one call that passes it goes through `expect`, which invokes its trailing
# arguments as a command — so no call site names `run_shim` with an argument in
# a way shellcheck can follow, and 0.9.0 (CI's version) reports SC2120. 0.11.0
# no longer does, which is exactly why this needs saying rather than relying on
# whichever shellcheck happens to be on the machine.
# shellcheck disable=SC2120
run_shim() {
    env WARD_APP_PATH="${KEG_APP}" \
        WARD_APPLICATIONS_DIR="${APPS}" \
        WARD_OPEN_COMMAND="${1:-${FAKE_OPEN}}" \
        WARD_TEST_OPEN_LOG="${OPEN_LOG}" \
        bash "${SHIM}"
}

# Asserts the exit status and that the message names the problem — a guard that
# fires with the wrong explanation sends the next reader somewhere else.
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
        PASSED=$((PASSED + 1))
        printf 'ok   %s\n' "${label}"
    else
        FAILED=$((FAILED + 1))
        printf 'FAIL %s — %s\n' "${label}" "${verdict}"
        printf '%s\n' "${output}" | sed 's/^/       /'
    fi
}

# Asserts a fact about the tree the run left behind. Separate from `expect`
# because what a refusal leaves alone is the half of its behaviour that no
# message or exit status can demonstrate.
check() {
    local label="$1"
    shift
    if "$@" 2>/dev/null; then
        PASSED=$((PASSED + 1))
        printf 'ok   %s\n' "${label}"
    else
        FAILED=$((FAILED + 1))
        printf 'FAIL %s\n' "${label}"
    fi
}

links_to() {
    [ "$(readlink "$1")" = "$2" ]
}

holds_text() {
    grep -qF "$2" "$1"
}

echo "# the placeholder the formula fills in"
# The counterpart to the formula's `refute_match`: that one proves the installed
# shim no longer holds the placeholder, this one proves the committed shim still
# does. Hardcode a path here and `inreplace` fails the build — loudly, but with
# nothing naming why the token mattered.
expect "the committed shim still carries the token inreplace looks for" accepts "__WARD_APP__" \
    grep -F "__WARD_APP__" "${SHIM}"

echo
echo "# linking into a clean /Applications"
new_case
expect "links Ward when nothing is there" accepts "Linked" run_shim
check "  the result is a symlink" test -L "${LINK}"
check "  it points at the app it was given" links_to "${LINK}" "${KEG_APP}"
check "  and it opened the link it just made" holds_text "${OPEN_LOG}" "${LINK}"

new_case
run_shim > /dev/null 2>&1
# fake-open appends, and new_case truncates only once — so without this the
# check below is satisfied by the priming run's entry and proves nothing about
# the run under test. Verified by mutation: a shim whose `keep` branch exits
# before it opens anything passed this whole suite 25/25 until this line existed.
: > "${OPEN_LOG}"
expect "says so and re-opens when already linked" accepts "already points at this Ward" run_shim
check "  the link is unchanged" links_to "${LINK}" "${KEG_APP}"
check "  and re-running still opens Ward" holds_text "${OPEN_LOG}" "${LINK}"

echo
echo "# links that are already there"
new_case
ln -s "${CASE_DIR}/uninstalled/Ward.app" "${LINK}"
expect "replaces the dangling link brew uninstall leaves behind" accepts "Relinked" run_shim
check "  it now points at the app it was given" links_to "${LINK}" "${KEG_APP}"

# The same directory reached by a second name, which is what a link written
# against the Cellar path looks like once the formula fills in the opt one.
# Retargeting it is the repair that keeps the next `brew upgrade` a no-op.
new_case
ln -s "${CASE_DIR}/keg" "${CASE_DIR}/keg-alias"
ln -s "${CASE_DIR}/keg-alias/Ward.app" "${LINK}"
expect "retargets a link naming the same app the long way round" accepts "Relinked" run_shim
check "  it names the app directly now" links_to "${LINK}" "${KEG_APP}"
check "  it is still a symlink" test -L "${LINK}"
# Without -n, `ln -sf` follows the existing link and writes the new one *inside*
# the old target: Ward.app goes on pointing where it did, and a stray
# Ward.app/Ward.app appears behind it. This is the only case that can catch it,
# because it is the only one where the existing link resolves to a directory.
check "  and nothing was nested inside the old target" test ! -e "${CASE_DIR}/keg/Ward.app/Ward.app"

echo
echo "# what it refuses to touch"
new_case
mkdir -p "${LINK}/Contents/MacOS"
printf 'someone elses build\n' > "${LINK}/Contents/MacOS/Ward"
expect "refuses to replace a real app bundle" rejects "is a real app bundle" run_shim
check "  the bundle it refused is intact" holds_text "${LINK}/Contents/MacOS/Ward" "someone elses build"
check "  and it opened nothing" test ! -s "${OPEN_LOG}"

new_case
OTHER_APP="${CASE_DIR}/elsewhere/Ward.app"
mkdir -p "${OTHER_APP}"
ln -s "${OTHER_APP}" "${LINK}"
expect "refuses to retarget a link pointing at a different app" rejects "already links somewhere else" \
    run_shim
check "  the link still points where it did" links_to "${LINK}" "${OTHER_APP}"
check "  and it opened nothing" test ! -s "${OPEN_LOG}"

echo
echo "# the environment it was handed"
new_case
rm -rf "${CASE_DIR}/keg"
expect "fails when the app path was never filled in" rejects "no app bundle at" run_shim
check "  and it linked nothing" test ! -e "${LINK}"

new_case
rmdir "${APPS}"
expect "fails when there is nowhere to link into" rejects "no directory at" run_shim

# The link is the half that matters and it succeeded, so this must not report a
# failed launch as a failure to install — the message says the link is in place,
# and that claim gets checked rather than trusted.
new_case
expect "reports a launcher that fails" rejects "could not open" run_shim false
check "  and the link it made is still there" links_to "${LINK}" "${KEG_APP}"

# `ln` is the only filesystem write here, and it was the only failure that
# printed a raw system error instead of a sentence. Skipped under root, where
# the mode bits below would not stop anything and the case would pass without
# ever reaching the guard — CI's ubuntu runner is unprivileged, so it runs there.
if [ "$(id -u)" -ne 0 ]; then
    new_case
    chmod 555 "${APPS}"
    expect "names the problem when it cannot write to /Applications" rejects "could not write" \
        run_shim
    chmod 755 "${APPS}"
    check "  and it linked nothing" test ! -e "${LINK}"
else
    echo "skip (running as root): cannot write to /Applications"
fi

echo
printf '%s passed, %s failed\n' "${PASSED}" "${FAILED}"
[ "${FAILED}" -eq 0 ]
