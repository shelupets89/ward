## What changed

<!-- One or two sentences. Why, not just what. -->

## Checks

- [ ] `swift test` passes
- [ ] `bash scripts/coverage.sh` passes (WardCore ≥ 85%)
- [ ] New pure logic went into `WardCore` with tests, not into the glue layer

## If this touches security-sensitive code

Shell quoting, the sudoers rule, the privileged runner, or the event tap — see [SECURITY.md](../SECURITY.md).

- [ ] I did **not** modify or delete `ShellQuotingTests` / `SudoersRuleTests` to make this pass
- [ ] Any new argument reaching a root command is quoted through `ShellQuoting`
- [ ] Anything written to `/etc/sudoers.d` is still `visudo -c` validated before install

## Manual verification

<!-- CI can't grant TCC permissions or close a lid. Which README manual-test
     steps did you actually run? "None" is a valid answer for docs-only PRs. -->
