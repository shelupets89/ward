# Stay Active

Posts synthetic input on an interval so apps watching for idleness think you're at the keyboard.

**Status:** Planned · **Failure model:** fails open

## What this is and isn't

**It does not stop the screen sleeping.** That's [Keep Screen Awake](../KeepScreenAwake/README.md), which uses a power assertion and is strictly better for that job — no cursor movement, nothing to fight you.

Stay Active exists for one thing an assertion cannot do: **app-level** idle detection. Slack and Teams presence, and monitoring software, watch input events, not power assertions. If that's the goal, say so plainly rather than dressing it up as a sleep fix.

Worth knowing this runs on whatever machine you install it on, including a managed work Mac.

## Behaviour

- Menu → 30 minutes / 2 hours / 8 hours. Capped like every other session.
- Every 30 seconds, **only if you've actually been idle**, posts one synthetic event.
- Never fires while you're genuinely using the machine — checked via `CGEventSource.secondsSinceLastEventType`.
- ⚡ in the menu bar while active; stops on expiry, toggle-off or quit.

## Design notes

**Prefer a modifier keypress over mouse movement.** Posting `F15` (or a bare flags-changed event) resets the idle timer without moving the cursor, so it can't hover a tooltip, scrub a video, or drop a drag. Moving the mouse 1px and back is the common approach and the worse one.

**Only jiggle when idle.** Firing unconditionally means fighting the user for the cursor. Reading `secondsSinceLastEventType` and skipping when recent real input exists makes the feature invisible when you're working.

Needs **Accessibility**, already required by Cleaning Mode — `InputPermissions` in `WardKit` handles the prompt.

## Tests

| Test | Asserts |
| --- | --- |
| `JiggleScheduleTests` | Fires only past the idle threshold; never fires when real input is recent; never fires when the session is inactive or expired; a real event resets the clock |

`JiggleSchedule` is a pure function of (last real input age, last synthetic fire, session state) → fire or don't. Write it and its tests before touching `CGEvent`.

Manual: start a session, leave the Mac alone 2 minutes, confirm Slack stays green and the cursor hasn't moved.
