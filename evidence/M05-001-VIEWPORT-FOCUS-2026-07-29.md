# M05-001 Viewport and Keyboard-Focus Closure

## Scope

This increment corrects the tactical HUD overlap visible in the reconstructed
Web build and adds a visible keyboard-focus treatment to the core tactical
controls. It does not claim full accessibility certification or a complete
device-and-browser matrix.

## Source result

- `TacticalUI.gd` measures the actual left and right rail widths before placing
  the tutorial panel and action dock.
- The tutorial panel and action dock remain clear of the rails when the
  viewport changes.
- Deterministic layout checks cover the observed 1112-pixel tactical viewport
  and a narrower 768-pixel case.
- Core actions, weapon controls, roster controls, camera/help controls, End
  Turn, and Extract accept Tab focus and receive a visible cyan outline.

## Verification

| Gate | Result |
|---|---|
| Static project verification | PASS |
| Godot headless TestRunner | PASS |
| Godot PlaytestRunner | PASS, 261/261 |
| Full Node suite | 39/40; expected fail-closed source/runtime manifest mismatch |
| Deterministic 1112-pixel layout checks | PASS |
| Deterministic 768-pixel layout checks | PASS |
| Keyboard-focus assertions | PASS |
| Fresh isolated Web export | PASS |
| Atomic browser loop at 1440 x 900 | PASS |
| Observed tactical canvas | 1112 x 626 |
| Guided tutorial | PASS, 6/6 |
| Runtime/full loop/idempotence/extraction/base-10 AP | PASS |

The live screenshot `screenshots/02-tactical-booted.png` was visually reviewed:
the upper tutorial panel clears the left rail and the lower action dock sits
below it without obscuring the tactical feed. The browser run used installed
Edge through explicit `PW_CHROMIUM` because standalone Chrome launch returned
Windows `EACCES`.

## Source identities

| File | SHA-256 |
|---|---|
| `game/scripts/TacticalUI.gd` | `91b2c2672b16c47b9c116c7f51c95283cca20d04c90451cda4f4fb1eeb927569` |
| `game/tests/TestRunner.gd` | `9373e7d5b07af17bde658b1a6d0c1ec6b6cb265fa7692c54e89d61fbb8d20af3` |

## Authoritative live pack

`evidence/playtests/20260729T105741264Z-6aedeca9`

| Fact | Result |
|---|---|
| Overall required-gate result | PASS |
| Deployment/extraction | Exactly 1 / exactly 1 |
| Seed | `1167583760` |
| Outcome | SUCCESS, 3 survivors |
| Replay | 5 accepted human actions, 30 events |
| Screenshots | 10 |
| Manifest artifacts | 12 |
| Served PCK | 263,972 bytes |
| Served PCK SHA-256 | `ad091f07ed11ecfc56800bb8f0c1668eb72c44698878e8587359bfe7f257b835` |
| Report SHA-256 | `f1d2d12412a8d60a8b0ebed0581a77d1fd79ada6ad08e2c1ce8f1594f029fa39` |
| Extraction SHA-256 | `ad385c33c8d43014b18eee76aebcb7e8b96c5b890f7ef6eb0024303419cbfc20` |
| `SHA256SUMS` SHA-256 | `90e776e5ff417133402fcae923cc275561a8654f36c01a25d2213b637d7f253f` |

M03 canonical cover/flank rationale was informational in this scenario and was
not observed. Eleven ordinary AI decisions were recorded; a purpose-built
standoff scenario remains the live M03 evidence gate.

## Remaining M05 gate

Before release-candidate promotion, run the broader supported viewport,
browser, keyboard-only, focus-order, reduced-motion, and contrast matrix. This
increment proves the source correction, deterministic narrow-width behavior,
and one complete live desktop loop; it is not the broader matrix.

The full Node suite intentionally remains 39/40 because the unchanged
`game/MANIFEST.sha256` describes the older committed runtime and rejects the
new `TestRunner.gd` identity. Regenerate runtime and manifest together only
inside an owner-approved M06 local release-candidate loop.
