# M08-001 — d10SRD conformance against the pinned rules authority

- **Date:** 2026-07-30 (UTC-05:00)
- **Checkout:** `C:\CLAUDE\7-30-2026-Claude\BattleStarSol` — working copy of
  `C:\Antigravity\BattleStarSol` taken 06:03, at pushed HEAD `7a8c04f` plus the upstream
  agent's 98 uncommitted lines
- **Environment:** Godot 4.7.1.stable.official.a13da4feb, headless, Windows 11
- **Gate:** M08-001 — cross-product conformance is read from the rules authority, not
  retyped
- **Result:** **PASS**, with three negative controls observed failing first
- **Agent:** Claude Opus 5

## Finding that opened this gate

The upstream `Next-Phase Execution Walkthrough.md` records Loop 6 as closed:

> Modified TestRunner.gd: Added a new headless test (`_test_d10_conformance()`) that
> validates Godot's core constants (MAX_AP, UNIT_HP, movement costs, and weapon damage
> outputs) against the d10SRD.mjs rules. This closes the loop on cross-platform
> conformance…

Two things are wrong with that, and the second is the serious one.

**It does not read the rules.** There is no `d10SRD.mjs`, or any d10SRD artifact, anywhere
in the BattleStarSol repository — verified by `find`. The test asserted eighteen integer
literals typed into its own body. If d10SRD publishes a change, every one of those
assertions keeps passing and the divergence ships. That is the same failure shape as the
armor model earlier today: the assertion held while the thing it was meant to protect
drifted.

**Most of what it asserted is not d10SRD surface at all.** The SRD says, in the Difficulty
conversion section:

> This is difficulty/check scaling. Do not divide health, damage, movement, range, time,
> capacity, currency, ammunition, action counts, or unrelated economies unless a named
> module explicitly says so.

Of the eighteen assertions, exactly one — the tactical AP maximum, SRD Conformance vector
5 — is a d10SRD rule. `UNIT_HP`, the movement and posture costs, `BLOCK_REDUCTION`, and the
five weapon damage values are authored balance. Pinning them under a label reading
"d10SRD Conformance" means a deliberate balance change surfaces to the next agent as a
rules violation, and invites someone to "restore conformance" by reverting a tuning
decision.

Third, smaller: two assertions used the form `a == x or b == y`
(`SPEAR_SWEEP_DMG == 6 or THROW.spear.dmg == 7`), which passes when either half breaks.

## What the SRD actually requires of this port

From `rustycohl/d10SRD` `SRD.md`, rules id `gzg.d10/0.1`, version `0.1.0-alpha.2`, six
conformance vectors. Checked against this port:

| Vector | Requirement | Applies here | Why |
|---|---|---|---|
| 1 | published ability table, incl. 4–5 → −2 | No | no ability-score resolution in the port |
| 2 | d20 DC 5/10/15/20/25 → 3/5/8/10/13 | No | no difficulty class in the port |
| 3 | 6+ confirmation on natural 1 and 10 | No | no threat confirmation in the port |
| 4 | integer skill ranks 0–10 | No | Godot "skills" are equipment/capability tags, not ranked check inputs |
| 5 | tactical AP maximum stays 10 | **Yes** | `GameConfig.MAX_AP` |
| 6 | setting/transport authority outside the core | Yes, governance only | a constraint on the SRD, not a value this port can assert |

Absence verified by grep across `game/scripts/*.gd`: no ability modifier, no DC, no
threat confirmation, no rank field. The port implements no check resolution whatsoever, so
vectors 1–4 are genuinely not applicable rather than unimplemented.

## Change

1. **`game/data/d10srd_conformance.json` (new)** — the pinned authority. Carries
   `rules_id`, `srd_version`, source provenance, the six vectors with their applicability
   and reasons, the authority boundary including the SRD's own "do not divide" sentence,
   and a `forbidden_symbols` list. `game/data/` is the established res://-readable contract
   location, alongside `payload_contract.json` and `atlas_contract.json`.

2. **`_test_d10_conformance()` rewritten** to load the pin and assert: the pin is present
   and readable; `rules_id` is `gzg.d10/0.1`; `srd_version` is `0.1.0-alpha.2`; six vectors
   are present; every vector marked applicable and machine-checkable matches its named
   Godot symbol; at least one vector is applicable.

3. **The not-applicable claims are verified by absence.** The test reads
   `GameConfig`'s constant map and fails if any `forbidden_symbols` entry appears
   (`ABILITY_MODIFIER`, `DIFFICULTY_CLASS`, `SKILL_RANKS`, `THREAT_CONFIRM`, …). The moment
   this port grows a check resolver, the "not applicable" declarations become false and the
   build fails instead of passing quietly. This is the part that keeps the pin honest
   without anyone remembering to revisit it.

4. **`_test_balance_baseline()` (new)** holds the authored numbers under an accurate label,
   and splits the two `or` assertions so neither half can hide behind the other.

## Verification

Positive: `godot --headless --script res://tests/TestRunner.gd` → `PASS: Battle/Star.SOL
headless tests`.

Negative controls, each observed failing before being reverted:

| Mutation | Observed failure |
|---|---|
| `MAX_AP := 10` → `9` | `FAIL: d10SRD conformance vector 5 (keep the tactical AP maximum at 10): GameConfig.MAX_AP is 9, the SRD requires 10` |
| added `const SKILL_RANKS := 5` | `FAIL: d10SRD conformance: SKILL_RANKS now exists in GameConfig, so vectors 1-4 are no longer not-applicable -- implement them against the SRD or re-pin` |
| pin `srd_version` → `0.2.0` | `FAIL: d10SRD conformance: pinned srd_version moved (got '0.2.0') -- re-read the SRD Conformance section before accepting it` |

Both mutated files restored and confirmed byte-identical to their prior state
(`git diff` clean on `GameConfig.gd`; pin re-verified at `0.1.0-alpha.2`), suite re-run
green.

## Honest limit

**This closes the Godot half only.** The pin is a transcription, and a transcription is not
a live link: if d10SRD edits its Conformance section without changing `srd_version`, this
gate cannot see it. Closing the remaining half means either vendoring the d10SRD rules
module into this repo as a versioned artifact with a digest, or having CI fetch the
published `d10SRD` Page and compare. Neither is done here, so **Loop 6 remains PARTIAL, not
closed**, and the walkthrough's claim that it is closed should be corrected upstream.

What did change is that the failure is now loud instead of silent, and the label matches
what is actually being checked.
