## [Unreleased]

### Added
- **Commander-only pilot model:** human controls the first squad unit (Commander); the other two are squad bots on utility AI.
- **Remotes (God Mode special):** jack into a squad agent to pilot them; Remotes Home / re-select Commander returns control. Specials stay behind the developer God Mode toggle.
- End Turn runs autonomous ally bots before enemy factions.
- **Tactical core modules:** `PilotControl`, `TurnDirector`, `SquadSpawner`, `MissionResolver` extract authority from Main; see `docs/TACTICAL_CORE.md`.

### Fixed (2026-07-25 loop / logic pass)
- AI turn no longer unlocks player input between enemy actions.
- AI bow fire payload type mismatch crash fixed.
- Active-faction-only action authority; combat acceptance prechecks.
- Fall/move deaths resolve mission end; kill/select UI safety.
- Throw ranges, equip inventory gate, GameState turn sync.
- See `docs/BUGFIX_PASS_2026-07-25.md`.

### Added
- **Armor System**: Units now spawn with base armor values (EFD: 8, Timecorps: 6, Metropoli: 4).
- **Damage Types & Armor Piercing**: Configured in items.json. Kinetic damage ablates armor, Thermal burns it, and Rail pierces it cleanly.
- **Explicit Cover**: Differentiated HALF_COVER (z=1) and FULL_COVER (z>=2). Crouching behind half-cover grants full-cover bonuses.
- **Contextual Mobility Grammar**: Fully documented in docs/TRIPLE_A_FRAMEWORK.md.
- **UI Enhancements**:
  - Floating health labels now show [A: X] for armor.
  - Weapon tooltips correctly read items.json and display Damage Type & APierce values.

### Changed
- **Base-10 AP Economy**: Migrated all constants and items.json costs to the Base-10 system.
- CombatSystem.gd heavily rewritten to factor in typed damage, armor degradation, and variable cover reductions.
- Main.gd _in_cover routine updated to return integers representing cover quality instead of booleans.
- Egress pathways hardened: StratLayer strictly uses call_deferred to restore subpanels upon returning from tactical. Web build correctly skips StratLayer injection on match end to rely on postMessage.

# Changelog

## 0.1.0-refactor - 2026-07-24

### Recovered

- Selected the newest combined tactical source and newest browser Atlas.
- Preserved the three-part Atlas / xCommander / Battle-Star architecture.
- Retained the tactical loop, inventory, combat, research, payload vault,
  extraction, proving ground, and bug export source paths.
- Preserved and normalized the recovered Take Cover, Double Jump, and
  Wall Run/Wall Jump/Flip sketches as primary contextual-mobility evidence.
- Recorded Godot plus addressable voxel topology as a movement-system
  requirement: cells, faces, edges, air volumes, materials, and local surface
  frames are rules data rather than decorative geometry.

### Corrected

- Made deployment seed, generator version, and rules version explicit.
- Replaced uncontrolled mechanical randomness with named seeded streams.
- Added a pure deterministic cell generator and headless tests.
- Expanded headless tests to instantiate both tactical and strategic scenes and
  route a real tactical action.
- Added `Bootstrap.tscn` for correct native/Web startup.
- Made the Web package self-contained by path.
- Added payload normalization, validation, schema, and examples.
- Fixed Atlas external entity ingestion and latitude/longitude zero handling.
- Corrected UI shortcut labels and safer browser message encoding/origins.
- Stopped treating extraction results as deployable missions.
- Removed runtime navigation-mesh baking and made the deterministic grid
  pathfinder the sole movement authority.
- Corrected the PowerShell test wrapper so a successful static check cannot
  bypass the Godot suite.
- Generated a fresh Godot 4.7.1 single-threaded debug Web build.
- Made the tactical launcher preserve the game’s 16:9 aspect ratio and added a
  full-screen tactical launch control.

- Restored the native launcher’s automatic HTTP handoff; it now starts or
  reuses the bundled loopback Web server instead of opening `file://`.
- Added a centralized 24-AP action economy with distinct stance/movement costs,
  elevation and flight costs, migrated weapon costs, equipment costs, and
  movement-path previews.
- Added deterministic routed-action and resolved-event records and included
  their JSON-safe replay bundle in extraction results.
- Added regression coverage for the native HTTP route, AP catalogue, action
  records, and replay serialization.
- Bundled the core A.T.L.A.S. Tailwind/Three/OrbitControls runtime, icon font,
  and globe textures so the isolated development server no longer produces an
  unstyled page when outside CDNs are blocked.
