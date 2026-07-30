# Pre-alpha `.02` injection ledger

This ledger translates the `.02` working codebase into auditable, reversible
modules for later injection into the known-good BattleStarSol repository.

## Boundary

- Source work line: `C:\SOL\BattleStarSol-prealpha-02`
- Source branch: `prealpha-02`
- Pinned base: `55ecad27bf83c56225a33dc20a62a4d305f6bc89`
- Target: the independent BattleStarSol product repository
- Expected target HEAD at injection:
  `55ecad27bf83c56225a33dc20a62a4d305f6bc89`
- Target promotion branch: `promotion/prealpha-02`
- Default operation: audit/dry run
- Mutating operation: explicitly pass `-Apply`; mechanically blocked while
  any required module is incomplete or `release.allow_apply` is false

The public/main codebase remains untouched during `.02` development.

## Baseline evidence — 2026-07-28

| Gate | Result | Evidence |
| --- | --- | --- |
| Source commit | pass | exact HEAD `55ecad27bf83c56225a33dc20a62a4d305f6bc89` |
| Source branch | pass | `prealpha-02` |
| Push isolation | pass | `upstream` push URL is `DISABLED` |
| Worktree | pass | clean before contract creation |
| Node release gate | pass | 15/15 |
| Node syntax | pass | bridge and server parse |
| Static Godot verifier | pass | required files, JSON, resources, RNG, and package boundary |
| Godot `TestRunner` | pass | inherited headless suite |
| Godot `PlaytestRunner` | pass | 147 checks in 1,686 ms |

Known inherited diagnostics remain the same dummy-renderer/font RID cleanup,
Windows certificate-store, scan-abort, and forced-shutdown ObjectDB/resource
warnings. Both suites exit successfully. They are evidence, not reclassified
as fixes.

## Module register

| ID | Module | State | Injection unit | Gate |
| --- | --- | --- | --- | --- |
| M00 | Isolation, contract, promotion guard, inherited baseline | complete | introducing commit(s) after pinned base | clean baseline and dry-run guard |
| M01 | Guided Proving Ground | validation pending | working-tree module commit | 192 automated checks pass; live browser smoke blocked by localhost policy |
| M02 | First-turn clarity and status truth | validation pending | working-tree module commit | 204 automated checks and Web export pass; live browser evidence pending |
| M03 | Cover-seeking and simple-flanking Agents | planned | pending | golden AI behavior coverage |
| M04 | Bounded deterministic repro artifact | planned | pending | clean-checkout import/repro |
| M05 | Narrow viewport and interaction | planned | pending | declared viewport/accessibility matrix |
| M06 | Release decision and acceptance evidence | planned | pending | all local, clean-clone, Web, workflow, and public gates |

### Superseding SOL recovery register — 2026-07-29

The table above remains the original 2026-07-28 work-line record. The recovered
SOL tree does not inherit its Git injection identity and has not been promoted.
Current module truth is:

| ID | Current SOL state | Current gate |
|---|---|---|
| M00 | complete | archive/commit/tree/file-count provenance and baseline tests pass |
| M01 | complete in SOL | reconstructed source plus atomic live 6/6 pass |
| M01-004 | complete | AP-zero End Turn recovery and refreshed affordable path pass |
| M01-005 | complete | camera/viewport synchronized observation coordinates pass |
| M02 | revalidated in combined source | static verifier, TestRunner, and PlaytestRunner 261/261 pass |
| M03 | headless golden complete; live rationale open | 12 deterministic cover/flank checks pass; dedicated live standoff still required |
| M04-A | atomic capture complete | authoritative PASS pack `20260729T104417824Z-b0e26ed0`; clean re-import open |
| M05 | active | viewport overlap and accessibility matrix |
| M06 | gated | local RC only after prior gates; public/Git remain owner-controlled |

`release.allow_apply` remains false. No line in this addendum authorizes
injection, Git mutation, public release, or manifest relabeling.

The introducing commit for M00 is resolved from Git history with:

