# M03-007 — Standoff cover is derived, not authored

- **Date:** 2026-07-30 (UTC-05:00)
- **Checkout:** `C:\CLAUDE\7-30-2026-Claude\BattleStarSol` (HEAD `7a8c04f` + upstream
  uncommitted work)
- **Environment:** Godot 4.7.1.stable.official.a13da4feb, headless
- **Gate:** M03-007 — every cover cell in a live scene carries material
- **Result:** **PASS**, regression observed failing against the prior behaviour first
- **Agent:** Claude Opus 5

## Finding

The upstream Standoff sector — a new launcher scenario built specifically to demonstrate AI
cover and flanking — injected its cover directly:

```gdscript
main.cells[cover_cell] = {"type": Config.COVER, "z": 3}
```

This bypasses `WorldBuilder.material_cell()`, which is the single authority for what a
cell is made of. M03-004 made `density`, `integrity`, and `material` load-bearing precisely
so that cover would stop being a painted flag.

**Why it was invisible.** The cell still scores correctly. `Ballistics.density_of()` has a
deliberate back-compat path for cells authored before materials existed: when neither
`integrity` nor `density` is present it calls `density_for_type()`, which delegates to
`World.material_cell()` and returns the identical density of 60 for a three-high cover
column. So cover strength, penetration, and destruction all behave exactly as they should.
There is no behavioural symptom to notice. A compatibility path built for old fixtures
quietly absorbed a new special case.

**What it actually costs.** The `material` key is absent, and two consumers read it:

- `Main._rebuild_tile()` passes `String(data.get("material", ""))` into
  `spawn_tile(..., material_state)`. Benign here — the pristine visual is correct either
  way, and once damaged `degrade_cell` writes `material` itself.
- **The terrain ledger records `material_before: ""`.** `Main.gd:2095` writes the
  pre-damage material into the `terrain_damaged` event. The reproduction schema types that
  field as a plain string with `maxLength: 32` and no enum, so `""` validates and the
  artifact does **not** fail closed. A replay of a Standoff mission therefore states that
  the wall was made of nothing before it broke, and nothing anywhere complains.

So: not a crash, not a scoring bug, and not caught by the fail-closed contract. A fidelity
defect in the replay record, plus a special case sitting directly on top of the system
built to make special cases unnecessary.

## Change

**`game/scripts/SquadSpawner.gd`** — the Standoff branch now calls
`World.material_cell(Config.COVER, 3)`, with a comment recording why the bare dict looked
fine and what it lost.

**`game/tests/TestRunner.gd`** — new `_test_scene_cover_is_material()`. It drives the
Standoff sector through the `PayloadBridge` autoload, instantiates `Main.tscn`, walks the
entire grid, and fails on any `COVER` or `HALF_COVER` cell missing `density`, `integrity`,
or `material` — reporting the offending coordinate and its actual key list. It also asserts
that the standoff lane cover is `hard` and that its density equals what the shared material
model assigns, so the demo cover is provably indistinguishable from generated cover.

The assertion is deliberately **structural, not behavioural**. Behaviour cannot catch this
class of defect: the compatibility fallback makes authored cover behave correctly by
construction. The only way to catch it is to check the shape of the cell.

## Verification

Negative control first — reverted `SquadSpawner.gd` to the upstream authored-cover form:

```text
FAIL: 1 cover cell(s) were authored without material fields -- cover must come from
      WorldBuilder.material_cell(); first: (3, 4) (type 1, z 3, keys ["type", "z"])
FAIL: standoff lane cover is not hard material
FAIL: standoff lane cover density diverges from the shared material model
```

Fix restored, full suite re-run: `PASS: Battle/Star.SOL headless tests`.

## Note for the register

`Ballistics.density_of()`'s back-compat path is load-bearing for the golden fixtures and
should stay, but it is now known to mask authored cover. `_test_scene_cover_is_material()`
is the control that makes it safe to keep. If a future scene builds cells outside
`material_cell()`, this is the test that will say so.
