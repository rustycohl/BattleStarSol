import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const source = await readFile(new URL("../game/web/bridge.js", import.meta.url), "utf8");

function memoryStorage() {
  const values = new Map();
  return {
    getItem(key) {
      return values.has(key) ? values.get(key) : null;
    },
    setItem(key, value) {
      values.set(key, String(value));
    },
  };
}

function loadBridge() {
  const window = {};
  const context = {
    Date,
    TextDecoder,
    TextEncoder,
    URLSearchParams,
    atob,
    btoa,
    console,
    localStorage: memoryStorage(),
    location: { search: "" },
    structuredClone,
    window,
  };
  vm.runInNewContext(source, context, { filename: "bridge.js" });
  return window.BSS_BRIDGE;
}

function extractionMessage(id = "xcommand:test:1") {
  return {
    gzg: "galaxy-message",
    version: "1.0",
    id,
    type: "xcommand.extraction",
    source: {
      galaxy: "xCommand",
      version: "0.1.1-prealpha.1",
      instance: "test",
    },
    target: {
      galaxy: "BattleStarSol",
      capability: "strategic.receive-extraction",
    },
    created_at: "2026-07-28T12:00:00.000Z",
    correlation_id: "battlestar:1234:1",
    payload: {
      schema: "gzg.xcommand.extraction/1.0",
      extraction: {
        outcome: "SUCCESS",
        sector: "Contract Test",
        seed: 1234,
        survivors: 2,
        gains: {
          neural: 7,
          capital: 1200,
          alloys: 3,
        },
      },
    },
  };
}

test("deployment is deterministic, versioned, and Base-10 compatible", () => {
  const bridge = loadBridge();
  const profile = bridge.defaultProfile();
  const options = {
    created_at: "2026-07-28T12:00:00.000Z",
    id: "battlestar:contract-test:1",
  };
  const first = bridge.createDeployMessage(null, profile, options);
  const second = bridge.createDeployMessage(null, profile, options);

  assert.deepEqual(first, second);
  assert.equal(first.type, "battlestar.deploy");
  assert.equal(first.payload.schema, "gzg.battlestar.deploy/1.0");
  assert.equal(first.target.capability, "tactical.deploy");
  assert.equal(first.payload.deploy.squad.length, 3);
  assert.equal(first.payload.deploy.seed, second.payload.deploy.seed);
  assert.deepEqual([...first.payload.deploy.objectives], [
    "Select the Commander",
    "Move and practice defense",
    "Complete a basic attack",
    "End turn and observe the phases",
    "Extract to strategy",
  ]);
});

test("envelope validation rejects unsupported major versions", () => {
  const bridge = loadBridge();
  const message = extractionMessage();
  message.version = "2.0";
  assert.throws(() => bridge.validateMessage(message), /Unsupported/);
});

test("envelope validation rejects non-JSON numbers and oversized URLs", () => {
  const bridge = loadBridge();
  const message = extractionMessage();
  message.payload.extraction.seed = Number.NaN;
  assert.throws(() => bridge.validateMessage(message), /non-finite/);
  assert.throws(() => bridge.fromBase64Utf8("A".repeat(240_001)), /budget/);
});

test("extraction applies exactly once to the local campaign vault", () => {
  const bridge = loadBridge();
  const profile = bridge.defaultProfile();
  const normalized = bridge.normalizeExtraction(extractionMessage());
  const first = bridge.applyExtraction(profile, normalized);
  const second = bridge.applyExtraction(first.profile, normalized);

  assert.equal(first.changed, true);
  assert.equal(second.changed, false);
  assert.equal(first.profile.resources.neural, 57);
  assert.equal(first.profile.resources.capital, 26200);
  assert.equal(first.profile.resources.alloys, 103);
  assert.equal(first.profile.missions.length, 1);
  assert.equal(first.profile.missions[0].correlation_id, "battlestar:1234:1");
});

test("legacy extraction is adapted without changing the standard output", () => {
  const bridge = loadBridge();
  const normalized = bridge.normalizeExtraction({
    channel: "battlestar",
    kind: "extraction",
    payload: {
      extraction_id: "legacy:test:1",
      outcome: "SUCCESS",
      seed: 55,
      survivors: 1,
      ts: 1785254400000,
    },
  });

  assert.equal(normalized.message.type, "xcommand.extraction");
  assert.equal(normalized.message.payload.schema, "gzg.xcommand.extraction/1.0");
  assert.equal(normalized.extraction.seed, 55);
});

test("UTF-8 deployment state survives the URL adapter", () => {
  const bridge = loadBridge();
  const value = JSON.stringify({ sector: "São Paulo / 東京", callsign: "ÉCHO" });
  assert.equal(bridge.fromBase64Utf8(bridge.toBase64Utf8(value)), value);
});

test("profile storage is bounded and recoverable", () => {
  const bridge = loadBridge();
  const storage = memoryStorage();
  const profile = bridge.defaultProfile();
  profile.missions = Array.from({ length: 70 }, (_, index) => ({ id: index }));
  profile.applied_extractions = Array.from({ length: 120 }, (_, index) => `id-${index}`);
  bridge.saveProfile(profile, storage);
  const restored = bridge.loadProfile(storage);

  assert.equal(restored.missions.length, 50);
  assert.equal(restored.applied_extractions.length, 100);
});

