# Battle/Star.SOL `.02` Module Ledger

## M00 — Immutable recovery

- Status: PASS
- Authority: World Engine v4 and 2026-07-29 gate audit
- Input: clean archived commit `ce5038df7cba69ab695c04f31d09ef4fbef46f57`
- Output: writable, Git-free reconstruction tree in `C:\SOL`
- Acceptance:
  - archive identity and SHA-256 recorded;
  - exactly 170 archived files before recovery records;
  - Node tests pass 17/17;
  - package check passes;
  - no reference source modified.
- Non-goals:
  - no M01 reconstruction yet;
  - no Git operation beyond read-only archive creation;
  - no repository publication.

### Evidence

- Archive SHA-256: `9a86c46f55adb3e4f52b381573b9feb417ac5ccd2c98d6047ee13e9cb6c65360`
- Extracted tracked-source count before recovery records: 170
- Git metadata copied: no
- `npm.cmd test`: PASS, 17/17
- `npm.cmd run check`: PASS
- Static project verification: PASS
- Godot headless TestRunner: PASS
- Godot PlaytestRunner: PASS, 225 checks
- Godot: 4.7.1 stable, official build `a13da4feb`
- Isolated Godot profile: `C:\SOL\BattleStarSol-prealpha-02\.runtime\godot-profile`
- Import shutdown emitted resource/ObjectDB warnings; the test runners returned success. Treat the warnings as a harness-cleanliness observation, not as a failed mechanics gate.

### Closure

The recovered source is the expected clean 225-check baseline. It does not
contain the later compiled M01 observation-surface work. M01 source
reconstruction is therefore required before any 239-check or 6/6 claim can be
re-earned.

## M01 - Action routing and Web observation reconstruction

- Status: PASS; SOURCE PARITY AND ATOMIC LIVE 6/6 RE-EARNED
- Authority: preserved M01 design log, accepted 239-check report schema, and
  reconstructed-source tests
- Input: M00's clean 225-check source baseline
- Output:
  - both human selection paths cross `ActionRouter`;
  - guided-mode Web observation is read-only, bounded, and simulation-derived;
  - observation target order and Chebyshev radius match the accepted compiled
    behavior;
  - missing actor/camera/projection silently suppresses publication;
  - no JavaScript input or second gameplay authority was introduced.
- Acceptance earned:
  - static project verification: PASS;
  - Godot headless TestRunner: PASS;
  - Godot PlaytestRunner: PASS, 239 checks;
  - historical M01-001 progression: 225 to 228 checks reconstructed;
  - historical M01-003 progression: 228 to 239 checks reconstructed.
- Subsequent closure:
  - the fresh six-step Web run passed in the atomic evidence pack
    `20260729T104417824Z-b0e26ed0`;
  - exactly one deployment correlated to one full extraction;
  - the replay contains 5 accepted human actions, 30 events, all six tutorial
    steps, and a completion event;
  - runtime, full loop, idempotence, full extraction, and base-10 AP gates pass;
  - M01-004 and M01-005 subsequently closed in their own modules.
- Still open:
  - the committed Web runtime and `game/MANIFEST.sha256` still represent the
    older 225-check build and must not be relabeled as this source;
  - local RC promotion remains a later M06 gate.

### Evidence

- `evidence/M01-RECONSTRUCTION-2026-07-29.md`
- `game/scripts/Main.gd` SHA-256:
  `8e8d373ac34dd14c44039a395ab87f7e9360cc0346bb318ee5933e8bf6084e26`
- `game/scripts/TacticalUI.gd` SHA-256:
  `8d7bf5e71e59a74c74cb29acac30541cd42fbdde9bfba74d95b491822e8f1913`
- `game/tests/PlaytestRunner.gd` SHA-256:
  `e08b5f1d5bef90c6ee9da7c067492d7705c3629d3bd25f37a2af8d3389e2b673`

## M01-004 - AP-zero tutorial recovery

- Status: PASS
- Input: M01's reconstructed 239-check source
- Output:
  - DEFENSE guidance distinguishes affordable Brace from an exhausted AP pool;
  - exhausted guidance explicitly directs the player to End Turn;
  - End Turn and the returning player-turn event retain the DEFENSE checkpoint;
  - refreshed AP republishes affordable guidance;
  - an accepted Brace advances to ATTACK through the existing action boundary.
- Acceptance:
  - static project verification: PASS;
  - Godot headless TestRunner: PASS;
  - Godot PlaytestRunner: PASS, 247 checks;
  - eight new recovery checks pass.

### Evidence

- `evidence/M01-004-AP-RECOVERY-2026-07-29.md`

## M01-005 - Camera-synchronized observation coordinates

