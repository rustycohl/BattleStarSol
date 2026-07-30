extends RefCounted
class_name Ballistics

## Penetration and destruction of terrain cover.
##
## Cover in this game is not a flag on a tile. A cell has a material, a density,
## and an integrity, and cover is the consequence: a round either stops in the
## material, punches through with reduced effect, or breaks the material down so
## the cell no longer protects the same way. That relationship is what makes
## generated terrain meaningful — a spawn is safe or exposed because of what is
## actually standing there.
##
## Pure and deterministic. Nothing here reads global state, so the same shot
## against the same cell always resolves the same way, and the tests and the live
## simulation cannot disagree.

const Config = preload("res://scripts/GameConfig.gd")
const World = preload("res://scripts/WorldBuilder.gd")

## Penetration values are expressed on the same 0-100 scale as density, so a
## weapon's number can be read directly against a wall's number.
const PENETRATION := {
	"unarmed": 0,
	"primitive": 10,
	"ballistic": 45,
	"pistol": 35,
	"rifle": 55,
	"shotgun": 30,
	"sniper": 85,
	"laser": 65,
	"plasma": 90,
	"magnetic": 75
}

## Below this an intact cell is no longer treated as hard cover.
const HARD_COVER_FLOOR := 50
## Below this a cell offers no protection at all and reads as open ground.
const RUBBLE_FLOOR := 12

static func penetration_of(kind: String) -> int:
	return int(PENETRATION.get(kind, PENETRATION["primitive"]))

## Base-10, matching the action economy and the decadal density scale.
const PIERCE_PER_POINT := 10

## Damage types already carried by every weapon. A rail penetrator concentrates
## its energy, thermal burns rather than punches, kinetic is the baseline.
const DAMAGE_TYPE_PENETRATION := {
	"rail": 15,
	"kinetic": 0,
	"thermal": 5
}

## Penetration derived from the weapon's own authored fields rather than a second
## table keyed by name: `armor_pierce` scaled onto the density scale, adjusted by
## `damage_type`. `penetrates_cover` is existing authored intent that cover does
## not apply at all, so it reads as total penetration and current balance holds.
static func penetration_for_item(item) -> int:
	if not (item is Dictionary):
		return PENETRATION["unarmed"]
	var data: Dictionary = item
	if bool(data.get("penetrates_cover", false)):
		return 100
	var pierce := maxi(int(data.get("armor_pierce", 0)), 0)
	var type_bonus := int(
		DAMAGE_TYPE_PENETRATION.get(String(data.get("damage_type", "kinetic")), 0)
	)
	# Ten per point of armour piercing. The project's action economy is base-10 and
	# cover density is decadal, so a decadal weapon scale keeps the comparison
	# readable and avoids knife-edges: an earlier x9 scale left plasma at 59
	# against a 60-density wall, decided by one point nobody authored.
	return clampi(pierce * PIERCE_PER_POINT + type_bonus, 0, 100)

static func density_of(cell_data) -> int:
	if not (cell_data is Dictionary):
		return 0
	var data: Dictionary = cell_data
	# `integrity` is the current state; `density` is what the material started as.
	# Cells authored before materials existed — including the golden test fixtures —
	# carry neither, so their type supplies the material they always implied.
	if data.has("integrity"):
		return maxi(int(data["integrity"]), 0)
	if data.has("density") and int(data["density"]) > 0:
		return maxi(int(data["density"]), 0)
	return density_for_type(int(data.get("type", Config.FLOOR)), int(data.get("z", 0)))

static func density_for_type(cell_type: int, height: int = 0) -> int:
	var implied := World.material_cell(cell_type, maxi(height, _implied_height(cell_type)))
	return int(implied.get("density", 0))

static func _implied_height(cell_type: int) -> int:
	if cell_type == Config.COVER:
		return 3
	if cell_type == Config.HALF_COVER:
		return 1
	return 0

## The cell standing in the firing lane, if any: the face adjacent to the target on
## the axis the shot arrives from. Same rule the cover model already uses, so the
## round hits exactly the material that was protecting the target.
static func lane_cover_cell(from_cell: Vector2i, target_cell: Vector2i, cells: Dictionary):
	var dx := from_cell.x - target_cell.x
	var dy := from_cell.y - target_cell.y
	if dx != 0:
		var x_face := target_cell + Vector2i(signi(dx), 0)
		if effective_cover_level(cells.get(x_face, {})) > 0:
			return x_face
	if dy != 0:
		var y_face := target_cell + Vector2i(0, signi(dy))
		if effective_cover_level(cells.get(y_face, {})) > 0:
			return y_face
	return null

