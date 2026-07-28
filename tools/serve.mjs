import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, join, normalize, relative } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../game/web/", import.meta.url));
const port = Number.parseInt(process.env.PORT ?? "8781", 10);
const mimeTypes = new Map([
  [".css", "text/css; charset=utf-8"],
  [".html", "text/html; charset=utf-8"],
  [".ico", "image/x-icon"],
  [".jpeg", "image/jpeg"],
  [".jpg", "image/jpeg"],
  [".js", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".ogg", "audio/ogg"],
  [".otf", "font/otf"],
  [".pck", "application/octet-stream"],
  [".png", "image/png"],
  [".svg", "image/svg+xml"],
  [".wasm", "application/wasm"],
  [".webmanifest", "application/manifest+json; charset=utf-8"],
  [".webp", "image/webp"],
  [".woff", "font/woff"],
  [".woff2", "font/woff2"],
]);

function resolveRequest(url) {
  const pathname = decodeURIComponent(new URL(url, "http://localhost").pathname);
  const requested = pathname.endsWith("/") ? `${pathname}index.html` : pathname;
  const candidate = normalize(join(root, requested));
  const route = relative(root, candidate);
  if (route.startsWith("..") || route.includes(":")) {
    throw new RangeError("Request escaped the game root.");
  }
  return candidate;
}

createServer(async (request, response) => {
  try {
    if (!["GET", "HEAD"].includes(request.method ?? "")) {
      response.writeHead(405, { "Content-Type": "text/plain; charset=utf-8" });
      response.end("Method not allowed.\n");
      return;
    }

    const path = resolveRequest(request.url ?? "/");
    const info = await stat(path);
    if (!info.isFile()) throw new Error("Not a file.");

    response.writeHead(200, {
      "Content-Type": mimeTypes.get(extname(path).toLowerCase()) ?? "application/octet-stream",
      "Content-Length": info.size,
      "Cache-Control": "no-store",
      "Cross-Origin-Embedder-Policy": "require-corp",
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Resource-Policy": "same-origin",
      "X-BattleStar-Dev-Server": "1",
      "X-Content-Type-Options": "nosniff",
    });
    if (request.method === "HEAD") {
      response.end();
      return;
    }
    createReadStream(path).pipe(response);
  } catch {
    response.writeHead(404, {
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "no-store",
    });
    response.end("Not found.\n");
  }
}).listen(port, "127.0.0.1", () => {
  console.log(`Battle/Star.SOL available at http://127.0.0.1:${port}/`);
});
