extends RefCounted
class_name AITactics

## Bounded, deterministic tactical-position planner for allied and hostile
## Agents. It proposes only ordinary ground paths and current cover actions;
## execution remains in Main and uses the same AP/legality authorities as the
## player path.

const Config = preload("res://scripts/GameConfig.gd")
const ActionCosts = preload("res://scripts/ActionEconomy.gd")
const MovementRules = preload("res://scripts/MovementContext.gd")
const Ballistics = preload("res://scripts/Ballistics.gd")

const SEARCH_RADIUS := 4

static func positioning_candidates(
	unit,
	units: Array,
	cells: Dictionary,
	pathfinder,
	attack_profile: Dictionary
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if (
		unit == null
		or not bool(unit.alive)
		or bool(unit.flying)
		or bool(unit.hovering)
		or String(unit.stance) == "prone"
		or pathfinder == null
	):
		return out

	var target = _nearest_hostile(unit, units)
	if target == null:
		return out
	var attack_cost := maxi(int(attack_profile.get("cost", Config.MELEE_COST)), 0)
	var attack_range := maxi(int(attack_profile.get("range", 1)), 1)
	var penetrates_cover := bool(attack_profile.get("penetrates_cover", false))

	if bool(unit.taking_cover):
		_append_committed_cover_candidate(
			out,
			unit,
			target,
			cells,
			pathfinder,
			attack_cost,
			attack_range,
			penetrates_cover
		)
		_sort_candidates(out)
		return out

	if attack_range <= 1:
		return out

	var current_exposure := exposure_count(Vector2i(unit.cell), unit, units, cells, pathfinder)
	var current_cover := cover_level(Vector2i(unit.cell), Vector2i(target.cell), cells)
	var current_los: bool = bool(pathfinder.has_los(
		Vector2i(unit.cell),
		Vector2i(target.cell),
		cells,
		int(unit.z),
		int(target.z),
		Config.INVALID_CELL,
		penetrates_cover
	))

	if int(unit.ap) >= attack_cost + Config.TAKE_COVER_COST:
		for cover_cell in MovementRules.cover_options(unit, cells):
			if not _cover_faces_threat(Vector2i(unit.cell), cover_cell, Vector2i(target.cell)):
				continue
			if not _has_attack_lane(
				Vector2i(unit.cell),
				int(unit.z),
				cover_cell,
				target,
				cells,
				pathfinder,
				attack_range,
				penetrates_cover
			):
				continue
			out.append({
				"key": "take_cover",
				"value": cover_cell,
				"score": 94.0 - float(current_exposure),
				"tie": _cell_key("take_cover", cover_cell),
				"rationale": "protective cover now; retain %d AP for offense" % (
					int(unit.ap) - Config.TAKE_COVER_COST
				)
			})

	_append_cover_routes(
		out,
		unit,
		target,
		units,
		cells,
		pathfinder,
		attack_cost,
		attack_range,
		penetrates_cover,
		current_exposure
	)
	_append_flank_routes(
		out,
		unit,
		target,
		units,
		cells,
		pathfinder,
		attack_cost,
		attack_range,
		penetrates_cover,
		current_exposure,
		current_cover,
		current_los
	)
	_sort_candidates(out)
	return out

static func can_afford_step_with_reserve(
	unit,
	step: Vector2i,
	cells: Dictionary,
	reserve_ap: int
) -> bool:
	if unit == null or not cells.has(step):
		return false
	var step_cost := ActionCosts.movement_step_cost(
		unit,
		int(unit.z),
		int(cells.get(step, {}).get("z", 0))
	)
	return int(unit.ap) - step_cost >= maxi(reserve_ap, 0)

static func exposure_count(
	position: Vector2i,
	unit,
	units: Array,
	cells: Dictionary,
	pathfinder
) -> int:
	var count := 0
	var position_z := int(cells.get(position, {}).get("z", int(unit.z)))
	for other in units:
		if other == null or not bool(other.alive) or int(other.team) == int(unit.team):
			continue
		if pathfinder.has_los(
			Vector2i(other.cell),
			position,
			cells,
			int(other.z),
			position_z
		):
			count += 1
	return count

## Cover read from the material standing in the firing lane. A wall that has been
## shot down to soft material scores as soft cover, and rubble scores as nothing,
## so destruction changes tactics without a second rule set.
## Elevation is optional so existing ground-level callers keep their meaning, but a
## wall that the shooter can see over no longer counts as cover.
static func cover_level(
	from_cell: Vector2i,
	target_cell: Vector2i,
	cells: Dictionary,
	from_z: int = 0,
	target_z: int = 0
) -> int:
	var dx := from_cell.x - target_cell.x
	var dy := from_cell.y - target_cell.y
	if dx != 0:
		var x_face = cells.get(target_cell + Vector2i(signi(dx), 0), {})
		var x_level: int = Ballistics.effective_cover_level(x_face)
		if x_level > 0 and Ballistics.cover_stands_between(x_face, from_z, target_z):
			return x_level
	if dy != 0:
		var y_face = cells.get(target_cell + Vector2i(0, signi(dy)), {})
		var y_level: int = Ballistics.effective_cover_level(y_face)
		if y_level > 0 and Ballistics.cover_stands_between(y_face, from_z, target_z):
			return y_level
	return 0

static func _append_committed_cover_candidate(
	out: Array[Dictionary],
	unit,
	target,
	cells: Dictionary,
	pathfinder,
	attack_cost: int,
	attack_range: int,
	penetrates_cover: bool
) -> void:
	var cover_cell := Vector2i(unit.cover_cell)
	if (
		penetrates_cover
		and pathfinder.has_los(
			Vector2i(unit.cell),
			Vector2i(target.cell),
			cells,
			int(unit.z),
			int(target.z),
			Config.INVALID_CELL,
			true
		)
	):
		return
	var has_lane := _has_attack_lane(
		Vector2i(unit.cell),
		int(unit.z),
		cover_cell,
		target,
		cells,
		pathfinder,
		attack_range,
		penetrates_cover
	)
	if (
		String(unit.lean) == "none"
		and has_lane
		and int(unit.ap) >= attack_cost + Config.LEAN_COST
	):
		out.append({
			"key": "lean_cover",
			"value": "left",
			"score": 96.0,
			"tie": "lean_cover:left",
			"rationale": "lean from committed cover; retain %d AP for fire" % (
				int(unit.ap) - Config.LEAN_COST
			)
		})
	elif not has_lane and int(unit.ap) >= attack_cost + Config.LEAVE_COVER_COST:
		out.append({
			"key": "leave_cover",
			"value": true,
			"score": 72.0,
			"tie": "leave_cover",
			"rationale": "cover has no legal attack lane; release for %d AP" % Config.LEAVE_COVER_COST
		})

static func _append_cover_routes(
	out: Array[Dictionary],
	unit,
	target,
	units: Array,
	cells: Dictionary,
	pathfinder,
	attack_cost: int,
	attack_range: int,
	penetrates_cover: bool,
	current_exposure: int
) -> void:
	var ordered_cells := _bounded_open_cells(Vector2i(unit.cell), units, cells, pathfinder)
	for candidate_cell in ordered_cells:
		var cover_faces := MovementRules.cover_faces_at(candidate_cell, cells)
		for cover_cell in cover_faces:
			if not _cover_faces_threat(candidate_cell, cover_cell, Vector2i(target.cell)):
				continue
			if not _has_attack_lane(
				candidate_cell,
				int(cells.get(candidate_cell, {}).get("z", 0)),
				cover_cell,
				target,
				cells,
				pathfinder,
				attack_range,
				penetrates_cover
			):
				continue
			var path: Array[Vector2i] = pathfinder.find_path(
				Vector2i(unit.cell),
				candidate_cell,
				cells,
				units
			)
			if path.size() < 2:
				continue
			var move_cost := ActionCosts.path_cost(unit, path, cells)
			var total_cost := move_cost + Config.TAKE_COVER_COST
			if int(unit.ap) - total_cost < attack_cost:
				continue
			var next_exposure := exposure_count(candidate_cell, unit, units, cells, pathfinder)
			if next_exposure > current_exposure:
				continue
			out.append({
				"key": "seek_cover",
				"value": {"path": path, "cover": cover_cell},
				"score": 76.0 + float(current_exposure - next_exposure) * 5.0 - float(move_cost),
				"tie": _cell_key("seek_cover", candidate_cell) + ":" + _cell_key("face", cover_cell),
				"rationale": "cover route %d AP; exposure %d→%d; retain %d AP" % [
					move_cost,
					current_exposure,
					next_exposure,
					int(unit.ap) - total_cost
				]
			})

static func _append_flank_routes(
	out: Array[Dictionary],
	unit,
	target,
	units: Array,
	cells: Dictionary,
	pathfinder,
	attack_cost: int,
	attack_range: int,
	penetrates_cover: bool,
	current_exposure: int,
	current_cover: int,
	current_los: bool
) -> void:
	for candidate_cell in _bounded_open_cells(Vector2i(unit.cell), units, cells, pathfinder):
		var candidate_z := int(cells.get(candidate_cell, {}).get("z", 0))
		if pathfinder.cheb(candidate_cell, Vector2i(target.cell)) > attack_range:
			continue
		var candidate_los: bool = bool(pathfinder.has_los(
			candidate_cell,
			Vector2i(target.cell),
			cells,
			candidate_z,
			int(target.z),
			Config.INVALID_CELL,
			penetrates_cover
		))
		if not candidate_los:
			continue
		var candidate_cover := cover_level(candidate_cell, Vector2i(target.cell), cells)
		var cover_gain := current_cover - candidate_cover
		var unlocks_los: bool = not current_los and candidate_los
		if cover_gain <= 0 and not unlocks_los:
			continue
		var path: Array[Vector2i] = pathfinder.find_path(
			Vector2i(unit.cell),
			candidate_cell,
			cells,
			units
		)
		if path.size() < 2:
			continue
		var move_cost := ActionCosts.path_cost(unit, path, cells)
		if int(unit.ap) - move_cost < attack_cost:
			continue
		var next_exposure := exposure_count(candidate_cell, unit, units, cells, pathfinder)
		if next_exposure > maxi(current_exposure, 1):
			continue
		out.append({
			"key": "flank",
			"value": path,
			"score": (
				88.0
				+ float(maxi(cover_gain, 0)) * 4.0
				+ (6.0 if unlocks_los else 0.0)
				- float(move_cost)
				- float(next_exposure)
			),
			"tie": _cell_key("flank", candidate_cell),
			"rationale": "simple flank %d AP; cover %d→%d; exposure %d→%d; retain %d AP" % [
				move_cost,
				current_cover,
				candidate_cover,
				current_exposure,
				next_exposure,
				int(unit.ap) - move_cost
			]
		})

static func _bounded_open_cells(
	origin: Vector2i,
	units: Array,
	cells: Dictionary,
	pathfinder
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for raw_cell in cells.keys():
		var cell := Vector2i(raw_cell)
		if cell == origin:
			continue
		if absi(cell.x - origin.x) + absi(cell.y - origin.y) > SEARCH_RADIUS:
			continue
		if int(cells.get(cell, {}).get("type", Config.FLOOR)) == Config.COVER:
			continue
		if not pathfinder.cell_free(cell, cells, units):
			continue
		out.append(cell)
	out.sort_custom(func(a: Vector2i, b: Vector2i):
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y
	)
	return out

static func _has_attack_lane(
	from_cell: Vector2i,
	from_z: int,
	ignored_cover: Vector2i,
	target,
	cells: Dictionary,
	pathfinder,
	attack_range: int,
	penetrates_cover: bool
) -> bool:
	if pathfinder.cheb(from_cell, Vector2i(target.cell)) > attack_range:
		return false
	return pathfinder.has_los(
		from_cell,
		Vector2i(target.cell),
		cells,
		from_z,
		int(target.z),
		ignored_cover,
		penetrates_cover
	)

static func _cover_faces_threat(
	position: Vector2i,
	cover_cell: Vector2i,
	threat_cell: Vector2i
) -> bool:
	var cover_direction := cover_cell - position
	var threat_direction := threat_cell - position
	return (
		cover_direction.x * threat_direction.x
		+ cover_direction.y * threat_direction.y
	) > 0

static func _nearest_hostile(unit, units: Array):
	var best = null
	var best_distance := 1 << 30
	var best_id := 1 << 30
	for other in units:
		if other == null or not bool(other.alive) or int(other.team) == int(unit.team):
			continue
		var distance := absi(other.cell.x - unit.cell.x) + absi(other.cell.y - unit.cell.y)
		var other_id := int(other.unit_id)
		if distance < best_distance or (distance == best_distance and other_id < best_id):
			best = other
			best_distance = distance
			best_id = other_id
	return best

static func _sort_candidates(candidates: Array[Dictionary]) -> void:
	candidates.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_score := float(a.get("score", 0.0))
		var b_score := float(b.get("score", 0.0))
		if not is_equal_approx(a_score, b_score):
			return a_score > b_score
		return String(a.get("tie", "")) < String(b.get("tie", ""))
	)

static func _cell_key(prefix: String, cell: Vector2i) -> String:
	return "%s:%+06d:%+06d" % [prefix, cell.x, cell.y]
