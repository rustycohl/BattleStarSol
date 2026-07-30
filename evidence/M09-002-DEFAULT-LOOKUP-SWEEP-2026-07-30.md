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

---

## Addendum — the consumers, swept

The scope section above named four consumers plus `PayloadContract` as unswept. Done here, so the
gap is closed rather than carried.

**82 further defaulted lookups, 33 on model keys:** `PayloadContract` 36 sites (19 model),
`CombatSystem` 24 (11), `TacticalUI` 19 (3), `InventorySystem` 3 (0), `StratLayer` **0**.

### Finding 1 — the weapons bar displayed a number the model does not use

`TacticalUI` built its weapon tooltip from the raw `armor_pierce` field:

```gdscript
var apierce = int(itm.get("armor_pierce", 0))
if apierce > 0: pierce_str = " (AP: %d)" % apierce
```

The model uses `Ballistics.penetration_for_item`, which is
`armor_pierce × PIERCE_PER_POINT + damage_type bonus`, clamped to 100 — and **100 outright** for a
weapon flagged `penetrates_cover`. So the tooltip read `AP: 5` where the game used 55, and a
cover-piercing weapon advertised its raw field rather than total penetration.

Two defects in one line. The number was wrong, and `AP` is the abbreviation this game uses for
action points — the core economy — so even a correct number would have been read as a cost.

Now `Penetration %d/100`, from the authority. Same species as the specials bug in M09-001: the
interface re-derived something an authority already owns.

### Finding 2 — a substituted payload was indistinguishable from a real one

`normalize_deploy` fills in missing fields with plausible values: sector becomes
`"Unknown Sector"`, faction `"HAD // VANGUARD-1"`, seed `FALLBACK_SEED`. That behaviour is right —
a partial payload should still yield a playable mission. What was missing was any way to know it
happened. A broken hand-off produced a mission that looked real, and because the fallback seed is
a **constant**, it looked reproducible too.

`PayloadContract.deploy_shape_report(raw)` (new) reports which fields were substituted and
whether the squad is explicitly empty — pure, and reporting rather than rejecting. The
substitution stays; the silence does not. Asserted both ways: a partial payload is reported
incomplete **and** still normalises to a playable mission, so nothing starts crashing that
previously played.

### What was checked and found correct

- `CombatSystem` reads `damage_type` / `armor_pierce` in two places (ranged and melee) and
  `penetrates_cover` in two more. These feed damage resolution and cover-ignoring targeting
  respectively, which are different questions; not a duplicate authority.
- `InventorySystem`'s three defaults touch no model keys.
- **`StratLayer` has none at all.**

### An overstated claim, corrected

`_test_consumer_defaults` asserts the authority's penetration is on the 0–100 scale, is not the
raw field passed through, and reads as total for a cover-piercing weapon. **It does not observe
the tooltip.** Reverting `TacticalUI` to the raw field leaves every assertion passing — verified by
running that negative control, which did not fire.

The test comment now says so explicitly. Closing it means reaching the weapons-bar button and
reading its tooltip, the way `_test_specials_stay_visible_in_god_mode` reaches `action_btns`. That
is a further module. This is the third time in this session that a plausible assertion turned out
not to test what it appeared to; the pattern is that asserting *near* a value is not asserting
*the thing that consumes* it, and only the negative control tells them apart.

### Gates

`npm test` **60/60**; Godot `TestRunner` **PASS, 1492 checks**; `PlaytestRunner` **PASS, 312**.
Runtime re-exported then `MANIFEST.sha256` regenerated, normalized to LF, verified `i/lf w/lf`.

### Remaining, named

A payload-shape gate is reported but not yet *enforced* anywhere — nothing fails a mission for
launching on a substituted payload, and nothing surfaces the report to the player or the
extraction. Wiring `deploy_shape_report` into the launcher and the extraction envelope is the
obvious next step, and is the payload analogue of Option E.
