# Cleaning Mode — notes for Claude

**Fails open.** Every restriction must die with the process. If you add a resource here, it dies with the app or it doesn't belong.

## Invariants

- **The esc-hold gesture is cloth-proof.** Any other key or modifier cancels the hold and suppresses it until `esc` is physically released. Auto-repeat never restarts a cancelled hold. This is the whole point of the feature — changes need tests.
- **Caps Lock is excluded from `WatchedModifiers` on purpose.** Its flag reports toggle state, not a held key; including it would permanently block the exit.
- **Timing uses `ContinuousClock`.** A wall-clock jump must not shorten the hold.
- **Entry is all-or-nothing.** Never a shield over live input, never blocked input with no visible way out. If either half fails, abort and restore.
- **Secure input is checked at entry and by a watchdog.** When another app holds it, the tap can't see keystrokes — including the ones needed to leave.

## Gotchas

- The tap callback returns `nil` for *everything*, including `tapDisabled*` notifications. Anything else leaks an event through.
- The tap runs on the main run loop, so the `DispatchQueue.main.async` hops are technically redundant — but two reviewers disagreed on whether they're load-bearing for the self-invalidation path in `recoverDisabledTap()`. Left in deliberately; don't "simplify" without testing that path on-device.
- Borderless windows refuse key status by default. `KeyableShieldWindow` overrides it so the backup monitor receives events.
- `NSScreen.screens` can legitimately return empty mid-reconfiguration. Guarded — don't remove.

## Layout

`Sources/Pure/` — `EscapeHoldTracker`, `WatchedModifiers`, `SystemDefinedKeyEventDecoder`. Fully tested; keep new decidable logic here.

`Sources/` — event tap, shield windows, SwiftUI overlay, controller. Needs a running app and Accessibility; not unit-testable.
