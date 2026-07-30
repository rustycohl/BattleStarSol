(() => {
  "use strict";

  const MESSAGE_VERSION = "1.0";
  const PRODUCT_VERSION = "0.1.1-prealpha.1";
  const PROFILE_KEY = "bss_profile_v1";
  const DEPLOY_KEY = "bss_deploy_message";
  const EXTRACTION_KEY = "bss_extraction_message";
  const TYPE_PATTERN = /^[a-z0-9]+(?:[.-][a-z0-9]+)+$/;
  const MAX_MESSAGE_BYTES = 4_000_000;
  const MAX_URL_PAYLOAD_CHARS = 240_000;
  const MAX_ATLAS_STATE_CHARS = 12_000;
  const MAX_STORED_EXTRACTION_BYTES = 500_000;

  const clone = (value) => globalThis.structuredClone
    ? globalThis.structuredClone(value)
    : JSON.parse(JSON.stringify(value));

  function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }

  function jsonClone(value, maxBytes = MAX_MESSAGE_BYTES) {
    let json;
    try {
      json = JSON.stringify(value, (_key, item) => {
        if (typeof item === "number" && !Number.isFinite(item)) {
          throw new TypeError("Galaxy messages cannot contain non-finite numbers.");
        }
        if (["bigint", "function", "symbol", "undefined"].includes(typeof item)) {
          throw new TypeError("Galaxy messages must contain JSON values only.");
        }
        return item;
      });
    } catch (error) {
      throw new TypeError(`Galaxy message is not valid JSON: ${error.message}`);
    }
    if (typeof json !== "string") throw new TypeError("Galaxy message is not serializable.");
    if (new TextEncoder().encode(json).byteLength > maxBytes) {
      throw new RangeError("Galaxy message exceeds the supported size.");
    }
    return JSON.parse(json);
  }

  function boundedText(value, fallback, maxLength) {
    return String(value || fallback).slice(0, maxLength);
  }

  function normalizedTarget(input) {
    const candidate = isObject(input) ? input : {};
    const target = {
      type: boundedText(candidate.type, "coordinate", 40),
      name: boundedText(candidate.name, "Proving Ground", 160),
    };
    for (const [key, limit] of [
      ["id", 256],
      ["city", 120],
      ["category", 120],
      ["description", 500],
    ]) {
      if (candidate[key] !== undefined && candidate[key] !== null) {
        target[key] = String(candidate[key]).slice(0, limit);
      }
    }
    for (const [key, minimum, maximum] of [
      ["latitude", -90, 90],
      ["longitude", -180, 180],
    ]) {
      if (candidate[key] === undefined || candidate[key] === null) continue;
      const coordinate = Number(candidate[key]);
      if (!Number.isFinite(coordinate) || coordinate < minimum || coordinate > maximum) {
        throw new RangeError(`A.T.L.A.S. ${key} is outside its valid range.`);
      }
      target[key] = coordinate;
    }
    return target;
  }

  function validateMessage(message) {
    if (!isObject(message)) throw new TypeError("Galaxy message must be an object.");
    if (message.gzg !== "galaxy-message") throw new TypeError("Invalid galaxy discriminator.");
    if (!/^1\.[0-9]+$/.test(String(message.version))) {
      throw new RangeError("Unsupported galaxy-message major version.");
    }
    if (typeof message.id !== "string" || !message.id || message.id.length > 256) {
      throw new TypeError("A bounded message id is required.");
    }
    if (!TYPE_PATTERN.test(String(message.type))) throw new TypeError("Message type is invalid.");
    if (!isObject(message.source) || !message.source.galaxy || !message.source.version || !message.source.instance) {
      throw new TypeError("Complete source metadata is required.");
    }
    if (!isObject(message.target) || !message.target.galaxy || !TYPE_PATTERN.test(String(message.target.capability))) {
      throw new TypeError("Complete target metadata is required.");
    }
    if (!isObject(message.payload)) throw new TypeError("Message payload must be an object.");
    if (Number.isNaN(Date.parse(String(message.created_at)))) throw new TypeError("Message timestamp is invalid.");
    return jsonClone(message);
  }

  function fromBase64Utf8(value) {
    if (typeof value !== "string" || value.length > MAX_URL_PAYLOAD_CHARS) {
      throw new RangeError("Encoded deployment exceeds the URL payload budget.");
    }
    return new TextDecoder().decode(Uint8Array.from(atob(value), (character) => character.charCodeAt(0)));
  }

  function toBase64Utf8(value) {
    const bytes = new TextEncoder().encode(String(value));
    if (bytes.byteLength > MAX_URL_PAYLOAD_CHARS * 0.75) {
      throw new RangeError("Deployment exceeds the URL payload budget.");
    }
    let binary = "";
    for (let offset = 0; offset < bytes.length; offset += 0x8000) {
      binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
    }
    return btoa(binary);
  }

  function positiveSeed(value) {
    let hash = 0x811c9dc5;
    for (const character of String(value)) {
      hash ^= character.codePointAt(0);
      hash = Math.imul(hash, 0x01000193);
    }
    return (hash >>> 0) % 2147483646 + 1;
  }

  function defaultProfile() {
    return {
      schema: "gzg.battlestar.profile/1.0",
      callsign: "VANGUARD-1",
      faction: "HAD // HEAVY ARMOR DIVISION",
      resources: {
        neural: 50,
        capital: 25000,
        alloys: 100,
      },
      missions: [],
      applied_extractions: [],
      deployment_count: 0,
      hud: defaultHudPreferences(),
    };
  }

  // Adaptive HUD preferences. Presentation only: no mechanical value is stored
  // here, and an unreadable or hostile value falls back to the authored HUD
  // rather than failing a deployment.
  const HUD_SURFACE_KEYS = ["status", "feed", "tutorial", "dock"];
  const HUD_OPACITY_MIN = 0.15;
  const HUD_OPACITY_MAX = 1;

  function defaultHudPreferences() {
    const surfaces = {};
    for (const key of HUD_SURFACE_KEYS) {
      surfaces[key] = { opacity: HUD_OPACITY_MAX, parked: false };
    }
    return { schema: "gzg.battlestar.hud/1.0", surfaces };
  }

  function normalizeHudPreferences(candidate) {
    const fallback = defaultHudPreferences();
    if (!isObject(candidate)) return fallback;
    const incoming = isObject(candidate.surfaces) ? candidate.surfaces : {};
    const surfaces = {};
    for (const key of HUD_SURFACE_KEYS) {
      const entry = isObject(incoming[key]) ? incoming[key] : {};
      const opacity = Number(entry.opacity);
      surfaces[key] = {
        opacity: Number.isFinite(opacity)
          ? Math.min(HUD_OPACITY_MAX, Math.max(HUD_OPACITY_MIN, opacity))
          : HUD_OPACITY_MAX,
        parked: entry.parked === true,
      };
    }
    return { schema: fallback.schema, surfaces };
  }

  function normalizeProfile(candidate) {
    const fallback = defaultProfile();
    if (!isObject(candidate)) return fallback;
    const resources = isObject(candidate.resources) ? candidate.resources : {};
    return {
      ...fallback,
      ...candidate,
      schema: fallback.schema,
      callsign: String(candidate.callsign || fallback.callsign).slice(0, 40),
      faction: String(candidate.faction || fallback.faction).slice(0, 120),
      resources: {
        neural: Math.max(0, Number(resources.neural) || 0),
        capital: Math.max(0, Number(resources.capital) || 0),
        alloys: Math.max(0, Number(resources.alloys) || 0),
      },
      missions: Array.isArray(candidate.missions) ? candidate.missions.slice(-50) : [],
      applied_extractions: Array.isArray(candidate.applied_extractions)
        ? candidate.applied_extractions.slice(-100).map(String)
        : [],
      deployment_count: Math.max(0, Number(candidate.deployment_count) || 0),
      hud: normalizeHudPreferences(candidate.hud),
    };
  }

  function loadProfile(storage = localStorage) {
    try {
      return normalizeProfile(JSON.parse(storage.getItem(PROFILE_KEY) || "null"));
    } catch {
      return defaultProfile();
    }
  }

  function saveProfile(profile, storage = localStorage) {
    const normalized = normalizeProfile(profile);
    storage.setItem(PROFILE_KEY, JSON.stringify(normalized));
    return normalized;
  }

  // Narrow read/write pair the tactical runtime calls across the JavaScript
  // bridge, so the Godot side never has to know the profile's storage shape.
  function readHudPreferences(storage = localStorage) {
    return loadProfile(storage).hud;
  }

  function writeHudPreferences(hud, storage = localStorage) {
    const profile = loadProfile(storage);
    profile.hud = normalizeHudPreferences(hud);
    return saveProfile(profile, storage).hud;
  }

  function normalizeAtlasSelection(data) {
    if (isObject(data) && data.gzg === "galaxy-message") {
      const message = validateMessage(data);
      if (message.type !== "atlas.selection") return null;
      return message;
    }
    if (isObject(data?.galaxy_message)) {
      return normalizeAtlasSelection(data.galaxy_message);
    }
    if (data?.channel === "atlas" && data?.kind === "selection" && isObject(data.payload)) {
      const selection = {
        ...data.payload,
      };
      if (Number.isFinite(selection.lat)) {
        selection.latitude = selection.lat;
        delete selection.lat;
      }
      if (Number.isFinite(selection.lng)) {
        selection.longitude = selection.lng;
        delete selection.lng;
      }
      return validateMessage({
        gzg: "galaxy-message",
        version: MESSAGE_VERSION,
        id: `atlas-legacy:${Date.now()}`,
        type: "atlas.selection",
        source: {
          galaxy: "ATLAS",
          version: "legacy-adapter",
          instance: "embedded",
        },
        target: {
          galaxy: "*",
          capability: "tactical.deploy",
        },
        created_at: new Date().toISOString(),
        payload: {
          schema: "gzg.atlas.selection/1.0",
          deployable: Boolean(data.payload.deployable),
          selection,
        },
      });
    }
    return null;
  }

  function selectionData(selectionMessage) {
    if (!selectionMessage) {
      return {
        deployable: true,
        selection: {
          type: "coordinate",
          name: "Proving Ground",
          latitude: 34.0522,
          longitude: -118.2437,
        },
      };
    }
    const message = validateMessage(selectionMessage);
    if (message.type !== "atlas.selection") throw new TypeError("Expected atlas.selection.");
    return message.payload;
  }

  function createDeployMessage(selectionMessage, profileInput, options = {}) {
    const profile = normalizeProfile(profileInput);
    const selected = selectionData(selectionMessage);
    if (!selected.deployable) throw new RangeError("The A.T.L.A.S. selection is not deployable.");
    const target = normalizedTarget(selected.selection);
    const deploymentCount = profile.deployment_count + 1;
    const createdAt = options.created_at ?? new Date().toISOString();
    const seed = options.seed ?? positiveSeed([
      target.name || "Proving Ground",
      target.latitude ?? 0,
      target.longitude ?? 0,
      deploymentCount,
    ].join("|"));
    const sector = String(target.name || "Proving Ground").slice(0, 160);
    const type = String(target.type || "coordinate");
    const isProvingGround = sector === "Proving Ground";
    const deploy = {
      type: "deploy",
      payload_contract_version: "1.0",
      generator_version: 1,
      rules_version: "alpha-1",
      sector,
      faction: profile.faction,
      seed,
      atlas_state: boundedText(options.atlas_state, "#", MAX_ATLAS_STATE_CHARS),
      squad: [
        { name: profile.callsign, cls: "Heavy" },
        { name: "SCOUT-3", cls: "Recon" },
        { name: "MEDIC-2", cls: "Support" },
      ],
      objectives: isProvingGround
        ? [
          "Select the Commander",
          "Move and practice defense",
          "Complete a basic attack",
          "End turn and observe the phases",
          "Extract to strategy",
        ]
        : type === "crisis"
          ? ["Stabilize crisis site", "Protect civilian corridors", "Extract"]
          : ["Recon selected coordinates", "Neutralize hostiles", "Extract"],
      map: {
        target: clone(target),
      },
      resources: {
        neural: profile.resources.neural,
        capital: profile.resources.capital,
        alloys: profile.resources.alloys,
      },
    };
    const message = {
      gzg: "galaxy-message",
      version: MESSAGE_VERSION,
      id: options.id ?? `battlestar:${seed}:${deploymentCount}`,
      type: "battlestar.deploy",
      source: {
        galaxy: "BattleStarSol",
        version: PRODUCT_VERSION,
        instance: "browser-local",
      },
      target: {
        galaxy: "xCommand",
        capability: "tactical.deploy",
      },
      created_at: createdAt,
      payload: {
        schema: "gzg.battlestar.deploy/1.0",
        deploy,
      },
    };
    if (selectionMessage?.id) message.correlation_id = selectionMessage.id;
    return validateMessage(message);
  }

  function unwrapDeploy(input) {
    if (isObject(input) && input.gzg === "galaxy-message") {
      const message = validateMessage(input);
      if (!["battlestar.deploy", "dealer.deploy"].includes(message.type)) {
        throw new TypeError("Expected a tactical deployment message.");
      }
      const deploy = isObject(message.payload.deploy) ? message.payload.deploy : message.payload;
      if (!isObject(deploy) || deploy.type !== "deploy") throw new TypeError("Deployment payload is invalid.");
      return { message, deploy: clone(deploy) };
    }
    if (isObject(input) && input.type === "deploy") {
      return { message: null, deploy: clone(input) };
    }
    throw new TypeError("Deployment input is invalid.");
  }

  function normalizeExtraction(data) {
    if (isObject(data) && data.gzg === "galaxy-message") {
      const message = validateMessage(data);
      if (message.type !== "xcommand.extraction") return null;
      const extraction = isObject(message.payload.extraction)
        ? message.payload.extraction
        : message.payload;
      return { message, extraction: clone(extraction) };
    }
    if (isObject(data?.galaxy_message)) {
      return normalizeExtraction(data.galaxy_message);
    }
    if (data?.channel === "battlestar" && data?.kind === "extraction" && isObject(data.payload)) {
      const extraction = clone(data.payload);
      const id = String(extraction.extraction_id || `xcommand-legacy:${extraction.seed || 0}:${extraction.ts || Date.now()}`);
      return {
        message: validateMessage({
          gzg: "galaxy-message",
          version: MESSAGE_VERSION,
          id,
          type: "xcommand.extraction",
          source: {
            galaxy: "xCommand",
            version: "legacy-adapter",
            instance: "godot-web",
          },
          target: {
            galaxy: "BattleStarSol",
            capability: "strategic.receive-extraction",
          },
          created_at: new Date(Number(extraction.ts) || Date.now()).toISOString(),
          payload: {
            schema: "gzg.xcommand.extraction/1.0",
            extraction,
          },
        }),
        extraction,
      };
    }
    return null;
  }

  function compactExtractionMessage(input, maxBytes = MAX_STORED_EXTRACTION_BYTES) {
    const message = validateMessage(input);
    const encoded = new TextEncoder().encode(JSON.stringify(message));
    if (encoded.byteLength <= maxBytes) return message;

    const extraction = isObject(message.payload?.extraction)
      ? message.payload.extraction
      : message.payload;
    const gains = isObject(extraction.gains) ? extraction.gains : {};
    const replay = isObject(extraction.replay) ? extraction.replay : {};
    message.payload = {
      schema: "gzg.xcommand.extraction/1.0",
      extraction: {
        type: String(extraction.type || "extraction"),
        payload_contract_version: String(extraction.payload_contract_version || "1.0"),
        generator_version: Math.max(1, Number(extraction.generator_version) || 1),
        rules_version: String(extraction.rules_version || "alpha-1"),
        sector: String(extraction.sector || "").slice(0, 160),
        seed: Math.max(1, Number(extraction.seed) || 1),
        outcome: String(extraction.outcome || "UNKNOWN").slice(0, 40),
        survivors: Math.max(0, Number(extraction.survivors) || 0),
        gains: {
          neural: Math.max(0, Number(gains.neural) || 0),
          capital: Math.max(0, Number(gains.capital) || 0),
          alloys: Math.max(0, Number(gains.alloys) || 0),
          loot: [],
          loot_count: Array.isArray(gains.loot) ? gains.loot.length : 0,
        },
        note: String(extraction.note || "").slice(0, 500),
        ts: Math.max(0, Number(extraction.ts) || Date.now()),
        extraction_id: String(extraction.extraction_id || message.id).slice(0, 256),
        replay: {
          truncated: true,
          action_count: Array.isArray(replay.actions) ? replay.actions.length : 0,
          event_count: Array.isArray(replay.events) ? replay.events.length : 0,
        },
      },
    };
    message.extensions = {
      ...(isObject(message.extensions) ? message.extensions : {}),
      browser_storage: {
        compacted: true,
        original_bytes: encoded.byteLength,
      },
    };
    return validateMessage(message);
  }

  function applyExtraction(profileInput, normalized) {
    if (!normalized?.message || !isObject(normalized.extraction)) {
      throw new TypeError("A normalized extraction message is required.");
    }
    const profile = normalizeProfile(profileInput);
    const id = normalized.message.id;
    if (profile.applied_extractions.includes(id)) {
      return { changed: false, profile };
    }
    const extraction = normalized.extraction;
    const gains = isObject(extraction.gains) ? extraction.gains : {};
    profile.resources.neural += Math.max(0, Number(gains.neural) || 0);
    profile.resources.capital += Math.max(0, Number(gains.capital) || 0);
    profile.resources.alloys += Math.max(0, Number(gains.alloys) || 0);
    profile.applied_extractions.push(id);
    profile.applied_extractions = profile.applied_extractions.slice(-100);
    profile.missions.push({
      id,
      sector: String(extraction.sector || "Unknown sector").slice(0, 160),
      seed: Number(extraction.seed) || 0,
      outcome: String(extraction.outcome || "UNKNOWN").slice(0, 40),
      survivors: Math.max(0, Number(extraction.survivors) || 0),
      gains: {
        neural: Math.max(0, Number(gains.neural) || 0),
        capital: Math.max(0, Number(gains.capital) || 0),
        alloys: Math.max(0, Number(gains.alloys) || 0),
      },
      correlation_id: String(normalized.message.correlation_id || ""),
      received_at: new Date().toISOString(),
    });
    profile.missions = profile.missions.slice(-50);
    return { changed: true, profile };
  }

  function readEncodedPayload(search = location.search) {
    const encoded = new URLSearchParams(search).get("p");
    if (!encoded) return null;
    return JSON.parse(fromBase64Utf8(encoded));
  }

  window.BSS_BRIDGE = Object.freeze({
    DEPLOY_KEY,
    EXTRACTION_KEY,
    MESSAGE_VERSION,
    PRODUCT_VERSION,
    PROFILE_KEY,
    applyExtraction,
    compactExtractionMessage,
    createDeployMessage,
    defaultHudPreferences,
    defaultProfile,
    fromBase64Utf8,
    normalizeHudPreferences,
    readHudPreferences,
    writeHudPreferences,
    loadProfile,
    normalizeAtlasSelection,
    normalizeExtraction,
    normalizeProfile,
    positiveSeed,
    readEncodedPayload,
    saveProfile,
    toBase64Utf8,
    unwrapDeploy,
    validateMessage,
  });
})();
