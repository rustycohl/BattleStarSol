# M04-001 Bounded Reproduction and Clean Strategic Re-import

## Result

PASS for the declared M04 supported portion.

The authoritative atomic PASS pack
`evidence/playtests/20260729T104417824Z-b0e26ed0` now produces one strict
`gzg.battlestar.repro/1.0` artifact. A clean in-memory BattleStarSol profile
accepts the artifact's reconstructed standard extraction message, reproduces
the declared strategic result and resource delta, and rejects the duplicate
import as already applied.

This is deliberately not a claim that the Godot engine re-simulated the
ordered action ledger. The current pre-alpha extraction emits no authoritative
mechanical state hash. The artifact records both limitations explicitly.

## Contract and privacy boundary

The reproduction contract is fail-closed:

- canonical JSON rejects undefined, non-finite, non-JSON, and non-plain values;
- action records are capped at 256, event records at 1,024, and canonical
  artifact content at 128,000 UTF-8 bytes;
- all object keys are allowlisted and unknown or sensitive fields are rejected;
- actor and squad names are removed;
- A.T.L.A.S. return state, map coordinates, browser storage/profile data,
  console lines, screenshots, URLs, and filesystem paths are excluded;
- the current version accepts the known privacy-safe `Proving Ground`
  scenario and empty result loot only;
- source evidence must be a finalized PASS pack whose complete physical file
  set is covered by `SHA256SUMS`;
- unmanifested files, duplicate manifest routes, symlinks/junctions, digest
  changes, identity changes, and oversized inputs fail closed.

The artifact contains product/contract/generator/rules versions, served PCK
identity, pseudonymized deployment state, seed, five ordered actions, thirty
ordered events, result, source-pack provenance, equivalence declaration, and
two SHA-256 digests.

## Authoritative artifact

- Path:
  `evidence/reproductions/20260729T104417824Z-b0e26ed0/battlestar-repro.json`
- File bytes: 16,755
- Canonical bytes: 9,012
- File SHA-256:
  `e895bfbb8bc6dc8d506bafd3293a08c5782061878680b53b72eb4cfdcaedf0d0`
- Artifact digest:
  `05fc6100c000088e02d11396edf79f183f152c22f3f4523b2f56408ab914a628`
- Mechanical-scope digest:
  `d830f0e8944e6614cd2e630b7a70a8756f5023dbe0e9fbf9ca4bb5f4e218f0f2`
- Source `SHA256SUMS` digest:
  `a6b37fba1333c907e2904c12a1efe2cf2593bfaeb091d6f3de57e36bb1a753ff`
- Served tactical PCK digest:
  `e5e312c0676f156ebd28ff564c40d6254104ab9808eb29127dd1c940aa00c5ca`

The artifact digest covers the canonical artifact except its own digest field.
The mechanical-scope digest covers schema, product/version/platform, served
PCK identity, normalized deployment, ordered replay, and declared result. It
excludes wall-clock/run provenance and does not masquerade as a Godot state
hash.

## Clean strategic re-import

The standalone verifier reconstructed an `xcommand.extraction` galaxy message
and passed it through the existing `BSS_BRIDGE.normalizeExtraction` and
`BSS_BRIDGE.applyExtraction` boundary.

| Check | Result |
|---|---|
| Outcome | `SUCCESS` |
| Seed | `1167583760` |
| Survivors | `3` |
| Gains | neural `25`, capital `301`, alloys `0`, loot `[]` |
| Resources before | neural `50`, capital `25000`, alloys `100` |
| Resources after | neural `75`, capital `25301`, alloys `100` |
| First import | changed `true` |
| Duplicate import | changed `false` |
| Final mission count | `1` |

## Verification

| Gate | Result |
|---|---|
| Focused M04-B tests | PASS, 12/12 |
| Bridge + atomic evidence + M04-B tests | PASS, 32/32 |
| Standalone artifact verify/import command | PASS |
| New module syntax | PASS |
| Existing package syntax gate | PASS |
| Deterministic regeneration matches checked-in artifact | PASS |
| Tampered result/digest rejection | PASS |
| Unknown and sensitive-field rejection | PASS |
| Non-finite and oversized-ledger rejection | PASS |
| Unmanifested-file rejection | PASS |
| Symlink/junction rejection | PASS |
| Negative pack rejected as authoritative source | PASS |
| Clean strategic import and duplicate idempotence | PASS |

Commands:

```text
node tools/repro-bundle.mjs verify evidence/reproductions/20260729T104417824Z-b0e26ed0/battlestar-repro.json
node --test tests/bridge.test.mjs tests/playtest-evidence.test.mjs tests/repro-bundle.test.mjs
node --check tools/repro-bundle.mjs
npm.cmd run check
```

## Source identities

| File | SHA-256 |
|---|---|
| `tools/repro-bundle.mjs` | `48f25a039898f19423611f73982b1552adbb32d8af56613e6d0a4cd3b53c66f3` |
| `contracts/battlestar-repro.schema.json` | `73c0700ec56917001a054941eac7f94905892e54ec6f0cc0b029c3074cd587a5` |
| `tests/repro-bundle.test.mjs` | `61f613fa71122b8756a0d9d2166ad2c2312b4fe4ede5f23f3f40b2938ea1be0f` |
| authoritative reproduction JSON | `e895bfbb8bc6dc8d506bafd3293a08c5782061878680b53b72eb4cfdcaedf0d0` |

## Remaining boundary

M04 is complete for the release contract's declared supported portion:
deployment/identity validation, canonical bounded ledger/result integrity,
strategic outcome reproduction, and duplicate-import idempotence.

Godot mechanical re-simulation, a true initial/final mechanical state hash,
and native/Web cross-platform state equivalence remain later deterministic-core
work. They are not silently promoted into this M04 result.
