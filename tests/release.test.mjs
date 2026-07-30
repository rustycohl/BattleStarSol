import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { access, readFile, stat } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const text = (path) => readFile(new URL(path, root), "utf8");

test("the Page launches the game, not a tactical substitute", async () => {
  const [strategy, launcher, bridge] = await Promise.all([
    text("game/web/index.html"),
    text("game/web/battlestar.html"),
    text("game/web/bridge.js"),
  ]);

  assert.match(strategy, /QUICK DEPLOY: PROVING GROUND/);
  assert.match(strategy, /LOCAL CAMPAIGN VAULT/);
  assert.match(strategy, /location\.assign\(url\)/);
  assert.doesNotMatch(strategy, /window\.open\(url,\s*"battlestar"\)/);
  assert.match(launcher, /tactical\/index\.html\?p=/);
  assert.match(launcher, /THIS IS THE GAME/);
  assert.match(launcher, /EXTRACT \/ F8/);
  assert.doesNotMatch(launcher, /DEMO SIM/);
  assert.match(bridge, /gzg\.battlestar\.deploy\/1\.0/);
  assert.match(bridge, /gzg\.xcommand\.extraction\/1\.0/);
  assert.match(bridge, /compactExtractionMessage/);
});

test("the committed Godot release package is present and plausible", async () => {
  const paths = [
    "game/web/tactical/index.html",
    "game/web/tactical/index.js",
    "game/web/tactical/index.pck",
    "game/web/tactical/index.wasm",
  ];
  await Promise.all(paths.map((path) => access(new URL(path, root))));

  const wasmPath = new URL("game/web/tactical/index.wasm", root);
  const [wasm, wasmInfo, packInfo] = await Promise.all([
    readFile(wasmPath),
    stat(wasmPath),
    stat(new URL("game/web/tactical/index.pck", root)),
  ]);
  assert.deepEqual([...wasm.subarray(0, 4)], [0x00, 0x61, 0x73, 0x6d]);
  assert.ok(wasmInfo.size > 30_000_000);
  assert.ok(wasmInfo.size < 100_000_000);
  assert.ok(packInfo.size > 100_000);
});

test("the embedded A.T.L.A.S. fallback is complete and static", async () => {
  const atlas = await text("game/web/atlas/index.html");
  await Promise.all([
    access(new URL("game/web/atlas/atlas.generated.css", root)),
    access(new URL("game/web/atlas/galaxy-io.js", root)),
    access(new URL("game/web/atlas/vendor/three.r128.min.js", root)),
    access(new URL("game/web/atlas/vendor/textures/earth-blue-marble.jpg", root)),
  ]);
  assert.match(atlas, /atlas\.generated\.css/);
  assert.doesNotMatch(atlas, /cdn\.tailwindcss\.com/);
  assert.doesNotMatch(atlas, /cdnjs\.cloudflare\.com\/ajax\/libs\/three/);
});

test("release claims are tied to source and deployment configuration", async () => {
  const [config, main, workflow, status, galaxy, packageJson] = await Promise.all([
    text("game/scripts/GameConfig.gd"),
    text("game/scripts/Main.gd"),
    text(".github/workflows/pages.yml"),
    text("STATUS.md"),
    text("docs/GALAXY.md"),
    text("package.json"),
  ]);
  // Derived from the package rather than pinned to a literal, so the release claim
  // and the released artifact cannot drift apart at the next version bump.
  const version = JSON.parse(packageJson).version;

  assert.match(config, /const MAX_AP := 10/);
  assert.match(main, /"emergency_evac": \[KEY_F8\]/);
  assert.match(workflow, /path: game\/web/);
  assert.ok(version.length > 0, "package.json declares no version");
  assert.ok(
    status.includes(version),
    `STATUS.md does not claim the released version ${version}`,
  );
  assert.match(galaxy, /one repository = one Page = one galaxy/);
  await access(new URL("archive/launch-surface-alpha.1/README.md", root));
});

test("standard contracts and operating documentation ship with the galaxy", async () => {
  const required = [
    "contracts/galaxy-message.schema.json",
    "contracts/battlestar-deploy.schema.json",
    "contracts/xcommand-extraction.schema.json",
    "contracts/examples/battlestar-deploy.json",
    "contracts/examples/xcommand-extraction.json",
    "docs/CONTROLS.md",
    "docs/GALAXY.md",
    "docs/IO.md",
    "docs/PROVENANCE.md",
    "docs/VALIDATION.md",
  ];
  await Promise.all(required.map((path) => access(new URL(path, root))));
});

test("the game source and committed runtime match the release manifest", async () => {
  const manifest = await text("game/MANIFEST.sha256");
  const entries = manifest.trim().split(/\r?\n/).map((line) => {
    const match = line.match(/^([0-9a-f]{64})  (.+)$/);
    assert.ok(match, `Malformed manifest line: ${line}`);
    return { digest: match[1], path: match[2] };
  });

  assert.ok(entries.length >= 120);
  for (const entry of entries) {
    const body = await readFile(new URL(`game/${entry.path}`, root));
    const actual = createHash("sha256").update(body).digest("hex");
    assert.equal(actual, entry.digest, `${entry.path} does not match MANIFEST.sha256`);
  }
});
