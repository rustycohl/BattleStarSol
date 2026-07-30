# HANDOFF 2: State of Play, Ecosystem Ledger, & Future Milestones

**DATE:** 2026-07-30
**SUBJECT:** Comprehensive Ecosystem Overview & Product Roadmap
**VERSION:** Battle/Star.SOL Pre-Alpha `0.1.3-prealpha.1`

This document serves as the high-fidelity ecosystem ledger for future developers and AI agents. It details the true historical progression, current architectural state, and the necessary milestones required to advance the Battle/Star.SOL federated ecosystem to a complete Beta state.

---

## 1. Work to Date: The Architectural Foundation

The project has achieved a remarkable level of maturity, driven by a strict adherence to modularity and separation of concerns. The core design philosophy explicitly isolates the **Strategic Layer (A.T.L.A.S.)** from the **Tactical Simulation (X-Command)**.

### The X-Command Tactical Engine (Godot 4.7.1)
The tactical simulation is built in Godot, but explicitly engineered to run headlessly as a deterministic state machine. This is not a standard Godot physics game; it is a rigid, rule-based board state designed to sync identically across clients.
*   **Voxel Topology:** The battlefield is a 20x20 grid featuring Z-axis verticality. Cells hold material density, structural integrity, and climbability. 
*   **The Base-10 Action Economy:** A tightly balanced AP system governing movement (walk/sprint), combat (melee/ranged), and utility actions (grab, assemble, stow, swap hands).
*   **Advanced Mobility Mechanics:** The `ManeuverState` system handles complex topological traversals including `wall_run`, `wall_jump`, `toggle_flight`, and `cover_monkey` (vaulting/leaning).
*   **Deep Combat & Ballistics:** The simulation calculates true Line of Sight (LOS) and features typed damage (kinetic, energy, etc.), armor penetration gradients, and dynamic cover utilization (leaning/hunkering).
*   **AI "Rip and Tear" Framework:** The `AIBehavior` and `AITactics` scripts govern a utility-scoring AI. They dynamically evaluate targets, seek cover, calculate firing lines, and (when permitted by the `dev_god_mode` scaffolding switch) evaluate advanced mobility to flank the player. 
*   **Determinism & Verification:** The engine boasts a headless testing apparatus (`TestRunner` and `PlaytestRunner`) with nearly 1,500 assertions that run natively in PowerShell to guarantee state integrity before any visual layer is painted.

### The A.T.L.A.S. Strategic Substrate (Web)
*   **The Federated Vault:** Strategy, roster management, payload construction, and post-mission archiving happen in the browser (`https://rustycohl.github.io/BattleStarSol`). The web client stores state (mission counts, salvage, rosters) locally in a resilient pre-alpha vault.
*   **The Deployment Bridge:** The Godot `StratLayer.gd` UI seamlessly transitions the player into the tactical module, and `PayloadBridge.gd` unpacks federated JSON deployment payloads into the deterministic X-Command grid.
*   **Dual-Mode Multiplayer Sync:** The engine was historically engineered for both Live WebRTC synchronization and Asynchronous Play-by-Email (PBeM), a core pillar of the project's long-term scope.

---

## 2. The Current State of Play

As of this handoff, the codebase is in a highly stabilized state following a critical cleanup operation.

1.  **Handoff Queue Cleared:** The final structural integrations from the Opus 5 milestone have been executed. The Action Economy correctly charges AP for complex inventory swaps and stowing, and the AI heuristic successfully evaluates advanced movement (Wall Run/Flight) while strictly obeying development lock-outs.
2.  **Strict Agent Policy Enforced:** Due to previous stealth regressions caused by aggressive "vibecoding" (agents permanently bypassing production endpoints for the sake of local testing), a hard barrier has been erected. `docs/AGENT_POLICY.md` expressly forbids hardcoding local loopback scripts into production files. 
3.  **Clean Repository:** All headless tests pass natively. There are no memory leaks in the runners, and the `main` branch is fundamentally sound and ready for aggressive feature expansion.

---

## 3. Suggested Next Steps (Immediate Priorities)

For the next agent or human developer picking up this repository, the immediate next steps should focus on capitalizing on the structural stability to implement pending core mechanics.

*   **Implement Proper Class/Role Scaffolding:** Currently, advanced mobility (Flight, Wall Run, Remotes) is universally gated behind `dev_god_mode`. The immediate next step is to introduce the overarching Role/Class taxonomy so units possess inherent `_special_enabled` traits organically, allowing AI to utilize their specific skillsets in standard production play.
*   **Voxel Destruction Engine:** The terrain materials have density and integrity properties, but the cascading destruction logic (darkening, shedding height, turning into lootable debris under fire) needs to be formally hooked into the ballistics loop.
*   **The Hazard Ecosystem:** Introduce elemental tiles (fire, acid, smoke) to complicate pathfinding and force the AI to evaluate environmental danger in `AIBehavior.gd`.

---

## 4. Suggested Major Milestones to Complete the Product

To transition Battle/Star.SOL from a robust Alpha simulation to a feature-complete Beta product, the following macro-level milestones must be conquered:

### Milestone 1: The Reactive Battlefield (Overwatch & Interrupts)
The Base-10 economy currently operates on a strict turn-by-turn expenditure. We must implement **Overwatch**, allowing agents to reserve AP to interrupt opponent movement phases dynamically. This is a massive architectural shift requiring the engine to pause deterministic execution, request opponent reaction checks, and resolve concurrent states.

### Milestone 2: True Multiplayer WebRTC Validation
While the foundations exist for dual-mode sync, a comprehensive cross-client validation phase is necessary. This milestone involves spinning up two distinct browser sessions hitting the GitHub Pages endpoint, injecting a P2P payload, and successfully executing a synchronized combat loop without desyncing the determinism matrix.

### Milestone 3: The Metagame & R&D Layer
A.T.L.A.S. must be expanded from a simple deployment vault into a true strategic layer. This includes implementing the R&D tech tree, vendor interactions, salvage currency spending, and persistent squad injuries/permadeath mechanics.

### Milestone 4: Audiovisual Polish & Asset Replacement
The mathematical simulation is currently represented by minimalist, functional UI and primitive 3D shapes. This milestone focuses entirely on replacing the primitives with final rigged models, particle effects, and integrating a full dynamic soundscape via `AudioSystem.gd`.

### Milestone 5: The Pre-Alpha .02 Release Contract
Fulfilling every single requirement listed in `docs/PREALPHA-02-RELEASE-CONTRACT.md`, culminating in a finalized, bug-free, fully playable end-to-end loop that can be confidently promoted to the public branch.
