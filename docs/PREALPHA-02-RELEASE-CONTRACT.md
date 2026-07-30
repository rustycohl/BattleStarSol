# Battle/Star.SOL pre-alpha `.02` release contract

**Work line:** `C:\SOL\BattleStarSol-prealpha-02`

**Branch:** `prealpha-02`

**Known-good base:** `55ecad27bf83c56225a33dc20a62a4d305f6bc89`

**Baseline release:** `0.1.1-prealpha.1`

**Candidate version:** `0.1.2-prealpha.2`

**Current state:** private development checkpoint; not released

## Purpose

Pre-alpha `.02` makes the already-proven strategic-to-tactical-to-extraction
loop understandable, reproducible, and ready for a principal playtest. It does
not replace the public known-good repository while incomplete.

This contract is the bounded meaning of “feature complete” and “no known
release bug” for `.02`. Future-roadmap mechanics are not missing `.02`
features unless this document names them as required.

## Required release scope

### M00 — Isolated work line and inherited baseline

- Keep `.02` in a separate Git repository and branch.
- Pin the exact source commit and baseline version.
- Disable pushing from this work line to the known-good source remote.
- Preserve each accepted module as a reviewable commit.
- Provide a machine-checkable injection manifest and dry-run-first promotion
  guard.
- Reproduce all inherited tests before feature work.

### M01 — Guided Proving Ground

A fresh profile must receive deterministic guidance through:

1. orienting to and selecting the Commander;
2. previewing and completing a move;
3. taking cover or receiving an explicit cover explanation;
4. obtaining/using a weapon or completing a basic attack;
5. ending a turn and observing Agent and hostile phases; and
6. extracting and seeing the strategic result.

The guide must follow the current Base-10 economy, action router, message
contracts, and same-tab flow. Every state transition needs deterministic
automated coverage.

### M02 — First-turn clarity and status truth

- Make the active pilot, AP, legal core actions, visible costs, end-turn
  consequence, and F8/HUD extraction escape hatch obvious.
- Reconcile player-facing faction names without changing existing serialized
  identifiers.
- Separate advanced/developer mobility from core controls.
- Remove duplicate or stale “next” claims.
- Update in-game help, controls, status, version labels, and known limits as
  one change.

### M03 — Cover-seeking and simple-flanking Agents

- Use the existing legality and utility boundaries to score bounded cover and
  simple-flank candidates.
- Make tie-breaking deterministic.
- Give allied and hostile Agents no movement, visibility, AP, or action
  authority unavailable to the player rules.
- Keep advanced-mobility and wall-run AI out of scope.
- Record concise decision rationale in the tactical feed/replay record.
- Add golden coverage for cover selection, unsafe exposure, a simple flank,
  AP conservation, and the no-candidate fallback.

### M04 — Bounded deterministic repro artifact

Export and re-import one privacy-safe playtest artifact containing:

- normalized deployment and seed;
- generator, rules, contract, and product versions;
- bounded action and event records;
- current/final mechanical hash when available;
- platform/build metadata;
- a concise optional user note;
- extraction result when available; and
- an integrity digest.

The artifact must exclude credentials, keys, full browser storage, and direct
personal identifiers. A clean checkout must reproduce the supported portion
and explain any declared non-equivalence.

### M05 — Narrow-viewport and interaction pass

- Declare and verify the supported desktop and narrow viewport matrix.
- Repair clipping, hidden/unreachable required actions, focus traps, and
  undersized required targets.
- Establish keyboard focus order and visible focus.
- Check contrast, text scaling, reduced motion, and actionable error messages.
- Keep the dense embedded A.T.L.A.S. surface explicitly desktop-first where it
  cannot truthfully meet the tactical narrow-screen contract.
- Capture evidence for each supported viewport.

### M06 — Release decision and acceptance evidence

`.02` may be promoted and launched only when:

- M00 through M05 are complete;
- no known P0, P1, or release-blocking defect remains;
- inherited and new automated tests pass;
- a clean clone imports in Godot;
- the static verifier, both Godot suites, Node tests, and syntax checks pass;
- a matching release Web export is committed and hash-verified;
- local strategic-to-tactical-to-extraction and replay-idempotence smokes pass;
- documentation, manifests, UI, and version labels agree;
- the public workflow succeeds; and
- the public full-loop smoke is clean.

The manifest’s `release.allow_apply` remains `false` until the pre-promotion
gates pass. Public workflow and public full-loop evidence are post-promotion
release gates; a failed public gate requires correction or rollback and `.02`
must not be called launched.

## Explicit non-goals

The following are preserved roadmap work, not `.02` release requirements:

- authenticated accounts or remote campaign authority;
- multiplayer, peer authority, hotseats, ranks, or Discord integration;
- named persistent soldiers, campaign permadeath, wounds, or a full armory;
- overwatch, suppression, structural destruction, dynamic hazards, or Void
  actors;
- the full 13-node campaign loop;
- advanced-mobility AI or complete wall-run grammar;
- production audio, character models, animation, telemetry, or Steam
  packaging;
- wallet, chain, token, P2P transport, or storage-yield systems; and
- cross-platform replay-hash equivalence beyond the declared `.02` matrix.

## Defect policy

- **P0:** data loss, security/credential exposure, destructive promotion, or no
  playable path. Blocks all release work.
- **P1:** required scope cannot be completed, required action is unreachable,
  deterministic replay is broken, or the public full loop fails. Blocks
  release.
- **P2:** meaningful but bounded defect with a documented workaround. Must be
  fixed when inside `.02` scope; otherwise recorded before release.
- **P3:** cosmetic or later-roadmap issue that does not falsify the release
  claim. Record and defer deliberately.

Unknown severity is release-blocking until triaged.

## Module loop

Every module follows:

1. back up the known-good state;
2. record intent, inputs, outputs, invariants, fallback, and non-goals;
3. implement the smallest independently testable boundary;
4. review code, failure paths, security, provenance, accessibility, and
   documentation;
5. fix in-scope defects;
6. run module and regression gates;
7. record evidence and remaining limits;
8. commit the accepted module; and
9. leave main untouched until guarded promotion.

## Controlling files

- Machine state: [`../prealpha-02-manifest.json`](../prealpha-02-manifest.json)
- Injection record: [`PREALPHA-02-INJECTION-LEDGER.md`](PREALPHA-02-INJECTION-LEDGER.md)
- Release evidence: [`PREALPHA-02-ANALYSIS-LOG.md`](PREALPHA-02-ANALYSIS-LOG.md)
- Promotion guard: [`../tools/promote-prealpha-02.ps1`](../tools/promote-prealpha-02.ps1)
