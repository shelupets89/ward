# Keep Awake Until Exit

Stays awake while something is still running — a build, a long script, a dev server on a port.

**Status:** Planned · **Failure model:** fails open

## Why it isn't built in

`caffeinate -w <pid>` exists and does roughly this, but you have to already know the PID, keep a terminal open, and it only covers idle sleep. There's no way to say "stay awake while `claude` is running" or "while something is listening on 3001".

## Behaviour

- Menu → **Keep Awake Until…** → pick from running candidates, or type a target.
- Targets accept three forms:
  - a process name — `claude`
  - a port — `:3001` or `3001`
  - a PID — `pid 1234`
- Holds an assertion until the target disappears, then releases it and notifies.
- A safety cap still applies: if the target outlives the cap, the session ends anyway.

## Design notes

Polling beats watching. `kqueue` can watch a PID for exit, but a *name* or *port* target may not exist yet and its PID changes across restarts — so poll every few seconds and resolve the target each time. `pgrep` for names, `lsof -ti` for ports.

The interesting logic is entirely pure: parsing a target spec and deciding whether a process list satisfies it. That's where the tests go; the polling loop is trivial glue.

Fails open — the assertion dies with the process, so nothing to recover.

## Tests

| Test | Asserts |
| --- | --- |
| `WatchTargetParserTests` | `claude` → name; `:3001` and `3001` → port; `pid 1234` → PID; whitespace and empty input rejected; ambiguous input resolves predictably |
| `WatchTargetMatcherTests` | Given sample `pgrep` / `lsof` output, decides alive vs gone; a name matching a substring of another process does not count; multiple matches count as alive |

Both are pure and get written first. Manual: start `sleep 60`, watch it, confirm the assertion appears in `pmset -g assertions` and disappears within one poll of the process exiting.
