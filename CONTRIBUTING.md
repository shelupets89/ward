# Contributing

## Before a PR

```bash
swift test
bash scripts/coverage.sh
```

Both run in CI along with ShellCheck and a packaging check. `main` is protected — PRs only.

## Two rules

**1. Decidable logic goes in `Pure/`.** If it's a function of its inputs, it belongs in a `Pure/` directory with tests. The coverage gate measures those automatically and requires ≥85%. Everything else is glue that needs a running app and granted permissions — don't write fake tests for it.

**2. Every feature declares a failure model.**

- *Fails open* — effects die with the process. Nothing persistent.
- *Fails closed* — changes state outliving the process. Must cap sessions, implement `recoverLeakedState()` and `allowsQuit()`.

Mixing these up is the most damaging mistake available here.

## Adding a feature

1. `Features/<Name>/Sources/` + `Tests/`, with `README.md` and `CLAUDE.md`
2. Library + test targets in `Package.swift`, depending on `WardKit`
3. Conform to `WardFeature` in `<Name>+WardFeature.swift`
4. One line in `AppDelegate.features`

If you're editing `AppDelegate` for feature logic, the boundary is wrong.

## Security-sensitive changes

Ward runs commands as root, writes to `/etc/sudoers.d`, and intercepts every keystroke. See [SECURITY.md](SECURITY.md) for the files that get extra scrutiny.

**Do not weaken `ShellQuotingTests` or `SudoersRuleTests` to make a change pass.** Those tests exist to catch exactly the change that would need them weakened.

## Style

Follow the surrounding code. Named exports, no force-unwraps, `ContinuousClock` for timing, `WardLogger` over `print()`. Conventional Commits with a gitmoji prefix.
