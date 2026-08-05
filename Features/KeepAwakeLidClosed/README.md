# Keep Awake with Lid Closed

Keeps the Mac running with the lid shut, for a capped stretch, so background work survives closing the laptop.

**Status:** Shipped · **Failure model:** fails **closed** — read the safety section

## Why it isn't built in

Power assertions (`IOPMAssertion`, `caffeinate`) only block *idle* sleep. Closing the lid triggers a **demand** sleep from the clamshell sensor, which ignores assertions entirely. The only lever macOS offers is `pmset disablesleep` — undocumented, absent from `man pmset`, and root-only.

Verified on macOS 26 / M4 Pro, on battery, single display, with [`lid-sleep-probe.sh`](../../scripts/lid-sleep-probe.sh):

| `SleepDisabled` | Largest gap | macOS log |
| --- | --- | --- |
| `0` (control) | 109 s | `Entering Sleep state due to 'Clamshell Sleep'` |
| `1` | 2 s | *no sleep events* |

The control run matters as much as the test — if it doesn't report **SLEPT**, something else is holding the Mac awake and the result is meaningless. An external display puts the Mac in clamshell mode, which stays awake regardless.

```bash
bash scripts/lid-sleep-probe.sh 90    # re-verify after macOS updates
```

## This one fails closed

`pmset disablesleep` is **persistent global system state** surviving quit, crash and reboot. A MacBook left with sleep disabled in a closed bag gets hot and flattens its battery. So:

- **Every session is capped** — 8 hours max. There is no "until I turn it off", on purpose.
- **Quitting is gated** — quit with it on and Ward offers to restore first.
- **The menu never guesses** — it re-reads the live `pmset` flag on every open, so a setting left by a crash shows as "Restore Normal Sleep" with a ⚡ icon. A flag Ward can't *read* counts as possibly-disabled.
- **A failed restore keeps retrying** — the expiry timer is only torn down once sleep is genuinely restored.
- **Residual risk:** `kill -9` beats all of it. The next launch or menu open catches it; `sudo pmset -a disablesleep 0` fixes it by hand.

## Authentication

Turning it **on** asks for Touch ID, but only once the sudoers rule is installed. Without it the toggle needs a password dialog anyway, so Ward skips the biometric gate rather than show two prompts for one action. Turning it **off** never prompts — a safety path you can decline isn't one.

> Touch ID here is an **intent gate, not a privilege boundary.** Root comes from the sudoers rule; anything running as you could call `pmset` directly. It makes a persistent change deliberate, nothing more.

Ward offers the one-time setup itself on first use, showing the exact rule before installing. The rule grants exactly two `pmset` invocations, has no wildcards, and is `visudo`-validated before it lands. Remove with `sudo rm /etc/sudoers.d/ward`.

## Layout

| Path | Contents |
| --- | --- |
| `Sources/Pure/` | `SleepSettingsParser` (reads `pmset -g`), `SudoersRule` (rule text + install command) |
| `Sources/` | `LidSleepSetting`, `SudoersRuleInstaller`, `KeepAwakeController` |

## Tests

| File | Asserts |
| --- | --- |
| `SleepSettingsParserTests` | Flag set / zero / absent / whitespace variants; a substring match never counts |
| `SudoersRuleTests` | No wildcards; `visudo` validation ordered before install; absolute paths; `0440 root:wheel`; hostile user names routed through quoting |

Manual: menu → 30 minutes → Touch ID → ⚡ icon, `pmset -g` shows `SleepDisabled 1`. Disconnect external displays, run the probe, close the lid → **STAYED AWAKE**. `killall -9 Ward` while active, relaunch → leak alert.
