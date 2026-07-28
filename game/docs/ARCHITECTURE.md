# Architecture

**Live snapshot:** see also [TACTICAL_CORE.md](TACTICAL_CORE.md) and monorepo [STATE_OF_PLAY](../../docs/STATE_OF_PLAY.md).

## Boundaries

**A.T.L.A.S.** observes context, renders strategic entities, and emits a small
deployment payload. It is a browser surface under `web/atlas/` and is not rebuilt
in Godot.

**xCommander** owns deterministic terrain, legal actions, turns, AI behavior,
combat, and extraction calculation. Theme must not fork core rules.

**Battle/Star.SOL** supplies factions, pilot fantasy (Commander / Agents /
Remotes), narrative grammar, resources, research, and presentation.

## Runtime flow

```text
A.T.L.A.S. / StratLayer / Vault
        │  DeploymentPayload (contract 1.0)
        v
PayloadBridge + PayloadContract
        │
        v
Main (scene) + modules:
  SquadSpawner → cast + pilot roles
  ActionRouter → intents
  PilotControl → who may act
  TurnDirector → AP / phase policy
  ActionEconomy / MovementContext / ManeuverState
  CombatSystem / InventorySystem / AIBehavior
  MissionResolver → salvage + outcome package
        │  ExtractionResult + replay bundle
        v
PayloadBridge → postMessage / user:// / optional HTTP
        v
A.T.L.A.S. shell or StratLayer vault
```

Canonical distribution: static pages + client Godot (native or Web).
HTTP GET/POST in PayloadBridge is optional relay only.

## Control model (Battle/Star theme on xCommander)

| Role | Flags | Policy |
|------|--------|--------|
| Commander | `is_commander`, `player_controlled` | Human home body |
| Agent | `is_squad_bot` | Utility AI unless Remotes login |
| Hostile | neither | Utility AI on their faction turn |

`PilotControl.gd` is the authority for login state. Remotes is a **God Mode**
special (or unit skill token). Behavior-over-special-case: agents share the
same action vocabulary and AI scorer as hostiles.

## Determinism

Payload carries `seed`, `generator_version`, `rules_version`.

- World cells: base seed (`WorldBuilder`).
- Sim rolls: `Main.sim_rng` only (dodge/flip, ballistic salvage loss).
- Visual/narrative streams must not advance the sim stream.
- Generator changes that break old seeds need a new `generator_version`.

## Action providers

UI and hotkeys call `ActionRouter.request_action`, which records intents and
dispatches to `Main.perform_action`.

Scripted AI currently scores with `AIBehavior` and resolves inside Main
(`_enemy_act`) for hostiles and autonomous agents. Target architecture still
calls for full provider parity (human / AI / replay / inference) through the
same intent object.

## Action economy

**Live scale: Base-10** (`GameConfig.MAX_AP = 10`).
`ActionEconomy` is the sole cost catalogue for UI, legality, AI cost awareness,
and previews. Historical design notes about 24 AP are prior tuning, not current
balance.

## Contextual movement

`MovementContext` = geometry/state legality.
`ManeuverState` = airborne / wall phase records.
`Main` = current resolver (animation + apply).

- Take Cover: paid commit, brace, lean, paid exit; face blocks non-penetrating fire.
- Jump: momentum or Precision Jump; air anchor; paid completion; zero-AP fall → prone.
- Wall Run / Wall Jump / Flip / Cover Monkey: implemented under God Mode specials;
  Wall Run is vertical tower faces only for now.

## Combat

`CombatSystem` owns hit resolution:

- Half cover (z≈1) / full cover (z≥2); crouch upgrades half→full vs ranged.
- Armor: kinetic ablates, thermal burns, rail/beam pierce (`items.json`).
- High ground bonus; block reduction; flip/dodge use `sim_rng`.

## Mission end

`MissionResolver` compiles living counts, salvage (mission-type aware), and
gains. Main owns timers, hints, scene return, and PayloadBridge push.

## Packaging

- Native: `Bootstrap.tscn` → StratLayer; deploy → Main.
- Web: Bootstrap → Main; A.T.L.A.S. embedded; extraction via postMessage.
- Orphan multiplayer / experiments: `../../archive/orphans` (not active runtime).
