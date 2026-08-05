# Sleep Inspector

Answers "why won't my Mac sleep?" — in words rather than raw output.

**Status:** Planned · **Failure model:** none — read-only

## Why it isn't built in

macOS offers no answer to this question. `pmset -g assertions` has it, but the output is a wall of hex handles and internal identifiers:

```
pid 535(powerd): [0x00070dce000186fa] 03:26:16 PreventUserIdleSystemSleep named: "Powerd - Prevent sleep while display is on"
pid 604(WindowServer): [0x000731ba000991d0] 00:00:43 UserIsActive named: "com.apple.iohideventsystem.queue.tickle serviceID:100000cab …"
```

Nothing tells you which of those actually matters, or that `Powerd - Prevent sleep while display is on` just means your screen is on.

## Behaviour

- Menu → **What's keeping this Mac awake?**
- Shows one line per assertion: owning app, how long it's been held, and a plain-English meaning.
- Says so clearly when nothing is blocking sleep.
- Flags Ward's own assertions as Ward's, so the app never mystifies the user about its own effects.

## Design notes

The odd one out — a readout, not a toggle. No failure model to design, no permissions, no privileged execution. It exists because Keep Awake naturally raises the question and Ward is already parsing `pmset`.

Translation matters more than parsing. `PreventUserIdleDisplaySleep` means nothing to most people; "keeping the screen on" does. Assertion types are a small fixed set, so the mapping is a lookup, not heuristics — and an unknown type falls back to showing the raw name rather than guessing.

## Tests

| Test | Asserts |
| --- | --- |
| `SleepAssertionsParserTests` | Real `pmset -g assertions` output → structured entries with pid, process, type, duration, name; the system-wide summary block is skipped; zero-count entries excluded; empty and malformed input yield no entries rather than throwing |
| `AssertionDescriptionTests` | Known types map to plain English; unknown types fall back to the raw name |

Fixtures come from real output captured on this machine. Parser and translation are pure and get written first; the window is glue.