## Resolves one round against one cell.
##
## Returns the shot's outcome, how much of its effect survives, and the cell's
## integrity afterwards. A round that cannot beat the material stops dead; one
## that beats it passes through at reduced effect and takes the material with it.
static func resolve_penetration(cell_data, weapon_kind: String, power: int = 100) -> Dictionary:
	return resolve_with_penetration(cell_data, penetration_of(weapon_kind), power)

## Resolves using the weapon's own authored fields, which is the combat path.
static func resolve_item_penetration(cell_data, item, power: int = 100) -> Dictionary:
	return resolve_with_penetration(cell_data, penetration_for_item(item), power)

static func resolve_with_penetration(cell_data, penetration: int, power: int = 100) -> Dictionary:
	var integrity := density_of(cell_data)
	var safe_power := maxi(power, 0)
	if integrity <= 0:
		return {
			"outcome": "clear",
			"stopped": false,
			"power_through": safe_power,
			"integrity_before": 0,
			"integrity_after": 0,
			"damage_to_cover": 0
		}
	# Every hit works the material, whether or not the round gets through.
	var damage := maxi(int(round(float(penetration) * 0.5)), 1)
	var integrity_after := maxi(integrity - damage, 0)
	# Equal penetration does not pass: it would arrive with nothing left, which is a
	# knife-edge decided by rounding rather than by design. The material wins ties.
	if penetration <= integrity:
		return {
			"outcome": "stopped",
			"stopped": true,
			"power_through": 0,
			"integrity_before": integrity,
			"integrity_after": integrity_after,
			"damage_to_cover": integrity - integrity_after
		}
	# Through, but the material takes its share out of the round.
	var retained := clampf(1.0 - (float(integrity) / maxf(float(penetration), 1.0)), 0.0, 1.0)
	return {
		"outcome": "penetrated",
		"stopped": false,
		"power_through": int(round(float(safe_power) * retained)),
		"integrity_before": integrity,
		"integrity_after": integrity_after,
		"damage_to_cover": integrity - integrity_after
	}

## Applies wear to a cell and returns its new state. A cell degrades through its
## own material classes rather than vanishing: hard cover becomes soft cover,
## soft cover becomes rubble, rubble becomes open ground.
## How many tiers of material the remaining integrity can hold up.
##
## A column is a stack of tiers resting on the ground. Down is -Y, so material rests on what
## is beneath it and nothing floats: a column always occupies tiers 1..z contiguously from the
## ground up, and losing material shortens it from the top. That is the whole of the gravity
## rule, and it is what makes shedding sequential — a six-high wall goes 6, 5, 4, 3 rather
## than dropping to 2 the instant it crosses a threshold.
##
## Capacity per tier is the cell's *original* material spread over its *original* tier count.
## Both are fixed at generation: `density` is what the material started as and never changes as
## integrity falls, and `tiers` records the height it started at. Deriving capacity from the
## current height instead would make each tier cheaper as the column shrank, so the last tier
## would be indestructible.
static func supported_tiers(cell_data) -> int:
	if not (cell_data is Dictionary):
		return 0
	var data: Dictionary = cell_data
	var started_tiers := int(data.get("tiers", int(data.get("z", 0))))
	if started_tiers <= 0:
		return 0
	var started_density := int(data.get("density", 0))
	if started_density <= 0:
		# Pre-material cells imply their material from type, exactly as `density_of` does.
		started_density = density_for_type(int(data.get("type", Config.FLOOR)), started_tiers)
	if started_density <= 0:
		return 0
	var capacity := maxf(float(started_density) / float(started_tiers), 1.0)
	return clampi(int(floor(float(density_of(data)) / capacity)), 0, started_tiers)

