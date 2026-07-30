# M03-003 Haili, the guided instructor

## Authority

Principal decision, 2026-07-29: the guided Proving Ground gets an armed
instructor agent, and her name is Haili.

M03-002 established that the tutorial could not express positional play because
its only hostiles were two `Target Dummy` units with `ap = 0`. This module fixes
the scenario rather than the AI.

## Naming

"Haili" is a casual personal name. It is **distinct in fact** from the franchise
property "H.A.I.L.I.", though lineage exists between them. The two registry
entries must not be merged, and this character's name must not be expanded into
the acronym. Recorded at the principal's clarification of 2026-07-29.

## What changed

Three production changes, all confined to the guided scenario. Every other sector
keeps its previous behavior exactly.

1. **Haili spawns in the Proving Ground.** One agent of the opposing faction at a
   deterministic instruction post — five cells along the training lane, beyond the
   one-turn melee lane but inside the observation radius — with the faction's
   standard skills and a full Base-10 action pool. The two target dummies remain
   at `ap = 0`; they still teach the action surface.
2. **The training lane now has cover.** The insertion pads are forced flat so
   units never spawn on a column, which also meant the tutorial had no cover to
   take: `Take Cover` was permanently greyed out and the observation surface
   published zero cover faces. Two deterministic cover cells are now added for the
   Proving Ground only — one orthogonally adjacent to the Commander's start,
   because `MovementContext.cover_options` reads the faces adjacent to the actor's
   own cell, and one out in the lane for the move-then-take-cover lesson.
3. **Cover is injected before the tiles are built**, so the meshes and the
   simulation agree on the same terrain.

No AI, action economy, or rules change. No change to `AITactics`, `AIBehavior`, or
the observation surface's bounds.

## Result

The guided scenario now teaches and demonstrates what it describes.

| Measure | Before | After |
|---|---|---|
| Tutorial hostiles | 2 dummies, both `ap = 0` | 2 dummies plus Haili at 10 AP |
| `Take Cover` control | permanently disabled | enabled, visible in the round-1 capture |
| Cover faces published live | 0 of 9 samples | 9 of 9 samples |
| Canonical rationale in the guided ledger | none possible | all five signatures |
| Guided tutorial completion | 6/6 | 6/6, unchanged |
| Mission outcome | SUCCESS, 3 survivors, seed `1167583760` | identical |

Signatures observed in the guided ledger: `protective cover now`,
`lean from committed cover`, `cover has no legal attack lane`, `cover route`, and
`simple flank`. Haili takes cover, leans from it, abandons it when it offers no
firing lane, and flanks — the four behaviors M03-001's golden tests describe, now
demonstrable in front of a new player.

## M03-001 acceptance, now complete

The item M03-002 had to record PARTIAL is closed:

| Condition | Result |
|---|---|
| Seeded standoff includes armed ranged hostiles | PASS |
| At least one reachable cover option exists | PASS — a cover face adjacent to the Commander, asserted deterministically for all three factions |
| Evidence surface shows legal movement, cover faces, and attack targets from the same authority | **PASS** — 9 of 9 guided samples published all three blocks; previously PARTIAL because the guided lane had no cover to publish |
| A golden test can distinguish hold, approach-cover, flank, and attack | PASS, unchanged from M03-001 |

## Verification

| Gate | Result |
|---|---|
| Static project verification | PASS |
| Godot headless TestRunner | PASS |
| Godot PlaytestRunner | PASS, 282 checks (was 261; 21 new instructor, cover, and lane assertions) |
| `npm run check` | PASS |
| Full Node release suite | 39/40; the single expected fail-closed source/runtime manifest mismatch |
| Guided autonomous playtest | PASS; 6/6, SUCCESS, 3 survivors, seed `1167583760`, `M03_canonical_rationale_observed` true with five signatures |
| Guided M03 harness | PASS on all five gates |
| M05-B accessibility matrix re-run on this build | PASS, 9 cases |
| Visual review, guided round 1 | PASS; `Take Cover (T)` enabled, 3 hostiles, tutorial at 2/6 |

New deterministic coverage asserts, for all three factions, that: the instructor
exists, is hostile, holds a full Base-10 pool, is armed, stands beyond the melee
lane and within ten cells; the dummies keep `ap = 0`; the lane offers at least two
cover cells with at least one touching the Commander; and every cover cell is on
the map and clear of insertion cells.

## Authoritative packs

| Pack | Purpose |
|---|---|
| `evidence/m03/20260730T023322942Z-0a32872d` | Guided M03 closure, 5 gates PASS, cover faces 9/9 |
| `evidence/m03/20260730T004924241Z-89b82318` | M03-002 armed-sector closure, retained |
| `evidence/a11y/20260730T023640349Z-eb10ba7a` | M05-B matrix re-validated on this build |

Served tactical PCK for the guided closure: 278,360 bytes, SHA-256
`de4b85ad8efbb40330359b5fd94f2879705590dc952b5117ed7b7f162af7850c`.

## Source identities

| File | SHA-256 |
|---|---|
| `game/scripts/SquadSpawner.gd` | `4e91f22a1db1dd683b88945a621cb3ed0a3ef06aa69ce114e87f4f7eb68ab359` |
| `game/scripts/WorldBuilder.gd` | `cb438f24e3d6b4700609e30bcf14ce01a9c3af5d92c4dd0b2dbcc5027cd11bd4` |
| `game/scripts/Main.gd` | `988d58eee9e53d4aed9a5c780e36513d8a33b826ffd60011f2fe7512211f767d` |
| `game/tests/PlaytestRunner.gd` | `3c02d8f4fd8c4de675cd746e0dc8e666eea8be659dd7fedce9e4e4c81d9ddd90` |
| `game/tests/TestRunner.gd` | `1ff7d658d0b112e7244518c7db32e8e9f38521793673162430790ad34989230c` |
| `tools/m03/standoff.mjs` | `482eb41748abaf685aa7f7f5f86d4388ee0366bf56f26c17e1164711bdeb1dd5` |

## Still open

- The tutorial does not yet *teach* cover in prose. The step text still describes
  melee against a dummy; a cover instruction step would need a script change and
  a seventh tutorial step, which changes the 6/6 contract. Left as a design
  decision.
- Haili has no dialogue, portrait, or characterisation beyond her name and
  behavior.
- Whether she should be able to kill the Commander during the tutorial is
  unresolved. She is a fully armed agent; across the runs recorded here she chose
  cover and flanking rather than a lethal push, and every guided run completed
  6/6, but nothing prevents a harder line in a future scenario.
- The committed public runtime still predates all of this work; promotion belongs
  to an owner-approved M06.
