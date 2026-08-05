#!/usr/bin/env bash
# Report and enforce line coverage for WardCore.
#
# Measures every Pure/ directory and nothing else.
#
# Pure/ holds logic that is a function of its inputs — no AppKit, no IOKit, no
# system calls — so it can be tested properly and must be. Everything outside
# Pure/ is glue that needs a running app and granted TCC permissions; holding it
# to a coverage number would only reward writing fake tests for it.
#
# The rule is therefore a filesystem fact rather than a convention someone has
# to remember: put decidable logic in Pure/, and it is automatically measured.
#
# Usage: bash scripts/coverage.sh [minimum-percent]   (default 85)

set -euo pipefail

cd "$(dirname "$0")/.."

MINIMUM_COVERAGE="${1:-85}"

swift test --enable-code-coverage > /dev/null

BIN_PATH="$(swift build --show-bin-path)"
PROFDATA_PATH="${BIN_PATH}/codecov/default.profdata"
XCTEST_BUNDLE="$(find "${BIN_PATH}" -maxdepth 1 -name '*.xctest' | head -1)"

if [ -z "${XCTEST_BUNDLE}" ] || [ ! -f "${PROFDATA_PATH}" ]; then
    echo "Could not locate test binary or coverage data under ${BIN_PATH}" >&2
    exit 1
fi

TEST_BINARY="${XCTEST_BUNDLE}/Contents/MacOS/$(basename "${XCTEST_BUNDLE}" .xctest)"

# shellcheck disable=SC2207
PURE_DIRECTORIES=($(find Sources Features -type d -name Pure | sort))
if [ ${#PURE_DIRECTORIES[@]} -eq 0 ]; then
    echo "No Pure/ directories found — nothing to measure." >&2
    exit 1
fi
COVERAGE_ARGS=(
    "${TEST_BINARY}"
    -instr-profile "${PROFDATA_PATH}"
    -ignore-filename-regex='(Tests|\.build)'
    "${PURE_DIRECTORIES[@]}"
)

echo "── Coverage: Pure/ directories ───────────────────────────"
xcrun llvm-cov report "${COVERAGE_ARGS[@]}"
echo

# Parsed from JSON rather than by column position: the report's column layout
# varies between toolchains, and a mis-parse must never read as a pass.
TOTAL_LINE_COVERAGE="$(
    xcrun llvm-cov export -summary-only "${COVERAGE_ARGS[@]}" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["totals"]["lines"]["percent"])'
)"

if ! printf '%s' "${TOTAL_LINE_COVERAGE}" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
    echo "❌ Could not read a coverage percentage (got: '${TOTAL_LINE_COVERAGE}')." >&2
    exit 1
fi

PRINTABLE_COVERAGE="$(printf '%.2f' "${TOTAL_LINE_COVERAGE}")"

if ! python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) >= float(sys.argv[2]) else 1)" \
    "${TOTAL_LINE_COVERAGE}" "${MINIMUM_COVERAGE}"; then
    echo "❌ Pure/ line coverage ${PRINTABLE_COVERAGE}% is below the ${MINIMUM_COVERAGE}% minimum."
    exit 1
fi

echo "✅ Pure/ line coverage ${PRINTABLE_COVERAGE}% (minimum ${MINIMUM_COVERAGE}%)."
