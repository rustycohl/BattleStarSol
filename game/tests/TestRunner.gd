extends SceneTree

const World = preload("res://scripts/WorldBuilder.gd")
const Contract = preload("res://scripts/PayloadContract.gd")
const Config = preload("res://scripts/GameConfig.gd")
const ActionCosts = preload("res://scripts/ActionEconomy.gd")
const MovementRules = preload("res://scripts/MovementContext.gd")
const Maneuvers = preload("res://scripts/ManeuverState.gd")
const PathScript = preload("res://scripts/Pathfinder.gd")
const UnitScript = preload("res://scripts/Unit.gd")
const SquadSpawn = preload("res://scripts/SquadSpawner.gd")
const Ballistics = preload("res://scripts/Ballistics.gd")
const Tactics = preload("res://scripts/AITactics.gd")
const Tutorial = preload("res://scripts/TutorialDirector.gd")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_seeded_generation()
	_test_payload_contract()
	_test_faction_vocabulary()
	_test_action_economy()
	_test_tutorial_state_machine()
	_test_contextual_movement()
	_test_web_contract()
	await _test_main_scene()
	await _test_multi_round_cycle()
	await _test_strategic_scene()
	if failures.is_empty():
		print("PASS: Battle/Star.SOL headless tests")
		quit(0)
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _signature(cells: Dictionary) -> String:
	var rows: Array = []
	for x in Config.GRID_W:
		for y in Config.GRID_H:
			var cell := Vector2i(x, y)
			var data: Dictionary = cells.get(cell, {})
			rows.append([
				x,
				y,
				int(data.get("type", -1)),
				int(data.get("z", -1)),
				bool(data.get("climbable", false))
			])
	return JSON.stringify(rows)

func _test_seeded_generation() -> void:
	var first := World.generate_cells(84021)
	var replay := World.generate_cells(84021)
	var other := World.generate_cells(84022)
	_expect(first.size() == Config.GRID_W * Config.GRID_H, "generator returned the wrong cell count")
	_expect(_signature(first) == _signature(replay), "same seed did not reproduce the same cells")
	_expect(_signature(first) != _signature(other), "different seeds produced identical cells")
	for data in first.values():
		_expect(data.has("type") and data.has("z") and data.has("climbable"), "cell is missing required fields")
	var spawn_seen := {}
	for team in [Config.FACTION_HAD, Config.FACTION_SYND, Config.FACTION_TIME]:
		var spawn_cells := World.spawn_cells(team)
		_expect(spawn_cells.size() == 3, "faction spawn does not contain three positions")
		for cell in spawn_cells:
			_expect(first.has(cell), "faction spawn is outside the generated map")
			_expect(int(first.get(cell, {}).get("z", -1)) == 0, "faction spawn was generated on elevated terrain")
			_expect(not spawn_seen.has(cell), "faction spawn positions overlap")
			spawn_seen[cell] = true

func _test_payload_contract() -> void:
	var legacy := {
		"type": "tactical_state",
		"deploy": {
			"sector": "Test Sector",
			"faction": "HAD",
			"seed": 77,
			"squad": [{"name": "Test-1"}],
			"objectives": ["Test"],
			"resources": {"neural": 0, "capital": 0}
		}
	}
	var normalized := Contract.normalize_deploy(legacy)
	_expect(normalized["type"] == "deploy", "legacy payload did not normalize")
	_expect(normalized["payload_contract_version"] == Contract.CONTRACT_VERSION, "contract version missing")
	_expect(int(normalized["seed"]) == 77, "normalization changed the seed")
	_expect(Contract.validate_deploy(normalized).is_empty(), "normalized deployment did not validate")
	var galaxy := {
		"gzg": "galaxy-message",
		"version": "1.0",
		"id": "deploy-test-77",
		"type": "battlestar.deploy",
		"payload": {
			"schema": "gzg.battlestar.deploy/1.0",
			"deploy": legacy["deploy"]
		}
	}
	var galaxy_normalized := Contract.normalize_deploy(galaxy)
	_expect(int(galaxy_normalized["seed"]) == 77, "galaxy deploy seed changed")
	_expect(galaxy_normalized["galaxy_message_id"] == "deploy-test-77", "galaxy message id was not preserved")
	_expect(Contract.validate_deploy(galaxy_normalized).is_empty(), "galaxy deployment did not validate")
	var future := galaxy.duplicate(true)
	future["version"] = "2.0"
	_expect(not Contract.validate_deploy(Contract.normalize_deploy(future)).is_empty(), "future galaxy major accepted")
	var invalid := normalized.duplicate(true)
	invalid["sector"] = ""
	_expect(not Contract.validate_deploy(invalid).is_empty(), "invalid deployment was accepted")

func _test_faction_vocabulary() -> void:
	_expect(Config.FACTION_HAD == 0, "HAD serialized faction ID drifted")
	_expect(Config.FACTION_SYND == 1, "Syndicate serialized faction ID drifted")
	_expect(Config.FACTION_TIME == 2, "Timecorps serialized faction ID drifted")
	_expect(Config.faction_name(Config.FACTION_HAD) == "HAD // EFD", "HAD visible alias set drifted")
	_expect(Config.faction_name(Config.FACTION_SYND) == "SYNDICATE // METROPOLI", "Syndicate visible alias set drifted")
	_expect(Config.faction_name(Config.FACTION_TIME) == "TIMECORPS // KAIJU/ALIENS", "Timecorps visible alias set drifted")
	var aliases := {
		"HAD": Config.FACTION_HAD,
		"EFD Defense": Config.FACTION_HAD,
		"SYNDICATE": Config.FACTION_SYND,
		"Metropoli Alpha": Config.FACTION_SYND,
		"Timecorps": Config.FACTION_TIME,
		"Kaiju/Aliens": Config.FACTION_TIME,
		"Aliens": Config.FACTION_TIME
	}
	for label in aliases:
		_expect(
			SquadSpawn.faction_from_payload_string(label) == int(aliases[label]),
			"faction parser no longer accepts canonical/legacy alias %s" % label
		)

func _test_action_economy() -> void:
	_expect(Config.MAX_AP == 10, "granular action economy does not expose the 10 AP budget")
	_expect(Config.AP_DISPLAY_SEGMENTS == 10, "AP display no longer preserves the compact 10-segment HUD")
	var unit := UnitScript.new()
	unit.ap = Config.MAX_AP
	unit.max_ap = Config.MAX_AP
	unit.move_mode = "run"
	unit.stance = "stand"
	unit.z = 0
	var cells := {
		Vector2i(0, 0): {"z": 0},
		Vector2i(1, 0): {"z": 0},
		Vector2i(2, 0): {"z": 1}
	}
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	_expect(ActionCosts.path_cost(unit, path, cells) == 3, "run path did not charge flat plus elevation AP")
	unit.move_mode = "sprint"
	_expect(ActionCosts.path_cost(unit, path, cells) == 3, "sprint path did not use its granular step cost")
	unit.move_mode = "run"
	unit.stance = "crouch"
	_expect(ActionCosts.path_cost(unit, path, cells) == 5, "crouched movement cost was not applied")
	unit.stance = "prone"
	_expect(ActionCosts.path_cost(unit, path, cells) == 7, "prone movement cost was not applied")
	unit.stance = "stand"
	unit.cover_monkey_active = true
	_expect(ActionCosts.path_cost(unit, path, cells) == 5, "Cover Monkey did not add one AP per movement segment")
	unit.cover_monkey_active = false
	var items: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	var rifle: Dictionary = items.get("t1_rifle", {})
	_expect(ActionCosts.weapon_cost(rifle) == 4, "weapon AP cost was not migrated to granular units")
	_expect(not bool(rifle.get("penetrates_cover", false)), "ordinary rifle unexpectedly penetrates cover")
	_expect(bool(items.get("t3_railgun", {}).get("penetrates_cover", false)), "railgun is not marked as cover-penetrating")

