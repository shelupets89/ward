# Sleep Inspector — notes for Claude

**Read-only.** No failure model, no permissions, no privileged execution. Keep it that way — the moment this feature can *change* something, it needs everything the others carry.

## Invariants

- **Never offer to kill a process or release someone else's assertion.** It's a readout. An "end this" button turns a safe feature into one that can break other apps.
- **Unknown assertion types show their raw name.** Never guess a friendly description from a pattern — Apple adds types, and a confident wrong explanation is worse than a raw string.
- **Label Ward's own assertions as Ward's.** If Keep Screen Awake is holding one, this must say so rather than leaving the user hunting.

## Gotchas

- `pmset -g assertions` has two sections. The system-wide summary at the top is counts, not entries — parsing it as entries produces phantom rows with no owner.
- Entries with count `0` in the summary are not held; only the "Listed by owning process" section describes live assertions.
- Timestamps are `HH:MM:SS` elapsed, not wall-clock. Don't render them as a time of day.
- Output includes device names and window titles that can be non-ASCII and quoted — parse defensively, don't assume ASCII.
- Run through `BoundedProcess` like every other subprocess call.

## Layout

`Sources/Pure/` — `SleepAssertionsParser` (output → entries), `AssertionDescription` (type → plain English). Both fully testable with captured fixtures.

`Sources/` — the window/list and `WardFeature` conformance.