- Added contextual Take Cover: geometry-gated targeting, paid entry and exit,
  automatic brace, facing, movement commitment, serialization, event records,
  contextual UI, and headless regression coverage.
- Added `MovementContext.gd` as the foundation for chained movement legality
  instead of continuing to treat the mobility catalogue as unrelated toggles.
- Added serializable `ManeuverState.gd`, per-turn Run/Sprint distance and
  lifetime Sprint distance, persistent paid Jump anchors, paid second-stage
  landing/revector, Precision Jump momentum bypass, cross-turn suspension when
  AP is preserved, and zero-AP detachment/fall/prone recovery.
- Replaced the Wall Run/Wall Jump/Flip AP placeholders with a tested initial
  chain: selected vertical wall face, recorded surface frame, paid traversal,
  outward Wall Jump into the shared air state, and animated airborne
  Flip-as-Dodge.
- Made Lean contextual to committed cover and made cover physically obstruct
  outgoing fire unless the unit leans or the equipped item explicitly
  penetrates cover.
- Added the dev-special Cover Monkey stance: +1 AP per movement segment, free
  movement-triggered exit, and free threat-aware automatic cover entry.
- Deferred creation of the vendored A.T.L.A.S. style runtime until
  `DOMContentLoaded`, guaranteeing its `MutationObserver` receives a real
  document node in embedded, direct-file, and isolated browser contexts.
- Repaired copied `file://` A.T.L.A.S. snapshots: browser-blocked WebGL
  textures now produce a visible procedural Earth, a single limited-mode
  notice, and a hash-preserving link to the local HTTP build instead of a
  black globe.
- Centralized the animated-action busy-to-ready UI transition so movement,
  Jump, Flight, Wall Run, Wall Jump, Flip, and future asynchronous actions
  cannot leave the ordinary action bar locked until an unrelated God Mode
  toggle forces a refresh.
- Added a final tactical-startup readiness publication and regression coverage
  proving that the initial, post-animation, and God Mode off/on/off ordinary
  action states agree.
- Promoted zero-AP airborne detachment to an explicit player-facing result:
  the hint and deterministic event now report its cause, drop, damage, and
  Prone recovery.
- Unified visual tiles, units, highlights, air anchors, and pointer picking
  under one even-grid coordinate transform, removing the half-cell Jump-target
  offset.
- Added a four-round, three-faction lifecycle regression for deferred turn
  handoff.
- Corrected Web extraction ownership: browser deployments now return to and
  restore the saved A.T.L.A.S. state instead of loading covert ingress inside
  the tactical iframe.
- Split persistent squad status from the transient tactical feed, compacted
  and centered the bottom action dock with responsive group wrapping and empty
  contextual-group collapse, and added an in-runtime fullscreen control.
- Made `PLAY WEB DEV.cmd` rebuild the embedded Godot package automatically
  when project source is newer, using the supplied console executable and
  isolated templates before starting or reusing the local server.

### Removed from active runtime

- Unverified ENet/server-authoritative singleton and peer ownership.
- Stale generated Godot Web binaries.
- Native Godot Atlas approximation.

These are preserved in the sibling `battlestar.orphans` archive where useful.

### Verification

- Static source/package verification: passed.
- Browser strategic shell, demo result cycle, and external feed smoke: passed.
- Godot 4.7.1 script import: passed.
- Godot deterministic and scene-level headless suite: passed.
- Tactical, strategic, and bootstrap scene startup: passed.
- Fresh Godot 4.7.1 Web export: passed.
- WebAssembly startup and deployment loading: passed.
- Browser Sprint action and complete enemy-turn cycle: passed.
- Godot extraction result handoff to the launcher: passed.
- Native Web server startup, MIME/header contract, and instance reuse: passed.
- Contextual strategic crisis to HTTP tactical payload route: passed.
- Self-contained A.T.L.A.S. layout/globe under isolated HTTP headers: passed.
- Contextual Take Cover state, AP, serialization, and movement lock: passed.
- Contextual cover fire, cover penetration, Cover Monkey, persistent Jump,
  Wall Run, Wall Jump, and airborne Flip headless regression suite: passed.
- Initial action readiness, busy-to-ready recovery, God Mode state
  equivalence, and zero-AP airborne detachment evidence: passed.
- Rebuilt tactical WebAssembly runtime and styled A.T.L.A.S. browser startup:
  passed.
- Visual voxel/highlight transform alignment and four-round deferred turn
  cycle: passed.
- Direct-file A.T.L.A.S. snapshot procedural fallback: passed.
- Full native interactive mission smoke: pending.
