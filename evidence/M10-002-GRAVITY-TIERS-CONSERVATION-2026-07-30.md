# M10-002 — Gate hole closed; columns shed under gravity; matter is conserved

- **Date:** 2026-07-30 (UTC-05:00)
- **Checkout:** `C:\CLAUDE\7-30-2026-Claude\BattleStarSol`
- **Environment:** Godot 4.7.1.stable.official.a13da4feb, headless; Node 22; Windows PowerShell 5.1
- **Gates:** M10-002a harness integrity, M10-002b gravity-driven tier shedding, M10-002c conservation of matter
- **Result:** **PASS** on all three, each with controls observed failing first
- **Agent:** Claude Opus 5

---

## Part A — the gate hole

M10-001 recorded that a test hitting `SCRIPT ERROR` abandons the rest of its function, returns
control to the runner, and leaves the suite reporting **PASS** with every later assertion
silently unexecuted. Cleared here, in two layers, because neither alone is sufficient.

**Layer 1, in-engine: an assertion floor.** `_expect` now counts every call. The suite prints
its count and fails if fewer assertions ran than `MIN_CHECKS`. GDScript gives a caller no way
to learn that its callee aborted — a runtime error looks identical to a normal return — so the
count is the only in-engine signal available. This is the pattern `PlaytestRunner` already
used; nothing new was invented for it.

Verified deterministic across three consecutive runs at 1302, then pinned. Raised to **1427**
when this module's tests landed. The floor is raised deliberately when tests are added and is
never lowered to make a run pass.

**Layer 2, at the process boundary: `game/tools/test.ps1` now scans output.** The exit code is
not sufficient evidence, and the floor cannot see failures *outside* a test function — parse
errors, or an error before the first assertion. The wrapper fails on `SCRIPT ERROR`,
`Parse Error`, or `Invalid type in function` regardless of exit code, and also fails if a suite
exits 0 without printing a `PASS:` line.

**A pre-existing break found while doing this.** `test.ps1` invoked Godot directly under
`$ErrorActionPreference = 'Stop'`. In Windows PowerShell 5.1, stderr from a native executable
is wrapped in an `ErrorRecord`, so the project-import step's harmless
`WARNING: Scan thread aborted` became a **terminating error that aborted the whole script
before any suite ran**. Both Godot invocations now go through `Start-Process` with
`-RedirectStandardOutput` / `-RedirectStandardError` to files, which is the 5.1-safe pattern.
The harness had been silently unusable this way; nobody had noticed because everyone ran the
suites by hand.

### Verification

Reinstated the exact defect from M10-001 — the wrong argument order in `damage_terrain`:

| Layer | Observed |
|---|---|
| in-engine floor | `FAIL: only 1299 assertions ran, expected at least 1302 -- a test aborted before reaching its assertions (look for an engine error above)` |
| `test.ps1` wrapper | `FAIL: res://tests/TestRunner.gd produced engine errors, so its result cannot be trusted even at exit 0:` then the offending lines; exit **1** |

Restored, then the wrapper run end to end: static verification PASS, `TestRunner` PASS 1427
checks, `PlaytestRunner` PASS 312 checks, exit **0**. Confirmed the wrapper tolerates the
benign `ObjectDB instances were leaked` and `resources still in use at exit` lines rather than
failing on every run.

One self-inflicted detail fixed: the floor's failure message originally quoted the literal
string `SCRIPT ERROR`, so it matched the wrapper's own fatal filter. Reworded to "engine
error".

---

## Part B — height sheds sequentially, under gravity

Previously a column's height snapped: `z = mini(maxi(height - 1, 1), 2)` the instant integrity
crossed `HARD_COVER_FLOOR`. A six-high wall became two-high in one step and the four tiers
between simply stopped existing.

**Down is −Y.** Material rests on what is beneath it and nothing floats, so a column occupies
tiers 1..z contiguously from the ground and losing material shortens it **from the top**. That
is the whole of the gravity rule, and it is what makes the shed sequential.

`Ballistics.supported_tiers(cell)` answers how many tiers the remaining integrity can hold up:

