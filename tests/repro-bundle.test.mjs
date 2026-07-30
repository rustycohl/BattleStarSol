import assert from "node:assert/strict";
import {
  cpSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { afterEach, test } from "node:test";
import { fileURLToPath } from "node:url";

import {
  MAX_ACTIONS,
  REPRO_SCHEMA,
  createReproArtifact,
  loadBridgeForNode,
  loadEvidencePack,
  reimportReproArtifact,
  stableStringify,
  validateReproArtifact,
} from "../tools/repro-bundle.mjs";

const passPack = fileURLToPath(new URL(
  "../evidence/playtests/20260729T104417824Z-b0e26ed0/",
  import.meta.url,
));
const negativePack = fileURLToPath(new URL(
  "../evidence/playtests/20260729T104213250Z-844cc201/",
  import.meta.url,
));
const generatedArtifact = new URL(
  "../evidence/reproductions/20260729T104417824Z-b0e26ed0/battlestar-repro.json",
  import.meta.url,
);
const temporaryRoots = [];

afterEach(() => {
  while (temporaryRoots.length) {
    rmSync(temporaryRoots.pop(), { recursive: true, force: true });
  }
});

function temporaryCopy(source = passPack) {
  const holder = mkdtempSync(join(tmpdir(), "bss-repro-test-"));
  temporaryRoots.push(holder);
  const target = join(holder, "pack");
  cpSync(source, target, { recursive: true });
  return target;
}

function clone(value) {
  return structuredClone(value);
}

test("the reproduction contract is strict JSON Schema 2020-12", () => {
  const schema = JSON.parse(
    readFileSync(new URL("../contracts/battlestar-repro.schema.json", import.meta.url), "utf8"),
  );
  assert.equal(schema.$schema, "https://json-schema.org/draft/2020-12/schema");
  assert.equal(schema.properties.schema.const, REPRO_SCHEMA);
  assert.equal(schema.additionalProperties, false);
  assert.equal(schema.$defs.action.additionalProperties, false);
  assert.equal(schema.$defs.replay.properties.actions.maxItems, MAX_ACTIONS);
});

test("canonical JSON sorts nested keys and rejects ambiguous values", () => {
  assert.equal(
    stableStringify({ z: 2, a: { two: 2, one: 1 } }),
    stableStringify({ a: { one: 1, two: 2 }, z: 2 }),
  );
  assert.throws(() => stableStringify({ value: undefined }), /undefined/);
  assert.throws(() => stableStringify({ value: Number.NaN }), /non-finite/);
  assert.throws(() => stableStringify(new Date()), /plain object/);
});

test("the authoritative PASS pack creates the checked-in artifact deterministically", () => {
  const first = createReproArtifact(passPack);
  const second = createReproArtifact(passPack);
  const checkedIn = JSON.parse(readFileSync(generatedArtifact, "utf8"));
  assert.deepEqual(first, second);
  assert.deepEqual(first, checkedIn);
  assert.equal(first.integrity.mechanical_digest, "d830f0e8944e6614cd2e630b7a70a8756f5023dbe0e9fbf9ca4bb5f4e218f0f2");
  assert.equal(first.integrity.artifact_digest, "05fc6100c000088e02d11396edf79f183f152c22f3f4523b2f56408ab914a628");
  assert.equal(first.mission.replay.actions.length, 5);
  assert.equal(first.mission.replay.events.length, 30);
});

test("the bounded artifact excludes direct-name and browser/profile surfaces", () => {
  const raw = readFileSync(generatedArtifact, "utf8");
  for (const forbidden of [
    "AUTOPILOT",
    "atlas_state",
    "latitude",
    "longitude",
    "console_lines",
    "screenshots/",
    "localStorage",
    "PW_CHROMIUM",
    "C:\\\\Users\\\\",
  ]) {
    assert.equal(raw.includes(forbidden), false, `artifact leaked ${forbidden}`);
  }
  const artifact = JSON.parse(raw);
  assert.deepEqual(
    artifact.mission.deployment.squad.map((unit) => Object.keys(unit).sort()),
    [["class", "slot"], ["class", "slot"], ["class", "slot"]],
  );
  assert.equal(artifact.privacy.direct_identifiers, "excluded");
});

test("clean-state strategic re-import reproduces the result and is duplicate-idempotent", () => {
  const artifact = JSON.parse(readFileSync(generatedArtifact, "utf8"));
  const report = reimportReproArtifact(artifact, loadBridgeForNode());
  assert.deepEqual(report.result, {
    sector: "Proving Ground",
    seed: 1167583760,
    outcome: "SUCCESS",
    survivors: 3,
    gains: { neural: 25, capital: 301, alloys: 0, loot: [] },
  });
  assert.deepEqual(report.strategic_import, {
    first_changed: true,
    duplicate_changed: false,
    mission_count: 1,
    resources_before: { neural: 50, capital: 25000, alloys: 100 },
    resources_after: { neural: 75, capital: 25301, alloys: 100 },
  });
  assert.ok(report.not_claimed.includes("Godot mechanical re-simulation from the action ledger"));
});

test("canonical or declared-result tampering invalidates the artifact digest", () => {
  const artifact = JSON.parse(readFileSync(generatedArtifact, "utf8"));
  artifact.mission.result.survivors += 1;
  assert.throws(() => validateReproArtifact(artifact), /mission_resolved|digest/);
});

test("unsupported and explicitly sensitive fields fail closed", () => {
  const artifact = JSON.parse(readFileSync(generatedArtifact, "utf8"));
  const unknown = clone(artifact);
  unknown.mission.result.future_field = true;
  assert.throws(() => validateReproArtifact(unknown), /not supported/);
  const sensitive = clone(artifact);
  sensitive.profile_path = "C:\\Users\\someone";
  assert.throws(() => validateReproArtifact(sensitive), /forbidden sensitive field/);
});

test("non-finite values and oversized ledgers fail closed", () => {
  const artifact = JSON.parse(readFileSync(generatedArtifact, "utf8"));
  const nonFinite = clone(artifact);
  nonFinite.mission.result.gains.capital = Number.NaN;
  assert.throws(() => validateReproArtifact(nonFinite), /finite number|non-finite/);

  const oversized = clone(artifact);
  const template = oversized.mission.replay.actions[0];
  oversized.mission.replay.actions = Array.from(
    { length: MAX_ACTIONS + 1 },
    (_, index) => ({ ...clone(template), sequence: index + 1 }),
  );
  assert.throws(() => validateReproArtifact(oversized), /exceeds 256/);
});

test("terrain destruction is carried in the reproduction contract and fails closed", () => {
  const artifact = JSON.parse(readFileSync(generatedArtifact, "utf8"));
  const events = artifact.mission.replay.events;
  const template = events[events.length - 1];
  const terrainEvent = (overrides = {}) => ({
    sequence: template.sequence + 1,
    record_type: "event",
    event: "terrain_damaged",
    payload: {
      attacker: 1,
      cell: { x: 4, y: 7, z: 3 },
      cover_after: 1,
      cover_before: 2,
      destroyed: false,
      integrity_after: 32,
      integrity_before: 60,
      material_after: "soft",
      material_before: "hard",
      weapon: "t1_rifle",
      ...overrides,
    },
  });

  // A well-formed terrain change passes shape validation. Appending any event to
  // a sealed artifact must still fail on the mechanical digest — that is the
  // contract refusing an unrecomputed ledger, not a rejection of the payload.
  const accepted = clone(artifact);
  accepted.mission.replay.events = [...clone(events), terrainEvent()];
  assert.throws(() => validateReproArtifact(accepted), /Mechanical digest/);

  // An unattributed environmental change reports attacker 0 and an empty weapon,
  // and reaches the same digest boundary rather than a shape error.
  const environmental = clone(artifact);
  environmental.mission.replay.events = [
    ...clone(events),
    terrainEvent({ attacker: 0, weapon: "" }),
  ];
  assert.throws(() => validateReproArtifact(environmental), /Mechanical digest/);

  // Out-of-range material state, unknown payload keys, and non-finite integrity
  // all fail closed rather than reaching an importer.
  for (const [overrides, pattern] of [
    [{ cover_before: 3 }, /cover_before/],
    [{ integrity_after: 101 }, /integrity_after/],
    [{ integrity_before: Number.NaN }, /finite integer|non-finite/],
    [{ material_after: "hard cover" }, /material_after/],
    [{ future_field: true }, /not supported/],
  ]) {
    const rejected = clone(artifact);
    rejected.mission.replay.events = [...clone(events), terrainEvent(overrides)];
    assert.throws(() => validateReproArtifact(rejected), pattern);
  }

  // A terrain change alters the mechanical scope, so it cannot be dropped or
  // forged without changing the artifact's digest.
  const baseline = stableStringify(clone(artifact).mission.replay.events);
  assert.notEqual(baseline, stableStringify(accepted.mission.replay.events));
});

test("clean evidence import rejects files absent from SHA256SUMS", () => {
  const copy = temporaryCopy();
  writeFileSync(join(copy, "unmanifested.txt"), "must fail\n");
  assert.throws(() => loadEvidencePack(copy), /unmanifested file/);
});

test("clean evidence import rejects symbolic-link and junction content", () => {
  const copy = temporaryCopy();
  symlinkSync(join(copy, "screenshots"), join(copy, "linked-screenshots"), "junction");
  assert.throws(() => loadEvidencePack(copy), /symbolic links/);
});

test("a finalized negative pack remains evidence but cannot source the authoritative artifact", () => {
  const imported = loadEvidencePack(negativePack, { requirePass: false });
  assert.equal(imported.report.result, "FAIL");
  assert.throws(() => createReproArtifact(negativePack), /must be a PASS pack/);
});

test("artifact validation reports the bounded canonical import surface", () => {
  const artifact = JSON.parse(readFileSync(generatedArtifact, "utf8"));
  const validation = validateReproArtifact(artifact);
  assert.equal(validation.schema, REPRO_SCHEMA);
  assert.equal(validation.actionCount, 5);
  assert.equal(validation.eventCount, 30);
  assert.ok(validation.bytes < 10_000);
});
