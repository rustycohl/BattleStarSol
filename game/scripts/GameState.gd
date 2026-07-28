extends Node

# GameState.gd — Runtime state singleton

signal state_changed
signal turn_changed(new_turn: int)
signal unit_selected(unit)
signal ap_changed(unit)
signal action_performed(action: String, actor, target_cell: Vector2i)
signal record_added(record: Dictionary)

var turn: int = GameConfig.FACTION_HAD
var selected_unit = null
var units: Array = []
var cells: Dictionary = {}
var debris: Dictionary = {}
var game_over: bool = false
var busy: bool = false
var turn_count: int = 1
var kills_count: int = 0
var mission_seed: int = 84021
var generator_version: int = 1
var rules_version: String = "alpha-1"
var action_records: Array[Dictionary] = []
var event_records: Array[Dictionary] = []
var _record_sequence: int = 0

# Selected behavioral difficulty mode (see GameConfig.Difficulty / GDD 6.2).
var difficulty: int = GameConfig.DEFAULT_DIFFICULTY

# --- Roguelike Meta-Progression & Persistence ---
var commander_callsign: String = ""
var commander_faction: String = "HAD"
var mission_type: String = "covert"
var session_active: bool = false  # true while logged in -> return-from-match lands on the MAP, not login
var return_action: String = ""    # tracks what UI component launched the tactical layer to restore it on egress

var unlocked_tiers: Array = [0, 1]

# Vault (Permanent Resources)
var vault_fiat: int = 25000
var vault_alloys: int = 100
var vault_neural: int = 50

# Pending Loot (Risked during tactical layer)
var pending_loot := {
	"fiat": 0,
	"alloys": 0,
	"neural": 0
}

func reset_pending_loot() -> void:
	pending_loot = {"fiat": 0, "alloys": 0, "neural": 0}

func add_loot(type: String, amount: int) -> void:
	if pending_loot.has(type):
		pending_loot[type] += amount
		emit_signal("state_changed")

func commit_extraction() -> void:
	var n_gained = pending_loot["neural"]
	vault_fiat += pending_loot["fiat"]
	vault_alloys += pending_loot["alloys"]
	vault_neural += n_gained
	reset_pending_loot()
	var Economy = get_node_or_null("/root/Economy")
	if Economy and n_gained > 0:
		Economy.earn_neural(n_gained, "Tactical Extraction")
	emit_signal("state_changed")

func fail_extraction() -> void:
	reset_pending_loot()
	emit_signal("state_changed")

func reset_state() -> void:
	turn = GameConfig.FACTION_HAD
	selected_unit = null
	units.clear()
	cells.clear()
	debris.clear()
	game_over = false
	busy = false
	turn_count = 1
	kills_count = 0
	action_records.clear()
	event_records.clear()
	_record_sequence = 0
	emit_signal("state_changed")

func begin_mission(seed_value: int, generation: int = 1, rules: String = "alpha-1") -> void:
	mission_seed = seed_value if seed_value > 0 else 84021
	generator_version = generation
	rules_version = rules
	reset_state()

func get_seed() -> int:
	return mission_seed

func select_unit(u) -> void:
	selected_unit = u
	emit_signal("unit_selected", u)
	emit_signal("state_changed")

func set_turn(new_turn: int) -> void:
	turn = new_turn
	if turn == GameConfig.FACTION_HAD:
		turn_count += 1
	emit_signal("turn_changed", turn)
	emit_signal("state_changed")

func notify_ap_changed(u) -> void:
	emit_signal("ap_changed", u)
	emit_signal("state_changed")

func notify_action(action: String, actor, target_cell: Vector2i = GameConfig.INVALID_CELL) -> void:
	emit_signal("action_performed", action, actor, target_cell)

func _next_record_sequence() -> int:
	_record_sequence += 1
	return _record_sequence

func _actor_ref(actor) -> Dictionary:
	if actor == null:
		return {}
	return {
		"unit_id": int(actor.unit_id),
		"name": String(actor.name),
		"team": int(actor.team)
	}

func record_action(
	actor,
	action: String,
	target_cell: Vector2i,
	use_offhand: bool,
	target_z: int,
	ap_before: int,
	ap_after_dispatch: int,
	accepted: bool,
	round_index: int,
	active_team: int
) -> Dictionary:
	var record := {
		"sequence": _next_record_sequence(),
		"record_type": "action",
		"round": round_index,
		"active_team": active_team,
		"actor": _actor_ref(actor),
		"action": action,
		"target": {"x": target_cell.x, "y": target_cell.y, "z": target_z},
		"use_offhand": use_offhand,
		"ap_before": ap_before,
		"ap_after_dispatch": ap_after_dispatch,
		"accepted": accepted
	}
	action_records.append(record)
	emit_signal("record_added", record)
	return record

func record_event(event_name: String, payload: Dictionary = {}) -> Dictionary:
	var record := {
		"sequence": _next_record_sequence(),
		"record_type": "event",
		"event": event_name,
		"payload": payload.duplicate(true)
	}
	event_records.append(record)
	emit_signal("record_added", record)
	return record

func replay_bundle() -> Dictionary:
	return {
		"mission_seed": mission_seed,
		"generator_version": generator_version,
		"rules_version": rules_version,
		"actions": action_records.duplicate(true),
		"events": event_records.duplicate(true)
	}