- Status: PASS
- Finding: screen coordinates published only on UI/tutorial changes became
  stale during the camera's 0.35-second focus tween.
- Output:
  - Web-only view refresh is throttled to 10 Hz;
  - a camera/viewport signature prevents observation rebuilding while the view
    is static;
  - changed view signatures republish the same authoritative targets with
    current screen coordinates;
  - normal UI and tutorial changes still publish immediately.
- Acceptance:
  - static project verification: PASS;
  - Godot headless TestRunner: PASS;
  - Godot PlaytestRunner: PASS, 261 checks;
  - camera and viewport signature checks: PASS, 2/2;
  - isolated Web export: PASS;
  - in-app browser aimed move and aimed melee: PASS using refreshed
    observation coordinates.

### Evidence

- `evidence/M01-005-VIEW-SYNC-2026-07-29.md`

## M03-001 - Deterministic cover/flank golden cases

- Status: HEADLESS PASS; LIVE LEDGER OBSERVATION PENDING
- Output: 12 test-first golden checks around the existing AI implementation;
  no production AI code changed.
- Acceptance:
  - seed `1167583760` creates an armed ranged Agent at legal standoff;
  - protective cover beats legal fire and approach;
  - exact route, score 79, and attack-AP reserve are deterministic;
  - an identical seed replays the same decision and route;
  - committed cover selects `lean_cover` at score 96;
  - unusable committed cover selects `leave_cover`;
  - a central blocker selects a flank that opens LOS and retains attack AP;
  - integrated `AIBehavior` emits canonical cover-route and simple-flank
    rationale signatures.
- Verification:
  - M03 closure: PASS, 259 checks;
  - current combined source: PASS, 261 checks.

### Evidence

- `evidence/M03-001-GOLDEN-AI-2026-07-29.md`

## M07-001 - Public release 0.1.2-prealpha.4

- Status: PUBLISHED and live
- Authority: principal instruction, 2026-07-30 — push to public so playtesting can
  begin from the public endpoints. Procedure: `.agents/09-GIT-AND-BACKUP.md`, written
  before any Git operation.
- Backups taken first, both retained:
  - `BattleStarSol-prealpha-02-20260730T0555Z-pre-push.zip`, 561 files, 75,645,844
    bytes, SHA-256 `16a37374d01d18af5ae8a9da6174ed9e904b647347d333c1dcc4c5248586e07f`;
  - `BattleStarSol-prealpha-02-20260730T0625Z-release-0.1.2-prealpha.4.zip`, 578
    files, 78,814,486 bytes, SHA-256
    `30d2c46fae7d3f9c97ce670837f99fd8b802fc13a7724f7074abe6b658e0e93e`.
- Method: the reconstruction is Git-free, so the remote was cloned and the tree
  copied in. No history was rewritten and nothing was initialised over a live remote.
- Base `55ecad27` to published `25ecf4e`, tags `v0.1.2-prealpha.1` through
  `v0.1.2-prealpha.4`, following the repository's existing `v<version>` convention.
- Defect caught before publishing: `.gitattributes` declares `eol=lf` and twelve
  working files carried CRLF, so the manifest described bytes CI would never check
  out. Normalised, re-exported, regenerated, and re-verified inside the clone.
- Defects caught after publishing, by CI and by smoke-testing the public endpoint:
  - a browser-discovery test asserted a hardcoded Windows path while the resolver
    composes with `path.join`, so it passed on Windows and failed on Linux. The
    first fix attempt did not apply and shipped as `prealpha.2`; `prealpha.3`
    corrected it by asserting precedence instead of separators;
  - the HUD grips used glyphs the bundled font lacks and rendered as placeholder
    boxes. `prealpha.4` uses ASCII.
- Live verification: CI green on `25ecf4e`; the public Page serves 297,500 bytes with
  SHA-256 `3a05a870...`, matching the committed runtime; a public-endpoint smoke test
  booted Godot, reported tutorial 1/7, showed the grenade in the dock, and moved
  keyboard focus to Brace on the first Tab, with zero page errors.
- `release.allow_apply` remains `false`. This publishes the product repository; it
  does not promote through `promote-prealpha-02.ps1`.

### Evidence

- `evidence/M07-001-PUBLIC-RELEASE-2026-07-30.md`
- `evidence/M03-006-BLAST-VERTICAL-ARMOR-2026-07-30.md`

## M06-001 - Local release candidate

- Status: PASS. Local preparation only — no Git, no publication,
  `release.allow_apply` remains `false`
- Authority: principal approval, 2026-07-30, of the owner-gated M06 loop every
  earlier module deliberately avoided
