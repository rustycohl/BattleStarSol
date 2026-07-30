import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

import { abilityModifier, resolveCheck, scaleD20DC } from "../vendor/d10srd/d10.mjs";

// Conformance against the d10SRD by EXECUTING the vendored rules, not by asserting numbers
// retyped into this file.
//
// The rules live in their own repository and are distributed here under their own licence.
// A conformance test that cannot run the rules is self-referential: it keeps passing while
// the published rules move underneath it. vendor/d10srd/PROVENANCE.json records the exact
// upstream commit and a digest per file, so an out-of-band edit to the vendored copy, or a
// partial update that forgets a digest, fails here rather than drifting quietly.
//
// The six vectors are the SRD's own Conformance section. Vectors 1-4 are exercised against
// the real implementation below. Vector 5 is cross-checked against both the Godot
// configuration authority and the Godot-side pin. Vector 6 is a boundary the SRD states
// about itself, asserted by requiring the sentence that states it to still be present.

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const vendorDir = join(repoRoot, "vendor", "d10srd");

const provenance = JSON.parse(readFileSync(join(vendorDir, "PROVENANCE.json"), "utf8"));
const srdText = readFileSync(join(vendorDir, "SRD.md"), "utf8");
const godotPin = JSON.parse(
  readFileSync(join(repoRoot, "game", "data", "d10srd_conformance.json"), "utf8"),
);
const gameConfig = readFileSync(join(repoRoot, "game", "scripts", "GameConfig.gd"), "utf8");

function digestOf(relativePath) {
  return createHash("sha256")
    .update(readFileSync(join(vendorDir, relativePath)))
    .digest("hex");
}

function godotConstant(name) {
  // The Godot side is the authority for its own constants; read them out of the source
  // rather than duplicating the values here.
  const match = gameConfig.match(new RegExp(`^const\\s+${name}\\s*:=\\s*(-?\\d+)`, "m"));
  assert.ok(match, `GameConfig.gd does not define ${name}`);
  return Number.parseInt(match[1], 10);
}

test("the vendored rules match their recorded provenance", () => {
  assert.ok(provenance.files.length >= 3, "provenance must cover every vendored file");
  for (const entry of provenance.files) {
    assert.equal(
      digestOf(entry.path),
      entry.sha256,
      `vendor/d10srd/${entry.path} does not match its recorded digest -- the vendored copy was edited out of band, or an update forgot to re-record it. Re-copy from ${provenance.source.repository} and update PROVENANCE.json together.`,
    );
  }
});

test("the Godot pin and the vendored rules name the same published version", () => {
  assert.equal(
    godotPin.rules_id,
    provenance.rules_id,
    "the Godot-side pin and the vendored authority disagree about which rules identifier is in force",
  );
  assert.equal(
    godotPin.srd_version,
    provenance.version,
    "the Godot-side pin and the vendored authority disagree about the SRD version -- re-pin both together",
  );
});

test("vector 1: the published ability table, including 4-5 => -2", () => {
  // The table as published, exercised against the real implementation. The 4-5 => -2 row is
  // called out in the SRD because a naive halving of the legacy d20 modifier loses it.
  const published = [
    [4, -2], [5, -2],
    [6, -1], [7, -1], [8, -1], [9, -1],
    [10, 0], [11, 0],
    [12, 1], [13, 1], [14, 1], [15, 1],
    [16, 2], [17, 2], [18, 2], [19, 2],
    [20, 3],
  ];
  for (const [score, expected] of published) {
    assert.equal(
      abilityModifier(score),
      expected,
      `ability score ${score} must yield modifier ${expected}`,
    );
  }
  // The domain is 4-20 inclusive; outside it the rules must refuse rather than extrapolate.
  assert.throws(() => abilityModifier(3), RangeError);
  assert.throws(() => abilityModifier(21), RangeError);
  assert.throws(() => abilityModifier(10.5), RangeError);
});

test("vector 2: d20 DCs 5, 10, 15, 20, 25 convert to 3, 5, 8, 10, 13", () => {
  const published = [[5, 3], [10, 5], [15, 8], [20, 10], [25, 13]];
  for (const [d20, d10] of published) {
    assert.equal(scaleD20DC(d20), d10, `d20 DC ${d20} must convert to d10 DC ${d10}`);
  }
});

