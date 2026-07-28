# Implementation status

**As of:** 2026-07-28 pre-alpha (`0.1.1-prealpha.1`)
**Companion:** monorepo [STATE_OF_PLAY](../../docs/STATE_OF_PLAY.md) · [TACTICAL_CORE](TACTICAL_CORE.md)

This file is the **live claim list** for the Godot product tree. Alpha series docs under `docs/alpha/` are recovery history.

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

### Presentation / tooling

- Responsive tactical HUD (squad rail, ephemeral feed, action dock, fullscreen)
- Fog-of-war style hostile hide beyond sensor radius 12
- Bootstrap: native → StratLayer; web → Main
- Headless `TestRunner` + `PlaytestRunner` (147 checks); static `tools/verify.ps1`

---

## Partial / scaffold

| Area | Notes |
|------|--------|
| Mobility | Wall Run is vertical tower faces only; AI does not yet use advanced mobility |
| Verticality | Height affects cost/LOS/fall/bonus; climbing/reach still permissive |
| Audio | Buses/pools exist; no shipped SFX library; missing clips remain deliberately silent/null |
| Tutorial | Proving Ground is a one-unit sandbox, not a guided mission FSM |
| Online relay | Optional HTTP in PayloadBridge; no shipped server |
| Models | GLB path lookup exists; no shipped character models |
| Atlas FoW | Approximate sensor filter; no authenticated world feed |
| Web tactical package | Fresh Godot 4.7.1 single-threaded release export committed; rebuild after Godot source changes |

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

Expected: static PASS · PlaytestRunner 147 checks PASS · TestRunner PASS.

---

## Next (alpha sprint candidates)

1. AI agents use cover and simple flanking (still no wall-run AI required)
2. Playtest-tune Base-10 costs and agent aggression
3. Guided Proving Ground objectives and clearer first-turn interaction
4. Guided Proving Ground objectives
5. Overwatch / destruction only after the above feels solid

---

## Historical doc caveats

- `docs/alpha/14` and older notes describe a **24-AP** scale; **live code is Base-10** (`GameConfig.MAX_AP = 10`).
- Paths like `alpha build docs/` or `battlestar.codex` refer to pre-monorepo layouts; use this tree.
- Recovery ledger (`docs/alpha/04`) is provenance, not a todo list.
