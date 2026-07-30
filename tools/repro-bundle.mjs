#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  lstatSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

import {
  SHA256_PATTERN,
  sha256File,
  validateEvidenceIdentity,
  verifySha256Manifest,
} from "./playtest/evidence-pack.mjs";

export const REPRO_SCHEMA = "gzg.battlestar.repro/1.0";
export const CANONICALIZATION = "gzg.canonical-json/1.0";
export const MAX_REPRO_BYTES = 128_000;
export const MAX_ACTIONS = 256;
export const MAX_EVENTS = 1_024;

const MAX_PACK_BYTES = 8_000_000;
const MAX_PACK_FILES = 64;
const SAFE_SCENARIOS = new Set(["Proving Ground"]);
const RESULT_PATTERN = /^[A-Z][A-Z0-9_-]{0,39}$/;
const SAFE_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9:._-]{0,255}$/;
const ACTION_PATTERN = /^[a-z][a-z0-9_]{0,63}$/;
const EVENT_PATTERN = /^[a-z][a-z0-9_]{0,63}$/;
const FORBIDDEN_KEY_PATTERN =
  /(?:password|passwd|secret|token|cookie|authorization|email|browser_storage|local_storage|profile_path|user_path|home_path)/i;
const FORBIDDEN_TEXT_PATTERNS = [
  /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i,
  /(?:[A-Za-z]:\\Users\\|\/Users\/|\/home\/|file:\/\/)/i,
  /\b(?:Bearer|Basic)\s+[A-Za-z0-9._~+/=-]{8,}/i,
];

const PRIVACY_EXCLUSIONS = Object.freeze([
  "actor and squad names",
  "A.T.L.A.S. return state and map coordinates",
  "browser storage and profile data",
  "console lines, screenshots, URLs, and filesystem paths",
]);
const SUPPORTED_EQUIVALENCE = Object.freeze([
  "validated deployment identity and normalized initial input",
  "ordered action/event ledger and canonical digest",
  "declared tactical result and strategic import delta",
  "duplicate extraction idempotence",
]);
const UNSUPPORTED_EQUIVALENCE = Object.freeze([
  "Godot mechanical re-simulation from the action ledger",
  "native/Web or cross-platform mechanical state-hash equivalence",
]);
const MECHANICAL_HASH_REASON =
  "The current pre-alpha extraction does not emit an authoritative mechanical state hash.";

const EVENT_PAYLOAD_KEYS = Object.freeze({
  tutorial_step_changed: ["complete", "display_step", "step", "total_steps"],
  movement_resolved: ["actor", "ap_spent", "from", "mode", "to"],
  damage_resolved: [
    "attacker",
    "damage",
    "hp_after",
    "hp_before",
    "ranged",
    "target",
    "weapon",
  ],
  agent_decision: [
    "actor",
    "ap_before",
    "decision",
    "position",
    "rationale",
    "round",
    "score",
    "team",
  ],
  loot_collected: ["actor", "ap_spent", "cell", "items"],
  unit_killed: ["attacker", "cell", "target", "weapon"],
  // Area detonation. A blast is one event with an aggregate outcome; the terrain it
  // breaks is recorded separately as terrain_damaged, on the same terms.
  blast_resolved: [
    "attacker",
    "cell",
    "damage_dealt",
    "radius",
    "terrain_destroyed",
    "units_hit",
    "units_shielded",
    "weapon",
  ],
  // Terrain destruction. Carried on the same terms as unit_killed: a bounded grid
  // cell, the acting unit id, and the material transition — no real-world
  // coordinate, no browser or profile surface.
  terrain_damaged: [
    "attacker",
    "cell",
    "cover_after",
    "cover_before",
    "destroyed",
    "integrity_after",
    "integrity_before",
    "material_after",
    "material_before",
    "weapon",
  ],
  turn_started: ["active_team", "round"],
  mission_resolved: ["note", "outcome", "survivors"],
});

function plainObject(value, path) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new TypeError(`${path} must be an object.`);
  }
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null) {
    throw new TypeError(`${path} must be a plain object.`);
  }
  return value;
}

function exactKeys(value, required, optional = [], path = "value") {
  const object = plainObject(value, path);
  const allowed = new Set([...required, ...optional]);
  for (const key of required) {
    if (!Object.hasOwn(object, key)) throw new TypeError(`${path}.${key} is required.`);
  }
  for (const key of Object.keys(object)) {
    if (FORBIDDEN_KEY_PATTERN.test(key)) {
      throw new TypeError(`${path}.${key} is a forbidden sensitive field.`);
    }
    if (!allowed.has(key)) throw new TypeError(`${path}.${key} is not supported.`);
  }
  return object;
}

function boundedString(value, path, maximum, { pattern, allowed } = {}) {
  if (typeof value !== "string" || value.length < 1 || value.length > maximum) {
    throw new TypeError(`${path} must be a non-empty string of at most ${maximum} characters.`);
  }
  if (/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(value)) {
    throw new TypeError(`${path} contains unsupported control characters.`);
  }
  if (FORBIDDEN_TEXT_PATTERNS.some((candidate) => candidate.test(value))) {
    throw new TypeError(`${path} contains direct or sensitive data.`);
  }
  if (pattern && !pattern.test(value)) throw new TypeError(`${path} has an unsupported format.`);
  if (allowed && !allowed.has(value)) throw new TypeError(`${path} is not allowlisted.`);
  return value;
}

function finiteNumber(value, path, minimum, maximum, { integer = false } = {}) {
  if (
    typeof value !== "number"
    || !Number.isFinite(value)
    || (integer && !Number.isInteger(value))
    || value < minimum
    || value > maximum
  ) {
    throw new TypeError(
      `${path} must be a ${integer ? "finite integer" : "finite number"} from ${minimum} through ${maximum}.`,
    );
  }
  return Object.is(value, -0) ? 0 : value;
}

