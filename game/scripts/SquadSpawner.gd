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

## The guided Proving Ground's armed instructor. The target dummies teach the
## action surface; Haili is the one agent in the tutorial with a real action-point
## pool, so cover and flanking can actually be taught and observed rather than
## only asserted in headless tests.
##
## Naming note (principal decision, 2026-07-29): "Haili" is a casual personal
## name and is distinct in fact from the franchise property "H.A.I.L.I.", even
## though lineage exists between them. Do not merge the two entries, and do not
## expand this character's name into the acronym.
const INSTRUCTOR_NAME := "Haili"

## Every squad member carries one grenade, so the destructible-terrain mechanics are
## testable by hand from the first turn.
const GRENADE_KIND := "grenade"
const STARTING_GRENADES := 1
const INSTRUCTOR_STANDOFF := 5

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

static func tutorial_dummy_cells(
	player_faction: int,
	width: int = Config.GRID_W,
	height: int = Config.GRID_H
) -> Array[Vector2i]:
	var player_cells := World.spawn_cells(player_faction, width, height)
	if player_cells.is_empty():
		return []
	var start: Vector2i = player_cells[0]
	var toward_center := Vector2i(
		1 if start.x < int(width / 2.0) else -1,
		1 if start.y < int(height / 2.0) else -1
	)
	return [
		Vector2i(start.x + toward_center.x * 2, start.y),
		Vector2i(start.x + toward_center.x * 2, start.y + toward_center.y)
	]

## Haili's instruction post. She stands beyond the one-turn melee lane so the
## guided steps stay reachable, but close enough that the player's squad holds
## line of sight on her — which is what lets her demonstrate cover and flanking
## instead of standing still.
static func tutorial_instructor_cell(
	player_faction: int,
	width: int = Config.GRID_W,
	height: int = Config.GRID_H
) -> Vector2i:
	var player_cells := World.spawn_cells(player_faction, width, height)
	if player_cells.is_empty():
		return Vector2i.ZERO
	var start: Vector2i = player_cells[0]
	var toward_center := Vector2i(
		1 if start.x < int(width / 2.0) else -1,
		1 if start.y < int(height / 2.0) else -1
	)
	return Vector2i(
		clampi(start.x + toward_center.x * INSTRUCTOR_STANDOFF, 0, width - 1),
		clampi(start.y + toward_center.y * 2, 0, height - 1)
	)

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
		# One grenade each, so terrain destruction is reachable in the first turn of
		# any mission rather than only after finding scattered loot.
		u.inv[GRENADE_KIND] = int(u.inv.get(GRENADE_KIND, 0)) + STARTING_GRENADES

	if sector == "Proving Ground":
		# Keep the deterministic training lane close enough for one move,
		# Brace/cover instruction, and a basic attack inside the Base-10 pool.
		# The opponent faction follows the player's choice instead of becoming
		# friendly when the Commander selects Syndicate/Metropoli.
		var fac := (player_faction + 1) % 3
		var dummy_cells := tutorial_dummy_cells(player_faction)
		for j in range(dummy_cells.size()):
			var dummy = main._make_unit(fac, dummy_cells[j])
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
		var instructor_cell := tutorial_instructor_cell(player_faction)
		var instructor = main._make_unit(fac, instructor_cell)
		instructor.name = INSTRUCTOR_NAME
		instructor.skills = (skills[fac] as Array).duplicate()
		instructor.hp = Config.UNIT_HP
		instructor.max_hp = Config.UNIT_HP
		instructor.ap = Config.MAX_AP
		instructor.max_ap = Config.MAX_AP
		instructor.is_commander = false
		instructor.is_squad_bot = false
		instructor.player_controlled = false
	elif sector == "Standoff":
		var fac := (player_faction + 1) % 3
		var lane_y := 3
		var target_cell := Vector2i(7, lane_y)
		var ranger_cell := Vector2i(1, lane_y)
		var cover_cell := Vector2i(3, lane_y + 1)
		
		# Move player to target cell
		if main.units.size() > 0:
			var p = main.units[0]
			p.cell = target_cell
			if p.node:
				p.node.position = main._cell_to_world(target_cell)
		
		var ranger = main._make_unit(fac, ranger_cell)
		ranger.name = "AI Ranger"
		ranger.skills = (skills[fac] as Array).duplicate()
		ranger.hp = Config.UNIT_HP
		ranger.max_hp = Config.UNIT_HP
		ranger.ap = Config.MAX_AP
		ranger.max_ap = Config.MAX_AP
		ranger.is_commander = false
		ranger.is_squad_bot = false
		ranger.player_controlled = false
		
		# Cover for the standoff lane. This has to come from `material_cell` like every
		# other piece of cover in the game. A bare `{"type", "z"}` dict scores the same,
		# because `Ballistics.density_of` falls back to the type's implied material and
		# reaches the identical density of 60 -- which is exactly why the special case was
		# invisible. What it loses is the `material` key: `_rebuild_tile` and the terrain
		# ledger both read "" where they should read "hard", so a replay of a Standoff
		# mission records that this wall was made of nothing before it broke.
		if main.cells.has(cover_cell):
			main.cells[cover_cell] = World.material_cell(Config.COVER, 3)
			World.spawn_tile(main.tiles_root, cover_cell, Config.COVER, 3, 888888)
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
