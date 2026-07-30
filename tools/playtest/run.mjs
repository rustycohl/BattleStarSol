#!/usr/bin/env node

import { chromium } from "playwright-core";
import { fileURLToPath } from "node:url";

import {
  DEFAULT_BASE_URL,
  beginEvidenceRun,
  finalizeEvidenceRun,
  normalizeBaseUrl,
  probeDevServer,
  resolveChromiumExecutable,
  sha256Bytes,
  writeArtifactExclusive,
} from "./evidence-pack.mjs";

const argv = process.argv.slice(2);
const argument = (flag, fallback) => {
  const index = argv.indexOf(flag);
  return index >= 0 && argv[index + 1] ? argv[index + 1] : fallback;
};

const numericArgument = (flag, fallback, minimum, maximum) => {
  const value = Number(argument(flag, fallback));
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new RangeError(`${flag} must be an integer from ${minimum} through ${maximum}.`);
  }
  return value;
};

const defaultOutput = fileURLToPath(new URL("../../evidence/playtests/", import.meta.url));
const browserResolution = resolveChromiumExecutable({
  playwrightExecutablePath: chromium.executablePath(),
});
const config = Object.freeze({
  base: normalizeBaseUrl(argument("--base", process.env.BSS_BASE_URL || DEFAULT_BASE_URL)),
  rounds: numericArgument("--rounds", "8", 0, 20),
  out: argument("--out", defaultOutput),
  headed: argv.includes("--headed"),
  requireM03: argv.includes("--require-m03"),
  callsign: String(argument("--callsign", "AUTOPILOT")).slice(0, 40),
  bootTimeoutMs: 90_000,
  browser: browserResolution,
});

// These values are used only to choose among targets the game already
// publishes as legal. The game remains the sole AP and legality authority.
const BRACE_COST = 2;
const MELEE_COST = 4;
const DEFENSE_AND_MELEE_RESERVE = BRACE_COST + MELEE_COST;
const MAX_CONSOLE_LINES = 500;
const MAX_PAGE_ERRORS = 100;
const MAX_LOG_CHARS = 2_000;

const launchArguments = [
  "--enable-unsafe-swiftshader",
  "--use-gl=swiftshader",
];

const hit = Object.freeze({
  commanderRow: { dx: 171, dy: 229 },
  worldCenter: { dx: 556, dy: 319 },
  dummies: [
    { dx: 585, dy: 312 },
    { dx: 530, dy: 295 },
    { dx: 595, dy: 332 },
  ],
  moveRing: [[60, 34], [-60, 34]],
});

const m03Signatures = [
  "protective cover now",
  "lean from committed cover",
  "cover has no legal attack lane",
  "cover route",
  "simple flank",
];
const m03Decisions = ["take_cover", "cover_route", "flank"];
// Seven user-facing steps since 2026-07-30: COVER sits between DEFENSE and
// ATTACK, and is skipped when the lane offers no adjacent cover.
const tutorialOrder = new Map([
  ["select_commander", 1],
  ["move", 2],
  ["defense", 3],
  ["cover", 4],
  ["attack", 5],
  ["end_turn", 6],
  ["observe_phases", 7],
  ["extract", 8],
]);

function boundedPush(target, value, maximum) {
  if (target.length >= maximum) return;
  target.push(String(value).slice(0, MAX_LOG_CHARS));
}

function cellOf(candidate) {
  const cell = candidate?.cell;
  if (!cell || !Number.isFinite(Number(cell.x)) || !Number.isFinite(Number(cell.y))) {
    return null;
  }
  return { x: Number(cell.x), y: Number(cell.y) };
}

function orthogonallyAdjacent(first, second) {
  return Math.abs(first.x - second.x) + Math.abs(first.y - second.y) === 1;
}

