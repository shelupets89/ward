# Plan: Explain before handing off — permission escalation ordering

> **Revision 2.** Four review agents rejected revision 1's central move. Their findings, and what changed, are in [Review History](#review-history) at the end. Revision 1 proposed a `PermissionEscalation.escalate(byExplaining:thenIfChosen:)` combinator; that is gone.

## Summary
Both permission flows in `InputPermissions` fire a system prompt and then immediately open Ward's own alert, so two modals stack and the one that can name the bundle sits behind the one that cannot. The prompt should fire only once the user has read Ward's alert and chosen to open settings — where it still does the job that justifies keeping it: putting a row in the pane.

The sequencing decision moves into `Pure/` as a step machine, mirroring `KillEscalation`. The glue is left holding leaf calls only, so the ordering is not something it can get wrong.

**This does not reduce the accepting user to one dialog.** They still see the system modal, now *after* consent instead of over the explanation. The cancelling user sees one dialog where they saw two.

## User Story
As someone turning on Cleaning Mode after an upgrade,
I want to read which Ward is asking before macOS interrupts,
So that I grant the right build instead of flipping a switch that is already on and grants nothing.

## Problem → Solution
Two modals race to the front, the informative one behind → the explanation is read first, and the system is only involved once the user has acted on it.

## Metadata
- **Complexity**: Small
- **Source PRD**: N/A — observed 2026-08-22 after `brew upgrade ward` to 0.3.0
- **Estimated Files**: 3 (1 new pure source, 1 new test, 1 edited)

---

## Both flows have this bug, not just Accessibility

| Flow | Prompting call | Evidence it prompts |
|---|---|---|
| `ensureAccessibilityGranted` | `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` | Its documented purpose; shows the modal in the screenshot that started this |
| `presentTapCreationFailedAlert` | `CGRequestListenEventAccess()` | SDK header, `CGEvent.h:401`: `/* Requests event listening access if absent, potentially prompting */` |

Revision 1 scoped the problem statement to Accessibility, which made the second fix look like scope creep — one reviewer said so. It is the same bug. Both get fixed, and the header quote above is why that is a fix rather than a symmetry preference.

`CGEvent.h:399` also offers `CGPreflightListenEventAccess()`, the non-prompting check. The Accessibility flow already splits preflight (`AXIsProcessTrusted`) from prompt; the Input Monitoring flow has no preflight at all. **Adding one is out of scope** — it changes when the alert appears, not what order things happen in — but it is noted here because the asymmetry is real.

---

## UX Design

### Before (both flows)
```
     system prompt fires  ──┐
                            ├─ two modals, same instant
     Ward's NSAlert opens ──┘   the one naming the bundle is BEHIND
```

### After
```
     Ward's NSAlert         "Ward needs Accessibility access"
        alone               names /opt/homebrew/Cellar/ward/0.3.0/Ward.app
                            warns the stale entry reads as enabled
                            [Open Accessibility Settings] [Cancel]
             │
      Cancel │ Open Settings
       ──────┴──────
      nothing      system prompt (registers Ward in the pane)
      fires        then the Accessibility pane opens
```

### Interaction Changes
| Touchpoint | Before | After |
|---|---|---|
| Cancelling user | two modals, then nothing | one dialog, then nothing |
| Accepting user | two modals at once, then settings | explanation, then system modal, then settings |
| Registration | always, before any explanation | only after consent |

---

## Mandatory Reading

| Priority | File | Lines | Why |
|---|---|---|---|
| P0 | `Features/FreePort/Sources/Pure/KillEscalation.swift` | 1-12, 73-100 | **The pattern.** An alert-interleaved flow as pure data; glue holds only leaf calls |
| P0 | `Features/FreePort/Sources/FreePortController.swift` | 67-146 | How glue consumes steps: `nextStep`, `guard case`, do exactly that, feed the result back |
| P0 | `Sources/WardKit/InputPermissions.swift` | 1-71 | The file being changed |
| P0 | `Sources/WardKit/WardAlert.swift` | 1-14 | Why alert code is `@MainActor` here |
| P1 | `Sources/WardKit/ExpiryTimer.swift` | 20-23 | Why a same-target helper stays `internal`, and the honest limit of privateness |
| P1 | `scripts/coverage.sh` | 6-7 | What `Pure/` admits: no live AppKit, no IOKit, no system calls |
| P2 | `Features/FreePort/Tests/KillEscalationTests.swift` | all | How a step machine is tested here |

