# Changelog

## Unreleased — 2026-07-30, second run

Six commits on `7a8c04f`. Not published; `0.1.3-prealpha.1` remains the live release.

### Added
- **The d10SRD rules are distributed with this product** at `vendor/d10srd/`, carried with
  `LICENSE-MIT`, `LICENSE-APACHE`, and `NOTICE-d10SRD`. `PROVENANCE.json` records the upstream
  repository, the exact commit, and a SHA-256 per file.
  `tests/d10srd-conformance.test.mjs` executes the real implementation against all six
  published conformance vectors. Loop 6 is closed. Previously the only check was a
  transcription of the rule numbers into a test, which asserts a copy against itself.
- ORACLE character and DEALER deck payload ingestion (`gzg.oracle.character/0.1`,
  `gzg.dealer.deck/0.1`), carried through the normalized deploy envelope.
- A Standoff sector: a launcher scenario for observing AI cover and flank behaviour.
- `_test_balance_baseline()`, holding authored balance numbers under an accurate label —
  the SRD forbids deriving health, damage, movement, or action counts from d10 scaling.
- `_test_scene_cover_is_material()`, a structural check that walks a live scene and rejects
  cover cells authored without material fields.
- `tests/evidence-hygiene.test.mjs`, gating evidence promotion: no `.partial` run may be
  tracked, every promoted pack carries `SHA256SUMS`, no promoted pack carries
  `HARNESS-ERROR.json`.

### Fixed
- The Standoff sector injected cover as a bare `{"type", "z"}` dict, bypassing
  `WorldBuilder.material_cell`. It behaved correctly, because `Ballistics.density_of` falls
  back to the type's implied material — which is why no behavioural test caught it. The cost
  was ledger fidelity: `material_before` recorded `""`, and the reproduction schema types
  that field loosely enough that it validated rather than failing closed.
- `npm test` was failing before this run. Five manifest-listed scripts had been edited
  without regenerating `game/MANIFEST.sha256`, and the committed Web runtime predated those
  edits. Re-exported the runtime first, then regenerated the manifest from it; the reverse
  order binds a stale runtime to new source and passes green.
- Two assertions of the form `a == x or b == y`, which passed when either half broke, split
  so neither axis can hide behind the other.

### Changed
- Conformance and balance are now separate concerns with separate tests. Seventeen authored
  numbers had been pinned under a "d10SRD Conformance" label, which would make a deliberate
  tuning change read as a rules violation.
- Conformance vectors 1–4 remain not applicable to this port — it implements no check
  resolution — but the claim is now verified by absence: a forbidden check-resolution symbol
  appearing in `GameConfig` fails the build, so the declaration cannot quietly become false.

### Known limit, unchanged
- Terrain events can exhaust the reproduction ledger at roughly 18 worst-case grenades per
  mission, bounded by artifact bytes rather than event count. Full fidelity is retained and
  the artifact fails closed.

## 0.1.3-prealpha.1 — 2026-07-30

Bugfix and balance pass. Six defects, each with a regression test verified to fail
against the old behaviour first.

### Fixed
- Destroying a unit's cover charged that unit an action point for someone else's shot,
  and silently failed at zero AP — leaving them flagged in cover, movement-locked,
  behind rubble, permanently.
- A blast damaged the same terrain once per unit it hit, so a grenade thrown into a
  crowd chewed through cover several times faster than the same grenade on one target.
- Every terrain rebuild leaked a tile node and left lookups resolving to the dying one,
  which meant the damaged-terrain appearance was never actually visible.
- Rebuilt tiles carried a pointless material override, duplicating a material per
  rebuild and defeating the distinction between damaged and pristine terrain.
- `armor_pierce` had stopped functioning: armor mapped onto terrain's density scale made
  a vest as tough as concrete, so every tier-1 kinetic round was fully mitigated and a
  pistol and a rifle became identical against every armor value. The authored
  subtraction is restored as the curve; penetration now adds only the outright-defeat
  case.
- Blasts reached through walls they had not breached. Line of sight from the blast centre
  now costs a shielded unit one extra halving rather than granting immunity, and the
  blast ledger records how many were shielded.

### Known limit, deliberately unchanged
- Terrain events can exhaust the reproduction ledger: about 18 worst-case grenades per
  mission, bounded by artifact bytes rather than event count. Full fidelity is retained
  and the artifact fails closed. Measured and analysed in
  `evidence/OBSERVATION-001-LEDGER-CAPACITY-2026-07-30.md`.