## Applies wear to a cell and returns its new state. A cell degrades through its
## own material classes rather than vanishing: hard cover becomes soft cover,
## soft cover becomes rubble, rubble becomes open ground.
##
## Height now sheds tier by tier under gravity rather than snapping at a threshold, and the
## result reports `tiers_lost` so the caller can account for the matter that came down. A tier
## does not cease to exist when it fails — see `Main.damage_terrain`, which turns the loss into
## debris on the ground through the existing debris system.
static func degrade_cell(cell_data, damage: int) -> Dictionary:
	if not (cell_data is Dictionary):
		return {}
	var data: Dictionary = (cell_data as Dictionary).duplicate(true)
	var height := int(data.get("z", 0))
	# Record the original tier count the first time a cell is worked on, so capacity per tier
	# stays fixed for the rest of its life.
	if not data.has("tiers"):
		data["tiers"] = height
	var integrity := maxi(density_of(data) - maxi(damage, 0), 0)
	data["integrity"] = integrity
	if integrity < RUBBLE_FLOOR:
		# Nothing is left standing, so there is no material left to take. Open
		# ground carries no density, exactly as freshly generated floor does.
		data["type"] = Config.FLOOR
		data["z"] = 0
		data["material"] = "rubble"
		data["climbable"] = false
		data["density"] = 0
		data["integrity"] = 0
	else:
		# Gravity first: the column can only be as tall as its remaining material supports,
		# and it never grows back.
		data["z"] = mini(height, maxi(supported_tiers(data), 1))
		if integrity < HARD_COVER_FLOOR:
			data["type"] = Config.HALF_COVER
			data["material"] = "soft"
			data["climbable"] = true
		data["climbable"] = int(data["z"]) > 0 and int(data["z"]) <= 2
	data["tiers_lost"] = maxi(height - int(data.get("z", 0)), 0)
	return data

## Armor on the same scale as terrain density and weapon penetration, so one
## concept governs "can this round get through that", whether "that" is a wall or a
## breastplate. Unit armor is authored in small integer points, base-10 like the
## action economy, so a point is worth ten on this scale.
static func armor_density(armor_points: int) -> int:
	return clampi(maxi(armor_points, 0) * PIERCE_PER_POINT, 0, 100)

## Resolves a round against worn armor. Mirrors terrain exactly: armor that beats
## the round stops it outright, armor the round beats mitigates only in proportion
## to what it took out of the shot.
static func resolve_armor(armor_points: int, item, power: int = 100) -> Dictionary:
	var result := resolve_with_penetration(
		{"integrity": armor_density(armor_points)},
		penetration_for_item(item),
		power
	)
	result["armor_points"] = maxi(armor_points, 0)
	result["armor_density"] = armor_density(armor_points)
	# How much of the armor's mitigation survives the round, 1.0 when the armor
	# stops it and 0.0 when the round is barely slowed.
	result["mitigation_scale"] = (
		1.0
		if bool(result["stopped"])
		else 1.0 - clampf(float(result["power_through"]) / 100.0, 0.0, 1.0)
	)
	return result

## Vertical cover. A wall only protects while it actually stands between the
## shooter and the target: shoot from above it, or stand on something taller than
## it, and it stops being cover. Height is already carried on every cell and every
## unit, so this reads existing state rather than adding a parallel one.
static func cover_stands_between(cell_data, shooter_z: int, target_z: int) -> bool:
	if not (cell_data is Dictionary):
		return false
	var cover_height := int((cell_data as Dictionary).get("z", 0))
	return cover_height > maxi(shooter_z, target_z)

## Cover strength derived from material state rather than tile type, so a wall
## that has been shot to pieces stops scoring as full cover.
static func effective_cover_level(cell_data) -> int:
	if not (cell_data is Dictionary):
		return 0
	var data: Dictionary = cell_data
	var integrity := density_of(data)
	if integrity < RUBBLE_FLOOR:
		return 0
	if int(data.get("type", Config.FLOOR)) == Config.COVER and integrity >= HARD_COVER_FLOOR:
		return 2
	if integrity >= RUBBLE_FLOOR:
		return 1
	return 0

## The best penetration a unit can currently bring, read from its own skills. Used
## to answer "can that wall actually protect me from this shooter".
static func best_penetration(skills: Array) -> int:
	var best := PENETRATION["unarmed"]
	for skill in skills:
		best = maxi(best, penetration_of(String(skill)))
	return best

## Whether a cell still protects a defender from a given shooter.
static func protects_against(cell_data, shooter_skills: Array) -> bool:
	var integrity := density_of(cell_data)
	if integrity < RUBBLE_FLOOR:
		return false
	return best_penetration(shooter_skills) < integrity
