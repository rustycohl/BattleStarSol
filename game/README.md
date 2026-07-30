# Battle/Star.SOL — modular pre-alpha source

This is the recovered, cleaned test candidate built from `battlestar-actual`, the
newer `xcommander-actual` extraction, the live A.T.L.A.S. file, and the design
record under `old/`.

The candidate keeps the proven three-part shape:

1. **A.T.L.A.S.** is the real browser strategic surface in
   `web/atlas/index.html`.
2. **xCommander** is the generic Godot tactical engine represented by the
   simulation and action scripts.
3. **Battle/Star.SOL** is the thin faction, extraction, economy, and narrative
   layer around those systems.

## What changed in this recovery

- The deployment seed now drives map generation, weapon scattering, AI jitter,
  evasion, salvage, and narrative through separate deterministic streams.
- `ActionRouter.gd` is the single UI/hotkey action entry point and the seam
  prepared for replay, scripted, and inference-driven agents. Scripted AI is
  not routed through it yet. The untested ENet branch is not active code.
- `Bootstrap.tscn` launches the strategic surface natively and the tactical
  scene in Web exports, so the Web preset no longer depends on a manual main
  scene swap.
- The Web package contains its own A.T.L.A.S. copy; its core style runtime,
  globe libraries, icon font, and textures now load from same-origin local
  paths under the server's required isolation headers.
- Deployment payloads are normalized and validated against an explicit 1.0
  contract.
- A.T.L.A.S. hash feeds can now render external entities and apply the current
  approximate detection-radius filter.
- Static verification and expanded Godot 4.7.1 headless tests are included.
- The first interactive regression pass restores the third faction, three-unit
  standard squads, 20x20-safe insertion pads, authoritative terrain height,
  bounded walking steps, targeted animated Jump, targetable Flight air cubes,
  discoverable loot markers, and a first camera-feel retune.
- The second interaction pass restores unit facing, exposes Flight layer and
  landing controls, keeps both click and button pickup paths, retires floating
  loot words, handles direct-file Web launches cleanly, and makes strategic
  deployment contextual to selected A.T.L.A.S. events or coordinates.
- The native A.T.L.A.S. button now starts or reuses the bundled HTTP server,
  eliminating the regressed `file://` handoff while preserving the tactical
  launcher as the working payload harness.
- The action economy uses a centralized Base-10 AP scale with distinct
  sprint/run/crouch/prone movement, elevation, equipment, weapon, jump, and
  flight costs plus path-cost previews.
- Routed player intents and resolved mechanical events are recorded in a
  JSON-safe replay bundle included with extraction results.
- Contextual movement now has a dedicated legality layer. A grounded,
  non-prone unit beside cover can target a cover face, pay AP to commit and
  brace, retain crouch/lean combinations, and pay AP to release movement.
- `ManeuverState.gd` replaces the shallow Jump/Wall Run/Wall Jump/Flip flags
  with a serializable phase contract. Actual Run/Sprint distance creates
  momentum; Jump reaches a persistent air anchor; a second paid Jump lands or
  revectors; preserved AP allows cross-turn suspension; zero AP causes a
  fall/prone recovery after the current action.
- Dev specials now expose targeted vertical Wall Run segments, contextual
  outward Wall Jump, airborne Flip-as-Dodge, Precision Jump, and the Cover
  Monkey stance. Cover Monkey adds +1 AP per movement step and slides out of
  and into threat-aware cover for free.
- Animated actions now publish a shared busy-to-ready transition, preventing
  movement and aerial animations from leaving the action bar grey until a
  God Mode toggle. Startup and off/on/off availability are regression-tested.
- Spending the last AP in a committed airborne maneuver now produces an
  explicit detachment result with physical fall, recorded drop/damage, and
  Prone recovery instead of a free or silent landing.
- Lean is available only from committed cover. Non-penetrating shots cannot
  cross the selected cover face; explicitly penetrating magnetic, rail, beam,
  and singularity weapons can.