func _test_tutorial_state_machine() -> void:
	var director = Tutorial.new()
	_expect(
		not director.begin({"sector": "Ordinary Mission"}, Config.FACTION_HAD, 1),
		"tutorial activated outside the Proving Ground"
	)
	_expect(
		director.begin({"sector": "Proving Ground"}, Config.FACTION_HAD, 1),
		"Proving Ground did not activate the tutorial"
	)
	_expect(
		director.current_snapshot()["step_key"] == "select_commander",
		"tutorial did not begin at Commander selection"
	)

	var commander := UnitScript.new()
	commander.alive = true
	commander.team = Config.FACTION_HAD
	commander.is_commander = true
	_expect(director.observe_action("select", commander), "Commander selection did not advance tutorial")
	_expect(director.current_snapshot()["step_key"] == "move", "tutorial skipped the move step")
	_expect(
		director.observe_record({
			"record_type": "event",
			"event": "movement_resolved",
			"payload": {"actor": 1}
		}),
		"resolved movement did not advance tutorial"
	)
	director.set_cover_available(false)
	_expect(director.observe_action("brace", commander), "clear-lane Brace did not satisfy defense instruction")
	_expect(director.observe_action("melee", commander), "basic attack did not advance tutorial")
	_expect(director.observe_action("endturn", commander), "End Turn did not start observation step")
	_expect(
		not director.observe_record({
			"record_type": "event",
			"event": "turn_started",
			"payload": {"active_team": Config.FACTION_SYND, "round": 1}
		}),
		"hostile phase incorrectly completed turn observation"
	)
	_expect(
		director.observe_record({
			"record_type": "event",
			"event": "turn_started",
			"payload": {"active_team": Config.FACTION_HAD, "round": 2}
		}),
		"returned player turn did not expose extraction step"
	)
	_expect(
		director.observe_record({
			"record_type": "event",
			"event": "mission_resolved",
			"payload": {"outcome": "SUCCESS"}
		}),
		"mission resolution did not complete tutorial"
	)
	_expect(director.current_snapshot()["complete"], "tutorial completion flag is false")
	_expect(director.transition_history.size() == 7, "tutorial transition count drifted")

	# Cover as material: penetration, destruction, and the cover level that follows
	# from what a cell is actually made of.
	var hard_cell := World.material_cell(Config.COVER, 5)
	var soft_cell := World.material_cell(Config.HALF_COVER, 2)
	var open_cell := World.material_cell(Config.FLOOR, 0)
	_expect(
		int(hard_cell["density"]) > int(soft_cell["density"])
		and int(soft_cell["density"]) > int(open_cell["density"]),
		"terrain material does not scale density with cover class"
	)
	_expect(
		int(hard_cell["integrity"]) == int(hard_cell["density"]),
		"fresh terrain does not start at full integrity"
	)
	_expect(
		String(hard_cell["material"]) == "hard" and String(soft_cell["material"]) == "soft",
		"terrain material class is not recorded"
	)
	# A taller column is thicker, so it stops more.
	_expect(
		int(World.material_cell(Config.COVER, 6)["density"])
		> int(World.material_cell(Config.COVER, 3)["density"]),
		"column height does not inform density"
	)
	# Primitive weapons cannot beat hard cover; a sniper round can.
	var stopped: Dictionary = Ballistics.resolve_penetration(hard_cell, "primitive", 100)
	_expect(String(stopped["outcome"]) == "stopped", "primitive fire penetrated hard cover")
	_expect(int(stopped["power_through"]) == 0, "stopped fire delivered power through cover")
	_expect(
		int(stopped["damage_to_cover"]) > 0,
		"stopped fire did not work the material at all"
	)
	var through: Dictionary = Ballistics.resolve_penetration(hard_cell, "sniper", 100)
	_expect(String(through["outcome"]) == "penetrated", "sniper fire failed to penetrate hard cover")
	_expect(
		int(through["power_through"]) > 0 and int(through["power_through"]) < 100,
		"penetrating fire did not lose power to the material"
	)
	_expect(
		int(through["integrity_after"]) < int(through["integrity_before"]),
		"penetration left the material untouched"
	)
	# Sustained fire degrades cover through its material classes.
	var worked = hard_cell
	var degrade_guard := 0
	while Ballistics.effective_cover_level(worked) == 2 and degrade_guard < 20:
		var hit: Dictionary = Ballistics.resolve_penetration(worked, "rifle", 100)
		worked = Ballistics.degrade_cell(worked, int(hit["damage_to_cover"]))
		degrade_guard += 1
	_expect(degrade_guard > 0 and degrade_guard < 20, "hard cover never degraded under fire")
	_expect(
		Ballistics.effective_cover_level(worked) < 2,
		"degraded cover still scores as full cover"
	)
	while Ballistics.effective_cover_level(worked) > 0 and degrade_guard < 40:
		worked = Ballistics.degrade_cell(worked, 20)
		degrade_guard += 1
	_expect(
		int(worked["type"]) == Config.FLOOR and String(worked["material"]) == "rubble",
		"destroyed cover did not become open rubble"
	)
	# Weapon penetration is derived from the fields weapons already carry, so the
	# ordering follows the authored armour-piercing values rather than a second
	# table that could drift from them.
	var pistol_item: Dictionary = {"armor_pierce": 1, "damage_type": "kinetic"}
	var rifle_item: Dictionary = {"armor_pierce": 2, "damage_type": "kinetic"}
	var rail_item: Dictionary = {"armor_pierce": 5, "damage_type": "rail"}
	var flagged_item: Dictionary = {"armor_pierce": 0, "penetrates_cover": true}
	_expect(
		Ballistics.penetration_for_item(pistol_item)
		< Ballistics.penetration_for_item(rifle_item),
		"penetration does not follow armour-piercing order"
	)
	_expect(
		Ballistics.penetration_for_item(rail_item)
		> Ballistics.penetration_for_item(rifle_item),
		"a rail penetrator does not out-penetrate a kinetic rifle"
	)
	_expect(
		Ballistics.penetration_for_item({"armor_pierce": 2, "damage_type": "thermal"})
		> Ballistics.penetration_for_item(rifle_item),
		"damage type does not inform penetration"
	)
	_expect(
		Ballistics.penetration_for_item(flagged_item) == 100,
		"an authored cover-penetrating weapon is not treated as total penetration"
	)
	_expect(
		Ballistics.penetration_for_item("not-an-item") == Ballistics.PENETRATION["unarmed"],
		"a missing weapon is not unarmed"
	)
	# A light weapon is stopped by the thickest cover; the heaviest authored round
	# is not. Balance is asserted as an ordering, not as a magic number.
	var thickest := World.material_cell(Config.COVER, 6)
	_expect(
		String(Ballistics.resolve_item_penetration(thickest, pistol_item)["outcome"]) == "stopped",
		"a pistol defeats the thickest cover in the game"
	)
	_expect(
		String(Ballistics.resolve_item_penetration(thickest, flagged_item)["outcome"])
		== "penetrated",
		"an authored cover-penetrating weapon is stopped by cover"
	)
	# Balance is asserted as a shape, not as magic numbers: the weapon set must form
	# a real ladder against terrain rather than collapsing into "nothing gets
	# through" or "everything does".
	var weapon_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	_expect(weapon_data is Dictionary, "weapon data did not load for the balance check")
	if weapon_data is Dictionary:
		var thinnest_hard := World.material_cell(Config.COVER, 3)
		var thickest_hard := World.material_cell(Config.COVER, 6)
		var soft := World.material_cell(Config.HALF_COVER, 1)
		var tiers := {}
		var stopped_by_thickest := 0
		var through_thinnest_hard := 0
		var through_everything := 0
		var ranged_count := 0
		for weapon_key in (weapon_data as Dictionary):
			var weapon = (weapon_data as Dictionary)[weapon_key]
			if not (weapon is Dictionary):
				continue
			if String((weapon as Dictionary).get("category", "")) != "ranged":
				continue
			ranged_count += 1
			var pen: int = Ballistics.penetration_for_item(weapon)
			tiers[pen] = true
			_expect(
				pen >= 0 and pen <= 100,
				"%s penetration is off the density scale" % String(weapon_key)
			)
			if String(Ballistics.resolve_item_penetration(thickest_hard, weapon)["outcome"]) == "stopped":
				stopped_by_thickest += 1
			if String(Ballistics.resolve_item_penetration(thinnest_hard, weapon)["outcome"]) == "penetrated":
				through_thinnest_hard += 1
			if String(Ballistics.resolve_item_penetration(soft, weapon)["outcome"]) == "penetrated":
				through_everything += 1
			# Every weapon must be able to break cover eventually, or cover becomes
			# an absolute wall for that weapon and flanking is the only answer.
			var breaking = soft.duplicate(true)
			var break_guard := 0
			while Ballistics.effective_cover_level(breaking) > 0 and break_guard < 200:
				var work: Dictionary = Ballistics.resolve_item_penetration(breaking, weapon)
				breaking = Ballistics.degrade_cell(breaking, int(work["damage_to_cover"]))
				break_guard += 1
			_expect(
				break_guard < 200,
				"%s can never break even soft cover" % String(weapon_key)
			)
		_expect(ranged_count >= 8, "too few ranged weapons to judge the ladder")
		_expect(tiers.size() >= 4, "the weapon set has fewer than four penetration tiers")
		_expect(
			stopped_by_thickest > 0,
			"no weapon is stopped by the thickest cover in the game"
		)
		_expect(
			through_thinnest_hard > 0,
			"no weapon can shoot through the thinnest hard cover"
		)
		_expect(
			stopped_by_thickest < ranged_count,
			"every weapon is stopped by the thickest cover"
		)
		_expect(
			through_everything < ranged_count,
			"every weapon penetrates soft cover, so soft cover means nothing"
		)
	# The lane cell is the material that was actually protecting the target.
	var firing_lane := {
		Vector2i(2, 2): World.material_cell(Config.FLOOR, 0),
		Vector2i(3, 2): World.material_cell(Config.COVER, 4),
		Vector2i(4, 2): World.material_cell(Config.FLOOR, 0)
	}
	_expect(
		Ballistics.lane_cover_cell(Vector2i(5, 2), Vector2i(2, 2), firing_lane) == Vector2i(3, 2),
		"the firing lane does not resolve to the protecting cell"
	)
	_expect(
		Ballistics.lane_cover_cell(Vector2i(0, 2), Vector2i(2, 2), firing_lane) == null,
		"an unprotected lane reports cover"
	)
	# Single-authority checks. These exist because the recurring failure in this
	# project is building a second authority for something that already has one.
	# See .agents/08-CAPABILITY-REGISTER.md.
	var script_sources := {}
	for script_name in [
		"WorldBuilder", "Ballistics", "AITactics", "MovementContext",
		"CombatSystem", "Main", "SquadSpawner"
	]:
		script_sources[script_name] = FileAccess.get_file_as_string(
			"res://scripts/%s.gd" % script_name
		)
	# Exactly one place assigns terrain material.
	var material_assigners := 0
	for script_name in script_sources:
		if String(script_sources[script_name]).contains("\"integrity\": density"):
			material_assigners += 1
	_expect(
		material_assigners == 1,
		"terrain material is assigned in %d places; it must have one authority" % material_assigners
	)
	# Cover strength is derived from Ballistics, never re-derived from tile type.
	for script_name in ["AITactics", "MovementContext", "Main"]:
		var body := String(script_sources[script_name])
		_expect(
			not body.contains("== Config.COVER: return 2"),
			"%s re-derives cover level from tile type instead of material" % script_name
		)
	_expect(
		String(script_sources["AITactics"]).contains("Ballistics.effective_cover_level"),
		"cover scoring no longer reads the material authority"
	)
	_expect(
		String(script_sources["MovementContext"]).contains("Ballistics.effective_cover_level"),
		"commitable cover faces no longer read the material authority"
	)
	# Armor and terrain share one penetration scale.
	_expect(
		String(script_sources["Ballistics"]).contains("resolve_with_penetration"),
		"penetration no longer has a single resolver"
	)
	_expect(
		String(script_sources["CombatSystem"]).contains("Ballistics.resolve_armor"),
		"armor mitigation does not use the shared penetration scale"
	)
	# Weapon behaviour derives from item fields rather than a name-keyed table.
	_expect(
		String(script_sources["CombatSystem"]).contains("Ballistics.resolve_item_penetration"),
		"combat resolves penetration by weapon name instead of by item fields"
	)
	# Terrain changes go through the one authority that also records them.
	var terrain_mutators := 0
	for script_name in script_sources:
		if String(script_sources[script_name]).contains("Ballistics.degrade_cell"):
			terrain_mutators += 1
	_expect(
		terrain_mutators == 1,
		"terrain is degraded in %d places; it must have one authority" % terrain_mutators
	)
	_expect(
		String(script_sources["Main"]).contains("func damage_terrain"),
		"the terrain damage authority is missing"
	)

	# Vertical cover: a wall only protects while it actually stands between the
	# shooter and the target.
	var tall_wall := World.material_cell(Config.COVER, 4)
	_expect(
		Ballistics.cover_stands_between(tall_wall, 0, 0),
		"a tall wall does not protect two ground-level units"
	)
	_expect(
		not Ballistics.cover_stands_between(tall_wall, 5, 0),
		"a shooter above the wall is still blocked by it"
	)
	_expect(
		not Ballistics.cover_stands_between(tall_wall, 0, 4),
		"a target standing as high as the wall is still protected by it"
	)
	_expect(
		Ballistics.cover_stands_between(tall_wall, 3, 3),
		"a wall taller than both units stops protecting them"
	)
	var vertical_cells := {
		Vector2i(2, 2): World.material_cell(Config.FLOOR, 0),
		Vector2i(3, 2): World.material_cell(Config.COVER, 3),
		Vector2i(6, 2): World.material_cell(Config.FLOOR, 0)
	}
	_expect(
		Tactics.cover_level(Vector2i(6, 2), Vector2i(2, 2), vertical_cells, 0, 0) == 2,
		"ground-level fire ignores an interposed wall"
	)
	_expect(
		Tactics.cover_level(Vector2i(6, 2), Vector2i(2, 2), vertical_cells, 4, 0) == 0,
		"fire from above the wall is still reduced by it"
	)
	# Committing to cover also requires the face to be taller than the actor.
	var high_actor := UnitScript.new()
	high_actor.alive = true
	high_actor.stance = "stand"
	high_actor.cell = Vector2i(2, 2)
	high_actor.z = 4
	high_actor.taking_cover = false
	_expect(
		MovementRules.cover_options(high_actor, vertical_cells).is_empty(),
		"a unit standing above a wall can still commit to it as cover"
	)
	high_actor.z = 0
	_expect(
		MovementRules.cover_options(high_actor, vertical_cells) == [Vector2i(3, 2)],
		"a ground-level unit cannot commit to the adjacent wall"
	)

	# Armor resolves on the same penetration scale as terrain.
	_expect(
		Ballistics.armor_density(0) == 0 and Ballistics.armor_density(10) == 100,
		"armor is not expressed on the density scale"
	)
	var heavy_armor := 6
	var weak_round: Dictionary = {"armor_pierce": 1, "damage_type": "kinetic"}
	var heavy_round: Dictionary = {"armor_pierce": 9, "damage_type": "rail"}
	var stopped_by_armor: Dictionary = Ballistics.resolve_armor(heavy_armor, weak_round)
	var through_armor: Dictionary = Ballistics.resolve_armor(heavy_armor, heavy_round)
	_expect(
		bool(stopped_by_armor["stopped"]),
		"a weak round defeats heavy armor"
	)
	_expect(
		is_equal_approx(float(stopped_by_armor["mitigation_scale"]), 1.0),
		"armor that stops a round does not mitigate fully"
	)
	_expect(
		not bool(through_armor["stopped"]),
		"heavy armor stops a rail penetrator"
	)
	_expect(
		float(through_armor["mitigation_scale"]) < 1.0,
		"a penetrating round loses nothing to armor"
	)
	_expect(
		float(through_armor["mitigation_scale"]) >= 0.0,
		"armor mitigation went negative"
	)
	# The armor curve is pinned so it cannot drift silently again. `armor_pierce` must
	# keep shaving points — an earlier version put armor on terrain's density scale
	# alone, which made every tier-1 kinetic round "stopped" and erased the difference
	# between a pistol and a rifle.
	var pistol_pierce := 1
	var rifle_pierce := 2
	for armor_points in [1, 2, 4, 6, 8]:
		var pistol_eff: int = maxi(armor_points - pistol_pierce, 0)
		var rifle_eff: int = maxi(armor_points - rifle_pierce, 0)
		_expect(
			rifle_eff < pistol_eff or armor_points <= pistol_pierce,
			"a higher armour-piercing weapon does not beat more armour at %d points" % armor_points
		)
	# A round that defeats the armour outright is not mitigated at all.
	var defeating: Dictionary = {"armor_pierce": 10, "damage_type": "rail"}
	_expect(
		not bool(Ballistics.resolve_armor(6, defeating)["stopped"]),
		"a rail penetrator is stopped by medium armour"
	)
	# A round that cannot defeat it faces the authored subtraction, not zero.
	_expect(
		bool(Ballistics.resolve_armor(6, {"armor_pierce": 1, "damage_type": "kinetic"})["stopped"]),
		"a light kinetic round defeats medium armour outright"
	)
	# More armor is never worse against the same round.
	_expect(
		float(Ballistics.resolve_armor(8, heavy_round)["mitigation_scale"])
		>= float(Ballistics.resolve_armor(4, heavy_round)["mitigation_scale"]),
		"heavier armor mitigates less than lighter armor"
	)

	# The grenade: a thrown object whose blast is authored in its own item data.
	var item_db = root.get_node_or_null("ItemDB")
	var grenade_item = item_db.get_item("grenade") if item_db != null else {}
	_expect(grenade_item is Dictionary and not (grenade_item as Dictionary).is_empty(), "the grenade item is missing")
	if grenade_item is Dictionary and not (grenade_item as Dictionary).is_empty():
		var grenade: Dictionary = grenade_item
		_expect(
			int(grenade.get("blast_radius", 0)) >= 1,
			"the grenade has no blast radius"
		)
		_expect(
			bool(grenade.get("blast_terrain", false)),
			"the grenade does not affect terrain"
		)
		_expect(
			int(grenade.get("range", 0)) > 1,
			"the grenade cannot be thrown"
		)
		_expect(
			Config.KINDS.has("grenade") and Config.CODES.has("grenade"),
			"the grenade is not a registered carryable kind"
		)
		# Its blast must be able to break the hard cover it is meant to test.
		var blast_cell := World.material_cell(Config.COVER, 3)
		var blast_damage := maxi(int(round(float(int(grenade.get("dmg", 0))) * 3.0 * 1.5)), 1)
		_expect(
			Ballistics.effective_cover_level(
				Ballistics.degrade_cell(blast_cell, blast_damage)
			) < 2,
			"a point-blank grenade does not break hard cover"
		)
	# Cells authored before materials existed still read as the cover they implied.
	_expect(
		Ballistics.effective_cover_level({"type": Config.COVER, "z": 3}) == 2,
		"a legacy cover cell lost its protection"
	)
	_expect(
		Ballistics.effective_cover_level({"type": Config.FLOOR, "z": 0}) == 0,
		"open ground scores as cover"
	)
	# Whether a wall protects you depends on who is shooting at it.
	_expect(
		Ballistics.protects_against(hard_cell, ["primitive"]),
		"hard cover does not protect against primitive fire"
	)
	_expect(
		not Ballistics.protects_against(hard_cell, ["primitive", "plasma"]),
		"hard cover still protects against plasma"
	)
	_expect(
		Ballistics.best_penetration(["primitive", "rifle", "sniper"])
		== Ballistics.penetration_of("sniper"),
		"a unit does not bring its best penetration"
	)
	# Cover beside a spawn is read out of the generated terrain, not painted in.
	var natural_cover_seeds := 0
	for probe_seed in [84021, 1167583760, 999999, 555, 12345]:
		var probe_cells := World.generate_cells(probe_seed)
		for probe_faction in [Config.FACTION_HAD, Config.FACTION_SYND, Config.FACTION_TIME]:
			for spawn_cell in World.spawn_cells(probe_faction):
				_expect(
					int((probe_cells[spawn_cell] as Dictionary)["z"]) == 0,
					"an insertion cell is not level for seed %d" % probe_seed
				)
		if World.cover_near_spawn(probe_cells, Config.FACTION_HAD).size() > 0:
			natural_cover_seeds += 1
	_expect(
		natural_cover_seeds > 0,
		"no seed generates natural cover near the insertion point"
	)

	# The guided lane now has cover and an instructor who uses it, so the tutorial
	# teaches Take Cover as its own step rather than as alternate DEFENSE prose.
	var cover_director := Tutorial.new()
	_expect(
		cover_director.begin({"sector": "Proving Ground"}, Config.FACTION_HAD, 1),
		"the cover tutorial did not activate"
	)
	_expect(
		int(cover_director.current_snapshot()["total_steps"]) == 7,
		"the guided tutorial does not advertise seven steps"
	)
	cover_director.set_cover_available(true)
	_expect(cover_director.observe_action("select", commander), "cover run did not select")
	_expect(
		cover_director.observe_record({
			"record_type": "event",
			"event": "movement_resolved",
			"payload": {}
		}),
		"cover run did not resolve movement"
	)
	_expect(
		String(cover_director.current_snapshot()["step_key"]) == "defense",
		"cover run is not at the defense step"
	)
	_expect(cover_director.observe_action("brace", commander), "Brace did not satisfy defense")
	var cover_snapshot: Dictionary = cover_director.current_snapshot()
	_expect(
		String(cover_snapshot["step_key"]) == "cover",
		"Brace beside cover did not advance to the cover step"
	)
	_expect(
		int(cover_snapshot["display_step"]) == 4,
		"the cover step is not the fourth guided step"
	)
	_expect(
		String(cover_snapshot["title"]).contains("COVER")
		and String(cover_snapshot["body"]).contains("Take Cover"),
		"the cover step does not instruct Take Cover"
	)
	_expect(
		not cover_director.observe_action("melee", commander),
		"an attack skipped the cover instruction"
	)
	_expect(
		cover_director.observe_action("take_cover", commander),
		"Take Cover did not satisfy the cover step"
	)
	_expect(
		String(cover_director.current_snapshot()["step_key"]) == "attack",
		"the cover step did not advance to the attack step"
	)
	_expect(
		int(cover_director.current_snapshot()["display_step"]) == 5,
		"the attack step did not renumber after the cover step"
	)
	# Reaching for the stronger option first is never treated as a mistake.
	var direct_cover := Tutorial.new()
	direct_cover.begin({"sector": "Proving Ground"}, Config.FACTION_HAD, 1)
	direct_cover.set_cover_available(true)
	direct_cover.observe_action("select", commander)
	direct_cover.observe_record({
		"record_type": "event",
		"event": "movement_resolved",
		"payload": {}
	})
	_expect(
		direct_cover.observe_action("take_cover", commander),
		"Take Cover at the defense step was rejected"
	)
	_expect(
		String(direct_cover.current_snapshot()["step_key"]) == "attack",
		"taking cover first did not satisfy both defense and cover"
	)
	# Cover that disappears must not strand the player on the cover step.
	var lost_cover := Tutorial.new()
	lost_cover.begin({"sector": "Proving Ground"}, Config.FACTION_HAD, 1)
	lost_cover.set_cover_available(true)
	lost_cover.observe_action("select", commander)
	lost_cover.observe_record({
		"record_type": "event",
		"event": "movement_resolved",
		"payload": {}
	})
	lost_cover.observe_action("brace", commander)
	_expect(
		String(lost_cover.current_snapshot()["step_key"]) == "cover",
		"the lost-cover run is not at the cover step"
	)
	lost_cover.set_cover_available(false)
	_expect(
		String(lost_cover.current_snapshot()["step_key"]) == "attack",
		"losing cover stranded the player on the cover step"
	)
	# A lane without cover still runs the six-step path.
	var clear_lane := Tutorial.new()
	clear_lane.begin({"sector": "Proving Ground"}, Config.FACTION_HAD, 1)
	clear_lane.set_cover_available(false)
	clear_lane.observe_action("select", commander)
	clear_lane.observe_record({
		"record_type": "event",
		"event": "movement_resolved",
		"payload": {}
	})
	_expect(clear_lane.observe_action("brace", commander), "clear-lane Brace was rejected")
	_expect(
		String(clear_lane.current_snapshot()["step_key"]) == "attack",
		"a clear lane did not skip the cover step"
	)

	for faction in [Config.FACTION_HAD, Config.FACTION_SYND, Config.FACTION_TIME]:
		var player_cells := World.spawn_cells(faction)
		# The training lane's cover is whatever the environment generated there.
		# It is never painted in, so the assertion is that the insertion footprint
		# stays level and that cover, when present, is real terrain beside it.
		var lane_cells := World.generate_cells(999999)
		for spawn_cell in player_cells:
			_expect(
				int((lane_cells[spawn_cell] as Dictionary)["z"]) == 0,
				"an insertion cell is not level for faction %d" % faction
			)
		var natural_cover: Array = World.cover_near_spawn(lane_cells, faction)
		for cover_cell in natural_cover:
			_expect(
				lane_cells.has(cover_cell),
				"reported natural cover is outside the map for faction %d" % faction
			)
			_expect(
				not player_cells.has(cover_cell),
				"natural cover sits on a player insertion cell for faction %d" % faction
			)
			_expect(
				Ballistics.effective_cover_level(lane_cells[cover_cell]) > 0,
				"reported natural cover offers no protection for faction %d" % faction
			)
		# Haili stands beyond the melee lane but inside the observation radius.
		var instructor_cell := SquadSpawn.tutorial_instructor_cell(faction)
		_expect(
			lane_cells.has(instructor_cell),
			"the instructor post is outside the map for faction %d" % faction
		)
		_expect(
			not player_cells.has(instructor_cell),
			"the instructor post overlaps a player insertion cell for faction %d" % faction
		)
		var instructor_distance := absi(instructor_cell.x - player_cells[0].x) + absi(
			instructor_cell.y - player_cells[0].y
		)
		_expect(
			instructor_distance > 3 and instructor_distance <= 10,
			"the instructor post is not a standoff for faction %d" % faction
		)
		var dummy_cells := SquadSpawn.tutorial_dummy_cells(faction)
		_expect(dummy_cells.size() == 2, "tutorial did not provide two targets for faction %d" % faction)
		for cell in dummy_cells:
			_expect(World.generate_cells(999999).has(cell), "tutorial target is outside the map")
			_expect(not player_cells.has(cell), "tutorial target overlaps a player insertion cell")
			_expect(
				absi(cell.x - player_cells[0].x) + absi(cell.y - player_cells[0].y) <= 3,
				"tutorial target is outside the one-turn training lane"
			)
