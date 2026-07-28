# Validation record

## Release under test

- product: Battle/Star.SOL
- version: `0.1.1-prealpha.1`
- date: 2026-07-28
- Godot: `4.7.1.stable.official.a13da4feb`
- Web export: release, GL Compatibility, single-threaded

## Source and scene gates

The repository test wrapper performs a clean isolated project import, static
verification, `TestRunner`, and `PlaytestRunner`.

| Gate | Result |
| --- | --- |
| static project verification | pass |
| Godot script/resource import | pass |
| TestRunner | pass |
| PlaytestRunner | 147 checks pass in approximately 1.8 seconds |
| release Web export | pass |

Observed non-fatal shutdown diagnostics:

- dummy-renderer texture/font RID allocations reported at headless exit;
- Windows root certificate store read failure in isolated test/export profile;
- editor scan-abort and ObjectDB/resource cleanup warnings during forced
  headless shutdown.

These warnings are recorded, not reclassified as fixes. The test processes
exit `0`.

## Repository release gate

`npm test` covers:

- deterministic/versioned deployment construction;
- future-major rejection;
- non-JSON/non-finite rejection and URL/state boundary limits;
- standardized and legacy extraction normalization;
- idempotent resource/history application;
- large-replay compaction without loss of campaign summary authority;
- bounded profile storage and Unicode URL transport;
- presence and WebAssembly magic of the committed Godot release;
- GitHub’s per-file size constraint for the WebAssembly binary;
- real tactical mount and absence of the old demo substitute;
- bundled static A.T.L.A.S. fallback;
- Base-10 and F8 source invariants;
- Pages publishing the complete `game/web` tree;
- required contract/operating documents; and
- full SHA-256 agreement for the active Godot source and committed runtime.

`npm run check` parses the browser bridge and local server.

Result for this release: **15/15 Node tests pass; both syntax checks pass.**

## Browser loop

The release browser smoke must demonstrate:

1. strategic Page and embedded A.T.L.A.S. render;
2. quick deployment creates a standard `battlestar.deploy`;
3. the Godot Web canvas loads from the committed release files;
4. the tactical HUD exposes the 10-AP state;
5. an in-engine F8/HUD extraction emits `xcommand.extraction`;
6. the launcher receives and forwards that message;
7. strategy regains focus and records one mission; and
8. replaying the same extraction does not duplicate gains.

Local and public observations are appended below after the respective smoke.

### Local browser observation

The first pass rendered strategy and created a valid deployment, then exposed a
popup-policy defect: the named tactical popup was suppressed while the
strategic Page remained active. Core deployment was corrected to same-tab
navigation.

The corrective pass at `http://127.0.0.1:8781/` verified:

- the embedded A.T.L.A.S. globe rendered with 3/18 default layers;
- Quick Deploy navigated to the tactical launcher in the same tab;
- the real Godot Web canvas rendered the 20×20 battlefield, Commander, two
  agents, both hostile squads, tactical HUD, and 10/10 AP;
- F8 displayed `EMERGENCY EVAC INITIATED` inside the Godot canvas;
- strategy restored its saved A.T.L.A.S. hash and recorded one successful
  three-survivor mission;
- a forced Page reload kept the mission count at one and did not replay the
  result toast, confirming idempotent application;
- a second deployment accepted Space/End Turn, displayed allied-agent
  execution, resolved the hostile factions, and returned control at `T2` with
  the Commander restored to 10/10 AP; and
- a second in-engine F8 extraction returned to strategy and advanced the
  browser-local mission count to two.

This verifies the composed Web game loop, not merely the launcher shell.

After the JSON/storage boundary hardening, a final corrective smoke loaded the
embedded A.T.L.A.S. `0.1.0-alpha.2` snapshot, rendered a fresh Godot mission,
completed F8 extraction, advanced the existing local vault from three missions
to four, and retained four after a forced reload with no replayed result toast.

### Public GitHub Pages observation

Pending deployment.

## Claim discipline

This record does not claim authenticated accounts, remote campaign authority,
multiplayer, persistent soldiers, production assets/audio, or a complete
native-platform test matrix. See [`../STATUS.md`](../STATUS.md).
