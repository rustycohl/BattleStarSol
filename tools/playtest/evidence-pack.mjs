import { createHash, randomUUID } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  statSync,
  writeFileSync,
} from "node:fs";
import {
  basename,
  dirname,
  isAbsolute,
  join,
  relative,
  resolve,
} from "node:path";

export const DEFAULT_BASE_URL = "http://127.0.0.1:8781/";
export const SHA256_PATTERN = /^[a-f0-9]{64}$/;
const RUN_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;

export class EvidenceIdentityError extends Error {
  constructor(errors) {
    super(`Evidence identity is inconsistent: ${errors.join("; ")}`);
    this.name = "EvidenceIdentityError";
    this.errors = [...errors];
  }
}

function assertPlainObject(value, name) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new TypeError(`${name} must be an object.`);
  }
  return value;
}

function cleanExecutablePath(value) {
  const text = String(value ?? "").trim();
  if (text.startsWith('"') && text.endsWith('"') && text.length >= 2) {
    return text.slice(1, -1);
  }
  return text;
}

function safeRunId(runId) {
  const value = String(runId ?? "");
  if (!RUN_ID_PATTERN.test(value) || value.endsWith(".partial")) {
    throw new TypeError("Run ID must be a Windows-safe filename component.");
  }
  return value;
}

function safeArtifactPath(root, file) {
  const value = String(file ?? "");
  if (!value || value.includes("\0") || /[\r\n]/.test(value) || isAbsolute(value)) {
    throw new TypeError("Artifact path must be a safe relative path.");
  }
  const target = resolve(root, value);
  const route = relative(resolve(root), target);
  if (!route || route.startsWith("..") || isAbsolute(route)) {
    throw new RangeError("Artifact path escaped the evidence run directory.");
  }
  return { target, route: route.replaceAll("\\", "/") };
}

function parseJsonFile(path, name) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    throw new TypeError(`${name} is not valid JSON: ${error.message}`);
  }
}

function timestamp(value, name, errors) {
  const parsed = Date.parse(String(value ?? ""));
  if (!Number.isFinite(parsed)) errors.push(`${name} is not a valid timestamp`);
  return parsed;
}

function listArtifactFiles(root, current = root) {
  const files = [];
  for (const entry of readdirSync(current, { withFileTypes: true })) {
    const path = join(current, entry.name);
    if (entry.isSymbolicLink()) {
      throw new TypeError(`Evidence packs cannot contain symbolic links: ${entry.name}`);
    }
    if (entry.isDirectory()) {
      files.push(...listArtifactFiles(root, path));
    } else if (entry.isFile()) {
      files.push(relative(root, path).replaceAll("\\", "/"));
    }
  }
  return files.sort();
}

export function makeRunId({
  now = new Date(),
  uuid = randomUUID(),
} = {}) {
  if (!(now instanceof Date) || Number.isNaN(now.getTime())) {
    throw new TypeError("Run ID requires a valid Date.");
  }
  const suffix = String(uuid).replaceAll("-", "").toLowerCase();
  if (!/^[a-f0-9]{8,}$/.test(suffix)) {
    throw new TypeError("Run ID requires a UUID-like hexadecimal suffix.");
  }
  const stamp = now.toISOString().replace(/[-:.]/g, "");
  return safeRunId(`${stamp}-${suffix.slice(0, 8)}`);
}

export function normalizeBaseUrl(value = DEFAULT_BASE_URL) {
  const url = new URL(String(value || DEFAULT_BASE_URL));
  if (!["http:", "https:"].includes(url.protocol)) {
    throw new TypeError("Playtest base URL must use HTTP or HTTPS.");
  }
  url.search = "";
  url.hash = "";
  if (!url.pathname.endsWith("/")) url.pathname += "/";
  return url.href;
}