func _test_contextual_movement() -> void:
	var unit := UnitScript.new()
	unit.name = "Context Test"
	unit.team = Config.FACTION_HAD
	unit.cell = Vector2i(2, 2)
	unit.hp = Config.UNIT_HP
	unit.max_hp = Config.UNIT_HP
	unit.ap = Config.MAX_AP
	unit.max_ap = Config.MAX_AP
	unit.inv = {}
	unit.alive = true
	unit.stance = "stand"
	var cover := Vector2i(3, 2)
	var cells := {
		unit.cell: {"type": Config.FLOOR, "z": 0},
		cover: {"type": Config.COVER, "z": 3},
		Vector2i(2, 3): {"type": Config.FLOOR, "z": 0},
		Vector2i(4, 2): {"type": Config.FLOOR, "z": 0}
	}
	var path_rules = PathScript.new()
	_expect(MovementRules.cover_options(unit, cells) == [cover], "context layer did not expose adjacent cover")
	_expect(MovementRules.can_take_cover(unit, cover, cells), "context layer rejected legal adjacent cover")
	_expect(not MovementRules.can_take_cover(unit, Vector2i(2, 3), cells), "context layer accepted ordinary floor as cover")
	_expect(not MovementRules.can_lean(unit, "left"), "Lean was exposed without a cover commitment")
	_expect(not MovementRules.can_initiate_jump(unit), "standing unit initiated a momentum jump")
	_expect(MovementRules.can_initiate_jump(unit, true), "Precision Jump did not bypass the momentum prerequisite")
	unit.run_distance_this_turn = 2
	unit.sprint_distance_this_turn = 1
	_expect(MovementRules.can_initiate_jump(unit), "recorded movement distance did not create jump momentum")
	_expect(MovementRules.wall_options(unit, cells) == [cover], "momentum plus adjacent wall did not expose Wall Run")
	_expect(not path_rules.has_los(unit.cell, Vector2i(4, 2), cells, 0, 0), "solid cover did not block line of sight")
	_expect(path_rules.has_los(unit.cell, Vector2i(4, 2), cells, 0, 0, cover), "Lean-style ignored face did not open a firing line")
	_expect(path_rules.has_los(unit.cell, Vector2i(4, 2), cells, 0, 0, Config.INVALID_CELL, true), "penetration did not open a firing line through cover")
	unit.taking_cover = true
	unit.cover_cell = cover
	unit.blocking = true
	_expect(MovementRules.movement_locked(unit), "committed cover did not lock positional movement")
	_expect(MovementRules.can_lean(unit, "left") and MovementRules.can_lean(unit, "right"), "committed cover did not expose contextual Lean")
	_expect(MovementRules.cover_options(unit, cells).is_empty(), "committed unit was offered another cover entry")
	unit.cover_monkey_active = true
	_expect(not MovementRules.movement_locked(unit), "Cover Monkey did not release movement commitment")
	unit.cover_monkey_active = false
	unit.maneuver = Maneuvers.airborne(
		unit.cell, 0, unit.cell, 1, unit.cell, 0, 1,
		unit.run_distance_this_turn, unit.sprint_distance_this_turn, Config.JUMP_COST, 1
	)
	_expect(not MovementRules.action_locked(unit, "ranged"), "airborne state incorrectly blocked attacks")
	_expect(MovementRules.action_locked(unit, "move"), "airborne state allowed ordinary ground movement")
	var saved := unit.to_dict()
	var restored := UnitScript.new()
	restored.inv = {}
	restored.apply_dict(saved)
	_expect(restored.taking_cover and restored.cover_cell == cover, "cover commitment did not survive serialization")
	_expect(Maneuvers.is_airborne(restored.maneuver), "airborne maneuver did not survive serialization")
	_expect(restored.run_distance_this_turn == 2 and restored.sprint_distance_this_turn == 1, "movement momentum did not survive serialization")
	_expect(ActionCosts.fixed_cost("take_cover") == Config.TAKE_COVER_COST, "take-cover AP is not centralized")
	_expect(ActionCosts.fixed_cost("leave_cover") == Config.LEAVE_COVER_COST, "leave-cover AP is not centralized")

