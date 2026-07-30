#!/usr/bin/env node

// M05-B live viewport, reduced-motion, and keyboard-order matrix.
//
// This harness is deliberately separate from the autonomous playtest. It does
// not claim a mechanical result, an extraction, or a reproduction artifact. It
// boots the tactical runtime once per case and asserts the layout the game
// itself published, the motion preference the game itself resolved, and the
// keyboard traversal the game itself reported.
//
// Run the repository server first, then:
//
//   node tools/a11y/matrix.mjs
//
// Serve an isolated export by pointing the server at it:
//
//   $env:BSS_WEB_ROOT = '.runtime\web-m05b\site'; npm.cmd start

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

const defaultOutput = fileURLToPath(new URL("../../evidence/a11y/", import.meta.url));
const browserResolution = resolveChromiumExecutable({
  playwrightExecutablePath: chromium.executablePath(),
});

const config = Object.freeze({
  base: normalizeBaseUrl(argument("--base", process.env.BSS_BASE_URL || DEFAULT_BASE_URL)),
  out: argument("--out", defaultOutput),
  headed: argv.includes("--headed"),
  callsign: String(argument("--callsign", "A11Y-MATRIX")).slice(0, 40),
  bootTimeoutMs: 90_000,
  browser: browserResolution,
});

// Browser viewports whose embedded canvas the HUD claims to serve. The canvas is
// smaller than the window and the game reports its own size, so these map onto
// HudLayout.SUPPORTED_VIEWPORTS rather than equalling it.
const SUPPORTED_VIEWPORTS = Object.freeze([
  { width: 1920, height: 1080 },
  { width: 1600, height: 900 },
  { width: 1440, height: 900 },
  { width: 1366, height: 768 },
]);

// Declared-unsupported windows. The HUD cannot serve a canvas this short without
// a compact mode; the requirement is that the game reports the constraint rather
// than silently overlapping its own panels.
const CONSTRAINED_VIEWPORTS = Object.freeze([
  { width: 1280, height: 800 },
  { width: 1024, height: 768 },
  { width: 768, height: 1024 },
]);

// Reduced motion is orthogonal to width, so it is proven at a wide and a narrow
// case rather than at every viewport. This bound is reported, not hidden.
const REDUCED_MOTION_VIEWPORTS = Object.freeze([
  { width: 1920, height: 1080 },
  { width: 1366, height: 768 },
]);

const MAX_TAB_PRESSES = 12;

const cases = [
  ...SUPPORTED_VIEWPORTS.map((viewport) => ({
    viewport,
    motion: "no-preference",
    expectation: "supported",
  })),
  ...CONSTRAINED_VIEWPORTS.map((viewport) => ({
    viewport,
    motion: "no-preference",
    expectation: "constrained",
  })),
  ...REDUCED_MOTION_VIEWPORTS.map((viewport) => ({
    viewport,
    motion: "reduce",
    expectation: "supported",
  })),
];

const launchArguments = [
  "--enable-unsafe-swiftshader",
  "--use-gl=swiftshader",
];

const run = beginEvidenceRun(config.out);
const report = {
  harness: "gzg.battlestar.a11y-matrix/1.0",
  run_id: run.runId,
  started_at: new Date().toISOString(),
  scope: {
    claims: [
      "published layout clearance at each supported browser viewport",
      "resolved reduced-motion preference",
      "observed keyboard traversal order across the core tactical controls",
    ],
    not_claimed: [
      "mechanical result, extraction, or reproduction equivalence",
      "screen-reader or assistive-technology behavior",
      "browser coverage beyond the resolved Chromium build",
      "operating-system text scaling",
    ],
  },
  config: {
    base: config.base,
    callsign: config.callsign,
    reduced_motion_viewports: REDUCED_MOTION_VIEWPORTS,
    max_tab_presses: MAX_TAB_PRESSES,
  },
  browser: {
    resolver_source: config.browser.source,
    headed: config.headed,
  },
  server: null,
  cases: [],
  gates: {},
  findings: [],
  screenshots: [],
  artifacts: {},
};

const label = (entry) => `${entry.viewport.width}x${entry.viewport.height}/${entry.motion}`;

const gate = (name, ok, detail = "", required = true) => {
  report.gates[name] = { ok: Boolean(ok), required: Boolean(required), detail };
  const prefix = required ? (ok ? "GATE PASS" : "GATE FAIL") : "OBSERVATION";
  console.log(`${prefix}  ${name}${detail ? ` - ${detail}` : ""}`);
};

const finding = (severity, text) => {
  report.findings.push({ severity, text });
  console.log(`[${severity}] ${text}`);
};

let screenshotNumber = 0;
const capture = async (page, name) => {
  const file = `screenshots/${String(++screenshotNumber).padStart(2, "0")}-${name}.png`;
  const bytes = await page.screenshot();
  const artifact = writeArtifactExclusive(run, file, bytes);
  report.screenshots.push({ run_id: run.runId, name, ...artifact });
  return artifact;
};

