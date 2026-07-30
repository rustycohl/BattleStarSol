extends RefCounted
class_name MovementContext

## Contextual movement legality and follow-up state.
##
## Movement verbs should enter this layer when their availability depends on
## geometry, posture, momentum, or another movement phase. This keeps them from
## becoming unrelated buttons that only spend AP and toggle a flag.

const Config = preload("res://scripts/GameConfig.gd")
const Ballistics = preload("res://scripts/Ballistics.gd")
const Maneuvers = preload("res://scripts/ManeuverState.gd")

const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
	Vector2i(0, -1)
]

## Commitable cover faces beside a cell. A face qualifies on the strength of the
## material still standing there, so a wall shot down to rubble stops offering
## cover without a separate rule.
static func cover_faces_at(
	cell: Vector2i,
	cells: Dictionary,
	actor_z: int = 0
) -> Array[Vector2i]:
	var options: Array[Vector2i] = []
	for direction in CARDINAL_DIRECTIONS:
		var candidate: Vector2i = cell + direction
		var data: Dictionary = cells.get(candidate, {})
		# A face has to be taller than the actor to be worth committing to.
		if (
			Ballistics.effective_cover_level(data) >= 2
			and int(data.get("z", 0)) > actor_z
		):
			options.append(candidate)
	return options

static func cover_options(unit, cells: Dictionary) -> Array[Vector2i]:
	var options: Array[Vector2i] = []
	if unit == null or not bool(unit.alive) or bool(unit.taking_cover):
		return options
	if bool(unit.flying) or bool(unit.hovering) or String(unit.stance) == "prone":
		return options
	if Maneuvers.is_committed(unit.maneuver):
		return options
	return cover_faces_at(Vector2i(unit.cell), cells, int(unit.z))

static func can_take_cover(unit, target: Vector2i, cells: Dictionary) -> bool:
	return target != Config.INVALID_CELL and cover_options(unit, cells).has(target)

static func can_leave_cover(unit) -> bool:
	return unit != null and bool(unit.alive) and bool(unit.taking_cover)

static func can_lean(unit, direction: String) -> bool:
	if unit == null or not bool(unit.alive) or not bool(unit.taking_cover):
		return false
	if Vector2i(unit.cover_cell) == Config.INVALID_CELL:
		return false
	if String(unit.stance) == "prone" or Maneuvers.is_committed(unit.maneuver):
		return false
	return direction in ["left", "right"]

static func has_run_momentum(unit) -> bool:
	if unit == null:
		return false
	return int(unit.run_distance_this_turn) + int(unit.sprint_distance_this_turn) > 0

static func can_initiate_jump(unit, precision_jump: bool = false) -> bool:
	if unit == null or not bool(unit.alive) or bool(unit.taking_cover):
		return false
	if bool(unit.flying) or bool(unit.hovering) or String(unit.stance) == "prone":
		return false
	if Maneuvers.is_committed(unit.maneuver):
		return false
	return precision_jump or has_run_momentum(unit)

static func wall_options(unit, cells: Dictionary) -> Array[Vector2i]:
	var options: Array[Vector2i] = []
	if unit == null or not bool(unit.alive) or bool(unit.taking_cover):
		return options
	if bool(unit.flying) or bool(unit.hovering) or String(unit.stance) == "prone":
		return options
	if Maneuvers.is_committed(unit.maneuver) or not has_run_momentum(unit):
		return options
	for direction in CARDINAL_DIRECTIONS:
		var candidate: Vector2i = Vector2i(unit.cell) + direction
		var data: Dictionary = cells.get(candidate, {})
		if (
			int(data.get("type", Config.FLOOR)) == Config.COVER
			and int(data.get("z", 0)) > int(unit.z)
		):
			options.append(candidate)
	return options

static func can_begin_wall_run(unit, wall_cell: Vector2i, cells: Dictionary) -> bool:
	return wall_cell != Config.INVALID_CELL and wall_options(unit, cells).has(wall_cell)

static func can_continue_wall_run(unit, cells: Dictionary) -> bool:
	if unit == null or not Maneuvers.is_wall_running(unit.maneuver):
		return false
	var wall_cell := Maneuvers.vector2(unit.maneuver.get("wall_cell", {}), Config.INVALID_CELL)
	var wall_height := int(cells.get(wall_cell, {}).get("z", 0))
	return wall_cell != Config.INVALID_CELL and wall_height > int(unit.z)

static func can_wall_jump(unit) -> bool:
	return unit != null and bool(unit.alive) and Maneuvers.is_wall_running(unit.maneuver)

static func movement_locked(unit) -> bool:
	return (
		unit != null
		and bool(unit.taking_cover)
		and not bool(unit.cover_monkey_active)
	)

static func action_locked(unit, action: String) -> bool:
	if unit == null:
		return false
	if movement_locked(unit) and action in [
		"move", "jump", "fly_to", "toggle_run", "toggle_walk", "dodge", "flip", "hover",
		"toggle_flight", "wall_run", "wall_jump"
	]:
		return true
	if Maneuvers.is_airborne(unit.maneuver) and action in [
		"move", "toggle_run", "toggle_walk", "dodge", "hover", "wall_run", "take_cover",
		"leave_cover", "crouch", "prone", "lean_l", "lean_r"
	]:
		return true
	if Maneuvers.is_wall_running(unit.maneuver) and action in [
		"move", "jump", "toggle_run", "toggle_walk", "dodge", "hover", "take_cover",
		"leave_cover", "crouch", "prone", "lean_l", "lean_r"
	]:
		return true
	return false
