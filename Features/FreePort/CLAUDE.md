# Free a Port — notes for Claude

**Destructive and irreversible.** The only feature in Ward that can lose the user's work. Everything else here toggles state that can be toggled back; a killed process is gone, and `SIGKILL` denies it any cleanup.

It is neither fail-open nor fail-closed — it's a one-shot action. Take the `WardFeature` defaults (nothing to recover, nothing to gate on quit) and don't try to force it into the root `CLAUDE.md` taxonomy.

## Invariants

- **Never kill without showing what will die first.** Name the command and PID, not a count. This is the feature's entire safety story, since nothing can be undone afterwards.
- **Never escalate privileges.** No `sudo`, no `PrivilegedShellRunner`. A port held by another user or root is *reported*, never killed. Blast radius stays at what the user could have killed from their own shell.
- **Dedup by PID before showing or killing.** `lsof` emits separate IPv4 and IPv6 rows for one process; reporting "2 processes" for one PID is a lie the user acts on.
- **Verify after killing.** Re-check the port rather than assuming `kill` succeeded — the whole point is knowing the port is actually free.
- **Escalation is bounded by the pids the user approved.** A port freed by `SIGTERM` can be grabbed by a different process inside the two-second grace period; `SIGKILL`ing it would kill something that was never named in any dialog. `KillEscalation.Stage` carries `approvedTargets` so this cannot be forgotten — don't replace it with "whatever holds the port now".
- **A refused signal is not a survived one, and neither list may be dropped.** `kill(2)` can return `EPERM` even for a process this user owns. `stillHeld` therefore carries *two* lists — `signalled` (outlived a delivered SIGKILL) and `undelivered` (never received one) — and both are rendered. An earlier shape reported only the undelivered ones and silently dropped a process still holding the port, which is the same failure as reporting a count instead of names. `undeliveredTargets` is the SIGKILL round's result **only**: a pid refused at SIGTERM whose SIGKILL then landed *was* signalled, and folding the earlier refusal in would report it as untouched.
- **Never report a signal Ward did not send.** `stillHeld` means "we signalled this and it is still here"; `takenByAnotherProcess` means "what you approved is gone and something else is on the port now". Collapsing them back into one case puts *"it survived both SIGTERM and SIGKILL"* under a process that was never signalled — the review caught exactly that. For the same reason `unreadablePort` ("nothing was changed") must never be shown after a signal has gone out; that is what `unverifiablePort` is for.
- **A failed check is not an empty result.** `lsof` exits non-zero both for "nothing matched" and for "never ran", so `BoundedProcess.Outcome.didRun` is the only thing separating them. Reading a failed check as "no holders" reports a port the user owns as belonging to somebody else.
- **Never pass a non-positive pid to `kill(2)`.** It reads `0` as the whole process group and `-1` as every process the user owns. Both the parser and `ProcessSignaller` refuse them; keep both locks.

## Gotchas

- **`lsof` is at `/usr/sbin/lsof`**, not `/usr/bin`. `netstat` is at `/usr/sbin/netstat`. Use absolute paths; don't rely on `PATH`.
- `lsof -ti tcp:PORT` exits non-zero when nothing matches. That's normal, not an error — don't surface it as a failure.
- **An unprivileged `lsof` cannot see other users' sockets at all** — verified: five ports listening per `netstat` returned zero `lsof` rows and exit 1, exactly like a free port. This is why `OccupiedPortParser` exists. Never re-derive "nothing was listening" from empty `lsof` output alone; that reading makes the root-held case unreachable and tells the user a port is free while their `EADDRINUSE` says otherwise.
- **Ownership is compared by numeric UID, not login name.** `lsof -l` prints UIDs, matched against `getuid()`. Comparing formatted login names invites a truncation mismatch, and the whole feature turns on that comparison being exact.
- `lsof` writes its `WARNING: can't stat()` noise to **stderr**, which `BoundedProcess` already discards. The parser skips unparsable lines anyway — don't rely on only one of those two.
- **`ControlCenter` holds ports 5000 and 7000** on macOS for AirPlay Receiver, and 5000 is a common dev port. This is the concrete case the confirmation dialog exists for.
- A process can hold a port and be un-killable by the user (root-owned). `kill` fails with EPERM — report it plainly rather than retrying or escalating.
- The port may free itself between listing and killing. Handle "already gone" as success, not as an error.
- All subprocess calls go through `BoundedProcess` — but bounded is not free: it blocks its thread for up to ten seconds, so on the main actor a hung `lsof` freezes the whole app, not just the menu. Every inspection runs off the main actor, and the "Ports in Use" submenu fills in asynchronously behind a placeholder. Don't move those calls back onto the main thread for simplicity.

## Layout

`Sources/Pure/` — `PortSpecParser` (string → port), `ListeningProcessParser` (`lsof` output → deduped entries), `KillEscalation` (TERM → wait → KILL → verify, as a state machine). All testable with captured fixtures.

`Sources/` — subprocess calls, confirmation UI, controller, `WardFeature` conformance.
