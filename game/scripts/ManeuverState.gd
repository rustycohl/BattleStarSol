extends RefCounted

## Serializable state shared by contextual movement chains.
##
## A maneuver is a mechanical phase with an origin, spatial anchor, legal
## follow-ups, accumulated AP, and an explicit exit. It is not a UI toggle.

const GROUNDED := "grounded"
const AIRBORNE := "airborne_committed"
const WALL_RUNNING := "wall_running"

static func grounded(exit_reason: String = "") -> Dictionary:
	return {
		"phase": GROUNDED,
		"kind": "",
		"stage": 0,
		"origin": {},
		"anchor": {},
		"planned_landing": {},
		"wall_cell": {},
		"wall_normal": {},
		"local_up": {"x": 0, "y": 1, "z": 0},
		"local_forward": {},
		"momentum": {"run": 0, "sprint": 0},
		"ap_spent": 0,
		"started_round": 0,
		"exit_reason": exit_reason
	}

static func point(cell: Vector2i, z: int) -> Dictionary:
	return {"x": cell.x, "y": cell.y, "z": z}

static func vector2(value: Variant, fallback: Vector2i = Vector2i.ZERO) -> Vector2i:
	if value is Dictionary:
		return Vector2i(int(value.get("x", fallback.x)), int(value.get("y", fallback.y)))
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return fallback

static func height(value: Variant, fallback: int = 0) -> int:
	if value is Dictionary:
		return int(value.get("z", fallback))
	if value is Array and value.size() >= 3:
		return int(value[2])
	return fallback

static func airborne(
	origin_cell: Vector2i,
	origin_z: int,
	anchor_cell: Vector2i,
	anchor_z: int,
	landing_cell: Vector2i,
	landing_z: int,
	stage: int,
	run_distance: int,
	sprint_distance: int,
	ap_spent: int,
	started_round: int,
	source: String = "jump"
) -> Dictionary:
	var state := grounded()
	state["phase"] = AIRBORNE
	state["kind"] = source
	state["stage"] = stage
	state["origin"] = point(origin_cell, origin_z)
	state["anchor"] = point(anchor_cell, anchor_z)
	state["planned_landing"] = point(landing_cell, landing_z)
	state["momentum"] = {
		"run": maxi(run_distance, 0),
		"sprint": maxi(sprint_distance, 0)
	}
	state["ap_spent"] = maxi(ap_spent, 0)
	state["started_round"] = maxi(started_round, 0)
	return state

static func wall_run(
	origin_cell: Vector2i,
	origin_z: int,
	anchor_cell: Vector2i,
	anchor_z: int,
	wall_cell: Vector2i,
	wall_normal: Vector2i,
	forward: Vector2i,
	run_distance: int,
	sprint_distance: int,
	ap_spent: int,
	started_round: int
) -> Dictionary:
	var state := grounded()
	state["phase"] = WALL_RUNNING
	state["kind"] = "wall_run"
	state["stage"] = 1
	state["origin"] = point(origin_cell, origin_z)
	state["anchor"] = point(anchor_cell, anchor_z)
	state["wall_cell"] = point(wall_cell, anchor_z)
	state["wall_normal"] = {"x": wall_normal.x, "y": wall_normal.y}
	state["local_up"] = {"x": 0, "y": 0, "z": 1}
	state["local_forward"] = {"x": forward.x, "y": forward.y}
	state["momentum"] = {
		"run": maxi(run_distance, 0),
		"sprint": maxi(sprint_distance, 0)
	}
	state["ap_spent"] = maxi(ap_spent, 0)
	state["started_round"] = maxi(started_round, 0)
	return state

static func normalize(value: Variant) -> Dictionary:
	var state := grounded()
	if value is not Dictionary:
		return state
	for key in state:
		if value.has(key):
			state[key] = value[key]
	var phase := String(state.get("phase", GROUNDED))
	if phase not in [GROUNDED, AIRBORNE, WALL_RUNNING]:
		state["phase"] = GROUNDED
		state["exit_reason"] = "invalid_serialized_phase"
	state["stage"] = maxi(int(state.get("stage", 0)), 0)
	state["ap_spent"] = maxi(int(state.get("ap_spent", 0)), 0)
	state["started_round"] = maxi(int(state.get("started_round", 0)), 0)
	var momentum: Dictionary = state.get("momentum", {})
	state["momentum"] = {
		"run": maxi(int(momentum.get("run", 0)), 0),
		"sprint": maxi(int(momentum.get("sprint", 0)), 0)
	}
	return state.duplicate(true)

static func is_airborne(state: Dictionary) -> bool:
	return String(state.get("phase", GROUNDED)) == AIRBORNE

static func is_wall_running(state: Dictionary) -> bool:
	return String(state.get("phase", GROUNDED)) == WALL_RUNNING

static func is_committed(state: Dictionary) -> bool:
	return String(state.get("phase", GROUNDED)) != GROUNDED
