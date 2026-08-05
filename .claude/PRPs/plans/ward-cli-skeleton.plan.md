# Plan: `ward` CLI skeleton

## Summary

Add a `ward` command-line binary built from Ward's existing feature libraries. This phase delivers the executable target, hand-rolled argument parsing, `--version` and `--help` — no feature commands yet. It exists to prove an executable target composes with the feature libraries before any command depends on that.

## User Story

As a macOS developer with Ward installed, I want a `ward` command on my `PATH`, so that later phases can expose Ward's terminal-shaped features without restructuring anything.

## Problem → Solution

Ward's features are reachable only from a menu-bar app, and some of them (freeing a port, keeping awake until a build finishes) are needed while already in a terminal → a standalone binary sharing the same libraries, with no IPC and no duplicated logic.

## Metadata

- **Complexity**: Medium
- **Source PRD**: `.claude/PRPs/prds/homebrew-tap-and-cli.prd.md`
- **PRD Phase**: Phase 1 — CLI skeleton
- **Estimated Files**: 7 (5 create, 2 update)

> **Why Phase 1 and not Phase 0.** Phase 0 (formula spike) is a shell investigation — `brew audit`, install, upgrade, check whether Accessibility survives — with no code to plan. It is independent of this phase and should run in parallel. Its outcome can invalidate PRD Phase 4, not this one.

---

## UX Design

### Before
```
┌────────────────────────────────────┐
│ Terminal: "port 3001 in use"       │
│   → open menu bar → find item      │
│   → type port → confirm            │
│ (hands leave the keyboard)         │
└────────────────────────────────────┘
```

### After (this phase only)
```
┌────────────────────────────────────┐
│ $ ward --version                   │
│ ward 0.1.0                         │
│ $ ward --help                      │
│ (usage; commands land in phase 2+) │
└────────────────────────────────────┘
```

### Interaction Changes

| Touchpoint | Before | After | Notes |
|---|---|---|---|
| Binary on `PATH` | none | `ward` | Product name ≠ target name — see GOTCHA in Task 1 |
| Menu-bar app | unchanged | unchanged | CLI is standalone; no IPC, no shared state |

---

## Mandatory Reading

| Priority | File | Lines | Why |
|---|---|---|---|
| P0 | `Package.swift` | 41–56 | Exact target-block shape to copy; note there is **no `products:` section yet** |
| P0 | `Sources/Ward/WardApp.swift` | all | The only existing `@main` entry point |
| P0 | `Features/KeepScreenAwake/Sources/Pure/KeepScreenAwakeState.swift` | all | Newest `Pure/` type — doc-comment style, `Equatable, Sendable`, value semantics |
| P0 | `Features/KeepScreenAwake/Tests/KeepScreenAwakeStateTests.swift` | 1–25 | Swift Testing style: `struct` suite, `@Test("sentence")`, `#expect` |
| P1 | `Sources/WardKit/WardLogger.swift` | all | Logging categories; a new one is needed |
| P1 | `Sources/WardKit/BoundedProcess.swift` | 11–19 | Subprocess API for later phases |
| P2 | `CLAUDE.md` | all | `Pure/` rule, non-negotiables |
| P2 | `SECURITY.md` | "Scope" section | States Ward has **no dependencies** — this plan preserves that |

## External Documentation

| Topic | Source | Key Takeaway |
|---|---|---|
| SwiftPM executable products | `Package.swift` manifest reference | A binary's name comes from the **product**, not the target. Without a `products:` entry the binary is named after the target |

---

## Patterns to Mirror

### TARGET_DECLARATION
```swift
// SOURCE: Package.swift:41-50
        .target(
            name: "KeepScreenAwake",
            dependencies: ["WardKit"],
            path: "Features/KeepScreenAwake/Sources"
        ),
        .testTarget(
            name: "KeepScreenAwakeTests",
            dependencies: ["KeepScreenAwake"],
            path: "Features/KeepScreenAwake/Tests"
        ),
```

### PURE_TYPE
```swift
// SOURCE: Features/KeepScreenAwake/Sources/Pure/KeepScreenAwakeState.swift
/// What the Keep Screen Awake menu should show, derived from the session alone.
///
/// Unlike its lid-closed namesake there is no system setting to consult: the
/// assertion cannot outlive the process, so the session is the whole truth.
public enum KeepScreenAwakeState: Equatable, Sendable {
    case off
    case active(remaining: Duration)

    public init(session: KeepAwakeSession?, at instant: ContinuousClock.Instant) {
        guard let session, !session.isExpired(at: instant) else {
            self = .off
            return
        }
        self = .active(remaining: session.remaining(at: instant))
    }
}
```
Note: doc comment explains *why*, not what. `public`, `Equatable, Sendable`, no AppKit import.

