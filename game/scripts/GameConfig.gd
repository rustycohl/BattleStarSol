extends Node

# Centralized game configuration constants

const GRID_W := 20
const GRID_H := 20
static var cell_size := 2.0
const HEIGHT_STEP := 1.6
## Pre-alpha uses a Base-10 AP budget (compact HUD). Historical 24-AP notes are
## a prior tuning scale; do not mix scales mid-mission. ActionEconomy is the
## sole cost authority for UI, AI, legality, and replay.
const AP_SCALE := 1
const MAX_AP := 10
const AP_DISPLAY_SEGMENTS := 10
const MOVE_COST := 1
const SPRINT_MOVE_COST := 1
const CROUCH_MOVE_COST := 2
const PRONE_MOVE_COST := 3
const MELEE_COST := 4
## Local fog-of-war / sensor radius for hostile visibility (GAMEPLAY Shadow Play).
const TACTICAL_SENSOR_RADIUS := 12
const MAX_WALK_STEP := 1
const MAX_JUMP_STEP := 2
const MAX_FLIGHT_Z := 8

# Behavioral & Grid Scaling Parameters
const TARGET_GRID_SIZE := 100
const FUTURE_LARGE_GRID := 1000
const AGGRESSION := 0.85
const LOW_HP_BLOCK_THRESHOLD := 0.5
const AI_GUARD_LIMIT := 60

const FIST_DMG := 4
const ROCK_1H_DMG := 5
const ROCK_2H_DMG := 8
const SPEAR_SWEEP_DMG := 6
const CLUB_SWEEP_DMG := 5
const BOW_MELEE_DMG := 3
const STRING_MELEE_DMG := 1
const STRUNG_MELEE_DMG := 3

const THROW = {
	"rock":  {"cost": 4, "dmg": 5, "range": 6},
	"spear": {"cost": 4, "dmg": 7, "range": 5},
	"club":  {"cost": 4, "dmg": 4, "range": 3},
}

const ASSEMBLE_COST := 4
const BOW_COST := 5
const BOW_DMG := 9
const BOW_RANGE := 7

const BLOCK_COST := 2
const BLOCK_REDUCTION := 3
const COVER_REDUCTION := 2
const HALF_COVER_REDUCTION := 1
const GRAB_COST := 1
const JUMP_COST := 4
const DODGE_COST := 1
const FLIP_COST := 2
const HOVER_COST := 1
const FLIGHT_TOGGLE_COST := 1
const WALL_RUN_COST := 2
const WALL_JUMP_COST := 2
const CROUCH_COST := 1
const PRONE_COST := 2
const LEAN_COST := 1
const TAKE_COVER_COST := 1
const LEAVE_COVER_COST := 1
const COVER_MONKEY_MOVE_SURCHARGE := 1
const EQUIP_COST := 1
const UNIT_HP := 10

const FLOOR := 0
const COVER := 1
const HALF_COVER := 2
## Three hotseat factions (Battle/Star theme mapping lives in faction_name).
const FACTION_HAD := 0
const FACTION_SYND := 1
const FACTION_TIME := 2
## Default fireteam size for non-tutorial deploys (1 Commander + 2 Agents).
const STANDARD_SQUAD_SIZE := 3

const KINDS = ["rock", "spear", "club", "bow", "string", "arrow", "stringedbow"]
const ENEMY_WEAPONS = ["rock", "spear", "club"]
const CODES = {"rock": "R", "spear": "S", "club": "C", "bow": "Bw", "string": "St", "arrow": "Ar", "stringedbow": "SB"}
const INVALID_CELL = Vector2i(-999, -999)

# All systems that draw or pick the voxel grid must use the same transform.
# With an even-sized grid, GRID_W / 2.0 and (GRID_W - 1) / 2.0 differ by
# half a cell; that historical split made tiles appear one world unit away
# from their units, highlights, and mouse targets.
static func cell_to_world(cell: Vector2i, height_units: float = 0.0) -> Vector3:
	var offset_x := float(GRID_W - 1) * 0.5
	var offset_y := float(GRID_H - 1) * 0.5
	return Vector3(
		(float(cell.x) - offset_x) * cell_size,
		height_units * HEIGHT_STEP,
		(float(cell.y) - offset_y) * cell_size
	)

static func world_to_cell(world: Vector3) -> Vector2i:
	var offset_x := float(GRID_W - 1) * 0.5
	var offset_y := float(GRID_H - 1) * 0.5
	return Vector2i(
		int(round(world.x / cell_size + offset_x)),
		int(round(world.z / cell_size + offset_y))
	)

# ==========================================================
#  RETUNE (design v2) — scale, verticality, factions, difficulty
# ==========================================================

# Grid scale tiers — "Russian dolls": 10 -> 100 -> 1000, and never larger.
const MAX_GRID_SIZE := 1000

# Verticality payoff: a flat "+1 per level of height advantage."
# Taught to players as a mindset ("the enemy's gate is down"). See GDD 5.2.
const HIGH_GROUND_BONUS := 1

# ---------- Faction canon (the three hotseats) ----------
# The three team slots map to the shipping factions + their signature colours.
static func faction_name(team: int) -> String:
	match team:
		FACTION_HAD:  return "EFD"
		FACTION_SYND: return "Metropoli"
		FACTION_TIME: return "Kaiju/Aliens"
	return "Unknown"

## Static so call sites can use GameConfig.faction_color without relying on the
## autoload instance (keeps pure config helpers free of node lifecycle).
static func faction_color(team: int) -> Color:
	match team:
		FACTION_HAD:  return Color(0.20, 0.80, 0.92) # EFD / Defense    — Substrate Cyan
		FACTION_SYND: return Color(0.95, 0.68, 0.18) # Metropoli        — Amber
		FACTION_TIME: return Color(0.32, 0.90, 0.38) # Kaiju / Aliens   — Anomaly Green
	return Color.WHITE

# ---------- Difficulty modes [purely behavioral] ----------
# No mode grants a stat advantage — a harder mode only *thinks* better (GDD 6.2).
# Ordered easiest -> hardest.
enum Difficulty { RIP_AND_TEAR, FIRST_LIEUTENANT, TACTICAL_GENIUS, MASTER_AND_COMMANDER, APEX_PREDATOR }
const DEFAULT_DIFFICULTY := Difficulty.FIRST_LIEUTENANT

static func difficulty_name(d: int) -> String:
	match d:
		Difficulty.RIP_AND_TEAR:         return "Rip and Tear"
		Difficulty.FIRST_LIEUTENANT:     return "First Lieutenant"
		Difficulty.TACTICAL_GENIUS:      return "Tactical Genius"
		Difficulty.MASTER_AND_COMMANDER: return "Master and Commander"
		Difficulty.APEX_PREDATOR:        return "Apex Predator"
	return "First Lieutenant"

# Behavioral knobs the AI reads (see AIBehavior.gd).
# Higher modes play more consistently (less random jitter over the same scorer).
static func ai_jitter_amp(d: int) -> float:
	match d:
		Difficulty.RIP_AND_TEAR:         return 10.0
		Difficulty.FIRST_LIEUTENANT:     return 6.0
		Difficulty.TACTICAL_GENIUS:      return 4.0
		Difficulty.MASTER_AND_COMMANDER: return 2.5
		Difficulty.APEX_PREDATOR:        return 1.0
	return 6.0

# Rip and Tear is pure aggression: it never guards or self-preserves.
# Every other mode will block/brace when hurt.
static func ai_uses_defense(d: int) -> bool:
	return d != Difficulty.RIP_AND_TEAR