func _test_web_contract() -> void:
	var shell := FileAccess.get_file_as_string("res://web/index.html")
	var atlas := FileAccess.get_file_as_string("res://web/atlas/index.html")
	var launcher := FileAccess.get_file_as_string("res://web/battlestar.html")
	var bridge := FileAccess.get_file_as_string("res://web/bridge.js")
	var strat := FileAccess.get_file_as_string("res://scripts/StratLayer.gd")
	var server := FileAccess.get_file_as_string("res://tools/launch-web.ps1")
	var builder := FileAccess.get_file_as_string("res://tools/rebuild-web.ps1")
	_expect(shell.contains("id=\"deploy\" hidden"), "strategic Deploy action is visible without a target")
	_expect(shell.contains("selectedMessage"), "strategic shell does not retain contextual deployment targets")
	_expect(shell.contains("QUICK DEPLOY: PROVING GROUND"), "strategic shell lacks a standalone play path")
	_expect(atlas.contains("type === 'crisis'"), "crisis events are not marked as deployable context")
	_expect(atlas.contains("type:'coordinate'"), "map coordinates do not publish deployment context")
	_expect(atlas.contains("atlas.generated.css"), "A.T.L.A.S. static production styling is missing")
	_expect(not atlas.contains("tailwindcss.js"), "A.T.L.A.S. restored the browser Tailwind compiler")
	_expect(atlas.contains("vendor/three.r128.min.js"), "A.T.L.A.S. globe runtime is not bundled locally")
	_expect(atlas.contains("vendor/textures/earth-blue-marble.jpg"), "A.T.L.A.S. globe texture is not bundled locally")
	_expect(not atlas.contains("cdn.tailwindcss.com"), "A.T.L.A.S. still references the blocked Tailwind CDN")
	_expect(not atlas.contains("cdnjs.cloudflare.com/ajax/libs/three.js"), "A.T.L.A.S. still references the blocked Three.js CDN")
	_expect(FileAccess.file_exists("res://web/atlas/vendor/fonts/material-icons-outlined.otf"), "local A.T.L.A.S. icon font is missing")
	_expect(launcher.contains("function returnToStrategy()"), "extraction launcher does not return to the strategic map")
	_expect(launcher.contains("deploy.atlas_state"), "extraction return does not preserve the A.T.L.A.S. snapshot")
	_expect(launcher.contains("window.opener.focus()"), "popup extraction does not restore focus to its strategic opener")
	_expect(launcher.contains("location.replace(strategyUrl())"), "same-tab extraction lacks a strategic fallback")
	_expect(launcher.contains("allow=\"fullscreen; autoplay\""), "embedded tactical runtime is not permitted to enter fullscreen")
	_expect(shell.contains("atlas.src = `atlas/index.html${location.hash}`"), "same-tab strategy return does not restore the A.T.L.A.S. hash")
	_expect(shell.contains("location.assign(url)"), "core tactical launch still depends on popup permission")
	_expect(launcher.contains("tactical/index.html?p="), "launcher does not mount the real Godot tactical runtime")
	_expect(not launcher.contains("DEMO SIM"), "launcher still substitutes a browser demo for the game")
	_expect(bridge.contains("gzg.battlestar.deploy/1.0"), "standardized deployment message is missing")
	_expect(bridge.contains("gzg.xcommand.extraction/1.0"), "standardized extraction message is missing")
	_expect(bridge.contains("applied_extractions.includes"), "strategic persistence is not idempotent")
	_expect(bridge.contains("compactExtractionMessage"), "long extraction recovery has no bounded storage path")
	_expect(launcher.contains("applyExtraction(bridge.loadProfile()"), "same-tab extraction is not applied before recovery storage")
	_expect(strat.contains("tools/launch-web.ps1"), "native A.T.L.A.S. launch does not start the bundled HTTP server")
	_expect(not strat.contains("OS.shell_open(\"file:///\""), "native A.T.L.A.S. launch still opens the broken direct-file route")
	_expect(server.contains("X-BattleStar-Dev-Server"), "local Web server cannot identify and reuse an existing instance")
	_expect(server.contains("'font/otf'"), "local Web server does not serve the bundled icon font with an explicit MIME type")
	_expect(builder.contains("--export-release Web"), "one-click Web development does not build a release Godot package")
	_expect(builder.contains("Godot_v4.7.1-stable_win64_console.exe"), "Web rebuild does not discover the supplied console executable")

