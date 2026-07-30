# M09-002 — Sweep of defaulted lookups in the registered authorities

- **Date:** 2026-07-30 (UTC-05:00)
- **Checkout:** `C:\CLAUDE\7-30-2026-Claude\BattleStarSol`
- **Environment:** Godot 4.7.1.stable.official.a13da4feb, headless; Node 22
- **Gate:** M09-002 — a malformed cell cannot enter the model unnoticed
- **Result:** **PASS**. No defects found in the defaults themselves; the structural gap they
  create is now closed.
- **Agent:** Claude Opus 5

## Why this sweep

From M03-007: the Standoff sector built a cover cell by hand as `{"type": COVER, "z": 3}` and it
*behaved correctly*, because `Ballistics.density_of` has a deliberate back-compat path that
derives material from the type for pre-material fixtures and reached the identical density. The
only symptom was an empty `material_before` in the terrain ledger, which the reproduction schema
types loosely enough to validate. No behavioural test could have caught it.

The generalisation recorded at the time: **every `get(key, default)` in an authority is a place
a special case can enter without symptom.** This is the audit of those sites.

## What the sweep found

Mechanical scan of the eleven authorities named in `.agents/08-CAPABILITY-REGISTER.md`:

| Authority | Role | Defaulted lookups |
|---|---|---:|
| `Main.gd` | terrain change during a mission | 90 |
| `PayloadContract.gd` | deploy/extraction payloads | 36 |
| `Ballistics.gd` | penetration, destruction, cover strength | 13 |
| `AITactics.gd` | cover scoring in a lane | 12 |
| `WorldBuilder.gd` | terrain generation and material | 11 |
| `Pathfinder.gd` | line of sight | 8 |
| `MovementContext.gd` | commitable cover faces | 5 |
| `GameState.gd` | ledger of record | 4 |
| `ActionEconomy.gd` | action costs | 3 |
| `HudLayout.gd` | HUD layout and contrast | 1 |

**183 sites total; 63 of them on the cell and material keys** — the class that hid the Standoff
bypass.

**No defects were found in the defaults.** This is the honest result and it is worth stating
plainly rather than manufacturing findings. Nearly every default is the conservative answer: a
missing cell reading as `z = 0` and `type = FLOOR` means "open ground", which is what an absent
cell should be. Removing them would introduce crashes, not remove bugs.

Three sites looked suspicious enough to read closely, and all three were correct:

- **`Main.gd` terrain-change guard** — `int(after.get("type", -1)) == int(before.get("type", -2))`.
  The two defaults differ **on purpose**: a cell missing `type` entirely must compare unequal so
  the change is still recorded rather than dropped as a no-op. Correct, and undocumented, so it
  now carries a comment explaining the asymmetry. Left as it was otherwise.
- **`Pathfinder` cover tests** — `cells[c].get("type", 0) == GameConfig.COVER`. `0` is
  `Config.FLOOR`, so a missing cell reads as not-cover, which is right. Changed to
  `GameConfig.FLOOR`: identical value, states the intent.
- **`WorldBuilder._loot_candidates`** — `get("z", 99)`, so a missing cell can never be a loot
  candidate. Deliberately conservative. Unchanged.

## The real gap, and the fix

Defaults cannot detect that something entered the model malformed — that is precisely what they
exist to tolerate. So the remedy is not to touch the defaults. It is to assert the **shape** of
what enters.

**`WorldBuilder.CELL_FIELDS` and `cell_shape_error(cell_data)` (new)** — the authoritative field
set for a terrain cell, and a pure predicate returning `""` or the reason a cell is malformed. It
rejects a missing field, an **unrecognised** field, negative material, integrity exceeding the
density the cell started with, and a height exceeding the tiers it started with.

The unrecognised-field check matters as much as the missing-field one: a stray key is how a
parallel model begins. A cell carrying `painted_cover` is rejected by name.

**`_test_cell_shape_authority` (new)** asserts:

- `material_cell` satisfies the shape it defines, across all three types and five heights;
- a cell satisfies it at **every stage of its destruction**, nine successive hits deep;
- the whole generated world satisfies it, 400 cells at the pinned seed;
- and malformed cells are actually rejected — hand-built, non-Dictionary, integrity above its
  starting density, height above its starting tiers, and a stowaway field. Without those, the
  check would be decoration.

**`_test_scene_cover_is_material` generalised** from cover cells to the entire live grid. The
narrow version was written for the defect that prompted it; this is the general form.

## Verification

Negative control — reinstated the hand-built Standoff cell:

```text
FAIL: 1 cell(s) in the live scene do not satisfy the cell shape;
      first (3, 4): missing ["density", "integrity", "material", "tiers", "climbable"]
      (has ["type", "z"])
FAIL: 1 cover cell(s) were authored without material fields …
FAIL: standoff lane cover is not hard material
```

The general check names the exact missing fields, which the narrow one could not.

| Gate | Result |
|---|---|
| `npm test` | **PASS**, 60/60 |
| Godot `TestRunner.gd` | **PASS**, **1472 checks** (was 1441) |
| Godot `PlaytestRunner.gd` | **PASS**, 312 checks |

Web runtime re-exported, then `MANIFEST.sha256` regenerated from it, normalized to LF.

## Scope, stated honestly

**Swept:** the eleven authorities in the capability register, for defaulted dictionary lookups.

**Not swept:** the same pattern in `TacticalUI.gd`, `StratLayer.gd`, `CombatSystem.gd`, and
`InventorySystem.gd`. Those are not registered as authorities, which is exactly why they were out
of scope and also why they deserve their own pass — a consumer that defaults its way around a
missing field is how the *next* silent divergence starts. `PayloadContract.gd`'s 36 sites are the
largest remaining concentration and govern the deploy/extraction boundary; a payload-shape
predicate on the same pattern as `cell_shape_error` is the obvious next module there.

**Not attempted:** removing any default. The sweep's conclusion is that the defaults are right
and the missing thing was a shape assertion. That is a narrower result than "found bugs", and it
is what the evidence supports.
