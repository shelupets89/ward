# Keep Awake with Lid Closed — notes for Claude

**Fails closed.** `pmset disablesleep` outlives quit, crash and reboot. This is the one feature that can leave the user's Mac in a harmful state — an overheating laptop in a closed bag.

## Invariants

- **Never remove the session cap.** 8 hours is the maximum and there is deliberately no unlimited option. The cap is the safety feature, not a limitation.
- **Never tear down the expiry timer before the restore succeeds.** A failed restore must keep retrying; killing the timer first strands the session with its safety net dead. This bug shipped once and was caught by three independent reviewers.
- **`menuState` re-reads the live flag.** Never derive "off" from `session == nil` alone — a crash leaves the flag set with no session owning it.
- **A failed *read* is `.unknown`, not `.enabled`.** Treat unknown as possibly-disabled, or the leak check silently skips the exact condition it exists to catch.
- **Never write `/etc/sudoers.d` without `visudo -c` on the staged file.** An invalid file there breaks `sudo` machine-wide.
- **The sudoers rule must stay wildcard-free.** `sudoers` matches arguments literally without wildcards; adding one would let extra arguments through.

## Gotchas

- `start(for:)` is `async` and suspends on Touch ID. State validated before the suspension is **stale** after it — re-check. An earlier version let a stale call resurrect a session the user had just turned off.
- The Touch ID gate is skipped when `sudo -n` can't run the toggle, because the password dialog would appear anyway. Two prompts for one action is worse than one.
- `SleepDisabled` appears in `pmset -g` only once it has ever been set, and persists as `0` afterwards. Absent and `0` both mean sleep is enabled.
- Expiry uses the non-interactive path only, so without the sudoers rule it *always* fails. That's why the alert fires once rather than every 30 seconds.

## Layout

`Sources/Pure/` — `SleepSettingsParser`, `SudoersRule`. Both fully tested; `SudoersRule` builds a command that runs as root, so treat changes there as security-sensitive.

`Sources/` — `LidSleepSetting` (chooses arguments), `SudoersRuleInstaller` (first-run setup), `KeepAwakeController` (session, expiry, leak recovery, quit gate).