- Output:
  - the committed Web runtime rebuilt from current source: 240,848 bytes
    (`dc13bc47…`) to 291,532 bytes (`01413a8c59015e6cf31b3174479f22faaea7950134203a1a1690dbc1407664e4`).
    The previous runtime was the pre-M01 225-check build;
  - `game/MANIFEST.sha256` regenerated from its own entry list, since
    `update-manifest.ps1` needs Git and this checkout is deliberately Git-free;
    129 entries became 134 with the five new game source files added
    (`ddc6449babc3881d63725ed3276dd9a5f38b7527f651087fef8f31504b71fc71`).
- Gate closed: the fail-closed source/runtime manifest check that has failed since
  the SOL recovery began now passes. **The full Node suite is 43/43 for the first
  time in this work line.**
- Acceptance earned: static PASS; TestRunner PASS; PlaytestRunner 294; `npm run
  check` PASS; Node suite 43/43; all 134 manifest entries verified; live guided 7/7
  and the 9-case accessibility matrix both run against the committed runtime with
  the served package identity matching it byte-for-byte.
- Not done: no publication, no promotion, no version bump. `package.json` stays
  `0.1.1-prealpha.1`; naming the release is an owner decision.

### Evidence

- `evidence/M06-001-LOCAL-RELEASE-CANDIDATE-2026-07-30.md`
- RC playtest: `evidence/playtests/20260730T051839524Z-bfb7a88f`
- RC matrix: `evidence/a11y/20260730T052031602Z-a748ef15`

## M03-005 - Destruction in play, in the ledger, and calibrated

- Status: PASS
- Authority: principal decision, 2026-07-30 — penetration in combat resolution,
  terrain change in the ledger and reproduction contract, and a balance pass
- Output:
  - `CombatSystem.apply_damage` resolves the firing-lane cell, resolves penetration
    from the weapon's own fields, scales cover reduction by what the material took,
    and applies the damage;
  - `Main.damage_terrain` is the single authority: it changes the cell, rebuilds the
    affected tile, appends to the mission's ordered terrain record, records a
    `terrain_damaged` event, and releases any unit committed to cover that no longer
    protects;
  - `terrain_damaged` carried in the reproduction contract on the same terms as
    `unit_killed` — bounded grid cell, acting unit, material transition — with
    everything else failing closed;
  - `tests/BallisticsTable.gd` emits the weapon-versus-cover table used for the
    balance pass.
- Correction to an earlier claim in this ledger: the M04 contract excludes
  A.T.L.A.S. real-world coordinates, browser and profile surfaces, and direct
  names. It already carried bounded grid positions, so terrain damage follows that
  existing rule rather than a new one.
- Calibration faults found and fixed: an `armor_pierce x 9` scale left plasma at 59
  against a 60-density wall, decided by one unauthored point — the scale is now
  base-10, matching the action economy; and equal penetration "passed through"
  delivering nothing, so the material now wins ties.
- Result: six penetration tiers across fourteen ranged weapons; ten are stopped by
  some cover, and the four that penetrate everything are exactly those authored as
  `penetrates_cover`.
- Model correction found by the live test: rubble kept residual integrity, so open
  ground could still be damaged. Rubble now carries no density.
- Acceptance earned: static PASS; TestRunner PASS; PlaytestRunner 294, up from 282;
  Node suite 43/43; live guided 7/7.
- Still open: no visual destruction beyond the tile rebuild; the checked-in M04
  artifact predates terrain events so no bundle exercises one yet; penetration does
  not interact with unit armour; vertical cover is not modelled; the ladder is
  coherent but not playtested.

### Evidence

- `evidence/M03-005-DESTRUCTION-IN-PLAY-2026-07-30.md`
- `game/scripts/Ballistics.gd` SHA-256:
  `b28c8adb0eb1ac764aa9dbf0773b0d4cc3f969cf3bd143a6b5937fffc067ef89`
- `game/scripts/CombatSystem.gd` SHA-256:
  `86870266fceb3d2a6c3ee7aa84aa436d001bbba317db78928f76500246cf4fc2`

## M03-004 - Cover as material, and the cover instruction step

- Status: PASS for its declared scope; penetration is wired into cover derivation,
  not yet into combat resolution
- Authority: principal decisions of 2026-07-30 — add a cover instruction step;
  cover is naturally occurring from the environment; destructible environments and
  penetration mechanics inform how cover is generated; and build from what already
  exists, recorded as a standing principle in
  `C:\SOL\WORLD-ENGINE-V1\.agents\07-SYSTEMS-FROM-SYSTEMS.md`
- Superseded: M03-003's hand-placed tutorial cover cells are removed. The lane had
  cover because a function said so; now it has cover because the world makes cover.
