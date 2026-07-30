import { deterministicD10 } from "./core.mjs";

function assertInteger(value, label, minimum, maximum) {
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new RangeError(`${label} must be an integer from ${minimum} through ${maximum}.`);
  }
}

export function roundHalfAwayFromZero(value) {
  if (!Number.isFinite(value)) {
    throw new TypeError("A finite number is required.");
  }
  return Math.sign(value) * Math.floor(Math.abs(value) + 0.5);
}

export function abilityModifier(score) {
  assertInteger(score, "Ability score", 4, 20);
  // The canonical published table controls odd scores. Convert the legacy
  // d20 modifier first, then halve it; this preserves 4–5 => -2.
  const legacyD20Modifier = Math.floor((score - 10) / 2);
  return roundHalfAwayFromZero(legacyD20Modifier / 2);
}

export function scaleD20DC(dc) {
  if (!Number.isFinite(dc) || dc < 1) {
    throw new RangeError("DC must be a positive number.");
  }
  return Math.ceil(dc / 2);
}

export function resolveCheck({
  roll,
  confirmation = null,
  abilityScore,
  skillRanks,
  situational = 0,
  dc,
}) {
  assertInteger(roll, "Roll", 1, 10);
  assertInteger(abilityScore, "Ability score", 4, 20);
  assertInteger(skillRanks, "Skill ranks", 0, 10);
  assertInteger(situational, "Situational modifier", -10, 10);
  assertInteger(dc, "Difficulty class", 1, 30);

  const threat = roll === 10 ? "success" : roll === 1 ? "failure" : null;
  if (threat !== null) {
    assertInteger(confirmation, "Confirmation", 1, 10);
  }

  const confirmed = threat !== null && confirmation >= 6;
  const modifier = abilityModifier(abilityScore);
  const total = roll + modifier + skillRanks + situational;
  let outcome = total >= dc ? "success" : "failure";

  if (confirmed && threat === "success") {
    outcome = "critical_success";
  } else if (confirmed && threat === "failure") {
    outcome = "critical_failure";
  }

  return {
    schema: "gzg.d10.check-result/0.1",
    roll,
    confirmation: threat === null ? null : confirmation,
    threat,
    confirmed,
    ability_score: abilityScore,
    ability_modifier: modifier,
    skill_ranks: skillRanks,
    situational,
    dc,
    total,
    outcome,
  };
}

export async function rollCheck(seed, inputs) {
  const roll = await deterministicD10(seed, "primary");
  const confirmation = roll === 1 || roll === 10
    ? await deterministicD10(seed, "confirmation")
    : null;
  return resolveCheck({ ...inputs, roll, confirmation });
}
