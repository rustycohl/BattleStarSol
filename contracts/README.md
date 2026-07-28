# BattleStarSol contracts

This galaxy keeps tested local copies of every public contract it implements:

- `galaxy-message.schema.json` — shared transport-neutral envelope `1.x`;
- `battlestar-deploy.schema.json` — strategic deployment input;
- `xcommand-extraction.schema.json` — tactical mission-result output; and
- `examples/` — canonical messages at the actual browser/Godot boundary.

The shared envelope copy is pinned from the GZG-NOW contract module. A later
shared-repository change cannot silently alter this Page at runtime.

The browser implementation is `game/web/bridge.js`; the Godot implementation
is `game/scripts/PayloadContract.gd` and `game/scripts/PayloadBridge.gd`.
Standard messages are emitted first. Historical shapes are accepted only by
explicit adapters and immediately normalized.
