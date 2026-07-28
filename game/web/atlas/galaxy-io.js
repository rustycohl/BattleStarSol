(() => {
  "use strict";

  const MESSAGE_VERSION = "1.0";
  const PRODUCT_VERSION = "0.1.0-alpha.2";
  const CAPABILITY_PATTERN = /^[a-z0-9]+(?:[.-][a-z0-9]+)+$/;
  const MAX_MESSAGE_BYTES = 2_000_000;
  let sequence = 0;
  let latestMessage = null;

  function newInstanceId() {
    try {
      const existing = sessionStorage.getItem("gzg.atlas.instance");
      if (existing) return existing;
      const created = globalThis.crypto?.randomUUID?.() ?? "local-browser";
      sessionStorage.setItem("gzg.atlas.instance", created);
      return created;
    } catch {
      return "local-browser";
    }
  }

  const instanceId = newInstanceId();

  function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }

  function jsonClone(value) {
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
    if (new TextEncoder().encode(json).byteLength > MAX_MESSAGE_BYTES) {
      throw new RangeError("Galaxy message exceeds the supported size.");
    }
    return JSON.parse(json);
  }

  function validate(message) {
    if (!isObject(message)) throw new TypeError("Galaxy message must be an object.");
    if (message.gzg !== "galaxy-message") throw new TypeError("Invalid galaxy discriminator.");
    if (!/^1\.[0-9]+$/.test(message.version)) throw new RangeError("Unsupported galaxy-message version.");
    if (typeof message.id !== "string" || !message.id) throw new TypeError("Message id is required.");
    if (!CAPABILITY_PATTERN.test(message.type)) throw new TypeError("Invalid message type.");
    if (!isObject(message.source) || !message.source.galaxy || !message.source.version || !message.source.instance) {
      throw new TypeError("Complete source metadata is required.");
    }
    if (!isObject(message.target) || !message.target.galaxy || !CAPABILITY_PATTERN.test(message.target.capability)) {
      throw new TypeError("Complete target metadata is required.");
    }
    if (!isObject(message.payload)) throw new TypeError("Payload must be an object.");
    if (new Date(message.created_at).toISOString() !== message.created_at) {
      throw new TypeError("created_at must be an exact UTC ISO-8601 timestamp.");
    }
    return jsonClone(message);
  }

  function normalizedSelection(input) {
    const candidate = isObject(input) ? input : {};
    const selection = {};
    for (const [key, fallback, limit] of [
      ["type", "unknown", 40],
      ["name", "Selected A.T.L.A.S. target", 160],
      ["id", "", 256],
      ["city", "", 120],
      ["category", "", 120],
      ["description", "", 500],
    ]) {
      if (candidate[key] === undefined || candidate[key] === null) continue;
      selection[key] = String(candidate[key] || fallback).slice(0, limit);
    }

    for (const [source, target, minimum, maximum] of [
      ["lat", "latitude", -90, 90],
      ["lng", "longitude", -180, 180],
    ]) {
      if (candidate[source] === undefined || candidate[source] === null) continue;
      const coordinate = Number(candidate[source]);
      if (!Number.isFinite(coordinate) || coordinate < minimum || coordinate > maximum) {
        throw new RangeError(`Selection ${source} is outside its valid range.`);
      }
      selection[target] = Number(coordinate.toFixed(6));
    }

    return {
      schema: "gzg.atlas.selection/1.0",
      deployable: Boolean(candidate.deployable),
      selection,
    };
  }

  function createSelection(input, options = {}) {
    sequence += 1;
    const createdAt = options.created_at ?? new Date().toISOString();
    const message = {
      gzg: "galaxy-message",
      version: MESSAGE_VERSION,
      id: options.id ?? `atlas:${instanceId}:${createdAt}:${sequence}`,
      type: "atlas.selection",
      source: {
        galaxy: "ATLAS",
        version: PRODUCT_VERSION,
        instance: instanceId,
      },
      target: {
        galaxy: options.targetGalaxy ?? "*",
        capability: "tactical.deploy",
      },
      created_at: createdAt,
      payload: normalizedSelection(input),
    };
    if (options.correlation_id) message.correlation_id = options.correlation_id;
    return validate(message);
  }

  function targetOrigin() {
    const requested = new URL(location.href).searchParams.get("parentOrigin");
    if (requested) {
      try {
        const parsed = new URL(requested);
        if (!["http:", "https:"].includes(parsed.protocol)) {
          throw new TypeError("Unsupported parent origin protocol.");
        }
        return parsed.origin;
      } catch {
        throw new TypeError("parentOrigin must be an absolute HTTP(S) origin.");
      }
    }
    return location.protocol === "file:" ? "*" : location.origin;
  }

  function enableExportButton() {
    const button = document.getElementById("btn-export-selection");
    if (!button) return;
    button.disabled = false;
    button.title = "Download the latest versioned galaxy message";
    button.classList.remove("bg-slate-800", "border-slate-700", "text-slate-500", "disabled:cursor-not-allowed");
    button.classList.add("bg-blue-600/20", "hover:bg-blue-600/40", "border-blue-500/50", "text-blue-400", "hover:text-white");
  }

  function publishSelection(input, options = {}) {
    const message = createSelection(input, options);
    latestMessage = message;
    enableExportButton();
    window.dispatchEvent(new CustomEvent("gzg:galaxy-message", { detail: structuredClone(message) }));

    if (window.parent !== window) {
      const origin = targetOrigin();
      window.parent.postMessage(message, origin);
      window.parent.postMessage({
        channel: "atlas",
        kind: "selection",
        payload: structuredClone(input),
        galaxy_message: message,
      }, origin);
    }
    return structuredClone(message);
  }

  function exportLatest() {
    if (!latestMessage) throw new Error("Select a coordinate or deployable event first.");
    const blob = new Blob([`${JSON.stringify(latestMessage, null, 2)}\n`], {
      type: "application/json",
    });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `atlas-selection-${latestMessage.id.replace(/[^a-z0-9.-]+/gi, "-")}.json`;
    link.click();
    URL.revokeObjectURL(url);
  }

  function selfTest() {
    const sample = createSelection(
      {
        deployable: true,
        type: "coordinate",
        name: "Self-test",
        lat: 0,
        lng: 0,
      },
      {
        id: "atlas-self-test",
        created_at: "2026-07-28T12:00:00.000Z",
      },
    );
    return {
      ok: validate(sample).payload.selection.latitude === 0,
      checks: 10,
      protocol: `gzg.galaxy-message/${MESSAGE_VERSION}`,
    };
  }

  window.ATLAS_IO = Object.freeze({
    createSelection,
    exportLatest,
    getLatest: () => structuredClone(latestMessage),
    publishSelection,
    selfTest,
    validate,
    version: MESSAGE_VERSION,
  });

  window.addEventListener("DOMContentLoaded", () => {
    document.getElementById("btn-export-selection")?.addEventListener("click", exportLatest);
  });
})();
