# Battle/Star.SOL status

**Release:** `0.1.1-prealpha.1`
**Date:** 2026-07-28
**Channel:** public playable pre-alpha
**Page:** <https://rustycohl.github.io/BattleStarSol/>

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

Godot’s headless shutdown currently reports renderer/font RID cleanup warnings
and a Windows root-certificate-store warning. The suites exit successfully;
the warnings are tracked and are not represented as fixed.

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

The controlling detailed implementation ledger is
[`game/docs/STATUS.md`](game/docs/STATUS.md). Superseded claims remain preserved
in the archive and historical docs.
