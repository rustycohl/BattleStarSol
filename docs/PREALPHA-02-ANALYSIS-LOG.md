# Pre-alpha `.02` analysis and correction log

This is the concise, current record of documentation-guided analysis,
implementation, review, bug correction, and validation. It complements the
commit history; it does not replace tests or the release contract.

## Current-state pointer — 2026-07-29

The post-recovery source of truth is `../MODULE-LEDGER.md` plus the dated files
under `../evidence/`. The entries below remain chronological evidence from the
original `.02` line; their older check counts and pending states are not the
current SOL claim.

The 2026-07-29 recovery loop:

- archived clean commit `ce5038d` and recorded archive identity;
- reconstructed M01 action routing and bounded Web observation;
- added AP-zero recovery and camera-synchronized observation coordinates;
- closed the combined Godot gate at 261/261;
- added twelve M03 deterministic cover/flank golden checks;
- created and tested the atomic evidence foundation;
- finalized the authoritative browser pack
  `20260729T104417824Z-b0e26ed0`;
- preserved M03 live rationale, M04 clean re-import,
  M05 viewport/accessibility, M06 promotion, and public release as open gates.

## 2026-07-28 — M00 baseline

### Inputs reviewed

- V3 State of Play
- V3 Roadmap V2 Post-Launch Edition, phase 2
- V3 Doc’s Orphanage
- current root status and validation records
- live Godot implementation status and testing guide
- current Node release tests and Godot verification scripts

### Findings

- The separate `.02` work line is correctly pinned to the current known-good
  BattleStarSol head.
- The source remote can fetch but cannot push, preventing accidental mutation
  of the known-good product repository.
- The inherited codebase already contains the real composed game loop; `.02`
  is playtest preparation, not a replacement website.
- The required `.02` delta is bounded to onboarding, first-turn truth, current
  cover/flank AI, repro artifacts, interaction/accessibility coverage, and
  release proof.
- Large campaign, multiplayer, chain, production-asset, and signature-system
  expansions remain explicitly outside `.02`.

### Verification

- `npm.cmd test`: 15/15 pass.
- `npm.cmd run check`: pass.
- static Godot verification: pass.
- Godot `TestRunner`: pass.
- Godot `PlaytestRunner`: 147 checks pass in 1,686 ms.

### Corrections

- Added a bounded release contract so “feature complete” has a testable
  meaning.
- Added a machine-readable module/release manifest.
- Added a dry-run-first promotion guard with exact-head, clean-tree,
  allowlist, linear-history, module-readiness, and test gates.
- Added a deterministic game-manifest refresh tool for future source/export
  changes.

### Remaining before M01

- M00 commits: `5428793` and corrective guard commit `6b5dd0a`.
- The dry-run guard reran all inherited gates and stopped on incomplete
  modules without modifying the target.

## 2026-07-28 — M01 guided Proving Ground

### Analysis

- The prior Proving Ground was only a one-unit sandbox with a single transient
  hint.
- Its two dummies were always assigned to the Syndicate team, making them
  friendly when the player selected that faction.
- Dummies spawned across the 20×20 board, so the documented move/attack lesson
  was not guaranteed inside one Base-10 turn.
- The action and event records already provided the correct deterministic
  tutorial observation boundary.

### Implementation and correction loop

- Added a pure advisory `TutorialDirector` with six user-facing steps.
- Advanced selection/defense/attack/end-turn from accepted actions and
  movement/phase/extraction from resolved events.
- Added a persistent top-center objective panel.
- Placed two zero-AP hostile dummies in each faction’s level insertion lane.
- Added explicit Brace fallback when the lane has no adjacent cover.
- Added the same objective list to native and browser deployment payloads.
- Fixed the full-flow test’s deferred End Turn race.
- Preserved the isolated-profile Godot wrapper after a direct invocation
  reproduced the documented engine-level signal-11 startup crash.

### Evidence

- Node release gate: 17/17 pass;
- Node syntax checks: pass;
- static verifier: pass;
- `TestRunner`: pass;
- `PlaytestRunner`: 192 checks pass in 2,493 ms;
- all three faction variants: pass;
- matching Godot 4.7.1 release Web export: pass;
- in-app localhost browser smoke: blocked by browser security policy.

### State

M01 is implemented and exported, but remains `validation_pending` until the
required live-browser interaction/full-loop evidence can be collected. It is
not promotable and does not change the known-good public build.

## 2026-07-28 — M02 first-turn clarity and status truth

### Analysis

- The tactical HUD exposed a generic player/enemy turn label but not the
  active faction, active pilot, AP, or the consequence of ending a turn.
- Core action costs existed in authoritative logic and tooltips, but no
  compact persistent reference made the Base-10 opening turn legible.
- Controls documentation promised F1/Tab help, while no in-game help surface
  existed.
- `enemy_label` was updated on every UI refresh but had never been mounted in
  the roster before the roster rebuild path.
- Faction presentation used EFD/Metropoli/Kaiju-Aliens while deployment and
  design documents also used HAD/Syndicate/Timecorps.
- Advanced mobility remained mixed under a generic SPECIAL heading.

### Implementation and correction loop

- Preserved faction IDs `0/1/2` and all existing payload aliases while using
  combined visible labels for both vocabularies.
- Added persistent faction/turn, active-pilot/AP, legal-action, phase-order,
  extraction, hostile-count, and core-cost readouts.
- Implemented the documented F1/Tab help overlay with Escape priority.
- Renamed and documented the developer boundary, keeping Remotes and advanced
  mobility out of the default core dock.
- Updated controls, tactical architecture, source status, and README claims in
  the same module.

### Evidence

- static verifier: pass;
- `TestRunner`: pass;
- `PlaytestRunner`: 204 checks pass in 2,129 ms;
- serialized IDs and seven canonical/legacy alias inputs: pass;
- all six faction-deployment labels: pass;
- help open/close, core-cost line, active pilot/AP, End Turn consequence,
  F8 extraction, hostile count, and default advanced-control hiding: pass;
- matching Godot 4.7.1 release Web export: pass.

### State

M02 is implemented and exported, and remains `validation_pending` until
live-browser interaction evidence is complete. The public/target codebase is
unchanged.