function booleanValue(value, path) {
  if (typeof value !== "boolean") throw new TypeError(`${path} must be a boolean.`);
  return value;
}

function canonicalize(value, path = "$") {
  if (value === null) return "null";
  if (Array.isArray(value)) {
    return `[${value.map((item, index) => canonicalize(item, `${path}[${index}]`)).join(",")}]`;
  }
  switch (typeof value) {
    case "string":
      return JSON.stringify(value);
    case "boolean":
      return value ? "true" : "false";
    case "number":
      if (!Number.isFinite(value)) throw new TypeError(`${path} contains a non-finite number.`);
      return Object.is(value, -0) ? "0" : JSON.stringify(value);
    case "object": {
      plainObject(value, path);
      const keys = Object.keys(value).sort();
      return `{${keys.map((key) => {
        if (value[key] === undefined) throw new TypeError(`${path}.${key} is undefined.`);
        return `${JSON.stringify(key)}:${canonicalize(value[key], `${path}.${key}`)}`;
      }).join(",")}}`;
    }
    default:
      throw new TypeError(`${path} contains unsupported canonical data: ${typeof value}.`);
  }
}

export function stableStringify(value) {
  return canonicalize(value);
}

export function digestCanonical(value) {
  return createHash("sha256").update(stableStringify(value), "utf8").digest("hex");
}

function position(value, path) {
  const source = exactKeys(value, ["x", "y", "z"], [], path);
  return {
    x: finiteNumber(source.x, `${path}.x`, -10_000, 10_000, { integer: true }),
    y: finiteNumber(source.y, `${path}.y`, -10_000, 10_000, { integer: true }),
    z: finiteNumber(source.z, `${path}.z`, -1_000, 1_000, { integer: true }),
  };
}

function actorReference(value, path, { source = false } = {}) {
  const actor = exactKeys(
    value,
    ["team", "unit_id"],
    source ? ["name"] : [],
    path,
  );
  return {
    unit_id: finiteNumber(actor.unit_id, `${path}.unit_id`, 1, 10_000, { integer: true }),
    team: finiteNumber(actor.team, `${path}.team`, 0, 32, { integer: true }),
  };
}

function projectAction(value, index) {
  const path = `replay.actions[${index}]`;
  const action = exactKeys(
    value,
    [
      "accepted",
      "action",
      "active_team",
      "actor",
      "ap_after_dispatch",
      "ap_before",
      "record_type",
      "round",
      "sequence",
      "target",
      "use_offhand",
    ],
    [],
    path,
  );
  if (action.record_type !== "action") throw new TypeError(`${path}.record_type must be action.`);
  return {
    sequence: finiteNumber(action.sequence, `${path}.sequence`, 1, 1_000_000, { integer: true }),
    record_type: "action",
    round: finiteNumber(action.round, `${path}.round`, 1, 100_000, { integer: true }),
    active_team: finiteNumber(action.active_team, `${path}.active_team`, 0, 32, { integer: true }),
    actor: actorReference(action.actor, `${path}.actor`, { source: true }),
    action: boundedString(action.action, `${path}.action`, 64, { pattern: ACTION_PATTERN }),
    target: position(action.target, `${path}.target`),
    use_offhand: booleanValue(action.use_offhand, `${path}.use_offhand`),
    ap_before: finiteNumber(action.ap_before, `${path}.ap_before`, 0, 10, { integer: true }),
    ap_after_dispatch: finiteNumber(
      action.ap_after_dispatch,
      `${path}.ap_after_dispatch`,
      0,
      10,
      { integer: true },
    ),
    accepted: booleanValue(action.accepted, `${path}.accepted`),
  };
}

function projectItems(value, path) {
  if (Array.isArray(value)) {
    if (value.length > 32) throw new RangeError(`${path} exceeds 32 item types.`);
    return value.map((entry, index) => {
      const item = exactKeys(entry, ["item", "quantity"], [], `${path}[${index}]`);
      return {
        item: boundedString(item.item, `${path}[${index}].item`, 80, { pattern: ACTION_PATTERN }),
        quantity: finiteNumber(
          item.quantity,
          `${path}[${index}].quantity`,
          0,
          10_000,
          { integer: true },
        ),
      };
    });
  }
  const source = plainObject(value, path);
  const names = Object.keys(source).sort();
  if (names.length > 32) throw new RangeError(`${path} exceeds 32 item types.`);
  return names.map((name, index) => ({
    item: boundedString(name, `${path}[${index}].item`, 80, { pattern: ACTION_PATTERN }),
    quantity: finiteNumber(source[name], `${path}.${name}`, 0, 10_000, { integer: true }),
  }));
}

