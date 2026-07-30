# OBSERVATION-001 — Ledger capacity versus simulation richness

**Status: not fixed, deliberately. Full fidelity retained; the artifact fails closed.**

Principal instruction, 2026-07-30: *"keep it honest for now, note this very
extensively in docs [...] I'm going to deep dive it because it has broader
implications than just grenades."*

This document is written to be sufficient source material for a paper. It states what
was measured, how, what binds, what the options cost, and where the problem stops being
about grenades.

---

## 1. The concrete finding

A single radius-2 grenade emits one `terrain_damaged` event per destructible cell it
works. Beyond some number of grenades in one mission, the mission can no longer produce
a reproduction artifact at all.

### Measurements

All figures measured on this checkout, not estimated. Method is given so they can be
re-derived or disputed.

| Quantity | Value | How measured |
|---|---:|---|
| Cells in a radius-2 Chebyshev blast | 25 | 5×5 footprint, `_detonate` |
| Destructible cells in generated terrain | **53%** | 2,800 cells across 7 real mission seeds, counting `density_of() > 0` |
| Hard cover specifically | 9% | same sample |
| Expected terrain events per blast | **≈13** | 25 × 0.53 |
| Worst-case terrain events per blast | 25 | every cell in footprint destructible |
| Canonical bytes per `terrain_damaged` event | **277** | `stableStringify` of a representative projected event |
| Canonical bytes per `blast_resolved` event | 198 | same |
| Contract event cap (`MAX_EVENTS`) | 1,024 | `tools/repro-bundle.mjs` |
| Contract byte cap (`MAX_REPRO_BYTES`) | 128,000 | same |
| Baseline events in a real mission, no grenades | 121–172 | four recorded evidence packs |

### The binding constraint is bytes, not events

This is the part that matters and the part that was initially reported wrongly.

1,024 terrain events would occupy **283,648 bytes** — more than double the 128,000-byte
cap. The byte cap therefore binds first, at **462 terrain events**.

| Scenario | Grenades before the event cap | Grenades before the **byte** cap |
|---|---:|---:|
| Worst case, 25 events per blast | 40 | **18** |
| Measured terrain, ~13 events per blast | 78 | **35** |

An earlier note in the bugfix loop said "roughly 40 grenades". That figure came from the
event cap alone and is wrong by better than a factor of two. **The real ceiling is
about 18 grenades in a worst-case mission and about 35 in a typical one**, before
subtracting the 121–172 events a mission already spends on movement, damage, decisions,
and turns.

Correcting for that baseline, the usable terrain budget is roughly 420 events, or
**~16 worst-case grenades**.

### Failure mode

`createReproArtifact` throws. It fails **closed** — no invalid or truncated artifact is
produced — which is the correct safety property and was designed in.

It is also **silent from inside the game**. Nothing in play, in the HUD, or in the
extraction indicates that a mission has crossed the threshold. The mission completes
normally, the extraction applies normally, and only a later attempt to build a
reproduction bundle discovers that this mission is not reproducible. The information
arrives at the wrong end of the pipeline.

---

## 2. Why this is not a grenade problem

The grenade is the first mechanic that made the shape visible. The shape is general.

### 2.1 Player actions and world deltas scale differently

- **Player actions** grow with turns: O(turns × units × actions-per-turn). Bounded by
  the action economy — base-10 AP caps what a unit can do per turn by construction.
- **World-state deltas** grow with the *area of effect* of those actions, multiplied by
  the *density of stateful cells* in that area. Nothing caps this. One action can emit
  dozens of deltas.

The ratio that matters is **deltas per decision**. For a rifle shot it is 0 or 1. For a
radius-2 grenade on 53%-destructible terrain it is ~13. The action economy limits
decisions; it does not limit their consequences.

Any mechanic that widens area or adds stateful cells multiplies the same coefficient:

| Mechanic | Deltas per decision | Notes |
|---|---:|---|
| Single-target fire | 0–1 | current baseline |
| Radius-2 blast | ~13 | measured |
| Radius-3 blast | ~26 | 7×7 × 0.53 |
| Fire or gas propagation | unbounded per turn | spreads without a new decision |
| Structural collapse | unbounded | one hit can cascade |
| Crowds | ×units | per-unit deltas from one effect |

**Propagation is the qualitative break.** A blast is bounded by its radius. Fire that
spreads emits deltas on turns when the player did nothing at all, which severs the last
link between decisions and record size.

### 2.2 The ledger is being asked to do two incompatible jobs

The replay ledger currently serves as:

1. **an evidence trail** — auditable proof of what happened, reviewable by a human,
   bounded so that review is feasible and so that the artifact can be transported,
   hashed, and compared;
2. **a candidate reproduction input** — the record from which a result could later be
   re-derived.

These want opposite things. Evidence wants *small and legible*. Reproduction wants
*complete*. The 128,000-byte cap is right for the first job and arbitrary for the
second.

The project has been honest about this boundary: M04 explicitly does **not** claim
Godot mechanical re-simulation, and records that the extraction carries no authoritative
mechanical state hash. That honesty is what makes the tension visible rather than
fatal — but the tension is unresolved, not absent.

### 2.3 The standard trade, and why neither pole is free

- **Input-replay** — record seed and inputs only, re-simulate to recover state. Tiny
  artifacts, size independent of world churn. Requires bit-exact determinism across
  versions, platforms, and floating-point behaviour. Any engine upgrade or refactor
  invalidates every stored replay. This project has three clients in view (Godot native,
  Godot Web, and future implementations) and has already declined to claim cross-platform
  state equivalence.
- **State-delta logging** — record what changed. Robust to non-determinism and to
  engine change, verifiable without re-running anything. Size grows with churn, which is
  exactly the wall documented here.
