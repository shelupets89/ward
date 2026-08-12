#!/usr/bin/env bash
set -uo pipefail

# render-formula.sh is a gate, and the way a gate fails is by quietly stopping
# gating. CI only ever feeds it a well-formed tarball, so every guard's *reject*
# branch would go unrun: a check that became vacuously permissive — an inverted
# condition, a pattern that matches nothing — would leave CI green for as long
# as it took someone to notice by hand. That is the failure this whole area was
# fixed for, one layer up, so it gets a test rather than a paragraph.
#
# Plain bash and no framework, matching the repo's zero-dependency posture. Runs
# on Linux, which also keeps the script's own portability claim honest.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/render-formula-tests.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

# A throwaway tree, so the template can be doctored to reach guards a correct
# template can never trigger. render-formula.sh resolves everything from its own
# location, so the copy needs the same shape.
TREE="${WORK}/tree"
mkdir -p "${TREE}/scripts" "${TREE}/packaging/homebrew"
cp "${REPO_ROOT}/scripts/render-formula.sh" "${TREE}/scripts/"
cp "${REPO_ROOT}/packaging/homebrew/ward.rb.template" "${TREE}/packaging/homebrew/"
SCRIPT="${TREE}/scripts/render-formula.sh"
TEMPLATE="${TREE}/packaging/homebrew/ward.rb.template"
PRISTINE="${WORK}/pristine.template"
cp "${TEMPLATE}" "${PRISTINE}"

# A real tarball of the real tree, named the way CI names it, and the same
# tarball with LICENSE removed.
GOOD_TARBALL="${WORK}/ward-9.9.9.tar.gz"
NO_LICENCE_TARBALL="${WORK}/ward-nolicence-9.9.9.tar.gz"
NEARLY_LICENCE_TARBALL="${WORK}/ward-nearlylicence-9.9.9.tar.gz"
git -C "${REPO_ROOT}" archive --format=tar.gz --prefix=ward-9.9.9/ -o "${GOOD_TARBALL}" HEAD
mkdir -p "${WORK}/unpacked"
tar xzf "${GOOD_TARBALL}" -C "${WORK}/unpacked"
rm -f "${WORK}/unpacked/ward-9.9.9/LICENSE"
tar czf "${NO_LICENCE_TARBALL}" -C "${WORK}/unpacked" ward-9.9.9

# A tarball carrying LICENSE.md but no LICENSE. The formula's `test do` asserts
# a file named exactly LICENSE in the bundle, so this one must still be refused
# — and it is the case that tells an anchored '/LICENSE$' apart from a bare
# 'LICENSE', which would match this and wave it through. Deleting the file
# outright cannot make that distinction: both patterns reject that.
printf 'not the licence\n' > "${WORK}/unpacked/ward-9.9.9/LICENSE.md"
tar czf "${NEARLY_LICENCE_TARBALL}" -C "${WORK}/unpacked" ward-9.9.9
rm -f "${WORK}/unpacked/ward-9.9.9/LICENSE.md"

# A LICENSE that exists but is nested, so only the root-anchored pattern
# refuses it. make-app.sh copies the root one; a vendored ThirdParty/LICENSE
# must not stand in for it.
NESTED_LICENCE_TARBALL="${WORK}/ward-nestedlicence-9.9.9.tar.gz"
mkdir -p "${WORK}/unpacked/ward-9.9.9/ThirdParty"
printf 'someone elses licence\n' > "${WORK}/unpacked/ward-9.9.9/ThirdParty/LICENSE"
tar czf "${NESTED_LICENCE_TARBALL}" -C "${WORK}/unpacked" ward-9.9.9
rm -rf "${WORK}/unpacked/ward-9.9.9/ThirdParty"

PASSED=0
FAILED=0
OUTPUT_SERIAL=0

# Set immediately before a single `expect` call to also assert some text is
# *absent*. Needed where the wrong code path would fail too, just for the wrong
# reason, so exit status and error text alone cannot tell them apart. `expect`
# clears it, so it never leaks into the next case.
FORBIDDEN_TEXT=""

