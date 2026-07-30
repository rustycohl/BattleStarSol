# Implementation status

## 2026-07-29 isolated SOL reconstruction

The dated public/source claim list below is preserved. Current reconstructed
state is controlled by `../../MODULE-LEDGER.md` and its evidence records:

- static verifier and TestRunner: PASS;
- PlaytestRunner: PASS, 261/261;
- M01 routing/observation, M01-004 AP recovery, and M01-005 view sync: PASS;
- atomic live M01 tutorial: PASS, 6/6;
- M03 cover/flank golden cases: PASS; production AI unchanged;
- atomic evidence helper: PASS, 11/11 focused Node tests;
- authoritative atomic browser run:
  `20260729T104417824Z-b0e26ed0`, PASS;
- M04 bounded reproduction artifact and clean strategic import: PASS for the
  declared supported portion;
- M05 overlap/focus source checks and fresh 1440x900 atomic loop: PASS; broader
  viewport/accessibility matrix remains open;
- Network Sync (WebRTC) and Play-by-Email (PBeM) dual-mode architecture: PASS;
- Terrain exhaustion payload compression (Option C): PASS;
- Native headless Godot X-Command tactical tests: PASS;
- full Node release suite: 60/60;
- committed runtime/manifest parity and release promotion: open.

The current isolated Web export was validated in the in-app browser and in the
standalone atomic Edge run. It is not the committed public runtime and must not
be represented as published.

**As of:** 2026-07-28 pre-alpha (`0.1.1-prealpha.1`)
**Companion:** monorepo [STATE_OF_PLAY](../../docs/STATE_OF_PLAY.md) · [TACTICAL_CORE](TACTICAL_CORE.md)

This file is the **live claim list** for the Godot product tree. Alpha series docs under `docs/alpha/` are recovery history.
The public version above is unchanged; M01–M02 below describe the isolated
`prealpha-02` source work line and are not deployment claims.

---

## Implemented (working source)

### Control & turns

- **Commander pilot model** — human input only on the active pilot (default: first squad unit, Commander)
- **Squad agents** — other two fireteam slots are bots (`is_squad_bot`); same utility AI as hostiles
- **Remotes** — God Mode special jacks into an agent; Remotes Home / Commander target returns
- **End Turn pipeline** — ally agents resolve, then enemy factions; AP refresh via `TurnDirector`
- Three-faction turn cycle with `GameState.turn` sync and global round counter

### Strategic ↔ tactical loop

- Native StratLayer login / launcher / vault inject / R&D lab scaffold
- A.T.L.A.S. browser surface (local vendors, isolation headers, deploy context)
- Native launch reuses loopback HTTP server (`tools/launch-web.ps1`)
- Payload contract 1.0 normalize/validate; seed + generator/rules versions
- Extraction on victory wipe, defeat wipe, and EVAC; vault commit/fail; replay bundle
- Standard galaxy deployment/extraction envelopes with correlation and an
  explicit legacy adapter
- Browser-local callsign/resources/mission vault with bounded, idempotent
  extraction application (not an authenticated account)
- **Play-By-Email (PBeM)** and **Live Network Sync** (WebRTC/ENet) for dual-mode multiplayer state exchange.

### Tactical sim

- Seeded 20×20 height map, spawn pads, deterministic item scatter
- **Base-10 AP** economy; `ActionEconomy` sole cost authority; path-cost preview
- Pathfinding, LOS, shared even-grid cell↔world transform
- Melee / ranged / throw; inventory, grab, bow assembly; item tiers in `data/items.json`
- Armor types (kinetic / thermal / rail) and half/full cover matrix
- Take Cover + Lean; cover face blocks non-penetrating fire
- ManeuverState airborne/wall phases; Jump + zero-AP fall/prone recovery
- God Mode specials: Wall Run, Wall Jump, Flip, Cover Monkey, Precision Jump bypass, free-fly cam
- Utility-scored AI for hostiles and autonomous squad agents
- Mission-local death; salvage by mission type (`MissionResolver`)
- Ordered action + event records on extraction
- Deterministic six-step Proving Ground director driven by accepted actions
  and resolved events, with a persistent objective panel and nearby inert
  hostile targets for every player faction
- Persistent first-turn truth: combined faction vocabulary, active pilot and
  AP, visible core costs, explicit End Turn sequence, and extraction route
- F1/Tab core-loop help overlay; advanced mobility/remotes visibly separated
  behind the developer control
- Persistent hostile-count label restored to the squad roster

### Presentation / tooling

- Responsive tactical HUD (squad rail, ephemeral feed, action dock, fullscreen)
- Fog-of-war style hostile hide beyond sensor radius 12
- Bootstrap: native → StratLayer; web → Main
- Headless `TestRunner` + `PlaytestRunner` (204 checks); static `tools/verify.ps1`

---

## Partial / scaffold

| Area | Notes |
|------|--------|
| Mobility | Wall Run is vertical tower faces only; AI does not yet use advanced mobility |
| Verticality | Height affects cost/LOS/fall/bonus; climbing/reach still permissive |
| Audio | Buses/pools exist; no shipped SFX library; missing clips remain deliberately silent/null |
| Models | GLB path lookup exists; no shipped character models |
| Atlas FoW | Approximate sensor filter; no authenticated world feed |
| Web tactical package | Matching Godot 4.7.1 `.02` source export rebuilt locally; live browser validation remains pending |

---

## Not implemented

- Authenticated accounts, persistent soldiers, permadeath campaign
- Overwatch, suppression, destruction, hazards
- Full ghost/tag-in XP, hotseats, Discord, continuous-time
- Cross-platform replay hash equivalence
- Steam / telemetry / production packaging pass
- Multiplayer authority (ENet remains in `archive/orphans`)

---

## Verification

```powershell
# From monorepo root
.\tools\run-playtests.ps1

# Or Godot project
cd game
..\..\godot-exe\Godot_v4.7.1-stable_win64_console.exe --path . --headless --script res://tests/PlaytestRunner.gd
.\tools\verify.ps1
```

Expected: static PASS · PlaytestRunner 204 checks PASS · TestRunner PASS.

---

## Next (alpha sprint candidates)

1. AI agents use cover and simple flanking (still no wall-run AI required)
2. Playtest-tune Base-10 costs and agent aggression
3. Complete the broader viewport/accessibility matrix after the passing M04
   strategic-reimport and M05 desktop/narrow-width source increments
4. Overwatch / destruction only after the above feels solid

---

## Historical doc caveats

- `docs/alpha/14` and older notes describe a **24-AP** scale; **live code is Base-10** (`GameConfig.MAX_AP = 10`).
- Paths like `alpha build docs/` or `battlestar.codex` refer to pre-monorepo layouts; use this tree.
- Recovery ledger (`docs/alpha/04`) is provenance, not a todo list.