test("vector 3: natural 1 and natural 10 are threats confirmed on 6 or higher", () => {
  const base = { abilityScore: 10, skillRanks: 0, situational: 0, dc: 5 };

  // A natural 10 beats DC 5 on its own; the confirmation decides whether it is critical.
  const tenUnconfirmed = resolveCheck({ ...base, roll: 10, confirmation: 5 });
  assert.equal(tenUnconfirmed.threat, "success");
  assert.equal(tenUnconfirmed.confirmed, false);
  assert.equal(tenUnconfirmed.outcome, "success");

  const tenConfirmed = resolveCheck({ ...base, roll: 10, confirmation: 6 });
  assert.equal(tenConfirmed.confirmed, true);
  assert.equal(tenConfirmed.outcome, "critical_success");

  const oneUnconfirmed = resolveCheck({ ...base, roll: 1, confirmation: 5 });
  assert.equal(oneUnconfirmed.threat, "failure");
  assert.equal(oneUnconfirmed.confirmed, false);
  assert.equal(oneUnconfirmed.outcome, "failure");

  const oneConfirmed = resolveCheck({ ...base, roll: 1, confirmation: 6 });
  assert.equal(oneConfirmed.confirmed, true);
  assert.equal(oneConfirmed.outcome, "critical_failure");

  // 6 is the floor, so 6 confirms and 5 does not -- asserted from both sides above. A
  // threat roll with no confirmation supplied must be refused rather than defaulted.
  assert.throws(() => resolveCheck({ ...base, roll: 10 }), RangeError);
  assert.throws(() => resolveCheck({ ...base, roll: 1 }), RangeError);

  // A non-threat roll carries no confirmation at all.
  const ordinary = resolveCheck({ ...base, roll: 7 });
  assert.equal(ordinary.threat, null);
  assert.equal(ordinary.confirmation, null);
});

test("vector 4: skill ranks are integers from 0 through 10", () => {
  const base = { roll: 5, abilityScore: 10, situational: 0, dc: 5 };
  for (const ranks of [0, 1, 5, 9, 10]) {
    assert.equal(resolveCheck({ ...base, skillRanks: ranks }).skill_ranks, ranks);
  }
  assert.throws(() => resolveCheck({ ...base, skillRanks: -1 }), RangeError);
  assert.throws(() => resolveCheck({ ...base, skillRanks: 11 }), RangeError);
  assert.throws(() => resolveCheck({ ...base, skillRanks: 2.5 }), RangeError);
});

test("vector 5: the tactical AP maximum is 10 on every surface that states it", () => {
  // The SRD keeps the tactical maximum at 10. Three places assert it, and they must agree:
  // the published document, the Godot configuration authority, and the Godot-side pin.
  assert.ok(
    srdText.replace(/\s+/g, " ").includes("keep the tactical AP maximum at 10"),
    "the vendored SRD no longer states the tactical AP maximum -- re-read the Conformance section before accepting the new text",
  );
  assert.equal(godotConstant("MAX_AP"), 10, "GameConfig.MAX_AP diverges from the SRD");

  const apVector = godotPin.vectors.find((vector) => vector.id === 5);
  assert.ok(apVector, "the Godot pin no longer carries conformance vector 5");
  assert.equal(
    apVector.expected,
    10,
    "the Godot pin expects an AP maximum other than the SRD's 10",
  );
});

test("vector 6: the authority boundary is still stated by the rules themselves", () => {
  // This is the sentence that keeps balance tuning out of conformance. If it ever leaves
  // the SRD, the split between _test_d10_conformance and _test_balance_baseline on the
  // Godot side stops being justified by anything, and that has to be a visible event.
  // Matched against whitespace-normalised text: the sentence is hard-wrapped in the
  // document, and where the wrap falls is not part of the rule.
  const srdFlat = srdText.replace(/\s+/g, " ");
  assert.ok(
    srdFlat.includes(
      "Do not divide health, damage, movement, range, time, capacity, currency, ammunition, action counts, or unrelated economies unless a named module explicitly says so.",
    ),
    "the SRD's 'do not divide' boundary is no longer present in the vendored document",
  );
  assert.equal(
    godotPin.authority_boundary.quote.replace(/\s+/g, " ").includes("Do not divide health, damage, movement"),
    true,
    "the Godot pin's recorded boundary quote no longer matches the SRD",
  );
});

test("every SRD conformance vector is accounted for", () => {
  // Six vectors published, six covered. A new vector appearing upstream must not be able to
  // slip in unexercised.
  const published = srdText
    .split("\n")
    .filter((line) => /^\d+\.\s/.test(line.trim()))
    .length;
  assert.ok(
    published >= 6,
    `expected at least the six published conformance vectors in the vendored SRD, found ${published}`,
  );
  assert.equal(
    godotPin.vectors.length,
    6,
    "the Godot pin no longer enumerates six vectors; if upstream published more, cover them here first",
  );
});
