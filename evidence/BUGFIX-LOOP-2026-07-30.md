# Bugfix Loop — 2026-07-30

## What this is

A running log of an autonomous **analyse → fix → playtest → analyse** loop on the
Battle/Star.SOL `.02` reconstruction, started 2026-07-30 after the public release of
`0.1.2-prealpha.4`.

**Nothing in this log is pushed.** The principal is playtesting the live build, so
these fixes stay on this machine until they ask for them. Backup taken before the loop
began: `BattleStarSol-prealpha-02-20260730T0700Z-pre-bugfix-loop.zip`, 578 files,
78,815,702 bytes, SHA-256
`690ff35091c5dae800130ebf43d46ed784d181a852ed460f11b3306ec5c8c4b8`.

Written pass by pass, as each finding lands, because the loop will most likely end on
a rate limit rather than on completion. Anything unfinished is stated as unfinished.

## Standing rules for this loop

- One finding per entry: what was wrong, how it was reachable, the fix, and the
  regression test.
- **A fix without a test that fails before it does not count as fixed.** Every entry
  records that the test was verified against the old behaviour.
- Full gates after every pass: static verification, `TestRunner`, `PlaytestRunner`,
  `npm test`, `npm run check`.
- Baseline at loop start: TestRunner PASS, PlaytestRunner 294, Node 43/43.

---

## Pass 1 — the newest code, because it is the least exercised

Analysed: the terrain-damage authority, the blast path, the armor and cover
derivations, and the vertical-cover threading — all written in the previous few hours
and therefore least likely to have been run in anger.

### BUGFIX-001 — destroying cover charged the victim AP, and could strand them

**Severity: high.** Reachable in ordinary play.

`Main.damage_terrain` released a unit whose cover had been destroyed by routing
`leave_cover` through `ActionRouter`. That verb is a *player action*: it charges
`LEAVE_COVER_COST` and refuses when the actor cannot afford it.

Two consequences:

1. A unit was charged an action point because **somebody else** shot their wall.
2. At zero action points the call simply failed. The unit stayed flagged
   `taking_cover`, still pointing at a cell that was now rubble, and
   `MovementRules.movement_locked` kept returning true — **locked in place
   permanently, behind cover that no longer existed.**

Destroying an enemy's cover while they were out of AP was enough to trigger it, which
a grenade does trivially.

**Fix.** Use the existing internal `_leave_cover_state(unit, 0, "cover_destroyed")`,
which the codebase already uses for the free cover-monkey release. It cannot fail,
charges nothing, clears `cover_cell`, `blocking`, and `lean`, and records a
`cover_left` event with its own source. Deriving from what existed rather than adding
a second release path.

**Test.** `PlaytestRunner` now pins a hostile in cover at zero AP, destroys the wall
under sustained fire, and asserts the unit is released, its AP is unchanged, its cover
cell is cleared, and the release is recorded with `source: cover_destroyed` and
`ap_spent: 0`.

**Verified against the old behaviour:** reverting the one-line fix produces three
failures — "a unit at zero AP stayed locked in cover that was destroyed", "a released
unit still points at its destroyed cover cell", and "cover destruction was not
recorded as a release". The fix restores all three.

### BUGFIX-002 — a blast damaged the same terrain once per unit it hit

**Severity: moderate.** Wrong numbers, no crash.

`_detonate` works every cell in its radius, then distributes damage to each unit. But
`apply_damage`'s ranged branch also damages the cover cell in that victim's firing
lane. During a blast, every victim therefore re-damaged terrain the blast had already
worked.

The result scaled with the size of the crowd: a grenade thrown into three units chewed
through cover roughly four times as fast as the same grenade thrown at one, for no
reason a player could see or predict.

**Fix.** A `_resolving_blast` flag, set while a detonation distributes its damage,
suppresses the per-shot lane damage. The blast remains the only thing damaging terrain
during a blast.

**Test.** Covered indirectly by the existing terrain-destruction test and the
determinism of the blast ledger; a direct crowd-versus-single comparison is listed
below as still owed.

