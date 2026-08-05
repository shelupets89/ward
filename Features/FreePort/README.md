# Free a Port

Kills whatever is holding a TCP port — the "port 3001 is already in use" fix, without the terminal.

**Status:** Shipped · **Failure model:** neither — see below

## Why it isn't built in

macOS has no way to answer "what's on port 3001", let alone stop it. The usual fix is a chain nobody remembers:

```bash
lsof -ti tcp:3001 | xargs kill
```

…which fails silently when nothing is listening, and doesn't escalate when the process ignores `SIGTERM`.

## This is Ward's first destructive feature

Every other feature is reversible: turn Cleaning Mode off, restore sleep, release an assertion. **Killing a process is not.** Unsaved work is gone, and `SIGKILL` gives the process no chance to clean up.

It also doesn't fit the fail-open / fail-closed split the other features use — it's a one-shot action, not a state toggle. `WardFeature`'s defaults are correct here (nothing to recover, nothing to gate on quit), but the taxonomy in the root `CLAUDE.md` doesn't describe it, and that's fine as long as nobody tries to force it into one.

The safety design is therefore entirely front-loaded: **show exactly what will die, before anything dies.**

## Behaviour

- Menu → **Free a Port…** asks for a port. `3001`, `:3001` and `tcp:3001` all work.
- Menu → **Ports in Use** lists what's currently listening (port, command, PID), so the common case needs no typing. It's populated on demand — a full `lsof` costs ~200ms and shouldn't be paid on every menu open.
- Confirmation names the processes — `node (pid 26036)`, not "2 processes".
- `SIGTERM` first, wait ~2s, then `SIGKILL` any survivors, then verify the port is actually free.
- Reports the outcome: freed, still held, or nothing was listening.

## Constraints

**Never escalate privileges.** Only processes the user owns get killed. A port held by root (22, 80, 443) is reported, not `sudo`-killed. This keeps the blast radius to things the user could have killed from their own shell anyway, and it means a typo can't take down a system daemon.

**Show, don't assume.** On this machine `ControlCenter` holds ports **5000 and 7000** for AirPlay Receiver — and 5000 is a very common dev port. A blind `kill` on a mistyped port would take out Control Center. The confirmation exists for exactly this.

**Dedup by PID.** `lsof` lists IPv4 and IPv6 rows separately, so one process appears twice. Killing "two processes" that are one PID is a confusing lie.

**An unprivileged `lsof` cannot see other users' sockets at all.** A root-held port produces no rows and a non-zero exit — byte-for-byte identical to a free port. Left there, "never kill a root-held port" would have been unreachable in practice: Ward would have said *"nothing was listening"* about port 22 and sent the user back to try again. Occupancy is therefore read from `netstat -an -p tcp`, which needs no privileges and lists every listener regardless of owner. `netstat` answers *whether* a port is taken; `lsof` remains the only source for *who* holds it, and only ever for processes this user could signal.

## Layout

| Path | Contents |
| --- | --- |
| `Sources/Pure/` | `PortSpecParser`, `ListeningProcessParser`, `OccupiedPortParser`, `KillEscalation`, `PortSnapshot`, `ListeningProcess`, `FreePortMessages` |
| `Sources/` | `PortInspector` (`lsof`/`netstat` via `BoundedProcess`), `ProcessSignaller` (`kill(2)`), controller, menu |

`FreePortMessages` is in `Pure/` deliberately: the confirmation dialog is the entire safety mechanism, so what it says is a tested property rather than incidental copy.

`ProcessSignaller` calls `kill(2)` directly instead of going through `BoundedProcess`. Spawning `/bin/kill` would add a process that can hang and would flatten `EPERM` ("you may not") and `ESRCH` ("already gone") into one exit status — and those two mean opposite things here.

## Tests

| Test | Asserts |
| --- | --- |
| `PortSpecParserTests` | `3001`, `:3001`, `tcp:3001` all parse; `0`, `65536`, `-1`, `abc`, empty rejected; surrounding whitespace tolerated |
| `ListeningProcessParserTests` | Real `lsof` output → entries with command, pid, user, port; header row skipped; IPv4/IPv6 duplicates collapse to one PID; `\x20` escapes decoded; non-positive pids and non-LISTEN rows refused; malformed lines skipped rather than throwing |
| `OccupiedPortParserTests` | Real `netstat` output → listening ports; IPv4, IPv6 and dual-stack rows; non-listening connections and headers ignored |
| `KillEscalationTests` | TERM first; escalates to KILL only for survivors after the wait; stops when the port frees early; reports still-held when survivors persist; never escalates when nothing was listening; never signals another user's process; never force-kills a pid the user was not shown |
| `FreePortMessagesTests` | The confirmation names every target by command and pid, never as a count; says the action cannot be undone; separates processes it will not touch |

Written first, all pure. The `lsof`/`netstat`/`kill` calls are thin glue on top.

Manual: start `python3 -m http.server 3456`, free it from the menu, confirm the process is gone and the port is clear. Then try a port held by another user and confirm it is reported rather than killed.
