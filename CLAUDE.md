# Ward — notes for Claude

macOS menu-bar utility. Personal project, **not DoorLoop work** — no Linear tickets, no feature flags, no PR title conventions. The user's global Swift style rules still apply.

Each feature has its own `CLAUDE.md`. Read the one you're working in.

## The rule that matters most

Every feature declares a **failure model**, and they are not interchangeable:

- **Fails open** — effects die with the process. `killall Ward` restores everything. Add no persistent state here.
- **Fails closed** — changes state that outlives the process. Must implement `recoverLeakedState()` and `allowsQuit()`, and must cap every session.

Getting this wrong is the worst bug this codebase can have: a fail-closed feature without recovery leaves the user's Mac altered with nothing left running to fix it.

## Structure

```
Sources/WardKit/                shared glue: logging, process, privileged exec, permissions, WardFeature
Sources/WardKit/Pure/           shared pure logic
Features/<Name>/Sources/        feature glue
Features/<Name>/Sources/Pure/   feature pure logic  ← the coverage gate measures these
Features/<Name>/Tests/
Sources/Ward/                   app shell — status item only, knows nothing about any feature
```

**`Pure/` is filesystem-enforced, not a convention.** `scripts/coverage.sh` finds every `Pure/` directory and requires ≥85%. If logic can be expressed as a function of its inputs, it goes there and gets tested.

## Adding a feature

1. `Features/<Name>/Sources/` + `Tests/`, plus `README.md` and `CLAUDE.md`
2. Two targets in `Package.swift` (library + test), depending on `WardKit`
3. Conform the controller to `WardFeature` in a `+WardFeature.swift` file
4. One line in `AppDelegate.features`

The shell never learns what a feature does. If you're editing `AppDelegate` for feature logic, the boundary is wrong.

## Commands

```bash
swift build && swift test
bash scripts/coverage.sh
bash scripts/make-app.sh            # → dist/Ward.app
bash scripts/make-icon.sh           # → Support/Ward.icns (only when changing the icon)
bash scripts/lid-sleep-probe.sh 90
```

Launch the built `.app`, never `swift run` — TCC grants attach to whatever launched the process.

## Environment facts (verified — don't re-derive)

- `pmset` is at `/usr/bin/pmset`. `lsof` and `netstat` are at `/usr/sbin/`. Use absolute paths — these are in *different* directories and guessing has already cost one silent-failure bug.
- An unprivileged `lsof` **cannot see other users' sockets**. A root-held port looks exactly like a free one (no rows, exit 1). `netstat -an -p tcp` needs no privileges and lists every listener — use it whenever "is this in use?" must be answered for ports you don't own.
- `pmset disablesleep` genuinely prevents clamshell sleep, verified against a control run that slept. Undocumented — re-verify with `lid-sleep-probe.sh` after macOS updates.
- Power assertions and `caffeinate` do **not** cover lid-close sleep. Don't propose them as a fix for it.
- No code-signing identity exists. Forces ad-hoc signing, re-granting Accessibility after rebuilds, blocks `SMAppService`. Several designs exist only because of this.
- Touch ID via `LAContext` is an **intent gate, not a privilege boundary**. Never describe it as security.

### Homebrew (verified during the Phase 0 spike)

- `brew audit --new --strict --online` **accepts a formula whose only payload is a `.app`**. Verified with a negative control, so the clean pass is real, not a skipped audit. The "formulae are CLI-only, apps belong in casks" convention is not enforced by any tool.
- SwiftPM evaluates `Package.swift` inside its own `sandbox-exec` sandbox, and the kernel refuses to nest that inside Homebrew's build sandbox. It surfaces as `Invalid manifest` with `sandbox_apply: Operation not permitted` buried underneath. `swift build --disable-sandbox` is the only fix — there is no environment variable for it. `make-app.sh` takes `WARD_DISABLE_SWIFTPM_SANDBOX=1`.
- **A formula cannot put anything in `/Applications`.** `post_install` runs sandboxed and `/Applications` is not on the allowlist (`Errno::EPERM`, observed), and `Keg.keg_link_directories` is `bin etc include lib sbin share var` — no linking mechanism reaches it. The symlink is the user's step; `caveats` prints it.
- A brew-installed Ward carries **no `com.apple.quarantine`** — only `com.apple.provenance`, which does not gate launch. Verified: launches with no Gatekeeper dialog and no `com.apple.syspolicy` activity at all, despite `spctl -a` still returning `rejected`. Quarantine is what makes macOS run that assessment on open; with no quarantine the rejection is never consulted. (`spctl` run by hand still consults it — the claim is about the launch path, not about Gatekeeper being unreachable.)
- Homebrew 5.x requires **tap trust**, and the two forms are not equivalent. `brew install shelupets89/ward/ward` auto-trusts that one formula and needs no interaction, even with stdin closed. `brew tap` followed by `brew install ward` fails outright: *"Refusing to load formula … from untrusted tap"*. Always document the fully-qualified command — the two-step form in the PRD's user flow does not work.
- `brew upgrade` **replaces both halves of the app's TCC identity**, measured across 0.2.0 → 0.2.1: the Cellar path changes with the version, and the ad-hoc CDHash changes with the rebuild. An Accessibility grant cannot survive it. The `/Applications` symlink does survive, because it points at the version-independent `opt` path.
- **A stale Accessibility entry keeps showing its toggle on while granting nothing.** Diagnosed by mtime, since TCC's database cannot be read: `TCC.db` had not been written for 65 minutes at a point when the running binary was 65 minutes old, so no grant for it could exist — yet the pane showed Ward enabled. Toggling that entry does not rebind it; it has to be removed with `−` and re-added. Worth knowing before debugging "Accessibility is on but `AXIsProcessTrusted()` is false", which is otherwise baffling.
- `/Library/Application Support/com.apple.TCC/TCC.db` is unreadable even with `sudo`, and `tccd` redacts its log messages. **Its mtime is readable**, uses no WAL sidecar files, and is therefore the one usable signal for "was a grant written since X".

## Non-negotiables

- Never write to `/etc/sudoers.d` or `/etc/pam.d` without validating the staged file first.
- Never weaken the cloth-proof esc-hold gesture. Changes there need tests.
- Timing uses `ContinuousClock`, never `Date()`.
- `os.Logger` via `WardLogger`, never `print()`.
- Failures the user would want to know about get an `NSAlert`, not just a log line.
- Don't `git init`, create remotes, or push to `main` (protected — use a worktree + PR).
