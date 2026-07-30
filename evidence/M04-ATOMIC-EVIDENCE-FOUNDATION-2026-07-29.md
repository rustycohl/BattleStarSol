# M04 Atomic Evidence Foundation

## Finding

The preserved historical `stage/playtest/evidence` directory is not one
atomic run. Its report and extraction use different extraction IDs and ledger
counts, and its screenshots come from earlier timestamps. The historical
folder remains useful provenance, but it is not accepted as single-run proof.

The root cause is a reusable evidence directory with fixed filenames and no
run identity, cross-file identity validation, or digest manifest.

## SOL-Owned Foundation

The recovered workspace now contains a tested evidence-pack helper that:

- creates a Windows-safe run ID;
- exclusively creates `evidence/playtests/<run-id>.partial`;
- never cleans or reuses a partial or final run;
- normalizes the canonical local URL to `http://127.0.0.1:8781/`;
- requires the Battle/Star development-server response marker;
- honors an explicit valid `PW_CHROMIUM` path first and otherwise resolves an
  installed browser fail-closed;
- binds deployment message, extraction message, extraction ID, correlation ID,
  seed, and run timestamps;
- records screenshot hashes and sizes at capture time;
- writes extraction, report, and sorted `SHA256SUMS`;
- re-reads and verifies identity and every digest;
- atomically renames the partial directory only after verification.

A completed run whose game gates fail is still finalized as valid negative
evidence. A harness failure, identity mismatch, or digest mismatch remains
partial.

## Verification

| Gate | Result |
|---|---|
| Focused evidence tests | PASS, 11/11 |
| Package syntax check | PASS |
| Exclusive workspaces | PASS |
| Matching identity fixture | PASS |
| Mismatched extraction rejected | PASS |
| Screenshot tampering rejected | PASS |
| Post-finalization tampering detected | PASS |
| Negative run finalized | PASS |

This machine resolves Chrome at:

`C:\Program Files\Google\Chrome\Application\chrome.exe`

Direct Playwright launch of Chrome returned Windows `EACCES`. The authoritative
run therefore used the installed Edge executable through explicit
`PW_CHROMIUM`; the report records Edge `150.0.4078.105`. The browser-extension
session is not part of this standalone evidence foundation.

## Source identities

| File | SHA-256 |
|---|---|
| `tools/playtest/evidence-pack.mjs` | `44891d2dd588c9ca43942bf7225a353cf7bc5321586e4891c61a9e9d6bb86d7a` |
| `tests/playtest-evidence.test.mjs` | `eb7c6f05ace6069e0b10ec911bd7bc2c316b254b137ca6115e9d8b8abf4201d6` |
| `tools/playtest/run.mjs` | `b21113672a3c786c726a383fbddbd034a33cbccf017c5d96829d8a38dc7b5faf` |
| `tools/playtest/README.md` | `04ba105ab8b8acfb5ff7f2351202f9ac443bd6c57299d472cc4eebd178a65f0d` |

## Authoritative live pack

`evidence/playtests/20260729T104417824Z-b0e26ed0`

| Fact | Result |
|---|---|
| Overall required-gate result | PASS |
| Deployment/extraction | Exactly 1 / exactly 1 |
| Seed | `1167583760` |
| Outcome | SUCCESS, 3 survivors |
| Guided tutorial | PASS, 6/6 |
| Replay | 5 accepted human actions, 30 events |
| Idempotence | PASS, mission count `1 → 1` |
| Base-10 AP | PASS |
| Screenshots | 10 |
| Manifest artifacts | 12, independently verified |
| Served PCK | 261,268 bytes |
| Served PCK SHA-256 | `e5e312c0676f156ebd28ff564c40d6254104ab9808eb29127dd1c940aa00c5ca` |
| Report SHA-256 | `b6127f9101390c8614bd1ad0dd1dd476c00e8bc28b6bf2b894eb0cbcad810c02` |
| Extraction SHA-256 | `d9a6569908c1534f50dfe04a410ddc4aef7fb6f04d5f5569fc390a7c15c5ccc5` |
| `SHA256SUMS` SHA-256 | `a6b37fba1333c907e2904c12a1efe2cf2593bfaeb091d6f3de57e36bb1a753ff` |

M03 canonical rationale is observational by default because the Proving Ground
is not its required standoff scenario. This run records eleven valid ordinary
AI decisions and no cover/flank signature. `--require-m03` makes that
observation a required gate only for a purpose-built scenario.

Earlier failed and negative runs remain preserved. Harness failures stay
`.partial`; the earlier finalized M03-negative packs remain valid negative
evidence and are not the authoritative PASS pack.

## Open gate

The fresh reconstructed Web export is now captured atomically. Full M04 still
requires a supported clean-checkout re-import that reproduces the same result.
The old committed release manifest is expected to fail the
source/runtime-identity test until an owner-approved local RC re-export. It must
not be rewritten to conceal that boundary.
