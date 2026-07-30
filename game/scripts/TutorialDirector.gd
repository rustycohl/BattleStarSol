extends RefCounted
class_name TutorialDirector

## Deterministic, advisory Proving Ground state machine.
##
## The director observes only accepted actions and resolved simulation events.
## It does not grant AP, move units, reveal hidden state, or bypass the normal
## action router. The tactical rules remain the authority.

signal guidance_changed(snapshot: Dictionary)

enum Step {
	SELECT_COMMANDER,
	MOVE,
	DEFENSE,
	COVER,
	ATTACK,
	END_TURN,
	WAIT_FOR_RETURN,
	EXTRACT,
	COMPLETE
}

## Seven user-facing steps since 2026-07-30. COVER was added once the guided lane
## finally had cover in it and an instructor who uses it; before that the cover
## instruction existed only as alternate DEFENSE prose for a situation the
## scenario could never produce.
const USER_STEP_COUNT := 7

var active: bool = false
var step: int = Step.SELECT_COMMANDER
var player_faction: int = 0
var starting_round: int = 1
var cover_available: bool = false
var defense_affordable: bool = true
var transition_history: Array[Dictionary] = []

func begin(payload: Dictionary, faction: int, round_index: int = 1) -> bool:
	active = String(payload.get("sector", "")) == "Proving Ground"
	step = Step.SELECT_COMMANDER
	player_faction = faction
	starting_round = maxi(round_index, 1)
	cover_available = false
	defense_affordable = true
	transition_history.clear()
	if active:
		_emit_guidance()
	return active

func set_cover_available(value: bool) -> void:
	if cover_available == value:
		return
	cover_available = value
	# Never strand the player on a cover step whose cover has gone away — a move,
	# a stance change, or a committed maneuver can all remove the option.
	if active and step == Step.COVER and not cover_available:
		_advance(Step.ATTACK, "cover_unavailable")
		return
	if active and (step == Step.DEFENSE or step == Step.COVER):
		_emit_guidance()

func set_defense_affordable(value: bool) -> void:
	if defense_affordable == value:
		return
	defense_affordable = value
	if active and step == Step.DEFENSE:
		_emit_guidance()

func observe_action(action: String, actor) -> bool:
	if not active:
		return false
	var is_commander := (
		actor != null
		and bool(actor.get("alive"))
		and bool(actor.get("is_commander"))
		and int(actor.get("team")) == player_faction
	)

	match step:
		Step.SELECT_COMMANDER:
			if action == "select" and is_commander:
				return _advance(Step.MOVE, "commander_selected")
		Step.DEFENSE:
			if is_commander:
				# Taking cover satisfies defense outright, so a player who reaches
				# for the stronger option is never told they did it wrong.
				if cover_available and action == "take_cover":
					return _advance(Step.ATTACK, "cover_taken_during_defense")
				if action == "brace":
					if cover_available:
						return _advance(Step.COVER, "braced")
					return _advance(Step.ATTACK, "clear_lane_braced")
		Step.COVER:
			if is_commander and action == "take_cover":
				return _advance(Step.ATTACK, "cover_entered")
		Step.ATTACK:
			if is_commander and action in ["melee", "ranged"]:
				return _advance(Step.END_TURN, "basic_attack_accepted")
		Step.END_TURN:
			if action == "endturn":
				return _advance(Step.WAIT_FOR_RETURN, "turn_ended")
	return false

func observe_record(record: Dictionary) -> bool:
	if not active:
		return false
	if String(record.get("record_type", "")) != "event":
		return false
	var event_name := String(record.get("event", ""))
	var payload = record.get("payload", {})
	if not (payload is Dictionary):
		payload = {}

	if step == Step.MOVE and event_name == "movement_resolved":
		return _advance(Step.DEFENSE, "movement_resolved")
	if step == Step.WAIT_FOR_RETURN and event_name == "turn_started":
		var active_team := int(payload.get("active_team", -1))
		var round_index := int(payload.get("round", starting_round))
		if active_team == player_faction and round_index > starting_round:
			return _advance(Step.EXTRACT, "player_turn_returned")
	if step == Step.EXTRACT and event_name == "mission_resolved":
		return _advance(Step.COMPLETE, "extraction_resolved")
	return false

