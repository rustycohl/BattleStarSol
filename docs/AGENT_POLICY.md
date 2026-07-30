# Agent Development & Testing Policy

**CRITICAL POLICY: DO NOT MANGLE PRODUCTION CODE FOR LOCAL TESTING**

Battle/Star.SOL is a live alpha multiplayer product with a strictly maintained production environment. Future AI agents and developers working in this repository must adhere to the following strict boundaries between testing and production code:

## 1. Production Endpoints Must Remain Untouched
Production scripts, scenes, and UI launch surfaces (e.g., `StratLayer.gd`, `Main.gd`) must **always** point to the actual production endpoints (e.g., `https://rustycohl.github.io/BattleStarSol`).
- **NEVER** overwrite a production URL or launch script with a local loopback server (`127.0.0.1` or `tools/launch-web.ps1`) in the committed codebase.
- **NEVER** bypass turn cycles, network synchronization locks, or core game logic just to make a local test run faster. Doing so breaks the engine for all other clients and degrades the multiplayer determinism.

## 2. Proper Methods for Local Testing
If you need to test logic locally, use the isolated, non-destructive tools provided:
- Use the headless `TestRunner.gd` or `PlaytestRunner.gd` simulation suites via `tools/test.ps1`.
- If a temporary manual test is required, write a scratch script in your temporary workspace or use isolated environment variables. 
- *Any local testing hacks must be reverted before committing or pushing changes.*

## 3. The "Vibecoding" Trap
It is unacceptable to turn this ecosystem into a "vibecoded toy" that only works in your specific, isolated container environment. Code must run identically on the user's browser, the GitHub Pages deployment, and the native Godot engine. If your code relies on local PowerShell scripts or specific directory paths injected into production files, you have broken the project.

**If you are asked to "test this locally", it means to verify your changes using the established headless test suites or safe, temporary test branches—it NEVER means to permanently mutate the production deployment.**
