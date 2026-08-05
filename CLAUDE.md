# Ward — working notes for Claude

macOS menu-bar utility. Two features that each suspend a normal macOS behaviour temporarily: **Cleaning Mode** (black out displays + block all input so the screen can be wiped) and **Keep Awake with Lid Closed** (`pmset disablesleep`).

**This is a personal project, not DoorLoop work.** No Linear tickets, no feature flags, no PR title conventions, no `DbTenant` scoping. The user's global Swift style rules still apply.

## The invariant that matters most

The two features have **opposite failure models**. Never blur them, and never share machinery between them without thinking about this:

| | Cleaning Mode | Keep Awake |
|---|---|---|
| Failure mode | Fails **open** | Fails **closed** |
| On process death | Everything restored | Setting persists |
| Safety net | `killall Ward` is enough | Capped session, quit gate, leak check |

`pmset disablesleep` survives quit, crash, **and reboot**. A MacBook left with sleep disabled in a closed bag overheats and drains flat. Any change touching `KeepAwakeController`, `LidSleepSetting`, or `SudoersRule` must preserve: the hard session cap, the quit-time gate, the launch/menu leak check, and the retry-on-failed-restore behaviour.

Conversely, nothing in Cleaning Mode may outlive the process. If you add a resource there, it must die with the app.

## Architecture rule

```
Sources/WardCore   pure, decidable logic — ALWAYS unit-tested, no AppKit import
Sources/Ward       AppKit/IOKit/LocalAuthentication glue — not unit-testable
```

**When you write logic, ask whether it can live in `WardCore`.** If it can be expressed as a function of its inputs, it belongs there with tests. This is the repo's actual quality gate — not a coverage number on the glue layer. Precedents: shell quoting, the sudoers command builder, `pmset` output parsing, the esc-hold state machine, media-key decoding.

`scripts/coverage.sh` enforces ≥85% line coverage on `WardCore` only, deliberately. Don't add coverage requirements for `Sources/Ward` — it would only reward fake tests.

## Commands

```bash
swift build                      # debug build
swift test                       # 63 tests (XCTest + Swift Testing)
bash scripts/coverage.sh         # coverage gate, same as CI
bash scripts/make-app.sh         # → dist/Ward.app
bash scripts/make-dmg.sh         # → dist/Ward-<v>.dmg + INSTRUCTIONS.txt
bash scripts/lid-sleep-probe.sh 90   # empirically re-verify lid-close behaviour
```

Always launch the built `.app`, never `swift run` — macOS attributes TCC grants to whatever launched the process.

## Environment facts (verified — don't re-derive or contradict)

- **`pmset` is at `/usr/bin/pmset`**, not `/usr/sbin/pmset`.
- **`pmset disablesleep` genuinely works** on macOS 26 / M4 Pro, on battery — verified with control (slept, 109 s gap, `Clamshell Sleep` logged) and test (stayed awake) runs. It is **undocumented** (absent from `man pmset`), so re-verify with `lid-sleep-probe.sh` after macOS updates.
- **Power assertions and `caffeinate` do NOT cover lid-close sleep.** Clamshell sleep is a demand sleep, not an idle one. Don't propose `IOPMAssertion` as a fix for it.
- **No code-signing identity exists** (`security find-identity` → 0 valid). This forces ad-hoc signing, means Accessibility must be re-granted after every rebuild, blocks `SMAppService` privileged helpers, and makes downloaded builds hit Gatekeeper. Many design choices exist only because of this — a Developer ID would remove three separate workarounds.
- **Touch ID here is an intent gate, not a privilege boundary.** `LAContext` cannot grant root; the sudoers rule does. Never describe it as security in UI text or docs.
- **`SleepDisabled` appears in `pmset -g` only once set**, and persists as `0` after being reset. "Key absent" and "key is 0" both mean sleep is enabled; a failed *read* means unknown, which is treated as possibly-disabled.

## Things not to break

- **The esc-hold exit gesture is cloth-proof by design.** Any other key or modifier cancels the hold and suppresses it until esc is physically released. A cloth dragged over the keyboard must never be able to exit Cleaning Mode. Changes here need tests.
- **Timing uses `ContinuousClock`**, never `Date()` — a wall-clock jump must not shorten the exit hold or a keep-awake session.
- **Never write to `/etc/sudoers.d` without `visudo -c` validating the staged file first.** An invalid file there breaks `sudo` machine-wide.
- **Entry into Cleaning Mode is refused unless input blocking *and* shielding both succeed** — never a shield over live input, never blocked input with no visible way out.
- Don't add a "keep awake indefinitely" option. The cap is the safety feature.

## Conventions

- Swift Testing (`import Testing`) for new tests; the older `EscapeHoldTrackerTests` is XCTest and can stay.
- `os.Logger` via `WardLogger`, never `print()`. Every failure and recovery path logs.
- Failure paths that the user would want to know about get an `NSAlert`, not just a log line.
- No git repo exists yet. Don't `git init` or create remotes without asking.