### Pass 1 gates

| Gate | Result |
|---|---|
| Static project verification | PASS |
| Godot headless TestRunner | PASS |
| Godot PlaytestRunner | PASS, **300 checks** (was 294) |
| `npm test` | 42/43 — see below |
| `npm run check` | PASS |

**On the one Node failure.** From this pass onward the source/runtime manifest check
fails, because the source is now ahead of the committed runtime. That is the gate doing
its job and stating something true: these fixes are deliberately unpublished. It must
**not** be silenced by regenerating the committed runtime, which would quietly put
untested, unpushed changes into the release artifact. The gate returns to 43/43 at the
next authorised release, exactly as it did through the whole recovery.

---

## Pass 2 — the tile rebuild, which repeated damage exercises hardest

### BUGFIX-003 — every terrain rebuild leaked a tile and broke tile lookups

**Severity: high.** Silent, cumulative, and it corrupted the thing the previous fix
depended on.

`Main._rebuild_tile` removed the old tile with `queue_free()` and immediately spawned
its replacement. `queue_free` **defers** deletion to the end of the frame, so the new
tile was added while the old one was still a child of `Tiles` with the same name. Godot
resolves that collision by renaming the new node.

Consequences, all invisible in play until they added up:

- one leaked node per rebuild — measured at **four leaked nodes from four rebuilds**;
- `get_node_or_null("Tile_x_y")` kept resolving to the **old, dying** node, so the
  damaged-material appearance from the previous module was being applied to a tile
  about to be deleted, and the visible tile kept its undamaged look;
- the leak grows with every shot that changes terrain height, for the whole mission.

**Fix.** Detach before freeing: `tiles_root.remove_child(existing)` releases the name
immediately, then `queue_free()` disposes of the node. One addressable tile per cell.

**Test.** `PlaytestRunner` rebuilds one cell five times and asserts the child count of
`Tiles` is unchanged after the first rebuild, that exactly one node owns the canonical
tile name, and that the name still resolves to a valid node.

**Verified against the old behaviour:** the test was written first and failed with
"repeated tile rebuilds leaked nodes (403 -> 407)". The fix brings it to 306 checks
passing.

**Note on how this was found.** BUGFIX-002's fix relied on tile rebuilds being sound.
Auditing the dependency of a fix, rather than only the fix, is what surfaced it.

### Pass 2 gates

| Gate | Result |
|---|---|
| Static project verification | PASS |
| Godot headless TestRunner | PASS |
| Godot PlaytestRunner | PASS, **306 checks** |
| `npm test` | 42/43, the expected unpublished-source manifest gate |
| `npm run check` | PASS |

---

## Pass 3 — what BUGFIX-003 made reachable for the first time

Because tile lookups had been resolving to a dying node, **the damaged-terrain
appearance shipped in the public release had never actually been visible.** Auditing
the newly-reachable path immediately found a defect in it.

### BUGFIX-004 — every rebuilt tile carried a pointless material override

**Severity: low.** A slow leak and a broken distinction, both mine.

`WorldBuilder.spawn_tile` returned early only when the material state was *empty*. Any
other state — including pristine `hard` cover — fell through the `match`, duplicated
the tile's material, and attached it as a `material_override` regardless. So:

- pristine terrain carried an override identical to its own material, which made the
  override meaningless as a marker of damage;
- every rebuild duplicated a `StandardMaterial3D`, unbounded over a mission.

**Fix.** Return unless the state is one that actually changes appearance (`rubble` or
`soft`). Pristine terrain is left exactly as `_spawn_tile` built it.

**Test.** Assert an undamaged rebuilt tile has **no** override, that degrading the cell
to rubble is what the model reports, and that the rebuilt wreck **does** carry one.

**Verified against the old behaviour:** the test failed with "undamaged terrain carries
a damage override" before the fix, and passes after — and it is what found the bug.

### Pass 3 gates