- Output:
  - terrain generation levels only the insertion footprint plus one step off, so
    cover near a spawn is naturally occurring; the historical four-deep pad rule is
    retained in source for reference;
  - cells carry `material`, `density`, and `integrity`, derived from cover class
    and column height — a field that already existed and nothing consumed;
  - `scripts/Ballistics.gd`: penetration on the same 0-100 scale as density, fire
    that stops or passes through at reduced power, degradation through hard cover
    to soft cover to rubble to open ground, cover strength derived from material,
    and protection judged against a specific shooter's best penetration;
  - `AITactics.cover_level` and `MovementContext.cover_faces_at` derive from
    material, so destruction changes tactics for player and AI through one
    authority;
  - guided tutorial is seven steps, COVER between DEFENSE and ATTACK, skipped when
    no cover is adjacent and never a dead end.
- Backward compatibility: cells authored before materials carry no density, so
  their type supplies the material they implied. The twelve M03-001 golden checks
  pass untouched.
- Acceptance earned: static PASS; TestRunner PASS; PlaytestRunner 282; `npm run
  check` PASS; Node suite 42 tests with the single expected manifest failure; live
  guided run 7/7 SUCCESS at seed `1167583760`.
- Honest limit: the live run correctly *skipped* the cover step because the
  harness's move ends beside a hostile rather than beside cover. Both branches are
  proven deterministically.
- Still open: penetration is not yet called from `CombatSystem`, so terrain does
  not break during a mission; no visual destruction; terrain change is not in the
  extraction ledger or reproduction contract; penetration values are uncalibrated.

### Evidence

- `evidence/M03-004-COVER-AS-MATERIAL-2026-07-30.md`
- `game/scripts/Ballistics.gd` SHA-256:
  `a0a48b055a9afdf8393c1f9ff86f1aa6252453de5f3f115d7e7d6930a236946b`
- `game/scripts/WorldBuilder.gd` SHA-256:
  `078ad35ffce06fc896867e87aaadce78fdc507103d5d8f5629275e5dd003c070`

## M05-D - HUD pointer affordance and persistence

- Status: PASS
- Authority: principal decision, 2026-07-30 — the two open M05-C items, in order
- Output:
  - a `HudGrips` overlay giving every surface a slide grip and an opacity grip,
    placed against the surface's real rectangle each layout pass, with a parked
    surface's slide grip moving into the handle that stays on screen;
  - grips are pointer affordances only and stay out of the keyboard traversal that
    F2/F3/F4 covers;
  - a bounded `hud` field in the Commander profile, schema
    `gzg.battlestar.hud/1.0`, with `readHudPreferences` / `writeHudPreferences` as
    the narrow pair the runtime calls;
  - only deliberate player intent is stored; automatic adaptation never is.
- Defects found and corrected: the tactical runtime runs inside the launcher's
  iframe, so `window.BSS_BRIDGE` is absent from its own window and the first
  implementation silently wrote nothing — it now resolves the host bridge the way
  `PayloadBridge` already does; and HUD changes did not republish the observation,
  so a live run could not see them.
- Acceptance earned: static PASS; TestRunner PASS; PlaytestRunner 282; Node suite
  42 tests with the single expected manifest failure; live round-trip in which a
  faded rail and a parked feed were stored in the profile and reapplied on a fresh
  deployment.
- Still open: no slide animation; grips park and restore but do not drag;
  preferences are per-browser-profile.

### Evidence

- `evidence/M05-004-HUD-AFFORDANCE-PERSISTENCE-2026-07-30.md`
- `game/web/bridge.js` SHA-256:
  `c0055123bcdebfd957cf11760c57674a5893df78692e76901933390c320c9199`

## M05-C - Adaptive HUD

- Status: PASS; the M05-B support boundary is superseded by adaptation
- Authority: principal decision, 2026-07-29 — every HUD element should have
  variable transparency, be able to scroll or slide out of the way, and otherwise
  be adaptive
- Output:
  - four adaptive surfaces (status rail, tactical feed, tutorial callout, action
    dock), each with continuous `0.15`-`1.0` transparency, a reversible slide that
    leaves an 18-pixel handle, and scrolling content;
  - `HudLayout.adaptive_metrics`, which takes player intent and returns the
    arrangement that fits, parking the feed first and then the status rail;
  - the action dock and tutorial callout are never auto-parked;
  - F2 selects a surface, F3 cycles transparency, F4 slides it, each announced in
    the hint line; Tab stays reserved for focus traversal;
  - bounded `auto_parked` and `surface_opacity` in the Web observation surface.
- Correctness rules recorded in the evidence: player intent is the only input, so
  adaptation cannot compound; rail extents are measured from the authored gutter
  plus the surface's own width, never its slid position; park offsets derive from
  those same measurements in the same pass.
