# Security Policy

## Reporting a vulnerability

Use GitHub's [private vulnerability reporting](https://github.com/shelupets89/ward/security/advisories/new) — not a public issue. Please allow a reasonable window before disclosing.

Ward is a personal project maintained in spare time. There is no SLA, but anything that could give an attacker root or intercept a password will be treated as urgent.

## Why this repo needs more care than its size suggests

Ward is small, but it does three things that make a subtle malicious change expensive:

1. **It runs commands as root.** `PrivilegedShellRunner` executes through `sudo` or macOS's authorization prompt.
2. **It writes a `sudoers` rule.** `SudoersRule` builds a file that lands in `/etc/sudoers.d/`. A malformed rule breaks `sudo` machine-wide; a *malicious* one is a local privilege escalation.
3. **It intercepts all keyboard input.** Cleaning Mode installs a session-wide `CGEventTap` that sees every keystroke.

A plausible-looking change to string escaping, argument construction, or the event-tap callback is enough to weaponise any of these. That is the threat this repo actually guards against.

### Files where changes get extra scrutiny

| File | Why |
| --- | --- |
| `Sources/WardCore/ShellQuoting.swift` | Shell + AppleScript escaping for a root command line |
| `Sources/WardCore/SudoersRule.swift` | Builds the rule written to `/etc/sudoers.d/` |
| `Sources/Ward/PrivilegedShellRunner.swift` | Executes as root |
| `Sources/Ward/LidSleepSetting.swift` | Chooses the arguments passed to root |
| `Sources/Ward/InputBlocker.swift` | Sees every keystroke |
| `scripts/install-sudoers-rule.sh` | Installs the rule from a shell |
| `.github/workflows/` | Runs on CI with repository context |

These are covered by [CODEOWNERS](.github/CODEOWNERS) and by tests that pin their invariants — `ShellQuotingTests` asserts injection payloads stay inert, and `SudoersRuleTests` asserts the rule has no wildcards and is `visudo`-validated *before* install. **Do not weaken or delete those tests to make a change pass.**

## Design decisions that are intentional, not bugs

Please don't report these as vulnerabilities — they're documented trade-offs:

- **Touch ID is an intent gate, not a privilege boundary.** `LAContext` cannot grant root; the sudoers rule does. Anything already running as your user can call `pmset` directly without passing through Touch ID. It exists to make a persistent system change deliberate, not to stop an attacker.
- **The sudoers rule grants the *user*, not the app.** That's inherent to the sudoers approach. It is scoped to exactly two `pmset` invocations with no wildcards, so it confers no other root capability.
- **Builds are ad-hoc signed.** There is no paid Developer ID, so releases are not notarized and macOS Gatekeeper will warn. Building from source avoids this entirely.
- **Cleaning Mode cannot block the power button or lid close.** Those are hardware-level, and the power button is deliberately the escape hatch of last resort.

## CI posture

- Workflows use `pull_request`, never `pull_request_target` — fork PRs get a read-only token and no access to secrets.
- Every workflow declares least-privilege `permissions:` explicitly rather than inheriting repository defaults.
- Workflow runs from first-time contributors require manual approval.

## Scope

Ward has no network code, no telemetry, no accounts, and no dependencies. Reports about data exfiltration or supply-chain risk in dependencies do not apply — there are none.

One thing does sit in the trust chain: the Homebrew tap. `brew install shelupets89/ward/ward` builds whatever source the formula in [`shelupets89/homebrew-ward`](https://github.com/shelupets89/homebrew-ward) points at, and `brew upgrade` does it again without the user looking at this repository. That formula is written only by the release workflow, using a fine-grained `TAP_PUSH_TOKEN` scoped to `Contents: write` on the tap and nothing else, and it pins an exact tarball by `sha256`. Write access to the tap repo, or that token, is therefore worth the same scrutiny as write access here. Reports about either are in scope.
