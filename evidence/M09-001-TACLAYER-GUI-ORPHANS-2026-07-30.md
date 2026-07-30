# M09-001 — Tactical GUI orphans: hidden specials and a double-bound key

- **Date:** 2026-07-30 (UTC-05:00)
- **Checkout:** `C:\CLAUDE\7-30-2026-Claude\BattleStarSol`
- **Environment:** Godot 4.7.1.stable.official.a13da4feb, headless; Node 22
- **Gate:** M09-001 — the tactical interface represents what the model permits
- **Result:** **PASS**, three defects fixed, each with a control observed failing first
- **Agent:** Claude Opus 5
- **Origin:** hand playtest by the principal — "the 'Wall Run' option in dev mode was just
  missing"

## Defect 1 — specials hidden by their own precondition

`TacticalUI.update_ui()` set special visibility twice per pass:

```gdscript
for special_name in ["remotes", "cover_monkey", "flip", "wall_run", "wall_jump", "frenzy"]:
    action_btns[special_name].visible = god          # writer 1
...
action_btns["wall_run"].disabled = (                  # precondition computed
    main.selected.ap < Config.WALL_RUN_COST
    or (not wall_running and runnable_walls.is_empty())
)
...
action_btns["wall_run"].visible = wall_running or not runnable_walls.is_empty()   # writer 2
action_btns["flip"].visible = airborne
action_btns["wall_jump"].visible = wall_running
```

Writer 2 wins. With no qualifying wall adjacent — standing on open ground, which is most of
the time — Wall Run vanished in dev mode. **Flip and Wall Jump vanished the same way**, by the
same three lines; only Wall Run had been noticed.

Two things make this worse than a cosmetic slip:

- **The `disabled` computation directly above is unreachable in exactly the cases it was
  written for.** The author wrote both a grey-it-out path and a hide-it path for the same
  condition, and the hide won. That contradiction is the orphan signature: two intents, one
  silently overriding the other.
- **The tooltip is the only place the requirement is written down** — "spend actual Run/Sprint
  momentum to traverse an adjacent wall as local ground." Hiding the button takes the
  explanation with it, so the mechanic becomes undiscoverable and the God Mode toggle appears
  to do nothing for that special.

## Defect 2 — the interface re-decided availability instead of asking the authority

`Main._special_enabled(unit, name)` is `unit.has_special(name, dev_god_mode)`, which is
`dev_god_mode or skills.has(name)`. The action router gates every special through it. The
interface instead tested `dev_god_mode` directly.

Consequence: **a unit carrying a special's skill token can use it but has no button for it.**
The router permits the action; the interface never draws it. No unit in `DEFAULT_SKILLS`
currently carries a special token, so this is latent rather than observable today — stated
plainly rather than counted as a live bug — but it is the reason the two decisions could drift
in the first place.

## Defect 3 — one key driving two actions

`_setup_input_map()`:

```gdscript
"camera_elevate": [KEY_E],
"camera_descend": [KEY_Q],
...
"lean_left":  [KEY_Q],
"lean_right": [KEY_E],
```

Nothing consumes the event. `Main` polls `Input.is_action_just_pressed("lean_left")` in its
input handler; `CameraController` independently polls
`Input.is_action_pressed("camera_descend")`. Both fire. **Pressing Q while in cover leaned the
unit and dropped the camera in the same frame.**

`docs/CONTROLS.md` documented it as intended behaviour:

> `| Q / E | lean left/right when contextual; also camera elevation controls |`

Which is the failure mode from live build notes rule 19 in miniature: the collision was
observed, written down, and thereby preserved.

The capability register's single-authority list claims "no gameplay action claims a key
reserved for the interface." The test that existed guarded exactly one key — Tab — and Tab was
the one key anyone had been burned by.

## Changes

- **`TacticalUI.gd`** — new `SPECIAL_ACTIONS` const listing the specials Main gates through
  `_special_enabled`, with a note on why `precision_jump` and `frenzy` are excluded.
  Visibility is set once, from that authority. New `_gate_special(name, reason)` applies
  precondition as `disabled` plus an appended tooltip and **cannot hide**. New
  `_first_reason(candidates)` reports the cheapest-to-fix blocker first, so a player short on
  AP is told that rather than told about wall geometry they cannot change. The three hiding
  overwrites are gone; the flight and frenzy development aids keep their existing God Mode
  binding, unchanged.
- **`Main.gd`** — lean moved to `KEY_BRACKETLEFT` / `KEY_BRACKETRIGHT`. Lean is contextual and
  already has buttons; camera is always live and WASD-adjacent, so moving lean is the smaller
  change and preserves camera muscle memory. Brackets read as lean direction and collide with
  nothing.
- **`TacticalUI.gd`** — button labels now read `Lean L ([)` / `Lean R (])`.
- **`docs/CONTROLS.md`** — the collision line replaced with two accurate rows.
- **`TestRunner.gd`** — two new controls (below).
- Web runtime re-exported, `game/MANIFEST.sha256` regenerated from it, normalized to LF.

## Controls added

**`_test_specials_stay_visible_in_god_mode()`** — instantiates `Main.tscn`, selects the human
pilot, and asserts across `SPECIAL_ACTIONS`: with God Mode off and no token nothing is claimed
and nothing is shown; with God Mode on every special the authority grants is **visible**
whatever the situation, and any disabled special states a reason. Then the specific playtest
case: standing still with no wall available, Wall Run must be visible, disabled, and its
tooltip must mention momentum.

**Key-collision invariant** — walks the whole `InputMap`, skipping `ui_*`, and fails if any
keycode owns more than one action, naming both. An action may carry several keys; a key may not
carry several actions.

## Verification

Negative controls, each observed failing before reverting:

| Mutation | Observed failure |
|---|---|
| reinstated the three `visible =` overwrites | `flip is hidden in God Mode …`, `wall_run is hidden in God Mode …`, `wall_jump is hidden in God Mode …`, `Wall Run vanished with no wall available instead of greying out` |
| reinstated `lean_left: [KEY_Q]`, `lean_right: [KEY_E]` | `key Q drives both 'camera_descend' and 'lean_left' -- neither consumes the event, so both fire`, and the same for E |

After restoring: `npm test` **56/56 PASS**, Godot `TestRunner` **PASS**, `PlaytestRunner`
**PASS, 312 checks**.

## Sweep performed, and its limits

A mechanical audit of `update_ui()` for properties written more than once found seven further
multiply-written `visible` properties — `hover`, `frenzy`, `toggle_flight`, `flight_up`,
`flight_down`, `flight_land`, `toggle_free_fly`. **All are `if`/`else` branch pairs on
`dev_god_mode`, not competing writers on one path.** Checked, not assumed; no change made.

A cross-reference of registered buttons against the input map found the Q/E collision above.
The remaining asymmetries are legitimate: camera and HUD actions are keyboard-only by design,
`end_turn`/`emergency_evac` have buttons under different names, and ten buttons are mouse-only.

**Not swept:** `StratLayer.gd` and the launcher UI, and the weapons bar. The same two-writer
audit should be run over those before the next release. Naming them so the gap is visible
rather than implied.

**One thing observed and deliberately not changed:** `CameraController.gd:124` reads
`Input.is_action_pressed("camera_elevate") or Input.is_action_pressed("jump")`, so the jump key
also raises the camera. This is a code-level double-read rather than an `InputMap` collision,
so the new invariant does not catch it, and it may be intentional. Recorded for a decision
rather than silently altered.