### TEST_STRUCTURE
```swift
// SOURCE: Features/KeepScreenAwake/Tests/KeepScreenAwakeStateTests.swift:1-20
import Testing
import WardKit
@testable import KeepScreenAwake

/// The menu is rebuilt from this state on every open, so these cases are the
/// whole contract between a running session and what the user is offered.
struct KeepScreenAwakeStateTests {
    private let startInstant = ContinuousClock.now

    @Test("Is off when no session is running")
    func isOffWithoutSession() {
        #expect(KeepScreenAwakeState(session: nil, at: startInstant) == .off)
    }
}
```
Plain `struct` suite (no class, no XCTest), `@Test` with a sentence, `#expect`.

### LOGGING_PATTERN
```swift
// SOURCE: Sources/WardKit/WardLogger.swift
public enum WardLogger {
    public static let cleaningMode = Logger(subsystem: "com.dimashelupets.ward", category: "cleaning-mode")
    public static let keepAwake = Logger(subsystem: "com.dimashelupets.ward", category: "keep-awake")
}
```
Interpolations elsewhere use `privacy: .public` for non-sensitive values.

### ENTRY_POINT
```swift
// SOURCE: Sources/Ward/WardApp.swift
@main
enum WardApp {
    @MainActor
    static func main() {
        // ...
    }
}
```
`@main` on an `enum`, never a `main.swift` with top-level code.

---

## Files to Change

| File | Action | Justification |
|---|---|---|
| `Package.swift` | UPDATE | Add `products:` with an executable named `ward`; add `WardCLI` + `WardCLITests` targets |
| `Sources/WardCLI/WardCommandLine.swift` | CREATE | `@main` entry point |
| `Sources/WardCLI/Pure/CommandLineParser.swift` | CREATE | argv → `ParsedCommand`; pure and measured by the coverage gate |
| `Sources/WardCLI/Pure/UsageText.swift` | CREATE | `--help` text as a pure function |
| `Sources/WardKit/Pure/WardVersion.swift` | CREATE | Single version constant shared by app and CLI |
| `Tests/WardCLITests/CommandLineParserTests.swift` | CREATE | Parser contract |
| `Tests/WardKitTests/WardVersionTests.swift` | CREATE | Asserts the constant matches `Support/Info.plist` |

## NOT Building

- **Any feature command.** No `free-port`, `until`, `sleep-why`, `keep-awake`. Phase 2+.
- **swift-argument-parser or any external dependency.** See Task 2 rationale.
- **IPC with the menu-bar app.** The CLI never talks to a running Ward.
- **Shell completions, man page, colour output.** Not needed to validate the phase.
- **The Homebrew formula.** PRD Phase 4.

---

## Step-by-Step Tasks

### Task 1: Add the executable product and targets

- **ACTION**: Update `Package.swift`.
- **IMPLEMENT**: Add a `products:` array (the manifest has none today) with `.executable(name: "ward", targets: ["WardCLI"])`. Add `.executableTarget(name: "WardCLI", dependencies: ["WardKit"])` and `.testTarget(name: "WardCLITests", dependencies: ["WardCLI"])`.
- **MIRROR**: TARGET_DECLARATION.
- **IMPORTS**: n/a.
- **GOTCHA**: **The binary is named after the *product*, not the target.** Without the `products:` entry, `swift build` emits `WardCLI`, and the Homebrew formula in Phase 4 would install the wrong name. The target must stay `WardCLI` (Swift module names are conventionally capitalised) while the product is lowercase `ward`.
- **GOTCHA**: `WardCLI` depends on `WardKit` only — **not** on any feature library in this phase. Adding feature deps now would couple the skeleton to work that hasn't landed.
- **VALIDATE**: `swift build 2>&1 | grep -E "error:|Build complete"` then `ls "$(swift build --show-bin-path)/ward"`.

### Task 2: Write the argument parser tests (RED)

- **ACTION**: Create `Tests/WardCLITests/CommandLineParserTests.swift` **before** the parser.
- **IMPLEMENT**: Suite covering the table in Testing Strategy below.
- **MIRROR**: TEST_STRUCTURE.
- **IMPORTS**: `import Testing`, `@testable import WardCLI`.
- **GOTCHA**: **Do not add swift-argument-parser.** `SECURITY.md` states Ward has *no dependencies* and that supply-chain reports don't apply because there are none. A CLI with a handful of commands does not justify invalidating that claim — and hand-rolled parsing is pure, so it lands in `Pure/` and is covered by the existing gate. If a future phase genuinely needs subcommand ergonomics, that is a deliberate decision requiring a `SECURITY.md` update, not a side effect of this phase.
- **VALIDATE**: `swift test 2>&1 | grep "error: cannot find"` — expect failures naming `CommandLineParser`. Watch them fail before implementing.

