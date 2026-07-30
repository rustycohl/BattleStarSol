#!/usr/bin/env node

// M03-002 live positional-rationale harness.
//
// The guided Proving Ground cannot express M03 behavior: it spawns two AP-0
// Target Dummies, so no agent there can ever choose cover or a flank. This
// harness therefore deploys through the ordinary A.T.L.A.S. coordinate path,
// which spawns armed hostile agents, plays free rounds, and reads the canonical
// rationale out of the game's own extraction ledger.
//
// It changes no production behavior and picks no scenario the player could not
// reach: one globe click, one deployment, the real End Turn key, one F8
// extraction.
//
// Run the repository server first, then:
//
//   node tools/m03/standoff.mjs

import { chromium } from "playwright-core";
import { fileURLToPath } from "node:url";
import { renameSync } from "node:fs";

import {
  DEFAULT_BASE_URL,
  beginEvidenceRun,
  createSha256Manifest,
  normalizeBaseUrl,
  probeDevServer,
  resolveChromiumExecutable,
  sha256Bytes,
  verifySha256Manifest,
  writeArtifactExclusive,
} from "../playtest/evidence-pack.mjs";

const argv = process.argv.slice(2);
const argument = (flag, fallback) => {
  const index = argv.indexOf(flag);
  return index >= 0 && argv[index + 1] ? argv[index + 1] : fallback;
};

const defaultOutput = fileURLToPath(new URL("../../evidence/m03/", import.meta.url));
const browserResolution = resolveChromiumExecutable({
  playwrightExecutablePath: chromium.executablePath(),
});

const config = Object.freeze({
  base: normalizeBaseUrl(argument("--base", process.env.BSS_BASE_URL || DEFAULT_BASE_URL)),
  out: argument("--out", defaultOutput),
  headed: argv.includes("--headed"),
  callsign: String(argument("--callsign", "M03-STANDOFF")).slice(0, 40),
  rounds: Number(argument("--rounds", "8")),
  // Guided mode deploys the Proving Ground instead of an A.T.L.A.S. coordinate.
  // Since the tutorial is active there, the bounded observation surface also
  // publishes movement, cover faces, and attack targets.
  guided: argv.includes("--guided"),
  bootTimeoutMs: 90_000,
  browser: browserResolution,
});

// Canonical rationale prefixes emitted by AITactics through AIBehavior.
const COVER_SIGNATURES = Object.freeze([
  "protective cover now",
  "lean from committed cover",
  "cover has no legal attack lane",
  "cover route",
]);
const FLANK_SIGNATURES = Object.freeze(["simple flank"]);
const POSITIONAL_DECISIONS = Object.freeze(["seek_cover", "take_cover", "cover_route", "flank"]);

const launchArguments = ["--enable-unsafe-swiftshader", "--use-gl=swiftshader"];

const run = beginEvidenceRun(config.out);
const report = {
  harness: "gzg.battlestar.m03-standoff/1.0",
  run_id: run.runId,
  started_at: new Date().toISOString(),
  scope: {
    claims: [
      "an armed hostile scenario reachable through the ordinary deployment path",
      "canonical cover or flank rationale present in the game's own extraction ledger",
      "decision, position, AP, and score recorded by the game for each agent choice",
    ],
    not_claimed: [
      "guided-mode cover_faces publication, which M01 deliberately bounds to the tutorial",
      "any change to production AI, scenario generation, or the observation surface",
      "reproduction-bundle or cross-platform state equivalence",
    ],
  },
  config: {
    base: config.base,
    callsign: config.callsign,
    rounds: config.rounds,
  },
  browser: { resolver_source: config.browser.source, headed: config.headed },
  server: null,
  deployment: null,
  steps: [],
  gates: {},
  observations: {},
  findings: [],
  screenshots: [],
  artifacts: {},
};

