# Stay Active — notes for Claude

**Fails open.** Synthetic events stop the moment the process does.

## Invariants

- **Never fire while the user is actually active.** Check `CGEventSource.secondsSinceLastEventType` first. A jiggler that fights the user for the cursor is a bug, not a feature.
- **Don't move the mouse.** Post `F15` or a flags-changed event instead — it resets the idle timer without a cursor that can hover, scrub or drop a drag. If you think you need mouse movement, you probably need [Keep Screen Awake](../KeepScreenAwake/CLAUDE.md) instead.
- **Keep the session cap.** Same reasoning as everywhere else in Ward: an indefinite "appear present" toggle is one you forget is on.

## Be accurate about what this does

In UI text, docs and commit messages, this defeats **app-level idle detection**. It does not prevent sleep — assertions do that, and Ward already has one. Describing it as a sleep fix would be wrong, and would send users to the worse of two tools.

## Gotchas

- Requires **Accessibility** to post events. Already granted for Cleaning Mode; reuse `InputPermissions` rather than prompting separately.
- `CGEvent.post(tap: .cghidEventTap)` is the right tap for synthetic input. Posting to a session tap can loop back into Ward's own event tap if Cleaning Mode is somehow active — guard against both features running at once.
- Some monitoring software detects synthetic events via `CGEventSourceStateID`. Ward makes no attempt to hide, and shouldn't.

## Layout

`Sources/Pure/` — `JiggleSchedule`: (idle seconds, last fire, session state) → fire or don't. Fully testable, no `CGEvent` involved.

`Sources/` — event posting, timer, controller, `WardFeature` conformance.