async function runCase(browser, entry) {
  const name = label(entry);
  const context = await browser.newContext({
    viewport: entry.viewport,
    reducedMotion: entry.motion,
    acceptDownloads: false,
  });
  const result = {
    viewport: entry.viewport,
    motion: entry.motion,
    expectation: entry.expectation,
    canvas: null,
    reported_viewport: null,
    layout: null,
    accessibility: null,
    focus_sequence: [],
    core_focus_sequence: [],
    checks: {},
  };
  try {
    const page = await context.newPage();
    await page.goto(new URL("index.html", config.base).href, {
      waitUntil: "load",
      timeout: 45_000,
    });
    await page.waitForTimeout(1_800);

    const callsign = page.locator("#callsign");
    if (await callsign.count()) {
      await callsign.fill(config.callsign);
      await callsign.press("Tab");
      await page.waitForTimeout(300);
    }
    await page.click("#quick");
    await page.waitForURL(/battlestar\.html/, { timeout: 20_000 });

    const frame = page.frameLocator("#mount");
    const canvas = frame.locator("canvas");
    await canvas.waitFor({ state: "visible", timeout: config.bootTimeoutMs });

    const gameFrame = () => page.frames()
      .find((candidate) => candidate.url().includes("tactical/index.html"));
    const observation = async () => {
      try {
        return await gameFrame()?.evaluate(() => window.__gzg_observation ?? null) ?? null;
      } catch {
        return null;
      }
    };

    let current = null;
    const bootStarted = Date.now();
    while (Date.now() - bootStarted < config.bootTimeoutMs) {
      await page.waitForTimeout(1_000);
      current = await observation();
      if (current?.layout && Object.keys(current.layout).length) break;
    }
    result.checks.published_layout = Boolean(
      current?.layout && Object.keys(current.layout).length,
    );
    if (!result.checks.published_layout) {
      result.checks.note = "the tactical runtime published no layout observation";
      await capture(page, `${entry.viewport.width}x${entry.viewport.height}-${entry.motion}-nolayout`);
      return result;
    }

    result.canvas = await canvas.boundingBox();
    result.reported_viewport = current.viewport ?? null;
    result.layout = current.layout;
    result.accessibility = current.accessibility ?? null;

    const layout = current.layout;
    result.checks.tutorial_clears_status_rail =
      Number(layout.tutorial_left) >= Number(layout.tutorial_clearance);
    result.checks.dock_clears_feed_rail =
      Number(layout.action_dock_left) >= Number(layout.action_dock_clearance);
    result.checks.dock_clears_tutorial = Boolean(layout.tutorial_dock_clear);
    // A supported window must keep a usable tactical feed; a declared-
    // unsupported window must report the constraint instead of hiding it.
    // With the adaptive HUD every supported window must resolve, and a short
    // window must resolve by adaptation rather than by reporting a broken layout.
    result.checks.layout_resolves = !layout.constrained;
    result.adapted = Array.isArray(layout.auto_parked) ? layout.auto_parked : [];
    result.checks.adaptation_matches_declaration = entry.expectation === "supported"
      ? result.adapted.length === 0 && Boolean(layout.event_rail_visible)
      : result.adapted.includes("feed");
    result.checks.actions_never_auto_parked = !result.adapted.includes("dock")
      && !result.adapted.includes("tutorial");

    const expectReduced = entry.motion === "reduce";
    result.checks.motion_preference_resolved =
      Boolean(result.accessibility)
      && Boolean(result.accessibility.reduced_motion) === expectReduced;

    // Keyboard traversal. The canvas must hold focus first; the game reports
    // which core control it moved focus to.
    if (result.canvas) {
      await page.mouse.click(
        result.canvas.x + result.canvas.width / 2,
        result.canvas.y + Math.min(60, result.canvas.height / 6),
      );
      await page.waitForTimeout(400);
    }
    const declaredOrder = Array.isArray(result.accessibility?.focus_order)
      ? result.accessibility.focus_order
      : [];
    for (let press = 0; press < MAX_TAB_PRESSES; press += 1) {
      await page.keyboard.press("Tab");
      await page.waitForTimeout(320);
      const focused = (await observation())?.accessibility?.focused_control ?? "";
      const previous = result.focus_sequence.at(-1);
      if (focused && focused !== previous) result.focus_sequence.push(focused);
      if (new Set(result.focus_sequence).size >= 5) break;
    }
    result.core_focus_sequence = result.focus_sequence
      .filter((key) => declaredOrder.includes(key));
    result.checks.focus_order_observed = result.focus_sequence.length > 0;
    // Traversal follows tree order so no action is stranded. The live gate is
    // that Tab enters the HUD from the canvas and keeps advancing.
    result.checks.keyboard_entry_adopted = result.focus_sequence.length > 0
      && declaredOrder.includes(result.focus_sequence[0]);
    result.checks.traversal_advances = new Set(result.focus_sequence).size >= 3;
    result.checks.core_controls_reachable = result.core_focus_sequence.length >= 1;

    await capture(page, `${entry.viewport.width}x${entry.viewport.height}-${entry.motion}`);
    return result;
  } catch (error) {
    result.checks.error = String(error?.message ?? error).slice(0, 400);
    return result;
  } finally {
    await context.close().catch(() => {});
  }
}

