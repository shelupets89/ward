#!/usr/bin/env bash
# Does this Mac keep running with the lid closed?
#
# Writes a timestamp every second. If the Mac sleeps, this process is suspended
# and the timestamps show a gap — that gap is the evidence. Needs no privileges;
# toggling `pmset disablesleep` is done by you, separately.
#
# Usage: bash scripts/lid-sleep-probe.sh [seconds]   (default 90)

set -euo pipefail

DURATION="${1:-90}"
PROBE_LOG="/tmp/ward-lid-probe.log"
SLEEP_GAP_THRESHOLD=3

echo "── Preflight ─────────────────────────────────────────────"

SLEEP_DISABLED="$(pmset -g | awk '/SleepDisabled/ {print $2}')"
echo "SleepDisabled:  ${SLEEP_DISABLED:-0 (not set)}"

POWER_SOURCE="$(pmset -g batt | head -1 | sed 's/Now drawing from //; s/['"'"']//g')"
echo "Power source:   ${POWER_SOURCE}"

DISPLAY_COUNT="$(system_profiler SPDisplaysDataType 2>/dev/null | grep -c 'Resolution:' || true)"
echo "Displays:       ${DISPLAY_COUNT}"
if [ "${DISPLAY_COUNT}" -gt 1 ]; then
    echo
    echo "  ⚠️  More than one display detected. With an external display attached"
    echo "      (plus power and an input device) macOS enters clamshell mode and"
    echo "      stays awake ANYWAY — that would confound this test."
    echo "      Disconnect external displays before trusting the result."
fi

PROBE_START_EPOCH="$(date +%s)"
echo
echo "── Probe ─────────────────────────────────────────────────"
echo "Close the lid when the countdown ends, then reopen it after ~${DURATION}s."
echo "Keep the Mac on a desk — not in a bag — while testing."
for countdown in 5 4 3 2 1; do
    printf '\r  starting in %ds… ' "${countdown}"
    sleep 1
done
printf '\r  probing — CLOSE THE LID NOW.            \n'

: > "${PROBE_LOG}"
for _ in $(seq "${DURATION}"); do
    date +%s >> "${PROBE_LOG}"
    sleep 1
done

echo
echo "── Result ────────────────────────────────────────────────"

LARGEST_GAP="$(awk 'NR>1 {gap = $1 - previous; if (gap > largest) largest = gap} {previous = $1} END {print largest + 0}' "${PROBE_LOG}")"
echo "Largest gap between heartbeats: ${LARGEST_GAP}s"

if [ "${LARGEST_GAP}" -ge "${SLEEP_GAP_THRESHOLD}" ]; then
    echo "→ The Mac SLEPT. Background processes were suspended."
else
    echo "→ The Mac STAYED AWAKE. Background processes kept running."
fi

echo
echo "Sleep/wake events macOS recorded during the probe:"
pmset -g log \
    | awk -v start="${PROBE_START_EPOCH}" '
        /Sleep  |Wake  |Clamshell/ {
            command = "date -j -f \"%Y-%m-%d %H:%M:%S\" \"" $1 " " $2 "\" +%s 2>/dev/null"
            command | getline event_epoch
            close(command)
            if (event_epoch >= start) print "  " $0
        }' \
    | head -20
echo "  (nothing listed above = macOS logged no sleep during the probe)"
