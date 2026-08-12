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
- **`startProgressTimerIfNeeded`'s nil-guard is load-bearing.** Every input event while holding reaches it, auto-repeat esc key-downs included, and those can outpace the 1/30 s tick. Restart-on-every-call would starve the timer — and `handleProgressTick` is the only thing that ever notices a completed hold and exits. Don't replace it with anything whose `start()` stops first (`WardKit.ExpiryTimer` does).
- **`InputBlocker` is deliberately *not* `@MainActor`.** It owns no isolated state, so the `CGEvent.tapCreate` C callback reaches it with no bridge at all. Isolating it would just move the bridge into the callback without removing one.
- Borderless windows refuse key status by default. `KeyableShieldWindow` overrides it so the backup monitor receives events.
- `NSScreen.screens` can legitimately return empty mid-reconfiguration. Guarded — don't remove.

## Layout

`Sources/Pure/` — `EscapeHoldTracker`, `WatchedModifiers`, `EscapeKeyCode`, `SystemDefinedKeyEventDecoder`. Fully tested; keep new decidable logic here. Framework *value* types are fine (`WatchedModifiers` takes `NSEvent.ModifierFlags` and `CGEventFlags`); what disqualifies code is needing a live object. `coverage.sh`'s "no AppKit" is shorthand for that, not the literal rule.

`Sources/` — event tap, shield windows, SwiftUI overlay, controller. Most of it needs a running app and Accessibility, so it isn't unit-testable. `InputEventHandlers` is not: it is the routing table both input sources share, and it *is* tested.

## Isolation

`CleaningModeController`, `ShieldWindowsController` and the `InputEventHandlers` closures are all `@MainActor`, so the exit-gesture path is compiler-checked end to end. Two `MainActor.assumeIsolated` bridges remain, each at a framework callback whose block type cannot carry isolation, each justified at the site: `makeMainRunLoopTimer` (both `Timer`s go through it) and the `NSEvent` local monitor. Nothing non-`Sendable` crosses either — which is why `MonitoredKeyEvent` exists rather than passing `NSEvent` into the monitor's bridge.

The tap's `DispatchQueue.main.async` hop needs **no** bridge: the compiler treats a literal `DispatchQueue.main.async` block as main-actor isolated. That recognition is syntactic, so hoisting the queue into a local silently loses it — but it fails as a compile error, not at run time. Adding a third bridge should feel like a design smell; prefer declaring isolation.