- Defect introduced and corrected during the module: wrapping the dock in a
  `ScrollContainer` stripped its intrinsic height, collapsing it to a 16-pixel
  sliver, which handed the layout a false measurement and broke keyboard traversal
  at three viewports. The scroll container now holds the authored dock height.
- Result: every tested window resolves. 1280x800, 1024x768, and 768x1024 —
  previously declared unsupported — now adapt by parking the feed, and the two
  smallest also park the status rail.
- Acceptance earned: static PASS; TestRunner PASS; PlaytestRunner PASS at 282
  checks; `npm run check` PASS; Node suite 39/40 unchanged; live matrix PASS on 9
  cases and 7 gates; guided autonomous playtest PASS at 6/6 with the same outcome
  and seed; visual review at 1024x768.
- Still open: transparency and slide are keyboard-only with no pointer affordance;
  no persistence across missions; no animation; two handles stack in a narrow
  column at the smallest canvases.

### Evidence

- `evidence/M05-003-ADAPTIVE-HUD-2026-07-30.md`
- Pack: `evidence/a11y/20260730T030311004Z-ad232028`
- `game/scripts/HudLayout.gd` SHA-256:
  `3a7589dd34a15b5adeb0c6e85a9f0b120d98e853be64c694ffebad66c523a2d7`
- `game/scripts/TacticalUI.gd` SHA-256:
  `9f3a86823e288ec496b25891317d51cf11f8423ed626f8261717f4c0e8c9207b`

## M03-002 - Live positional rationale

- Status: PASS for the required gates; one acceptance item PARTIAL by M01's
  deliberate bound
- Input: M03-001's headless golden gate and its open live observation
- Root cause of the open gate: `SquadSpawner.spawn_into` gives the Proving
  Ground two `Target Dummy` units with `ap = 0` and `max_ap = 0`. No seed of the
  guided scenario can express cover, lean, or flank behavior, so the eleven
  valid decisions recorded in M05-001 were correct and the absent signature was
  inevitable. Every other sector spawns three armed agents per rival faction.
- Output:
  - `game/tests/M03SeedSweep.gd`, a measuring sweep that reproduces the
    launcher's FNV-1a seed hash, self-checks it against known launcher values,
    plays real rounds, and reads the game's own decision ledger;
  - `tools/m03/standoff.mjs`, a live harness that deploys through the real
    A.T.L.A.S. coordinate path, plays free rounds with the real End Turn key,
    extracts once, and reads the canonical rationale from the ledger.
  - Both are additive. No production script was modified.
- Acceptance earned:
  - headless sweep: 8 of 8 armed-sector seeds produce canonical cover rationale,
    4 of 8 also produce `simple flank`, first appearing at round 2 or 3;
  - seed-hash self-check: PASS, including the observed live Proving Ground seed
    `1167583760` at deployment count 1;
  - live pack: PASS on all three required gates — armed scenario reached through
    the ordinary deployment path, canonical rationale present in the live
    ledger, and 12 of 12 positional records complete on decision, position, AP,
    and score;
  - static verification, TestRunner, PlaytestRunner 261/261, `npm run check`,
    and the 39/40 Node suite unchanged;
  - visual review at round 6.
- Live mission: sector `24.44°N, 90.00°E`, seed `167063568`, 6 armed hostiles,
  142 decisions, 12 positional, SUCCESS with 3 survivors.
- Boundary:
  - the `cover_faces` observation block remains guided-mode only by M01's
    design; widening it was rejected as out of scope, so that acceptance item is
    recorded PARTIAL rather than claimed;
  - no reproduction-bundle, mechanical-state-hash, or cross-platform
    equivalence claim.

### Evidence

- `evidence/M03-002-LIVE-RATIONALE-2026-07-29.md`
- Live pack: `evidence/m03/20260730T004924241Z-89b82318`
- `SHA256SUMS` SHA-256:
  `278cbdef23c424269765482df25e7c37feebc6f22877c5c3186cc26e08843606`
- `game/tests/M03SeedSweep.gd` SHA-256:
  `298f0548ef9306da8aa727c544855c4198aa2de2be5d025861bdaadfddeb8f87`
- `tools/m03/standoff.mjs` SHA-256:
  `bf22fc2eed89e465fb20f1764d794c3b11c07983d4d575a14a7d6e758aa25ecf`

## M03-003 - Haili, the guided instructor

- Status: PASS; M03-001 acceptance now complete
- Authority: principal decision, 2026-07-29 — the guided Proving Ground gets an
  armed instructor agent named Haili
