# Cleaning Mode

Blacks out every display and swallows all input, so you can wipe the screen and keyboard without shutting the Mac down.

**Status:** Shipped · **Failure model:** fails open

## Why it isn't built in

Apple's official guidance is to shut the Mac down before cleaning it. That's impractical with work running. Teslas solve this with a screen-clean mode; macOS has no equivalent.

## Behaviour

- Black shield on **every** display, above everything including notification banners. Cursor hidden.
- All keyboard input swallowed: typing, media/volume/brightness keys, ⌘-Tab, ⌘-Q, screenshots, force-quit, lock-screen shortcut.
- Mouse clicks and scrolling swallowed.
- Exit by holding `esc` **alone** for 5 seconds; a ring fills as you hold.

## Why the exit is cloth-proof

A cloth dragged across the keyboard holds `esc` too. So the hold only counts when `esc` is the only thing pressed:

- Any other key cancels it, and stays cancelled until `esc` is physically released.
- Any held modifier (⌘ ⌥ ⌃ ⇧ fn) prevents a hold starting and cancels one in progress.
- Auto-repeat can never restart a cancelled hold.

Caps Lock is deliberately excluded — its flag reports toggle state, not a held key, and would block the exit permanently.

## Failsafes

- Tap, shields and kiosk options all die with the process. `killall Ward` over SSH restores everything, as does holding the power button.
- If macOS disables the tap and it can't be re-enabled, Ward exits the mode rather than leave a shield over live input.
- Entry is refused unless input blocking **and** shielding both succeed.
- Entry is refused while another app holds secure input. If that starts mid-session, a watchdog exits.
- A backup in-app key monitor duplicates the esc path if the tap goes silent.
- The hold is measured on `ContinuousClock`, so a clock jump can't shorten or block it.

## Not blockable

Power button, lid close, and some trackpad gestures — hardware level. The power button is deliberately the escape hatch of last resort.

## Layout

| Path | Contents |
| --- | --- |
| `Sources/Pure/` | `EscapeHoldTracker` (exit state machine), `WatchedModifiers`, `SystemDefinedKeyEventDecoder` |
| `Sources/` | Event tap, shield windows, SwiftUI overlay, secure-input detector, controller |

## Tests

| File | Asserts |
| --- | --- |
| `EscapeHoldTrackerTests` | Every transition: hold, cancel, suppress-until-release, modifier gate, auto-repeat, clamping |
| `WatchedModifiersTests` | Which modifiers cancel a hold, and that Caps Lock doesn't |
| `SystemDefinedKeyEventDecoderTests` | Media-key press/release decoding from the packed `data1` field |
| `InputEventHandlersTests` | The routing table both input sources share: which handler each key event fires, that a non-escape key-up fires nothing, and that delivery order is preserved |

Manual (needs Accessibility): type and press media keys during the mode → nothing happens; hold `esc` 5s → exits; hold `esc`+letter for 10s → does not exit; unplug a display mid-session → shields rebuild.
