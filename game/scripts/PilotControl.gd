extends RefCounted
class_name PilotControl

## Human pilot authority for the default pre-alpha control model.
##
## Design intent (GAMEPLAY + architecture):
## - One human "login" into a body at a time (Commander home body by default).
## - Other squad slots are autonomous agents (same action vocabulary / AI).
## - Remotes (dev special) jacks the human into an ally agent temporarily.
## - Behavior over private rules: bots are distinguished by policy, not stats.

const Config = preload("res://scripts/GameConfig.gd")

static func is_human_pilot(unit) -> bool:
	return unit != null and bool(unit.alive) and bool(unit.player_controlled)

static func can_human_command(unit, player_faction: int, turn: int, action: String) -> bool:
	if unit == null or not bool(unit.alive):
		return false
	if int(unit.team) != turn:
		return false
	# Inspect-select and remotes plumbing are not "command" verbs.
	if action in ["select", "remotes", "remotes_home", "endturn"]:
		return true
	if int(unit.team) != player_faction:
		return false
	return is_human_pilot(unit)

static func get_commander(units: Array, player_faction: int):
	for u in units:
		if u != null and bool(u.alive) and int(u.team) == player_faction and bool(u.is_commander):
			return u
	for u in units:
		if u != null and bool(u.alive) and int(u.team) == player_faction and bool(u.player_controlled):
			return u
	return null

static func get_active_pilot(units: Array, player_faction: int):
	for u in units:
		if u != null and bool(u.alive) and int(u.team) == player_faction and bool(u.player_controlled):
			return u
	return null

static func list_squad_bots(units: Array, player_faction: int) -> Array:
	var out: Array = []
	for u in units:
		if u == null or not bool(u.alive):
			continue
		if int(u.team) != player_faction:
			continue
		if bool(u.is_squad_bot) and not bool(u.player_controlled):
			out.append(u)
	return out

static func apply_default_squad_roles(unit, slot_index: int) -> void:
	if unit == null:
		return
	if slot_index == 0:
		unit.is_commander = true
		unit.is_squad_bot = false
		unit.player_controlled = true
		var n := String(unit.name).strip_edges()
		if n.is_empty() or n.begins_with("Vanguard") or n == "Lead" or n == "Alpha" or n == "Dev-1":
			unit.name = "Commander"
	else:
		unit.is_commander = false
		unit.is_squad_bot = true
		unit.player_controlled = false
		var nm := String(unit.name)
		if not nm.to_lower().contains("agent"):
			unit.name = "%s (Agent)" % nm

static func set_human_pilot(units: Array, player_faction: int, unit) -> bool:
	if unit == null or not bool(unit.alive) or int(unit.team) != player_faction:
		return false
	for u in units:
		if u != null and int(u.team) == player_faction:
			u.player_controlled = (u == unit)
	return true

static func remotes_login(units: Array, player_faction: int, target) -> Dictionary:
	## Returns {ok:bool, reason:String, pilot:Unit}
	if target == null or not bool(target.alive) or int(target.team) != player_faction:
		return {"ok": false, "reason": "target must be a living squad unit", "pilot": null}
	if bool(target.is_commander):
		return remotes_return_home(units, player_faction)
	if not bool(target.is_squad_bot):
		return {"ok": false, "reason": "body is not a remote-capable agent", "pilot": null}
	set_human_pilot(units, player_faction, target)
	return {"ok": true, "reason": "login", "pilot": target}

static func remotes_return_home(units: Array, player_faction: int) -> Dictionary:
	var commander = get_commander(units, player_faction)
	if commander == null:
		return {"ok": false, "reason": "no Commander body", "pilot": null}
	set_human_pilot(units, player_faction, commander)
	return {"ok": true, "reason": "home", "pilot": commander}

static func pick_default_selection(units: Array, player_faction: int):
	var pilot = get_active_pilot(units, player_faction)
	if pilot != null:
		return pilot
	return get_commander(units, player_faction)