- Naming: "Haili" is a casual personal name, distinct in fact from the franchise
  property "H.A.I.L.I." though lineage exists. Do not merge the registry entries
  and do not expand this character's name into the acronym.
- Output, confined to the Proving Ground:
  - Haili spawns as one opposing-faction agent at a deterministic instruction
    post five cells along the training lane, armed, with a full Base-10 pool; the
    two target dummies stay at `ap = 0`;
  - the training lane gains two deterministic cover cells, one orthogonally
    adjacent to the Commander's start, because cover options are read from the
    faces adjacent to the actor;
  - cover is injected before the tiles are built so meshes and simulation agree.
- No AI, action-economy, rules, or observation-bound change.
- Result:
  - `Take Cover` was permanently disabled in the tutorial and is now enabled;
  - live cover faces went from 0 of 9 samples to 9 of 9;
  - the guided ledger now carries all five canonical signatures, including
    `lean from committed cover` and `cover has no legal attack lane`;
  - guided completion stays 6/6, SUCCESS, 3 survivors, seed `1167583760`.
- Acceptance closed: M03-002's PARTIAL item — movement, cover faces, and attack
  targets from the same authority — is now PASS in the guided scenario.
- Verification: static PASS; TestRunner PASS; PlaytestRunner PASS at 282 checks,
  up from 261; `npm run check` PASS; Node suite 39/40 unchanged; guided
  autonomous playtest PASS; guided M03 harness PASS on five gates; the M05-B
  accessibility matrix re-validated PASS on this build; visual review of guided
  round 1.
- Still open: cover is demonstrated but not yet taught in the step text; Haili
  has no dialogue or characterisation; whether she may kill the Commander during
  the tutorial is unresolved.

### Evidence

- `evidence/M03-003-HAILI-INSTRUCTOR-2026-07-30.md`
- Guided pack: `evidence/m03/20260730T023322942Z-0a32872d`
- Matrix re-validation: `evidence/a11y/20260730T023640349Z-eb10ba7a`
- `game/scripts/SquadSpawner.gd` SHA-256:
  `4e91f22a1db1dd683b88945a621cb3ed0a3ef06aa69ce114e87f4f7eb68ab359`
- `game/scripts/WorldBuilder.gd` SHA-256:
  `cb438f24e3d6b4700609e30bcf14ce01a9c3af5d92c4dd0b2dbcc5027cd11bd4`

## M04-A - Atomic playtest evidence foundation

- Status: PASS
- Input: the historical mixed-run evidence defect
- Output:
  - exclusive `<run-id>.partial` workspaces;
  - verified identity chain for deployment, extraction, report, seed, and time;
  - SHA-256 and byte-count records for evidence artifacts;
  - sorted digest manifest and atomic final-directory promotion;
  - canonical port `8781` probe and fail-closed browser resolution.
- Acceptance:
  - focused Node tests: PASS, 11/11;
  - package syntax gate: PASS;
  - exact `playwright-core@1.61.1`;
  - state-based six-step browser driver: PASS;
  - served PCK identity recorded before launch;
  - exactly one deployment and one full extraction;
  - authoritative pack result: PASS;
  - runtime, full loop, idempotence, full extraction, base-10 AP, and M01 6/6:
    PASS;
  - 12 pack artifacts independently verified against `SHA256SUMS`;
  - ordinary failed game gates finalize as valid negative evidence;
  - harness/identity failures remain partial;
  - tampering blocks finalization or invalidates a finalized pack.
- Closure:
  - M04-B consumes the authoritative PASS pack through a strict, complete-file
    import boundary and reproduces the declared strategic result.

### Evidence

- `evidence/M04-ATOMIC-EVIDENCE-FOUNDATION-2026-07-29.md`
- `tools/playtest/evidence-pack.mjs` SHA-256:
  `44891d2dd588c9ca43942bf7225a353cf7bc5321586e4891c61a9e9d6bb86d7a`
- `tests/playtest-evidence.test.mjs` SHA-256:
  `eb7c6f05ace6069e0b10ec911bd7bc2c316b254b137ca6115e9d8b8abf4201d6`
- `tools/playtest/run.mjs` SHA-256:
  `b21113672a3c786c726a383fbddbd034a33cbccf017c5d96829d8a38dc7b5faf`
- Authoritative pack:
  `evidence/playtests/20260729T104417824Z-b0e26ed0`
- Report SHA-256:
  `b6127f9101390c8614bd1ad0dd1dd476c00e8bc28b6bf2b894eb0cbcad810c02`
- Extraction SHA-256:
  `d9a6569908c1534f50dfe04a410ddc4aef7fb6f04d5f5569fc390a7c15c5ccc5`