## External Documentation

| Topic | Source | Key Takeaway |
|---|---|---|
| `CGRequestListenEventAccess` | macOS SDK `CGEvent.h:401` | "Requests event listening access if absent, **potentially prompting**" — verified in the SDK on this machine |
| `CGPreflightListenEventAccess` | macOS SDK `CGEvent.h:399` | The non-prompting check. Exists; deliberately not adopted here |
| `AXIsProcessTrustedWithOptions` | ApplicationServices | Prompt option both shows the modal and registers the app in the pane |

GOTCHA: the registration claim is **unverifiable on this machine** — `TCC.db` is unreadable even with `sudo` (`CLAUDE.md`), and proving it would mean revoking a real grant. It is the reason the call is kept and moved rather than deleted. Never assert it as measured.

---

## Patterns to Mirror

### PURE_STEP_MACHINE
// SOURCE: Features/FreePort/Sources/Pure/KillEscalation.swift:1-12
```swift
/// SIGTERM → wait → SIGKILL → verify, as a state machine with no side effects.
///
/// Every way this feature could destroy the wrong thing is a decision made
/// here, where it can be tested, rather than in the code holding the syscall:
public enum KillEscalation {
    public enum Stage: Equatable, Sendable { case initial, afterTermination(...), afterForceKill(...) }
    public enum Step: Equatable, Sendable { case terminate([Int32]), forceKill([Int32]), report(Outcome) }
    public static func nextStep(stage: Stage, snapshot: PortSnapshot, currentUser: String) -> Step
}
```

### GLUE_EXECUTES_ONE_NAMED_STEP
// SOURCE: Features/FreePort/Sources/FreePortController.swift:78-85
```swift
let firstStep = KillEscalation.nextStep(stage: .initial, snapshot: snapshot, ...)
guard case .terminate(let targets) = firstStep else {
    report(firstStep, port: port)
    return
}
```

### ISOLATION_IS_DECLARED
// SOURCE: Sources/WardKit/WardAlert.swift:9-13
```swift
/// Isolated, because `NSAlert` is. Every caller now declares the isolation it
/// needs rather than asserting it, so the whole chain keeps full compile-time
/// checking — which an unisolated helper would have silently given up on their
/// behalf.
@MainActor
public enum WardAlert {
```

### SAME_TARGET_HELPER_STAYS_INTERNAL
// SOURCE: Sources/WardKit/ExpiryTimer.swift:20-23
```swift
/// Not `public`: `CappedSession` is the only caller. That does not by itself
/// stop a feature from disarming early — a bare `Foundation.Timer` is always
/// within reach. What keeps the bug from being re-expressible is that neither
/// controller holds a timer-shaped property at all.
```

---

## Files to Change

| File | Action | Justification |
|---|---|---|
| `Sources/WardKit/Pure/PermissionEscalation.swift` | CREATE | The sequencing decision, where it can be tested |
| `Tests/WardKitTests/PermissionEscalationTests.swift` | CREATE | Exhaustive over the stage space |
| `Sources/WardKit/InputPermissions.swift` | UPDATE | `@MainActor`; executes steps; the prompt's name is deleted |

`Pure/` is correct here and revision 1's reasoning for avoiding it was wrong: `coverage.sh:6` admits anything that is "a function of its inputs — no live AppKit object, no IOKit, no system calls". A `Stage → [Step]` function is exactly that, and lands under the ≥85% gate. (Revision 1 claimed `CappedSession` avoids `Pure/` for testing reasons. It does not — it is `@MainActor` and owns a `Timer`, so it could never qualify.)

## NOT Building
- A `CGPreflightListenEventAccess()` preflight for Input Monitoring — real asymmetry, different change
- Any edit to `InputPermissionAlertBody` — the text already names the bundle and the stale entry
- Deleting either dialog — each carries what the other cannot
- A test that drives `NSAlert` — impossible in this target. Not "unnecessary": the glue can still be edited to call the prompt inline before asking for steps, and a reviewer demonstrated exactly that with the whole suite green. What moved out of the glue is tested; what is left in it is not

