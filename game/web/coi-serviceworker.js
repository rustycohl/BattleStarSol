/* coi-serviceworker v0.1.7 — Guido Zuidhof, MIT. Adds COOP/COEP headers so
   SharedArrayBuffer works on static hosts (e.g. GitHub Pages). Only needed if you
   export the Godot Web build WITH threads. Single-threaded export needs neither. */
if (typeof window === 'undefined') {
  self.addEventListener('install', () => self.skipWaiting());
  self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
  self.addEventListener('fetch', function (event) {
    const r = event.request;
    if (r.cache === 'only-if-cached' && r.mode !== 'same-origin') return;
    event.respondWith(fetch(r).then(function (response) {
      if (response.status === 0) return response;
      const headers = new Headers(response.headers);
      headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
      headers.set('Cross-Origin-Opener-Policy', 'same-origin');
      return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
    }).catch(function (e) { console.error(e); }));
  });
} else {
  (function () {
    if (window.crossOriginIsolated !== false) return;
    const s = document.currentScript && document.currentScript.src || 'coi-serviceworker.js';
    navigator.serviceWorker && navigator.serviceWorker.register(s).then(function (reg) {
      reg.addEventListener('updatefound', () => window.location.reload());
      if (reg.active && !navigator.serviceWorker.controller) window.location.reload();
    });
  })();
}
