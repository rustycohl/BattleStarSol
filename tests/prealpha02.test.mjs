import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const text = (path) => readFile(new URL(path, root), "utf8");

test("pre-alpha .02 is pinned, isolated, and promotion-blocked by default", async () => {
  const manifest = JSON.parse(await text("prealpha-02-manifest.json"));

  assert.equal(manifest.schema, "gzg.battlestar.prealpha-injection/1.0");
  assert.equal(manifest.workline, "prealpha.02");
  assert.equal(manifest.state, "development");
  assert.equal(manifest.source.branch, "prealpha-02");
  assert.equal(
    manifest.source.base_commit,
    "55ecad27bf83c56225a33dc20a62a4d305f6bc89",
  );
  assert.equal(manifest.source.push_remote, "disabled");
  assert.equal(manifest.release.allow_apply, false);

  const required = new Set(manifest.release.required_modules);
  assert.deepEqual(
    [...required].sort(),
    ["M00", "M01", "M02", "M03", "M04", "M05", "M06"],
  );
  const moduleById = new Map(
    manifest.modules.map((module) => [module.id, module]),
  );
  assert.equal(moduleById.get("M00").status, "complete");
  for (const id of ["M01", "M02", "M03", "M04", "M05", "M06"]) {
    assert.notEqual(moduleById.get(id).status, "complete");
  }

  await Promise.all([
    access(new URL("docs/PREALPHA-02-RELEASE-CONTRACT.md", root)),
    access(new URL("docs/PREALPHA-02-INJECTION-LEDGER.md", root)),
    access(new URL("docs/PREALPHA-02-ANALYSIS-LOG.md", root)),
    access(new URL("tools/promote-prealpha-02.ps1", root)),
    access(new URL("game/tools/update-manifest.ps1", root)),
  ]);
});

test("promotion guard enforces the clean exact-head release boundary", async () => {
  const guard = await text("tools/promote-prealpha-02.ps1");

  assert.match(guard, /status', '--porcelain'/);
  assert.match(guard, /Target HEAD is/);
  assert.match(guard, /release\.allow_apply is false/);
  assert.match(guard, /Required module/);
  assert.match(guard, /Changed paths outside the promotion allowlist/);
  assert.match(guard, /rev-list', '--merges'/);
  assert.match(guard, /if \(\$Apply\)/);
  assert.match(guard, /cherry-pick/);
});
