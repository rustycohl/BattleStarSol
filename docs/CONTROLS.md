# Battle/Star.SOL controls

## Strategic Page

- Change the callsign in the bottom command console.
- Select **Quick Deploy: Proving Ground** for the standalone mission path.
- Select a deployable A.T.L.A.S. crisis or coordinate to reveal contextual
  deployment.
- Mission results return to the local campaign vault automatically.

## Guided Proving Ground (`.02` work line)

The Proving Ground objective panel teaches the current six-step loop without
changing tactical authority:

1. select the Commander;
2. preview and complete a move;
3. use adjacent cover, or Brace when the clear training lane has no cover;
4. complete a basic melee or legal ranged attack;
5. end the turn and observe the autonomous/hostile phases; and
6. extract with the HUD control or F8.

The guide advances only after the action router accepts an action or the
simulation records its resolved event. It grants no AP, movement, visibility,
or attack exception. The two deterministic Target Dummies have no AP.

## Tactical basics

- **Left click:** select a unit, target, destination, or highlighted option.
- **Right-drag:** orbit the tactical camera.
- **Mouse wheel:** zoom; while targeting flight, change the flight layer.
- **W/A/S/D or arrows:** pan the camera.
- **Space or Enter:** end the player turn.
- **F8:** emergency extraction. This is a real engine action and returns the
  current survivors, salvage, gains, and replay record.
- **F1 or Tab:** tactical legend.
- **Escape:** cancel current targeting or close the legend.

The player directly pilots the Commander. The two squad agents resolve
autonomously when the turn ends, followed by both hostile factions.

## First-turn status truth (`.02` work line)

The left status rail now keeps the following facts visible instead of relying
on transient hints:

- the active faction and global turn;
- the active human pilot (`CMDR` or `REMOTE`) and current/maximum AP;
- which dock controls are currently legal;
- the exact End Turn consequence: allied Agents, then the other two faction
  phases; and
- the always-available extraction route (`EXTRACT` / F8).

The persistent core-cost line lists Move, Brace, Take Cover, Melee, and Equip.
Detailed and contextual costs remain in the action tooltips, while the action
resolver remains authoritative.

Faction labels use the combined current/canonical vocabulary while preserving
the existing serialized integer IDs:

| Serialized ID | Visible label | Accepted payload vocabulary |
| --- | --- | --- |
| `0` | `HAD // EFD` | HAD, EFD |
| `1` | `SYNDICATE // METROPOLI` | Syndicate/Synd, Metropoli/Metropolis |
| `2` | `TIMECORPS // KAIJU/ALIENS` | Timecorps, Kaiju, Alien/Aliens |

F1 or Tab opens an in-game core-loop reference; Escape closes it before
canceling any targeting mode.

## Action shortcuts

| Key | Action |
| --- | --- |
| B | brace/block |
| T | take or leave cover |
| C | crouch |
| P | prone |
| Q / E | lean left/right when contextual; also camera elevation controls |
| J | jump |
| M | toggle run/sprint |
| N | toggle facing/orientation |
| Z | dodge |
| X | flip |
| H | hover |
| V | toggle flight |
| Page Up / Page Down | change flight layer |
| L | land |
| G | grab loot |
| F | assemble bow |

The action dock is authoritative for availability. Context, AP, stance,
equipment, momentum, cover, and current maneuver state can disable an action
even when its key exists.

## Developer / advanced boundary

Remotes, Cover Monkey, Wall Run, Wall Jump, Flip, Frenzy, Hover, Flight, and
the free-fly camera are optional advanced experiments. They are hidden from
the core dock until **[DEV] ADVANCED MOBILITY + REMOTES** is enabled and are
not required to complete the Proving Ground or the core tactical loop.

## Base-10 AP

Every active unit starts its turn with 10 AP. Movement, stance changes, cover,
attacks, equipment, and advanced mobility draw from the same integer pool.
The displayed preview and the resolver share `ActionEconomy.gd`; older 24-AP
documents describe a superseded tuning scale.

## Extraction behavior

**EXTRACT** and **F8** use the same Godot `_do_evac()` path. After a short
in-engine delay, xCommand builds a standardized extraction message. The
tactical launcher displays receipt, forwards it to strategy, and returns focus
to the campaign Page. The strategic vault applies the message ID once.