export function resolveChromiumExecutable({
  env = process.env,
  platform = process.platform,
  exists = existsSync,
  playwrightExecutablePath = "",
} = {}) {
  const explicit = cleanExecutablePath(env.PW_CHROMIUM);
  if (explicit) {
    if (!exists(explicit)) {
      throw new Error(`PW_CHROMIUM does not point to an existing file: ${explicit}`);
    }
    return { path: explicit, source: "PW_CHROMIUM" };
  }

  const candidates = [];
  const playwrightPath = cleanExecutablePath(playwrightExecutablePath);
  if (playwrightPath) candidates.push({ path: playwrightPath, source: "playwright" });

  if (platform === "win32") {
    const programFiles = env.ProgramFiles || env.PROGRAMFILES || "C:\\Program Files";
    const programFilesX86 = env["ProgramFiles(x86)"] || env["PROGRAMFILES(X86)"] || "C:\\Program Files (x86)";
    const localAppData = env.LOCALAPPDATA || "";
    candidates.push(
      {
        path: join(programFiles, "Google", "Chrome", "Application", "chrome.exe"),
        source: "windows-chrome",
      },
      {
        path: join(programFilesX86, "Google", "Chrome", "Application", "chrome.exe"),
        source: "windows-chrome-x86",
      },
      ...(localAppData
        ? [{
          path: join(localAppData, "Google", "Chrome", "Application", "chrome.exe"),
          source: "windows-chrome-user",
        }]
        : []),
      {
        path: join(programFiles, "Microsoft", "Edge", "Application", "msedge.exe"),
        source: "windows-edge",
      },
      {
        path: join(programFilesX86, "Microsoft", "Edge", "Application", "msedge.exe"),
        source: "windows-edge-x86",
      },
    );
  }

  const seen = new Set();
  for (const candidate of candidates) {
    const path = cleanExecutablePath(candidate.path);
    const key = path.toLowerCase();
    if (!path || seen.has(key)) continue;
    seen.add(key);
    if (exists(path)) return { path, source: candidate.source };
  }

  throw new Error(
    "No Chromium-family browser was found. Set PW_CHROMIUM to an existing Chrome, Edge, or Chromium executable.",
  );
}

export async function probeDevServer(
  base = DEFAULT_BASE_URL,
  { fetchImpl = globalThis.fetch } = {},
) {
  if (typeof fetchImpl !== "function") throw new TypeError("A fetch implementation is required.");
  const url = normalizeBaseUrl(base);
  const response = await fetchImpl(url, { method: "HEAD", cache: "no-store" });
  if (!response?.ok) {
    throw new Error(`Battle/Star.SOL development server returned HTTP ${response?.status ?? "unknown"}.`);
  }
  const marker = response.headers?.get?.("x-battlestar-dev-server");
  if (marker !== "1") {
    throw new Error("The target is not the canonical Battle/Star.SOL development server.");
  }
  return { url, status: response.status, marker };
}

export function sha256Bytes(data) {
  return createHash("sha256").update(data).digest("hex");
}

export function sha256File(path) {
  return sha256Bytes(readFileSync(path));
}

export function beginEvidenceRun(
  outRoot,
  { runId = makeRunId() } = {},
) {
  const id = safeRunId(runId);
  const root = resolve(String(outRoot));
  const partialDir = join(root, `${id}.partial`);
  const finalDir = join(root, id);
  mkdirSync(root, { recursive: true });
  if (existsSync(finalDir)) {
    throw new Error(`Final evidence directory already exists: ${finalDir}`);
  }
  mkdirSync(partialDir, { recursive: false });
  return Object.freeze({ runId: id, outRoot: root, partialDir, finalDir });
}

export function writeArtifactExclusive(run, file, data) {
  assertPlainObject(run, "run");
  const { target, route } = safeArtifactPath(run.partialDir, file);
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, data, { flag: "wx" });
  const info = statSync(target);
  return Object.freeze({
    file: route,
    bytes: info.size,
    sha256: sha256File(target),
  });
}

