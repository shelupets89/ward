# Ward — Design (2026-08-05)

## Problem

Wiping a MacBook's screen or keyboard generates input: keys type into whatever is focused, media keys change volume and brightness, the trackpad clicks things. Apple's official answer is "shut down the Mac first" (support.apple.com/guide/mac-help/mchlp2657), which is impractical when background processes are running. Teslas solve this with a Screen Clean Mode: the screen goes dark and inert, and a deliberate gesture exits. macOS has no equivalent.

## Inspiration & prior art

- **Tesla Screen Clean Mode** — dark screen, deliberate hold gesture to exit. The behavioral model.
- **One Switch** (fireball.studio/oneswitch) — menu-bar switch utility (Hide Desktop Icons, Keep Awake, Screen Saver…). The interaction model: one click in the menu bar, no windows, no dock icon.
- **KeyboardCleanTool** (BetterTouchTool's author) — locks the keyboard only; the screen stays live and exit is a mouse click. Ward combines both halves (screen + keyboard) with a keyboard-only deliberate exit.

## Goals (MVP)

1. One menu-bar click → every display covered by a black shield with faint instructions.
2. All keyboard input blocked, including media/volume/brightness keys, Cmd-Tab, Cmd-Q, screenshot shortcuts, the force-quit combo, and the lock-screen shortcut.
3. Mouse/trackpad clicks and scrolling blocked; cursor hidden.
4. Exit only by holding `esc` **alone** for 5 uninterrupted seconds, with a progress ring for feedback.
5. Display stays awake while the mode is active.
6. Fail open: if the app dies for any reason, every restriction dies with it.

Non-goals for v0 (YAGNI): global hotkey, launch at login, preferences UI, custom app icon, auto-exit timer, notarized distribution.

## Approaches considered

- **A. Active CGEventTap + shield windows + kiosk presentation options** — chosen. A session-level filter tap consumes events before any app or system hotkey handler sees them. Real blocking, public API, dies with the process.
- **B. Shield window + kiosk options only** — no special permission needed, but volume/brightness/media keys, screenshots, and dictation still fire; keys merely land in a window that ignores them. Not a real lock. Rejected as the primary mechanism, kept as a defensive second layer.
- **C. IOKit HID exclusive access (seize the devices)** — closest to a hardware lock, but needs root or special entitlements and is fragile across macOS releases. Rejected.

## Key decisions

### 1. Blocking mechanism

Session-level **active CGEventTap** at head insertion with an all-events mask. The callback returns `nil` for everything, which consumes keys, `flagsChanged` (modifiers, fn/Globe), `systemDefined` events (volume/brightness/media keys), mouse buttons, scrolling, and gesture events. Requires the user to grant **Accessibility**; some macOS versions additionally want **Input Monitoring** — the app detects tap-creation failure and points at both. The app never shows the shield unless the tap is actually running (no half-locked states).

> [!note] Revised after review (2026-08-05)
> A six-agent review pass changed four things in this design. **Timing** uses a monotonic `ContinuousClock`, not wall-clock `Date` — a clock jump mid-hold must not shorten or block the exit gesture. **Entry is all-or-nothing**: blocking and shielding must both succeed, so neither "shield with live input" nor "blocked input with no shield" is reachable (`NSScreen.screens` can return empty mid-reconfiguration). **Secure input** is re-checked by a 1 s watchdog, not only at entry, since it can engage mid-session and silently starve the tap of the very esc presses needed to exit. And every failure/recovery path **logs** to `os.Logger` — cleaning mode hides the UI it would otherwise report through.

### 2. Cloth-proof exit state machine

Naive "esc held 5 s" fails in the real world: a cloth wiping the keyboard can hold esc (and everything around it) for 5 seconds and exit the mode mid-clean. Exit therefore requires esc **alone**:

- Any other key press while esc is held → the hold is cancelled and **suppressed until esc is physically released**.
- Any modifier (⌘ ⌥ ⌃ ⇧ fn) currently held → esc presses cannot start a hold, and pressing a modifier during a hold cancels it.
- Auto-repeat esc events never restart a cancelled hold (that is what the suppressed-until-release state is for) and never reset an active hold's start time.
- Media-key presses count as "other key".
- Mouse/trackpad activity does **not** cancel the hold (one hand can hold esc while the other puts the cloth down).

States: `idle → holding(startedAt) → suppressedUntilRelease`, plus an independent `areModifiersDown` gate. Implemented as a pure Swift struct in WardCore, fully unit-tested.

### 3. Shield UI

One borderless `NSWindow` per screen at `CGShieldingWindowLevel` (above everything, including notification banners), joining all Spaces, pure black. SwiftUI content: dim "Cleaning mode" title, "Hold esc for 5 seconds to exit" hint, and a progress ring while esc is held. Cursor hidden. Kiosk `NSApplication.presentationOptions` (hide Dock + menu bar, disable Apple menu, process switching, force quit, session termination, hide) as the second defensive layer. A black screen also happens to be the best surface for spotting smudges.

### 4. Safety posture — fail open

- The tap, windows, kiosk options, and sleep assertion all die with the process: a crash or `killall Ward` (e.g. over SSH) fully restores the machine.
- If macOS disables the tap (timeout, permission revoked) and it cannot be re-enabled, the app exits cleaning mode itself rather than leaving a shield up with live input underneath.
- Entry is **refused while secure keyboard input is active** (another app's password field): the tap could not intercept in that state, so the lock would be a lie.
- A local `NSEvent` monitor duplicates the esc-exit path as a backup that works whenever our window is key, even if the tap goes silent.
- The always-available hardware escape hatch: hold the power/Touch ID button.

### 5. Not blockable (hardware/OS level, documented in README)

Power/Touch ID button (long-press force shutdown), lid-close sleep, and some trackpad system gestures (best effort only).

### 6. Packaging

SwiftPM, two targets: **WardCore** (pure logic, unit tests) and **Ward** (AppKit/SwiftUI glue). `scripts/make-app.sh` assembles `dist/Ward.app` — an `LSUIElement` menu-bar app — and signs it. No codesigning identity exists on this machine, so signing is ad-hoc: after a rebuild macOS treats the binary as new and Accessibility must be re-granted (documented in README). Launch the bundled app, not `swift run`, so the TCC grant attaches to Ward rather than the terminal.

## Architecture

```
WardCore
└── EscapeHoldTracker        pure state machine (unit-tested)

Ward (app)
├── main.swift               NSApplication bootstrap (.accessory)
├── AppDelegate              status item + menu
├── CleaningModeController   orchestrates enter/exit; owns everything below
├── InputBlocker             CGEventTap wrapper; routes esc / other-key /
│                            modifier signals to handlers, swallows the rest
├── ShieldWindowsController  per-screen shield windows (rebuilds on display changes)
├── ShieldView + ShieldOverlayModel   SwiftUI overlay (instructions / progress ring)
├── InputPermissions         Accessibility / Input Monitoring checks + guidance
├── SecureInputDetector      refuses entry while secure input is active
└── DisplaySleepPreventer    IOPM assertion while mode is active
```

Data flow: tap callback (main run loop) → handler closures → tracker mutation → overlay model publishes → SwiftUI renders; a 30 Hz timer polls hold progress and triggers exit at 100%.

## Testing

- Unit tests: every EscapeHoldTracker transition (idle/holding/suppressed, modifier gate, autorepeat, clamping).
- Manual test plan (needs the user to grant Accessibility; in README): block verification for typing, media keys, Cmd-Tab/Cmd-Q/force-quit, clicks; hold-to-exit; mid-hold release; cloth simulation (esc + neighbors); secure-input refusal; multi-display.

## Resolved by assumption (flag if wrong)

- Name **Ward**, folder `~/DoorLoop/ward` (sibling of the other personal tools). Rename freely.
- 5 s hold duration hard-coded as a single constant.
- No git repo initialized — the machine's commit conventions/hooks are gated on user review, so init happens on request.
