# M03-005 Destruction in play, in the ledger, and calibrated

## Authority

Principal decision, 2026-07-30: do all of the outstanding items, in order —
penetration called from combat resolution, terrain change carried in the
extraction ledger and reproduction contract, and a balance pass on penetration
values.

M03-004 built the material model and derived cover from it, but stated plainly that
penetration was not yet called from `CombatSystem`, so terrain did not break in
play. That is now closed.

## 1. Penetration in combat resolution

The ranged damage path already had cover reduction, an authored `penetrates_cover`
flag, and `armor_pierce`. Penetration now informs those rather than duplicating
them.

On every ranged hit, `CombatSystem.apply_damage`:

1. resolves the cell standing in the firing lane — the same face the cover model
   reads, so the round meets exactly the material that was protecting the target;
2. resolves penetration against that cell's integrity using the weapon's own
   fields;
3. scales the cover reduction by how much of the round the material took, so a
   penetrating weapon gets a proportionate share of the target rather than a
   binary bypass;
4. applies the material damage through one authority.

`Main.damage_terrain` is that authority. It changes the cell, rebuilds the single
affected tile so the world matches the simulation, appends to the mission's ordered
`terrain_changes`, records a `terrain_damaged` event, and **releases any unit still
committed to cover that no longer protects** — a unit is never left holding a wall
that is not there.

Weapon penetration derives from the fields weapons already carry:

`penetration = armor_pierce x 10 + damage-type bonus`, clamped 0-100, with
`penetrates_cover` reading as total penetration so the authored intent and current
balance are preserved exactly.

## 2. Terrain change in the ledger and the contract

`terrain_damaged` is a `GameState` event, so it already flows into the extraction
replay. The reproduction contract now carries it on the same terms as
`unit_killed`: a bounded grid cell, the acting unit, and the material transition.

A correction to my own earlier claim: I had written that the M04 contract excludes
map coordinates. It excludes **A.T.L.A.S. real-world coordinates**, browser and
profile surfaces, and direct names — it already carries bounded **grid** positions
for `movement_resolved`, `agent_decision`, `loot_collected`, and `unit_killed`.
Terrain damage follows that existing rule rather than a new one.

Added to `tools/repro-bundle.mjs` and `contracts/battlestar-repro.schema.json`:
`attacker` (0 for an unattributed environmental change), `cell`, `cover_before`,
`cover_after`, `integrity_before`, `integrity_after`, `material_before`,
`material_after`, `destroyed`, and `weapon`. Everything else fails closed.

The cell records its height, because the contract's bounded position requires it
and a change at a given height is meaningful — the data was extended rather than
the contract loosened.

## 3. Balance pass

`game/tests/BallisticsTable.gd` emits every shipped ranged weapon against every
cover class the generator can produce, using the same derivation the simulation
uses. The table is evidence, not an assertion.

The first pass exposed two real calibration faults, both fixed:

- **A knife-edge.** At `armor_pierce x 9`, plasma landed on 59 against a
  60-density wall — stopped by a single point nobody authored. The scale is now
  `x 10`, matching this project's base-10 action economy and the decadal density
  scale, which removes the accident and produces a readable ladder.
- **A degenerate tie.** Equal penetration and integrity "penetrated" while
  delivering zero power. The material now wins ties, so a pass-through always means
  something arrived.

The resulting ladder across 14 ranged weapons — six penetration tiers, 0 to 100:

| Weapon class | Penetration | Soft cover | Thin hard cover | Thickest hard cover |
|---|---:|---|---|---|
| Bow | 0 | stopped | stopped | stopped |
| Tier-1 ballistic | 10 | stopped | stopped | stopped |
| Tier-1 sniper | 20 | stopped | stopped | stopped |
| Tier-2 laser | 25 | through | stopped | stopped |
| Tier-4 plasma | 65 | through | through | stopped |
| Rail and beam | 100 | through | through | through |

Ten of fourteen weapons are stopped by some cover; four penetrate everything, and
all four are the weapons authored as `penetrates_cover`. Every weapon can eventually
break cover by working the material, so cover is never absolute — but for most
weapons the answer is still to flank, which is what the AI already does.

## Verification

| Gate | Result |
|---|---|
| Static project verification | PASS |
| Godot headless TestRunner | PASS |
| Godot PlaytestRunner | PASS, 294 checks (was 282) |
| `npm run check` | PASS |
| Full Node release suite | PASS, 43/43 after the M06 manifest regeneration |
| Live guided playtest | PASS, 7/7 |

New deterministic coverage: a live mission stands a wall between a shooter and a
target, confirms it reads as full cover, damages it and sees integrity fall, checks
the change reaches both the mission record and the ledger, destroys it under
sustained fire, confirms cover scoring drops to zero and the tile is no longer a
cover tile, confirms the destruction is recorded as destroyed, and confirms open
ground stops taking terrain damage. Contract coverage adds a well-formed terrain
event, an unattributed environmental change, and five fail-closed cases.

One model correction found by that test: rubble kept a residual integrity, so open
ground could still be "damaged". Nothing is left standing, so rubble now carries no
density — exactly like freshly generated floor.

## Source identities

| File | SHA-256 |
|---|---|
| `game/scripts/Ballistics.gd` | `b28c8adb0eb1ac764aa9dbf0773b0d4cc3f969cf3bd143a6b5937fffc067ef89` |
| `game/scripts/Main.gd` | `27eab4c0a2d45f251581fe55571c43c5ccb9328ec4cc253bf45cbe4765fe63b4` |
| `game/scripts/CombatSystem.gd` | `86870266fceb3d2a6c3ee7aa84aa436d001bbba317db78928f76500246cf4fc2` |
| `tools/repro-bundle.mjs` | `f6ec77980aa55b1eef86e5fdf15d67890a0e0f3c6158eb202a5a1882c951d2e8` |
| `contracts/battlestar-repro.schema.json` | `fbee308106987a6e6b02de8b9e85afc97f6b30d376084dbc63f8d26422999f1a` |

## Still open

- **No visual destruction beyond the tile rebuild.** A degraded cell changes height
  and colour class; there is no debris, dust, or animation.
- The checked-in M04 reproduction artifact predates terrain events, so the contract
  supports them but no bundle exercises one yet. Regenerating it needs a fresh
  authoritative pack from a mission where terrain actually broke.
- Penetration does not yet interact with armour on units, only with terrain.
- Vertical cover is not modelled: a wall protects along its axis regardless of
  shooter elevation.
- The balance table is a first coherent ladder, not a playtested one. Playtesting
  is the principal's.
