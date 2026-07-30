import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const playtestsDir = join(repoRoot, "evidence", "playtests");

// A `.partial` evidence directory is, by definition, a run that never reached atomic
// promotion. Promotion is a rename: the pack becomes evidence at the instant it is
// complete and hashed, and not one step earlier. A committed `.partial` directory is
// therefore an unfinished run wearing the clothes of a result, and the surrounding
// documentation would present it as one. `.gitignore` alone is not a control -- it is a
// default that `git add -f` overrides and that a fresh clone can lose -- so the boundary
// is asserted here as well.

function trackedPaths() {
  let output;
  try {
    output = execFileSync("git", ["ls-files"], {
      cwd: repoRoot,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
  } catch (error) {
    // Fail closed rather than skip. A run that cannot see what is tracked cannot make
    // any claim about evidence hygiene, and silently passing would be the worse outcome.
    assert.fail(
      `evidence hygiene could not enumerate tracked files (git unavailable or not a checkout): ${error.message}`,
    );
  }
  return output.split("\n").filter((line) => line.length > 0);
}

function packDirectories() {
  if (!existsSync(playtestsDir)) {
    return [];
  }
  return readdirSync(playtestsDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name);
}

test("no partial evidence pack is tracked", () => {
  const offenders = trackedPaths().filter((path) => path.includes(".partial/"));
  assert.deepEqual(
    offenders,
    [],
    `partial evidence packs must never be committed; an unpromoted run would be published as a result. Offending paths: ${offenders.join(", ")}`,
  );
});

test("the partial-pack pattern is ignored by default", () => {
  const ignoreFile = join(repoRoot, ".gitignore");
  assert.ok(existsSync(ignoreFile), ".gitignore is missing");
  const patterns = readFileSync(ignoreFile, "utf8")
    .split("\n")
    .map((line) => line.trim());
  assert.ok(
    patterns.includes("*.partial/"),
    "`.gitignore` must carry `*.partial/` so an unpromoted run is not offered to `git add -A` in the first place",
  );
});

test("every promoted evidence pack carries its manifest", () => {
  const promoted = packDirectories().filter((name) => !name.endsWith(".partial"));
  // Not an assertion about how many packs exist -- a fresh checkout legitimately has
  // none. It asserts that whatever is present is complete.
  for (const name of promoted) {
    const manifest = join(playtestsDir, name, "SHA256SUMS");
    assert.ok(
      existsSync(manifest),
      `promoted evidence pack '${name}' has no SHA256SUMS, so nothing ties its artifacts to the run that produced them`,
    );
  }
});

test("no promoted evidence pack records a harness error", () => {
  const promoted = packDirectories().filter((name) => !name.endsWith(".partial"));
  for (const name of promoted) {
    const harnessError = join(playtestsDir, name, "HARNESS-ERROR.json");
    assert.ok(
      !existsSync(harnessError),
      `promoted evidence pack '${name}' contains HARNESS-ERROR.json -- a run that failed in the harness must stay '.partial' rather than being promoted to evidence`,
    );
  }
});