const step = (name, ok, detail = "") => {
  report.steps.push({ name, ok: Boolean(ok), detail, at: new Date().toISOString() });
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? ` - ${detail}` : ""}`);
  return Boolean(ok);
};

const gate = (name, ok, detail = "", required = true) => {
  report.gates[name] = { ok: Boolean(ok), required: Boolean(required), detail };
  const prefix = required ? (ok ? "GATE PASS" : "GATE FAIL") : "OBSERVATION";
  console.log(`${prefix}  ${name}${detail ? ` - ${detail}` : ""}`);
};

let screenshotNumber = 0;
const capture = async (page, name) => {
  const file = `screenshots/${String(++screenshotNumber).padStart(2, "0")}-${name}.png`;
  const artifact = writeArtifactExclusive(run, file, await page.screenshot());
  report.screenshots.push({ run_id: run.runId, name, ...artifact });
  return artifact;
};

let browser = null;
let extractionRaw = "";
try {
  const server = await probeDevServer(config.base);
  const packageUrl = new URL("tactical/index.pck", config.base);
  const packageResponse = await fetch(packageUrl, { cache: "no-store" });
  if (!packageResponse.ok) {
    throw new Error(`Served tactical package returned HTTP ${packageResponse.status}.`);
  }
  const servedPackage = Buffer.from(await packageResponse.arrayBuffer());
  report.server = {
    ...server,
    tactical_pck: {
      url: packageUrl.href,
      bytes: servedPackage.byteLength,
      sha256: sha256Bytes(servedPackage),
    },
  };
  step(
    "served tactical package identified",
    true,
    `${servedPackage.byteLength} bytes sha256:${report.server.tactical_pck.sha256}`,
  );

  browser = await chromium.launch({
    executablePath: config.browser.path,
    headless: !config.headed,
    args: launchArguments,
  });
  report.browser.version = browser.version();
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    acceptDownloads: false,
  });
  const page = await context.newPage();

  await page.goto(new URL("index.html", config.base).href, {
    waitUntil: "load",
    timeout: 45_000,
  });
  await page.waitForTimeout(3_000);
  const callsign = page.locator("#callsign");
  if (await callsign.count()) {
    await callsign.fill(config.callsign);
    await callsign.press("Tab");
    await page.waitForTimeout(400);
  }

  if (config.guided) {
    // Guided mode: the product's own Quick Deploy, so the tutorial is active and
    // the bounded observation surface publishes.
    await capture(page, "strategic-console");
    await page.click("#quick");
    await page.waitForURL(/battlestar\.html/, { timeout: 20_000 });
  } else {
    // Select a coordinate on the real A.T.L.A.S. globe. Any sector other than the
    // Proving Ground takes the armed-hostile spawn path.
    const atlasCanvas = page.frameLocator("#atlas").locator("canvas").first();
    await atlasCanvas.waitFor({ state: "visible", timeout: 60_000 });
    const globe = await atlasCanvas.boundingBox();
    if (!globe) throw new Error("The A.T.L.A.S. globe has no page-space bounds.");
    await capture(page, "atlas-globe");

    let deployLabel = null;
    for (const [dx, dy] of [[0, 0], [24, 12], [-28, 18], [44, -22], [-46, -30]]) {
      await page.mouse.click(globe.x + globe.width / 2 + dx, globe.y + globe.height / 2 + dy);
      await page.waitForTimeout(1_000);
      if ((await page.evaluate(() => document.getElementById("deploy")?.hidden)) === false) {
        deployLabel = (await page.locator("#deploy").textContent())?.trim() ?? null;
        break;
      }
    }
    step("A.T.L.A.S. coordinate selection is deployable", Boolean(deployLabel), String(deployLabel ?? ""));
    if (!deployLabel) throw new Error("No deployable A.T.L.A.S. coordinate selection was published.");
    report.observations.selection_label = deployLabel;
    await capture(page, "atlas-target-acquired");

    // Exactly one deployment, through the product's own deploy control.
    await page.click("#deploy");
    await page.waitForURL(/battlestar\.html/, { timeout: 20_000 });
  }
  const deploymentRaw = await page.evaluate(() => localStorage.getItem("bss_deploy_message"));
  if (!deploymentRaw) throw new Error("The single deployment message was not stored.");
  report.deployment = JSON.parse(deploymentRaw);
  const deploy = report.deployment?.payload?.deploy ?? {};
  const sector = String(deploy.sector ?? "");
  step(
    config.guided ? "deployment targets the guided Proving Ground" : "deployment targets an armed sector",
    config.guided ? sector === "Proving Ground" : (sector.length > 0 && sector !== "Proving Ground"),
    `sector=${sector} seed=${deploy.seed}`,
  );
  report.observations.mission = { sector, seed: deploy.seed, faction: deploy.faction };

  const canvas = page.frameLocator("#mount").locator("canvas");
  await canvas.waitFor({ state: "visible", timeout: config.bootTimeoutMs });
  let booted = false;
  const bootStarted = Date.now();
  for (let attempt = 0; attempt < 60; attempt += 1) {
    await page.waitForTimeout(1_000);
    const rendered = await canvas.screenshot().catch(() => null);
    if (rendered && rendered.length > 24_000) { booted = true; break; }
  }
  step("godot tactical runtime booted", booted, `${((Date.now() - bootStarted) / 1_000).toFixed(1)}s`);
  if (!booted) throw new Error("Godot tactical runtime did not produce a rendered frame.");
  await capture(page, "tactical-booted");

  // Free rounds through the real End Turn key. The forces close, and cover
  // seeking becomes available once an agent is actually exposed.
  const box = await canvas.boundingBox();
  if (box) {
    await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
    await page.waitForTimeout(600);
  }
  // In guided mode the bounded observation surface publishes. Sample it each
  // round so movement, cover faces, and attack targets are evidenced from the
  // game's own authority rather than inferred.
  const gameFrame = () => page.frames()
    .find((candidate) => candidate.url().includes("tactical/index.html"));
  const observation = async () => {
    try {
      return await gameFrame()?.evaluate(() => window.__gzg_observation ?? null) ?? null;
    } catch {
      return null;
    }
  };
  const surface = { samples: 0, with_move: 0, with_cover: 0, with_attack: 0, best: null };
  const sampleSurface = async () => {
    const current = await observation();
    if (!current) return;
    surface.samples += 1;
    const moves = Array.isArray(current.move_targets) ? current.move_targets.length : 0;
    const covers = Array.isArray(current.cover_faces) ? current.cover_faces.length : 0;
    const attacks = Array.isArray(current.attack_targets) ? current.attack_targets.length : 0;
    if (moves > 0) surface.with_move += 1;
    if (covers > 0) surface.with_cover += 1;
    if (attacks > 0) surface.with_attack += 1;
    if (covers > 0 && (!surface.best || covers > surface.best.cover_faces)) {
      surface.best = {
        round: current.round,
        viewport: current.viewport,
        actor: current.actor?.cell ?? null,
        move_targets: moves,
        cover_faces: covers,
        attack_targets: attacks,
        cover_sample: current.cover_faces.slice(0, 4),
      };
    }
  };

  await sampleSurface();
  for (let round = 1; round <= config.rounds; round += 1) {
    await page.keyboard.press("Space");
    await page.waitForTimeout(5_000);
    await sampleSurface();
    if (round === 1 || round === config.rounds || round % 3 === 0) {
      await capture(page, `round-${String(round).padStart(2, "0")}`);
    }
  }
  step("free rounds played", true, `${config.rounds} rounds`);
  report.observations.surface = surface;

  await page.keyboard.press("F8");
  await page.waitForTimeout(5_000);
  await capture(page, "post-extract");

  extractionRaw = await page.evaluate(() => localStorage.getItem("bss_extraction_message") || "");
  if (!extractionRaw) throw new Error("No extraction message reached the local vault.");
  const extractionMessage = JSON.parse(extractionRaw);
  const extraction = extractionMessage?.payload?.extraction;
  const replay = extraction?.replay;
  if (!Array.isArray(replay?.events) || !Array.isArray(replay?.actions)) {
    throw new Error("The captured extraction lacks the full replay ledger.");
  }
  step("one full extraction ledger captured", true, `${extractionRaw.length} bytes`);

  const decisions = replay.events
    .filter((event) => event.event === "agent_decision")
    .map((event) => event.payload);
  const rationales = decisions.map((decision) => String(decision.rationale ?? ""));
  const coverHits = COVER_SIGNATURES.filter((s) => rationales.some((r) => r.includes(s)));
  const flankHits = FLANK_SIGNATURES.filter((s) => rationales.some((r) => r.includes(s)));
  const decisionHits = POSITIONAL_DECISIONS.filter(
    (name) => decisions.some((decision) => String(decision.decision) === name),
  );
  const positional = decisions.filter((decision) => (
    POSITIONAL_DECISIONS.includes(String(decision.decision))
    || COVER_SIGNATURES.concat(FLANK_SIGNATURES).some((s) => String(decision.rationale ?? "").includes(s))
  ));
  const complete = positional.filter((decision) => (
    Number.isFinite(Number(decision.score))
    && decision.position
    && Number.isFinite(Number(decision.position.x))
    && Number.isFinite(Number(decision.position.y))
    && Number.isFinite(Number(decision.ap_before))
    && Number.isFinite(Number(decision.round))
  ));

  report.observations.m03 = {
    decisions_recorded: decisions.length,
    cover_signature_hits: coverHits,
    flank_signature_hits: flankHits,
    positional_decision_hits: decisionHits,
    positional_decisions: positional.length,
    first_positional_round: positional.length
      ? Math.min(...positional.map((decision) => Number(decision.round)))
      : null,
    sample: positional.slice(0, 6).map((decision) => ({
      round: decision.round,
      team: decision.team,
      decision: decision.decision,
      rationale: decision.rationale,
      score: decision.score,
      ap_before: decision.ap_before,
      position: decision.position,
    })),
  };
  report.observations.outcome = {
    outcome: extraction.outcome,
    survivors: extraction.survivors,
    seed: extraction.seed ?? replay.mission_seed,
    actions: replay.actions.length,
    events: replay.events.length,
  };

  gate(
    config.guided
      ? "guided scenario reached with an agent able to act"
      : "armed hostile scenario reached through the ordinary deployment path",
    (config.guided ? sector === "Proving Ground" : sector !== "Proving Ground")
      && decisions.length > 0,
    `sector=${sector} decisions=${decisions.length}`,
  );
  gate(
    "canonical positional rationale present in the live ledger",
    coverHits.length > 0 || flankHits.length > 0,
    `cover=[${coverHits.join(", ")}] flank=[${flankHits.join(", ")}]`,
  );
  gate(
    "positional decisions carry decision, position, AP, and score",
    positional.length > 0 && complete.length === positional.length,
    `${complete.length}/${positional.length} complete records`,
  );
  gate(
    "flank rationale observed",
    flankHits.length > 0,
    "geometry-dependent; cover alone still closes the required gate",
    false,
  );
  if (config.guided) {
    // M03-001 acceptance: movement, cover faces, and attack targets from the
    // same authority. Only guided mode publishes that surface.
    gate(
      "observation surface publishes movement, cover faces, and attack targets",
      surface.with_move > 0 && surface.with_cover > 0 && surface.with_attack > 0,
      `${surface.samples} samples: move=${surface.with_move} cover=${surface.with_cover} attack=${surface.with_attack}`,
    );
  }

  report.finished_at = new Date().toISOString();
  const requiredGates = Object.entries(report.gates).filter(([, value]) => value.required);
  report.result = requiredGates.every(([, value]) => value.ok) ? "PASS" : "FAIL";

  const extractionArtifact = writeArtifactExclusive(run, "extraction.json", extractionRaw);
  report.artifacts.extraction = extractionArtifact;
  const reportArtifact = writeArtifactExclusive(
    run,
    "m03-report.json",
    `${JSON.stringify(report, null, 2)}\n`,
  );
  const manifest = createSha256Manifest([
    reportArtifact,
    extractionArtifact,
    ...report.screenshots.map(({ file, sha256 }) => ({ file, sha256 })),
  ]);
  writeArtifactExclusive(run, "SHA256SUMS", manifest);
  verifySha256Manifest(run.partialDir, manifest);
  renameSync(run.partialDir, run.finalDir);
  console.log(`${report.result}  m03 pack ${run.finalDir}`);
  process.exitCode = report.result === "PASS" ? 0 : 1;
} catch (error) {
  console.error(`HARNESS FAIL  ${error?.message ?? error}`);
  console.error(`partial evidence retained at ${run.partialDir}`);
  process.exitCode = 2;
} finally {
  await browser?.close().catch(() => {});
}
