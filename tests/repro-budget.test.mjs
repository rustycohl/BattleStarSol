import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

import { MAX_EVENTS, MAX_REPRO_BYTES } from "../tools/repro-bundle.mjs";

// The reproduction artifact's caps are enforced by the Node bundler, which the Godot runtime
// cannot import. `game/data/repro_budget.json` is their res://-readable view so the game can
// tell a player how much budget is left — Option E from
// evidence/OBSERVATION-001-LEDGER-CAPACITY-2026-07-30.md, whose finding was that the worst
// property of this limit is its silence.
//
// A copy of a number is a number that can drift. These assertions are what make the copy safe,
// exactly as tests/d10srd-conformance.test.mjs does for the rules pin.

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const pin = JSON.parse(
  readFileSync(join(repoRoot, "game", "data", "repro_budget.json"), "utf8"),
);

test("the in-game budget pin matches the bundler's caps", () => {
  assert.equal(
    pin.max_events,
    MAX_EVENTS,
    "game/data/repro_budget.json disagrees with MAX_EVENTS in tools/repro-bundle.mjs -- the in-play readout would lie about the remaining budget",
  );
  assert.equal(
    pin.max_repro_bytes,
    MAX_REPRO_BYTES,
    "game/data/repro_budget.json disagrees with MAX_REPRO_BYTES in tools/repro-bundle.mjs",
  );
});

test("the warning threshold leaves usable room", () => {
  // A warning at or above the cap is not a warning, it is a post-mortem. The entire point of
  // Option E is that the information arrives while the mission can still be ended cleanly.
  assert.ok(
    typeof pin.warn_at_fraction === "number",
    "the pin carries no warning threshold",
  );
  assert.ok(
    pin.warn_at_fraction > 0 && pin.warn_at_fraction < 1,
    `warn_at_fraction must sit strictly between 0 and 1, found ${pin.warn_at_fraction}`,
  );
});

test("the baseline overhead leaves a positive terrain budget", () => {
  assert.ok(
    Number.isInteger(pin.baseline_overhead_bytes) && pin.baseline_overhead_bytes >= 0,
    "baseline_overhead_bytes must be a non-negative integer",
  );
  assert.ok(
    pin.baseline_overhead_bytes < pin.max_repro_bytes,
    "the recorded baseline overhead meets or exceeds the byte cap, which would leave no budget at all",
  );
});

test("the measured figures record the cap that actually binds", () => {
  // The event cap alone suggested roughly forty grenades. The byte cap binds first and the
  // real figure is about eighteen. That correction is the substance of OBSERVATION-001 and
  // must not be quietly reverted to the friendlier number.
  assert.equal(
    pin.measured.binding_cap,
    "bytes",
    "the pin no longer records bytes as the binding cap; re-measure before changing this",
  );
  assert.ok(
    pin.measured.worst_case_grenades <= 20,
    `worst_case_grenades is recorded as ${pin.measured.worst_case_grenades}; the measured figure is about 18, and the event-cap-only estimate of ~40 is the number that was wrong`,
  );
  assert.ok(
    pin.measured.terrain_events_to_exhaust_bytes < MAX_EVENTS,
    "the pin claims the byte cap binds, but records more terrain events than the event cap allows",
  );
});
