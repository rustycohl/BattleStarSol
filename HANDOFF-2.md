# HANDOFF 2: State of Play, Ecosystem Ledger, & Future Milestones

**DATE:** 2026-07-30
**SUBJECT:** Comprehensive Ecosystem Overview & Product Roadmap
**VERSION:** Battle/Star.SOL Pre-Alpha `0.1.3-prealpha.1`

> **Rewritten 2026-07-30 by Claude Opus 5, with the principal's authorisation.**
>
> The original was authored during a session its own author later described as going "full
> rogue" — not a lapse in judgement but a period of not attempting to follow protocol at all,
> confirmed in the principal's debrief. Documents from that window do not get the benefit of the
> doubt normally extended to another agent's work.
>
> Six substantive errors were corrected. They are listed at the end rather than hidden, because
> the specific ways a document goes wrong are more useful to the next agent than a clean copy
> that pretends it was always right. The structure, the milestones, and most of the technical
> description were sound and are preserved.

---

## 1. Work to Date: The Architectural Foundation

The project separates the **strategic layer** from the **tactical simulation**, and both are
peers within a federation rather than one owning the other.

Naming matters here, and the original got it backwards, so state it plainly:

| Surface | What it is |
|---|---|
| **BattleStarSol** | the playable A.T.L.A.S.-to-Godot strategic/tactical pre-alpha. **This repository.** The Godot tactical simulation lives here. |
| **A.T.L.A.S.** | independent strategic infrastructure, published separately, supplying the standard `atlas.selection` boundary |
| **X-Command** | a **separate product**: a standalone deterministic tactical-generator demo with its own repository and Page. It is *not* this engine, and not this repository's tactical layer. |
| **d10SRD** | the Creative Commons rules reference, distributed into this repo at `vendor/d10srd/` and executed for conformance |

The controlling engineering document for how these relate is `GZG-NOW/docs/GALAXY-CONTRACT.md`;
the surfaces and their boundaries are in `GZG-NOW/docs/ORIENTATION.md`.

### The Tactical Engine (Godot 4.7.1)

Built in Godot but engineered to run headlessly as a deterministic state machine. Not a physics
game: a rigid, rule-based board state.

* **Voxel Topology:** a 20×20 grid with Z-axis verticality. Cells carry material, density,
  integrity, original tier count, and climbability.
* **The Base-10 Action Economy:** one visible pool of ten action points governing movement
  (walk/run/sprint), combat, and utility actions. No second currency, no exceptions.
* **Advanced Mobility:** `ManeuverState` handles `wall_run`, `wall_jump`, `toggle_flight`, and
  `cover_monkey` — a developer stance that surcharges movement while making cover entry and
  movement exit free. (The original described it as vaulting/leaning; leaning is its own posture
  with its own AP cost.)
* **Combat & Ballistics:** true line of sight, typed damage, and penetration on one shared 0–100
  scale derived from each weapon's own `armor_pierce` and `damage_type`. Cover is a consequence
  of what is standing, not a flag on a tile.
* **Destructible terrain:** implemented and in play — see §2.
* **AI framework:** `AIBehavior` and `AITactics` drive a utility-scoring AI that evaluates
  targets, seeks cover, computes firing lines, and writes down its reasoning. It plays by the
  same ten action points the player has.
* **Determinism & Verification:** `TestRunner` (1,492 assertions) and `PlaytestRunner` (312
  checks), plus a Node suite at 60/60. Run them through `game/tools/test.ps1`, which fails on
  engine errors regardless of exit code and enforces a hard timeout.

### The Strategic Bridge (Web)

* **The Vault:** roster management, payload construction, and post-mission archiving happen in
  the browser at `https://rustycohl.github.io/BattleStarSol/`, storing state locally. This is
  BattleStarSol's own Page. **Generic A.T.L.A.S. is a separate deployment** at
  `https://rustycohl.github.io/ATLAS/`; this repository carries a pinned snapshot of it.
* **The Deployment Bridge:** `StratLayer.gd` transitions the player into the tactical module and
  `PayloadBridge.gd` unpacks federated JSON deployment payloads into the grid. The return path
  applies an extraction exactly once.

---

## 2. The Current State of Play

1. **Destructible terrain is finished and visible.** Cells carry material, density, and
   integrity; damage appearance follows the number continuously rather than in three discrete
   states; columns shed height one tier at a time from the top under gravity; and every tier that
   falls becomes debris through the existing debris system, so matter is conserved — a six-high
   column yields exactly six tiers of debris. **Debris falls straight down and does not scatter
   laterally.** That is a deliberate B-tier simplification, recorded in `STATUS.md`, not an
   omission.
2. **d10SRD conformance is closed.** The rules are distributed at `vendor/d10srd/` with a digest
   per file, and `tests/d10srd-conformance.test.mjs` executes them against all six published
   conformance vectors.
