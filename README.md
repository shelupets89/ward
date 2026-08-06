# Ward

A macOS menu-bar utility for things macOS makes hard. No Dock icon, no window, no network code, no telemetry.

## Install

```bash
brew install shelupets89/ward/ward
```

This compiles Ward on your machine rather than downloading it. Nothing downloaded means nothing carries `com.apple.quarantine`, which is what makes macOS check an app with Gatekeeper when you open it — so there's no security dialog at any point. That matters here: Ward isn't notarized, and the dialog it would otherwise produce has no Open button. Needs Xcode Command Line Tools (`xcode-select --install`), and builds in well under a minute (about 10 seconds on Apple silicon).

Homebrew's install sandbox isn't permitted to write to `/Applications`, so the last step is yours. `brew install` prints it when it finishes:

```bash
ln -s "$(brew --prefix ward)/Ward.app" /Applications && open /Applications/Ward.app
```

Use the full `shelupets89/ward/ward` name rather than tapping first and installing `ward` — Homebrew only auto-trusts a formula you name in full, and the short form is refused as coming from an untrusted tap.

Update with `brew upgrade ward` — the symlink follows, so it's a one-time step. **The Accessibility grant does not survive an upgrade**: Ward is ad-hoc signed, every upgrade rebuilds it into a binary macOS considers a different app, and grants are tied to the binary. Cleaning Mode needs re-granting each time.

Re-granting means **removing Ward from the Accessibility list with `−` and adding it back** — not flipping its switch. The old entry keeps showing its toggle **on** while granting nothing, because it still refers to the previous build. That looks exactly like a working grant and isn't one.

**Without Homebrew**, build it by hand — same reason it works, no quarantine on a local build:

```bash
git clone https://github.com/shelupets89/ward.git && cd ward && bash scripts/make-app.sh && open dist/Ward.app
```

**Or download** the [latest release](https://github.com/shelupets89/ward/releases/latest). macOS will refuse to open it — *"Apple could not verify Ward-x.y.z.dmg is free of malware"* — because Ward isn't notarized. That dialog offers only **Move to Trash** and **Done**; there's no Open button in it.

To clear the quarantine flag:

```bash
xattr -rd com.apple.quarantine ~/Downloads/Ward-*.dmg
```

Same command for the app itself, if it's blocked again after you drag it to Applications:

```bash
xattr -rd com.apple.quarantine /Applications/Ward.app
```

Without a terminal: click **Done**, then System Settings → Privacy & Security → scroll to **Security** → **Open Anyway**.

> Either route is you telling macOS to trust a file it can't verify. Reasonable for something you or a colleague built. Not a habit for downloads in general — and building from source above avoids the question entirely.

> Launch the built `.app`, not `swift run` — macOS attaches permission grants to whatever launched the process.

## First run

Ward appears in the menu bar as ✨ (⚡ when something is holding the system awake). Click it.

Each feature explains its own permissions on first use. Cleaning Mode needs **Accessibility**; Keep Awake offers a one-time Touch ID setup.

## Features

| Feature | What it does | Status |
| --- | --- | --- |
| [Cleaning Mode](Features/CleaningMode/README.md) | Black out displays + block input so you can wipe the screen | ✅ Shipped |
| [Keep Awake, Lid Closed](Features/KeepAwakeLidClosed/README.md) | Keep working with the MacBook shut, for a capped stretch | ✅ Shipped |
| [Keep Screen Awake](Features/KeepScreenAwake/README.md) | Stop the display sleeping, without moving your mouse | ✅ Shipped |
| [Touch ID for sudo](Features/TouchIDForSudo/README.md) | One-click `pam_tid` — no UI for this exists anywhere | 📋 Planned |
| [Stay Active](Features/StayActive/README.md) | Synthetic input to defeat app-level idle detection | 📋 Planned |
| [Keep Awake Until Exit](Features/KeepAwakeUntilExit/README.md) | Stay awake while a build, process or port is alive | 📋 Planned |
| [Sleep Inspector](Features/SleepInspector/README.md) | Answers "what's keeping my Mac awake?" | 📋 Planned |
| [Free a Port](Features/FreePort/README.md) | Kill whatever is holding port 3001, with a look before you leap | ✅ Shipped |

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| "Apple could not verify…" | Downloaded copy — see the release notes, or build from source |
| Cleaning Mode does nothing | Accessibility not granted, or granted to your terminal via `swift run` |
| Stopped working after a rebuild or `brew upgrade` | Ad-hoc signing makes each build a new app. Remove Ward from Accessibility with `−` and add it back — its toggle stays **on** while granting nothing |
| Stuck in Cleaning Mode | `killall Ward` over SSH, or hold the power button |
| Mac won't sleep | Menu → **Restore Normal Sleep**. By hand: `sudo pmset -a disablesleep 0` |
| "Port N belongs to another user" | Ward only stops your own processes. Free it yourself: `sudo lsof -ti tcp:N \| xargs sudo kill` |

```bash
log stream --predicate 'subsystem == "com.dimashelupets.ward"' --level info
```

## Development

```bash
swift build
swift test                  # 139 tests
bash scripts/coverage.sh    # Pure/ must stay ≥85%
```

One library target per feature under `Features/`, each depending on `WardKit` and none on each other. `Sources/Ward` is a thin shell owning the status item.

**Logic that is a function of its inputs goes in a `Pure/` directory.** The coverage gate finds those automatically — no list to maintain.

[MIT licensed](LICENSE) — use it, change it, ship it, keep the notice. [CONTRIBUTING.md](CONTRIBUTING.md) · [SECURITY.md](SECURITY.md) · [CLAUDE.md](CLAUDE.md)