func _test_main_scene() -> void:
	var packed := load("res://Main.tscn") as PackedScene
	_expect(packed != null, "Main.tscn did not load")
	if packed == null:
		return

	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	_expect(main.has_method("_spawn_squads"), "Main.gd did not load")
	if not main.has_method("_spawn_squads"):
		main.free()
		return
	_expect(main.cells.size() == Config.GRID_W * Config.GRID_H, "tactical scene did not build the full grid")
	_expect(main.tiles_root.get_child_count() == Config.GRID_W * Config.GRID_H, "visual voxel count disagrees with the logical grid")
	for probe_cell in [Vector2i(0, 0), Vector2i(10, 10), Vector2i(Config.GRID_W - 1, Config.GRID_H - 1)]:
		var tile := main.tiles_root.get_node_or_null("Tile_%d_%d" % [probe_cell.x, probe_cell.y]) as MeshInstance3D
		_expect(tile != null, "named visual voxel is missing at %s" % probe_cell)
		if tile != null:
			var expected := Config.cell_to_world(probe_cell)
			_expect(
				is_equal_approx(tile.position.x, expected.x) and is_equal_approx(tile.position.z, expected.z),
				"visual voxel is offset from its logical cell at %s" % probe_cell
			)
		_expect(
			main._world_to_cell(main._cell_to_world(probe_cell)) == probe_cell,
			"cell/world transform did not round-trip at %s" % probe_cell
		)
	var highlight_probe := Vector2i(10, 10)
	main._highlight_tile(highlight_probe, Color.WHITE)
	var probe_highlight := main.highlight_root.get_child(main.highlight_root.get_child_count() - 1) as MeshInstance3D
	var probe_tile := main.tiles_root.get_node("Tile_%d_%d" % [highlight_probe.x, highlight_probe.y]) as MeshInstance3D
	_expect(
		is_equal_approx(probe_highlight.position.x, probe_tile.position.x)
		and is_equal_approx(probe_highlight.position.z, probe_tile.position.z),
		"target highlight is not centered on its visual voxel"
	)
	main._clear_highlights()
	_expect(main.units.size() == 9, "standard tactical scene did not spawn three complete three-unit teams")
	_expect(main.selected != null, "tactical scene did not select a player unit")
	var team_counts := {Config.FACTION_HAD: 0, Config.FACTION_SYND: 0, Config.FACTION_TIME: 0}
	var occupied := {}
	for unit in main.units:
		team_counts[unit.team] = int(team_counts.get(unit.team, 0)) + 1
		_expect(not occupied.has(unit.cell), "two units spawned in the same map column")
		occupied[unit.cell] = true
		_expect(unit.z == int(main.cells.get(unit.cell, {}).get("z", -1)), "unit internal height disagrees with its tile")
	for team in team_counts:
		_expect(int(team_counts[team]) == 3, "one faction did not receive three units")
	_expect(main.debris.size() >= 17, "loot scatter did not place the expected item groups")
	for cell in main.debris:
		_expect(int(main.cells.get(cell, {}).get("z", 99)) <= Config.MAX_WALK_STEP, "loot was scattered onto an inaccessible tower")
	for holder in main.debris_nodes.values():
		for child in holder.get_children():
			_expect(not (child is Label3D), "deprecated floating LOOT label is still active")
	_expect(main.tactical_ui.action_btns.has("flight_up"), "visible flight layer-up control is missing")
	_expect(main.tactical_ui.action_btns.has("flight_down"), "visible flight layer-down control is missing")
	_expect(main.tactical_ui.action_btns.has("flight_land"), "visible flight landing control is missing")
	_expect(main.tactical_ui.action_btns.has("take_cover"), "contextual take-cover control is missing")
	_expect(main.tactical_ui.action_btns["grab"].text.contains("Grab Loot"), "explicit pickup button is not clearly labeled")
	_expect(InputMap.has_action("emergency_evac"), "engine-level emergency extraction shortcut is missing")
	var evac_events := InputMap.action_get_events("emergency_evac")
	_expect(
		evac_events.any(func(event): return event is InputEventKey and event.keycode == KEY_F8),
		"emergency extraction is not bound to F8"
	)
	_expect(main.tactical_ui.get_node_or_null("ViewModeBox/btn_full") != null, "tactical fullscreen control is missing")
	_expect(main.tactical_ui.get_node_or_null("ViewModeBox/btn_help") != null, "tactical help control is missing")
	_expect(main.tactical_ui.get_node_or_null("EventPanel") != null, "ephemeral tactical feed is not separated from persistent squad status")
	_expect(main.tactical_ui.get_node_or_null("ActionDock") != null, "responsive bottom action dock is missing")
	var status_panel := main.tactical_ui.get_node_or_null("StatusPanel") as Control
	var tutorial_panel := main.tactical_ui.get_node_or_null("TutorialPanel") as Control
	var event_panel := main.tactical_ui.get_node_or_null("EventPanel") as Control
	var action_dock := main.tactical_ui.get_node_or_null("ActionDock") as Control
	_expect(status_panel != null, "persistent tactical status rail is not addressable")
	if status_panel != null and tutorial_panel != null:
		var status_clearance := status_panel.position.x + status_panel.size.x + 14.0
		_expect(
			tutorial_panel.position.x >= status_clearance,
			"tutorial panel overlaps the persistent tactical status rail"
		)
	if event_panel != null and action_dock != null:
		var event_clearance := event_panel.position.x + event_panel.size.x + 14.0
		_expect(
			action_dock.position.x >= event_clearance,
			"action dock overlaps the lower tactical-feed rail"
		)
	var compact_layout: Dictionary = main.tactical_ui.layout_metrics_for_width(768.0)
	_expect(
		is_equal_approx(float(compact_layout.get("tutorial_left", 0.0)), 244.0),
		"compact tutorial layout does not preserve status-rail clearance"
	)
	_expect(
		is_equal_approx(float(compact_layout.get("action_dock_left", 0.0)), 244.0),
		"compact action-dock layout does not preserve tactical-feed clearance"
	)
	var evidence_view_layout: Dictionary = main.tactical_ui.layout_metrics_for_width(1112.0)
	_expect(
		float(evidence_view_layout.get("tutorial_left", 0.0))
		>= float(evidence_view_layout.get("tutorial_clearance", 0.0)),
		"1112-wide evidence viewport lets the tutorial enter the status rail"
	)
	_expect(
		float(evidence_view_layout.get("action_dock_left", 0.0))
		>= float(evidence_view_layout.get("action_dock_clearance", 0.0)),
		"1112-wide evidence viewport lets the action dock enter the tactical-feed rail"
	)
	var expanded_rail_layout: Dictionary = main.tactical_ui.layout_metrics_for_width(
		768.0,
		330.0,
		260.0
	)
	_expect(
		is_equal_approx(float(expanded_rail_layout.get("tutorial_left", 0.0)), 344.0),
		"tutorial layout ignores a status rail expanded by its content"
	)
	_expect(
		is_equal_approx(float(expanded_rail_layout.get("action_dock_left", 0.0)), 274.0),
		"action-dock layout ignores an expanded tactical-feed rail"
	)
	# M05-B: the supported viewport matrix. Width decides rail clearance and
	# height decides tutorial/action-dock/tactical-feed clearance.
	for supported_viewport in main.tactical_ui.SUPPORTED_VIEWPORTS:
		var matrix_layout: Dictionary = main.tactical_ui.layout_metrics_for_viewport(
			float(supported_viewport.x),
			float(supported_viewport.y)
		)
		var viewport_label := "%dx%d" % [supported_viewport.x, supported_viewport.y]
		_expect(
			float(matrix_layout.get("tutorial_left", 0.0))
			>= float(matrix_layout.get("tutorial_clearance", 0.0)),
			"%s lets the tutorial enter the status rail" % viewport_label
		)
		_expect(
			float(matrix_layout.get("action_dock_left", 0.0))
			>= float(matrix_layout.get("action_dock_clearance", 0.0)),
			"%s lets the action dock enter the tactical-feed rail" % viewport_label
		)
		_expect(
			bool(matrix_layout.get("tutorial_dock_clear", false)),
			"%s lets the action dock reach the tutorial callout" % viewport_label
		)
		_expect(
			bool(matrix_layout.get("event_rail_visible", false)),
			"%s leaves no usable tactical-feed rail" % viewport_label
		)
		_expect(
			not bool(matrix_layout.get("constrained", true)),
			"%s is reported as a constrained layout" % viewport_label
		)
	# A cramped-but-disjoint tactical feed must stay reported rather than pass
	# silently: the shortest supported canvas leaves very little feed history.
	var shortest_supported: Vector2i = main.tactical_ui.SUPPORTED_VIEWPORTS[
		main.tactical_ui.SUPPORTED_VIEWPORTS.size() - 1
	]
	var shortest_layout: Dictionary = main.tactical_ui.layout_metrics_for_viewport(
		float(shortest_supported.x),
		float(shortest_supported.y)
	)
	_expect(
		shortest_layout.has("event_rail_cramped"),
		"the layout no longer reports tactical-feed crowding"
	)
	_expect(
		float(shortest_layout.get("event_rail_height", 0.0)) > 0.0,
		"the shortest supported canvas leaves no tactical-feed rail"
	)
	_expect(
		bool(shortest_layout.get("event_rail_cramped", false)),
		"the shortest supported canvas no longer reports a cramped tactical feed"
	)
	# Canvases the HUD cannot serve must be detected, never silently overlapped.
	for short_canvas in main.tactical_ui.HudLayout.UNSUPPORTED_SHORT_CANVASES:
		var short_layout: Dictionary = main.tactical_ui.layout_metrics_for_viewport(
			float(short_canvas.x),
			float(short_canvas.y)
		)
		_expect(
			bool(short_layout.get("constrained", false)),
			"%dx%d is not reported as a constrained canvas" % [short_canvas.x, short_canvas.y]
		)
	# A wrapped multi-row dock must push the bottom-anchored feed rail up rather
	# than keeping the historical single-row -112 assumption.
	var wrapped_dock_layout: Dictionary = main.tactical_ui.layout_metrics_for_viewport(
		1366.0,
		768.0,
		main.tactical_ui.STATUS_RAIL_RIGHT,
		main.tactical_ui.STATUS_RAIL_RIGHT,
		main.tactical_ui.TUTORIAL_HEIGHT,
		212.0
	)
	_expect(
		is_equal_approx(float(wrapped_dock_layout.get("action_dock_top", 0.0)), 544.0),
		"wrapped action dock does not grow upward from the bottom margin"
	)
	_expect(
		is_equal_approx(float(wrapped_dock_layout.get("event_rail_bottom_offset", 0.0)), -238.0),
		"wrapped action dock does not push the tactical-feed rail clear"
	)
	_expect(
		float(wrapped_dock_layout.get("event_rail_bottom_offset", 0.0)) < -112.0,
		"wrapped action dock keeps the historical single-row feed-rail offset"
	)
	_expect(
		not bool(wrapped_dock_layout.get("constrained", true)),
		"a wrapped dock at 1366x768 is misreported as constrained"
	)
	# Known open case: the 1112x626 embedded tactical canvas with a wrapped dock
	# leaves no usable tactical-feed rail. The remedy is a dock-compaction pass;
	# until then the condition must be detected rather than silently overlapped.
	var embedded_wrapped_layout: Dictionary = main.tactical_ui.layout_metrics_for_viewport(
		1112.0,
		626.0,
		main.tactical_ui.STATUS_RAIL_RIGHT,
		main.tactical_ui.STATUS_RAIL_RIGHT,
		main.tactical_ui.TUTORIAL_HEIGHT,
		212.0
	)
	_expect(
		bool(embedded_wrapped_layout.get("tutorial_dock_clear", false)),
		"the embedded wrapped dock reaches the tutorial callout"
	)
	_expect(
		not bool(embedded_wrapped_layout.get("event_rail_visible", true)),
		"the embedded wrapped-dock feed-rail regression is no longer detected"
	)
	_expect(
		bool(embedded_wrapped_layout.get("constrained", false)),
		"the embedded wrapped dock is not reported as a constrained layout"
	)
	# A viewport too short for both surfaces must be reported, not silently
	# overlapped.
	var constrained_layout: Dictionary = main.tactical_ui.layout_metrics_for_viewport(
		1024.0,
		360.0,
		main.tactical_ui.STATUS_RAIL_RIGHT,
		main.tactical_ui.STATUS_RAIL_RIGHT,
		main.tactical_ui.TUTORIAL_HEIGHT,
		320.0
	)
	_expect(
		bool(constrained_layout.get("constrained", false)),
		"an unusably short viewport is not reported as constrained"
	)
	_expect(
		not bool(constrained_layout.get("tutorial_dock_clear", true)),
		"an unusably short viewport claims tutorial/dock clearance"
	)
	# The live pass must publish the same metrics it applied.
	var applied_layout: Dictionary = main.tactical_ui.last_layout_metrics
	_expect(
		not applied_layout.is_empty(),
		"the responsive layout pass did not record its metrics"
	)
	if event_panel != null and not applied_layout.is_empty():
		if bool(applied_layout.get("event_rail_visible", false)):
			_expect(
				is_equal_approx(
					event_panel.offset_bottom,
					float(applied_layout.get("event_rail_bottom_offset", 0.0))
				),
				"the tactical-feed rail offset does not match the applied layout metric"
			)
	# M05-C: adaptive HUD surfaces — transparency, slide, scroll, adaptation.
	var surface_keys: Array = main.tactical_ui.surface_keys()
	_expect(surface_keys.size() == 4, "the HUD does not expose four adaptive surfaces")
	for surface_key in surface_keys:
		var surface: Dictionary = main.tactical_ui.surface_state(String(surface_key))
		_expect(
			surface.get("node") != null,
			"adaptive surface %s has no control" % String(surface_key)
		)
		# Transparency is continuous and never fully invisible, so a surface can
		# always be found again.
		var faded: float = main.tactical_ui.set_surface_opacity(String(surface_key), 0.0)
		_expect(
			is_equal_approx(faded, main.tactical_ui.HudLayout.OPACITY_MIN),
			"adaptive surface %s can be made fully invisible" % String(surface_key)
		)
		var node := main.tactical_ui.surface_state(String(surface_key))["node"] as Control
		_expect(
			is_equal_approx(node.modulate.a, main.tactical_ui.HudLayout.OPACITY_MIN),
			"adaptive surface %s did not apply its opacity" % String(surface_key)
		)
		var restored: float = main.tactical_ui.set_surface_opacity(String(surface_key), 1.0)
		_expect(
			is_equal_approx(restored, main.tactical_ui.HudLayout.OPACITY_MAX),
			"adaptive surface %s cannot return to full opacity" % String(surface_key)
		)
	# Pointer affordance: every surface has a visible slide grip and an opacity
	# grip, and the slide grip stays reachable when the surface is parked.
	_expect(
		main.tactical_ui.get_node_or_null("HudGrips") != null,
		"the adaptive HUD has no pointer affordance"
	)
	for grip_key in surface_keys:
		var grip_surface: Dictionary = main.tactical_ui.surface_state(String(grip_key))
		var slide_grip := grip_surface.get("slide_grip") as Button
		var fade_grip := grip_surface.get("fade_grip") as Button
		_expect(slide_grip != null, "surface %s has no slide grip" % String(grip_key))
		_expect(fade_grip != null, "surface %s has no opacity grip" % String(grip_key))
		if slide_grip == null or fade_grip == null:
			continue
		_expect(
			not String(slide_grip.tooltip_text).is_empty()
			and not String(fade_grip.tooltip_text).is_empty(),
			"surface %s grips carry no tooltip" % String(grip_key)
		)
		# The grips are pointer affordances; the keyboard path is F2/F3/F4, so they
		# must not lengthen the action traversal order.
		_expect(
			slide_grip.focus_mode == Control.FOCUS_NONE
			and fade_grip.focus_mode == Control.FOCUS_NONE,
			"surface %s grips joined the keyboard action order" % String(grip_key)
		)
		var grip_parked_before: bool = main.tactical_ui.is_surface_parked(String(grip_key))
		slide_grip.pressed.emit()
		_expect(
			main.tactical_ui.is_surface_parked(String(grip_key)) != grip_parked_before
			or String(grip_key) == "status" or String(grip_key) == "feed",
			"the slide grip for %s did not change its state" % String(grip_key)
		)
		slide_grip.pressed.emit()
		var grip_opacity_before: float = float(
			main.tactical_ui.surface_state(String(grip_key))["opacity"]
		)
		fade_grip.pressed.emit()
		_expect(
			not is_equal_approx(
				float(main.tactical_ui.surface_state(String(grip_key))["opacity"]),
				grip_opacity_before
			),
			"the opacity grip for %s did nothing" % String(grip_key)
		)
		main.tactical_ui.set_surface_opacity(String(grip_key), 1.0)
	# A parked surface keeps its slide grip on screen, inside the handle.
	main.tactical_ui.set_surface_parked("tutorial", true)
	var parked_grip := main.tactical_ui.surface_state("tutorial")["slide_grip"] as Button
	_expect(
		parked_grip.position.y >= 0.0,
		"a parked surface's slide grip left the screen"
	)
	main.tactical_ui.set_surface_parked("tutorial", false)
	# The opacity cycle wraps, so repeated presses always come back to full.
	var cycle_value := 1.0
	var cycle_returned := false
	for _cycle_step in range(main.tactical_ui.HudLayout.OPACITY_STEPS.size()):
		cycle_value = main.tactical_ui.HudLayout.next_opacity(cycle_value)
		if is_equal_approx(cycle_value, main.tactical_ui.HudLayout.OPACITY_MAX):
			cycle_returned = true
	_expect(cycle_returned, "the opacity cycle never returns to full")
	# Sliding a surface away leaves a handle and is reversible.
	# The tutorial callout is never auto-parked, so a manual slide there is always
	# honoured. Sliding a surface that adaptation is currently forcing open or shut
	# is correctly overridden on the next layout pass, which is why this uses the
	# one surface adaptation never touches.
	var slide_key := "tutorial"
	var slide_node := main.tactical_ui.surface_state(slide_key)["node"] as Control
	var started_parked: bool = main.tactical_ui.is_surface_parked(slide_key)
	# The tutorial parks upward, so its slide axis is vertical.
	var start_left: float = slide_node.offset_top
	_expect(
		main.tactical_ui.toggle_surface_parked(slide_key) == not started_parked,
		"the surface slide toggle did not invert its state"
	)
	_expect(
		main.tactical_ui.is_surface_parked(slide_key) == not started_parked,
		"the slid surface does not report its new state"
	)
	var toggled_left: float = slide_node.offset_top
	_expect(
		not is_equal_approx(toggled_left, start_left),
		"the slid surface did not move off or back onto its edge"
	)
	_expect(
		(toggled_left < start_left) == (not started_parked),
		"the surface slid the wrong way"
	)
	_expect(
		main.tactical_ui.toggle_surface_parked(slide_key) == started_parked,
		"the surface slide toggle is not reversible"
	)
	_expect(
		is_equal_approx(slide_node.offset_top, start_left),
		"the restored surface did not return to its previous position"
	)
	# Scrolling: content taller than a surface scrolls rather than spilling.
	_expect(
		main.tactical_ui.get_node_or_null("StatusPanel/StatusScroll") != null,
		"the status rail does not scroll its content"
	)
	_expect(
		main.tactical_ui.get_node_or_null("ActionDock/ActionDockScroll") != null,
		"the action dock does not scroll its content"
	)
	# Adaptation: a canvas that cannot host the open layout parks the feed rather
	# than reporting a broken layout, and never parks the actions or instructions.
	for short_canvas in main.tactical_ui.HudLayout.UNSUPPORTED_SHORT_CANVASES:
		var adaptive: Dictionary = main.tactical_ui.HudLayout.adaptive_metrics(
			float(short_canvas.x),
			float(short_canvas.y)
		)
		var canvas_label := "%dx%d" % [short_canvas.x, short_canvas.y]
		_expect(
			not bool(adaptive.get("constrained", true)),
			"%s is not resolved by adaptation" % canvas_label
		)
		var parked_list: Array = adaptive.get("auto_parked", [])
		_expect(
			parked_list.has("feed"),
			"%s did not park the tactical feed to fit" % canvas_label
		)
		_expect(
			not parked_list.has("dock") and not parked_list.has("tutorial"),
			"%s auto-parked the actions or the instructions" % canvas_label
		)
	# A supported canvas needs no adaptation at all.
	for supported_canvas in main.tactical_ui.SUPPORTED_VIEWPORTS:
		var open_metrics: Dictionary = main.tactical_ui.HudLayout.adaptive_metrics(
			float(supported_canvas.x),
			float(supported_canvas.y)
		)
		_expect(
			(open_metrics.get("auto_parked", []) as Array).is_empty(),
			"%dx%d parked a surface it did not need to" % [supported_canvas.x, supported_canvas.y]
		)
	# Player intent survives adaptation: a surface the player slid away stays away.
	var intent_metrics: Dictionary = main.tactical_ui.HudLayout.adaptive_metrics(
		1172.0,
		659.0,
		{"status": {"slide": main.tactical_ui.HudLayout.Slide.PARKED}}
	)
	var intent_surfaces: Dictionary = intent_metrics.get("surfaces", {})
	_expect(
		int((intent_surfaces.get("status", {}) as Dictionary).get("slide", -1))
		== main.tactical_ui.HudLayout.Slide.PARKED,
		"adaptation discarded the player's slid surface"
	)
	# M05-B: reduced motion. Camera transitions are presentation only, so a
	# reduced-motion host must land on the destination immediately.
	var camera = main.camera_controller
	_expect(camera != null, "tactical camera controller is not addressable")
	if camera != null:
		_expect(
			is_equal_approx(float(camera.motion_scale), 1.0),
			"authored camera motion is not the default"
		)
		_expect(not bool(camera.is_reduced_motion()), "default state claims reduced motion")
		var authored_focus := Vector3(4.0, 0.0, 6.0)
		camera.focus_position(authored_focus)
		_expect(
			not camera.global_position.is_equal_approx(authored_focus),
			"authored camera motion skipped its focus transition"
		)
		camera.set_motion_scale(0.0)
		_expect(bool(camera.is_reduced_motion()), "reduced motion did not engage")
		var reduced_focus := Vector3(-3.0, 0.0, 9.0)
		camera.focus_position(reduced_focus)
		_expect(
			camera.global_position.is_equal_approx(reduced_focus),
			"reduced motion did not apply the camera focus immediately"
		)
		_expect(
			camera.desired_pivot_pos.is_equal_approx(reduced_focus),
			"reduced-motion focus did not record the pivot target"
		)
		camera.set_mode(camera.Mode.OTS)
		_expect(
			is_equal_approx(float(camera.distance), 4.0),
			"reduced motion did not apply the camera mode distance immediately"
		)
		camera.set_mode(camera.Mode.BEV)
		_expect(
			is_equal_approx(float(camera.distance), 30.0),
			"reduced motion did not restore the tactical camera distance"
		)
		camera.set_motion_scale(1.0)
		camera.global_position = authored_focus
		camera.desired_pivot_pos = authored_focus
	# M05-B: keyboard traversal must reach every core tactical control and must
	# be repeatable, without stranding the non-core actions.
	var traversal: Array = main.tactical_ui.keyboard_traversal_keys()
	_expect(traversal.size() > 1, "keyboard traversal visits no controls")
	_expect(
		main.tactical_ui.keyboard_entry_control(true) != null
		and String(traversal[0]) == main.tactical_ui._focus_key_for(
			main.tactical_ui.keyboard_entry_control(true)
		),
		"keyboard traversal does not start at the keyboard entry control"
	)
	# Every action the current HUD state actually offers must be reachable.
	# Disabled and hidden controls are excluded because traversal skips them.
	var reachable_keys: Array = main.tactical_ui.keyboard_reachable_action_keys()
	_expect(reachable_keys.size() >= 8, "the HUD offers too few enabled keyboard targets to judge")
	for required_key in reachable_keys:
		_expect(
			traversal.has(String(required_key)),
			"keyboard traversal strands the enabled %s control" % String(required_key)
		)
	var enabled_core := 0
	for core_key in main.tactical_ui.FOCUS_ORDER_KEYS:
		if reachable_keys.has(String(core_key)):
			enabled_core += 1
			_expect(
				traversal.has(String(core_key)),
				"keyboard traversal never reaches the enabled core control %s" % String(core_key)
			)
	_expect(enabled_core >= 2, "fewer than two core tactical controls are keyboard-reachable")
	var repeat_traversal: Array = main.tactical_ui.keyboard_traversal_keys()
	_expect(
		repeat_traversal == traversal,
		"keyboard traversal is not repeatable for the same HUD state"
	)
	# Tab belongs to focus traversal. Any gameplay action that claims it makes
	# the tactical controls unreachable without a mouse.
	for reserved_action in InputMap.get_actions():
		var action_name := String(reserved_action)
		if action_name.begins_with("ui_"):
			continue
		for reserved_event in InputMap.action_get_events(action_name):
			if reserved_event is InputEventKey:
				_expect(
					reserved_event.keycode != KEY_TAB,
					"gameplay action %s claims Tab from keyboard focus traversal" % action_name
				)
	_expect(
		InputMap.has_action("toggle_legend")
		and InputMap.action_get_events("toggle_legend").size() > 0,
		"the tactical help overlay lost its keyboard binding"
	)
	# Live keyboard traversal must be observable, not inferred.
	_expect(
		String(main.tactical_ui.focused_control_key).is_empty(),
		"a core control claims keyboard focus before any traversal"
	)
	var traversal_button := main.tactical_ui.action_btns["toggle_run"] as Button
	traversal_button.focus_entered.emit()
	_expect(
		String(main.tactical_ui.focused_control_key) == "toggle_run",
		"focusing a core control does not record the observable focus key"
	)
	# Keyboard-only entry: the first Tab must adopt the declared order because
	# Godot advances focus only from a control that already holds it.
	_expect(
		main.tactical_ui.enter_keyboard_focus(true),
		"forward keyboard entry found no focusable core control"
	)
	_expect(
		main.tactical_ui.action_btns[main.tactical_ui.FOCUS_ORDER_KEYS[0]].has_focus(),
		"forward keyboard entry does not start at the first control in the declared order"
	)
	_expect(
		main.tactical_ui.enter_keyboard_focus(false),
		"reverse keyboard entry found no focusable core control"
	)
	var last_focus_key: String = main.tactical_ui.FOCUS_ORDER_KEYS[
		main.tactical_ui.FOCUS_ORDER_KEYS.size() - 1
	]
	_expect(
		main.tactical_ui.action_btns[last_focus_key].has_focus(),
		"reverse keyboard entry does not start at the last control in the declared order"
	)
	# M05-B: contrast of the core tactical text against its own panel.
	for contrast_case in main.tactical_ui.contrast_report():
		_expect(
			bool(contrast_case.get("passes", false)),
			"%s contrast is %.2f:1, below the %.1f:1 minimum" % [
				String(contrast_case.get("label", "?")),
				float(contrast_case.get("ratio", 0.0)),
				float(contrast_case.get("minimum", 4.5))
			]
		)
	_expect(main.tactical_ui.enemy_label.get_parent() == main.tactical_ui.roster_box, "hostile count is not mounted in the persistent roster")
	_expect(main.tactical_ui.turn_label.text.contains(Config.faction_name(main.player_faction)), "turn banner omits the active faction vocabulary")
	_expect(main.tactical_ui.pilot_label.text.contains("ACTIVE PILOT:"), "active-pilot status is missing")
	_expect(main.tactical_ui.pilot_label.text.contains("[CMDR]"), "initial Commander pilot is not identified")
	_expect(main.tactical_ui.pilot_label.text.contains("AP 10/10"), "active-pilot AP is not visible")
	_expect(main.tactical_ui.phase_help_label.text.contains("END TURN"), "phase status omits End Turn consequence")
	_expect(main.tactical_ui.phase_help_label.text.contains("EXTRACT/F8"), "phase status omits emergency extraction")
	_expect(main.tactical_ui.core_costs_label.text.contains("Move %d/step" % Config.MOVE_COST), "persistent core-cost line is missing")
	_expect(main.tactical_ui.action_btns["endturn"].text.contains("SPACE"), "End Turn button omits its shortcut")
	_expect(main.tactical_ui.action_btns["evac"].text.contains("F8"), "Extract button omits its shortcut")
	for focus_key in ["brace", "toggle_run", "endturn", "evac"]:
		var focus_button := main.tactical_ui.action_btns[focus_key] as Button
		_expect(focus_button.focus_mode == Control.FOCUS_ALL, "%s is missing keyboard focus" % focus_key)
		_expect(
			focus_button.has_theme_stylebox_override("focus"),
			"%s is missing a visible keyboard-focus outline" % focus_key
		)
	_expect(not main.tactical_ui.is_help_visible(), "tactical help should start closed")
	main.tactical_ui.set_help_visible(true)
	_expect(main.tactical_ui.is_help_visible(), "tactical help did not open")
	main.tactical_ui.set_help_visible(false)
	_expect(not main.tactical_ui.is_help_visible(), "tactical help did not close")
	_expect(not main.tactical_ui.action_groups["special"]["group"].visible, "developer mobility leaked into the core action dock")
	var ordinary_action_keys := [
		"endturn", "evac", "brace", "crouch", "prone", "toggle_orient",
		"take_cover", "jump", "toggle_run", "dodge", "grab", "assemble"
	]
	var initial_action_state := {}
	for action_key in ordinary_action_keys:
		if main.tactical_ui.action_btns.has(action_key):
			initial_action_state[action_key] = main.tactical_ui.action_btns[action_key].disabled
	_expect(not bool(initial_action_state.get("endturn", true)), "initial End Turn control is disabled")
	_expect(not bool(initial_action_state.get("toggle_run", true)), "initial Run/Sprint control is disabled")
	main.busy = true
	main._update_ui()
	_expect(main.tactical_ui.action_btns["endturn"].disabled, "busy state did not lock the action bar")
	main.busy = false
	await process_frame
	var post_busy_action_state := {}
	for action_key in ordinary_action_keys:
		if main.tactical_ui.action_btns.has(action_key):
			post_busy_action_state[action_key] = main.tactical_ui.action_btns[action_key].disabled
	_expect(
		post_busy_action_state == initial_action_state,
		"busy-to-ready transition did not restore the initial action-bar state"
	)
	main.dev_god_mode = true
	main.tactical_ui.update_ui()
	main.dev_god_mode = false
	main.tactical_ui.update_ui()
	var post_toggle_action_state := {}
	for action_key in ordinary_action_keys:
		if main.tactical_ui.action_btns.has(action_key):
			post_toggle_action_state[action_key] = main.tactical_ui.action_btns[action_key].disabled
	_expect(
		post_toggle_action_state == initial_action_state,
		"God Mode off-on-off changed ordinary action availability"
	)
	var router = root.get_node_or_null("ActionRouter")
	var game_state = root.get_node_or_null("GameState")
	_expect(router != null and router.game == main, "tactical scene did not bind the action router")

	if main.selected != null and router != null and game_state != null:
		var prior_mode: String = main.selected.move_mode
		var prior_action_records: int = game_state.action_records.size()
		_expect(router.request_action(main.selected, "toggle_run"), "action router rejected a legal stance action")
		_expect(main.selected.move_mode != prior_mode, "routed action did not change tactical state")
		_expect(game_state.action_records.size() == prior_action_records + 1, "action router did not append a deterministic action record")
		var routed_record: Dictionary = game_state.action_records.back()
		_expect(routed_record.get("action", "") == "toggle_run" and routed_record.get("accepted", false), "action record did not preserve the accepted intent")
		_expect(not JSON.stringify(game_state.replay_bundle()).is_empty(), "replay bundle is not JSON serializable")
		main.selected.run_distance_this_turn = 1
		_expect(main.begin_targeting("jump"), "jump button could not enter target mode")
		_expect(main.pending_target_action == "jump", "jump target mode was not retained")
		main.cancel_targeting()
		_expect(main.begin_targeting("flight"), "flight button could not enter air-cube target mode")
		var flight_unit = main.selected
		var initial_flight_level: int = main.pending_target_z
		_expect(main.adjust_flight_layer(1), "visible flight layer control could not change altitude")
		var flight_level: int = main.pending_target_z
		_expect(flight_level == initial_flight_level + 1, "flight targeting layer did not increase")
		_expect(
			router.request_action(flight_unit, "fly_to", flight_unit.cell, false, flight_level),
			"air-cube movement was rejected"
		)
		await create_timer(0.5).timeout
		_expect(flight_unit.z == flight_level and flight_unit.flying, "flight movement did not update unit altitude")
		var terrain_z := int(main.cells[flight_unit.cell].get("z", 0))
		_expect(
			router.request_action(flight_unit, "fly_to", flight_unit.cell, false, terrain_z),
			"flight landing target was rejected"
		)
		await create_timer(0.5).timeout
		_expect(flight_unit.z == terrain_z and not flight_unit.flying, "landing did not return the unit to terrain")
		flight_unit.ap = Config.MAX_AP
		flight_unit.run_distance_this_turn = 1
		var jump_target: Vector2i = flight_unit.cell + Vector2i(2, 0)
		var prior_facing: float = flight_unit.node.rotation.y
		_expect(main.begin_targeting("jump"), "jump could not be armed after landing")
		_expect(
			router.request_action(flight_unit, "jump", jump_target),
			"legal two-tile jump was rejected"
		)
		await create_timer(0.5).timeout
		_expect(flight_unit.cell == jump_target, "jump did not reach its selected air column")
		_expect(Maneuvers.is_airborne(flight_unit.maneuver), "first jump did not retain an airborne maneuver phase")
		_expect(flight_unit.z == int(main.cells[jump_target].get("z", 0)) + 1, "jump anchor was not above its planned landing")
		_expect(absf(angle_difference(prior_facing, flight_unit.node.rotation.y)) > 0.5, "unit did not turn to face its movement direction")
		_expect(not MovementRules.action_locked(flight_unit, "ranged"), "airborne jump state blocked attacks")
		_expect(main.begin_targeting("jump"), "airborne unit could not arm its paid completion jump")
		_expect(
			router.request_action(flight_unit, "jump", jump_target),
			"airborne unit could not complete its jump"
		)
		await create_timer(0.5).timeout
		_expect(not Maneuvers.is_committed(flight_unit.maneuver), "completed jump remained committed")
		_expect(flight_unit.z == int(main.cells[jump_target].get("z", 0)), "completed jump did not land on terrain")
		var cover_origin := Config.INVALID_CELL
		var cover_target := Config.INVALID_CELL
		var wall_jump_target := Config.INVALID_CELL
		var probe := UnitScript.new()
		probe.alive = true
		probe.stance = "stand"
		probe.run_distance_this_turn = 1
		for candidate in main.cells:
			if int(main.cells[candidate].get("type", Config.FLOOR)) != Config.FLOOR:
				continue
			if main._unit_at(candidate) != null:
				continue
			probe.cell = Vector2i(candidate)
			probe.z = int(main.cells[candidate].get("z", 0))
			var options := MovementRules.wall_options(probe, main.cells)
			for option in options:
				var outward := probe.cell + (probe.cell - option)
				if (
					main.cells.has(outward)
					and int(main.cells[outward].get("type", Config.FLOOR)) == Config.FLOOR
					and main._unit_at(outward) == null
				):
					cover_origin = Vector2i(candidate)
					cover_target = option
					wall_jump_target = outward
					break
			if cover_origin != Config.INVALID_CELL:
				break
		_expect(cover_origin != Config.INVALID_CELL, "generated map did not provide a testable cover context")
		if cover_origin != Config.INVALID_CELL:
			flight_unit.cell = cover_origin
			flight_unit.z = int(main.cells[cover_origin].get("z", 0))
			flight_unit.node.position = main._cell_to_world(cover_origin)
			flight_unit.ap = Config.MAX_AP
			main._update_ui()
			_expect(main.tactical_ui.action_btns["take_cover"].visible, "take-cover control did not appear beside usable geometry")
			_expect(main.begin_targeting("take_cover"), "legal cover context could not enter target mode")
			var cover_ap_before: int = flight_unit.ap
			_expect(
				router.request_action(flight_unit, "take_cover", cover_target),
				"legal cover commitment was rejected"
			)
			_expect(flight_unit.taking_cover and flight_unit.cover_cell == cover_target, "cover commitment state was not retained")
			_expect(flight_unit.blocking, "taking cover did not apply automatic brace")
			_expect(flight_unit.ap == cover_ap_before - Config.TAKE_COVER_COST, "taking cover charged the wrong AP")
			_expect(main.tactical_ui.action_btns["lean_l"].visible, "Lean did not become visible inside committed cover")
			var lean_ap_before: int = flight_unit.ap
			_expect(router.request_action(flight_unit, "lean_l"), "contextual Lean was rejected in cover")
			_expect(flight_unit.lean == "left" and flight_unit.ap == lean_ap_before - Config.LEAN_COST, "Lean did not retain its state or AP cost")
			_expect(not router.request_action(flight_unit, "move", Config.INVALID_CELL), "committed unit was allowed to move without leaving cover")
			var serialized_cover: Dictionary = flight_unit.to_dict()
			var restored_cover := UnitScript.new()
			restored_cover.inv = {}
			restored_cover.apply_dict(serialized_cover)
			_expect(restored_cover.taking_cover and restored_cover.cover_cell == cover_target, "live cover state did not serialize")
			main.dev_god_mode = true
			_expect(router.request_action(flight_unit, "cover_monkey"), "Cover Monkey stance could not be enabled")
			_expect(flight_unit.cover_monkey_active and not MovementRules.movement_locked(flight_unit), "Cover Monkey did not make cover exit movement-contextual")
			var slide_ap_before: int = flight_unit.ap
			var slide_cost := ActionCosts.movement_step_cost(
				flight_unit,
				flight_unit.z,
				int(main.cells[wall_jump_target].get("z", 0))
			)
			_expect(router.request_action(flight_unit, "move", wall_jump_target), "Cover Monkey could not slide out of cover into movement")
			await create_timer(0.8).timeout
			_expect(not flight_unit.taking_cover and flight_unit.cell == wall_jump_target, "Cover Monkey did not leave cover for free during movement")
			_expect(flight_unit.ap == slide_ap_before - slide_cost, "Cover Monkey move did not charge only step cost plus surcharge")
			var return_ap_before: int = flight_unit.ap
			var return_cost := ActionCosts.movement_step_cost(
				flight_unit,
				flight_unit.z,
				int(main.cells[cover_origin].get("z", 0))
			)
			_expect(router.request_action(flight_unit, "move", cover_origin), "Cover Monkey could not return to a cover-adjacent cell")
			await create_timer(0.8).timeout
			_expect(flight_unit.taking_cover and flight_unit.cell == cover_origin, "Cover Monkey did not enter cover automatically at movement end")
			_expect(flight_unit.ap == return_ap_before - return_cost, "automatic cover entry charged hidden AP")
			_expect(router.request_action(flight_unit, "cover_monkey"), "Cover Monkey stance could not be disabled")
			var leave_ap_before: int = flight_unit.ap
			_expect(router.request_action(flight_unit, "leave_cover"), "committed unit could not leave cover")
			_expect(not flight_unit.taking_cover and flight_unit.cover_cell == Config.INVALID_CELL, "leave-cover did not release movement")
			_expect(flight_unit.ap == leave_ap_before - Config.LEAVE_COVER_COST, "leaving cover charged the wrong AP")
			flight_unit.ap = Config.MAX_AP
			flight_unit.run_distance_this_turn = 1
			flight_unit.sprint_distance_this_turn = 0
			_expect(main.begin_targeting("wall_run"), "momentum plus wall did not enter Wall Run targeting")
			_expect(router.request_action(flight_unit, "wall_run", cover_target), "targeted Wall Run segment was rejected")
			await create_timer(0.8).timeout
			_expect(Maneuvers.is_wall_running(flight_unit.maneuver) and flight_unit.wall_running, "Wall Run did not create a surface-relative commitment")
			_expect(flight_unit.z == int(main.cells[cover_origin].get("z", 0)) + 1, "Wall Run did not traverse one vertical surface segment")
			_expect(main.begin_targeting("wall_jump"), "active wall contact did not expose Wall Jump")
			_expect(router.request_action(flight_unit, "wall_jump", wall_jump_target), "outward Wall Jump target was rejected")
			await create_timer(0.8).timeout
			_expect(Maneuvers.is_airborne(flight_unit.maneuver) and not flight_unit.wall_running, "Wall Jump did not transition into airborne state")
			var flip_ap_before: int = flight_unit.ap
			_expect(router.request_action(flight_unit, "flip"), "airborne Flip/Dodge was rejected")
			await create_timer(0.8).timeout
			_expect(flight_unit.flipping and flight_unit.ap == flip_ap_before - Config.FLIP_COST, "Flip did not produce its airborne Dodge window")
			flight_unit.ap = Config.MAX_AP
			_expect(router.request_action(flight_unit, "jump", flight_unit.cell), "wall-jump air state could not complete a landing")
			await create_timer(0.8).timeout
			_expect(not Maneuvers.is_committed(flight_unit.maneuver), "wall-jump landing did not clear its maneuver")

			var fall_target := Config.INVALID_CELL
			for candidate in main.cells:
				if (
					int(main.cells[candidate].get("type", Config.FLOOR)) == Config.FLOOR
					and main._unit_at(candidate) == null
					and absi(candidate.x - flight_unit.cell.x) + absi(candidate.y - flight_unit.cell.y) == 2
					and absi(int(main.cells[candidate].get("z", 0)) - flight_unit.z) <= Config.MAX_JUMP_STEP
				):
					fall_target = Vector2i(candidate)
					break
			_expect(fall_target != Config.INVALID_CELL, "no forced-fall jump target was available")
			if fall_target != Config.INVALID_CELL:
				flight_unit.ap = Config.JUMP_COST
				flight_unit.run_distance_this_turn = 1
				_expect(router.request_action(flight_unit, "jump", fall_target), "zero-reserve jump was rejected")
				await create_timer(0.9).timeout
				_expect(not Maneuvers.is_committed(flight_unit.maneuver), "zero AP did not detach the airborne unit")
				_expect(flight_unit.stance == "prone", "forced maneuver fall did not recover prone")
				_expect(
					main.tactical_ui.hint_label.text.contains("AIRBORNE AP EXHAUSTED"),
					"forced maneuver fall did not present its AP-exhaustion result"
				)
				var detach_record: Dictionary = {}
				for event_record in game_state.event_records:
					if (
						String(event_record.get("event", "")) == "maneuver_detached"
						and String(event_record.get("payload", {}).get("reason", "")) == "ap_exhausted"
					):
						detach_record = event_record.get("payload", {})
				_expect(not detach_record.is_empty(), "forced maneuver fall was not recorded")
				_expect(int(detach_record.get("drop", 0)) > 0, "forced maneuver fall did not record its drop")
				_expect(detach_record.has("damage"), "forced maneuver fall did not record resolved damage")
			main.cancel_targeting()

	main.free()
	await process_frame
	if router != null:
		router.bind(null)

