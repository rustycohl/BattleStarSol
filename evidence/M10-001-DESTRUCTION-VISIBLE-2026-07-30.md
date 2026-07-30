# M10-001 — Destruction is visible: appearance follows integrity, and so does the redraw

- **Date:** 2026-07-30 (UTC-05:00)
- **Checkout:** `C:\CLAUDE\7-30-2026-Claude\BattleStarSol`
- **Environment:** Godot 4.7.1.stable.official.a13da4feb, headless; Node 22
- **Gate:** M10-001 — a damaged wall looks damaged, in proportion
- **Result:** **PASS**, three defects found and fixed, each with a control observed failing
- **Agent:** Claude Opus 5

## The goal, stated plainly

From the roadmap and page five of the treatment: *a wall that has taken four rifle rounds
should look like a wall that has taken four rifle rounds.* The destruction model has tracked
material, density, and integrity since M03-004. None of it reached the player except in three
sudden jumps.

## What was actually wrong — three layers, only the first of which was obvious

**1. The appearance model was discrete while the damage model was continuous.**
`spawn_tile` took a `material_state: String` and drew something only for `"rubble"` or
`"soft"`. Integrity runs from a cell's original density down to zero, so a hard wall at 54 of
96 — three hits from gone — rendered identical to an untouched one.

**2. The redraw trigger was threshold-based, so a continuous appearance could not have
helped.** This is the one that mattered, and it was invisible until the wiring was tested
end to end. `Main.damage_terrain` rebuilt a tile only when:

```gdscript
if int(before.get("z", 0)) != int(after.get("z", 0)) or cover_before != cover_after:
    _rebuild_tile(cell)
```

Both conditions are threshold crossings. A wall could take three rounds, lose a third of its
material, and never be redrawn. **Making the appearance continuous behind a threshold trigger
would still have produced three states** — the module would have looked done and changed
nothing on screen.

**3. A latent regression I introduced and caught by printing the numbers.** The first version
of `damage_appearance` tested the material name before wear. `material_cell` names
HALF_COVER's material `"soft"` to describe what it is made of; `degrade_cell` writes `"soft"`
to mean a hard wall worked down. Same string, two meanings. Every untouched half-cover tile on
the board classified as damaged — a duplicated material per tile and a visible lean on
undamaged terrain, which is exactly the leak an earlier bugfix had removed. Every invariant I
had written still passed. The table did not:

```text
--- pristine cells of each type must not draw ---
type 0: wear 1.000 state pristine draws false
type 2: wear 1.000 state soft     draws true      <-- pristine half-cover, drawing
type 1: wear 1.000 state pristine draws false
```

Live build notes rule 14, earned again: invariants are not a substitute for looking at the
output.

## Changes

**`WorldBuilder.gd`** — three new pure functions, following the `HudLayout`/`Ballistics`
pattern so the model is assertable headlessly without a scene:

- `wear_of(cell_data) -> float` — how much of its original material a cell still has, 1.0 to
  0.0, as `integrity / density`. Nothing new is stored; the ratio was already in the data.
  Cells with no `integrity` key — the golden fixtures — read as pristine, matching how
  `Ballistics.density_of` treats them. Rubble carries `density 0` by construction, so the
  material tag is what separates "never had anything" from "lost everything".
- `damage_appearance(cell_data) -> Dictionary` — state, wear, darkening, scorch, and
  deterministic per-cell jitter. **Wear decides whether a cell looks damaged; the material only
  decides how that damage reads.**
- `tile_visual_signature(cell_data) -> String` — everything that changes how a tile is drawn,
  as one comparable string, with darkening quantised to `DARKEN_QUANTUM = 0.02` so a rebuild
  fires on visible change rather than per point of integrity.

One continuous darkening formula, `min(damage × 0.6, 0.55)`, reproduces both constants the old
three-state version used: at the soft-cover threshold it lands on 0.30, and at total loss it
reaches 0.60 and clamps to the rubble ceiling. Chosen for that reason, not by taste.

**`spawn_tile`** now takes the cell itself rather than a material label, so appearance is
derived from the material the cell has left and cannot disagree with it. It returns before
touching the material when the cell is pristine, preserving the no-leak fix. It keeps
`tile.material_override` rather than a per-surface override, because that is what the rest of
the codebase and the playtest suite assert on and the tiles are single-surface.

**`build_grid`** now routes through `spawn_tile` with the cell, so a map that arrives already
damaged — an imported strategic hand-off, a replayed mission — builds looking damaged instead
of rendering pristine until something hits it again.

**`Main.damage_terrain`** redraws when `tile_visual_signature` changes. The signature includes
type and `z`, so it strictly subsumes both conditions it replaces.

## Verification

Measured, not asserted — twelve damage per hit into a density-96 wall:

```text
hit  integrity  signature              redraw
  0   96        1|6|pristine|0|0       -
  1   84        1|6|worn|4|0           YES
  2   72        1|6|worn|8|0           YES
  3   60        1|6|worn|11|0          YES
  4   48        2|2|soft|15|0          YES
  5   36        2|1|soft|19|0          YES
  6   24        2|1|soft|22|0          YES
  7   12        2|1|soft|26|0          YES
```

Every hit changes the drawn result. Four rounds now look like four rounds.

Negative controls, each observed failing before revert:

| Mutation | Observed failure |
|---|---|
| material tested before wear | `freshly generated type 2 reads as 'soft' rather than pristine`, `… would draw a damage override, duplicating a material for undamaged terrain`, and the same for types 0 and 1 |
| threshold-only redraw trigger restored | `a damaged tile has no override material, so the damage is invisible in play` |

`_test_damage_appearance` covers: pristine terrain of every type draws nothing; pre-material
cells read pristine; darkening is monotonic under cumulative damage and never exceeds rubble;
all three damaged states are reached in order; only rubble is scorched and only rubble sits at
the ceiling; appearance is repeatable for the same cell, which a replay depends on; every hit
changes the visual signature; and the signature distinguishes height.

`_test_scene_cover_is_material` gained end-to-end wiring assertions, because a correct model
is not a model that reaches the screen: an untouched tile must carry no override, and a cell
damaged through `damage_terrain` must come back carrying one.

Gates: `npm test` **56/56 PASS**, Godot `TestRunner` **PASS**, `PlaytestRunner` **PASS, 312
checks**. Web runtime re-exported, then `MANIFEST.sha256` regenerated from it, normalized to LF.

## Two things found and deliberately not changed

**A test that errors is indistinguishable from a test that passes.** While wiring the scene
assertions I called `damage_terrain` with the wrong argument order. Godot printed
`SCRIPT ERROR: Invalid type in function 'damage_terrain' … Cannot convert argument 3 from Nil
to String`, abandoned the rest of that test function — and `TestRunner` still reported
`PASS`. Every assertion after the error simply never ran. This is a real hole in the gate: any
test that dies mid-way looks green. Fixing it means failing the suite on `SCRIPT ERROR`
output, which is a change to the harness rather than to this module. **Recorded, not fixed.**

**A six-high wall collapses to two-high in one step** when it crosses the soft threshold
(`degrade_cell` sets `z = mini(maxi(height - 1, 1), 2)`). That is pre-existing behaviour and
reads as a sudden geometric drop mid-fight. Whether a tall wall should shed height gradually
is a design question, not a defect. Named so it is visible.

## Still not visible

Damage now shows as darkening, roughening, loss of glow, lean, scorch, and height loss. It
does **not** show as cracks, decals, or debris geometry — there is no texture or particle work
here, only material and transform. That is the honest boundary of this module.
