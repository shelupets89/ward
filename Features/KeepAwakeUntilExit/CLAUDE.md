# Keep Awake Until Exit — notes for Claude

**Fails open.** The assertion dies with the process. No recovery hooks needed.

## Invariants

- **Resolve the target on every poll, not once.** A name or port target may not exist yet, and its PID changes when the process restarts. Caching the first PID silently breaks the feature the moment a dev server reloads.
- **Keep the safety cap.** A target that never exits must not mean an unbounded session — a typo'd process name would otherwise hold an assertion forever.
- **Substring matches don't count.** `claude` must not match `claude-helper`. Get this right in `WatchTargetMatcher` with tests, not in the polling loop.

## Gotchas

- `pgrep -x` matches exact names; plain `pgrep` matches substrings. Use the former.
- `lsof -ti :3001` needs no root for your own processes but returns nothing for another user's. Treat "no output" as gone, and don't try to escalate.
- All subprocess calls go through `BoundedProcess` — polling on the main actor with an unbounded `waitUntilExit` would freeze the menu.
- Poll interval is a trade-off: too tight wastes CPU on `lsof`, too loose leaves the Mac awake after the build finished. A few seconds is right; don't make it a preference.

## Layout

`Sources/Pure/` — `WatchTargetParser` (spec string → target), `WatchTargetMatcher` (target + process listing → alive?). Both fully testable with sample command output.

`Sources/` — polling timer, assertion handling, controller, `WardFeature` conformance.