function projectEventPayload(eventName, value, path) {
  const required = EVENT_PAYLOAD_KEYS[eventName];
  if (!required) throw new TypeError(`${path} uses unsupported event ${eventName}.`);
  const payload = exactKeys(value, required, [], path);
  switch (eventName) {
    case "tutorial_step_changed":
      return {
        complete: booleanValue(payload.complete, `${path}.complete`),
        display_step: finiteNumber(payload.display_step, `${path}.display_step`, 1, 100, { integer: true }),
        step: boundedString(payload.step, `${path}.step`, 64, { pattern: ACTION_PATTERN }),
        total_steps: finiteNumber(payload.total_steps, `${path}.total_steps`, 1, 100, { integer: true }),
      };
    case "movement_resolved":
      return {
        actor: finiteNumber(payload.actor, `${path}.actor`, 1, 10_000, { integer: true }),
        ap_spent: finiteNumber(payload.ap_spent, `${path}.ap_spent`, 0, 10, { integer: true }),
        from: position(payload.from, `${path}.from`),
        mode: boundedString(payload.mode, `${path}.mode`, 32, { pattern: ACTION_PATTERN }),
        to: position(payload.to, `${path}.to`),
      };
    case "damage_resolved":
      return {
        attacker: finiteNumber(payload.attacker, `${path}.attacker`, 1, 10_000, { integer: true }),
        damage: finiteNumber(payload.damage, `${path}.damage`, 0, 1_000, { integer: true }),
        hp_after: finiteNumber(payload.hp_after, `${path}.hp_after`, 0, 100_000, { integer: true }),
        hp_before: finiteNumber(payload.hp_before, `${path}.hp_before`, 0, 100_000, { integer: true }),
        ranged: booleanValue(payload.ranged, `${path}.ranged`),
        target: finiteNumber(payload.target, `${path}.target`, 1, 10_000, { integer: true }),
        weapon: typeof payload.weapon === "string" && payload.weapon.length === 0
          ? ""
          : boundedString(payload.weapon, `${path}.weapon`, 80, { pattern: ACTION_PATTERN }),
      };
    case "agent_decision":
      return {
        actor: finiteNumber(payload.actor, `${path}.actor`, 1, 10_000, { integer: true }),
        ap_before: finiteNumber(payload.ap_before, `${path}.ap_before`, 0, 10, { integer: true }),
        decision: boundedString(payload.decision, `${path}.decision`, 64, { pattern: ACTION_PATTERN }),
        position: position(payload.position, `${path}.position`),
        rationale: boundedString(payload.rationale, `${path}.rationale`, 200),
        round: finiteNumber(payload.round, `${path}.round`, 1, 100_000, { integer: true }),
        score: finiteNumber(payload.score, `${path}.score`, -1_000_000, 1_000_000),
        team: finiteNumber(payload.team, `${path}.team`, 0, 32, { integer: true }),
      };
    case "loot_collected":
      return {
        actor: finiteNumber(payload.actor, `${path}.actor`, 1, 10_000, { integer: true }),
        ap_spent: finiteNumber(payload.ap_spent, `${path}.ap_spent`, 0, 10, { integer: true }),
        cell: position(payload.cell, `${path}.cell`),
        items: projectItems(payload.items, `${path}.items`),
      };
    case "unit_killed":
      return {
        attacker: finiteNumber(payload.attacker, `${path}.attacker`, 1, 10_000, { integer: true }),
        cell: position(payload.cell, `${path}.cell`),
        target: finiteNumber(payload.target, `${path}.target`, 1, 10_000, { integer: true }),
        weapon: boundedString(payload.weapon, `${path}.weapon`, 80, { pattern: ACTION_PATTERN }),
      };
    case "blast_resolved":
      return {
        attacker: finiteNumber(payload.attacker, `${path}.attacker`, 0, 10_000, { integer: true }),
        cell: position(payload.cell, `${path}.cell`),
        damage_dealt: finiteNumber(payload.damage_dealt, `${path}.damage_dealt`, 0, 100_000, { integer: true }),
        radius: finiteNumber(payload.radius, `${path}.radius`, 0, 32, { integer: true }),
        terrain_destroyed: finiteNumber(payload.terrain_destroyed, `${path}.terrain_destroyed`, 0, 10_000, { integer: true }),
        units_hit: finiteNumber(payload.units_hit, `${path}.units_hit`, 0, 1_000, { integer: true }),
        units_shielded: finiteNumber(payload.units_shielded, `${path}.units_shielded`, 0, 1_000, { integer: true }),
        weapon: boundedString(payload.weapon, `${path}.weapon`, 80, { pattern: ACTION_PATTERN }),
      };
    case "terrain_damaged":
      return {
        // An unattributed change (an environmental collapse) reports attacker 0,
        // so the floor is 0 here rather than 1.
        attacker: finiteNumber(payload.attacker, `${path}.attacker`, 0, 10_000, { integer: true }),
        cell: position(payload.cell, `${path}.cell`),
        cover_after: finiteNumber(payload.cover_after, `${path}.cover_after`, 0, 2, { integer: true }),
        cover_before: finiteNumber(payload.cover_before, `${path}.cover_before`, 0, 2, { integer: true }),
        destroyed: booleanValue(payload.destroyed, `${path}.destroyed`),
        integrity_after: finiteNumber(payload.integrity_after, `${path}.integrity_after`, 0, 100, { integer: true }),
        integrity_before: finiteNumber(payload.integrity_before, `${path}.integrity_before`, 0, 100, { integer: true }),
        material_after: boundedString(payload.material_after, `${path}.material_after`, 32, { pattern: ACTION_PATTERN }),
        material_before: boundedString(payload.material_before, `${path}.material_before`, 32, { pattern: ACTION_PATTERN }),
        weapon: typeof payload.weapon === "string" && payload.weapon.length === 0
          ? ""
          : boundedString(payload.weapon, `${path}.weapon`, 80, { pattern: ACTION_PATTERN }),
      };
    case "turn_started":
      return {
        active_team: finiteNumber(payload.active_team, `${path}.active_team`, 0, 32, { integer: true }),
        round: finiteNumber(payload.round, `${path}.round`, 1, 100_000, { integer: true }),
      };
    case "mission_resolved":
      return {
        note: boundedString(payload.note, `${path}.note`, 100, { pattern: ACTION_PATTERN }),
        outcome: boundedString(payload.outcome, `${path}.outcome`, 40, { pattern: RESULT_PATTERN }),
        survivors: finiteNumber(payload.survivors, `${path}.survivors`, 0, 100, { integer: true }),
      };
    default:
      throw new TypeError(`${path} uses unsupported event ${eventName}.`);
  }
}