```text
capacity_per_tier = original_density / original_tiers
supported         = floor(current_integrity / capacity_per_tier)
```

Both inputs are the cell's **original** values. `density` already never changed as integrity
fell; `WorldBuilder.material_cell` now also records `tiers`, the height the column started at.
Deriving capacity from the *current* height instead would make each surviving tier cheaper to
hold up as the column shrank, and **the last tier would be indestructible** — asserted
directly.

`degrade_cell` sets `z = min(height, max(supported_tiers, 1))`, never grows a column back, and
reports `tiers_lost`.

---

## Part C — conservation of matter

A tier that fails does not cease to exist. `Main.damage_terrain` converts `tiers_lost` into
debris on the cell via the **existing** `_add_debris(cell, "rock", n)` — the same rocks a unit
can pick up and throw, which the AI already paths toward via
`Pathfinder.nearest_debris_path`. No second inventory of rubble was created; the capability
register lists debris as an existing system and this feeds it.

### Measured, not asserted

Twelve damage per hit, three column heights:

```text
=== column height 6, density 96, capacity/tier 16.0 ===
hit  integrity  z  supported  lost  debris_total
  1   84        5  5          1      1
  2   72        4  4          1      2
  3   60        3  3          1      3
  4   48        3  3          0      3        <- crosses to soft, height already correct
  5   36        2  2          1      4
  6   24        1  1          1      5
  7   12        1  0          0      5
  8    0        0  0          1      6
  total tiers recovered as debris: 6   original height: 6   conserved: true
```

Height 4 → 4 tiers recovered. Height 3 → 3 tiers recovered. **Exact conservation at every
height tested.**

A single large event still takes several tiers and accounts for all of them: 60 damage to a
six-high wall drops it to `z 2` and reports `tiers_lost 4`.

### Controls observed failing

| Mutation | Observed |
|---|---|
| restored the threshold snap for height | `a single small hit shed 2 tiers at once`, then 3, then 4 |
| removed the `_add_debris` hand-off | `2 tier(s) came down and left no debris -- destruction deleted matter`, `debris on the cell (0 rock) does not account for the 2 tier(s) that fell` |

**Two mistakes of my own, worth recording because both are on the live build notes list.**

First, I ran both mutations *simultaneously* and only the shedding control fired. The snap rule
held `z` at 6 for a 20-damage hit, so no tier was lost, so the conservation assertion — guarded
on `shed > 0` — never ran. **Two negative controls can mask each other.** Re-run one variable
at a time; the conservation control then fired immediately.

Second, when I suspected the mutation had not applied, my check was justified: the script that
applied it used `str.replace()` **without asserting the anchor matched**, which is precisely
rule 4 — a patch step that reports success without applying. It had applied, but the method was
unsound, and the diagnosis cost a probe run. Every mutation script in this session that
asserted its anchor gave a trustworthy answer; the one that did not, did not.

---

## Gates

| Gate | Result |
|---|---|
| `npm test` | **PASS**, 56/56 |
| Godot `TestRunner.gd` | **PASS**, **1427 checks** |
| Godot `PlaytestRunner.gd` | **PASS**, 312 checks |
| `game/tools/test.ps1` end to end | **PASS**, exit 0 |

Web runtime re-exported, then `MANIFEST.sha256` regenerated from it, normalized to LF.

## Open, and named

- **Debris is accounted for on the cell it fell from, not spread to neighbours.** A tier that
  comes down lands where it stood. Real collapse throws material outward, and the user's framing
  — "some blocks have to go so others can fall" — is fully satisfied vertically but not yet
  laterally. Spreading debris to adjacent cells is a further module and would interact with the
  reproduction ledger's size budget, which is already the known constraint at roughly 18
  worst-case grenades.
- **A tier's worth of matter is one rock.** That is a deliberate unit choice, not a measurement:
  the debris system counts item stacks, so one tier maps to one throwable. If tiers should yield
  material proportional to their density, that is a design decision.
- **Nothing above a destroyed tier is displaced laterally.** Collapse is modelled as the column
  shortening, not as blocks toppling into neighbouring cells.
