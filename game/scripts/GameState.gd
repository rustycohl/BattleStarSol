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

## --- Reproduction ledger budget -------------------------------------------------------
##
## Option E from `evidence/OBSERVATION-001-LEDGER-CAPACITY-2026-07-30.md`. The ledger has a
## hard ceiling and the worst property of that ceiling was its silence: a mission with heavy
## terrain destruction would play correctly, extract correctly, and produce a reproduction
## artifact that failed closed — with nobody told until afterwards.
##
## This does not raise the ceiling. It makes the ceiling visible while a player can still act.
##
## The caps are not retyped here. They live in `tools/repro-bundle.mjs`, which the runtime
## cannot import, so `game/data/repro_budget.json` is their res://-readable view and
## `tests/repro-budget.test.mjs` asserts the two agree.

const REPRO_BUDGET_PATH := "res://data/repro_budget.json"
var _repro_budget_cache: Dictionary = {}

func repro_budget_limits() -> Dictionary:
	if not _repro_budget_cache.is_empty():
		return _repro_budget_cache
	if not FileAccess.file_exists(REPRO_BUDGET_PATH):
		return {}
	var f := FileAccess.open(REPRO_BUDGET_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_repro_budget_cache = parsed
	return _repro_budget_cache

## How much of the reproduction budget this mission has spent, and how close it is to the
## cap that actually binds.
##
## Bytes are measured from the real serialised ledger rather than estimated per event, because
## events are not uniform in size and an estimate would drift from the bundler it is meant to
## predict. It is deliberately an approximation of the final artifact, not a duplicate of it:
## the bundler remains the gate and still fails closed. This is a readout.
func ledger_budget() -> Dictionary:
	var limits := repro_budget_limits()
	if limits.is_empty():
		return {}
	var max_events := int(limits.get("max_events", 0))
	var max_bytes := int(limits.get("max_repro_bytes", 0))
	var overhead := int(limits.get("baseline_overhead_bytes", 0))
	var warn_at := float(limits.get("warn_at_fraction", 0.75))

	var record_count := action_records.size() + event_records.size()
	var ledger_bytes := JSON.stringify(replay_bundle()).length()
	var byte_ceiling := maxi(max_bytes - overhead, 1)

	var event_fraction := float(record_count) / float(maxi(max_events, 1))
	var byte_fraction := float(ledger_bytes) / float(byte_ceiling)
	# The binding cap is whichever is closer to full. Measured on this project it is bytes,
	# but that is a measurement rather than a rule, so it is derived rather than assumed.
	var fraction := maxf(event_fraction, byte_fraction)
	var binding := "bytes" if byte_fraction >= event_fraction else "events"

	var status := "ok"
	if fraction >= 1.0:
		status = "over"
	elif fraction >= warn_at:
		status = "warn"

	return {
		"records": record_count,
		"max_events": max_events,
		"ledger_bytes": ledger_bytes,
		"byte_ceiling": byte_ceiling,
		"event_fraction": event_fraction,
		"byte_fraction": byte_fraction,
		"fraction": clampf(fraction, 0.0, 99.0),
		"remaining_fraction": clampf(1.0 - fraction, 0.0, 1.0),
		"binding_cap": binding,
		"status": status,
		"warn_at_fraction": warn_at
	}
