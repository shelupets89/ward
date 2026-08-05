# Touch ID for sudo — notes for Claude

**Fails closed.** Writes a file to `/etc/pam.d/` that survives quit, crash and reboot.

## Invariants

- **Only ever write `/etc/pam.d/sudo_local`.** Never `/etc/pam.d/sudo`, never any other PAM file. macOS provides `sudo_local` precisely so local changes survive system updates, and because it's additive a malformed one degrades to password auth rather than locking `sudo` out.
- **There is no `visudo` for PAM.** The sudoers pattern validates before installing; here you cannot. The mitigation is that the file is additive and its absence is the safe default — never introduce a code path that makes an existing working `sudo` depend on this file.
- **Removal must always work**, even if the file is corrupt or hand-edited. `rm` is the uninstall path; don't gate it on parsing.
- **Show the exact file content before writing.** Same rule as the sudoers installer — an app changing system auth config states what it's changing.

## Gotchas

- `/etc/pam.d/sudo` already contains `auth include sudo_local` as its first line on macOS 14+. Verify that before assuming the hook exists; on an older system the whole approach differs.
- The template lives at `/etc/pam.d/sudo_local.template` and contains the line commented out. Copy-and-uncomment rather than authoring content from scratch — Apple may change the directive.
- `pam_tid` works for Terminal `sudo`. Whether it fires for a GUI-spawned `sudo` with no controlling terminal is **unverified** — do not build anything in Ward that depends on it.
- This is genuinely useful and genuinely dangerous. It is the one feature where a bug means the user cannot `sudo` to fix it. Test the uninstall path first.

## Layout

`Sources/Pure/` — `PamTouchIDRule` (file content + install command), `PamConfigParser` (reads current state).

`Sources/` — installer using `PrivilegedShellRunner`, controller, `WardFeature` conformance.
