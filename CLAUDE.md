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

## Non-negotiables

- Never write to `/etc/sudoers.d` or `/etc/pam.d` without validating the staged file first.
- Never weaken the cloth-proof esc-hold gesture. Changes there need tests.
- Timing uses `ContinuousClock`, never `Date()`.
- `os.Logger` via `WardLogger`, never `print()`.
- Failures the user would want to know about get an `NSAlert`, not just a log line.
- Don't `git init`, create remotes, or push to `main` (protected — use a worktree + PR).
