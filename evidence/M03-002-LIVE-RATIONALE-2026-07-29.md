# M03-002 Live positional-rationale closure

## Scope

M03-001 closed the deterministic source gate with twelve golden checks and left
one item open: a live scenario whose ledger demonstrates a canonical cover or
flank rationale. This module closes it.

No production AI, scenario generation, or observation-surface behavior changed.
Date: 2026-07-29 / 2026-07-30 UTC evidence stamps.
Source boundary: `C:\SOL\BattleStarSol-prealpha-02`.
Committed runtime, `game/MANIFEST.sha256`, Git, the public Page, and
`release.allow_apply` are unchanged.

## Root cause of the open gate

The gate was never an AI defect or an unlucky seed. It was the scenario.

`SquadSpawner.spawn_into` branches on the sector. For `"Proving Ground"` it
spawns one player unit and two `Target Dummy` units with `ap = 0` and
`max_ap = 0`. An agent with no action points can never choose cover, a lean, a
flank, or anything else. **No seed of the Proving Ground can express M03
behavior**, so the eleven valid decisions M05-001 recorded were correct and the
absent cover signature was inevitable.

Every other sector takes the armed branch: three agents per rival faction, with
real AP and skills.

## Headless sweep

`game/tests/M03SeedSweep.gd` instantiates the real mission for the seeds the live
launcher can actually produce, plays free rounds, and reads the game's own
`agent_decision` ledger. It asserts nothing and changes nothing; it measures.

The launcher hashes `<sector>|<latitude>|<longitude>|<deployment_count>` with
FNV-1a. The sweep reproduces that hash and self-checks it against three known
launcher values, including the observed live Proving Ground seed `1167583760`
at deployment count 1. The self-check passes, so the swept seeds are reachable
seeds rather than invented ones.

Findings across eight armed-sector seeds:

| Measure | Result |
|---|---|
| Seeds probed | 8 |
| Armed hostiles per mission | 6 |
| Seeds producing canonical cover rationale | 8 of 8 |
| Seeds also producing `simple flank` | 4 of 8 |
| Round at which the rationale first appears | 2 or 3 |

A first-round probe found nothing, and that is correct: cover seeking requires a
hostile holding line of sight, and at spawn the forces are twenty cells apart, so
every agent properly chooses approach. The behavior is common once the forces
close — it simply cannot occur in a dummy scenario.

## Live closure

`tools/m03/standoff.mjs` deploys through the product's own path: one click on the
real A.T.L.A.S. globe to publish a coordinate selection, one press of the
product's deploy control, the real End Turn key for free rounds, and one F8
extraction. It selects nothing a player could not select.

| Fact | Value |
|---|---|
| Sector | `24.44°N, 90.00°E` (coordinate selection, not Proving Ground) |
| Mission seed | `167063568` |
| Hostile agents | 6 armed, 5 remaining at round 3 |
| Rounds played | 8 |
| Agent decisions recorded | 142 |
| Positional decisions | 12 |
| First positional round | 2 |
| Cover signatures observed | `protective cover now`, `cover route` |
| Flank signature observed | `simple flank` |
| Positional decision kinds | `seek_cover`, `take_cover`, `flank` |
| Outcome | SUCCESS, 3 survivors, 4 actions, 172 events |

Sample ledger records, exactly as the game wrote them:

```
r2 team2 flank score=93 ap=10 @(4,18,0) :: simple flank 1 AP; cover 2→2; exposure 1→0; retain 9 AP
r2 team2 flank score=91 ap=9  @(5,18,0) :: simple flank 4 AP; cover 2→0; exposure 0→1; retain 5 AP
r2 team2 flank score=92 ap=8  @(6,18,0) :: simple flank 2 AP; cover 2→0; exposure 2→2; retain 6 AP
r2 team2 flank score=90 ap=10 @(1,18,0) :: simple flank 4 AP; cover 2→2; exposure 2→0; retain 6 AP
```

Each record carries the decision, the acting position, AP before the choice, the
score, the round, and the exposure and cover transition the choice was made to
achieve. All twelve positional records are complete on those fields.

## Acceptance against M03-001's stated conditions

| Condition | Result |
|---|---|
| Seeded standoff includes armed ranged hostiles | PASS — 6 armed agents; the sweep confirms 8/8 seeds |
| At least one reachable cover option exists | PASS — the ledger records cover transitions such as `cover 2→2` with `exposure 2→0` |
| Evidence surface shows legal movement, cover faces, and attack targets from the same authority | PARTIAL — the extraction ledger supplies decision, position, AP, score, cover, and exposure from the game's own authority. The `cover_faces` observation block remains guided-mode only, by M01's deliberate bound. Widening it was rejected as out of scope for this module. |
| A golden test can distinguish hold, approach-cover, flank, and attack | PASS — closed by M03-001's twelve golden checks, unchanged here |

## Verification

| Gate | Result |
|---|---|
| Static project verification | PASS |
| Godot headless TestRunner | PASS |
| Godot PlaytestRunner | PASS, 261/261 |
| `npm run check` | PASS |
| Full Node release suite | 39/40; the single expected fail-closed source/runtime manifest mismatch |
| Headless seed sweep | 8/8 seeds expressive; seed-hash self-check PASS |
| Live M03 pack, 3 required gates | PASS |
| Visual review at round 6 | PASS; armed sector, hostile count, and real objectives visible |

## Authoritative live pack

`evidence/m03/20260730T004924241Z-89b82318`

| Fact | Value |
|---|---|
| Overall required-gate result | PASS |
| Screenshots | 8 |
| Served tactical PCK | 276,312 bytes |
| Served PCK SHA-256 | `5357e050000cf7d10f27017ac966eab55b12465ae8149247740698d35e949f37` |
| `SHA256SUMS` SHA-256 | `278cbdef23c424269765482df25e7c37feebc6f22877c5c3186cc26e08843606` |
| Browser | Chromium 150.0.4078.105 via `PW_CHROMIUM` (installed Edge) |
| Isolated site root | `.runtime\web-m05b\site` |

This pack proves a live positional-rationale scenario. It deliberately makes no
reproduction-bundle, mechanical-state-hash, or cross-platform equivalence claim.

## Source identities

| File | SHA-256 |
|---|---|
| `game/tests/M03SeedSweep.gd` | `298f0548ef9306da8aa727c544855c4198aa2de2be5d025861bdaadfddeb8f87` |
| `tools/m03/standoff.mjs` | `bf22fc2eed89e465fb20f1764d794c3b11c07983d4d575a14a7d6e758aa25ecf` |

Both files are additive. No existing production script was modified by this
module.

## Still open

- The guided Proving Ground remains unable to express positional AI, by design.
  If the tutorial should teach cover, it needs an armed instructor agent — a
  design decision, not a defect.
- `cover_faces` and the other observation blocks remain guided-mode only.
- Mechanical state hashes and native/Web equivalence remain Phase 3 work.
- M06 local release-candidate preparation remains owner-gated.