### Task 3: Implement the parser (GREEN)

- **ACTION**: Create `Sources/WardCLI/Pure/CommandLineParser.swift`.
- **IMPLEMENT**:
  ```swift
  public enum ParsedCommand: Equatable, Sendable {
      case version
      case help
      case unknown(String)
  }

  public enum CommandLineParser {
      public static func parse(arguments: [String]) -> ParsedCommand
  }
  ```
  `arguments` excludes the executable path — the caller drops it. Empty → `.help`. `--version`/`-v`/`version` → `.version`. `--help`/`-h`/`help` → `.help`. Anything else → `.unknown(firstArgument)`.
- **MIRROR**: PURE_TYPE — `public`, `Equatable, Sendable`, doc comment explaining *why*, no AppKit import.
- **IMPORTS**: none (stdlib only).
- **GOTCHA**: Must live under `Sources/WardCLI/Pure/` exactly. `scripts/coverage.sh` discovers `Pure/` directories by `find` and requires ≥85% — a parser outside `Pure/` is silently unmeasured.
- **VALIDATE**: `swift test` green; `bash scripts/coverage.sh` still passes.

### Task 4: Share one version constant

- **ACTION**: Create `Sources/WardKit/Pure/WardVersion.swift` and `Tests/WardKitTests/WardVersionTests.swift`.
- **IMPLEMENT**: `public enum WardVersion { public static let current = "0.1.0" }`. The test locates `Support/Info.plist` relative to `#filePath` and asserts `CFBundleShortVersionString` equals `WardVersion.current`.
- **MIRROR**: PURE_TYPE, TEST_STRUCTURE.
- **IMPORTS**: test needs `import Foundation` for `PropertyListSerialization`.
- **GOTCHA**: A CLI binary has no `Bundle.main` Info.plist, so it cannot read the version at runtime the way the app does. Two sources of truth is the real risk — the test is what keeps them honest, and `release.yml` already fails a tag that disagrees with `Info.plist`, so a drifted constant is caught twice.
- **GOTCHA**: Derive the repo root from `#filePath`, not the current working directory — `swift test` does not guarantee the CWD.
- **VALIDATE**: `swift test`; then temporarily edit the constant and confirm the test fails.

### Task 5: Usage text

- **ACTION**: Create `Sources/WardCLI/Pure/UsageText.swift`.
- **IMPLEMENT**: `public enum UsageText { public static func render() -> String }`. Lists `--version`, `--help`, and a line stating feature commands are not yet available.
- **MIRROR**: PURE_TYPE.
- **GOTCHA**: Keep it a pure function returning a `String` — no `print` inside, so it stays testable.
- **VALIDATE**: Test asserts the output names both flags.

### Task 6: Entry point

- **ACTION**: Create `Sources/WardCLI/WardCommandLine.swift`.
- **IMPLEMENT**:
  ```swift
  @main
  enum WardCommandLine {
      static func main() {
          let arguments = Array(CommandLine.arguments.dropFirst())
          switch CommandLineParser.parse(arguments: arguments) {
          case .version: print("ward \(WardVersion.current)")
          case .help: print(UsageText.render())
          case .unknown(let argument):
              FileHandle.standardError.write(Data("Unknown command: \(argument)\n".utf8))
              print(UsageText.render())
              exit(64)
          }
      }
  }
  ```
- **MIRROR**: ENTRY_POINT — `@main` on an `enum`, no `main.swift`.
- **IMPORTS**: `import Foundation`, `import WardKit`.
- **GOTCHA**: **Never touch `NSApplication` here.** `WardKit` transitively links AppKit, so it compiles — but instantiating `NSApplication` from a CLI would try to start a GUI session. The CLI must stay headless.
- **GOTCHA**: `exit(64)` is `EX_USAGE`; do not use `exit(1)` for a usage error.
- **GOTCHA**: A file named `main.swift` in the same target conflicts with `@main`. Name it `WardCommandLine.swift`.
- **VALIDATE**: `swift run ward --version` prints `ward 0.1.0`; `swift run ward --help` prints usage; `swift run ward bogus; echo $?` prints 64.

### Task 7: Logging category