export function validateEvidenceIdentity({
  report,
  deployment,
  extraction,
  expectedRunId = report?.run_id,
  clockSkewMs = 5_000,
}) {
  assertPlainObject(report, "report");
  assertPlainObject(deployment, "deployment");
  assertPlainObject(extraction, "extraction");
  const identity = assertPlainObject(report.identity, "report.identity");
  const payload = assertPlainObject(extraction.payload, "extraction.payload");
  const result = assertPlainObject(payload.extraction, "extraction.payload.extraction");
  const replay = result.replay && typeof result.replay === "object" ? result.replay : {};
  const actions = Array.isArray(replay.actions) ? replay.actions : [];
  const events = Array.isArray(replay.events) ? replay.events : [];
  const errors = [];

  if (deployment.gzg !== "galaxy-message" || deployment.type !== "battlestar.deploy") {
    errors.push("deployment is not a battlestar.deploy galaxy message");
  }
  if (deployment.payload?.schema !== "gzg.battlestar.deploy/1.0") {
    errors.push("deployment payload schema is not supported");
  }
  if (extraction.gzg !== "galaxy-message" || extraction.type !== "xcommand.extraction") {
    errors.push("extraction is not an xcommand.extraction galaxy message");
  }
  if (payload.schema !== "gzg.xcommand.extraction/1.0") {
    errors.push("extraction payload schema is not supported");
  }

  const runId = String(expectedRunId ?? "");
  if (report.run_id !== runId) errors.push("report run_id does not match the run directory");
  if (identity.run_id !== runId) errors.push("identity run_id does not match the run directory");
  if (identity.deployment_message_id !== deployment.id) {
    errors.push("deployment message ID does not match the report");
  }
  if (identity.extraction_message_id !== extraction.id) {
    errors.push("extraction message ID does not match the report");
  }
  if (identity.extraction_id !== result.extraction_id) {
    errors.push("payload extraction ID does not match the report");
  }
  if (extraction.id !== result.extraction_id) {
    errors.push("extraction message ID does not match payload extraction_id");
  }
  if (extraction.correlation_id !== deployment.id) {
    errors.push("extraction correlation_id does not match deployment message ID");
  }
  if (identity.correlation_id !== extraction.correlation_id) {
    errors.push("extraction correlation_id does not match the report");
  }

  const deploymentSeed = Number(deployment.payload?.deploy?.seed ?? deployment.seed);
  const extractionSeed = Number(result.seed);
  if (!Number.isFinite(deploymentSeed) || deploymentSeed <= 0) {
    errors.push("deployment seed is invalid");
  }
  if (!Number.isFinite(extractionSeed) || extractionSeed <= 0) {
    errors.push("extraction seed is invalid");
  }
  if (deploymentSeed !== extractionSeed) errors.push("deployment and extraction seeds differ");
  if (Number(identity.seed) !== extractionSeed) errors.push("report identity seed differs");
  if (Number(report.ledger?.seed) !== extractionSeed) errors.push("report ledger seed differs");
  if (report.ledger?.extraction_id !== extraction.id) errors.push("report ledger extraction ID differs");
  if (Number(report.ledger?.action_count) !== actions.length) {
    errors.push("report action count differs from extraction replay");
  }
  if (Number(report.ledger?.event_count) !== events.length) {
    errors.push("report event count differs from extraction replay");
  }

  const startedAt = timestamp(report.started_at, "report started_at", errors);
  const finishedAt = timestamp(report.finished_at, "report finished_at", errors);
  const extractedAt = timestamp(extraction.created_at, "extraction created_at", errors);
  const payloadTimestamp = Number(result.ts);
  if (Number.isFinite(startedAt) && Number.isFinite(finishedAt) && startedAt > finishedAt) {
    errors.push("report finished before it started");
  }
  if (
    Number.isFinite(startedAt)
    && Number.isFinite(finishedAt)
    && Number.isFinite(extractedAt)
    && (extractedAt < startedAt - clockSkewMs || extractedAt > finishedAt + clockSkewMs)
  ) {
    errors.push("extraction timestamp falls outside the run window");
  }
  if (!Number.isFinite(payloadTimestamp) || payloadTimestamp <= 0) {
    errors.push("payload extraction timestamp is invalid");
  } else if (Number.isFinite(extractedAt) && Math.abs(payloadTimestamp - extractedAt) > 2_000) {
    errors.push("payload and envelope extraction timestamps differ");
  }
  if (identity.extracted_at !== extraction.created_at) {
    errors.push("report extracted_at differs from the extraction envelope");
  }

  if (errors.length) throw new EvidenceIdentityError(errors);
  return Object.freeze({
    runId,
    deploymentMessageId: deployment.id,
    extractionMessageId: extraction.id,
    extractionId: result.extraction_id,
    correlationId: extraction.correlation_id,
    seed: extractionSeed,
    actionCount: actions.length,
    eventCount: events.length,
  });
}

export function createSha256Manifest(entries) {
  if (!Array.isArray(entries) || entries.length === 0) {
    throw new TypeError("SHA-256 manifest requires at least one artifact.");
  }
  const seen = new Set();
  const rows = entries.map((entry) => {
    const file = String(entry?.file ?? "").replaceAll("\\", "/");
    if (!file || file.startsWith("/") || file.includes("\0") || /[\r\n]/.test(file)) {
      throw new TypeError("SHA-256 manifest contains an unsafe filename.");
    }
    if (!SHA256_PATTERN.test(String(entry?.sha256 ?? ""))) {
      throw new TypeError(`SHA-256 manifest contains an invalid digest for ${file}.`);
    }
    if (seen.has(file)) throw new TypeError(`SHA-256 manifest repeats ${file}.`);
    seen.add(file);
    return `${entry.sha256}  ${file}`;
  });
  return `${rows.sort().join("\n")}\n`;
}

export function verifySha256Manifest(root, manifestText) {
  const base = resolve(String(root));
  const rows = String(manifestText).split(/\r?\n/).filter(Boolean);
  if (!rows.length) throw new TypeError("SHA-256 manifest is empty.");
  const checked = [];
  for (const row of rows) {
    const match = /^([a-f0-9]{64})  (.+)$/.exec(row);
    if (!match) throw new TypeError(`Malformed SHA-256 manifest row: ${row}`);
    const [, expected, file] = match;
    const { target, route } = safeArtifactPath(base, file);
    if (!existsSync(target) || !statSync(target).isFile()) {
      throw new Error(`Manifest artifact is missing: ${route}`);
    }
    const actual = sha256File(target);
    if (actual !== expected) throw new Error(`SHA-256 mismatch for ${route}.`);
    checked.push(Object.freeze({ file: route, sha256: actual }));
  }
  return Object.freeze(checked);
}

