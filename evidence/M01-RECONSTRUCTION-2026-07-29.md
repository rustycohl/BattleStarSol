# M01 Reconstruction Evidence

## Scope

- Module: M01-001 and M01-003 source reconstruction
- Date: 2026-07-29
- Writable boundary: `C:\SOL\BattleStarSol-prealpha-02`
- Starting point: M00's clean 225-check source baseline
- Reference material: read-only historical design log, compiled 239-check
  report schema, and archived playtest observations

No reference repository or historical file was modified.

## Reconstructed behavior

### M01-001: one action boundary

The Commander roster button and friendly-unit world click now request
`select` through `ActionRouter`. The existing router remains responsible for
the accepted-action ledger and tutorial notification.

### M01-003: bounded Web observation

The guided-mode observation:

- is emitted only on Web builds;
- exposes no input method and reads no state from JavaScript;
- derives actor, movement, cover, attack, tutorial, round, team, and viewport
  fields from the live simulation;
- scans a square/Chebyshev radius of two in row-major order;
- keeps at most 12 legal and affordable moves, eight authoritative cover
  faces, and eight visible living hostiles;
- uses `Pathfinder.is_adjacent()` independently of Chebyshev range;
- is capped at 16 KiB by regression test;
- publishes only changed serialized snapshots;
- returns an empty observation when the actor or camera projection is invalid.

The final top-level schema is:

`active_team`, `actor`, `attack_targets`, `cover_faces`, `kind`,
`move_targets`, `round`, `tutorial`, `viewport`.

## Verification

| Gate | Result |
|---|---|
| Static Godot verification | PASS |
| Godot headless TestRunner | PASS |
| Godot PlaytestRunner | PASS, 239 checks |
| M01-001 routed-selection checks | PASS |
| M01-003 observation checks | PASS |
| Guided movement through `ActionRouter` | PASS |

Godot version:

`4.7.1.stable.official.a13da4feb`

The isolated headless runs continue to emit editor-scan/ObjectDB/resource
cleanup warnings after successful test completion. Those warnings remain a
harness-cleanliness observation.

## Source identities

| File | SHA-256 |
|---|---|
| `game/scripts/Main.gd` | `8e8d373ac34dd14c44039a395ab87f7e9360cc0346bb318ee5933e8bf6084e26` |
| `game/scripts/TacticalUI.gd` | `8d7bf5e71e59a74c74cb29acac30541cd42fbdde9bfba74d95b491822e8f1913` |
| `game/tests/PlaytestRunner.gd` | `e08b5f1d5bef90c6ee9da7c067492d7705c3629d3bd25f37a2af8d3389e2b673` |

## Honest boundary

This evidence closes source reconstruction and headless parity. It does not
claim a new Web export, an atomic browser run, or public deployment. The
committed Web runtime and `game/MANIFEST.sha256` still describe the older
225-check package; their mismatch is the explicit re-export gate, not a reason
to rewrite the manifest.
