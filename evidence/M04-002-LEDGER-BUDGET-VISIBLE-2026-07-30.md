# M04-002 — Option E: the reproduction ledger's ceiling is visible in play

- **Date:** 2026-07-30 (UTC-05:00)
- **Checkout:** `C:\CLAUDE\7-30-2026-Claude\BattleStarSol`
- **Environment:** Godot 4.7.1.stable.official.a13da4feb, headless; Node 22
- **Gate:** M04-002 — the ledger limit is no longer silent
- **Result:** **PASS**, with one miscalibration of my own found and fixed
- **Agent:** Claude Opus 5

## What this implements

Option E from `evidence/OBSERVATION-001-LEDGER-CAPACITY-2026-07-30.md`, quoted from that
record:

> Independent of the above: report remaining ledger budget in the extraction, and warn when a
> mission crosses the threshold, so the information arrives while the player can still act on
> it. *Effect:* does not raise the ceiling; removes the silence, which is the worst property of
> the current failure.
>
> **If exactly one thing is done, E is the cheapest honest improvement, because it turns a
> silent limitation into a visible one.**

The ceiling is unchanged. What changes is that a mission spending its budget says so while it
is still running.

## The two-authority problem, solved the same way as the rules

The caps are enforced by `tools/repro-bundle.mjs` — `MAX_EVENTS = 1_024`,
`MAX_REPRO_BYTES = 128_000` — which the Godot runtime cannot import. Retyping them into GDScript
would create a second authority that drifts silently, which is exactly the d10SRD failure from
M08-001.

Same remedy: `game/data/repro_budget.json` is the res://-readable **view** of those constants,
and `tests/repro-budget.test.mjs` asserts the pinned values equal the exported ones. The two
cannot diverge without a build failure.

## Change

**`game/data/repro_budget.json` (new)** — the caps, the measured figures from OBSERVATION-001,
the warning threshold, and the baseline overhead with its derivation written out.

**`GameState.ledger_budget()` (new)** — reports records used against the event cap, serialised
ledger bytes against the byte cap less baseline overhead, which cap currently binds (derived, not
assumed), the fraction spent, and a status of `ok` / `warn` / `over`. Bytes are measured from the
real serialised ledger rather than estimated per event, because events are not uniform in size
and an estimate would drift from the bundler it exists to predict.

**`PayloadBridge.push_extraction`** attaches `repro_budget` to every extraction, so a mission
that spent its ledger reports it with its result rather than failing later when someone tries to
bundle it.

**`TacticalUI`** appends to the status rail once the budget is worth mentioning: `[REPLAY LEDGER
n%]` at warning, and at the ceiling `[REPLAY LEDGER FULL: n% of the byte cap -- this mission will
not reproduce]`. Nothing is shown while the budget is comfortable.

## Measured

Live ledger, terrain events, after calibration:

| terrain events | ledger bytes | fraction | binding cap | status |
|---:|---:|---:|---|---|
| 0 | 95 | 0.001 | bytes | ok |
| 50 | 11,355 | 0.108 | bytes | ok |
| 150 | 33,956 | 0.323 | bytes | ok |
| 300 | 68,036 | 0.648 | bytes | ok |
| 420 | 95,316 | 0.908 | bytes | **warn** |
| 462 | ~104,864 | ~0.999 | bytes | warn |
| 600 | 136,086 | 1.296 | bytes | **over** |

Bytes bind throughout, matching OBSERVATION-001. The readout reaches full at 462 terrain events,
which is the measured exhaustion point. The 75% warning fires around 346 events, leaving roughly
115 events of runway — enough to end a mission cleanly.

## A miscalibration of my own, and a test that did not catch it

I first pinned `baseline_overhead_bytes` at a **guessed** 9,000. Measuring showed the readout
then reported **88% at 462 events** — the point where the artifact is already full. An optimistic
readout, on a feature whose entire purpose is honesty about a limit.

Corrected by derivation rather than another guess. A live ledger costs 227.3 bytes per terrain
event (measured from the 300→420 slope), and OBSERVATION-001 measured the byte cap exhausted at
462 events, so the overhead the artifact carries beyond the replay bundle is
`128,000 − (462 × 227.3) = 23,136`, pinned at **23,000**. The derivation is written into the pin
so the next person re-derives it the same way instead of guessing again.

**Worse, and worth recording plainly: my first set of assertions did not catch this.** I wrote
status checks — ok at 300, warn at 420, over at 600 — and claimed in the test's own comment that
they "pin the calibration so that cannot come back." Running the negative control proved they did
not: with the wrong 9,000-byte overhead, 420 events still lands at 80% and still reads `warn`, so
**every assertion passed against the miscalibrated pin.** The control fired only after I added
the assertion that actually has teeth — that the readout must reach ≥97% at the measured
exhaustion point of 462 events.

Two lessons, both already on the list and both earned again here:

- A negative control is the only thing that establishes an assertion tests what you think.
  Plausible assertions clustered around a value are not the same as an assertion *of* that value.
- Writing "this pins X" in a comment does not pin X. The comment was wrong for several minutes
  and would have shipped as documentation of a guarantee that did not exist.

## Verification

Negative control, observed failing:

```text
FAIL: at the measured exhaustion point of 462 terrain events the readout claims only 88.1%
      spent -- baseline_overhead_bytes is miscalibrated and the readout is optimistic
```

Restored, and both bounds asserted: ≥97% so it cannot be optimistic, ≤115% so it cannot be
alarmist.

`tests/repro-budget.test.mjs` additionally asserts the pin equals the bundler's constants, that
the warning threshold sits strictly between 0 and 1, that the overhead is below the cap, and that
the recorded binding cap is still bytes and the worst-case grenade figure has not been reverted
to the friendlier event-cap-only estimate of ~40.

| Gate | Result |
|---|---|
| `npm test` | **PASS**, 60/60 (was 56) |
| Godot `TestRunner.gd` | **PASS**, **1441 checks** (was 1427) |
| Godot `PlaytestRunner.gd` | **PASS**, 312 checks |

Web runtime re-exported, then `MANIFEST.sha256` regenerated from it, normalized to LF.

## What this does not do

It does not raise the ceiling. Options A through D in OBSERVATION-001 remain open, and the
principled fix — a canonical mechanical state hash so a replay need not carry every event — is
still the largest and still not done.

The readout is an approximation, deliberately. The bundler remains the gate and still fails
closed. If the artifact envelope changes, the overhead must be re-derived; the pin says how.

**Also found while probing this:** a `SceneTree` script whose `_go` hits a runtime error never
reaches `quit()`, so the process hangs until killed rather than failing. That is a third face of
the harness hole closed in M10-002 — the assertion floor and output scan catch a suite that
*finishes* wrongly, not one that never finishes. A timeout belongs in `test.ps1`. Recorded, not
fixed.
