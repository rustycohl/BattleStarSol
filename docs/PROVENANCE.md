# Provenance and preservation

## Recovery basis

The active game was restored from the newest combined modular Godot candidate
in the preserved Ground Zero iterative corpus dated 2026-07-25. That candidate
already contained the Gemini-assisted modularization and the subsequent Grok
4.5 review notes supplied in the codebase. The recovery treated those notes as
review evidence, not as a replacement for source inspection or tests.

The product was then reconciled against:

- canonical design documents supplied for the alpha build;
- older Godot snapshots and notes in the iterative archive;
- the recovered Battle/Star.SOL, xCommander, and A.T.L.A.S. layers;
- the public generic A.T.L.A.S. release; and
- headless, package, and browser behavior.

Historical source is evidence. It is not silently deleted or declared current.

## Preservation anchors

- The public repository’s prior static launch Page is preserved under
  `archive/launch-surface-alpha.1`.
- Its starting public commit was `88be4f0`.
- The annotated tag `backup-2026-07-28-pre-game-restoration` marks the
  pre-restoration state.
- A verified offline bundle and working-tree archive were created before the
  restoration outside this repository.
- Generated editor/import caches and the supplied local Godot profile remain
  excluded; the release Web runtime is intentionally tracked.

## Architectural interpretation

The recovered three-layer structure remains:

1. **A.T.L.A.S.** — generic strategic browser substrate and selector;
2. **xCommand** — generic tactical simulation and extraction authority;
3. **Battle/Star.SOL** — themed deployment, campaign, economy, and fiction
   composition.

This repository ships a pinned local A.T.L.A.S. copy and xCommand runtime so it
stands alone. Their independent repositories are still separate galaxies.

## 2026-07-28 corrective integration

The integration:

- archived the static-only Page instead of overwriting its evidence;
- copied the modular candidate into an active, testable product tree;
- replaced the stale embedded A.T.L.A.S. snapshot with the current standalone
  release snapshot;
- normalized deployment and extraction through the shared galaxy envelope;
- added bounded/idempotent local campaign persistence;
- removed the browser tactical substitute from the active launcher;
- made the real Godot Web runtime the only mission resolver;
- corrected missing-audio, clean-import, release-export, and browser handoff
  defects;
- added engine-level F8 extraction for reliable egress and live validation;
  and
- rebuilt the release Web package from the corrected source.

The detailed earlier recovery ledger remains in `game/docs` and the preserved
historical corpus. It may contain superseded paths and 24-AP claims; live
source and the current status files control.

## Third-party and asset notes

- Godot engine output retains the upstream licenses embedded by Godot.
- The bundled Three.js build retains its upstream notice.
- `coi-serviceworker.js` identifies its MIT-licensed upstream origin; the
  current single-threaded export does not require it to provide gameplay.
- The embedded Material Icons font and globe texture set require a later
  source-by-source provenance/replacement audit before any production asset
  claim. They are carried forward for pre-alpha recovery and are explicitly
  not represented as original BattleStar art.

## Authorship and licenses

The recovery includes human-authored materials and AI-assisted modularization,
review, integration, and test work. Software in this repository is released
under MIT. Documentation and original design writing are published under CC BY
4.0. Third-party materials remain under their own terms. No software or
Creative Commons license grants trademark rights in the product names or marks.
