# Free a Port

Kills whatever is holding a TCP port — the "port 3001 is already in use" fix, without the terminal.

**Status:** Planned · **Failure model:** neither — see below

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

- Menu → **Free a Port…** lists what's currently listening (command, PID, port), so the common case needs no typing.
- Or enter a port directly.
- Confirmation names the processes — `node (pid 26036)`, not "2 processes".
- `SIGTERM` first, wait ~2s, then `SIGKILL` any survivors, then verify the port is actually free.
- Reports the outcome: freed, still held, or nothing was listening.

## Constraints

**Never escalate privileges.** Only processes the user owns get killed. A port held by root (22, 80, 443) is reported, not `sudo`-killed. This keeps the blast radius to things the user could have killed from their own shell anyway, and it means a typo can't take down a system daemon.

**Show, don't assume.** On this machine `ControlCenter` holds ports **5000 and 7000** for AirPlay Receiver — and 5000 is a very common dev port. A blind `kill` on a mistyped port would take out Control Center. The confirmation exists for exactly this.

**Dedup by PID.** `lsof` lists IPv4 and IPv6 rows separately, so one process appears twice. Killing "two processes" that are one PID is a confusing lie.

## Layout

| Path | Contents |
| --- | --- |
| `Sources/Pure/` | `PortSpecParser`, `ListeningProcessParser`, `KillEscalation` |
| `Sources/` | `lsof`/`kill` invocation via `BoundedProcess`, confirmation UI, controller |

## Tests

| Test | Asserts |
| --- | --- |
| `PortSpecParserTests` | `3001`, `:3001`, `tcp:3001` all parse; `0`, `65536`, `-1`, `abc`, empty rejected; surrounding whitespace tolerated |
| `ListeningProcessParserTests` | Real `lsof -iTCP -sTCP:LISTEN -P -n` output → entries with command, pid, user, port; header row skipped; IPv4/IPv6 duplicates collapse to one PID; malformed lines skipped rather than throwing |
| `KillEscalationTests` | TERM first; escalates to KILL only for survivors after the wait; stops when the port frees early; reports still-held when survivors persist; never escalates when nothing was listening |

All three are pure and get written first. The `lsof`/`kill` calls are thin glue on top.

Manual: start `python3 -m http.server 3001`, free it, confirm the process is gone and the port is clear. Then try a root-held port (22) and confirm it's reported rather than killed.