---

## Step-by-Step Tasks

### Task 1: `PermissionEscalation` as a pure step machine
- **ACTION**: create `Sources/WardKit/Pure/PermissionEscalation.swift`
- **IMPLEMENT**:
```swift
enum PermissionEscalation {
    enum Stage: Equatable, Sendable {
        case notYetAsked(isAlreadyGranted: Bool)
        case explained(userChoseSettings: Bool)
    }
    enum Step: Equatable, Sendable {
        case explain
        case registerWithSystem
        case openSettingsPane
    }
    static func nextSteps(_ stage: Stage) -> [Step]
}
```
  with exactly: `.notYetAsked(true) → []`, `.notYetAsked(false) → [.explain]`, `.explained(false) → []`, `.explained(true) → [.registerWithSystem, .openSettingsPane]`
- **MIRROR**: PURE_STEP_MACHINE, SAME_TARGET_HELPER_STAYS_INTERNAL (`internal`, not `public` — one caller, same target, and `@testable` reaches it)
- **GOTCHA**: **`.registerWithSystem` must be unreachable from `.notYetAsked`.** That is the whole point — the early prompt stops being expressible, because no stage yields that step before an explanation happened. Do not add a stage that offers it.
- **IMPORTS**: none
- **VALIDATE**: `swift build`

### Task 2: Tests, exhaustive over the stage space
- **ACTION**: create `Tests/WardKitTests/PermissionEscalationTests.swift`
- **IMPLEMENT**: one case per stage asserting the **exact array**, plus:
  - registration precedes the pane (`[.registerWithSystem, .openSettingsPane]`, in that order)
  - no stage anywhere yields `.registerWithSystem` before `.explain` — assert over every `Stage` value
- **MIRROR**: `KillEscalationTests`
- **GOTCHA**: assert exact arrays, never `contains`. A membership check passes against every wrong order.
- **VALIDATE**: `swift test`, then the mutation checks below

### Task 3: `InputPermissions` executes steps and stops deciding
- **ACTION**: edit `Sources/WardKit/InputPermissions.swift`
- **IMPLEMENT**:
  - add `@MainActor` to the enum (per ISOLATION_IS_DECLARED; both call sites in `CleaningModeController` are already `@MainActor`, so this is free)
  - `presentSettingsAlert` returns `Bool` — whether the user chose settings — and stops opening anything
  - both public entry points: ask `nextSteps` for the opening stage, present the alert if told to, then ask `nextSteps(.explained(userChoseSettings:))` and execute each step in order
  - **delete `promptSystemAccessibilityDialog()` as a name**; its two lines go inline at the single `.registerWithSystem` site. Same for `CGRequestListenEventAccess()` in the other flow.
- **MIRROR**: GLUE_EXECUTES_ONE_NAMED_STEP
- **GOTCHA**: deleting the name is the only part of this change that removes a capability. Keeping it as a private func leaves the early call one line away — which is exactly what shipped.
- **VALIDATE**: `swift build && swift test`, then `bash scripts/make-app.sh`

---

## Testing Strategy

| Test | Stage | Expected | Catches a reversal? |
|---|---|---|---|
| Already granted asks for nothing | `.notYetAsked(isAlreadyGranted: true)` | `[]` | n/a |
| A missing grant is explained first | `.notYetAsked(isAlreadyGranted: false)` | `[.explain]` exactly | **yes** — a reversed machine yields `.registerWithSystem` here |
| Cancelling fires nothing | `.explained(userChoseSettings: false)` | `[]` | **yes** |
| Accepting registers, then opens | `.explained(userChoseSettings: true)` | `[.registerWithSystem, .openSettingsPane]` in order | **yes** |
| No stage registers before explaining | every `Stage` | `.registerWithSystem` never precedes an `.explain` having happened | **yes** — the invariant, over the whole space |

Revision 1 listed five cases of which two were decorative — they passed against the exact mutation the plan itself prescribed. Every case above fails against at least one mutation below.

