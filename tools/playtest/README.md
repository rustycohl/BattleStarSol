# Atomic playtest evidence foundation

This directory contains the platform-neutral evidence-pack boundary for the
Battle/Star.SOL autonomous playtest.

`evidence-pack.mjs` provides:

- a unique Windows-safe run ID;
- exclusive `<run-id>.partial` work directories;
- explicit deployment-to-extraction identity checks;
- screenshot and extraction size/hash checks;
- a sorted `SHA256SUMS` manifest; and
- final-directory publication only after every identity and digest check
  passes.

A completed playtest whose game gates fail is still valid evidence and may be
finalized. A harness error, mixed-run identity, missing artifact, or digest
failure remains in its `.partial` directory and must not be represented as a
complete pack.

This is the integrity foundation, not the whole M04 claim. The future runner
must still bound and allowlist report content, exclude personal/browser-profile
data, and prove the supported clean-checkout re-import path.

## Browser and server contract

The canonical local server remains the repository server at
`http://127.0.0.1:8781/`. An eventual browser runner must call
`probeDevServer()` before launch; this rejects the historical Python server on
port 8777 and any unrelated process occupying the port.

`PW_CHROMIUM` is the authoritative explicit browser path. The resolver also
supports a supplied Playwright browser path and ordinary Windows Chrome/Edge
install locations. A runner should record browser product/version and the
resolver source, but not a user-profile path.

## Browser runner

`run.mjs` ports the historical six-step driver onto this boundary. It uses
exactly pinned `playwright-core`, resolves the executable through
`resolveChromiumExecutable()`, verifies the served tactical PCK identity, and
drives exactly one strategic deployment through one full extraction.

Run the repository server first, then:

```powershell
npm.cmd run playtest
```

The driver prefers a published move that leaves enough AP for Brace plus
melee and ends orthogonally adjacent to a visible hostile. It falls back to
the cheapest published legal move only when that setup is unavailable.

Completed packs appear under `evidence/playtests/<run-id>/`. Harness errors
remain under `<run-id>.partial/`. No extension-attached browser session is
required.

M03 canonical cover/flank rationale is recorded as an observation because the
Proving Ground is not the required standoff scenario. Use `--require-m03` only
when intentionally running a scenario that is expected to close that live
behavioral gate.
