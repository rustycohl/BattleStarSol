# Battle/Star.SOL

**Playable pre-alpha `0.1.2-prealpha.4`**

[Play the current Web build](https://rustycohl.github.io/BattleStarSol/)

> **Work-line notice:** this checkout is the isolated pre-alpha `.02`
> playtest-preparation codebase. The link above remains the known-good public
> `0.1.1-prealpha.1` build. `.02` is not released and cannot be promoted until
> every item in
> [`docs/PREALPHA-02-RELEASE-CONTRACT.md`](docs/PREALPHA-02-RELEASE-CONTRACT.md)
> passes.

This repository contains the game: a browser-local strategic command surface,
an embedded A.T.L.A.S. target selector, and a real Godot 4.7.1 tactical
runtime. A deployment enters the Base-10 action-point simulation; a victory,
defeat, or emergency extraction returns a versioned result to the local
campaign vault.

The former static launch Page is preserved unchanged under
[`archive/launch-surface-alpha.1`](archive/launch-surface-alpha.1/README.md).
It is history and fallback evidence, not the current product.

## Start playing

1. Open the Page and optionally change the Commander callsign.
2. Select **Quick Deploy: Proving Ground**, or choose a deployable A.T.L.A.S.
   event/coordinate and use the contextual deploy button.
3. Wait for the Godot tactical canvas to load.
4. Select the Commander, spend the 10-point AP pool, and end turns to resolve
   the two squad agents and both hostile factions.
5. Use **EXTRACT** in the tactical HUD or press **F8**. The real engine emits
   the extraction; the strategic Page records it exactly once.

The callsign, resources, deployment count, extraction IDs, and last 50 mission
summaries are stored only in this browser. That is a local pre-alpha vault, not
an authenticated account or remote authority.

## What is implemented

- deterministic 20×20 tactical maps driven by the deployment seed;
- three factions with three-unit squads: one Commander and two autonomous
  agents on the player side;
- Base-10 AP movement, stances, cover, LOS, typed combat, armor, inventory,
  salvage, flight, jump, wall, and developer mobility paths;
- utility AI, multi-faction turn resolution, victory/defeat/EVAC, and replay
  records;
- embedded standalone A.T.L.A.S. snapshot plus contextual and quick deployment;
- committed single-threaded Godot Web release files, not a JavaScript tactical
  mock;
- `battlestar.deploy` input and `xcommand.extraction` output in the shared
  `gzg.galaxy-message/1.0` envelope;
- bounded, idempotent local campaign persistence; and
- source, contract, browser-bridge, release-package, and headless game tests.

See [STATUS.md](STATUS.md) for the live claim list and
[docs/CONTROLS.md](docs/CONTROLS.md) for the tactical controls.

## Galaxy boundary

BattleStarSol follows the Ground Zero Games rule:

> one repository = one Page = one galaxy

This Page includes everything required for its core play loop. It does not
download mutable runtime code from another Ground Zero repository. Its pinned
A.T.L.A.S. copy is a local fallback; the independent generic A.T.L.A.S. Page
remains available at <https://rustycohl.github.io/ATLAS/>.

Peer galaxies integrate through copied, versioned data contracts—not hidden
shared state. Read [docs/GALAXY.md](docs/GALAXY.md) and
[docs/IO.md](docs/IO.md).

## Run and verify locally

Node 22 or newer serves the exact Page tree:

```text
npm start
```

Then open <http://127.0.0.1:8781/>. Run the repository release gate with:

```text
npm test
npm run check
```

The authoritative Godot test wrapper is:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\game\tools\test.ps1 -GodotPath C:\path\to\Godot_v4.7.1-stable_win64_console.exe
```

To rebuild the committed tactical Web runtime after a Godot source change:

```powershell
$env:BSS_GODOT_PATH = 'C:\path\to\Godot_v4.7.1-stable_win64_console.exe'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\game\tools\rebuild-web.ps1 -Force
```

## Repository map

- `game/` — authoritative Godot source and complete Page runtime
- `game/web/` — exact tree deployed by GitHub Pages
- `contracts/` — pinned outer envelope and BattleStar/xCommand payload schemas
- `docs/` — operating contract, controls, provenance, and validation evidence
- `tests/` — browser-bridge and release-integrity checks
- `prealpha-02-manifest.json` — machine-checkable module and promotion state
- `tools/promote-prealpha-02.ps1` — dry-run-first guarded injection path
- `archive/` — preserved superseded surfaces

The deeper recovered implementation notes remain in
[`game/docs`](game/docs/STATUS.md). Historical 24-AP documents are provenance;
live code is Base-10.

## License

Software is MIT licensed. Repository documentation and original design writing
are published under Creative Commons Attribution 4.0. Third-party components
retain their own notices. Names and marks are not licensed as trademarks.
See [LICENSE](LICENSE), [NOTICE](NOTICE), and
[docs/PROVENANCE.md](docs/PROVENANCE.md).
