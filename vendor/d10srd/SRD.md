# d10 System Reference Document — current alpha

Version: `0.1.0-alpha.2`

Rules identifier: `gzg.d10/0.1`

Documentation license: CC BY 4.0

## Purpose

d10SRD is a setting-neutral rules frame for checks, characters, actions,
conflict, consequences, and advancement. It preserves the calibrated shape of
the d20 legacy while enforcing the Ground Zero Games Base-10 constraint.

This document supplies rules, not a world. It requires no era, technology
level, genre, faction, character, account, chain, or game server.

## Core check

When an outcome is uncertain and both success and failure matter:

```text
check total = d10 + ability modifier + skill ranks + situational modifier
success when check total >= difficulty class
```

All fields are integers. The die result is 1–10. Skill ranks are 0–10.

## Difficulty conversion

Convert a d20 difficulty once:

```text
d10 difficulty = ceiling(d20 difficulty / 2)
```

| Tier | d20 DC | d10 DC |
| --- | ---: | ---: |
| Easy | 5 | 3 |
| Standard | 10 | 5 |
| Challenging | 15 | 8 |
| Difficult | 20 | 10 |
| Extremely Difficult | 25+ | 13+ |

This is difficulty/check scaling. Do not divide health, damage, movement,
range, time, capacity, currency, ammunition, action counts, or unrelated
economies unless a named module explicitly says so.

## Ability modifiers

Ability scores remain on the 4–20 legacy range.

| Ability score | d10 modifier |
| ---: | ---: |
| 4–5 | −2 |
| 6–9 | −1 |
| 10–11 | 0 |
| 12–15 | +1 |
| 16–19 | +2 |
| 20 | +3 |

## Critical threats

A natural 10 is a success threat. A natural 1 is a failure threat. Roll a
second d10; on 6 or higher, the critical confirms. The raw threat occurs 10%
of the time and the confirmation succeeds 50% of the time, restoring an
effective 5% critical rate.

## Base-10 action bridge

The tabletop action scale and xCommand’s 10 AP pool express the same resource
at different resolutions. `ActionEconomy` is the sole software authority for
the pool and action costs. A card may carry an AP modifier; it must not carry a
replacement absolute AP pool.

## Conformance

A conforming reference implementation must:

1. reproduce the published ability table, including `4–5 → −2`;
2. convert d20 DCs `5, 10, 15, 20, 25` to `3, 5, 8, 10, 13`;
3. require a 6+ confirmation for natural 1 and natural 10 threats;
4. retain integer skill ranks from 0–10;
5. keep the tactical AP maximum at 10; and
6. keep setting and transport authority outside this core.

The browser Page and Node test in this repository execute the first three
vectors directly. X-Command tests the Base-10 bridge.

## Publication history

Earlier d10 SRD material released under CC0 remains available under CC0. This
current-alpha document is original CC BY 4.0 material and does not withdraw,
restrict, or relicense that earlier grant.