function projectEvent(value, index) {
  const path = `replay.events[${index}]`;
  const event = exactKeys(value, ["event", "payload", "record_type", "sequence"], [], path);
  if (event.record_type !== "event") throw new TypeError(`${path}.record_type must be event.`);
  const eventName = boundedString(event.event, `${path}.event`, 64, { pattern: EVENT_PATTERN });
  return {
    sequence: finiteNumber(event.sequence, `${path}.sequence`, 1, 1_000_000, { integer: true }),
    record_type: "event",
    event: eventName,
    payload: projectEventPayload(eventName, event.payload, `${path}.payload`),
  };
}

function validateLedgerOrder(actions, events) {
  const records = [...actions, ...events].sort((left, right) => left.sequence - right.sequence);
  if (!records.length) throw new TypeError("mission.replay must contain records.");
  for (let index = 0; index < records.length; index += 1) {
    if (records[index].sequence !== index + 1) {
      throw new TypeError("mission.replay sequences must be unique and contiguous from 1.");
    }
  }
}

function projectDeployment(value) {
  const deploy = exactKeys(
    value,
    [
      "atlas_state",
      "faction",
      "generator_version",
      "map",
      "objectives",
      "payload_contract_version",
      "resources",
      "rules_version",
      "sector",
      "seed",
      "squad",
      "type",
    ],
    ["cell_size", "macro_grid"],
    "deployment",
  );
  if (deploy.type !== "deploy") throw new TypeError("deployment.type must be deploy.");
  const sector = boundedString(deploy.sector, "deployment.sector", 160, {
    allowed: SAFE_SCENARIOS,
  });
  if (!Array.isArray(deploy.squad) || deploy.squad.length < 1 || deploy.squad.length > 100) {
    throw new TypeError("deployment.squad must contain 1 through 100 units.");
  }
  if (!Array.isArray(deploy.objectives) || deploy.objectives.length > 100) {
    throw new TypeError("deployment.objectives must be a bounded array.");
  }
  const resources = exactKeys(
    deploy.resources,
    ["alloys", "capital", "neural"],
    [],
    "deployment.resources",
  );
  return {
    payload_contract_version: boundedString(
      deploy.payload_contract_version,
      "deployment.payload_contract_version",
      32,
    ),
    generator_version: finiteNumber(
      deploy.generator_version,
      "deployment.generator_version",
      1,
      1_000_000,
      { integer: true },
    ),
    rules_version: boundedString(deploy.rules_version, "deployment.rules_version", 64),
    sector,
    faction: boundedString(deploy.faction, "deployment.faction", 120),
    seed: finiteNumber(deploy.seed, "deployment.seed", 1, 2_147_483_647, { integer: true }),
    squad: deploy.squad.map((unit, index) => {
      const source = exactKeys(unit, ["cls", "name"], [], `deployment.squad[${index}]`);
      return {
        slot: index + 1,
        class: boundedString(source.cls, `deployment.squad[${index}].cls`, 80),
      };
    }),
    objectives: deploy.objectives.map((objective, index) =>
      boundedString(objective, `deployment.objectives[${index}]`, 500)),
    resources: {
      neural: finiteNumber(resources.neural, "deployment.resources.neural", 0, 1_000_000_000),
      capital: finiteNumber(resources.capital, "deployment.resources.capital", 0, 1_000_000_000),
      alloys: finiteNumber(resources.alloys, "deployment.resources.alloys", 0, 1_000_000_000),
    },
  };
}

function projectReplay(value) {
  const replay = exactKeys(
    value,
    ["actions", "events", "generator_version", "mission_seed", "rules_version"],
    [],
    "replay",
  );
  if (!Array.isArray(replay.actions) || replay.actions.length > MAX_ACTIONS) {
    throw new RangeError(`replay.actions exceeds ${MAX_ACTIONS} records.`);
  }
  if (!Array.isArray(replay.events) || replay.events.length > MAX_EVENTS) {
    throw new RangeError(`replay.events exceeds ${MAX_EVENTS} records.`);
  }
  const output = {
    mission_seed: finiteNumber(replay.mission_seed, "replay.mission_seed", 1, 2_147_483_647, {
      integer: true,
    }),
    generator_version: finiteNumber(
      replay.generator_version,
      "replay.generator_version",
      1,
      1_000_000,
      { integer: true },
    ),
    rules_version: boundedString(replay.rules_version, "replay.rules_version", 64),
    actions: replay.actions.map(projectAction),
    events: replay.events.map(projectEvent),
  };
  validateLedgerOrder(output.actions, output.events);
  return output;
}

function projectGains(value) {
  const gains = exactKeys(value, ["capital", "loot", "neural"], ["alloys"], "result.gains");
  if (!Array.isArray(gains.loot) || gains.loot.length !== 0) {
    throw new TypeError("result.gains.loot must be empty in repro contract 1.0.");
  }
  return {
    neural: finiteNumber(gains.neural, "result.gains.neural", 0, 1_000_000_000),
    capital: finiteNumber(gains.capital, "result.gains.capital", 0, 1_000_000_000),
    alloys: finiteNumber(gains.alloys ?? 0, "result.gains.alloys", 0, 1_000_000_000),
    loot: [],
  };
}

function projectResult(value) {
  const result = exactKeys(
    value,
    [
      "extraction_id",
      "gains",
      "generator_version",
      "note",
      "outcome",
      "payload_contract_version",
      "replay",
      "rules_version",
      "sector",
      "seed",
      "survivors",
      "ts",
      "type",
    ],
    [],
    "result",
  );
  if (result.type !== "extraction") throw new TypeError("result.type must be extraction.");
  return {
    type: "extraction",
    payload_contract_version: boundedString(
      result.payload_contract_version,
      "result.payload_contract_version",
      32,
    ),
    generator_version: finiteNumber(
      result.generator_version,
      "result.generator_version",
      1,
      1_000_000,
      { integer: true },
    ),
    rules_version: boundedString(result.rules_version, "result.rules_version", 64),
    sector: boundedString(result.sector, "result.sector", 160, { allowed: SAFE_SCENARIOS }),
    seed: finiteNumber(result.seed, "result.seed", 1, 2_147_483_647, { integer: true }),
    outcome: boundedString(result.outcome, "result.outcome", 40, { pattern: RESULT_PATTERN }),
    survivors: finiteNumber(result.survivors, "result.survivors", 0, 100, { integer: true }),
    gains: projectGains(result.gains),
    note: boundedString(result.note, "result.note", 100, { pattern: ACTION_PATTERN }),
  };
}