## 0.1.2-prealpha.4 — 2026-07-30

### Fixed
- HUD grip glyphs rendered as placeholder boxes on the live build: the bundled font
  has no arrow or half-circle glyphs. The slide and transparency grips now use ASCII.

## 0.1.2-prealpha.3 — 2026-07-30

### Fixed
- Continuous integration: the Windows browser-discovery test asserted a hardcoded
  Windows path while the resolver composes candidates with `path.join`, so it passed
  on Windows and failed on a Linux runner. It now approves the first candidate the
  resolver offers, asserting precedence rather than the host's path separator.
  The 0.1.2-prealpha.2 attempt at this fix did not apply and is superseded.
  No runtime change.

## 0.1.2-prealpha.1 — 2026-07-30

Recovered work line from the SOL reconstruction, published together.

### Added
- Destructible terrain: cells carry material, density, and integrity, and cover
  strength is derived from what is still standing.
- Penetration mechanics for weapons, terrain, and worn armor on one shared scale,
  derived from each weapon's own `armor_pierce` and `damage_type`.
- Vertical cover: a wall protects only while it stands between shooter and target.
- The grenade: a thrown object with an area blast that damages units and terrain,
  with visible detonation and scorched rubble. Every squad member starts with one.
- Haili, an armed instructor in the guided Proving Ground, and a seventh tutorial
  step that teaches Take Cover.
- Adaptive tactical HUD: per-surface transparency, slide-away with a handle, and
  scrolling content, with keyboard controls, pointer grips, and persistence in the
  Commander profile.

### Fixed
- Tab was bound to the help overlay, so no tactical control could ever take
  keyboard focus. Keyboard-only play now works.
- The tactical-feed rail covered the status rail's stance and cost lines at every
  viewport.
- The terrain generator flattened a four-deep pad at every spawn, erasing the cover
  faces beside every insertion point.

### Verified
- Static verification, Godot TestRunner, Godot PlaytestRunner at 294 checks,
  `npm test` at 43/43, and `npm run check`.
- Guided browser loop 7/7 and a nine-case accessibility matrix, both against the
  committed runtime.

### Known limits
- No multiplayer, no server-side campaign, no account.
- Terrain change is recorded in the ledger and supported by the reproduction
  contract, but no checked-in reproduction bundle exercises it yet.
- Penetration values are a first coherent ladder, not playtested.

## 0.1.1-prealpha.1 — 2026-07-28

### Restored

- Replaced the static-only launch surface with the actual modular Godot game.
- Preserved the previous Page under `archive/launch-surface-alpha.1`.
- Committed a fresh Godot 4.7.1 single-threaded release Web export.
- Embedded the current independently released generic A.T.L.A.S. snapshot as
  the galaxy’s local strategic fallback.

### Added

- Browser-local Commander profile, resources, deployment counter, mission
  history, and bounded extraction-id ledger.
- Versioned `battlestar.deploy` and `xcommand.extraction` galaxy messages.
- Idempotent extraction application and explicit legacy adapters.
- F8 engine-level emergency extraction for accessible, testable egress.
- Root release gate, local server, payload schemas, operating documentation,
  provenance, and validation record.
- GitHub Pages workflow publishing the complete `game/web` runtime.

### Corrected

- Missing audio assets now remain intentionally silent instead of creating
  unfilled generator streams.
- Clean test checkouts import the Godot project before the suites run.
- Web rebuilds now create their output directory and use release export.
- The launcher mounts the real tactical runtime and no longer presents a
  tactical browser substitute.
- Tactical results return first as standardized messages, preserve correlation,
  and reach both embedded and full-screen launch paths.
- Core deployment now navigates in the same tab, so popup suppression cannot
  accept a mission while hiding its tactical launcher.
- Atlas context and URL payloads are bounded, non-JSON/non-finite message values
  are rejected, and large replay recovery copies compact without losing the
  authoritative campaign summary.
- Same-tab extraction now applies the idempotent mission summary before the
  optional recovery-copy write, preventing storage quota from stranding egress.
- Pages verification and deployment actions now use their Node 24-compatible
  major releases, removing the deprecated Node 20 action warning.
- The canonical extraction example now uses the exact millisecond UTC timestamp
  shape required by the shared galaxy validator and emitted by the browser.

Historical implementation changes remain in
[`game/CHANGELOG.md`](game/CHANGELOG.md).