- Visual voxels, rules cells, movement targets, airborne anchors, highlights,
  and pointer picking now share one canonical even-grid transform.
- Browser extraction returns to the live strategic opener or restores the
  saved A.T.L.A.S. hash in same-tab fallback mode.
- The tactical HUD separates persistent squad state from transient activity;
  its compact bottom action dock wraps and hides empty contextual groups, and
  the runtime exposes a fullscreen toggle.
- The `.02` status layer makes the current faction, active pilot, AP, core
  costs, End Turn phase sequence, and F8 extraction route persistent; F1/Tab
  opens the matching in-game help, and developer mobility stays outside the
  core dock until explicitly enabled.
- The `.02` Proving Ground uses accepted actions and resolved events to guide
  the real six-step tactical loop with nearby inert hostile targets for every
  player faction.

## Run it

Requirements: Godot 4.x with the Compatibility renderer. The source record
named Godot 4.7; use that version if available.

### One-click Web development build

Double-click **`PLAY WEB DEV.cmd`**. It first compares the Godot source with
the embedded browser package and rebuilds that package when source is newer.
It then starts or reuses the private local Web server, opens the strategic page
in the default browser, and serves the build with the required WebAssembly
headers. No Python, Node, installation, export-menu work, or manual address
entry is required. Keep its small server window open while testing; close it
to stop the server.

The default address is `http://127.0.0.1:8766/index.html`. If that port is
already occupied, the launcher automatically chooses one of the next nineteen
ports and opens the correct address.

### Godot editor and validation

1. Import `project.godot` into Godot.
2. Press F6 on `Main.tscn` for the tactical slice, or F5 for the native
   strategic launcher. From the native launcher, **Launch A.T.L.A.S.** now
   starts/reuses the same local HTTP route automatically.
3. Run
   `powershell -ExecutionPolicy Bypass -File tools/test.ps1 -GodotPath C:\path\to\Godot.exe`
   before stamping a build.

The Web shell can be served directly from `web/`. It includes a fresh,
single-threaded Godot 4.7.1 release Web export in `web/tactical/`. The active
launcher has no browser tactical substitute: mission results come from Godot.

## Honest alpha status

The tactical loop, payload vault, extraction, research UI, bug export, Atlas
shell, and procedural presentation are implemented source paths. Godot 4.7.1
imports every script, starts the tactical and strategic scenes headlessly, and
passes the included scene-level tests. The release WebAssembly build boots,
accepts player input, advances the allied/enemy turn cycle, and posts a
standardized extraction result to strategy. A full native interactive mission
smoke is still required.

These are not complete yet: authenticated account persistence, persistent
soldiers/permadeath, ghost retention rules,
hotseats/rank/shards, Discord flow, real multiplayer coordination, remote feed
polling, freeform/branching tutorial scripting, controller support, RL
adapters, and complete mobility semantics. See `docs/STATUS.md`.

## Project map

- `scripts/Main.gd` - tactical scene coordinator and action resolver
- `scripts/ActionRouter.gd` - unified action boundary
- `scripts/ActionEconomy.gd` - authoritative tactical AP catalogue and path costs
- `scripts/MovementContext.gd` - geometry/state-dependent movement options
- `scripts/ManeuverState.gd` - serialized airborne and surface-relative phases
- `scripts/WorldBuilder.gd` - pure seeded cells plus scene construction
- `scripts/PayloadContract.gd` / `scripts/PayloadBridge.gd` - data boundary
- `scripts/CombatSystem.gd`, `InventorySystem.gd`, `Pathfinder.gd`,
  `AIBehavior.gd` - extracted tactical systems
- `web/` - self-contained strategic/tactical browser shell
- `data/` - payload schema, examples, Atlas contract, and item database
- `tests/` / `tools/` - repeatability and packaging checks

The full archaeology, feature ledger, and roadmap are in the sibling
`alpha build docs` folder.
