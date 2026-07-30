import assert from "node:assert/strict";
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { afterEach, test } from "node:test";

import {
  DEFAULT_BASE_URL,
  EvidenceIdentityError,
  beginEvidenceRun,
  finalizeEvidenceRun,
  makeRunId,
  normalizeBaseUrl,
  probeDevServer,
  resolveChromiumExecutable,
  verifySha256Manifest,
  writeArtifactExclusive,
} from "../tools/playtest/evidence-pack.mjs";

const temporaryRoots = [];

afterEach(() => {
  while (temporaryRoots.length) {
    const target = temporaryRoots.pop();
    rmSync(target, { recursive: true, force: true });
  }
});

function temporaryRoot() {
  const root = mkdtempSync(join(tmpdir(), "bss-evidence-test-"));
  temporaryRoots.push(root);
  return root;
}

function fixture(run, { result = "PASS" } = {}) {
  const startedAt = "2026-07-29T06:35:32.000Z";
  const extractedAt = "2026-07-29T06:35:40.000Z";
  const finishedAt = "2026-07-29T06:35:50.000Z";
  const seed = 1167583760;
  const deployment = {
    gzg: "galaxy-message",
    type: "battlestar.deploy",
    id: `battlestar:${seed}:1`,
    payload: {
      schema: "gzg.battlestar.deploy/1.0",
      deploy: { seed },
    },
  };
  const extractionId = `xcommand:${seed}:${Date.parse(extractedAt)}`;
  const extraction = {
    gzg: "galaxy-message",
    type: "xcommand.extraction",
    id: extractionId,
    correlation_id: deployment.id,
    created_at: extractedAt,
    payload: {
      schema: "gzg.xcommand.extraction/1.0",
      extraction: {
        extraction_id: extractionId,
        seed,
        ts: Date.parse(extractedAt),
        replay: {
          actions: [{ sequence: 1, action: "select" }],
          events: [{ sequence: 2, event: "mission_resolved" }],
        },
      },
    },
  };

  const screenshot = writeArtifactExclusive(run, "screenshots/01-strategic.png", Buffer.from("png bytes"));
  const extractionArtifact = writeArtifactExclusive(
    run,
    "extraction.json",
    `${JSON.stringify(extraction, null, 2)}\n`,
  );
  const report = {
    run_id: run.runId,
    started_at: startedAt,
    finished_at: finishedAt,
    result,
    identity: {
      run_id: run.runId,
      deployment_message_id: deployment.id,
      extraction_message_id: extraction.id,
      extraction_id: extraction.payload.extraction.extraction_id,
      correlation_id: extraction.correlation_id,
      seed,
      extracted_at: extraction.created_at,
    },
    deployment,
    ledger: {
      extraction_id: extraction.id,
      seed,
      action_count: 1,
      event_count: 1,
    },
    screenshots: [{
      run_id: run.runId,
      label: "strategic",
      at: startedAt,
      ...screenshot,
    }],
    artifacts: {
      extraction: extractionArtifact,
    },
  };
  writeArtifactExclusive(run, "playtest-report.json", `${JSON.stringify(report, null, 2)}\n`);
  return { deployment, extraction, report };
}

test("run IDs are deterministic, Windows-safe, and compact", () => {
  const value = makeRunId({
    now: new Date("2026-07-29T06:35:32.568Z"),
    uuid: "a1b2c3d4-e5f6-7890-abcd-ef0123456789",
  });
  assert.equal(value, "20260729T063532568Z-a1b2c3d4");
  assert.doesNotMatch(value, /[:\\/]/);
});

test("the canonical playtest port is 8781 and URLs are normalized", () => {
  assert.equal(DEFAULT_BASE_URL, "http://127.0.0.1:8781/");
  assert.equal(normalizeBaseUrl("http://127.0.0.1:8781"), DEFAULT_BASE_URL);
  assert.equal(normalizeBaseUrl("https://example.test/game"), "https://example.test/game/");
  assert.throws(() => normalizeBaseUrl("file:///tmp/game"), /HTTP or HTTPS/);
});

test("PW_CHROMIUM is authoritative and missing explicit paths fail closed", () => {
  const existing = "C:\\Browser\\chrome.exe";
  assert.deepEqual(
    resolveChromiumExecutable({
      env: { PW_CHROMIUM: `"${existing}"` },
      platform: "win32",
      exists: (candidate) => candidate === existing,
    }),
    { path: existing, source: "PW_CHROMIUM" },
  );
  assert.throws(
    () => resolveChromiumExecutable({
      env: { PW_CHROMIUM: "C:\\missing\\chrome.exe" },
      platform: "win32",
      exists: () => false,
    }),
    /PW_CHROMIUM does not point to an existing file/,
  );
});