- `SHA256SUMS` SHA-256:
  `a6b37fba1333c907e2904c12a1efe2cf2593bfaeb091d6f3de57e36bb1a753ff`
- Served tactical PCK:
  261,268 bytes,
  `e5e312c0676f156ebd28ff564c40d6254104ab9808eb29127dd1c940aa00c5ca`

## M04-B - Bounded reproduction and clean strategic re-import

- Status: PASS FOR DECLARED SUPPORTED PORTION
- Input:
  `evidence/playtests/20260729T104417824Z-b0e26ed0`
- Output:
  - strict `gzg.battlestar.repro/1.0` JSON Schema;
  - privacy-bounded, pseudonymized deployment/action/event/result projection;
  - canonical deep-key JSON serialization;
  - separate artifact-integrity and deterministic mechanical-scope digests;
  - complete-file evidence import that rejects unmanifested content and
    symlinks/junctions;
  - clean strategic extraction import and duplicate-idempotence report.
- Acceptance:
  - authoritative source must be a finalized PASS pack;
  - all twelve source artifacts match `SHA256SUMS`;
  - five actions and thirty events retain one contiguous ordered ledger;
  - actor/squad names, map coordinates, A.T.L.A.S. return state, browser
    storage/profile data, console, screenshots, URLs, and paths are excluded;
  - unknown/sensitive fields, non-finite values, oversized ledgers, tampering,
    extra files, and symbolic links fail closed;
  - deterministic regeneration matches the checked-in artifact;
  - clean import reproduces `SUCCESS`, seed `1167583760`, three survivors,
    neural `25`, capital `301`, alloys `0`, and empty loot;
  - clean strategic resources change from `50/25000/100` to
    `75/25301/100`;
  - first import changes state; duplicate import does not; mission count
    remains one;
  - focused M04-B tests: PASS, 12/12;
  - bridge + atomic evidence + M04-B tests: PASS, 32/32;
  - standalone verify/import and syntax gates: PASS.
- Equivalence boundary:
  - supported: deployment/identity validation, ordered ledger integrity,
    declared result, strategic delta, and duplicate idempotence;
  - not claimed: Godot mechanical re-simulation, an authoritative
    initial/final mechanical state hash, or native/Web cross-platform state
    equivalence.

### Evidence

- `evidence/M04-001-REPRO-REIMPORT-2026-07-29.md`
- Artifact:
  `evidence/reproductions/20260729T104417824Z-b0e26ed0/battlestar-repro.json`
- Artifact digest:
  `05fc6100c000088e02d11396edf79f183f152c22f3f4523b2f56408ab914a628`
- Mechanical-scope digest:
  `d830f0e8944e6614cd2e630b7a70a8756f5023dbe0e9fbf9ca4bb5f4e218f0f2`
- Artifact file SHA-256:
  `e895bfbb8bc6dc8d506bafd3293a08c5782061878680b53b72eb4cfdcaedf0d0`

## M05-A - Measured-rail viewport and keyboard-focus increment

- Status: SOURCE AND LIVE DESKTOP PASS; BROADER MATRIX OPEN
- Input: reconstructed 261-check tactical UI and the observed embedded-Web HUD
  overlap.
- Output:
  - tutorial and action surfaces are placed from measured rail widths;
  - viewport changes recalculate a non-overlapping layout;
  - core tactical controls accept Tab focus and receive a visible cyan focus
    outline;
  - deterministic assertions cover the observed 1112-pixel tactical canvas and
    a narrower 768-pixel case.
- Acceptance earned:
  - static project verification: PASS;
  - Godot TestRunner: PASS;
  - Godot PlaytestRunner: PASS, 261/261;
  - focused/current-contract Node checks: PASS;
  - full Node release suite: 39/40, with the single expected fail-closed
    source/runtime manifest mismatch;
  - fresh isolated Web export: PASS;
  - atomic 1440x900 browser loop: PASS;
  - guided tutorial: PASS, 6/6;
  - runtime, full loop, idempotence, full extraction, and base-10 AP: PASS;
  - live tactical screenshot visually reviewed for rail/tutorial/action-dock
    non-overlap.
- Still open:
  - supported viewport and browser matrix;
  - keyboard-only focus-order evidence;
  - reduced-motion, contrast, screen-reader, and scaling evidence;
  - committed runtime/manifest promotion, which belongs to M06.

### Evidence

- `evidence/M05-001-VIEWPORT-FOCUS-2026-07-29.md`
- Atomic pack:
  `evidence/playtests/20260729T105741264Z-6aedeca9`
- `game/scripts/TacticalUI.gd` SHA-256:
  `91b2c2672b16c47b9c116c7f51c95283cca20d04c90451cda4f4fb1eeb927569`
