# BattleStarSol as an autonomous galaxy

## Controlling rule

> one repository = one Page = one galaxy

BattleStarSol owns a complete bounded play loop. A peer outage may remove a
richer integration path, but it must not prevent this Page from loading,
explaining itself, deploying a proving-ground mission, running the tactical
engine, extracting, and recording the result locally.

Each Ground Zero galaxy is a port in the storm. It carries:

- its complete release runtime;
- its source and recoverable history;
- a pinned copy of every contract it implements;
- tests for its core behavior and public boundary;
- status, controls, provenance, license, validation, and known limits;
- a useful standalone fallback; and
- examples for every public message it accepts or emits.

No galaxy imports mutable runtime code from another Ground Zero repository.
Composition happens through versioned data. A local, immutable copy may be
embedded when the host needs a guaranteed fallback.

## BattleStarSol boundary

BattleStarSol is the themed product galaxy:

- **strategic authority:** the browser-local Battle/Star campaign profile;
- **context provider:** the bundled A.T.L.A.S. snapshot;
- **tactical authority:** the bundled Godot/xCommand simulation;
- **local persistence:** browser storage, explicitly non-network authority;
- **input:** `battlestar.deploy`;
- **output:** `xcommand.extraction`.

The standalone generic A.T.L.A.S. and X-Command repositories remain separate
galaxies. Their Pages can evolve, fail, or be replaced without changing the
minimum BattleStarSol play path.

## Standardized I/O

All cross-galaxy messages use `gzg.galaxy-message/1.0`. The outer envelope
routes and identifies the message. The inner `payload.schema` names the
capability-specific contract. Unsupported major versions and malformed payloads
are rejected; legacy inputs enter through explicit adapters and are immediately
normalized.

The repository pins the schemas under [`../contracts`](../contracts/README.md).
See [IO.md](IO.md) for message shapes and transport rules.

## Tight module loop

Every bounded change follows the same loop:

1. **Back up** the starting commit and irreplaceable source.
2. **Document** the module’s purpose, inputs, outputs, invariants, fallback,
   status, and non-goals.
3. **Implement** the smallest independently testable change.
4. **Review** the diff, provenance, license, security boundary, accessibility,
   and failure behavior.
5. **Correct** defects and rerun the relevant checks.
6. **Document again** with actual behavior, evidence, remaining limits, and
   contract changes.
7. **Push or publish:** push/deploy runnable Ground Zero **Games** products;
   publish Ground Zero **Gaming** documents under their declared Creative
   Commons terms.
8. **Smoke the public Page**, not merely the local checkout.
9. **Record** the result in this galaxy and the shared map.

A green workflow establishes only the behavior it tests. A rendered Page
establishes only that a Page rendered. Neither is evidence that the game loop
works until the live loop itself is exercised.

## Module completion record

For each module, the repository should be able to answer:

| Question | Required record |
| --- | --- |
| What was protected? | starting commit, tag, or backup location |
| What is the contract? | versioned schema and examples |
| What works alone? | fallback or local demo path |
| What was tested? | exact automated and interactive evidence |
| What remains false? | explicit limits and warnings |
| What shipped? | commit, tag, Page, or document publication |
| What changed afterward? | changelog and updated validation |

This process is part of the product architecture, not release-day paperwork.