test("Windows browser discovery is a fallback only when PW_CHROMIUM is unset", () => {
  const expected = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
  const result = resolveChromiumExecutable({
    env: { ProgramFiles: "C:\\Program Files" },
    platform: "win32",
    exists: (candidate) => candidate === expected,
  });
  assert.deepEqual(result, { path: expected, source: "windows-chrome" });
});

test("the server probe requires the canonical development-server marker", async () => {
  const success = await probeDevServer("http://127.0.0.1:8781", {
    fetchImpl: async (url, options) => ({
      ok: true,
      status: 200,
      headers: { get: (name) => name === "x-battlestar-dev-server" ? "1" : null },
      observed: { url, options },
    }),
  });
  assert.deepEqual(success, {
    url: "http://127.0.0.1:8781/",
    status: 200,
    marker: "1",
  });
  await assert.rejects(
    probeDevServer(DEFAULT_BASE_URL, {
      fetchImpl: async () => ({
        ok: true,
        status: 200,
        headers: { get: () => null },
      }),
    }),
    /not the canonical/,
  );
});

test("run workspaces are exclusive and never reuse a final or partial directory", () => {
  const root = temporaryRoot();
  const runId = "20260729T063532568Z-a1b2c3d4";
  const run = beginEvidenceRun(root, { runId });
  assert.equal(existsSync(run.partialDir), true);
  assert.throws(() => beginEvidenceRun(root, { runId }), /EEXIST|already exists/);
});

test("a complete PASS run finalizes atomically with a verified manifest", () => {
  const root = temporaryRoot();
  const run = beginEvidenceRun(root, { runId: "20260729T063532568Z-a1b2c3d4" });
  fixture(run);
  const finalized = finalizeEvidenceRun(run);
  assert.equal(existsSync(run.partialDir), false);
  assert.equal(existsSync(finalized.finalDir), true);
  const manifest = readFileSync(join(finalized.finalDir, "SHA256SUMS"), "utf8");
  const checked = verifySha256Manifest(finalized.finalDir, manifest);
  assert.deepEqual(
    checked.map((entry) => entry.file).sort(),
    ["extraction.json", "playtest-report.json", "screenshots/01-strategic.png"],
  );
});

test("a complete negative run is valid evidence and also finalizes", () => {
  const root = temporaryRoot();
  const run = beginEvidenceRun(root, { runId: "20260729T063532568Z-b1b2c3d4" });
  fixture(run, { result: "FAIL" });
  const finalized = finalizeEvidenceRun(run);
  const report = JSON.parse(readFileSync(join(finalized.finalDir, "playtest-report.json"), "utf8"));
  assert.equal(report.result, "FAIL");
});

test("mismatched extraction identity prevents promotion and preserves partial evidence", () => {
  const root = temporaryRoot();
  const run = beginEvidenceRun(root, { runId: "20260729T063532568Z-c1b2c3d4" });
  fixture(run);
  const extractionPath = join(run.partialDir, "extraction.json");
  const extraction = JSON.parse(readFileSync(extractionPath, "utf8"));
  extraction.id = "xcommand:other-run";
  writeFileSync(extractionPath, `${JSON.stringify(extraction, null, 2)}\n`);
  assert.throws(() => finalizeEvidenceRun(run), EvidenceIdentityError);
  assert.equal(existsSync(run.partialDir), true);
  assert.equal(existsSync(run.finalDir), false);
});

test("screenshot tampering prevents finalization", () => {
  const root = temporaryRoot();
  const run = beginEvidenceRun(root, { runId: "20260729T063532568Z-d1b2c3d4" });
  fixture(run);
  writeFileSync(join(run.partialDir, "screenshots", "01-strategic.png"), "tampered");
  assert.throws(() => finalizeEvidenceRun(run), /screenshot hash or size differs/);
  assert.equal(existsSync(run.partialDir), true);
});

test("a finalized manifest detects later tampering", () => {
  const root = temporaryRoot();
  const run = beginEvidenceRun(root, { runId: "20260729T063532568Z-e1b2c3d4" });
  fixture(run);
  const finalized = finalizeEvidenceRun(run);
  const manifestPath = join(finalized.finalDir, "SHA256SUMS");
  const manifest = readFileSync(manifestPath, "utf8");
  writeFileSync(join(finalized.finalDir, "extraction.json"), "{}\n");
  assert.throws(
    () => verifySha256Manifest(finalized.finalDir, manifest),
    /SHA-256 mismatch for extraction.json/,
  );
});