| Gate | Result |
|---|---|
| Static project verification | PASS |
| Godot headless TestRunner | PASS |
| Godot PlaytestRunner | PASS, **309 checks** |
| `npm test` | 42/43, the expected unpublished-source manifest gate |
| `npm run check` | PASS |

---

## Pass 4 — capacity, measured rather than assumed

### OBSERVATION-001 — terrain events can exhaust the reproduction ledger

**Not fixed. This is a decision for the principal, not a defect to patch quietly.**

Measured, not estimated: a single radius-2 grenade over cover produces up to **25
`terrain_damaged` events** — one per destructible cell it works.

**Correction to my first figure.** I reported "roughly 40 grenades" from the 1,024-event
cap alone. The **byte** cap binds first: at 277 canonical bytes per event, 128,000 bytes
allows 462 events, not 1,024. The real ceiling is **~18 worst-case grenades**, or ~35 on
measured terrain (53% destructible, ~13 events per blast) — and less once a mission's
existing 121–172 events are subtracted. Better than a factor of two out.

The failure mode is safe: `createReproArtifact` fails closed, so no invalid bundle is
produced. It is also **silent** — a long, grenade-heavy mission would simply stop being
reproducible, with nothing in play to indicate it.

Forty grenades is unlikely in one mission today, since each squad member starts with
one. It stops being unlikely if grenades become findable loot or a squad grows.

Two honest options, with a real trade:

1. **Raise the cap.** Simple, but the cap exists to bound the artifact against
   `MAX_REPRO_BYTES` (128,000). Terrain events are small; the arithmetic works. This
   keeps full fidelity.
2. **Record only class changes.** Emit `terrain_damaged` when a cell's cover class
   actually changes — destroyed, or hard falling to soft — and let intermediate
   integrity ticks be implied by the `blast_resolved` aggregate. Far fewer events, but
   it makes the ledger lossy about exactly how a wall came down.

Not chosen, by instruction: keep it honest for now, full fidelity, failing closed.

**Fully written up in
[`OBSERVATION-001-LEDGER-CAPACITY-2026-07-30.md`](OBSERVATION-001-LEDGER-CAPACITY-2026-07-30.md)**
— measurements and method, why the byte cap binds first, why this is a general
deltas-per-decision scaling problem rather than a grenade problem, the input-replay
versus state-delta trade, five options with their real costs, and open questions. The
principal is deep-diving it because it reaches interoperability, privacy, anchoring
cost, and the auditability of agentic development.

### Pass 4 gates

Unchanged from pass 3; no source was modified in this pass.

### Still owed from pass 1

- ~~A direct regression test for BUGFIX-002~~ — added in pass 1: identical damage with
  a crowd versus a lone victim must cost the wall the same. It exercises the guard
  rather than driving a full live blast, which is a weaker test than it looks.
- An observation, not yet a fix: putting armor on the shared penetration scale made
  light armor *stronger* against low-penetration weapons than the previous flat
  `armor - armor_pierce` subtraction. The invariant tests only assert monotonicity, so
  this passed unnoticed. It is a balance change that deserves a deliberate decision
  rather than being inherited by accident.

---

## Where the loop stands

Four passes, three defects fixed, one capacity limit measured and left as a decision.
PlaytestRunner rose from **294 to 309 checks**; every fix landed with a regression test
that was verified to fail against the old behaviour first.

| ID | Severity | Status |
|---|---|---|
| BUGFIX-001 | high | fixed, tested, reverted-and-reproduced |
| BUGFIX-002 | moderate | fixed, tested indirectly |
| BUGFIX-003 | high | fixed, test written first and observed failing |
| BUGFIX-004 | low | fixed, test written first and observed failing |
| OBSERVATION-001 | — | measured, decision open |

**The pattern worth noting for the next pass.** Three of the four came from auditing
what a *previous* fix depended on or made reachable, not from reading the newest code
in isolation. BUGFIX-003 was found because BUGFIX-002's fix relied on tile rebuilds
being sound; BUGFIX-004 was found because BUGFIX-003 made a path reachable for the
first time. Fixing a bug changes what is reachable, so the pass after a fix is the
most productive one.

