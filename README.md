# Ward

A menu-bar utility that wards things off. Each feature suspends a normal macOS behaviour temporarily, with a safety net for getting back.

- **Cleaning Mode** — Tesla-style. One click blacks out every display and locks the keyboard and trackpad so you can wipe the Mac without shutting it down. Exit by holding `esc` **alone** for 5 seconds.
- **Keep Awake with Lid Closed** — keep background work running with the MacBook shut, for a capped stretch.

Menu-bar-only app (no Dock icon), inspired by [One Switch](https://fireball.studio/oneswitch/)'s interaction model. No network code, no telemetry, no accounts.

**Jump to:** [Getting started](#getting-started) · [Troubleshooting](#troubleshooting) · [How Cleaning Mode works](#what-it-does-while-active) · [How Keep Awake works](#keep-awake-with-lid-closed) · [Development](#development)

> The two features have deliberately **opposite failure models**: Cleaning Mode fails *open* (kill the process and every restriction dies with it), Keep Awake fails *closed* (it changes persistent system state that outlives the app). They're kept separate for that reason.

---

# Getting started

## Step 1 — Install

**Building it yourself is the smoothest path**, and not just for developers: apps you build locally carry no quarantine flag, so macOS never shows a security warning. A downloaded copy does. Requires Xcode or the Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/shelupets89/ward.git && cd ward && bash scripts/make-app.sh && open dist/Ward.app
```

<details>
<summary><strong>Or: someone sent you a .dmg</strong> — expect a security warning, and here's why</summary>

macOS will refuse to open it:

> "Apple could not verify Ward-x.y.z.dmg is free of malware…"

That dialog offers only **Move to Trash** and **Done** — there is no Open button in it. This is expected. Ward isn't *notarized*, which needs a paid Apple Developer ID; it isn't evidence anything is wrong with the file.

Two ways past it — pick one:

```bash
xattr -d com.apple.quarantine ~/Downloads/Ward-*.dmg
```

Or without Terminal: click **Done**, then System Settings → Privacy & Security → scroll to **Security** → the blocked file is listed with an **Open Anyway** button.

Then drag Ward to Applications. The same warning may appear once more for the app itself:

```bash
xattr -dr com.apple.quarantine /Applications/Ward.app
```

> **Be honest with yourself here:** both routes are you telling macOS to trust a file it cannot verify. Fine for something a colleague built and sent you directly. Not a habit to apply to downloads generally.

</details>

> Always launch the built `.app`, **not** `swift run` — macOS attaches permission grants to whatever launched the code, so `swift run` grants them to your terminal instead of Ward.

## Step 2 — Find it

Ward has **no Dock icon and no window**. It lives in the menu bar as a ✨ bubbles icon (⚡ when Keep Awake is on). Click it for the menu.

## Step 3 — Turn on Cleaning Mode

Click **Start Cleaning Mode**. The first time, macOS will refuse — blocking the keyboard needs **Accessibility** access:

1. Click **Start Cleaning Mode** once. Ward prompts and adds itself to System Settings → Privacy & Security → **Accessibility**.
2. Switch it **on** there.
3. Click **Start Cleaning Mode** again — every screen goes black.
4. If it still refuses, also enable Ward under **Input Monitoring** (some macOS versions gate keyboard taps separately), then quit and relaunch Ward.

**To get out: hold `esc` — by itself — for 5 seconds.** A ring fills as you hold. If a key or modifier is pressed alongside it, the hold cancels; that's deliberate, so a cloth dragged across the keyboard can't exit the mode while you're cleaning.

## Step 4 — Turn on Keep Awake (optional)

Menu → **Keep Awake with Lid Closed** → 30 minutes / 2 hours / 8 hours. Now you can shut the lid and background work keeps running.

The first time, Ward offers a one-time setup so it can change the sleep setting without asking for your password every time. It shows the exact system rule before changing anything. Accept it and turning Keep Awake on uses **Touch ID**; declining is fine too — you'll just get a password prompt per toggle.

> ⚠️ **This one is different from Cleaning Mode.** It changes a system setting that survives quitting, crashing, and rebooting. A MacBook left awake in a closed bag gets hot and drains flat. That's why every session has a time cap, why quitting asks first, and why Ward re-checks the real setting each time you open the menu. [Details below](#this-one-fails-closed--read-this-part).

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| "Apple could not verify…" on a downloaded copy | See the `.dmg` section in Step 1 — or just build from source |
| Cleaning Mode does nothing / keys still work | Accessibility not granted, or granted to your terminal because you used `swift run` |
| Worked before, stopped after a rebuild | Ad-hoc signing makes each build a "new" app. Remove Ward from Accessibility with **−**, re-add the fresh `dist/Ward.app` |
| "Another app is capturing secure input" | A password field is focused somewhere. Close it and retry |
| Stuck in Cleaning Mode | `killall Ward` over SSH, or hold the power button. Every restriction dies with the process |
| Mac won't sleep after using Keep Awake | Open the menu — it will offer **Restore Normal Sleep**. By hand: `sudo pmset -a disablesleep 0` |

Watch what Ward is doing at any time:

```bash
log stream --predicate 'subsystem == "com.dimashelupets.ward"' --level info
```

---

# Reference

## What it does while active

- Black shield window on **every display**, above everything (including notification banners); cursor hidden; display kept awake.
- All keyboard input swallowed: typing, media/volume/brightness keys, Cmd-Tab, Cmd-Q, screenshots, force-quit combo, lock-screen shortcut.
- Mouse/trackpad clicks and scrolling swallowed.
- Kiosk presentation options (Dock, menu bar, process switching, force quit disabled) as a second layer.

## Exiting — and why it's cloth-proof

Hold `esc` alone for 5 uninterrupted seconds; a progress ring fills. But a cloth wiping the keyboard can hold `esc` too — so the gesture only counts when `esc` is the **only** thing pressed:

- Any other key press cancels the hold and suppresses it until `esc` is physically released.
- A held modifier (⌘ ⌥ ⌃ ⇧ fn) prevents a hold from starting and cancels one in progress.
- Auto-repeat events can never restart a cancelled hold.

## Failsafes

- **Fail open by design:** the event tap, shield windows, and kiosk options all die with the process. If anything goes wrong, `killall Ward` (e.g. over SSH) fully restores the machine — as does a force restart (hold the power button, which no software can block).
- If macOS disables the tap and it can't be re-enabled, Ward exits cleaning mode itself rather than leaving a shield up over live input.
- Entry is refused unless input blocking *and* screen shielding both succeed — never a shield with live input beneath it, never blocked input with no visible way out.
- Entry is refused while another app holds secure keyboard input (a password field), because blocking couldn't actually work then. If secure input engages *mid-session*, a watchdog exits cleaning mode rather than let the session become untypable.
- A backup in-app key monitor duplicates the esc-exit path if the tap ever goes silent while the shield is up.
- The 5-second hold is measured on a monotonic clock, so a clock change mid-hold can't shorten or block the exit gesture.
- Every failure and recovery path logs to the unified log. To watch a session live:

```bash
log stream --predicate 'subsystem == "com.dimashelupets.ward"' --level info
```

## Keep Awake with Lid Closed

Menu bar → **Keep Awake with Lid Closed** → 30 minutes / 2 hours / 8 hours. The icon switches to ⚡ while active and the menu shows the time left.

**Why it needs its own mechanism.** Power assertions (`IOPMAssertion`, `caffeinate`) only block *idle* sleep. Closing the lid triggers a demand sleep from the clamshell sensor, which ignores assertions entirely — so the display-sleep assertion cleaning mode uses does nothing here. The only lever macOS offers is `pmset disablesleep`, which is undocumented (absent from `man pmset`) and requires root.

Verified on this machine (macOS 26, M4 Pro, on battery, single display) with [`scripts/lid-sleep-probe.sh`](scripts/lid-sleep-probe.sh), which timestamps every second and reports gaps:

| `SleepDisabled` | Largest gap | macOS log |
| --- | --- | --- |
| `0` (control) | 109 s | `Entering Sleep state due to 'Clamshell Sleep'` |
| `1` | 2 s | *no sleep events* |

Re-run it yourself after any macOS update — this is an undocumented flag and Apple owes it no compatibility:

```bash
bash scripts/lid-sleep-probe.sh 90
```

> The control run matters as much as the test. If it doesn't report **SLEPT**, something else is holding the Mac awake — an external display puts it in clamshell mode, which stays awake regardless — and the second run proves nothing.

### This one fails *closed* — read this part

Cleaning mode fails open: kill the process and everything is restored. Keep Awake is the opposite. `pmset disablesleep` is **persistent global system state** that survives quit, crash, and reboot. A MacBook left with sleep disabled and shut in a bag gets hot and flattens its battery. So:

- **Every session is capped** — 8 hours is the longest option. There's no "until I turn it off" on purpose.
- **Quitting is gated:** quit with it on and Ward offers to restore sleep first.
- **Leak check at launch:** if the flag is set when the app starts, no session can own it — Ward offers to restore.
- **The menu never guesses.** It re-reads the live `pmset` flag every time it opens, so a setting left by a crash (or another tool) shows up as "Restore Normal Sleep" with a ⚡ icon rather than being reported as off. A flag Ward can't *read* counts as possibly-disabled, not as fine.
- **A failed restore keeps retrying.** The expiry timer is only torn down once sleep is genuinely restored, so a declined authorization doesn't quietly kill the safety net.
- **Residual risk:** `kill -9` bypasses all of the above. The next launch — or the next time you open the menu — catches it; `sudo pmset -a disablesleep 0` fixes it by hand anytime.

### Authentication

Turning Keep Awake **on** asks for Touch ID — but only once the sudoers rule below is installed. Without it, the toggle needs the macOS password dialog anyway, and Ward skips the biometric gate rather than making you answer two prompts for one action. Turning it **off** never prompts — a safety path you can decline isn't a safety path.

> Touch ID here is an **intent gate, not a privilege boundary.** Root comes from the sudoers rule (or the fallback password dialog); anything already running as you could call `pmset` directly without passing through it. Its job is to make a change to persistent system state deliberate, not to keep an attacker out. If no biometry is enrolled, Ward skips the gate and falls through to the real authorization step rather than blocking the feature.

**Ward offers this setup itself** the first time you pick a Keep Awake duration, and it stays in the menu as "Set Up Touch ID for Keep Awake…" until it's done. The dialog shows the exact rule before installing — an app granting itself standing root access should say precisely what it's granting. One password, once.

The rule is scoped to exactly two commands (toggling lid sleep, nothing else) and is validated with `visudo -c` before it's written, so a bad rule can't break `sudo`. Remove it any time with `sudo rm /etc/sudoers.d/ward`.

The same thing from a terminal, if you prefer:

```bash
bash scripts/install-sudoers-rule.sh
```

Without it, each toggle falls back to the macOS password dialog — your password goes to macOS, never to Ward. That dialog can't appear unattended, so an expired session can't restore sleep on its own; it tells you instead. **That's the real reason to install the rule:** it's what lets the expiry actually fire.

Unrelated but adjacent — `/etc/pam.d/sudo` already includes `sudo_local`, so you can enable Touch ID for Terminal `sudo` too:

```bash
sudo cp /etc/pam.d/sudo_local.template /etc/pam.d/sudo_local && sudo sed -i '' 's/^#auth/auth/' /etc/pam.d/sudo_local
```

Ward doesn't depend on this — whether `pam_tid` fires for a GUI-spawned `sudo` with no controlling terminal is unverified.

## Not blockable (hardware level)

Power/Touch ID button, lid-close sleep, and some trackpad system gestures (best effort). That's fine — the power button doubles as the escape hatch of last resort.

## Sharing it with someone

| Method | Recipient sees |
| --- | --- |
| **Send the repo** (recommended) | Nothing — locally built apps aren't quarantined |
| `scp` / `rsync` the `.dmg` | Nothing — SSH doesn't attach quarantine |
| Slack / Mail / browser download | The "could not verify" wall; needs the Step 1 workaround |

```bash
bash scripts/make-dmg.sh   # → dist/Ward-<version>.dmg + INSTRUCTIONS.txt
```

Send **both** files — macOS blocks the `.dmg`, so instructions sealed inside it are unreachable exactly when they're needed.

Only a paid **Developer ID + notarization** removes that wall for everyone, over any channel. It would also stop macOS treating each rebuild as a new app for Accessibility, and unlock `SMAppService` — which would make the sudoers rule unnecessary entirely. One purchase, three problems.

## Development

```bash
swift build                 # debug build
swift test                  # 63 tests across WardCore
bash scripts/coverage.sh    # coverage gate (same as CI)
```

CI runs on every push and PR ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)): build, test, a ≥85% line-coverage gate on `WardCore`, a full `.app` + `.dmg` packaging run with bundle-identity verification, and ShellCheck over `scripts/`. Tagging `v*` triggers [`release.yml`](.github/workflows/release.yml), which re-tests, builds the DMG, checks the tag matches `CFBundleShortVersionString`, and publishes a GitHub release with install instructions.

Only `WardCore` has a coverage requirement. `Sources/Ward` is AppKit/IOKit glue that can't run without a real app and granted permissions — a number there would only reward fake tests. The rule that actually holds quality up is stricter: **pure, decidable logic belongs in `WardCore`, where it's tested.**

- `Sources/WardCore` — pure, unit-tested logic (exit-gesture state machine, modifier matching, media-key decoding, `pmset` parsing, keep-awake expiry).
- `Sources/Ward` — AppKit/SwiftUI glue (tap, shields, permissions, status item, privileged toggle).
- Design rationale: `docs/superpowers/specs/2026-08-05-ward-design.md`.

## Manual test plan (needs granted permissions)

1. Start mode → all screens go black with instructions; cursor gone.
2. Type, press volume/brightness keys, Cmd-Tab, Cmd-Q, Ctrl-Cmd-Q, Cmd-Shift-4, click, scroll → nothing happens.
3. Hold `esc` → ring fills over 5 s → mode exits, everything restored.
4. Release `esc` at ~3 s → ring resets; mode stays.
5. Hold `esc` + any letter (cloth simulation) → no exit, even after 10 s; release everything, hold `esc` alone → exits.
6. Terminal: `sudo -k && sudo true` (leave the password prompt open) → Start → refusal alert about secure input.
7. If you have a second display: both covered; unplug/replug mid-mode → shields rebuild.

Keep Awake:

8. Menu → Keep Awake → 30 minutes → Touch ID prompt → icon becomes ⚡, menu shows time left, `pmset -g` reports `SleepDisabled 1`.
8b. Repeat and *cancel* the Touch ID prompt → nothing changes, `SleepDisabled` stays `0`.
9. Disconnect external displays, then `bash scripts/lid-sleep-probe.sh 90` and close the lid → **STAYED AWAKE**.
10. Quit with it on → prompt offering to restore sleep first.
11. `killall -9 Ward` while active, then relaunch → leak-restore alert appears.

## Ideas for later

Global hotkey, launch at login, app icon, configurable hold duration, notarized release.