- **ACTION**: Update `Sources/WardKit/WardLogger.swift`.
- **IMPLEMENT**: Add `public static let commandLine = Logger(subsystem: "com.dimashelupets.ward", category: "command-line")`.
- **MIRROR**: LOGGING_PATTERN.
- **GOTCHA**: A CLI reports to stdout/stderr, not the unified log — this category is for later phases that hold assertions or spawn processes. Do not route usage errors through it.
- **VALIDATE**: `swift build`.

---

## Testing Strategy

### Unit Tests

| Test | Input | Expected Output | Edge Case? |
|---|---|---|---|
| Empty arguments → help | `[]` | `.help` | ✅ |
| Long version flag | `["--version"]` | `.version` | |
| Short version flag | `["-v"]` | `.version` | |
| Bare subcommand form | `["version"]` | `.version` | |
| Long help flag | `["--help"]` | `.help` | |
| Short help flag | `["-h"]` | `.help` | |
| Unknown command | `["frobnicate"]` | `.unknown("frobnicate")` | ✅ |
| Extra args ignored for now | `["--version", "extra"]` | `.version` | ✅ |
| Empty string argument | `[""]` | `.unknown("")` | ✅ |
| Version constant matches plist | `Support/Info.plist` | equals `WardVersion.current` | ✅ |
| Usage names both flags | — | contains `--version` and `--help` | |

### Edge Cases Checklist
- [x] Empty input → `.help`, never a crash
- [x] Unknown input → `.unknown`, exit 64, usage printed
- [x] Empty-string argument
- [ ] Concurrent access — n/a, parser is a pure function
- [ ] Network failure — n/a, no network
- [ ] Permission denied — n/a this phase

---

## Validation Commands

### Static Analysis
```bash
swift build 2>&1 | grep -E "error:|warning:|Build complete"
```
EXPECT: `Build complete!`, no errors or warnings.

### Unit Tests
```bash
swift test 2>&1 | grep -E "Test run with|Executed [0-9]+ tests, with"
```
EXPECT: all pass, count increased by ~11.

### Coverage Gate
```bash
bash scripts/coverage.sh
```
EXPECT: `✅ Pure/ line coverage …% (minimum 85%)` and `Sources/WardCLI/Pure` listed in the table.

### Binary Name
```bash
ls "$(swift build --show-bin-path)/ward"
```
EXPECT: the file exists — proves the `products:` entry works.

### App Still Builds
```bash
bash scripts/make-app.sh && open dist/Ward.app && sleep 3 && pgrep -x Ward && killall Ward
```
EXPECT: menu-bar app unaffected.

### Manual Validation
- [ ] `swift run ward --version` → `ward 0.1.0`
- [ ] `swift run ward --help` → usage listing both flags
- [ ] `swift run ward bogus` → error on stderr, usage on stdout, `$?` is 64
- [ ] `swift run ward` (no args) → usage, exit 0
- [ ] Menu-bar app launches and quits normally

---

## Acceptance Criteria
- [ ] All tasks completed
- [ ] All validation commands pass
- [ ] Tests written **before** implementation, observed failing first
- [ ] No new external dependencies
- [ ] `Sources/WardCLI/Pure/` appears in the coverage table

## Completion Checklist
- [ ] Code follows discovered patterns
- [ ] Logging follows `WardLogger` conventions
- [ ] Tests use Swift Testing, not XCTest
- [ ] No hardcoded values outside `WardVersion`
- [ ] PRD Phase 1 marked `in-progress` then `complete`
- [ ] No scope additions — no feature commands

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Binary named `WardCLI` instead of `ward` | **M** | Phase 4 formula installs wrong name | `products:` entry; validated by the Binary Name command |
| Version constant drifts from `Info.plist` | **M** | CLI reports a stale version | Test asserts equality; `release.yml` already gates tags |
| Pure logic placed outside `Pure/` | **M** | Silently unmeasured by the gate | Coverage command must list `Sources/WardCLI/Pure` |
| Temptation to add swift-argument-parser | **M** | Invalidates the "no dependencies" claim in `SECURITY.md` | Explicit NOT-building item; hand-rolled parser is ~30 lines |
| `ward` collides with another binary on `PATH` | **L** | Confusing shadowing | PRD open question; check `command -v ward` on a clean machine before Phase 4 |

## Notes

- This phase deliberately delivers no user-visible feature. Its value is the answer to "does an executable target compose with these libraries" — cheap to learn now, expensive to learn in Phase 4.
- `KeepScreenAwake` shipped through the same modular structure and confirmed a feature is two targets plus one line, so the pattern is proven rather than theoretical.
- `ward until <command>` (PRD Phase 2) should be built **CLI-first**: wrapping a command gives exact lifetime with no polling, which is strictly simpler than the process-watching design specced for the menu version.