test("adaptive HUD preferences round-trip through the Commander profile", () => {
  const bridge = loadBridge();
  const storage = memoryStorage();

  // A fresh profile carries the authored HUD: every surface open and opaque.
  const fresh = bridge.readHudPreferences(storage);
  assert.equal(fresh.schema, "gzg.battlestar.hud/1.0");
  for (const key of ["status", "feed", "tutorial", "dock"]) {
    assert.equal(fresh.surfaces[key].opacity, 1);
    assert.equal(fresh.surfaces[key].parked, false);
  }

  const written = bridge.writeHudPreferences({
    surfaces: {
      status: { opacity: 0.5, parked: true },
      feed: { opacity: 0.75, parked: false },
    },
  }, storage);
  assert.equal(written.surfaces.status.opacity, 0.5);
  assert.equal(written.surfaces.status.parked, true);
  assert.equal(written.surfaces.feed.opacity, 0.75);

  // Preferences survive a reload and do not disturb the rest of the profile.
  const reloaded = bridge.loadProfile(storage);
  assert.equal(reloaded.hud.surfaces.status.parked, true);
  assert.equal(reloaded.callsign, bridge.defaultProfile().callsign);
  assert.equal(reloaded.deployment_count, 0);
});

test("adaptive HUD preferences fail closed on hostile or absent values", () => {
  const bridge = loadBridge();

  // Out-of-range, non-finite, unknown, and wrong-typed values all fall back to
  // the authored HUD rather than reaching the runtime.
  const clamped = bridge.normalizeHudPreferences({
    surfaces: {
      status: { opacity: 99, parked: "yes" },
      feed: { opacity: -5, parked: 1 },
      tutorial: { opacity: Number.NaN, parked: true },
      dock: "not-an-object",
      injected: { opacity: 0.2, parked: true },
    },
  });
  assert.equal(clamped.surfaces.status.opacity, 1);
  // Only a real boolean true parks a surface.
  assert.equal(clamped.surfaces.status.parked, false);
  assert.equal(clamped.surfaces.feed.opacity, 0.15);
  assert.equal(clamped.surfaces.feed.parked, false);
  assert.equal(clamped.surfaces.tutorial.opacity, 1);
  assert.equal(clamped.surfaces.tutorial.parked, true);
  assert.equal(clamped.surfaces.dock.opacity, 1);
  assert.equal(Object.hasOwn(clamped.surfaces, "injected"), false);

  for (const hostile of [null, undefined, 42, "surfaces", [], { surfaces: [] }]) {
    const fallback = bridge.normalizeHudPreferences(hostile);
    assert.equal(Object.keys(fallback.surfaces).length, 4);
    assert.equal(fallback.surfaces.dock.opacity, 1);
  }
});

test("deployment sanitizes A.T.L.A.S. context and bounds return state", () => {
  const bridge = loadBridge();
  const selection = {
    gzg: "galaxy-message",
    version: "1.0",
    id: "atlas:test:bounded",
    type: "atlas.selection",
    source: { galaxy: "ATLAS", version: "test", instance: "test" },
    target: { galaxy: "*", capability: "tactical.deploy" },
    created_at: "2026-07-28T12:00:00.000Z",
    payload: {
      schema: "gzg.atlas.selection/1.0",
      deployable: true,
      selection: {
        type: "crisis",
        name: "N".repeat(500),
        description: "D".repeat(1000),
        latitude: 40,
        longitude: -74,
        ignored_secret: "do-not-forward",
      },
    },
  };
  const message = bridge.createDeployMessage(selection, bridge.defaultProfile(), {
    atlas_state: "#".repeat(20_000),
    created_at: "2026-07-28T12:00:00.000Z",
  });
  const target = message.payload.deploy.map.target;
  assert.equal(target.name.length, 160);
  assert.equal(target.description.length, 500);
  assert.equal("ignored_secret" in target, false);
  assert.equal(message.payload.deploy.atlas_state.length, 12_000);
});

test("large extraction replay compacts without losing campaign authority", () => {
  const bridge = loadBridge();
  const message = extractionMessage("xcommand:test:large");
  message.payload.extraction.replay = {
    actions: Array.from({ length: 4000 }, (_, index) => ({ index, note: "x".repeat(80) })),
    events: Array.from({ length: 1000 }, (_, index) => ({ index, note: "y".repeat(80) })),
  };
  message.payload.extraction.gains.loot = Array.from({ length: 1000 }, (_, index) => ({ index }));
  const compact = bridge.compactExtractionMessage(message, 50_000);
  assert.equal(compact.payload.extraction.replay.truncated, true);
  assert.equal(compact.payload.extraction.replay.action_count, 4000);
  assert.equal(compact.payload.extraction.gains.loot_count, 1000);
  assert.equal(compact.payload.extraction.outcome, "SUCCESS");
  assert.equal(compact.correlation_id, "battlestar:1234:1");
  assert.ok(JSON.stringify(compact).length < 50_000);
});
