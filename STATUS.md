# Battle/Star.SOL status

## 2026-07-30 current state — read this section first

Everything below this section is retained history: the 2026-07-29 SOL recovery addendum and
the original 2026-07-28 `.02` record. They are accurate as records of their moment and are
**not** the current position.

**Working tree:** `C:\CLAUDE\7-30-2026-Claude\BattleStarSol`, at `e3b1685` — six commits on
published HEAD `7a8c04f`. Not pushed.

**Published:** `0.1.3-prealpha.1` at <https://rustycohl.github.io/BattleStarSol/>. The six
commits here are **not** in that release.

**Gates:**

| Gate | Result |
|---|---|
| `npm test` | **PASS**, 56/56 |
| Godot headless `TestRunner.gd` | **PASS** |
| Godot headless `PlaytestRunner.gd` | **PASS**, 312 checks |
| Web runtime matches source | **PASS** — re-exported, `MANIFEST.sha256` regenerated from it |

**What changed in this run:**

- **Loop 6 closed (M08-002).** The d10SRD rules are distributed into this repository at
  `vendor/d10srd/` under their own licence, with `PROVENANCE.json` recording upstream commit
  `c77005b20d74d25a426e6b7620e63d49b0778105` and a SHA-256 per file.
  `tests/d10srd-conformance.test.mjs` **executes** them against all six published conformance
  vectors. Previously the only check was a transcription of the rule numbers into a test,
  which asserts a copy against itself and cannot fail for the right reason. Diagnosed by the
  principal as an orphan — stripped scaffolding — not a documentation gap.
- **Conformance and balance separated (M08-001).** The SRD forbids deriving health, damage,
  movement, and action counts from d10 scaling. Seventeen authored balance numbers had been
  pinned under a "d10SRD Conformance" label, which would make a deliberate tuning change read
  as a rules violation. They now live in `_test_balance_baseline()`. Conformance vectors 1–4
  do not apply to this port (no check resolution exists here) and that claim is verified by
  absence: a forbidden check-resolution symbol appearing in `GameConfig` fails the build.
- **Standoff cover derived, not authored (M03-007).** The new Standoff sector injected a bare
  `{"type": COVER, "z": 3}` cell, bypassing `WorldBuilder.material_cell`. It behaved
  correctly — `Ballistics.density_of` falls back to the type's implied material — so no
  behavioural test could catch it. It cost ledger fidelity: `material_before` recorded `""`,
  and the reproduction schema types that field loosely enough to validate, so the artifact did
  not fail closed either. Now caught structurally by `_test_scene_cover_is_material()`.
- **Evidence promotion gated.** `.partial` runs are unpromoted by definition;
  `tests/evidence-hygiene.test.mjs` asserts none is tracked, that every promoted pack carries
  `SHA256SUMS`, and that no promoted pack contains `HARNESS-ERROR.json`.
- **An inherited red gate cleared.** `npm test` was failing before this run: five
  manifest-listed scripts had been edited without regenerating `game/MANIFEST.sha256`, and the
  committed Web runtime predated those edits. Re-exported first, then regenerated — the
  reverse order binds a stale runtime to new source and passes green.
- **Upstream work versioned.** The 98 uncommitted lines found in the leading-edge tree
  (ORACLE/DEALER payload ingestion, the Standoff sector, a d10 conformance test) are recorded
  verbatim in `60faf3c`, credited to their author, so the corrections can be reverted
  independently of the feature.

### Deliberate simplification: debris falls straight down

**This is a decision, not a defect.** When a wall loses a tier of material, that tier becomes
debris **on the cell it fell from**. Nothing is thrown outward, nothing topples into a
neighbouring cell, and nothing above a destroyed tier is displaced sideways.

It is acceptable because the part a player actually reads is intact: **boom means things fall**,
and the matter is accounted for. A six-high column yields exactly six tiers of debris — the
simulation is not lying about where material went, only about how far it scattered.

Classified **B-tier**: a known simplification a player will not be troubled by, as against
A-tier, which is anything that breaks the simulation's internal logic or the player's trust.

**It will be tackled later, for reasons beyond appearance.** Lateral displacement means writing
to cells the damage event did not target, which multiplies terrain events per blast — and the
reproduction ledger is already the binding constraint at roughly 18 worst-case grenades per
mission. Debris scatter and the ledger budget are the same piece of work.

**Open, and named:**

- This repository conforms to vendored d10SRD commit `c77005b`. If upstream publishes a rules
  change, `vendor/d10srd/PROVENANCE.json` carries the update procedure; the digest assertions
  make running it a visible act rather than an optional one.
- Terrain events can exhaust the reproduction ledger at roughly 18 worst-case grenades per
  mission, bounded by artifact bytes rather than event count. Full fidelity is retained and the
  artifact fails closed. Unchanged this run.
