extends Node

## Authoritative action-cost catalogue.
##
## All costs are integer tactical AP. The current rules use three AP for one
## legacy action unit, which preserves the old tempo while allowing sprint,
## standing, crouched, and prone movement to have distinct costs.

const Config = preload("res://scripts/GameConfig.gd")

static func fixed_cost(action: String) -> int:
	match action:
		"melee":
			return Config.MELEE_COST
		"jump":
			return Config.JUMP_COST
		"dodge":
			return Config.DODGE_COST
		"flip":
			return Config.FLIP_COST
		"hover":
			return Config.HOVER_COST
		"toggle_flight":
			return Config.FLIGHT_TOGGLE_COST
		"wall_run":
			return Config.WALL_RUN_COST
		"wall_jump":
			return Config.WALL_JUMP_COST
		"grab":
			return Config.GRAB_COST
		"assemble", "assemble_auto":
			return Config.ASSEMBLE_COST
		"brace":
			return Config.BLOCK_COST
		"crouch":
			return Config.CROUCH_COST
		"prone":
			return Config.PRONE_COST
		"lean_l", "lean_r":
			return Config.LEAN_COST
		"take_cover":
			return Config.TAKE_COVER_COST
		"leave_cover":
			return Config.LEAVE_COVER_COST
		"equip_fist":
			return Config.EQUIP_COST
	return 0

static func weapon_cost(item: Dictionary) -> int:
	return maxi(int(item.get("cost", Config.MOVE_COST)), 0)

static func movement_step_cost(unit, from_z: int, to_z: int) -> int:
	var cost := Config.MOVE_COST
	if unit != null:
		if String(unit.stance) == "prone":
			cost = Config.PRONE_MOVE_COST
		elif String(unit.stance) == "crouch":
			cost = Config.CROUCH_MOVE_COST
		elif String(unit.move_mode) == "sprint":
			cost = Config.SPRINT_MOVE_COST
		if bool(unit.cover_monkey_active):
			cost += Config.COVER_MONKEY_MOVE_SURCHARGE
		if bool(unit.hovering) or bool(unit.flying):
			return cost
	return cost + absi(to_z - from_z) * Config.AP_SCALE

static func path_cost(unit, path: Array, cells: Dictionary) -> int:
	if unit == null or path.size() < 2:
		return 0
	var total := 0
	var current_z := int(unit.z)
	for i in range(1, path.size()):
		var cell: Vector2i = path[i]
		var next_z := int(cells.get(cell, {}).get("z", 0))
		if bool(unit.hovering) or bool(unit.flying):
			next_z = maxi(next_z, current_z)
		total += movement_step_cost(unit, current_z, next_z)
		current_z = next_z
	return total

static func affordable_path(unit, path: Array, cells: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if unit == null or path.is_empty():
		return result
	result.append(Vector2i(path[0]))
	var spent := 0
	var current_z := int(unit.z)
	for i in range(1, path.size()):
		var cell: Vector2i = path[i]
		var next_z := int(cells.get(cell, {}).get("z", 0))
		if bool(unit.hovering) or bool(unit.flying):
			next_z = maxi(next_z, current_z)
		var step_cost := movement_step_cost(unit, current_z, next_z)
		if spent + step_cost > int(unit.ap):
			break
		spent += step_cost
		result.append(cell)
		current_z = next_z
	return result

static func flight_cost(from_cell: Vector2i, from_z: int, to_cell: Vector2i, to_z: int) -> int:
	var horizontal := absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)
	var vertical := absi(from_z - to_z)
	return maxi(Config.MOVE_COST, (horizontal + vertical) * Config.MOVE_COST)

static func format_cost(cost: int) -> String:
	return "%d AP" % cost