export function choosePublishedMove(observation, reserveAp = DEFENSE_AND_MELEE_RESERVE) {
  const actorAp = Number(observation?.actor?.ap);
  const targets = Array.isArray(observation?.move_targets)
    ? observation.move_targets.filter((target) => cellOf(target) && target?.screen)
    : [];
  if (!targets.length) return { target: null, reason: "no-published-target" };

  const visibleHostiles = Array.isArray(observation?.attack_targets)
    ? observation.attack_targets.filter((target) => cellOf(target) && target?.screen)
    : [];
  const setup = targets.filter((target) => {
    const cost = Number(target.ap);
    const destination = cellOf(target);
    return (
      Number.isFinite(actorAp)
      && Number.isFinite(cost)
      && cost > 0
      && actorAp - cost >= reserveAp
      && visibleHostiles.some((hostile) => orthogonallyAdjacent(destination, cellOf(hostile)))
    );
  });
  const deterministic = (first, second) => (
    Number(first.ap) - Number(second.ap)
    || cellOf(first).y - cellOf(second).y
    || cellOf(first).x - cellOf(second).x
  );
  if (setup.length) {
    return {
      target: [...setup].sort(deterministic)[0],
      reason: "brace-plus-melee-adjacent-visible-hostile",
    };
  }
  return {
    target: [...targets].sort(deterministic)[0],
    reason: "cheapest-published-fallback",
  };
}

const run = beginEvidenceRun(config.out);
const report = {
  harness: "gzg.battlestar.autonomous-playtest/3.0",
  run_id: run.runId,
  started_at: new Date().toISOString(),
  config: {
    base: config.base,
    rounds: config.rounds,
    require_m03: config.requireM03,
    callsign: config.callsign,
    viewport: { width: 1440, height: 900 },
  },
  browser: {
    resolver_source: config.browser.source,
    headed: config.headed,
  },
  identity: {},
  deployment: null,
  steps: [],
  console_lines: [],
  page_errors: [],
  observations: {},
  ledger: {},
  gates: {},
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
  const label = required ? (ok ? "GATE PASS" : "GATE FAIL") : "OBSERVATION";
  console.log(`${label}  ${name}${detail ? ` - ${detail}` : ""}`);
};

const finding = (severity, module, text) => {
  report.findings.push({ severity, module, text });
  console.log(`[${severity}] ${module}: ${text}`);
};

let screenshotNumber = 0;
const screenshot = async (page, label) => {
  const file = `screenshots/${String(++screenshotNumber).padStart(2, "0")}-${label}.png`;
  const capturedAt = new Date().toISOString();
  const bytes = await page.screenshot();
  const artifact = writeArtifactExclusive(run, file, bytes);
  report.screenshots.push({
    run_id: run.runId,
    label,
    at: capturedAt,
    ...artifact,
  });
  return artifact;
};