- The strategic layer is a working bridge, not yet a campaign.
- Destruction is modelled and visible: terrain takes damage, falls as debris, and leaves visual scorched rubble.
- The armor curve introduced in BUGFIX-005 (which scales armor proportionally instead of flat subtraction) is explicitly accepted as the intended mechanic.
- Promoted evidence packs under `evidence/playtests/` remain untracked.

**Evidence for this run:** `evidence/M08-001-D10SRD-CONFORMANCE-2026-07-30.md`,
`evidence/M08-002-D10SRD-VENDORED-2026-07-30.md`,
`evidence/M03-007-STANDOFF-COVER-DERIVED-2026-07-30.md`.

---

## 2026-07-29 SOL recovery addendum

This file retains the 2026-07-28 public and original `.02` record below. For
the current Git-free reconstruction at `C:\SOL\BattleStarSol-prealpha-02`, the
controlling source is [`MODULE-LEDGER.md`](MODULE-LEDGER.md).

Current bounded state:

- immutable recovery from archived commit `ce5038d`: PASS;
- static Godot verification and TestRunner: PASS;
- combined PlaytestRunner: PASS, 294 checks;
- M05-D HUD pointer affordance and profile persistence: PASS. Every surface has a
  slide grip and an opacity grip that follow it, including into its parked handle,
  and deliberate surface states persist in the Commander profile under schema
  `gzg.battlestar.hud/1.0`;
- M03-004 cover as material: PASS for its declared scope. Terrain generation now
  levels only the insertion footprint, so cover near a spawn is naturally
  occurring; cells carry material, density, and integrity; penetration and
  destruction derive cover strength, so a wall shot to rubble stops offering cover
  for player and AI alike; and the guided tutorial is seven steps with COVER
  between DEFENSE and ATTACK. Its stated limit — penetration not reaching combat
  resolution — is superseded by M03-005 below;
- M03-005 destruction in play: PASS. Penetration is called from combat resolution,
  so terrain breaks during a mission through one authority that also rebuilds the
  tile, records the change in the ledger, and releases units holding cover that no
  longer protects. `terrain_damaged` is carried in the reproduction contract, and a
  balance pass produced six penetration tiers across fourteen ranged weapons;
- M01 action routing, bounded Web observation, AP-zero recovery, and
  camera-synchronized coordinates: PASS;
- authoritative atomic browser pack
  `evidence/playtests/20260729T104417824Z-b0e26ed0`: PASS;
- guided Proving Ground: 7/7 since the cover step was added, SUCCESS, 3 survivors,
  seed `1167583760`;
- exact run identity: one deployment, one full extraction, 5 human actions,
  30 events, 10 screenshots, and 12 verified manifest artifacts;
- M03 deterministic cover/flank golden cases: PASS;
- M03-002 live positional rationale: PASS. The guided Proving Ground spawns
  AP-0 target dummies, so no seed of it could ever express cover or flank
  behavior; an ordinary armed A.T.L.A.S. coordinate deployment produced both
  canonical cover and flank rationale in the game's own ledger at round 2, with
  12/12 positional records complete;
- M03-003 Haili, the guided instructor: PASS. The Proving Ground now spawns one
  armed opposing-faction agent named Haili and two deterministic cover cells, so
  `Take Cover` is no longer permanently disabled, live cover faces went from 0 of
  9 samples to 9 of 9, and the guided ledger carries all five canonical cover and
  flank signatures. Guided completion held with the same outcome and seed. The
  hand-placed cover cells were superseded by M03-004, which made cover naturally
  occurring terrain instead.
  This closes the acceptance item M03-002 had to record PARTIAL. "Haili" is a
  casual personal name, distinct in fact from the property "H.A.I.L.I.";
- M04 bounded reproduction contract and clean strategic re-import: PASS for its
  declared supported portion; Godot mechanical re-simulation and cross-platform
  state equivalence remain later work;
- M05-A measured-rail overlap correction, focus source checks, and fresh
  1440x900 atomic loop: PASS;
- M05-B broader viewport, keyboard, reduced-motion, and contrast matrix: PASS
  for its declared scope across nine live cases. It released Tab from the help
  overlay so keyboard traversal works at all, added a keyboard entry point,
  made the status rail scroll so it stopped covering the tactical feed, and
  narrowed the claimed viewport support to canvases the HUD can actually serve
  (1172x659, 1112x626, 1038x584);
- M05-C adaptive HUD: PASS, and it supersedes that boundary. Every surface now has
  continuous transparency, a reversible slide that leaves a handle, and scrolling
  content; the layout adapts by parking the tactical feed and then the status rail
  rather than reporting a window it cannot serve. Every tested window from
  1920x1080 down to 768x1024 resolves. The actions and the tutorial callout are
  never auto-parked. Screen-reader behavior, wider browser coverage, OS text
  scaling, a pointer affordance, persistence, and animation remain open;
