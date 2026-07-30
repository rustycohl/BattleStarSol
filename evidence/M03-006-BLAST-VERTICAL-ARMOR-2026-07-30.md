# M03-006 Grenade, vertical cover, and armor penetration

## Authority

Principal decisions, 2026-07-30:

- visual destruction, delivered as a new in-game object: the grenade, which
  explodes and does area damage including to terrain, so the new mechanics can be
  tested properly;
- penetration added to weapon and armor mechanics explicitly;
- vertical cover modelled — all cover.

## Vertical cover

A wall now only protects while it actually stands between the shooter and the
target. `Ballistics.cover_stands_between` compares the cover's height against the
greater of the two units' elevations: shoot from above it, or stand on something as
tall as it, and it stops being cover.

Threaded through every consumer rather than added beside them:

- `AITactics.cover_level` takes shooter and target elevation. Existing ground-level
  callers keep their meaning through defaults.
- `MovementContext.cover_faces_at` takes the actor's elevation, so a unit standing
  above a wall can no longer commit to it.
- `Main._in_cover` passes both elevations; `CombatSystem` supplies the shooter's.

High ground already granted a damage bonus. It now also denies the target their
cover, which is what "high ground" should have meant all along.

## Armor penetration

Armor is expressed on the same 0-100 scale as terrain density and weapon
penetration, so "can this round get through that" is one question with one answer
whether the obstacle is a wall or a breastplate. Unit armor is authored in small
integer points, so a point is worth ten — base-10, like the action economy.

`Ballistics.resolve_armor` mirrors terrain exactly: armor that beats the round stops
it, armor the round beats mitigates only in proportion to what it took out of the
shot. `CombatSystem` uses that proportion in place of the previous flat
`armor - armor_pierce` subtraction. The authored `armor_pierce` is still the input;
what it buys is now graduated rather than a cliff.

## The grenade

A new carryable object modelled on the rock — a thrown item, not a firearm — with
two new authored fields that describe what it does rather than special-casing it:

| Field | Value | Meaning |
|---|---|---|
| `blast_radius` | 2 | cells affected from the landing cell |
| `blast_terrain` | true | the blast works terrain, not only units |
| `armor_pierce` | 3 | penetration 30 on the shared scale |
| `dmg` / `range` / `cost` | 8 / 6 / 4 | damage, throw range, AP |

`CombatSystem._detonate` resolves on the landing cell, not on a target:

- every living unit within radius takes damage halving with distance, minimum one,
  **including the thrower's own squad**;
- units are resolved in a deterministic order so a replay resolves identically;
- terrain in radius is worked through `Main.damage_terrain`, the same authority
  ordinary fire uses, with damage falling off from the centre;
- one `blast_resolved` event records attacker, cell, radius, units hit, damage
  dealt, and cover destroyed.

Every squad member starts with one grenade, so destructible terrain is reachable in
the first turn of any mission rather than only after finding scattered loot.

## Visual destruction

Two additions, both feedback rather than simulation:

- **Detonation.** An emissive sphere expands and fades over 0.28 s at the blast
  centre.
- **Damaged terrain.** `WorldBuilder.spawn_tile` now takes the cell's material
  state, so a rebuilt tile reads as damaged: rubble is darkened, matte, faintly warm
  and rotated off-axis; a wall worked down to soft material is dulled and leaning.

A destroyed wall no longer silently becomes pristine floor.

## Contract

`blast_resolved` is carried in the reproduction contract on the same terms as the
other events, with a strict payload allowlist. The terrain it breaks is recorded
separately as `terrain_damaged`, so a blast's aggregate outcome and its individual
material changes are both auditable.

## Verification

| Gate | Result |
|---|---|
| Static project verification | PASS |
| Godot headless TestRunner | PASS |
| Godot PlaytestRunner | PASS, 294 checks |
| `npm run check` | PASS |
| Full Node release suite | PASS, 43/43 |
| Guided browser loop | PASS, 7/7 against the committed runtime |
| Accessibility matrix | PASS, 9 cases, 7 gates |

New deterministic coverage: a tall wall protects two ground-level units, stops
protecting a shooter above it and a target level with it, and still protects two
units below its height; a unit above a wall cannot commit to it; armor is on the
density scale; a weak round is stopped by heavy armor and mitigates fully; a rail
penetrator gets through and costs the armor proportionally; heavier armor never
mitigates less; the grenade has a blast radius, affects terrain, is throwable, is a
registered carryable kind, and its point-blank blast breaks hard cover.

## Source identities

Recorded in the release commit `e7800dc` and tag `v0.1.2-prealpha.1`.

## Still open

- Blast damage does not yet fall off around corners: radius is Chebyshev distance,
  not line of sight, so a grenade affects a unit behind a wall it did not breach.
- No fragmentation, no lingering effects, no smoke.
- Vertical cover uses height comparison, not a true projectile trajectory: a shooter
  slightly below a wall's top gets no partial benefit.
- Armor ablation is unchanged: kinetic still removes one point, thermal two.
- The grenade has no throw arc animation; it uses the existing straight-line
  projectile.
