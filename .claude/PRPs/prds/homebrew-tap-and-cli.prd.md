# Homebrew Tap + `ward` CLI

## Problem Statement

Ward cannot be shared without friction. It has no Apple Developer ID, so every distribution channel tried so far ends at the same Gatekeeper wall, and the workaround — teaching people to strip quarantine — contradicts Ward's own security posture. Meanwhile several Ward features are needed *while the user is already in a terminal*, where a menu-bar-only interface is the wrong shape.

## Evidence

All observed directly on 2026-08-05, not assumed:

- A teammate sent the v0.1.0 DMG received **"Apple could not verify Ward-0.1.0.dmg is free of malware"**, a dialog offering only *Move to Trash* and *Done* — no Open button.
- `spctl -a -vv dist/Ward.app` → **`rejected`**. `Signature=adhoc`, `TeamIdentifier=not set`.
- The install instructions shipped *inside* the DMG, which macOS blocks — so they were unreachable exactly when needed. Packaging bug, since fixed.
- **`Rectangle.app`, installed via Homebrew Cask, carries the quarantine attribute.** It opens anyway because it is notarized. A cask of Ward would carry the same attribute and fail assessment.
- **A locally built `Ward.app` has no quarantine attribute at all** — verified with `xattr`. Compiling on the target machine sidesteps Gatekeeper rather than colliding with it.
- Ports are the terminal case: `lsof` showed `ControlCenter` holding 5000/7000, and the "port already in use" problem is encountered *from* a shell.

## Proposed Solution

A Homebrew tap whose formula **builds Ward from source** on the installing machine, plus a `ward` CLI binary built from the same feature libraries.

Building from source is the only Homebrew path that avoids Gatekeeper entirely — nothing is downloaded, so nothing is quarantined. `brew upgrade ward` then provides self-update with no Sparkle, no EdDSA keys, no appcast, and no hand-rolled version comparison.

The CLI is not merely packaging. For `free-port`, `sleep-why` and `until`, a terminal is the correct interface, and `ward until <command>` is a *better* design than the menu-driven equivalent: wrapping a command gives exact lifetime with no polling and no process-name matching.

## Key Hypothesis

We believe a source-building Homebrew formula will let a developer install and update Ward without ever seeing a security dialog, because nothing is downloaded and therefore nothing is quarantined.

We'll know we're right when a colleague runs `brew install shelupets89/ward/ward`, reaches a working menu-bar app, and reports no Gatekeeper prompt at any point.

## What We're NOT Building

- **Notarization** — needs a $99/yr Developer ID. It remains the real fix; this is explicitly a workaround, and the PRD should not pretend otherwise.
- **A Homebrew Cask** — would download a binary and be quarantined. Evidenced above.
- **Sparkle or a custom updater** — `brew upgrade` already does this.
- **IPC between CLI and app** — the CLI is standalone, sharing libraries not state. Remote-controlling the running app is a much larger project for little gain.
- **Cleaning Mode in the CLI** — needs a running app, Accessibility, and a shield window. Nonsensical as a command.
- **Submission to homebrew-cask upstream** — rejected on notability (~75 stars needed).

## Success Metrics

| Metric | Target | How Measured |
|--------|--------|--------------|
| Gatekeeper dialogs during install | **0** | Fresh machine or fresh user account: install and launch, count prompts |
| Steps from zero to running app | 1 command | `brew install shelupets89/ward/ward` |
| Update path | `brew upgrade ward` works with no manual step | Tag a release, bump formula, upgrade |
| CLI feature coverage | ≥3 commands | `keep-awake`, `until`, `free-port` / `sleep-why` |
| `Pure/` coverage after CLI lands | ≥85% (unchanged gate) | `scripts/coverage.sh` |

## Open Questions

- [ ] Does `brew audit` accept a formula that installs a GUI `.app`? Formulae are conventionally CLI-only; casks own apps. **Needs a spike before committing to the approach.**
- [ ] Where should the `.app` land — symlink into `/Applications`, or leave it in the Cellar and let the user link it? Affects whether TCC grants survive `brew upgrade`.
- [ ] **Does the Accessibility grant survive a `brew upgrade` rebuild?** Ad-hoc signing already invalidates TCC on rebuild. If every upgrade forces re-granting Accessibility, that materially weakens the value.
- [ ] Should the tap live in a second repo (`homebrew-ward`) or can it be a directory in this one? Homebrew expects `homebrew-<name>` as a repo name.
- [ ] Is `ward` a safe binary name, or does it collide with something in common `PATH`s?

