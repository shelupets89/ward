# Touch ID for sudo

Enables fingerprint authentication for `sudo` in Terminal, in one click.

**Status:** Planned · **Failure model:** fails **closed** — writes a persistent system file

## Why it isn't built in

There is no UI for this anywhere in macOS. Enabling it means knowing that `/etc/pam.d/sudo` already includes `sudo_local`, that `/etc/pam.d/sudo_local.template` exists, and that you copy it and uncomment one line. Every developer who wants this currently finds a blog post.

macOS ships the hook deliberately — `sudo_local` survives system updates, unlike editing `/etc/pam.d/sudo` directly. Ward just makes it discoverable.

## Behaviour

- Menu shows current state: **Touch ID for sudo: On / Off**.
- Enabling copies the template and uncomments `auth sufficient pam_tid.so`, after showing the exact file contents.
- Disabling removes `/etc/pam.d/sudo_local`.
- One authorization prompt per toggle.

## Safety

Editing PAM configuration badly can lock you out of `sudo` entirely — worse than the sudoers risk Ward already handles, because there's no `visudo` equivalent to validate PAM files.

Therefore:

- **Only ever write `/etc/pam.d/sudo_local`.** Never touch `/etc/pam.d/sudo` or any other PAM file. `sudo_local` is additive; if it's malformed, `sudo` still falls through to password auth.
- Write the file atomically, and verify it parses as expected before reporting success.
- The uninstall path must work even if the file is corrupt — removal is always safe.

## Design notes

Reuses `PrivilegedShellRunner` and the staged-file-then-install pattern from [`SudoersRule`](../KeepAwakeLidClosed/Sources/Pure/SudoersRule.swift). The shape is identical; only the destination and content differ.

Unlike the sudoers rule, there is no validator to run before install, so the mitigation is different: the file is additive-only and its absence is the safe default.

## Tests

| Test | Asserts |
| --- | --- |
| `PamTouchIDRuleTests` | File content has exactly the one uncommented `pam_tid.so` line; install command uses absolute paths, is `&&`-chained, targets **only** `sudo_local`, installs `0444 root:wheel` |
| `PamConfigParserTests` | Detects enabled vs commented-out vs absent vs a file containing unrelated rules |

Write both before any implementation. Manual: enable, run `sudo -k && sudo true` in Terminal → Touch ID prompt. Disable → password prompt returns.