function validateMissionConsistency(mission) {
  const deploy = mission.deployment;
  const replay = mission.replay;
  const result = mission.result;
  for (const [path, value] of [
    ["seed", deploy.seed],
    ["generator_version", deploy.generator_version],
    ["rules_version", deploy.rules_version],
    ["payload_contract_version", deploy.payload_contract_version],
  ]) {
    const replayValue = path === "seed" ? replay.mission_seed : replay[path];
    if (path !== "payload_contract_version" && replayValue !== value) {
      throw new TypeError(`deployment and replay ${path} differ.`);
    }
    if (result[path] !== value) throw new TypeError(`deployment and result ${path} differ.`);
  }
  if (result.sector !== deploy.sector) throw new TypeError("deployment and result sector differ.");
  const resolved = replay.events.filter((event) => event.event === "mission_resolved");
  if (resolved.length !== 1) throw new TypeError("replay must contain exactly one mission_resolved event.");
  if (
    resolved[0].payload.outcome !== result.outcome
    || resolved[0].payload.survivors !== result.survivors
    || resolved[0].payload.note !== result.note
  ) {
    throw new TypeError("mission_resolved event and declared result differ.");
  }
}

function parseManifestRoutes(manifestText) {
  const routes = [];
  const seen = new Set();
  for (const row of String(manifestText).split(/\r?\n/).filter(Boolean)) {
    const match = /^([a-f0-9]{64})  (.+)$/.exec(row);
    if (!match) throw new TypeError(`Malformed SHA-256 manifest row: ${row}`);
    const route = match[2].replaceAll("\\", "/");
    if (
      !route
      || isAbsolute(route)
      || route.startsWith("/")
      || route.split("/").includes("..")
      || /[\0\r\n]/.test(route)
    ) {
      throw new TypeError(`Unsafe manifest route: ${route}`);
    }
    if (seen.has(route)) throw new TypeError(`SHA-256 manifest repeats ${route}.`);
    seen.add(route);
    routes.push(route);
  }
  return routes.sort();
}

function listPackFiles(root, current = root) {
  const files = [];
  for (const entry of readdirSync(current, { withFileTypes: true })) {
    const target = join(current, entry.name);
    if (entry.isSymbolicLink() || lstatSync(target).isSymbolicLink()) {
      throw new TypeError(`Evidence import rejects symbolic links: ${entry.name}`);
    }
    if (entry.isDirectory()) {
      files.push(...listPackFiles(root, target));
    } else if (entry.isFile()) {
      files.push(relative(root, target).replaceAll("\\", "/"));
    } else {
      throw new TypeError(`Evidence import rejects non-file entries: ${entry.name}`);
    }
  }
  return files.sort();
}

export function loadEvidencePack(packDir, { requirePass = true } = {}) {
  const root = resolve(String(packDir));
  const rootInfo = lstatSync(root);
  if (!rootInfo.isDirectory() || rootInfo.isSymbolicLink()) {
    throw new TypeError("Evidence pack root must be a real directory.");
  }
  const physicalFiles = listPackFiles(root);
  if (physicalFiles.length > MAX_PACK_FILES) {
    throw new RangeError(`Evidence pack exceeds ${MAX_PACK_FILES} files.`);
  }
  const totalBytes = physicalFiles.reduce((sum, route) => sum + statSync(join(root, route)).size, 0);
  if (totalBytes > MAX_PACK_BYTES) throw new RangeError("Evidence pack exceeds the import byte budget.");
  const manifestRoute = "SHA256SUMS";
  if (!physicalFiles.includes(manifestRoute)) throw new TypeError("Evidence pack has no SHA256SUMS.");
  const manifestText = readFileSync(join(root, manifestRoute), "utf8");
  const manifestRoutes = parseManifestRoutes(manifestText);
  const expectedPhysical = [...manifestRoutes, manifestRoute].sort();
  if (
    expectedPhysical.length !== physicalFiles.length
    || expectedPhysical.some((route, index) => route !== physicalFiles[index])
  ) {
    throw new TypeError("Evidence pack contains a missing or unmanifested file.");
  }
  verifySha256Manifest(root, manifestText);

  const reportPath = join(root, "playtest-report.json");
  const extractionPath = join(root, "extraction.json");
  if (statSync(reportPath).size > 256_000) throw new RangeError("Playtest report exceeds 256 KB.");
  if (statSync(extractionPath).size > 512_000) throw new RangeError("Extraction exceeds 512 KB.");
  const report = JSON.parse(readFileSync(reportPath, "utf8"));
  const extraction = JSON.parse(readFileSync(extractionPath, "utf8"));
  const runId = root.split(/[\\/]/).at(-1);
  const identity = validateEvidenceIdentity({
    report,
    deployment: report.deployment,
    extraction,
    expectedRunId: runId,
  });
  if (requirePass) {
    if (report.result !== "PASS") throw new TypeError("Authoritative reproduction input must be a PASS pack.");
    const failedRequired = Object.entries(report.gates ?? {})
      .filter(([, gate]) => gate?.required !== false && gate?.ok !== true)
      .map(([name]) => name);
    if (failedRequired.length) {
      throw new TypeError(`Authoritative reproduction input has failed gates: ${failedRequired.join(", ")}.`);
    }
  }
  return Object.freeze({
    root,
    runId,
    report,
    extraction,
    identity,
    sourceManifestSha256: sha256File(join(root, manifestRoute)),
  });
}

