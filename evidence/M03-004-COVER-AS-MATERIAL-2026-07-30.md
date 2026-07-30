# M03-004 Cover as material, and the cover instruction step

## Authority

Principal decisions, 2026-07-30, in sequence:

1. add a cover instruction step to the guided tutorial;
2. "cover is naturally occurring from the environment ofc";
3. "game should have destructible environments and penetration mechanics, which
   inform you as to how to generate cover";
4. build this way in general — derive from what already exists, and ask when the
   documents do not decide.

The fourth is recorded as a standing principle in
`C:\SOL\WORLD-ENGINE-V1\.agents\07-SYSTEMS-FROM-SYSTEMS.md`, referenced from the
agent orientation checklist.

## What was wrong, and what replaced it

M03-003 gave the training lane cover by placing two cover cells beside the
Commander. It worked and it was wrong: the lane had cover because a tutorial
function said so.

Two systems that already existed were unfinished.

### Terrain generation erased its own cover

`generate_cells` flattened a four-deep pad at every spawn so units never spawn on
a column. That also removed every cover face beside an insertion point — the
reason `Take Cover` had been permanently disabled in every tutorial ever run.

The generator now levels only the cells a squad stands on plus one step off each
(`_inside_spawn_footprint`). The rest of the former pad keeps its generated
terrain, so **cover near a spawn is naturally occurring**. The historical
four-deep rule is retained in source as `_inside_spawn_pad` for reference.

`cover_near_spawn` reads naturally occurring cover out of the generated terrain
for tests and evidence. Nothing paints cover in.

### Cover was a flag, not a material

Every cell already carried a `density` field that nothing consumed. Cells now
carry `material`, `density`, and `integrity`, derived from cover class and column
height: a taller column is thicker, so it stops more and lasts longer.

`Ballistics.gd` makes that material mean something. It is pure and deterministic,
so headless checks and the live simulation cannot disagree:

| Concern | Behaviour |
|---|---|
| Penetration | Weapon penetration is expressed on the same 0–100 scale as density, so a weapon's number reads directly against a wall's. Skills already on units (`primitive`, `ballistic`, `pistol`, `rifle`, `shotgun`, `sniper`, `laser`, `plasma`, `magnetic`) supply the values. |
| Stopped fire | Penetration below integrity stops the round — and still works the material. |
| Penetrating fire | Above integrity the round passes through with power reduced in proportion to what it had to chew through, and takes material with it. |
| Destruction | A cell degrades through its own classes: hard cover to soft cover, soft cover to rubble, rubble to open ground. |
| Cover strength | Read from material state, so a wall shot down stops scoring as full cover. |
| Protection | `protects_against` answers whether a wall still shields a defender from a specific shooter's best penetration. |

`AITactics.cover_level` and `MovementContext.cover_faces_at` now derive from
material rather than tile type. **Destruction therefore changes tactics without a
second rule set**: a wall reduced to rubble stops offering a commitable cover face
and stops scoring in the firing lane, for the player and the AI alike, through the
same authority.

Cells authored before materials existed — including the M03 golden fixtures —
carry no density, so their type supplies the material they always implied. The
twelve M03-001 golden checks pass untouched.

## The cover instruction step

The guided tutorial is now seven user-facing steps: COVER sits between DEFENSE and
ATTACK.

The instruction text for cover already existed as alternate DEFENSE prose for a
situation the scenario could never produce. It is now its own step:

- DEFENSE asks for Brace, and advances to COVER when cover is adjacent;
- taking cover at DEFENSE satisfies both, so a player reaching for the stronger
  option is never told they did it wrong;
- COVER requires Take Cover on a published cover face, and names Haili as the
  agent to watch use it;
- a lane with no adjacent cover skips COVER entirely and keeps the six-step path;
- cover that disappears mid-step — through a move, a stance change, or a committed
  maneuver — advances rather than stranding the player.

`USER_STEP_COUNT` is 7 and display numbering renumbers accordingly. The autonomous
harness follows the seven-step contract and reports the cover step as taken or as
correctly skipped.

## Verification

| Gate | Result |
|---|---|
| Static project verification | PASS |
| Godot headless TestRunner | PASS |
| Godot PlaytestRunner | PASS, 282 checks |
| `npm run check` | PASS |
| Full Node release suite | 42 tests, 41 pass; the single expected fail-closed manifest mismatch |
| M03-001 golden cover/flank cases | PASS, unchanged |
| Live guided seven-step run | PASS; 7/7, SUCCESS, 3 survivors, seed `1167583760` |

New deterministic coverage: material density scales with cover class and column
height; fresh terrain starts at full integrity; primitive fire is stopped by hard
cover and still works it; sniper fire penetrates at reduced power; sustained rifle
fire degrades hard cover out of full-cover scoring and eventually to rubble;
legacy cells keep the cover they implied; protection depends on the shooter;
insertion cells stay level across five seeds; natural cover occurs near a spawn;
and the tutorial's cover step is required when cover is present, skipped when it is
not, satisfied by taking cover early, and never a dead end.

## Live result and its honest limit

The live guided run reached 7/7 and **correctly skipped** the cover step: the
harness chooses a move that ends adjacent to a visible hostile, and on this seed
that destination is not beside cover. Both branches are proven deterministically;
the live run exercised the skip branch.

Exercising the cover branch live would need the harness to prefer a destination
beside cover, which it cannot currently see — the observation surface publishes
cover faces for the actor's present cell only. Named as follow-up rather than
worked around.

The guided ledger in the same run reported `protective cover now`,
`lean from committed cover`, `cover route`, `simple flank`, `take_cover`, and
`flank` — Haili using material cover under the new model.

## Source identities

| File | SHA-256 |
|---|---|
| `game/scripts/Ballistics.gd` | `a0a48b055a9afdf8393c1f9ff86f1aa6252453de5f3f115d7e7d6930a236946b` |
| `game/scripts/WorldBuilder.gd` | `078ad35ffce06fc896867e87aaadce78fdc507103d5d8f5629275e5dd003c070` |
| `game/scripts/AITactics.gd` | `acac5f8bcc975730e6c3e20f0ac6cd543002d16dd984f6011f603ee126abccfc` |
| `game/scripts/MovementContext.gd` | `48b46cd8a624db864c850b901b4f7af549b7d97b430626d6b7c4d4c473465c34` |
| `game/scripts/TutorialDirector.gd` | `817a96d71b208ea80c7453000cfae36623b498abba7e9d339fa02d74ed1d0b05` |
| `game/tests/TestRunner.gd` | `6b34034c182e4b5f8f85e5f2dd3bee39fe0409dbf2e4a18f188cfadfce58cdcd` |
| `tools/playtest/run.mjs` | `04d87db171e01b33b873150635b3dd85c80136093932a9ead7c29e6d84ada20e` |

## Still open — and this is a real scope boundary

**Penetration and destruction are wired into cover derivation, not yet into combat
resolution.** `CombatSystem` does not yet call `resolve_penetration` to reduce a
round's damage through a wall, and no cell's integrity is reduced by live fire, so
terrain does not visibly break during a mission yet. The model, its scoring, and
its tests are real; the shooting path is the next module.

Also open:

- no visual destruction, debris, or tile mesh update on degradation;
- terrain changes are not yet part of the extraction ledger or the reproduction
  contract, so a destroyed wall is not carried in a replay;
- penetration values are a first calibration and have had no balance pass;
- the tutorial does not yet teach that cover can be destroyed or shot through;
- the harness cannot yet aim a move at cover, so the live cover step is skipped on
  this seed.