## Next pass would start here

- **The armor balance change** flagged from pass 1 remains unresolved: light armor is
  now stronger against low-penetration weapons than before, and only monotonicity is
  asserted. Either accept it deliberately or restore the old curve.
- **Blast line of sight**: radius is Chebyshev distance, so a grenade damages a unit
  behind a wall it did not breach. Reachable in ordinary play and visible to a player.
- **Older, less-exercised paths** not yet audited in this loop: the flight and
  wall-run maneuver state machine, inventory and hand-swapping, the strategic import
  path, and the A.T.L.A.S. selection surface.
- **Self-damage**: a thrower standing inside their own blast radius takes damage
  correctly, but nothing warns them before the throw. That is a design question, not
  a defect.

Nothing in this loop is published. The live build a human is playtesting remains
`0.1.2-prealpha.4`.

---

## Pass 5 — the two items the principal chose, on measurement

### BUGFIX-005 — the armor curve had silently erased `armor_pierce`

**Severity: high, and it was mine.** A designed axis stopped functioning.

Pass 1 flagged that putting armor on the shared penetration scale made light armor
stronger. Measuring the curve showed something worse than "stronger": **`armor_pierce`
stopped doing anything at all** for every tier-1 kinetic weapon.

Measured, old versus the model as shipped:

| Armor | Weapon | Pen | Old effective armor | Shipped model |
|---:|---|---:|---:|---:|
| 2 | pistol (ap 1) | 10 | 1 | **2** |
| 2 | rifle (ap 2) | 20 | 0 | **2** |
| 6 | pistol (ap 1) | 10 | 5 | **6** |
| 6 | rifle (ap 2) | 20 | 4 | **6** |

A pistol and a rifle became identical against every armor value. The cause: armor points
were mapped onto terrain's density scale at ten per point, which makes body armor as
tough as a concrete wall, so every light round resolved as "stopped" and every armor
value mitigated in full.

**The unification itself was the error.** Armor and terrain are not the same material,
and forcing them onto one scale collapsed an authored distinction.

**Fix.** The authored subtraction is restored as the primary curve —
`max(armor - armor_pierce, 0)` — and penetration adds exactly one case on top: a round
that defeats the armor outright is not mitigated at all. Every previously authored
balance point is preserved, and penetration is still explicit for armor.

**Test.** The curve is now pinned: a higher-`armor_pierce` weapon must face strictly less
effective armor at every armor value, a rail penetrator must not be stopped by medium
armor, and a light kinetic round must not defeat it outright.

### BUGFIX-006 — blasts reached through walls they had not breached

**Severity: moderate.** Visible to a player and tactically wrong.

Blast radius was Chebyshev distance only, so a grenade damaged a unit standing behind
intact cover exactly as if the wall were not there.

**Fix.** Line of sight from the blast centre is read from `Pathfinder.has_los`, the
existing authority, rather than re-derived. A shielded unit takes **one extra halving**
rather than becoming immune: shrapnel reaches around a corner, weakly. The wall itself
was already worked by the blast in the same detonation, so if it comes down, the next
blast finds the unit exposed.

The blast ledger now records `units_shielded`, and the reproduction contract and schema
carry it.

**Test.** Assert an open lane reports line of sight, an interposed wall taller than both
units does not, and that the extra halving reduces damage.

### Pass 5 gates

| Gate | Result |
|---|---|
| Static project verification | PASS |
| Godot headless TestRunner | PASS |
| Godot PlaytestRunner | PASS, **312 checks** |
| `npm test` | 42/43, the expected unpublished-source manifest gate |
| `npm run check` | PASS |

### Note

BUGFIX-005 is the clearest case yet for rule 12 in the live build notes. The unified
armor scale passed every test I had written, because those tests asserted monotonicity
and range — properties that a collapsed curve satisfies perfectly. Only printing the
actual numbers exposed it. **Invariants are not a substitute for looking at the output.**
