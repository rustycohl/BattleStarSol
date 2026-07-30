# Changelog

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