function productFromEvidence(report, extraction) {
  const deploySource = exactKeys(
    report.deployment?.source,
    ["galaxy", "instance", "version"],
    [],
    "deployment.source",
  );
  const extractionSource = exactKeys(
    extraction.source,
    ["galaxy", "instance", "version"],
    [],
    "extraction.source",
  );
  if (
    deploySource.galaxy !== "BattleStarSol"
    || extractionSource.galaxy !== "xCommand"
    || extractionSource.instance !== "godot-web"
    || deploySource.version !== extractionSource.version
  ) {
    throw new TypeError("Evidence product/source identities are inconsistent.");
  }
  return {
    galaxy: "BattleStarSol",
    version: boundedString(deploySource.version, "product.version", 64),
    platform: "godot-web",
    harness: boundedString(report.harness, "product.harness", 120),
  };
}

function projectEvidenceMission(pack) {
  const deployment = projectDeployment(pack.report.deployment.payload?.deploy);
  const extractionResult = pack.extraction.payload?.extraction;
  const replay = projectReplay(extractionResult?.replay);
  const result = projectResult(extractionResult);
  const mission = { deployment, replay, result };
  validateMissionConsistency(mission);
  return mission;
}

export function mechanicalScope(artifact) {
  return {
    schema: artifact.schema,
    product: {
      galaxy: artifact.product.galaxy,
      version: artifact.product.version,
      platform: artifact.product.platform,
    },
    build: {
      tactical_pck: artifact.build.tactical_pck,
    },
    mission: artifact.mission,
  };
}

function artifactDigestScope(artifact) {
  const { artifact_digest: _ignored, ...integrity } = artifact.integrity;
  return { ...artifact, integrity };
}

export function createReproArtifact(packDir) {
  const pack = loadEvidencePack(packDir, { requirePass: true });
  const tacticalPck = exactKeys(
    pack.report.server?.tactical_pck,
    ["bytes", "sha256", "url"],
    [],
    "report.server.tactical_pck",
  );
  const browser = exactKeys(
    pack.report.browser,
    ["headed", "resolver_source", "version"],
    [],
    "report.browser",
  );
  const result = pack.extraction.payload.extraction;
  const artifact = {
    schema: REPRO_SCHEMA,
    privacy: {
      classification: "pseudonymized-local-playtest",
      direct_identifiers: "excluded",
      excluded: [...PRIVACY_EXCLUSIONS],
    },
    product: productFromEvidence(pack.report, pack.extraction),
    build: {
      tactical_pck: {
        bytes: finiteNumber(tacticalPck.bytes, "build.tactical_pck.bytes", 1, 1_000_000_000, {
          integer: true,
        }),
        sha256: boundedString(tacticalPck.sha256, "build.tactical_pck.sha256", 64, {
          pattern: SHA256_PATTERN,
        }),
      },
      browser: {
        family: "chromium",
        version: boundedString(browser.version, "build.browser.version", 64),
      },
    },
    mission: projectEvidenceMission(pack),
    provenance: {
      evidence_run_id: boundedString(pack.runId, "provenance.evidence_run_id", 128),
      source_manifest_sha256: pack.sourceManifestSha256,
      deployment_message_id: boundedString(
        pack.identity.deploymentMessageId,
        "provenance.deployment_message_id",
        256,
        { pattern: SAFE_ID_PATTERN },
      ),
      extraction_message_id: boundedString(
        pack.identity.extractionMessageId,
        "provenance.extraction_message_id",
        256,
        { pattern: SAFE_ID_PATTERN },
      ),
      correlation_id: boundedString(
        pack.identity.correlationId,
        "provenance.correlation_id",
        256,
        { pattern: SAFE_ID_PATTERN },
      ),
      extracted_at: boundedString(
        new Date(pack.extraction.created_at).toISOString(),
        "provenance.extracted_at",
        64,
      ),
      extracted_at_ms: finiteNumber(result.ts, "provenance.extracted_at_ms", 1, 9_007_199_254_740_991, {
        integer: true,
      }),
    },
    equivalence: {
      supported: [...SUPPORTED_EQUIVALENCE],
      not_claimed: [...UNSUPPORTED_EQUIVALENCE],
      mechanical_state_hash: {
        available: false,
        reason: MECHANICAL_HASH_REASON,
      },
    },
    integrity: {
      canonicalization: CANONICALIZATION,
      algorithm: "sha-256",
      mechanical_digest: "",
      artifact_digest: "",
    },
  };
  artifact.integrity.mechanical_digest = digestCanonical(mechanicalScope(artifact));
  artifact.integrity.artifact_digest = digestCanonical(artifactDigestScope(artifact));
  validateReproArtifact(artifact);
  return artifact;
}

function validateStringArray(value, expected, path) {
  if (!Array.isArray(value) || value.length !== expected.length) {
    throw new TypeError(`${path} does not match the contract.`);
  }
  value.forEach((item, index) => {
    if (item !== expected[index]) throw new TypeError(`${path}[${index}] does not match the contract.`);
  });
}

function validateProjectedMission(value) {
  const mission = exactKeys(value, ["deployment", "replay", "result"], [], "mission");
  const deployment = projectDeployment({
    ...mission.deployment,
    type: "deploy",
    atlas_state: "",
    map: {},
    squad: mission.deployment.squad.map((unit, index) => ({
      name: `unit-${index + 1}`,
      cls: unit.class,
    })),
  });
  const replay = projectReplay(mission.replay);
  const result = projectResult({
    ...mission.result,
    extraction_id: "validated-at-provenance",
    replay,
    ts: 1,
  });
  const normalized = { deployment, replay, result };
  if (stableStringify(normalized) !== stableStringify(mission)) {
    throw new TypeError("mission contains a non-canonical or unsupported field.");
  }
  validateMissionConsistency(normalized);
}

