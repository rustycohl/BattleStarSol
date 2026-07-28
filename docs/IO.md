# BattleStarSol galaxy I/O

## Envelope

BattleStarSol implements the pinned
[`gzg.galaxy-message/1.0`](../contracts/galaxy-message.schema.json) envelope.
Every accepted message must have:

- the literal `gzg: "galaxy-message"` discriminator;
- a supported `1.x` envelope version;
- a stable message ID and valid dotted type;
- complete source and target metadata;
- an ISO-8601 creation timestamp; and
- an object payload with its own versioned schema name.

`correlation_id` connects an extraction to its deployment. Unknown additive
fields survive routing. Inputs from URLs, browser messages, files, and browser
storage are untrusted.

## Inputs

### `atlas.selection`

A.T.L.A.S. emits a deployable selection. BattleStarSol retains the message and
creates a deployment only after the player requests it. The embedded adapter
also recognizes the historical `channel: "atlas"` form, converts `lat/lng` to
`latitude/longitude`, and then uses only the normalized message.

### `battlestar.deploy`

The strategic layer emits
[`gzg.battlestar.deploy/1.0`](../contracts/battlestar-deploy.schema.json).
It contains:

- deterministic mission seed and rules/generator versions;
- sector, faction, three-unit squad, and objectives;
- selected A.T.L.A.S. context;
- the locally available resource snapshot; and
- the A.T.L.A.S. hash needed for a return path.

The Godot `PayloadContract` unwraps this envelope, rejects unknown envelope
majors and message types, validates the deploy payload, and preserves the
message/correlation IDs.

## Output

### `xcommand.extraction`

The tactical engine emits
[`gzg.xcommand.extraction/1.0`](../contracts/xcommand-extraction.schema.json)
for victory, defeat, and emergency EVAC. The extraction includes outcome,
survivors, seed, sector, gains, contract/rules versions, timestamp, extraction
ID, and a deterministic action/event replay bundle when available.

The tactical launcher applies the mission summary before attempting its
recovery write. The browser bridge applies a message ID once, so repeated
standard and legacy copies cannot duplicate gains. The local vault retains the
most recent 100 applied IDs and 50 mission summaries. Extraction recovery
messages above 500 KB discard replay detail and loot rows while retaining
counts, gains, outcome, survivors, seed, IDs, and correlation.

## Transports

| Transport | Use | Authority |
| --- | --- | --- |
| URL `p` query | deployment into the tactical runtime; bounded to 240,000 encoded characters | untrusted input |
| `postMessage` | same-origin Atlas selection and tactical extraction | validated adapter |
| `localStorage` | browser-local recovery cache and campaign vault | local convenience |
| JSON download | durable manual deployment transfer | user-carried data |
| Godot `user://payloads` | native/local tactical payload copy | local convenience |
| optional HTTP | experimental relay hooks | no shipped authority |

The A.T.L.A.S. return hash is capped at 12,000 characters and selection fields
are allowlisted/bounded before deployment. The current composed Page uses
same-origin frames and verifies the origin when
served over HTTP(S). Direct-file mode uses a wildcard target only as a local
compatibility path. No private key, credential, or remote account token belongs
in any message or URL.

## Compatibility policy

- Additive envelope changes remain in major version `1`.
- Breaking field or meaning changes require a new major version.
- Inner payloads version independently through `payload.schema`.
- Standard messages are authoritative; legacy shapes are adapters only.
- Unknown major versions and wrong message types are errors.
- A malformed peer message never becomes a fabricated mission or fabricated
  extraction.

Canonical examples live under [`../contracts/examples`](../contracts/examples).
