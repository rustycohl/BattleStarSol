extends RefCounted
class_name SquadSpawner

## Builds the three-faction tactical cast from a deploy payload.
## Applies the Commander + two Agent default control model.

const Config = preload("res://scripts/GameConfig.gd")
const Pilot = preload("res://scripts/PilotControl.gd")
const World = preload("res://scripts/WorldBuilder.gd")

const DEFAULT_SKILLS := {
	Config.FACTION_HAD: ["primitive", "ballistic", "pistol", "rifle", "shotgun", "sniper"],
	Config.FACTION_SYND: ["primitive", "laser", "pistol", "rifle", "magnetic"],
	Config.FACTION_TIME: ["primitive", "plasma", "rifle", "laser"]
}

const DEFAULT_NAMES := {
	Config.FACTION_HAD: ["Commander", "Scout (Agent)", "Heavy (Agent)"],
	Config.FACTION_SYND: ["Commander", "Alpha (Agent)", "Gamma (Agent)"],
	Config.FACTION_TIME: ["Commander", "Stalker (Agent)", "Titan (Agent)"]
}

static func faction_from_payload_string(raw: String) -> int:
	var fac := raw.to_lower()
	if fac.begins_with("had") or fac.begins_with("efd"):
		return Config.FACTION_HAD
	if fac.begins_with("synd") or fac.begins_with("metropoli"):
		return Config.FACTION_SYND
	if fac.begins_with("timecorps") or fac.begins_with("kaiju") or fac.begins_with("alien"):
		return Config.FACTION_TIME
	return Config.FACTION_HAD

static func resolve_player_faction(payload: Dictionary, commander_faction: String) -> int:
	if not payload.is_empty():
		return faction_from_payload_string(String(payload.get("faction", "")))
	return faction_from_payload_string(commander_faction)

static func spawn_into(main: Node, player_faction: int, payload: Dictionary) -> void:
	var sector := String(payload.get("sector", ""))
	var corners := {
		Config.FACTION_HAD: World.spawn_cells(Config.FACTION_HAD),
		Config.FACTION_SYND: World.spawn_cells(Config.FACTION_SYND),
		Config.FACTION_TIME: World.spawn_cells(Config.FACTION_TIME)
	}
	var names: Dictionary = DEFAULT_NAMES.duplicate(true)
	var skills: Dictionary = DEFAULT_SKILLS.duplicate(true)

	var squad_payload: Array = []
	if payload.has("squad") and payload["squad"] is Array:
		squad_payload = (payload["squad"] as Array).duplicate(true)

	var player_corner: Array = corners[player_faction]
	var player_names: Array = names[player_faction]
	var target_squad_size := 1 if sector == "Proving Ground" else 3
	while squad_payload.size() < target_squad_size:
		var fill_index: int = squad_payload.size()
		var fallback_name := String(player_names[mini(fill_index, player_names.size() - 1)])
		squad_payload.append({"name": fallback_name})

	for j in range(mini(squad_payload.size(), player_corner.size())):
		var sq_data: Dictionary = squad_payload[j]
		var u = main._make_unit(player_faction, player_corner[j])
		u.name = String(sq_data.get("name", player_names[mini(j, player_names.size() - 1)]))
		u.skills = (skills[player_faction] as Array).duplicate()
		Pilot.apply_default_squad_roles(u, j)

	if sector == "Proving Ground":
		var fac := Config.FACTION_SYND
		var fac_corner: Array = corners[fac]
		for j in range(mini(2, fac_corner.size())):
			var dummy = main._make_unit(fac, fac_corner[j])
			dummy.name = "Target Dummy"
			dummy.skills = ["primitive"]
			dummy.hp = 10
			dummy.max_hp = 10
			dummy.ap = 0
			dummy.max_ap = 0
			dummy.body_col = Color(0.8, 0.4, 0.1)
			dummy.is_commander = false
			dummy.is_squad_bot = false
			dummy.player_controlled = false
	else:
		for fac in [Config.FACTION_HAD, Config.FACTION_SYND, Config.FACTION_TIME]:
			if fac == player_faction:
				continue
			var fac_corner2: Array = corners[fac]
			var fac_names: Array = names[fac]
			for j in range(3):
				var enemy = main._make_unit(fac, fac_corner2[j])
				enemy.name = String(fac_names[j]).replace(" (Agent)", "").replace("Commander", String(fac_names[0]))
				# Hostile names: use clean defaults without agent suffix
				if fac == Config.FACTION_HAD:
					enemy.name = ["EFD Vanguard", "EFD Scout", "EFD Heavy"][j]
				elif fac == Config.FACTION_SYND:
					enemy.name = ["Metropoli Alpha", "Metropoli Beta", "Metropoli Gamma"][j]
				else:
					enemy.name = ["Kaiju Prime", "Alien Stalker", "Kaiju Titan"][j]
				enemy.skills = (skills[fac] as Array).duplicate()
				enemy.is_commander = false
				enemy.is_squad_bot = false
				enemy.player_controlled = false