# Asserts the exit status and that the message names the problem — a guard that
# fires with the wrong explanation sends the next reader somewhere else.
expect() {
    local label="$1" expectation="$2" wanted_text="$3"
    shift 3
    local forbidden="${FORBIDDEN_TEXT}"
    FORBIDDEN_TEXT=""
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
    if [ "${verdict}" = ok ] && [ -n "${forbidden}" ] &&
        printf '%s\n' "${output}" | grep -qF "${forbidden}"; then
        verdict="should not have said '${forbidden}'"
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

# Each case needs a path nothing has written to, or a stale file from an earlier
# case could stand in for one this render never produced.
next_output() {
    OUTPUT_SERIAL=$((OUTPUT_SERIAL + 1))
    printf '%s/out-%s/ward.rb' "${WORK}" "${OUTPUT_SERIAL}"
}

render_good() {
    bash "${SCRIPT}" --local-tarball "${GOOD_TARBALL}" "$(next_output)"
}

echo "# the happy path, and that it really substituted"
RENDERED="$(next_output)"
expect "renders a well-formed tarball" accepts "Wrote" \
    bash "${SCRIPT}" --local-tarball "${GOOD_TARBALL}" "${RENDERED}"
expect "the render carries the tarball's real checksum" accepts \
    "$(shasum -a 256 "${GOOD_TARBALL}" | awk '{print $1}')" \
    grep "sha256" "${RENDERED}"
expect "the render keeps the template's licence stanza" accepts 'license "MIT"' \
    grep "license" "${RENDERED}"

echo
echo "# the licence claim is checked against the tarball, not just declared"
expect "rejects a tarball with no LICENSE" rejects "contains no LICENSE" \
    bash "${SCRIPT}" --local-tarball "${NO_LICENCE_TARBALL}" "$(next_output)"
expect "rejects a tarball whose only licence file is LICENSE.md" rejects \
    "contains no LICENSE" \
    bash "${SCRIPT}" --local-tarball "${NEARLY_LICENCE_TARBALL}" "$(next_output)"
expect "rejects a LICENSE that is nested rather than at the archive root" rejects \
    "contains no LICENSE" \
    bash "${SCRIPT}" --local-tarball "${NESTED_LICENCE_TARBALL}" "$(next_output)"

echo
echo "# arguments"
expect "rejects a missing tarball" rejects "no tarball at" \
    bash "${SCRIPT}" --local-tarball "${WORK}/absent.tar.gz" "$(next_output)"

# Deriving the mode from "is LOCAL_TARBALL non-empty" rather than from what was
# asked for sends this into tag mode, where it fetches whatever TAG is in the
# environment — and release.yml exports one. Both modes fail here, so the exit
# status proves nothing; only the absence of a fetch tells them apart.
FORBIDDEN_TEXT="Fetching"
expect "refuses an empty --local-tarball rather than falling back to tag mode" \
    rejects "no tarball at" \
    env TAG=v0.0.0-must-never-be-fetched bash "${SCRIPT}" --local-tarball "" "$(next_output)"
cp "${GOOD_TARBALL}" "${WORK}/amp&ersand.tar.gz"
cp "${GOOD_TARBALL}" "${WORK}/pipe|char.tar.gz"
# These exist, so the rejection has to come from the path screen rather than
# from the file merely being absent. `&` is the dangerous one: on sed's
# replacement side it expands to the whole match, corrupting the url silently.
expect "rejects an existing path containing &" rejects "sed would mangle" \
    bash "${SCRIPT}" --local-tarball "${WORK}/amp&ersand.tar.gz" "$(next_output)"
expect "rejects an existing path containing |" rejects "sed would mangle" \
    bash "${SCRIPT}" --local-tarball "${WORK}/pipe|char.tar.gz" "$(next_output)"
expect "rejects a tag containing the sed delimiter" rejects "refusing tag" \
    bash "${SCRIPT}" 'v1.0|whoami' "$(next_output)"
# shellcheck disable=SC2016  # the unexpanded $(id) is the hostile input itself
expect "rejects a tag containing a shell metacharacter" rejects "refusing tag" \
    bash "${SCRIPT}" 'v1.0$(id)' "$(next_output)"
expect "rejects no arguments" rejects "usage:" bash "${SCRIPT}"
expect "rejects one argument" rejects "usage:" bash "${SCRIPT}" v1.0.0
expect "rejects --local-tarball without an output path" rejects "usage:" \
    bash "${SCRIPT}" --local-tarball "${GOOD_TARBALL}"

echo
echo "# the render guards, reached by doctoring the template"
# Nothing rendered at all. The negative placeholder grep passes here — an empty
# file contains no placeholders either — which is the hole this guard fills.
: > "${TEMPLATE}"
expect "rejects an empty render" rejects "is empty — nothing was rendered" \
    render_good

# The byte-comparison guard between those two is a backstop against a write that
# lands short — a partial render is not something this suite can synthesize from
# outside the script, since the comparison is against a second derivation of the
# same substitution. What is reachable is the write failing outright, which must
# stop the script rather than leave the guards inspecting a stale file.
cp "${PRISTINE}" "${TEMPLATE}"
UNWRITABLE="${WORK}/unwritable"
mkdir -p "${UNWRITABLE}/ward.rb"
expect "fails loudly when the output path cannot be written" rejects "" \
    bash "${SCRIPT}" --local-tarball "${GOOD_TARBALL}" "${UNWRITABLE}/ward.rb"

# `sed s|…|…|` has no `g` flag, so a second __URL__ on one line survives the
# render — and restoring the first still reproduces the template, so the restore
# check is blind to it. Only the negative grep catches this, which is why both
# guards are kept.
sed 's|  url "__URL__"|  url "__URL__" # __URL__|' "${PRISTINE}" > "${TEMPLATE}"
expect "rejects a leftover placeholder the restore check cannot see" rejects \
    "still contains placeholders" render_good

cp "${PRISTINE}" "${TEMPLATE}"
expect "accepts the pristine template again, so the doctoring was the cause" \
    accepts "Wrote" render_good

echo
printf '%s passed, %s failed\n' "${PASSED}" "${FAILED}"
[ "${FAILED}" -eq 0 ]
