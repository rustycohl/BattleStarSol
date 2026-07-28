# Triple-A Framework

## 1. Contextual Mobility Grammar
Contextual mobility is one of the core pillars of the engine's Triple-A framework. The engine is not a simple top-down 2D grid dressed up in 3D models; it is a true voxel-addressable 3D environment. Consequently, movement is not limited to contiguous, flat (x, y) pathfinding.

The **Contextual Mobility Grammar** dictates that every movement action must be understood as a *verb applied to a target surface state*.
When a user targets a cell, the MovementContext resolves not just a path, but the *manner* of traversal based on geometry, unit state, momentum, and anchor points.

### Core Grammar Rules
1. **Surface Connectivity:** Moving along contiguous flat cells resolves to Walk, Run, or Sprint based on distance.
2. **Vertical Disconnects (Airborne Phase):** Disconnected navigation nodes require an *airborne phase* (Jump, Double Jump, Drop). The engine tracks z-velocity and momentum snapshots during this phase.
3. **Surface-Relative Phase (Wall Mechanics):** Interacting with a tall (Z >= 3) surface while adjacent unlocks the surface-relative grammar: Wall Run (vertical/lateral) and Wall Jump (reactionary vector away from the surface).
4. **Stance Integration:** Movement must seamlessly interpolate with Stance (Prone, Crouch, Cover Monkey). Dropping from a high ledge while crouched retains the crouched momentum profile, reducing fall damage.

### Pros, Cons, and Integrations
*   **Pros:** Creates a deeply vertical, expressive tactical sandbox reminiscent of high-mobility arena shooters, but paced for tactical strategy.
*   **Cons:** Pathfinding complexity increases exponentially. Resolving AI behavior for 3D Wall Jumps is computationally expensive compared to 2D A*.
*   **Integrations:** Fully integrated into Main.gd path resolution. Next steps require ensuring the AI can utilize Wall Run to flank.

---

## 2. Tactical Depth, Determinism, and RNG

### Tactical Depth
Tactical Depth in this engine is derived from the **Armor Penetration Contract** and the **Cover Matrix**.
*   **Armor Contract:** Heavy armor outright ignores low-tier kinetic weapons but melts to thermal/rail penetration.
*   **Cover Matrix:** Full Cover (-2 Damage) and Half Cover (-1 Damage) physically block projectiles. Crouching behind Half Cover upgrades it to Full Cover.
*   **Pros:** Prevents stat-checking (e.g., higher level unit always wins) by enforcing rock-paper-scissors gear mechanics.
*   **Cons:** Can be opaque to new players if tooltips are not explicitly clear. (Solved by the [A: X] UI tags and updated tooltips).

### Determinism
The engine is strictly deterministic. A specific seed, generator_version, and rules_version will *always* result in the exact same procedural level, the exact same item scatter, and the exact same combat rolls.
*   **Integrations:** Random number generators are split between sim_rng (authoritative gameplay) and visual_rng (sparks, blood splatter, idle animations). Visual choices **never** advance the sim_rng.

### RNG (Random Number Generation)
We rely on RNG for hit confirmation, dodge rolls (Flip/Dodge), and damage variance. However, RNG must be *constrained* by Determinism.
*   **Pros:** Ensures replays and multiplayer sync are 100% reliable.
*   **Cons:** If a developer accidentally uses randi() instead of sim_rng.randi(), the simulation desyncs silently.
*   **Integrations:** All dodge chances (target.flipping, target.dodging) strictly check main.sim_rng.randf().
