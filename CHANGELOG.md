# Changelog

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
