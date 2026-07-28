import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const html = await readFile(new URL("../site/index.html", import.meta.url), "utf8");
const app = await readFile(new URL("../site/app.mjs", import.meta.url), "utf8");

test("launch surface exposes the intended first-release hierarchy", () => {
  assert.match(html, /INITIAL PUBLIC RELEASE \/\/ TWO PRODUCTS \+ ONE SRD/u);
  assert.match(html, /https:\/\/rustycohl\.github\.io\/X-Command\//u);
  assert.match(html, /https:\/\/rustycohl\.github\.io\/d10SRD\//u);
  assert.match(html, /https:\/\/rustycohl\.github\.io\/GZG-NOW\//u);
  assert.match(html, /DEVELOPMENT NETWORK LIVE/u);
});

test("launch page stays inert and dependency-free", () => {
  assert.match(html, /NO ACCOUNT/u);
  assert.match(html, /NO GAME SERVER/u);
  assert.match(html, /NO TRACKING/u);
  assert.doesNotMatch(html, /<script[^>]+src=["']https?:/u);
  assert.doesNotMatch(html, /<link[^>]+href=["']https?:[^"']+["'][^>]+stylesheet/u);
  assert.match(app, /launchByKey/u);
});