func current_snapshot() -> Dictionary:
	var title := ""
	var body := ""
	var display_step := 1

	match step:
		Step.SELECT_COMMANDER:
			title = "ORIENT / SELECT COMMANDER"
			body = "Click the green [CMDR] squad row or the Commander in the world. This confirms your active pilot and Base-10 AP pool."
			display_step = 1
		Step.MOVE:
			title = "PREVIEW / COMPLETE A MOVE"
			body = "Hover a reachable floor tile to preview the path and AP cost, then left-click it. AP is spent only as movement resolves."
			display_step = 2
		Step.DEFENSE:
			title = "DEFENSE / BRACE"
			if not defense_affordable:
				body = "You do not have enough AP to Brace. Press END TURN to refresh AP; the tutorial stays on DEFENSE and resumes when your Commander returns."
			elif cover_available:
				body = "Use Brace (B) to block incoming attacks. Cover is beside you, so Take Cover (T) also completes this step and is the stronger choice."
			else:
				body = "Use Brace (B) to block incoming attacks. Take Cover appears automatically whenever you stand beside valid cover."
			display_step = 3
		Step.COVER:
			title = "COVER / TAKE COVER"
			body = "Cover is adjacent. Choose Take Cover (T), then select a highlighted cover face. Committed cover blocks a firing lane; leaving it costs AP. Haili uses cover the same way — watch her during the hostile phase."
			display_step = 4
		Step.ATTACK:
			title = "BASIC ATTACK"
			body = "Click an adjacent Target Dummy for a melee attack. A legal ranged attack also completes this step when a weapon is ready."
			display_step = 5
		Step.END_TURN:
			title = "END TURN"
			body = "Press END TURN, Space, or Enter. Your Commander stops acting; allied Agents and hostile factions then resolve in order."
			display_step = 6
		Step.WAIT_FOR_RETURN:
			title = "OBSERVE THE PHASES"
			body = "Controls are intentionally locked while autonomous and hostile phases resolve. Wait for YOUR TURN (T2)."
			display_step = 6
		Step.EXTRACT:
			title = "EXTRACT / RETURN TO STRATEGY"
			body = "Use EXTRACT or F8. The tactical result returns to strategy and the local campaign applies it exactly once."
			display_step = 7
		Step.COMPLETE:
			title = "PROVING GROUND COMPLETE"
			body = "The guided sequence is complete. Returning to the strategic result now."
			display_step = 7

	return {
		"active": active,
		"step": step,
		"step_key": step_key(step),
		"display_step": display_step,
		"total_steps": USER_STEP_COUNT,
		"title": title,
		"body": body,
		"complete": step == Step.COMPLETE,
		"cover_available": cover_available,
		"defense_affordable": defense_affordable
	}

func step_key(value: int) -> String:
	match value:
		Step.SELECT_COMMANDER:
			return "select_commander"
		Step.MOVE:
			return "move"
		Step.DEFENSE:
			return "defense"
		Step.COVER:
			return "cover"
		Step.ATTACK:
			return "attack"
		Step.END_TURN:
			return "end_turn"
		Step.WAIT_FOR_RETURN:
			return "observe_phases"
		Step.EXTRACT:
			return "extract"
		Step.COMPLETE:
			return "complete"
	return "unknown"

func _advance(next_step: int, reason: String) -> bool:
	if next_step <= step:
		return false
	transition_history.append({
		"from": step_key(step),
		"to": step_key(next_step),
		"reason": reason
	})
	step = next_step
	_emit_guidance()
	return true

func _emit_guidance() -> void:
	emit_signal("guidance_changed", current_snapshot())