export function finalizeEvidenceRun(
  run,
  {
    reportFile = "playtest-report.json",
    extractionFile = "extraction.json",
    manifestFile = "SHA256SUMS",
  } = {},
) {
  assertPlainObject(run, "run");
  if (existsSync(run.finalDir)) {
    throw new Error(`Final evidence directory already exists: ${run.finalDir}`);
  }

  const reportPath = safeArtifactPath(run.partialDir, reportFile).target;
  const extractionPath = safeArtifactPath(run.partialDir, extractionFile).target;
  const manifestPath = safeArtifactPath(run.partialDir, manifestFile);
  if (existsSync(manifestPath.target)) {
    throw new Error(`Evidence manifest already exists: ${manifestPath.target}`);
  }
  const report = parseJsonFile(reportPath, reportFile);
  const deployment = assertPlainObject(report.deployment, "report.deployment");
  const extraction = parseJsonFile(extractionPath, extractionFile);
  const identity = validateEvidenceIdentity({
    report,
    deployment,
    extraction,
    expectedRunId: run.runId,
  });

  const extractionMeta = assertPlainObject(report.artifacts?.extraction, "report.artifacts.extraction");
  const extractionRoute = safeArtifactPath(run.partialDir, extractionMeta.file).route;
  if (extractionRoute !== safeArtifactPath(run.partialDir, extractionFile).route) {
    throw new EvidenceIdentityError(["report points to a different extraction artifact"]);
  }
  const actualExtractionHash = sha256File(extractionPath);
  const actualExtractionBytes = statSync(extractionPath).size;
  if (
    extractionMeta.sha256 !== actualExtractionHash
    || Number(extractionMeta.bytes) !== actualExtractionBytes
  ) {
    throw new EvidenceIdentityError(["report extraction hash or size differs"]);
  }

  const screenshots = Array.isArray(report.screenshots) ? report.screenshots : [];
  if (!screenshots.length) {
    throw new EvidenceIdentityError(["report contains no screenshots"]);
  }
  const reportedShots = new Set();
  const reportStartedAt = Date.parse(String(report.started_at ?? ""));
  const reportFinishedAt = Date.parse(String(report.finished_at ?? ""));
  for (const shot of screenshots) {
    if (shot.run_id !== run.runId) {
      throw new EvidenceIdentityError(["screenshot run_id differs"]);
    }
    const { target, route } = safeArtifactPath(run.partialDir, shot.file);
    if (reportedShots.has(route)) {
      throw new EvidenceIdentityError([`screenshot is repeated: ${route}`]);
    }
    reportedShots.add(route);
    if (!existsSync(target) || !statSync(target).isFile()) {
      throw new EvidenceIdentityError([`screenshot is missing: ${route}`]);
    }
    const capturedAt = Date.parse(String(shot.at ?? ""));
    if (
      !Number.isFinite(capturedAt)
      || capturedAt < reportStartedAt
      || capturedAt > reportFinishedAt
    ) {
      throw new EvidenceIdentityError([`screenshot timestamp falls outside the run: ${route}`]);
    }
    if (shot.sha256 !== sha256File(target) || Number(shot.bytes) !== statSync(target).size) {
      throw new EvidenceIdentityError([`screenshot hash or size differs: ${route}`]);
    }
  }
  const physicalShots = listArtifactFiles(run.partialDir)
    .filter((file) => file.toLowerCase().endsWith(".png"));
  if (
    physicalShots.length !== reportedShots.size
    || physicalShots.some((file) => !reportedShots.has(file))
  ) {
    throw new EvidenceIdentityError(["physical and reported screenshot sets differ"]);
  }

  const files = listArtifactFiles(run.partialDir)
    .filter((file) => file !== manifestPath.route);
  const entries = files.map((file) => {
    const target = safeArtifactPath(run.partialDir, file).target;
    return Object.freeze({
      file,
      bytes: statSync(target).size,
      sha256: sha256File(target),
    });
  });
  const manifest = createSha256Manifest(entries);
  writeFileSync(manifestPath.target, manifest, { flag: "wx" });
  verifySha256Manifest(run.partialDir, readFileSync(manifestPath.target, "utf8"));

  renameSync(run.partialDir, run.finalDir);
  return Object.freeze({
    runId: run.runId,
    finalDir: run.finalDir,
    manifestFile: basename(manifestPath.target),
    identity,
    artifacts: Object.freeze(entries),
  });
}
