# M07-001 Public release 0.1.2-prealpha.1

## Authority

Principal instruction, 2026-07-30:

> go ahead and push to public (from here on out I intend to personally test from the
> public endpoints - alpha is LIVE already by definition, and we keep it that) so I
> can begin playtesting while you start the next phase

Procedure followed: [`09-GIT-AND-BACKUP.md`](../../WORLD-ENGINE-V1/.agents/09-GIT-AND-BACKUP.md),
written before any Git operation was performed.

## Backup taken first

| Fact | Value |
|---|---|
| Path | `C:\SOL\backups\BattleStarSol-prealpha-02-20260730T0555Z-pre-push.zip` |
| Files | 561 |
| Bytes | 75,645,844 |
| SHA-256 | `16a37374d01d18af5ae8a9da6174ed9e904b647347d333c1dcc4c5248586e07f` |

Excludes `node_modules`, `.godot`, and `.runtime` — all reproducible, and their bulk
would hide the parts that are not. Nothing was deleted to make room.

## How the push was made

The reconstruction is deliberately Git-free, so the remote was **cloned** and the
tree copied into it. Nothing was initialised over a live remote and no history was
rewritten — the rule that protects prior work.

Base: `55ecad27` (`fix: align extraction fixture timestamp contract`), which is
exactly the commit the `.02` reconstruction was archived from.

Published: `e7800dc`, tagged `v0.1.2-prealpha.1`, following the repository's existing
`v<version>` tag convention rather than a new scheme. `v0.1.1-prealpha.1` remains the
rollback handle.

106 files changed. The evidence tree was **not** published wholesale; only the three
fixture paths the test suite actually reads were included, plus the evidence records
themselves. The reproduction fixtures are required or the suite cannot verify itself.

## A defect caught before publishing, not after

`.gitattributes` declares `* text=auto eol=lf`. Twelve working-tree files carried
CRLF, so the release manifest described bytes that CI would never check out: the
source/runtime manifest gate would have passed locally and **failed in CI**.

The working tree was normalised to LF, the runtime re-exported, the manifest
regenerated, and every gate re-run. The manifest was then verified a second time
*inside the clone*, which is the only check that reflects what CI sees.

This is exactly what step 3 of the push procedure exists to catch.

## Verification before the push

| Gate | Result |
|---|---|
| Static project verification | PASS |
| Godot headless TestRunner | PASS |
| Godot PlaytestRunner | PASS, 294 checks |
| `npm run check` | PASS |
| Full Node release suite (working tree) | PASS, 43/43 |
| Full Node release suite (inside the clone, no `node_modules`, as CI runs it) | PASS, 43/43 |
| Manifest verified inside the clone | 134 of 134 entries match |
| Guided browser loop against the committed runtime | PASS, 7/7, SUCCESS, seed `1167583760` |
| Accessibility matrix against the committed runtime | PASS, 9 cases, 7 gates |
| Served package identity | 297,500 bytes matching the committed `index.pck` |

## Version handling

`0.1.1-prealpha.1` to `0.1.2-prealpha.1`, applied to `package.json`,
`package-lock.json`, `README.md`, and the `STATUS.md` release block, with a
`CHANGELOG.md` entry recording what was added, fixed, verified, and left open.

`tests/release.test.mjs` had pinned the release claim to the literal
`0.1.1-prealpha.1` — and correctly failed the bump. Rather than update the literal,
the test now derives the expected version from `package.json`, so the release claim
and the released artifact cannot drift apart at the next bump.

## What a playtester will notice

- Every squad member starts with a grenade. Throwing it breaks cover, and broken
  cover looks broken.
- Cover can be shot through by heavier weapons, and shot away by anything given
  enough time.
- High ground now denies the target their cover as well as granting a damage bonus.
- The tutorial is seven steps and teaches Take Cover, with Haili demonstrating it.
- The HUD can be faded, slid away, and scrolled, by key (F2/F3/F4) or by the grips;
  the arrangement persists.

## Still open

- `release.allow_apply` remains `false`. This publishes the product repository; it
  does not promote through `promote-prealpha-02.ps1`.
- Playtest findings will be the next input. Nothing here substitutes for a human
  playing it.
- The limits recorded in `M03-005` and `M03-006` are unchanged by publishing.
