extends RefCounted
class_name TurnDirector

## Authoritative turn phase ordering for the tactical sim.
##
## Player faction phase:
##   1. Refresh AP for whole squad
##   2. Human pilots Commander (or Remotes body)
##   3. On End Turn: autonomous squad bots resolve (same AI as hostiles)
##   4. Advance to next faction; hostiles resolve fully on their phases
##
## Main remains the scene owner; this type only sequences the policy.

const Config = preload("res://scripts/GameConfig.gd")
const Pilot = preload("res://scripts/PilotControl.gd")

var main: Node

func bind(host: Node) -> void:
	main = host

func refresh_team_ap(team: int, clear_flight: bool = false) -> void:
	if main == null:
		return
	for u in main.units:
		if not u.alive or int(u.team) != team:
			continue
		u.ap = u.max_ap
		u.reset_turn_momentum()
		u.blocking = u.taking_cover
		u.dodging = false
		u.flipping = false
		u.hovering = false
		if clear_flight:
			u.flying = false
		if main.has_method("_refresh_label"):
			main._refresh_label(u)

func advance_faction_index(current: int) -> int:
	return (current + 1) % 3

func should_increment_global_round(new_turn: int) -> bool:
	# Global round ticks when the cycle returns to HAD (team 0).
	return new_turn == Config.FACTION_HAD

func ally_bots_ready_to_act(player_faction: int) -> Array:
	var out: Array = []
	if main == null:
		return out
	for u in Pilot.list_squad_bots(main.units, player_faction):
		if int(u.max_ap) > 0 and int(u.ap) > 0:
			out.append(u)
	return out