func _test_multi_round_cycle() -> void:
	var packed := load("res://Main.tscn") as PackedScene
	_expect(packed != null, "Main.tscn did not load for the multi-round regression")
	if packed == null:
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	# Keep this lifecycle test deterministic and quick: the hostile slots remain
	# present, but have no live actors to animate. This exercises the complete
	# HAD -> Syndicate -> Kaiju/Aliens -> HAD deferred turn chain repeatedly.
	for unit in main.units:
		if unit.team != main.player_faction:
			unit.alive = false
			if is_instance_valid(unit.node):
				unit.node.visible = false
	var starting_round: int = main.global_turn
	for cycle in 4:
		_expect(main.turn == main.player_faction, "round cycle did not begin on the player team")
		main._end_turn()
		var guard := 0
		while (main.turn != main.player_faction or main.busy) and guard < 120:
			await process_frame
			guard += 1
		_expect(guard < 120, "round cycle stalled before returning control to the player")
		_expect(main.global_turn == starting_round + cycle + 1, "global round counter skipped or repeated a round")
		_expect(not main.game_over, "turn cycling ended the mission without a resolution event")

	main.free()
	await process_frame
	var router = root.get_node_or_null("ActionRouter")
	if router != null:
		router.bind(null)

func _test_strategic_scene() -> void:
	var packed := load("res://StratLayer.tscn") as PackedScene
	_expect(packed != null, "StratLayer.tscn did not load")
	if packed == null:
		return

	var game_state = root.get_node_or_null("GameState")
	if game_state != null:
		game_state.session_active = false
	var strat := packed.instantiate()
	root.add_child(strat)
	await process_frame

	_expect(strat.ui_layer != null, "strategic scene did not create its UI layer")
	_expect(strat.ui_layer.get_child_count() > 0, "strategic scene did not construct its login surface")
	_expect(strat.faction_select != null and strat.faction_select.item_count == 3, "login does not expose all three factions")

	strat.free()
	await process_frame