---

## Users & Context

**Primary User**
- **Who**: A macOS developer colleague with Homebrew and Xcode Command Line Tools already installed.
- **Current behavior**: Receives a DMG over Slack, hits the Gatekeeper wall, either asks for help or gives up.
- **Trigger**: Being told "try this tool" — or, for the CLI, hitting `EADDRINUSE` on port 3001.
- **Success state**: Ward running in the menu bar, and `ward free-port 3001` available in the shell, without having thought about code signing once.

**Job to Be Done**
When a colleague tells me about a tool they built, I want to install it with one command I already trust, so I can try it without deciding whether to override macOS security.

**Non-Users**
- **Non-developers.** The formula requires Xcode CLT (~1–2 GB) and ~30s of compilation. For them, notarization is the only honest answer.
- **Anyone who needs a signed, auditable binary.** Source-building means each user's build is their own; there is no signed artifact to verify.

---

## Solution Detail

### Core Capabilities (MoSCoW)

| Priority | Capability | Rationale |
|----------|------------|-----------|
| Must | `ward` executable target on existing feature libraries | Everything else depends on it; validates the modular refactor a second time |
| Must | Formula building from source + tap repo | The entire point — the only Gatekeeper-free path |
| Must | `ward until <command>` | Better than the menu version: exact lifetime, no polling, no name matching |
| Should | `ward free-port <port>`, `ward sleep-why` | Terminal is where these problems are encountered |
| Should | Formula version auto-bump on release tag | Otherwise the formula silently rots behind releases |
| Could | `ward keep-awake <duration>` | Foreground assertion, `caffeinate`-like |
| Won't | Cask, Sparkle, notarization, CLI↔app IPC | See "What We're NOT Building" |

### MVP Scope

`ward --version` + one real command, installable via `brew install` from the tap with zero security dialogs. That alone tests the hypothesis; the remaining commands are additive.

### User Flow

```
brew tap shelupets89/ward
brew install ward
# → compiles locally, no download, no Gatekeeper
ward until npm run build      # terminal path
open -a Ward                  # menu-bar path
brew upgrade ward             # self-update
```

---

## Technical Approach

**Feasibility**: **HIGH** for the CLI, **MEDIUM** for the formula.

**Architecture Notes**
- Feature code already lives in per-feature library targets (`CleaningMode`, `KeepAwakeLidClosed`, `KeepScreenAwake`), each depending on `WardKit`. The CLI is one more `.executableTarget` on those same libraries — no restructuring.
- The recently shipped `KeepScreenAwake` confirmed the "two targets and one line" claim, so the pattern is proven rather than theoretical.
- The CLI is standalone: it holds its own assertions and runs its own subprocesses. No shared state with the app, no IPC.
- `ward until <cmd>` should be **built CLI-first**, because wrapping a command is strictly simpler than the polling/PID-matching design specced for the menu-bar version.

**Technical Risks**

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| `brew audit` rejects a formula shipping a `.app` | **M** | Spike first (open question 1). Fallback: formula installs only the `ward` CLI; app stays a manual/DMG install |
| Accessibility re-grant required after every `brew upgrade` | **M** | Test explicitly. If confirmed, document it loudly — it may make upgrades painful enough to reconsider |
| Xcode CLT missing on target machine | **H** | Formula declares the dependency; `brew` surfaces it before building |
| Formula drifts behind releases | **M** | Automate the version bump from the release workflow |
| Users read "installs from source" as slower/riskier | **L** | README explains it is *safer* here, with the quarantine evidence |

---

## Implementation Phases

