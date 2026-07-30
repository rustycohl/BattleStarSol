# M05-004 HUD pointer affordance and persistence

## Authority

Principal decision, 2026-07-30: the two open items from M05-C, in order — a
pointer affordance for the adaptive HUD controls, then persistence of surface
states to the Commander profile.

## Pointer affordance

The adaptive behaviour existed but was invisible to anyone who did not press F2.
Each surface now carries two grips on a `HudGrips` overlay:

| Grip | Behaviour |
|---|---|
| Slide (`⇥` / `⇤`) | Parks the surface or brings it back. Its glyph reflects the current state. |
| Opacity (`◐`) | Cycles the surface's transparency. |

The grips are placed against their surface's real rectangle at the end of every
layout pass, so they track adaptation. **A parked surface's slide grip moves into
the handle that stays on screen**, which is what makes a slid surface clickable
again rather than lost.

They are pointer affordances only: `focus_mode` is `FOCUS_NONE`, so they do not
lengthen the keyboard action traversal that F2/F3/F4 already covers. Both grips
carry tooltips naming their keyboard equivalent.

The opacity grip hides itself on a parked surface — there is nothing legible left
to fade.

## Persistence

HUD preferences are stored in the Commander profile, as instructed, rather than in
a side channel. `bridge.js` gained a bounded `hud` field:

- schema `gzg.battlestar.hud/1.0`, four named surfaces, each with `opacity` and
  `parked`;
- `normalizeHudPreferences` clamps opacity to `0.15`–`1.0`, accepts only a real
  boolean `true` as parked, drops unknown surface keys, and falls back to the
  authored HUD for any non-object, array, or missing value;
- `readHudPreferences` / `writeHudPreferences` are the narrow pair the tactical
  runtime calls, so the Godot side never learns the profile's storage shape.

Only deliberate player intent is written. Automatic adaptation is a response to
the current window, not a preference, and is never stored as one.

### One real bug found here

The tactical runtime lives inside the launcher's iframe, so `window.BSS_BRIDGE`
does not exist in its own window. The first implementation silently wrote nothing.
It now resolves the host bridge through `window.parent` and `window.opener`, the
same way `PayloadBridge` already hands off extractions — an existing pattern, not
a new one.

A second defect: HUD changes altered no simulation state, so nothing republished
the observation surface and a live run could not see them. HUD changes now publish.

## Verification

| Gate | Result |
|---|---|
| Static project verification | PASS |
| Godot headless TestRunner | PASS |
| Godot PlaytestRunner | PASS, 282 checks |
| `npm run check` | PASS |
| Full Node release suite | 42 tests, 41 pass; the single expected fail-closed manifest mismatch |
| Live persistence round-trip | PASS |

Live round-trip, in one browser session: two F3 presses faded the status rail to
`0.5`; F2 then F4 parked the tactical feed. The Commander profile recorded
`status.opacity 0.5` and `feed.parked true`. A **fresh deployment** then reported
`status` at `0.5` again — read back and applied, with automatic adaptation
reporting nothing parked of its own accord.

New deterministic coverage: every surface has both grips with tooltips; grips stay
out of the keyboard order; the slide grip inverts state and the opacity grip
changes opacity; a parked surface's slide grip stays on screen. Node coverage adds
a profile round-trip that leaves the rest of the profile untouched, and a
fail-closed case for out-of-range, non-finite, wrong-typed, unknown, and absent
values.

## Source identities

| File | SHA-256 |
|---|---|
| `game/scripts/TacticalUI.gd` | `751a3faf82265d47a04af25b77e913d5df651f19c321412ee83f0074c898c796` |
| `game/web/bridge.js` | `c0055123bcdebfd957cf11760c57674a5893df78692e76901933390c320c9199` |
| `tests/bridge.test.mjs` | `b12946003c728a1676184de8d719be9686663b8978ff52c9f17dbb09c5f98ea0` |

## Still open

- No animation on a slide; the surface jumps. Animating it should respect the
  reduced-motion preference resolved in M05-B.
- Grips are square glyph buttons, not drag handles. A surface cannot yet be
  dragged to an arbitrary position, only parked or restored.
- Preferences are per-browser-profile, like the rest of the local vault, and are
  cleared with it.