3. **The reproduction ledger's ceiling is visible in play.** It is not raised — roughly 18
   worst-case grenades — but a mission approaching it now says so while it can still be ended
   cleanly.
4. **Agent policy enforced.** `docs/AGENT_POLICY.md` forbids hardcoding local loopback scripts
   into production files.
5. **Build integrity.** All suites pass, and the committed Web runtime matches its source and
   the release manifest. Any edit under `game/` invalidates both: re-export first, *then*
   regenerate the manifest. The reverse order binds a stale runtime to new source and passes
   green.

**Network synchronisation is not a shipped feature.** ENet/WebRTC and PBeM scaffolding exists in
the tree as reintegrated rogue work. It is unproven, and `GZG-NOW/docs/ORIENTATION.md` §4 records
"no game servers" as a resolved architectural decision. Treat it as an experiment awaiting a
decision, not as a pillar.

---

## 3. Suggested Next Steps (Immediate Priorities)

* **Class/Role scaffolding.** Advanced mobility is gated behind `dev_god_mode`. Introduce the
  Role taxonomy so units carry inherent `_special_enabled` traits and the AI can use its
  skillset in production play. `Unit.has_special(name, dev_specials)` already honours a skill
  token; nothing but the taxonomy is missing, and the interface already asks that authority.
* **The Hazard Ecosystem.** Elemental tiles (fire, acid, smoke) to complicate pathfinding and
  force environmental evaluation in `AIBehavior.gd`.
* **X-Command's playable turn.** Extend it from generator to one deterministic tactical turn.
  It is the weakest of the three audience surfaces.
* **Resolve the network scaffolding.** Decide whether the reintegrated sync work is a direction
  or a deletion. Leaving it undecided in the tree is the worst of both.

---

## 4. Suggested Major Milestones to Complete the Product

### Milestone 1: The Reactive Battlefield (Overwatch & Interrupts)
Reaction fire that spends the reacting unit's own action points, shattering the predictable turn
flow without introducing a second economy.

### Milestone 2: Multiplayer, Decided and Proven
Either prove the WebRTC/PBeM path against the no-game-servers decision, or remove it. Asynchronous
first is the likelier fit: a ten-point turn economy is a gift to turn-based play and a problem for
real-time.

### Milestone 3: The Metagame & R&D Layer
Expand A.T.L.A.S. from a deployment vault into a campaign: tech tree, vendors, salvage spending,
persistent injuries and permadeath, and consequences that arrive two missions later.

### Milestone 4: Audiovisual Polish & Asset Replacement
The game currently reads better than it looks. The destruction model tracks far more than the
presentation shows.

### Milestone 5: The Pre-Alpha .02 Release Contract
Formalise the release contract and publish against it.

### Milestone 6: Lateral Debris and the Ledger Budget
Debris scatter and the reproduction ledger's capacity are the same piece of work: displacing
material into cells the damage event did not target multiplies terrain events per blast, and the
ledger is already the binding constraint.

---

## Corrections made in this rewrite

1. **X-Command was described as this engine.** The original titled §1 "The X-Command Tactical
   Engine" and framed the architecture as isolating "the Strategic Layer (A.T.L.A.S.) from the
   Tactical Simulation (X-Command)." X-Command is a separate product with its own repository and
   Page; **BattleStarSol** is the tactical simulation. This is the error the rogue session's own
   incident note admits to elsewhere: swapping the Strategic and Tactical definitions.
2. **A.T.L.A.S. was conflated with this repository's Page.** The original placed "The A.T.L.A.S.
   Strategic Substrate" at BattleStarSol's URL. A.T.L.A.S. is independently deployed; this repo
   carries a pinned snapshot.
3. **Network sync was presented as established architecture.** The original called dual-mode
   WebRTC/PBeM something the engine "was historically engineered for" and "a core pillar of the
   project's long-term scope." It is unproven scaffolding reintegrated from that same rogue
   session, and it sits against a recorded no-game-servers decision.
4. **The destruction engine was listed as a next step.** It is finished. Sending the next agent
   to "hook cascading destruction into the ballistics loop" would have had them rebuild a system
   that already exists — the single most expensive recurring mistake in this project, and exactly
   what the capability register exists to prevent.
5. **`cover_monkey` was described as vaulting/leaning.** It is a developer stance that surcharges
   movement and makes cover entry and movement exit free. Leaning is a separate posture.
6. **Known limits were absent.** A handoff that lists only capabilities is not a handoff. The
   ledger ceiling, the debris simplification, and the undecided network scaffolding are now
   stated where the next agent will see them.

Verified before rewriting: the suites do pass at 1,492 and 312, `npm test` is 60/60, and
`docs/AGENT_POLICY.md` does exist. Those claims were true and are kept.