- `game/tests/TestRunner.gd` SHA-256:
  `9373e7d5b07af17bde658b1a6d0c1ec6b6cb265fa7692c54e89d61fbb8d20af3`
- Served tactical PCK:
  263,972 bytes,
  `ad091f07ed11ecfc56800bb8f0c1668eb72c44698878e8587359bfe7f257b835`
- Report SHA-256:
  `f1d2d12412a8d60a8b0ebed0581a77d1fd79ada6ad08e2c1ce8f1594f029fa39`

## M05-B - Broader viewport, keyboard, motion, and contrast matrix

- Status: PASS for its declared scope; support boundary narrowed
- Input: the M05-A source correction and its single 1440x900 live loop
- Output:
  - the layout and contrast model moved to `scripts/HudLayout.gd` as pure static
    functions shared by the HUD, the headless checks, and the evidence emitter;
  - vertical layout metrics: measured status-rail bottom, feed-rail
    top/bottom/height, dock top, and a `constrained` flag;
  - Tab released from the help overlay and reserved for focus traversal;
  - a keyboard entry point, because Godot advances focus only from a control
    that already holds it;
  - a scrollable status rail, so the rail reports the height it occupies instead
    of spilling its content under the tactical feed;
  - feed-rail placement computed from the dock's measured height;
  - a reduced-motion camera boundary driven by the host preference on Web;
  - bounded `layout` and `accessibility` blocks in the Web observation surface;
  - `tools/a11y/matrix.mjs`, a live viewport/motion/keyboard matrix harness.
- Defects corrected:
  - Tab toggled help instead of traversing focus, making keyboard-only play
    impossible;
  - keyboard users had no entry point into the HUD;
  - the tactical-feed rail covered the status rail's stance and core-cost lines
    at every canvas, including in the M05-A pack that was reported as visually
    verified;
  - a wrapped action dock overlapped the feed rail.
- Acceptance earned:
  - static project verification: PASS;
  - Godot TestRunner: PASS;
  - Godot PlaytestRunner: PASS, 261/261;
  - `npm run check`: PASS;
  - full Node release suite: 39/40, the single expected fail-closed
    source/runtime manifest mismatch;
  - deterministic layout/contrast artifact: PASS, 0 of 17 contrast failures;
  - live matrix, nine cases: PASS on all five required gates;
  - visual review at 1366x768: status rail, feed rail, tutorial, and action dock
    disjoint, with a visible keyboard focus ring.
- Support boundary, stated as canvas sizes reported by the runtime:
  - supported: 1172x659, 1112x626, 1038x584;
  - declared unsupported and reported as constrained: 952x536, 696x420, 734x413;
  - every supported canvas reports a cramped tactical feed.
- Still open:
  - a compact HUD mode to widen the boundary and give the feed real room;
  - screen-reader and assistive-technology behavior, which a canvas runtime does
    not expose;
  - browser coverage beyond the resolved Chromium build, and OS text scaling;
  - committed runtime/manifest promotion, which belongs to M06.

### Evidence

- `evidence/M05-002-A11Y-MATRIX-2026-07-29.md`
- Live pack: `evidence/a11y/20260729T233419689Z-a083f87c`
- `SHA256SUMS` SHA-256:
  `dbfcae6a2eed03625db8b6d256e636590d458aed5f33248d4b98f8fd1761f89b`
- Served tactical PCK:
  276,312 bytes,
  `5357e050000cf7d10f27017ac966eab55b12465ae8149247740698d35e949f37`
- `game/scripts/HudLayout.gd` SHA-256:
  `8d7c908fc1427437b135ae892425fa2f25812217756d75185c7e4b168bda818b`
- `game/scripts/TacticalUI.gd` SHA-256:
  `6c24708f30d842958e3ff2cc899622af54bc5c3a75507ba0d1fdde6cf056ca31`
- `game/tests/TestRunner.gd` SHA-256:
  `5d24ad03c71470ac6453369dcf9af3b3fd9a0b68d12257e91c7fb9e50722941c`

## Original dependency order and current position

1. M00 baseline checks and provenance — complete
2. M01 source reconstruction and parity — complete in SOL
3. Atomic playtest evidence packs — complete
4. M01-004 AP-zero guidance — complete
5. M03 golden cases — complete; M03-002 closed the live rationale observation in
   an armed sector and identified the guided scenario's AP-0 dummies as the
   reason it could never appear there
6. M04 bounded reproduction artifact — complete for declared supported portion
7. M05 viewport/accessibility — M05-A source/live desktop increment and M05-B
   broader matrix complete; compact HUD mode and assistive-technology behavior
   remain open
8. M06 local release-candidate preparation — gated
