# Test gates

## Automated

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\test.ps1 -GodotPath C:\path\to\Godot_console.exe
```

The script first checks JSON, local resource references, Web packaging, removal
of the old network singleton, and use of explicit RNG streams. It then runs the
headless Godot suite directly. It intentionally does not boot the editor as a
test pre-step: Godot 4.7.1's Windows editor path can crash while initializing
its profile in restricted environments even though the project runtime and
headless suite are healthy.

Use the console executable when both Windows builds are available. If the GUI
executable displays an Application Error whose invalid read address ends in
`0x58`, dismiss it with **OK** and use the direct headless command above. Do not
interpret that editor-startup crash as a failed tactical suite or missing
export templates.

The headless suite verifies:

- equal seeds produce identical generated cells;
- different seeds produce different cells;
- the expected number of cells and required fields are present;
- the 24-AP scale and movement/elevation cost catalogue are consistent;
- legacy payload envelopes normalize to contract 1.0;
- invalid payloads are rejected;
- `Main.tscn` builds its complete grid and opposing squads;
- the action router binds, changes tactical state, and appends a serializable
  accepted intent record;
- native strategic launch references the bundled HTTP server and not
  `file://`;
- A.T.L.A.S. core presentation references bundled same-origin runtime assets;
- contextual cover legality, AP costs, state serialization, automatic Brace,
  paid exit, movement lock, and UI availability remain coherent;
- Cover Monkey adds exactly one AP per movement segment, exits committed cover
  for free during movement, and re-enters adjacent cover without a hidden
  action charge;
- Run/Sprint distance momentum, Precision Jump bypass, serialized airborne
  state, paid two-stage Jump, zero-AP detachment, fall, and prone recovery;
- contextual Lean, solid cover LOS, ignored selected face while leaning, and
  explicit weapon cover penetration;
- selected-face vertical Wall Run, surface-state serialization, outward Wall
  Jump, and airborne Flip/Dodge;
- `StratLayer.tscn` builds its login surface.

## Required manual smoke pass

1. F5 opens the native strategic launcher.
2. Login, quick deploy, and proving ground both reach `Main.tscn`.
3. Select, move, attack, end turn, evacuate, and return to strat.
4. Re-run the same seed and compare map/item placement.
5. Export a bug report and re-inject a deployment payload.
6. Unlock one research tier and verify vault deductions.
7. From the native launcher, click **Launch A.T.L.A.S.**, confirm the address
   starts with `http://127.0.0.1`, deploy through Atlas, and verify the Godot
   iframe posts the extraction result back.
8. Check 1280x720, 1280x800, 1920x1080, keyboard-only, and mouse-only flows.
9. Select a unit beside a tower, confirm **Take Cover** appears, target the
   adjacent face, verify the unit turns/braces and cannot move, test Crouch and
   Lean, then pay AP with **Leave Cover** and move normally.
10. From committed cover, confirm an unleaned ordinary weapon cannot fire
    through the chosen face; Lean and try again; repeat with a weapon marked
    cover-penetrating.
11. Enable God Mode specials and Cover Monkey. Move away from cover and back:
    confirm free slide-out/slide-in, the +1 AP movement surcharge, automatic
    Brace, and a sensible selected face.
12. Move at least one Run/Sprint segment, Jump to an air anchor, attack from
    the anchor, preserve AP and end the turn, then complete the paid second
    Jump next turn. Separately spend the last AP while airborne and confirm
    fall/prone recovery.
13. With God Mode specials, build momentum beside a tower, select **Wall Run**,
    climb one or more paid vertical segments, Wall Jump outward, and use Flip.
    Evaluate targeting clarity, pose, camera readability, and whether 6 AP per
    wall segment feels appropriate.

Do not stamp an alpha solely from static checks. The historical record made
“loads and runs in Godot” an explicit release gate.

## Recovery validation

Passed with `Godot_v4.7.1-stable_win64_console.exe`:

- project script import;
- automated static and headless suite;
- direct headless startup of `Main.tscn`;
- direct headless startup of `StratLayer.tscn`;
- direct headless startup of `Bootstrap.tscn`;
- Godot 4.7.1 single-threaded debug Web export;
- WebAssembly startup and deployment decoding;
- browser input through a routed Sprint action;
- a complete enemy-turn cycle returning to player turn 2;
- extraction result handoff from Godot to the tactical launcher.

The engine emits a certificate-store warning in the restricted recovery
environment and dummy-renderer leak warnings during forced headless shutdown.
The suite exits successfully and no project script errors are present.

The current Web runtime is included in `web/tactical/`. Rebuild it with the
matching Godot 4.7.1 templates; do not mix template and editor versions.