let browser = null;
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
  console.log(
    `served tactical package ${servedPackage.byteLength} bytes sha256:${report.server.tactical_pck.sha256}`,
  );

  browser = await chromium.launch({
    executablePath: config.browser.path,
    headless: !config.headed,
    args: launchArguments,
  });
  report.browser.version = browser.version();

  for (const entry of cases) {
    console.log(`--- ${label(entry)}`);
    const result = await runCase(browser, entry);
    report.cases.push(result);
    const failed = Object.entries(result.checks)
      .filter(([key, value]) => key !== "note" && key !== "error" && value === false)
      .map(([key]) => key);
    console.log(
      failed.length
        ? `  FAIL ${label(entry)}: ${failed.join(", ")}`
        : `  PASS ${label(entry)}`,
    );
  }

  const evaluated = report.cases.filter((entry) => entry.checks.published_layout);
  const railGate = evaluated.length === cases.length
    && evaluated.every((entry) => (
      entry.checks.tutorial_clears_status_rail
      && entry.checks.dock_clears_feed_rail
      && entry.checks.dock_clears_tutorial
    ));
  gate(
    "supported viewport rail and tutorial clearance",
    railGate,
    `${evaluated.length}/${cases.length} cases published a layout`,
  );
  gate(
    "every window resolves to a usable layout",
    evaluated.length > 0 && evaluated.every((entry) => entry.checks.layout_resolves),
    "no window reports a constrained layout once the HUD adapts",
  );
  gate(
    "adaptation matches the declared boundary",
    evaluated.length > 0
      && evaluated.every((entry) => entry.checks.adaptation_matches_declaration),
    "supported windows adapt nothing; short windows park the tactical feed",
  );
  gate(
    "actions and instructions are never auto-parked",
    evaluated.length > 0
      && evaluated.every((entry) => entry.checks.actions_never_auto_parked),
    "only the tactical feed may be parked automatically",
  );
  gate(
    "reduced-motion preference resolved",
    report.cases
      .filter((entry) => entry.checks.published_layout)
      .every((entry) => entry.checks.motion_preference_resolved),
    "the game resolved the host preference for every evaluated case",
  );
  const entryAdopted = evaluated.filter((entry) => entry.checks.keyboard_entry_adopted);
  const advancing = evaluated.filter((entry) => entry.checks.traversal_advances);
  gate(
    "Tab enters the tactical HUD from the canvas",
    entryAdopted.length === evaluated.length && evaluated.length > 0,
    `${entryAdopted.length}/${evaluated.length} cases entered at a declared core control`,
  );
  gate(
    "keyboard traversal keeps advancing through the action dock",
    advancing.length === evaluated.length && evaluated.length > 0,
    `${advancing.length}/${evaluated.length} cases reached three or more distinct controls`,
  );

  for (const entry of report.cases) {
    if (entry.checks.error) {
      finding("harness", `${entry.viewport.width}x${entry.viewport.height}/${entry.motion}: ${entry.checks.error}`);
    } else if (entry.checks.published_layout && entry.layout?.constrained) {
      finding(
        entry.expectation === "constrained" ? "declared-limit" : "defect",
        `${entry.viewport.width}x${entry.viewport.height}/${entry.motion}: canvas `
        + `${entry.reported_viewport?.w}x${entry.reported_viewport?.h} reported a constrained layout`,
      );
    }
  }

  report.finished_at = new Date().toISOString();
  const requiredGates = Object.entries(report.gates).filter(([, value]) => value.required);
  report.result = requiredGates.every(([, value]) => value.ok) ? "PASS" : "FAIL";

  const reportArtifact = writeArtifactExclusive(
    run,
    "a11y-report.json",
    `${JSON.stringify(report, null, 2)}\n`,
  );
  report.artifacts.report = reportArtifact;
  const manifest = createSha256Manifest([
    reportArtifact,
    ...report.screenshots.map(({ file, sha256 }) => ({ file, sha256 })),
  ]);
  writeArtifactExclusive(run, "SHA256SUMS", manifest);
  verifySha256Manifest(run.partialDir, manifest);
  renameSync(run.partialDir, run.finalDir);
  console.log(`${report.result}  matrix pack ${run.finalDir}`);
  process.exitCode = report.result === "PASS" ? 0 : 1;
} catch (error) {
  console.error(`HARNESS FAIL  ${error?.message ?? error}`);
  console.error(`partial evidence retained at ${run.partialDir}`);
  process.exitCode = 2;
} finally {
  await browser?.close().catch(() => {});
}
