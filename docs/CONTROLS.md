# Battle/Star.SOL controls

## Strategic Page

- Change the callsign in the bottom command console.
- Select **Quick Deploy: Proving Ground** for the standalone mission path.
- Select a deployable A.T.L.A.S. crisis or coordinate to reveal contextual
  deployment.
- Mission results return to the local campaign vault automatically.

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