| # | Phase | Description | Status | Parallel | Depends | PRP Plan |
|---|-------|-------------|--------|----------|---------|----------|
| 0 | Formula spike | Prove `brew audit` accepts a source formula shipping a `.app`; test TCC survival across upgrade | pending | - | - | - |
| 1 | CLI skeleton | `ward` executable target, arg parsing, `--version`, `--help` | in-progress | with 0 | - | [ward-cli-skeleton](../plans/ward-cli-skeleton.plan.md) |
| 2 | `ward until <cmd>` | Wrap a command, hold an assertion for its lifetime | pending | - | 1 | - |
| 3 | Further commands | `free-port`, `sleep-why` | pending | with 4 | 2 | - |
| 4 | Tap + formula | `homebrew-ward` repo, source-building formula | pending | with 3 | 0, 1 | - |
| 5 | Release automation + docs | Formula bump on tag; README install section | pending | - | 3, 4 | - |

### Phase Details

**Phase 0: Formula spike**
- **Goal**: Kill the approach early if Homebrew won't accept it.
- **Scope**: A throwaway local formula; run `brew audit`; install, upgrade, check whether Accessibility survives.
- **Success signal**: A clear yes/no on both open questions. A "no" redirects Phase 4 to CLI-only.

**Phase 1: CLI skeleton**
- **Goal**: Prove an executable target composes with the feature libraries.
- **Scope**: Target, argument parsing, `--version` reading `CFBundleShortVersionString`, `--help`.
- **Success signal**: `swift run ward --version` prints the version; `Pure/` coverage gate still passes.

**Phase 2: `ward until <cmd>`**
- **Goal**: Deliver the command that justifies the CLI existing.
- **Scope**: Spawn the wrapped command, hold `PreventUserIdleSystemSleep`, release on exit, propagate exit code.
- **Success signal**: `ward until sleep 30` keeps the Mac awake for exactly that long and exits 0.

**Phase 3: Further commands**
- **Goal**: Cover the other terminal-shaped problems.
- **Scope**: `free-port` (depends on the FreePort feature landing), `sleep-why`.
- **Success signal**: Each command works standalone with the app not running.

**Phase 4: Tap + formula**
- **Goal**: One-command install with no Gatekeeper dialog.
- **Scope**: `homebrew-ward` repo, formula, install/upgrade tested on a clean user account.
- **Success signal**: Zero security prompts, measured on a fresh account.

**Phase 5: Release automation + docs**
- **Goal**: Stop the formula rotting; make the path discoverable.
- **Scope**: Version bump from the release workflow; README install section leads with `brew`.
- **Success signal**: Tagging a release updates the formula with no manual step.

### Parallelism Notes

Phase 0 and 1 are independent — the spike is Homebrew-side, the skeleton is Swift-side. Run both first; the spike can invalidate Phase 4 before any effort is spent there. Phases 3 and 4 are independent once 1 and 2 exist.

---

## Decisions Log

| Decision | Choice | Alternatives | Rationale |
|----------|--------|--------------|-----------|
| Distribution channel | Homebrew tap, source-building formula | Cask; `curl \| bash`; DMG only | Only path with no download, therefore no quarantine. Verified: cask-installed Rectangle carries quarantine |
| Self-update | `brew upgrade` | Sparkle; custom `ward update` | Reuses machinery that exists; no keys, appcast, or version logic to own |
| CLI ↔ app relationship | Standalone, shares libraries | IPC; CLI as thin client | IPC is a large project; standalone covers every terminal-shaped feature |
| First CLI command | `until <cmd>` | `free-port` | Wrapping beats polling, and it doesn't depend on the in-flight FreePort work |
| `curl \| bash` installer | Rejected | — | Contradicts Ward's own stated posture on trusting unverifiable code |

---

## Research Summary

**Market Context**
Homebrew is the default install path for macOS developer tools. Upstream `homebrew-cask` enforces notability (~75 stars), so a personal tap is the only viable route. Casks apply quarantine by default; `--no-quarantine` exists but routinely instructing users to pass it teaches them to disable a protection.

**Technical Context**
Ward is already one library target per feature (`Features/<Name>/Sources`), all depending on `WardKit`, with a thin `Sources/Ward` shell. `KeepScreenAwake` shipped through this structure and confirmed a new feature is two targets plus one line. An `.executableTarget` for the CLI is the same shape. `Pure/` directories carry an automatic ≥85% coverage gate that the CLI must not dilute.

---

*Generated: 2026-08-05*
*Status: DRAFT — Phase 0 must resolve the two Homebrew open questions before Phase 4 is committed to*
