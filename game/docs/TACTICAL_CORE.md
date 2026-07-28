# Tactical core (pre-alpha)

Authoritative map of how Battle/Star.SOL implements the design boundaries.

## Products in this Godot project

| Layer | Responsibility | Key scripts |
|-------|----------------|------------|
| **xCommander** | Deterministic sim: terrain, turns, actions, AI, combat, extraction math | `WorldBuilder`, `Pathfinder`, `ActionEconomy`, `MovementContext`, `ManeuverState`, `CombatSystem`, `AIBehavior`, `TurnDirector`, `MissionResolver` |
| **Battle/Star.SOL** | Theme: factions, pilot fantasy, narrative, vault, presentation | `PilotControl`, `SquadSpawner`, `Narrative`, `Economy`, `TacticalUI`, `StratLayer` |
| **Boundary** | Payload + intents | `PayloadContract`, `PayloadBridge`, `ActionRouter` |

A.T.L.A.S. remains the browser shell under `web/atlas/`.

## Control model

1. **Commander** — first squad slot; human home body (`is_commander`, `player_controlled`).
2. **Agents** — remaining slots; `is_squad_bot`, autonomous via same AI as hostiles.
3. **Remotes** — God Mode special; temporarily sets `player_controlled` on an agent.
4. **End Turn** — autonomous agents resolve, then enemy factions.

Policy lives in `PilotControl.gd`. Main only orchestrates scene effects.

## Action pipeline

```
UI / hotkey / AI score
        |
        v
ActionRouter.request_action  (records intent)
        |
        v
Main.perform_action          (legality + dispatch)
        |
        +-- ActionEconomy costs
        +-- MovementContext / ManeuverState
        +-- CombatSystem / InventorySystem
        |
        v
GameState.event_records / extraction payload
```

AI currently resolves inside Main (`_enemy_act`) using `AIBehavior.score_actions`.
The long-term target is full intent parity through ActionRouter for all providers.

## Turn order

`TurnDirector` defines refresh policy. Sequence per global cycle:

1. Player faction AP refresh (whole squad).
2. Human pilots Commander (or Remotes body).
3. End Turn → squad bots AI pass (no AP re-grant).
4. Metropoli / Kaiju faction AI passes with full AP refresh.

## Determinism

- `sim_rng` — mechanical rolls (dodge/flip, ballistic salvage loss).
- `visual_rng` — presentation only (must never affect outcomes).
- World cells: base deploy seed via WorldBuilder.
- Payload carries `seed`, `generator_version`, `rules_version`.

## Combat contracts

- **Cover matrix**: half (z=1) / full (z>=2); crouch upgrades half→full vs ranged.
- **Armor**: kinetic ablates, thermal burns, rail/beam pierce (items.json).
- **LOS**: Pathfinder; committed cover face blocks non-penetrating fire unless leaning.
- **Hits**: deterministic damage after cover/armor; dodge/flip use `sim_rng`.

## Extraction

`MissionResolver` owns living counts, salvage compile, gains package.
Main owns timers, hints, scene return, and PayloadBridge push.

## God Mode specials

Unlocked by `dev_god_mode` (or unit skill token):

- Remotes / Remotes Home
- Cover Monkey, Flip, Wall Run, Wall Jump, Frenzy (as implemented)
- Free-fly drone camera

## File map (tactical)

| Concern | Module |
|---------|--------|
| Pilot / Remotes | `PilotControl.gd` |
| Turn phase policy | `TurnDirector.gd` |
| Squad cast | `SquadSpawner.gd` |
| Mission end | `MissionResolver.gd` |
| Scene orchestration | `Main.gd` |
| Costs | `ActionEconomy.gd` |
| Mobility legality | `MovementContext.gd` + `ManeuverState.gd` |
| Combat resolve | `CombatSystem.gd` |
| AI scores | `AIBehavior.gd` |