- full Node release suite: PASS, 43/43. The fail-closed source/runtime manifest
  check that had failed since the recovery began now passes, because M06-001
  regenerated the committed runtime and manifest together under owner approval;
- M06 local RC: PASS. The committed Web runtime was rebuilt from current source
  (240,848 to 291,532 bytes) and `game/MANIFEST.sha256` regenerated with it; the
  guided 7/7 loop and the 9-case accessibility matrix both pass against the
  committed runtime. Local preparation only: no Git, no publication, no version
  bump;
- `release.allow_apply`: remains false;
- committed public runtime and `game/MANIFEST.sha256`: regenerated locally by
  M06-001 under owner approval, and no longer the pre-M01 build;
- Git and the public Page: **published**. Release `0.1.2-prealpha.4` is live at
  <https://rustycohl.github.io/BattleStarSol/>, CI green on `25ecf4e`, and the served
  runtime hash matches the committed file. Two backup zips precede it and both are
  retained;
- M03-006 grenade, vertical cover, and armor penetration: PASS. A wall protects only
  while it stands between shooter and target; armor resolves on the same 0-100
  penetration scale as terrain; and the grenade is a thrown area blast that damages
  units and terrain, with a visible detonation and scorched rubble. Every squad
  member starts with one.

**Release:** `0.1.3-prealpha.1`
**Date:** 2026-07-30
**Channel:** public playable pre-alpha
**Page:** <https://rustycohl.github.io/BattleStarSol/>

## Separate `.02` work line

This checkout is the private `prealpha-02` development branch based exactly on
`55ecad27bf83c56225a33dc20a62a4d305f6bc89`. The release fields above describe
the unchanged public baseline, not a claim that `.02` has launched.

The `.02` contract, module status, and injection controls live in:

- [`docs/PREALPHA-02-RELEASE-CONTRACT.md`](docs/PREALPHA-02-RELEASE-CONTRACT.md)
- [`docs/PREALPHA-02-INJECTION-LEDGER.md`](docs/PREALPHA-02-INJECTION-LEDGER.md)
- [`prealpha-02-manifest.json`](prealpha-02-manifest.json)

Promotion is disabled while any required module is incomplete.

Current isolated-source progress:

- M00 isolation/release guard: complete;
- M01 guided Proving Ground: implemented and exported, live-browser evidence
  pending;
- M02 first-turn clarity/status truth: implemented with 204-check Godot
  coverage and a matching Web export; live-browser evidence pending; and
- M03–M06: not complete.

## Current claim

The repository now contains the real modular Godot game and a complete
strategic → tactical → extraction → local persistence path. The tactical Page
mounts the committed Godot 4.7.1 Web export; it does not substitute a browser
demo simulation.

## Verified locally

- static project verification: pass;
- Godot `TestRunner`: pass;
- Godot `PlaytestRunner`: 147/147 checks pass;
- release Web export: pass;
- Node bridge and release gate: 15/15 pass;
- local browser deployment, Godot T1→T2 faction cycle, F8 extraction, strategic
  return, persistence, and forced-reload idempotence: pass; and
- public Page smoke: recorded after deployment in
  [`docs/VALIDATION.md`](docs/VALIDATION.md).

Godot’s headless shutdown previously reported renderer/font RID cleanup warnings
and a Windows root-certificate-store warning. The test runners now properly `await` a frame before
exiting, giving the servers time to flush their resources and clean up cleanly.

## Implemented release surface

- browser-local Commander profile and bounded mission history;
- embedded generic A.T.L.A.S. snapshot with a no-peer quick-deploy path;
- standardized deployment input;
- deterministic 20×20 Godot tactical simulation with Base-10 AP;
- three factions and autonomous squad/enemy agents;
- cover, LOS, combat, armor, inventory, salvage, replay, and mobility systems;
- victory, defeat, and F8/HUD emergency extraction;
- standardized extraction output and idempotent strategic application; and
- complete static runtime committed for independent GitHub Pages hosting.

## Explicit pre-alpha limits

- no authenticated account or shared server-side campaign;
- no multiplayer authority;
- no persistent named soldiers or permadeath campaign;
- no complete guided tutorial, controller pass, production audio library, or
  production character-model set;
- advanced mobility remains partly developer-facing and AI does not use its
  complete grammar;
- local browser state can be cleared by the browser and is not a backup;
- A.T.L.A.S. external feeds remain optional/untrusted and the bundled texture
  provenance needs a later asset-replacement audit; and
- native interactive platform coverage remains narrower than the Web release
  path.

The current SOL module ledger is [`MODULE-LEDGER.md`](MODULE-LEDGER.md).
`game/docs/STATUS.md` retains the product-tree claim history and links back to
the recovery addendum. Superseded claims remain preserved in the archive and
historical docs.
