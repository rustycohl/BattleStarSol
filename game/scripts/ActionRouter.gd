extends Node

## The single action boundary for UI and hotkeys, designed to accept replay,
## scripted, and learned behavior providers after the resolver is extracted.
## Transport-specific experiments do not belong here.

const Config = preload("res://scripts/GameConfig.gd")

var game: Node = null

func bind(main_node: Node) -> void:
	game = main_node

func request_action(
	actor,
	action: String,
	target_cell: Vector2i = Config.INVALID_CELL,
	use_offhand: bool = false,
	target_z: int = -1
) -> bool:
	if game == null:
		return false
	# End Turn / remotes may be invoked without a living selected body.
	if actor == null and action not in ["endturn", "remotes", "remotes_home"]:
		return false
	# Reject actions for freed / dead actors early (defensive modular boundary).
	if actor != null and action not in ["endturn", "remotes", "remotes_home"]:
		if not bool(actor.alive) or actor.node == null or not is_instance_valid(actor.node):
			return false
	var ap_before := int(actor.ap) if actor != null else -1
	var accepted := bool(game.perform_action(actor, action, target_cell, use_offhand, target_z))
	# Note: AP for animated actions may still be in-flight; ap_after_dispatch is
	# the value immediately after the sync portion of perform_action returns.
	var ap_after_dispatch := int(actor.ap) if actor != null else -1
	GameState.record_action(
		actor,
		action,
		target_cell,
		use_offhand,
		target_z,
		ap_before,
		ap_after_dispatch,
		accepted,
		int(game.get("global_turn")),
		int(game.get("turn"))
	)
	if accepted:
		GameState.notify_action(action, actor, target_cell)
		if actor != null and game.has_method("schedule_maneuver_support_check"):
			game.schedule_maneuver_support_check(actor)
	return accepted