export function validateReproArtifact(value) {
  const artifact = exactKeys(
    value,
    [
      "build",
      "equivalence",
      "integrity",
      "mission",
      "privacy",
      "product",
      "provenance",
      "schema",
    ],
    [],
    "artifact",
  );
  if (artifact.schema !== REPRO_SCHEMA) throw new TypeError(`artifact.schema must be ${REPRO_SCHEMA}.`);
  const privacy = exactKeys(
    artifact.privacy,
    ["classification", "direct_identifiers", "excluded"],
    [],
    "privacy",
  );
  if (
    privacy.classification !== "pseudonymized-local-playtest"
    || privacy.direct_identifiers !== "excluded"
  ) {
    throw new TypeError("privacy classification is not supported.");
  }
  validateStringArray(privacy.excluded, PRIVACY_EXCLUSIONS, "privacy.excluded");

  const product = exactKeys(
    artifact.product,
    ["galaxy", "harness", "platform", "version"],
    [],
    "product",
  );
  if (product.galaxy !== "BattleStarSol" || product.platform !== "godot-web") {
    throw new TypeError("product identity is not supported.");
  }
  boundedString(product.version, "product.version", 64);
  boundedString(product.harness, "product.harness", 120);

  const build = exactKeys(artifact.build, ["browser", "tactical_pck"], [], "build");
  const pck = exactKeys(build.tactical_pck, ["bytes", "sha256"], [], "build.tactical_pck");
  finiteNumber(pck.bytes, "build.tactical_pck.bytes", 1, 1_000_000_000, { integer: true });
  boundedString(pck.sha256, "build.tactical_pck.sha256", 64, { pattern: SHA256_PATTERN });
  const browser = exactKeys(build.browser, ["family", "version"], [], "build.browser");
  if (browser.family !== "chromium") throw new TypeError("build.browser.family is not supported.");
  boundedString(browser.version, "build.browser.version", 64);

  validateProjectedMission(artifact.mission);

  const provenance = exactKeys(
    artifact.provenance,
    [
      "correlation_id",
      "deployment_message_id",
      "evidence_run_id",
      "extracted_at",
      "extracted_at_ms",
      "extraction_message_id",
      "source_manifest_sha256",
    ],
    [],
    "provenance",
  );
  boundedString(provenance.evidence_run_id, "provenance.evidence_run_id", 128);
  boundedString(provenance.source_manifest_sha256, "provenance.source_manifest_sha256", 64, {
    pattern: SHA256_PATTERN,
  });
  for (const key of ["deployment_message_id", "extraction_message_id", "correlation_id"]) {
    boundedString(provenance[key], `provenance.${key}`, 256, { pattern: SAFE_ID_PATTERN });
  }
  if (provenance.deployment_message_id !== provenance.correlation_id) {
    throw new TypeError("provenance correlation_id does not match deployment_message_id.");
  }
  if (provenance.extraction_message_id === provenance.deployment_message_id) {
    throw new TypeError("provenance extraction and deployment IDs must differ.");
  }
  boundedString(provenance.extracted_at, "provenance.extracted_at", 64);
  if (Number.isNaN(Date.parse(provenance.extracted_at))) {
    throw new TypeError("provenance.extracted_at is not a timestamp.");
  }
  finiteNumber(
    provenance.extracted_at_ms,
    "provenance.extracted_at_ms",
    1,
    9_007_199_254_740_991,
    { integer: true },
  );
  if (Math.abs(Date.parse(provenance.extracted_at) - provenance.extracted_at_ms) > 2_000) {
    throw new TypeError("provenance extraction timestamps differ.");
  }

  const equivalence = exactKeys(
    artifact.equivalence,
    ["mechanical_state_hash", "not_claimed", "supported"],
    [],
    "equivalence",
  );
  validateStringArray(equivalence.supported, SUPPORTED_EQUIVALENCE, "equivalence.supported");
  validateStringArray(equivalence.not_claimed, UNSUPPORTED_EQUIVALENCE, "equivalence.not_claimed");
  const mechanicalHash = exactKeys(
    equivalence.mechanical_state_hash,
    ["available", "reason"],
    [],
    "equivalence.mechanical_state_hash",
  );
  if (mechanicalHash.available !== false || mechanicalHash.reason !== MECHANICAL_HASH_REASON) {
    throw new TypeError("equivalence.mechanical_state_hash overstates current evidence.");
  }

  const integrity = exactKeys(
    artifact.integrity,
    ["algorithm", "artifact_digest", "canonicalization", "mechanical_digest"],
    [],
    "integrity",
  );
  if (integrity.canonicalization !== CANONICALIZATION || integrity.algorithm !== "sha-256") {
    throw new TypeError("integrity algorithm or canonicalization is unsupported.");
  }
  for (const key of ["mechanical_digest", "artifact_digest"]) {
    boundedString(integrity[key], `integrity.${key}`, 64, { pattern: SHA256_PATTERN });
  }
  const mechanicalDigest = digestCanonical(mechanicalScope(artifact));
  if (integrity.mechanical_digest !== mechanicalDigest) {
    throw new TypeError("Mechanical digest does not match the canonical supported scope.");
  }
  const artifactDigest = digestCanonical(artifactDigestScope(artifact));
  if (integrity.artifact_digest !== artifactDigest) {
    throw new TypeError("Artifact digest does not match the canonical artifact scope.");
  }
  const bytes = Buffer.byteLength(stableStringify(artifact), "utf8");
  if (bytes > MAX_REPRO_BYTES) throw new RangeError(`Reproduction artifact exceeds ${MAX_REPRO_BYTES} bytes.`);
  return Object.freeze({
    schema: artifact.schema,
    bytes,
    mechanicalDigest,
    artifactDigest,
    actionCount: artifact.mission.replay.actions.length,
    eventCount: artifact.mission.replay.events.length,
  });
}

