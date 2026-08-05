# Keep Screen Awake

Stops the display sleeping for a capped stretch, without touching your mouse.

**Status:** Shipped · **Failure model:** fails open

## Why it isn't built in

macOS has no toggle for this at all. Lock Screen settings let you change the timeout, which is not the same as a switch you flip while reading a long document or watching something.

This is also **the correct answer to "move the mouse to stop the screen sleeping"**. An `IOPMAssertion` does it properly: your cursor stays put, nothing hovers or scrubs by accident, and it can't fight you while you work. Synthetic mouse movement is only needed to defeat *app-level* idle detection — that's [Stay Active](../StayActive/README.md), a different feature with a different purpose.

## Behaviour

- Menu → 30 minutes / 2 hours / 8 hours.
- Holds a `PreventUserIdleDisplaySleep` assertion; releases it on expiry, on toggle-off, and on quit.
- ⚡ in the menu bar while active, with time remaining in the menu.
- The assertion dies with the process, so a crash restores normal behaviour. Nothing to recover at launch.

## Design notes

Almost entirely reuse: `DisplaySleepPreventer` (already in `WardKit`, already used by Cleaning Mode) plus `KeepAwakeSession` for the cap. The new code is a controller and a menu.

Deliberately **not** shared with [Keep Awake with Lid Closed](../KeepAwakeLidClosed/README.md) despite the similar name — that one fails closed and carries recovery machinery this one must not inherit.

## Tests

New pure logic is minimal; the cap and expiry are `KeepAwakeSession`, already covered in `WardKitTests`.

| Test | Asserts |
| --- | --- |
| `KeepScreenAwakeStateTests` | Menu state derives from the session: no session → durations offered; within the cap → remaining time; past the cap → still held, because only a successful release ends a session |

Write these before the controller. Manual check: start a 30-minute session, confirm `pmset -g assertions` lists a `PreventUserIdleDisplaySleep` entry owned by Ward, then confirm it disappears on toggle-off.