let browser = null;
let context = null;
let extractionRaw = "";
let finalized = null;
try {
  const server = await probeDevServer(config.base);
  const tacticalPackageUrl = new URL("tactical/index.pck", config.base);
  const tacticalPackageResponse = await fetch(tacticalPackageUrl, { cache: "no-store" });
  if (!tacticalPackageResponse.ok) {
    throw new Error(`Served tactical package returned HTTP ${tacticalPackageResponse.status}.`);
  }
  const tacticalPackage = Buffer.from(await tacticalPackageResponse.arrayBuffer());
  report.server = {
    ...server,
    tactical_pck: {
      url: tacticalPackageUrl.href,
      bytes: tacticalPackage.byteLength,
      sha256: sha256Bytes(tacticalPackage),
    },
  };
  step("canonical development server responds", true, `${server.url} marker=${server.marker}`);
  step(
    "served tactical package identified",
    true,
    `${tacticalPackage.byteLength} bytes sha256:${report.server.tactical_pck.sha256}`,
  );

  browser = await chromium.launch({
    executablePath: config.browser.path,
    headless: !config.headed,
    args: launchArguments,
  });
  report.browser.version = browser.version();
  context = await browser.newContext({
    viewport: report.config.viewport,
    acceptDownloads: false,
  });
  const page = await context.newPage();
  page.on("console", (message) => boundedPush(
    report.console_lines,
    message.text(),
    MAX_CONSOLE_LINES,
  ));
  page.on("pageerror", (error) => boundedPush(
    report.page_errors,
    error.message,
    MAX_PAGE_ERRORS,
  ));

  await page.goto(new URL("index.html", config.base).href, {
    waitUntil: "load",
    timeout: 45_000,
  });
  await page.waitForTimeout(2_500);
  step("strategic console loads", true, await page.title());
  await screenshot(page, "strategic-console");

  const callsign = page.locator("#callsign");
  if (await callsign.count()) {
    await callsign.fill(config.callsign);
    await callsign.press("Tab");
    await page.waitForTimeout(400);
    step("commander callsign accepted", true, config.callsign);
  } else {
    step("commander callsign accepted", false, "#callsign not found");
  }

  const strategicBefore = await page.evaluate(() => ({
    missions: document.getElementById("missions")?.textContent ?? null,
    history: document.getElementById("history-line")?.textContent ?? null,
  }));
  report.observations.strategic_before = strategicBefore;

  const quickLabel = await page.locator("#quick").textContent().catch(() => null);
  step("quick deploy control present", Boolean(quickLabel), String(quickLabel ?? "").trim());

  // Exactly one deployment is requested in the run.
  await page.click("#quick");
  await page.waitForURL(/battlestar\.html/, { timeout: 20_000 });
  step("same-tab launch to tactical launcher", true, "battlestar.html");

  const deploymentRaw = await page.evaluate(() => localStorage.getItem("bss_deploy_message"));
  if (!deploymentRaw) throw new Error("The single deployment message was not stored.");
  report.deployment = JSON.parse(deploymentRaw);

  await page.waitForTimeout(2_000);
  const brief = await page.evaluate(() => ({
    sector: document.getElementById("sector")?.textContent ?? null,
    faction: document.getElementById("faction")?.textContent ?? null,
    seed: document.getElementById("seed")?.textContent ?? null,
    squad: document.getElementById("squad")?.textContent ?? null,
    objectives: [...document.querySelectorAll("#objectives li")]
      .map((item) => item.textContent.trim()),
    runtime_status: document.getElementById("runtime-status")?.textContent ?? null,
  }));
  report.observations.deployment_brief = brief;
  step("deployment brief populated", Boolean(brief.seed), `seed=${brief.seed} sector=${brief.sector}`);

  const frame = page.frameLocator("#mount");
  const canvas = frame.locator("canvas");
  await canvas.waitFor({ state: "visible", timeout: config.bootTimeoutMs });
  const bootStarted = Date.now();
  let booted = false;
  for (let attempt = 0; attempt < 60; attempt += 1) {
    await page.waitForTimeout(1_000);
    const rendered = await canvas.screenshot().catch(() => null);
    if (rendered && rendered.length > 24_000) {
      booted = true;
      break;
    }
  }
  step("godot tactical runtime booted", booted, `${((Date.now() - bootStarted) / 1_000).toFixed(1)}s`);
  if (!booted) throw new Error("Godot tactical runtime did not produce a rendered frame.");
  await screenshot(page, "tactical-booted");

  const canvasBox = await canvas.boundingBox();
  if (!canvasBox) throw new Error("Godot canvas has no page-space bounds.");
  report.observations.canvas_box = canvasBox;
  const pointAt = (target) => ({
    x: canvasBox.x + target.dx,
    y: canvasBox.y + target.dy,
  });
  const click = async (target, waitMs = 900) => {
    const point = pointAt(target);
    await page.mouse.click(point.x, point.y);
    await page.waitForTimeout(waitMs);
  };
  const key = async (value, waitMs = 1_200) => {
    await page.keyboard.press(value);
    await page.waitForTimeout(waitMs);
  };

  const gameFrame = () => page.frames()
    .find((candidate) => candidate.url().includes("tactical/index.html"));
  const observation = async () => {
    try {
      return await gameFrame()?.evaluate(() => window.__gzg_observation ?? null) ?? null;
    } catch {
      return null;
    }
  };
  const waitForTutorialStep = async (stepKey, timeoutMs = 20_000) => {
    const started = Date.now();
    while (Date.now() - started < timeoutMs) {
      const current = await observation();
      const tutorial = current?.tutorial ?? current;
      const currentOrder = tutorialOrder.get(tutorial?.step) ?? 0;
      const requestedOrder = tutorialOrder.get(stepKey) ?? Number.POSITIVE_INFINITY;
      if (
        tutorial
        && (
          tutorial.step === stepKey
          || tutorial.complete
          || currentOrder > requestedOrder
        )
      ) {
        return current;
      }
      await page.waitForTimeout(700);
    }
    return observation();
  };
  const toPage = (screen, current) => {
    if (!screen || !current?.viewport?.w || !current?.viewport?.h) return null;
    return {
      x: canvasBox.x + Number(screen.x) * (canvasBox.width / Number(current.viewport.w)),
      y: canvasBox.y + Number(screen.y) * (canvasBox.height / Number(current.viewport.h)),
    };
  };
  const clickPage = async (point, waitMs = 1_200) => {
    if (!point) return false;
    await page.mouse.click(point.x, point.y);
    await page.waitForTimeout(waitMs);
    return true;
  };
  const aimed = { move: 0, cover: 0, attack: 0, swept: 0 };

  // 1/7: select Commander through the real roster control.
  await click(hit.commanderRow);
  const afterSelect = await waitForTutorialStep("move", 20_000);
  step(
    "roster select advances the guided tutorial",
    afterSelect?.tutorial?.step === "move",
    `step=${afterSelect?.tutorial?.display_step ?? "?"}/7 ${afterSelect?.tutorial?.step ?? "unobserved"}`,
  );
  await screenshot(page, "tutorial-1-select");

  // 2/7: prefer a setup that leaves Brace + melee AP and ends adjacent to a
  // visible hostile. Only fall back to the cheapest published legal move when
  // no such setup exists.
  let moved = null;
  const preMove = await observation();
  const selectedMove = choosePublishedMove(preMove);
  report.observations.move_choice = {
    reason: selectedMove.reason,
    reserve_ap: DEFENSE_AND_MELEE_RESERVE,
    published_targets: preMove?.move_targets?.length ?? 0,
    target: selectedMove.target
      ? { cell: selectedMove.target.cell, ap: selectedMove.target.ap }
      : null,
  };
  if (selectedMove.target) {
    await clickPage(toPage(selectedMove.target.screen, preMove), 1_500);
    aimed.move += 1;
    moved = await waitForTutorialStep("defense", 25_000);
  }
  // Corrected from the historical moved?.step bug: tutorial is nested.
  if (moved?.tutorial?.step !== "defense") {
    for (const offset of hit.moveRing) {
      await click({
        dx: hit.worldCenter.dx + offset[0],
        dy: hit.worldCenter.dy + offset[1],
      }, 1_200);
      aimed.swept += 1;
      moved = await waitForTutorialStep("defense", 12_000);
      if (moved?.tutorial?.step === "defense") break;
    }
  }
  step(
    "a completed move advances to defense",
    moved?.tutorial?.step === "defense",
    `step=${moved?.tutorial?.display_step ?? "?"}/7 ${moved?.tutorial?.step ?? "unobserved"}; choice=${selectedMove.reason}`,
  );
  await screenshot(page, "tutorial-2-move");

  // 3/7: Brace satisfies defense in every lane.
  await key("KeyB", 2_500);
  const afterDefense = await waitForTutorialStep("cover", 25_000);
  const defenseAdvanced = ["cover", "attack"].includes(afterDefense?.tutorial?.step);
  step(
    "defensive posture advances",
    defenseAdvanced,
    `step=${afterDefense?.tutorial?.display_step ?? "?"}/7 ${afterDefense?.tutorial?.step ?? "unobserved"}`,
  );
  await screenshot(page, "tutorial-3-defense");

  // 4/7: the cover step, when the lane offers cover. Take Cover, then commit to a
  // published cover face. A lane without cover skips straight to the attack step.
  if (afterDefense?.tutorial?.step === "cover") {
    await key("KeyT", 1_200);
    const current = await observation();
    report.observations.published_cover_faces = current?.cover_faces?.length ?? 0;
    for (const face of current?.cover_faces ?? []) {
      await clickPage(toPage(face.screen, current), 1_100);
      aimed.cover += 1;
      if ((await observation())?.tutorial?.step === "attack") break;
    }
    const afterCover = await waitForTutorialStep("attack", 25_000);
    step(
      "committed cover advances to attack",
      afterCover?.tutorial?.step === "attack",
      `step=${afterCover?.tutorial?.display_step ?? "?"}/7 ${afterCover?.tutorial?.step ?? "unobserved"}`,
    );
    await screenshot(page, "tutorial-4-cover");
  } else {
    step("cover step skipped in a lane without cover", true, "no adjacent cover published");
  }

  // 5/7: prefer an adjacent published hostile; retain measured pixel fallback.
  const preAttack = await observation();
  const hostiles = [...(preAttack?.attack_targets ?? [])]
    .sort((first, second) => Number(second.adjacent) - Number(first.adjacent));
  report.observations.published_attack_targets = hostiles.length;
  for (const hostile of hostiles) {
    await clickPage(toPage(hostile.screen, preAttack), 1_600);
    aimed.attack += 1;
    if ((await observation())?.tutorial?.step === "end_turn") break;
  }
  if ((await observation())?.tutorial?.step !== "end_turn") {
    for (const target of hit.dummies) {
      await click(target, 1_400);
      aimed.swept += 1;
      if ((await observation())?.tutorial?.step === "end_turn") break;
    }
  }
  const afterAttack = await waitForTutorialStep("end_turn", 25_000);
  step(
    "basic attack advances to end turn",
    afterAttack?.tutorial?.step === "end_turn",
    `step=${afterAttack?.tutorial?.display_step ?? "?"}/7 ${afterAttack?.tutorial?.step ?? "unobserved"}`,
  );
  await screenshot(page, "tutorial-5-attack");

  // 6/7 and 7/7: end turn, observe autonomous phases, then extract.
  await key("Space", 4_000);
  const afterEndTurn = await waitForTutorialStep("observe_phases", 25_000);
  const phaseObservationReached = (
    afterEndTurn?.tutorial?.step === "observe_phases"
    || afterEndTurn?.tutorial?.step === "extract"
    || afterEndTurn?.tutorial?.complete === true
  );
  step(
    "end turn advances to phase observation",
    phaseObservationReached,
    `step=${afterEndTurn?.tutorial?.display_step ?? "?"}/7 ${afterEndTurn?.tutorial?.step ?? "unobserved"}`,
  );
  await screenshot(page, "tutorial-5-endturn");
  const afterReturn = await waitForTutorialStep("extract", 60_000);
  step(
    "returned player turn exposes extraction",
    afterReturn?.tutorial?.step === "extract" || afterReturn?.tutorial?.complete === true,
    `step=${afterReturn?.tutorial?.display_step ?? "?"}/7 ${afterReturn?.tutorial?.step ?? "unobserved"}`,
  );
  report.observations.aimed_actions = aimed;

  for (let round = 1; round <= config.rounds; round += 1) {
    const dx = ((round % 5) - 2) * 90;
    const dy = ((round % 3) - 1) * 90;
    const center = pointAt(hit.worldCenter);
    await page.mouse.click(center.x + dx, center.y + dy);
    await page.waitForTimeout(700);
    await page.mouse.click(center.x + dy, center.y - dx);
    await page.waitForTimeout(700);
    await page.keyboard.press("Space");
    await page.waitForTimeout(4_000);
    if (round % 4 === 0 || round === config.rounds) {
      await screenshot(page, `round-${String(round).padStart(2, "0")}`);
    }
  }
  step("turn cycle survives full run", true, `${config.rounds} free rounds`);

  await page.keyboard.press("F8");
  await page.waitForTimeout(5_000);
  await screenshot(page, "post-extract");

  // Capture exactly one full extraction message from the product vault.
  extractionRaw = await page.evaluate(
    () => localStorage.getItem("bss_extraction_message") || "",
  );
  if (!extractionRaw) throw new Error("Full extraction message is absent from the local vault.");
  const extractionMessage = JSON.parse(extractionRaw);
  const extraction = extractionMessage?.payload?.extraction;
  const replay = extraction?.replay;
  if (
    extractionMessage?.extensions?.browser_storage?.compacted === true
    || !Array.isArray(replay?.actions)
    || !Array.isArray(replay?.events)
  ) {
    throw new Error("The captured extraction is compacted or lacks the full replay ledger.");
  }
  step("one full extraction message captured", true, `${extractionRaw.length} bytes`);

  if (!/index\.html/.test(page.url())) {
    const returnButton = page.locator("#return");
    if (await returnButton.count()) {
      await returnButton.click();
      await page.waitForTimeout(3_000);
    }
  }
  if (!/index\.html/.test(page.url())) {
    await page.goto(new URL("index.html", config.base).href, { waitUntil: "load" });
    await page.waitForTimeout(2_500);
  }
  await screenshot(page, "strategic-return");

  const strategicAfter = await page.evaluate(() => ({
    missions: document.getElementById("missions")?.textContent ?? null,
    history: document.getElementById("history-line")?.textContent ?? null,
    neural: document.getElementById("neural")?.textContent ?? null,
    capital: document.getElementById("capital")?.textContent ?? null,
  }));
  report.observations.strategic_after = strategicAfter;
  step(
    "strategic console shows a completed mission",
    Boolean(strategicAfter.history) && strategicAfter.history !== strategicBefore.history,
    strategicAfter.history,
  );

  await page.reload({ waitUntil: "load" });
  await page.waitForTimeout(2_500);
  const reloaded = await page.evaluate(() => ({
    missions: document.getElementById("missions")?.textContent ?? null,
  }));
  step(
    "mission count is idempotent under forced reload",
    reloaded.missions === strategicAfter.missions,
    `${strategicAfter.missions} -> ${reloaded.missions}`,
  );
  await screenshot(page, "after-reload");

  const events = replay.events;
  const actions = replay.actions;
  const eventHistogram = {};
  for (const event of events) {
    eventHistogram[event.event] = (eventHistogram[event.event] || 0) + 1;
  }
  const tutorialSteps = events
    .filter((event) => event.event === "tutorial_step_changed")
    .map((event) => ({ seq: event.sequence, ...event.payload }));
  const decisions = events
    .filter((event) => event.event === "agent_decision")
    .map((event) => event.payload);
  const decisionHistogram = decisions.reduce((histogram, decision) => {
    const name = String(decision.decision ?? "unknown");
    histogram[name] = (histogram[name] || 0) + 1;
    return histogram;
  }, {});
  const rationaleText = decisions.map((decision) => String(decision.rationale || "")).join("\n");
  const signatureHits = m03Signatures.filter((signature) => rationaleText.includes(signature));
  const decisionHits = m03Decisions.filter(
    (decision) => decisions.some((item) => String(item.decision) === decision),
  );
  const m03Observed = signatureHits.length > 0 || decisionHits.length > 0;

  report.ledger = {
    extraction_id: extraction.extraction_id,
    outcome: extraction.outcome,
    survivors: extraction.survivors,
    seed: extraction.seed ?? replay.mission_seed,
    rules_version: extraction.rules_version,
    generator_version: extraction.generator_version,
    payload_contract_version: extraction.payload_contract_version,
    action_count: actions.length,
    event_count: events.length,
    event_histogram: eventHistogram,
    tutorial_steps: tutorialSteps,
    agent_decisions: decisions,
    decision_histogram: decisionHistogram,
    m03_signature_hits: signatureHits,
    m03_decision_hits: decisionHits,
  };
  report.observations.m03 = {
    canonical_rationale_observed: m03Observed,
    signature_hits: signatureHits,
    decision_hits: decisionHits,
    decision_count: decisions.length,
  };
  report.identity = {
    run_id: run.runId,
    deployment_message_id: report.deployment.id,
    extraction_message_id: extractionMessage.id,
    extraction_id: extraction.extraction_id,
    correlation_id: extractionMessage.correlation_id,
    seed: Number(extraction.seed),
    extracted_at: extractionMessage.created_at,
  };

  const apViolations = actions.filter(
    (action) => Number(action.ap_before) > 10 || Number(action.ap_after_dispatch) > 10,
  );
  const tutorialReached = tutorialSteps.length
    ? Math.max(...tutorialSteps.map((tutorial) => Number(tutorial.display_step) || 0))
    : 0;
  const tutorialComplete = tutorialSteps.some((tutorial) => tutorial.complete === true);
  gate("runtime_clean", report.page_errors.length === 0, `${report.page_errors.length} page errors`);
  gate(
    "full_loop",
    Boolean(extraction) && report.steps
      .find((item) => item.name === "strategic console shows a completed mission")?.ok === true,
    `${extraction.outcome ?? "unknown"}; ${extraction.survivors ?? "?"} survivors; seed ${report.ledger.seed}`,
  );
  gate(
    "idempotence",
    report.steps.find((item) => item.name === "mission count is idempotent under forced reload")?.ok === true,
    "forced reload does not double-apply",
  );
  gate(
    "full_extraction_captured",
    actions.length > 0 && events.length > 0,
    `${actions.length} actions, ${events.length} events`,
  );
  gate(
    "base10_ap_authority",
    apViolations.length === 0,
    apViolations.length ? `${apViolations.length} records exceed 10 AP` : "no record exceeds 10 AP",
  );
  gate(
    "M01_proving_ground_completes",
    tutorialComplete,
    `reached step ${tutorialReached}/7${tutorialComplete ? "" : "; did not report complete"}`,
  );
  gate(
    "M03_canonical_rationale_observed",
    m03Observed,
    m03Observed
      ? [...signatureHits, ...decisionHits].join(", ")
      : `${decisions.length} decisions; none canonical (${Object.keys(decisionHistogram).join("/")})`,
    config.requireM03,
  );

  if (!tutorialComplete) {
    finding(
      "P1",
      "M01",
      `The served export reached tutorial step ${tutorialReached}/7; reconstructed source has not been re-exported.`,
    );
  }
  if (!m03Observed) {
    finding(
      "INFO",
      "M03",
      `No canonical positional rationale appeared in ${decisions.length} live decisions; the Proving Ground remains scenario-limited.`,
    );
  }

  report.finished_at = new Date().toISOString();
  const failedGates = Object.entries(report.gates)
    .filter(([, result]) => result.required !== false && !result.ok)
    .map(([name]) => name);
  report.failed_gates = failedGates;
  report.result = failedGates.length ? "FAIL" : "PASS";

  const extractionArtifact = writeArtifactExclusive(run, "extraction.json", extractionRaw);
  report.artifacts.extraction = extractionArtifact;
  writeArtifactExclusive(
    run,
    "playtest-report.json",
    `${JSON.stringify(report, null, 2)}\n`,
  );

  await context.close();
  context = null;
  await browser.close();
  browser = null;

  finalized = finalizeEvidenceRun(run);
  console.log(`REPORT ${finalized.finalDir}`);
  console.log(`RESULT ${report.result}${failedGates.length ? ` - ${failedGates.join(", ")}` : ""}`);
  process.exitCode = failedGates.length ? 1 : 0;
} catch (error) {
  report.finished_at = new Date().toISOString();
  report.result = "ERROR";
  report.harness_error = String(error?.stack || error);
  console.error("HARNESS ERROR", report.harness_error);
  if (context) await context.close().catch(() => {});
  if (browser) await browser.close().catch(() => {});
  if (!finalized) {
    try {
      writeArtifactExclusive(
        run,
        "harness-error.json",
        `${JSON.stringify(report, null, 2)}\n`,
      );
    } catch {
      // Preserve the original partial directory exactly when even the error
      // record cannot be written exclusively.
    }
  }
  console.error(`PARTIAL ${run.partialDir}`);
  process.exitCode = 2;
}
