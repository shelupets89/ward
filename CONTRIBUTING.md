# Contributing

Ward is a personal project, but PRs are welcome. A few things will make yours land faster.

## Before you open a PR

```bash
swift build
swift test                  # must be green
bash scripts/coverage.sh    # WardCore must stay ≥ 85%
```

## The one architectural rule

```
Sources/WardCore   pure, decidable logic — always unit-tested, never imports AppKit
Sources/Ward       AppKit/IOKit/LocalAuthentication glue — not unit-testable
```

**If your logic can be expressed as a function of its inputs, it belongs in `WardCore` with tests.** That is the quality gate here — not a coverage number on the glue layer, which would only reward writing fake tests for AppKit.

Only `WardCore` has a coverage requirement, deliberately.

## Invariants that must survive your change

These have all been broken once already and caught in review. Changes touching them need tests.

- **The esc-hold exit gesture is cloth-proof.** Any key or modifier pressed alongside `esc` cancels the hold and suppresses it until `esc` is physically released. A cloth dragged across the keyboard must never exit Cleaning Mode.
- **Cleaning Mode fails open.** Every restriction dies with the process. Nothing it acquires may outlive the app.
- **Keep Awake fails closed**, so it needs its safety net: a hard session cap, a quit-time gate, a leak check on launch and every menu open, and a retry when a restore fails. Don't add an uncapped "until I turn it off" option — the cap *is* the safety feature.
- **Timing uses `ContinuousClock`, never `Date()`.** A wall-clock jump must not shorten the exit hold or a keep-awake session.
- **Never write to `/etc/sudoers.d` without `visudo -c` validating the staged file first.** An invalid file there breaks `sudo` for the whole machine.

## Security-sensitive code

Ward runs commands as root and intercepts every keystroke. Changes to shell quoting, the sudoers rule builder, the privileged runner, or the event tap get extra scrutiny — see [SECURITY.md](SECURITY.md) for the list and the reasoning.

`ShellQuotingTests` and `SudoersRuleTests` exist specifically to catch a subtle weakening of those paths. **A PR that modifies or removes them to go green will be rejected.** If a test is genuinely wrong, say so in the PR and explain why.

## Style

- Swift Testing (`import Testing`) for new tests.
- `os.Logger` via `WardLogger`, never `print()`.
- Failure paths a user would want to know about get an `NSAlert`, not just a log line.
- Conventional Commits with a gitmoji prefix: `📝 docs(readme): …`, `🐛 fix(keep-awake): …`.

## What you can't test locally

Cleaning Mode and Keep Awake both need granted permissions and a real machine. The README's manual test plan covers what CI can't reach — please run the relevant steps and say so in your PR.