```text
git log --oneline -- docs/PREALPHA-02-RELEASE-CONTRACT.md
```

## Promotion protocol

1. Finish a module and its tests.
2. Update this ledger and `prealpha-02-manifest.json`.
3. Commit the module without unrelated files.
4. Run the promotion guard without `-Apply`.
5. Keep `release.allow_apply` false until M00–M05 and all pre-promotion gates
   pass.
6. Back up both repositories and record their exact heads.
7. Set `state` to `release_candidate`, set `release.allow_apply` to true, and
   commit the release-decision record.
8. Run the guard with `-Apply` against the exact expected target.
9. Re-run all gates in the promotion branch.
10. Push only the promotion branch, review the diff, deploy, and public-smoke.
11. Merge/tag only after the public smoke is clean.

If the target moved, a module is incomplete, a changed path is outside the
allowlist, either worktree is dirty, a test fails, or a merge commit appears
in the injection range, promotion stops without modifying the target.

### 2026-07-28 — M01: guided Proving Ground

- intent: teach the real Base-10 tactical loop without creating a parallel
  tutorial ruleset;
- source commit(s): resolve with
  `git log --oneline -- game/scripts/TutorialDirector.gd`;
- files: tutorial director, Main integration, tactical objective panel,
  deterministic target lane, strategic/browser objective payloads, tests,
  status, and controls;
- inputs: accepted `ActionRouter` actions plus resolved `GameState` events;
- outputs: six visible guidance steps and replay-recorded step transitions;
- invariants: no AP, movement, visibility, targeting, faction, or extraction
  bypass; two targets remain zero-AP;
- fallback: no nearby cover requires Brace and explains when Take Cover
  appears;
- review: corrected Syndicate-friendly tutorial targets; fixed the deferred
  End Turn test race; direct non-isolated Godot invocation reproduced the
  documented engine crash and the isolated wrapper remained authoritative;
- tests: Node 17/17 and syntax pass; static pass; `TestRunner` pass;
  `PlaytestRunner` 192 checks pass; matching Web export rebuilt;
- known limits: in-app browser policy rejected the localhost origin and
  forbids a browser-surface workaround, so visual/full-loop browser evidence
  is still required;
- backup: included in the next `.02` bundle checkpoint;
- promotion status: blocked; manifest state is `validation_pending`.

### 2026-07-28 — M02: first-turn clarity and status truth

- intent: make the opening tactical state legible without transient hints or
  prior documentation;
- source commit(s): resolve with
  `git log --oneline -- game/scripts/TacticalUI.gd`;
- files: faction presentation vocabulary, tactical status/help layer, input
  handling, tests, controls, status, and tactical architecture docs;
- inputs: active turn/faction, active human pilot, current AP, authoritative
  action availability, and the fixed three-faction phase order;
- outputs: persistent faction/turn, pilot/AP, legal-action guidance, core
  costs, End Turn consequence, extraction route, and F1/Tab help;
- invariants: serialized faction IDs remain `0/1/2`; canonical and legacy
  payload aliases continue to parse; resolver legality and AP costs are not
  duplicated or overridden by presentation;
- fallback: advanced mobility and Remotes remain available behind the explicit
  developer boundary but are hidden from the core dock by default;
- review: restored the previously unmounted hostile-count label and corrected
  the documented-but-missing F1/Tab help surface;
- tests: static pass; `TestRunner` pass; `PlaytestRunner` 204 checks pass,
  including all faction aliases and first-turn surfaces; matching Godot 4.7.1
  release Web export rebuilt;
- known limits: live browser interaction evidence is still required;
- backup: included in the next `.02` bundle checkpoint;
- promotion status: blocked; manifest state is `validation_pending`.

## Entry template

Each accepted module appends:

```text
### YYYY-MM-DD — Mxx: module name
- intent:
- source commit(s):
- files:
- inputs:
- outputs:
- invariants:
- fallback:
- review:
- tests:
- known limits:
- backup:
- promotion status:
```
