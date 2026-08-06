# Homebrew Tap + `ward` CLI

## Problem Statement

Ward cannot be shared without friction. It has no Apple Developer ID, so every distribution channel tried so far ends at the same Gatekeeper wall, and the workaround — teaching people to strip quarantine — contradicts Ward's own security posture. Meanwhile several Ward features are needed *while the user is already in a terminal*, where a menu-bar-only interface is the wrong shape.

## Evidence

All observed directly on 2026-08-05, not assumed:

- A teammate sent the v0.1.0 DMG received **"Apple could not verify Ward-0.1.0.dmg is free of malware"**, a dialog offering only *Move to Trash* and *Done* — no Open button.
- `spctl -a -vv dist/Ward.app` → **`rejected`**. `Signature=adhoc`, `TeamIdentifier=not set`.
- The install instructions shipped *inside* the DMG, which macOS blocks — so they were unreachable exactly when needed. Packaging bug, since fixed.
- **`Rectangle.app`, installed via Homebrew Cask, carries the quarantine attribute** — observed. It opens anyway because it is notarized. *Inference, not observation:* a Ward cask would carry the same attribute and, being unnotarized, fail assessment.
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
- [ ] **How bad is the Accessibility re-grant after `brew upgrade`?** Not *whether* — `CLAUDE.md` already records ad-hoc rebuilds invalidating TCC as verified, and there is no mechanism by which `brew` would differ. The open question is whether it is painful enough to sink the approach.
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

`brew install shelupets89/ward/ward` producing a running menu-bar app with zero security dialogs. **No CLI needed to test the hypothesis** — the install path is the whole point; every CLI command is additive.

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
- Feature code already lives in per-feature library targets (`CleaningMode`, `KeepAwakeLidClosed`, `KeepScreenAwake`), each depending on `WardKit`. The CLI is one more `.executableTarget` on those same libraries. **One restructuring is unavoidable**: a `ward` product collides with the existing `Ward` app target on case-insensitive APFS, so the app target is renamed to `WardApp` (bundle executable stays `Ward`). Verified by reproduction, not assumed.
- The recently shipped `KeepScreenAwake` confirmed the "two targets and one line" claim, so the pattern is proven rather than theoretical.
- The CLI is standalone: it holds its own assertions and runs its own subprocesses. No shared state with the app, no IPC.
- `ward until <cmd>` should be **built CLI-first**, because wrapping a command is strictly simpler than the polling/PID-matching design specced for the menu-bar version.

**Technical Risks**

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| `brew audit` rejects a formula shipping a `.app` | **M** | Spike first (open question 1). Fallback: formula installs only the `ward` CLI; app stays a manual/DMG install |
| Accessibility re-grant required after every `brew upgrade` | **H — near-certain** | `CLAUDE.md` already records ad-hoc rebuilds invalidating TCC as verified, and `brew upgrade` recompiles and re-signs the same way. Phase 0 confirms the magnitude, not the existence. If upgrades are this painful, reconsider the whole formula approach |
| Xcode CLT missing on target machine | **H** | Formula declares the dependency; `brew` surfaces it before building |
| Formula drifts behind releases | **M** | Automate the version bump from the release workflow |
| Users read "installs from source" as slower/riskier | **L** | README explains it is *safer* here, with the quarantine evidence |

---

## Implementation Phases

| # | Phase | Description | Status | Parallel | Depends | PRP Plan |
|---|-------|-------------|--------|----------|---------|----------|
| 0 | Formula spike | Prove `brew audit` accepts a source formula installing a `.app`; measure the TCC re-grant cost; settle where the app lands | pending | - | - | - |
| 1 | **Tap + formula** | `homebrew-ward` repo, source-building formula, README install section. **`brew install` gives you the app** | pending | - | 0 | - |
| 2 | Release automation | Formula version bump on release tag, so the install path doesn't rot | pending | - | 1 | - |
| 3 | CLI skeleton | `ward` executable target, arg parsing, `--version`, `--help` | pending | with 1, 2 | - | [ward-cli-skeleton](../plans/ward-cli-skeleton.plan.md) |
| 4 | `ward until <cmd>` | Wrap a command, hold an assertion for its lifetime | pending | - | 3 | - |
| 5 | `free-port`, `sleep-why` | Remaining terminal-shaped commands | pending | - | 3 | - |

### Phase Details

**Phase 0: Formula spike**
- **Goal**: Kill the approach early if Homebrew won't accept it.
- **Scope**: A throwaway local formula; run `brew audit`; install, upgrade, measure the Accessibility re-grant cost, and settle where the `.app` should land (Cellar vs `/Applications` symlink).
- **Success signal**: A clear yes/no on whether a formula may install an app-only payload. **A "no" makes Phase 3 a prerequisite for Phase 1** — a formula shipping a `ward` binary is conventional, one shipping only a `.app` is not.

**Phase 1: Tap + formula — the actual goal**
- **Goal**: Replace `git clone … && cd ward && bash scripts/make-app.sh && open dist/Ward.app` with one command.
- **Scope**: `homebrew-ward` repo, source-building formula, install tested on a clean user account, README install section rewritten to lead with `brew`.
- **Success signal**: `brew install shelupets89/ward/ward` on a machine that has never seen Ward produces a running menu-bar app with **zero security dialogs**.

**Phase 2: Release automation**
- **Goal**: Stop the formula silently drifting behind releases.
- **Scope**: Version bump driven from the existing release workflow.
- **Success signal**: Tagging a release updates the formula with no manual step.

**Phase 3: CLI skeleton**
- **Goal**: Prove an executable target composes with the feature libraries.
- **Scope**: Target, argument parsing, `--help`, and `--version` from a shared `WardVersion` constant — a CLI binary has no `Bundle.main` plist to read, so a test keeps the constant honest against `Info.plist`. **Starts by renaming the app target to `WardApp`** — a `ward` product collides with `Ward` on case-insensitive APFS.
- **Success signal**: `swift run ward --version` prints the version; the app bundle still builds and launches.

**Phase 4: `ward until <cmd>`**
- **Goal**: Deliver the command that justifies the CLI existing.
- **Scope**: Spawn the wrapped command, hold `PreventUserIdleSystemSleep`, release on exit, propagate the exit code.
- **Success signal**: `ward until sleep 30` keeps the Mac awake for exactly that long and exits 0.

**Phase 5: `free-port`, `sleep-why`**
- **Goal**: Cover the other terminal-shaped problems.
- **Scope**: Reuse the shipped Free a Port logic; add sleep-assertion reporting.
- **Success signal**: Each command works standalone with the app not running.

### Parallelism Notes

Phase 3 (CLI) is independent of Phases 0–2 and can run alongside them — it's Swift-side, they're Homebrew-side. **The one coupling runs the other way**: if Phase 0 finds that Homebrew won't accept a formula installing only a `.app`, then Phase 3 must land *before* Phase 1, because a formula that ships a `ward` binary is conventional and one that ships only an app is not.

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
