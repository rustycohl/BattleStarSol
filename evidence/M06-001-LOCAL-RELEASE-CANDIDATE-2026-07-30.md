# M06-001 Local release candidate

## Authority

Principal approval, 2026-07-30. Every module from M00 onward deliberately left the
committed runtime and `game/MANIFEST.sha256` untouched, because M05-001 recorded:

> Regenerate runtime and manifest together only inside an owner-approved M06 local
> release-candidate loop.

This is that loop. It is **local preparation only**: no Git operation, no
publication, no change to the public Page, and `release.allow_apply` remains
`false`.

## What changed

Two artifacts, regenerated together as the record requires.

### The committed Web runtime

Rebuilt from the current source into `game/web/tactical/`.

| | Before | After |
|---|---|---|
| Bytes | 240,848 | 291,532 |
| SHA-256 | `dc13bc47041556602c8e39fb1cb3605254c60e8497ca0e54e30a6ecfcfd96b21` | `01413a8c59015e6cf31b3174479f22faaea7950134203a1a1690dbc1407664e4` |

The previous runtime predated the entire SOL recovery: it was the 225-check build
from before M01. It now carries M01 through M05 and the material cover model.

### The release manifest

`game/tools/update-manifest.ps1` enumerates tracked files with `git ls-files`, and
this checkout is deliberately Git-free, so the manifest was regenerated directly
from its own entry list — every previously listed path, rehashed — plus the five
new game source files that belong under the directories it already tracks:

- `scripts/Ballistics.gd`
- `scripts/HudLayout.gd`
- `tests/A11yMatrix.gd`
- `tests/BallisticsTable.gd`
- `tests/M03SeedSweep.gd`

129 entries became 134. Editor-generated `.uid` files remain untracked, as before.

`game/MANIFEST.sha256` SHA-256:
`ddc6449babc3881d63725ed3276dd9a5f38b7527f651087fef8f31504b71fc71`

## The gate this closes

The Node release suite has reported 39/40, then 41/42, then 42/43 since the SOL
recovery began, with one deliberate failure: *the game source and committed runtime
match the release manifest*. It was fail-closed on purpose, guarding exactly this
boundary.

**It now passes. The full suite is 43/43 for the first time in this work line.**

## Verification

| Gate | Result |
|---|---|
| Static project verification | PASS |
| Godot headless TestRunner | PASS |
| Godot PlaytestRunner | PASS, 294 checks |
| `npm run check` | PASS |
| Full Node release suite | **PASS, 43/43** |
| Manifest self-check | every one of 134 entries matches its file |
| Live guided playtest on the committed runtime | PASS, 7/7, SUCCESS, 3 survivors, seed `1167583760` |
| Live accessibility matrix on the committed runtime | PASS, 9 cases, 7 gates |

Both live runs served `game/web` — the committed runtime itself, not an isolated
export. The served package identity in each pack matches the committed
`index.pck` byte-for-byte.

An earlier attempt at this validation silently served a stale isolated export
because the previous development server still held port 8781. It was caught by
comparing the served package hash against the committed one, which is why the
harness records that identity before launching.

## Authoritative packs

| Pack | Purpose |
|---|---|
| `evidence/playtests/20260730T051839524Z-bfb7a88f` | Guided 7/7 loop on the committed runtime |
| `evidence/a11y/20260730T052031602Z-a748ef15` | Accessibility matrix on the committed runtime |

RC playtest `SHA256SUMS` SHA-256:
`5aa60dd76c6f79966ad642d068bf5eb493fff9be9e51971c01ced0f06b681e76`

## What this is not

- **Not a publication.** No Git command was run, nothing was pushed, and the public
  Page still serves the previous build.
- **Not a promotion.** `release.allow_apply` remains `false`, and
  `tools/promote-prealpha-02.ps1` was not run; it targets another repository and
  requires Git.
- **Not a version bump.** `package.json` remains `0.1.1-prealpha.1`. Naming the
  release is an owner decision.
- **Not a claim of platform coverage.** One Chromium build, Windows only, as in
  M05.

## Rollback

The prior runtime is recoverable by re-exporting from the archived `ce5038d`
source, whose archive SHA-256 is recorded in `M00-RECOVERY-2026-07-29.md`. The
previous manifest is reconstructable the same way. Nothing outside
`C:\SOL\BattleStarSol-prealpha-02` was touched.

## Still open

- Publishing, and the version name the release carries.
- Terrain change is carried in the reproduction contract but the checked-in M04
  artifact predates it, so no reproduction bundle exercises a terrain event yet.
- Godot mechanical re-simulation and native/Web state equivalence, unchanged.
