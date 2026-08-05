# Keep Screen Awake — notes for Claude

**Fails open.** The assertion dies with the process. Do not add persistent state, a leak check, or a quit gate — this feature must stay cheap.

## Invariants

- **Assertion only.** Never reach for `pmset` here. If someone asks why the screen still sleeps with the lid closed, that's [Keep Awake with Lid Closed](../KeepAwakeLidClosed/CLAUDE.md), a different feature with a different failure model.
- **Keep the session cap** for consistency with the other keep-awake features, even though nothing bad happens if it's exceeded. Predictability is the point.
- **Don't merge this with `KeepAwakeLidClosed`.** They share a name and nothing else. Merging would pull fail-closed recovery machinery into a fail-open feature.

## Gotchas

- `DisplaySleepPreventer` already exists in `WardKit` and is used by Cleaning Mode. It's idempotent, but two features holding it at once means the first release must not cancel the second — check that before assuming reuse is free.
- `PreventUserIdleDisplaySleep` stops the *display* sleeping. It does not stop the system sleeping when the lid closes, and it does not stop app-level idle detection.

## Layout

`Sources/Pure/` — menu-state derivation only.

`Sources/` — controller wrapping `DisplaySleepPreventer` + `KeepAwakeSession`, and the `WardFeature` conformance.