- **Snapshot plus delta** — periodic authoritative state hashes with deltas between
  them. Bounds growth and enables verification without full re-simulation, at the cost
  of defining a canonical state hash — which is precisely the piece M04 records as
  missing.

The current design is delta logging without snapshots. The measured ceiling is the
predictable consequence.

### 2.4 Compression is a deferral, not a solution

The events are highly redundant: `material_before`/`material_after` are drawn from three
values, coordinates are small integers, and a blast's cells are contiguous. A
run-length or dictionary encoding would plausibly cut 277 bytes to well under 100,
raising the ceiling by 3–4×.

That buys one radius increment or one propagating mechanic. It does not change the
scaling, and it costs the property that makes the current artifact valuable: a human can
read it. Canonical, legible JSON is why tampering is detectable by inspection and why
the digest is meaningful to a reviewer.

### 2.5 Where it touches the wider federation

- **Interoperability.** If another product verifies a Battle/Star.SOL replay, the
  artifact is a wire format between sovereign products. Its size cap is a protocol
  constraint, not a local preference, and raising it is a multi-repository decision.
- **Privacy.** Every field the contract excludes for privacy also reduces
  reproducibility. Terrain deltas are the first case where the excluded-or-capped data
  is *mechanically* voluminous rather than personally sensitive — a different axis of
  the same tension.
- **Anchoring and settlement.** If a replay digest is ever anchored externally, artifact
  size becomes a recurring cost, and a cap becomes an economic parameter rather than an
  engineering one.
- **Agentic development generally.** Evidence packs must be small enough for a human or
  a reviewing agent to actually check. Richer simulation produces more evidence than can
  be reviewed. There is an information-theoretic floor: a bounded artifact cannot fully
  represent an unbounded process, so what to *discard* becomes a first-class design
  decision rather than an implementation detail.

---

## 3. Options, with what each actually costs

Recorded so the decision can be made deliberately. **None is implemented.**

### Option A — raise the byte cap

Terrain events are small. Raising `MAX_REPRO_BYTES` to, say, 512,000 moves the ceiling
to roughly 140 worst-case grenades.

*Costs:* the cap exists to keep artifacts transportable, reviewable, and cheap to hash
and compare. It is part of a published contract, so raising it is a contract change that
other consumers must accept. It also does not change the scaling — it relocates the wall.

### Option B — record only cover-class changes

Emit `terrain_damaged` only when a cell's cover class actually changes (hard→soft,
soft→rubble, or destroyed), letting intermediate integrity ticks be implied by the
`blast_resolved` aggregate.

*Effect:* roughly a 3–5× reduction, since most hits shave integrity without crossing a
threshold.

*Costs:* the ledger becomes **lossy about how a wall came down**. It could no longer
answer "how much did this specific shot contribute", which is exactly the kind of
question an audit trail exists to answer. It changes what the record *means*, which is
why it was not done unilaterally.

### Option C — aggregate per blast

One event carrying the affected cells and their transitions, instead of N events.

*Effect:* ~13 events become 1, at maybe 3–4× the bytes of a single event — a large net
win.

*Costs:* breaks the current invariant that every event is one atomic, independently
ordered record. The ledger-order validator, the strict per-event allowlist, and the
projection all assume one event per fact.

### Option D — snapshot plus delta

Introduce an authoritative terrain-state hash per turn; keep deltas only within a turn.

*Effect:* bounds growth at O(turns) instead of O(churn).

*Costs:* requires defining and stabilising a canonical mechanical state hash — the piece
M04 explicitly records as not yet existing. This is the principled fix and the largest
one.

### Option E — surface the limit in play

Independent of the above: report remaining ledger budget in the extraction, and warn
when a mission crosses the threshold, so the information arrives while the player can
still act on it.

*Effect:* does not raise the ceiling; removes the silence, which is the worst property
of the current failure.

**If exactly one thing is done, E is the cheapest honest improvement, because it turns a
silent limitation into a visible one.**

---

## 4. What is true today

- Full fidelity is retained. Every terrain change is recorded.
- The artifact fails closed. No truncated or invalid bundle can be produced.
- A mission that exceeds the budget still plays, still extracts, and still applies to
  the campaign correctly. Only reproduction-bundle creation is affected.
- No checked-in reproduction artifact currently contains a terrain event, because the
  checked-in pack predates the mechanic. The contract supports them; nothing exercises
  them yet.
- The limit is **~16–18 worst-case grenades**, or **~35 typical**, per mission.

## 5. How to re-derive these numbers

```bash
# bytes per canonical event, and which cap binds
node -e 'import("./tools/repro-bundle.mjs").then(m => { /* stableStringify a sample event */ })'

# destructible density across real mission seeds
Godot --path game --headless --script res://tests/_dens.gd   # see this document's history

# baseline events per mission
node -e 'JSON.parse(readFileSync("evidence/playtests/<pack>/playtest-report.json")).ledger'
```

The density probe was a throwaway script and was deleted after measuring; the figures
are reproducible from `WorldBuilder.generate_cells` and `Ballistics.density_of` over the
seeds listed in section 1.

## 6. Open questions worth a paper

1. Is there a principled bound on **deltas per decision** that a simulation should
   respect to stay auditable, and can it be derived from the action economy rather than
   chosen?
2. Can an evidence artifact be *provably sufficient* for a stated claim while remaining
   bounded — that is, can "what may be discarded" be derived from the claim instead of
   guessed?
3. For a federation of sovereign products exchanging replays, who owns the size cap, and
   what happens when one product's simulation outgrows another's verifier?
4. Does the honest answer differ for **evidence** and for **reproduction**, and should
   they therefore be two artifacts rather than one? The current design's difficulty may
   be that it has one artifact doing both jobs.