### Required Mutation Checks
Each must turn the suite red. If one does not, the test is decorative — fix the test.

1. Swap `[.registerWithSystem, .openSettingsPane]` → `[.openSettingsPane, .registerWithSystem]`
2. `.notYetAsked(isAlreadyGranted: false)` → `[.registerWithSystem, .explain]`
3. `.explained(userChoseSettings: false)` → `[.registerWithSystem, .openSettingsPane]`
4. `.notYetAsked(isAlreadyGranted: true)` → `[.explain]`

---

## Validation Commands

```bash
swift build                    # no errors, no warnings
swift test                     # all pass; count up from 188
bash scripts/coverage.sh       # Pure/ ≥ 85% — now includes PermissionEscalation
bash scripts/shellcheck.sh     # unchanged, run for regression
bash scripts/make-app.sh       # dist/Ward.app builds and signs
```

### Manual Validation — Accessibility
- [ ] Revoke Accessibility, launch `dist/Ward.app`, click Start Cleaning Mode
- [ ] Exactly one dialog, and it is Ward's, naming the bundle path
- [ ] Cancel → no system modal appeared at all
- [ ] Reopen, choose Open Accessibility Settings → system modal appears, pane opens
- [ ] Ward is listed in the pane (registration survived the move)

### Manual Validation — Input Monitoring
The second call site changes identically, so it gets identical scrutiny rather than riding on analogy.
- [ ] With Accessibility granted and Input Monitoring revoked, trigger the failed tap
- [ ] Exactly one dialog, and it is Ward's
- [ ] Cancel → no system modal
- [ ] Choose Open Input Monitoring Settings → system prompt, then the pane
- [ ] Ward is listed in the Input Monitoring pane

---

## Acceptance Criteria
- [ ] `.registerWithSystem` is unreachable from `.notYetAsked` — by the type, not by discipline
- [ ] `promptSystemAccessibilityDialog` no longer exists as a name
- [ ] `InputPermissions` is `@MainActor`
- [ ] All four mutation checks turn the suite red
- [ ] Both manual checklists pass on the built `.app`
- [ ] `swift test`, `coverage.sh`, `make-app.sh` green

## Risks
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Glue calls the AX prompt inline before asking for steps | Low | Restores stacking | The name is gone; re-adding means retyping the `kAXTrustedCheckOptionPrompt` dance. Not prevented — stated, per `ExpiryTimer`'s honesty about privateness |
| Registration does not actually depend on the prompt | Low | The call could have been dropped | Unverifiable here; keeping it is conservative either way |
| Input Monitoring behaves unlike Accessibility | Low | Second flow regresses | Its own manual checklist, above |
| `@MainActor` breaks a caller | Very low | Build error | Both call sites already `@MainActor`; `swift build` catches it immediately |

---

## Review History

Revision 1 proposed `PermissionEscalation.escalate(byExplaining:thenIfChosen:)` — a closure combinator modelled on `CappedSession.end(by:)`. Four reviewers found, independently:

1. **The combinator was ceremony.** `presentSettingsAlert` *already* had the correct ordering; the bug was the free-standing call above it. The new type would have wrapped the code that was never broken and left the broken line as reachable as ever.
2. **The `CappedSession` analogy failed.** `ExpiryTimer.swift:20-23` states the actual mechanism: the bug became unexpressible because the controllers hold no timer-shaped property. That removed a **resource**. A statement cannot be removed that way — but a `Stage` type *can* remove the decision, which is what revision 2 does.
3. **The tests caught nothing real.** All five exercised the combinator with synthetic closures; none executed a line of `InputPermissions`. Two of the five passed against the plan's own prescribed mutation.
4. **`KillEscalation` already solved this**, in this repo, for a harder case — an alert-interleaved destructive flow, 24 tests, zero AppKit in the test target.
5. **The `Pure/` rationale was factually wrong** (`coverage.sh:6`).
6. **The helper would have been unisolated**, contradicting `WardAlert`'s documented decision.
7. **The Summary over-claimed** "one alert" — true only for the cancelling user.
8. One reviewer called the Input Monitoring fix scope creep. **Rejected on evidence**: `CGEvent.h:401` says that call prompts too. The plan's framing was too narrow, not its scope.