export function reconstructExtractionMessage(artifact) {
  validateReproArtifact(artifact);
  const result = artifact.mission.result;
  return {
    gzg: "galaxy-message",
    version: "1.0",
    id: artifact.provenance.extraction_message_id,
    type: "xcommand.extraction",
    source: {
      galaxy: "xCommand",
      version: artifact.product.version,
      instance: "godot-web",
    },
    target: {
      galaxy: "BattleStarSol",
      capability: "strategic.receive-extraction",
    },
    created_at: artifact.provenance.extracted_at,
    correlation_id: artifact.provenance.correlation_id,
    payload: {
      schema: "gzg.xcommand.extraction/1.0",
      extraction: {
        ...result,
        replay: artifact.mission.replay,
        ts: artifact.provenance.extracted_at_ms,
        extraction_id: artifact.provenance.extraction_message_id,
      },
    },
  };
}

function mechanicalMissionSummary(mission) {
  return {
    sector: mission.sector,
    seed: mission.seed,
    outcome: mission.outcome,
    survivors: mission.survivors,
    gains: mission.gains,
  };
}

export function reimportReproArtifact(artifact, bridge, profile = bridge?.defaultProfile?.()) {
  const validation = validateReproArtifact(artifact);
  if (!bridge?.normalizeExtraction || !bridge?.applyExtraction || !bridge?.defaultProfile) {
    throw new TypeError("A BattleStarSol bridge implementation is required.");
  }
  const message = reconstructExtractionMessage(artifact);
  const normalized = bridge.normalizeExtraction(message);
  const before = bridge.normalizeProfile(profile);
  const first = bridge.applyExtraction(before, normalized);
  const second = bridge.applyExtraction(first.profile, normalized);
  const expected = artifact.mission.result;
  const mission = first.profile.missions.at(-1);
  const expectedResources = {
    neural: before.resources.neural + expected.gains.neural,
    capital: before.resources.capital + expected.gains.capital,
    alloys: before.resources.alloys + expected.gains.alloys,
  };
  const importedResources = {
    neural: first.profile.resources.neural,
    capital: first.profile.resources.capital,
    alloys: first.profile.resources.alloys,
  };
  const importedSummary = {
    sector: mission?.sector,
    seed: mission?.seed,
    outcome: mission?.outcome,
    survivors: mission?.survivors,
    gains: {
      neural: mission?.gains?.neural,
      capital: mission?.gains?.capital,
      alloys: mission?.gains?.alloys,
      loot: [],
    },
  };
  if (!first.changed) throw new TypeError("Clean-state reproduction import did not apply.");
  if (second.changed) throw new TypeError("Duplicate reproduction import was not idempotent.");
  if (stableStringify(importedResources) !== stableStringify(expectedResources)) {
    throw new TypeError("Strategic resource delta differs from the declared result.");
  }
  if (
    stableStringify(importedSummary)
    !== stableStringify(mechanicalMissionSummary(expected))
  ) {
    throw new TypeError("Strategic mission summary differs from the declared result.");
  }
  if (second.profile.missions.length !== first.profile.missions.length) {
    throw new TypeError("Duplicate reproduction import changed mission history.");
  }
  return Object.freeze({
    schema: "gzg.battlestar.repro-import-report/1.0",
    artifact_digest: validation.artifactDigest,
    mechanical_digest: validation.mechanicalDigest,
    supported_equivalence: [...SUPPORTED_EQUIVALENCE],
    not_claimed: [...UNSUPPORTED_EQUIVALENCE],
    result: mechanicalMissionSummary(expected),
    strategic_import: {
      first_changed: first.changed,
      duplicate_changed: second.changed,
      mission_count: second.profile.missions.length,
      resources_before: {
        neural: before.resources.neural,
        capital: before.resources.capital,
        alloys: before.resources.alloys,
      },
      resources_after: importedResources,
    },
  });
}

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

export function loadBridgeForNode() {
  const source = readFileSync(new URL("../game/web/bridge.js", import.meta.url), "utf8");
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

function readArtifact(path) {
  const info = lstatSync(path);
  if (!info.isFile() || info.isSymbolicLink()) {
    throw new TypeError("Reproduction artifact must be a real file.");
  }
  if (info.size > MAX_REPRO_BYTES * 2) throw new RangeError("Reproduction artifact file is too large.");
  return JSON.parse(readFileSync(path, "utf8"));
}

async function runCli() {
  const [command, input, output] = process.argv.slice(2);
  if (command === "export" && input && output) {
    const artifact = createReproArtifact(input);
    const report = reimportReproArtifact(artifact, loadBridgeForNode());
    const destination = resolve(output);
    mkdirSync(dirname(destination), { recursive: true });
    writeFileSync(destination, `${JSON.stringify(artifact, null, 2)}\n`, { flag: "wx" });
    console.log(JSON.stringify(report, null, 2));
    return;
  }
  if (command === "verify" && input && !output) {
    const artifact = readArtifact(resolve(input));
    console.log(JSON.stringify(reimportReproArtifact(artifact, loadBridgeForNode()), null, 2));
    return;
  }
  throw new Error(
    "Usage: node tools/repro-bundle.mjs export <finalized-pack-dir> <artifact.json> | verify <artifact.json>",
  );
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runCli().catch((error) => {
    console.error(error?.stack || error);
    process.exitCode = 1;
  });
}
