extends SceneTree

## Comprehensive headless playtest pass for pre-alpha.
## Runs alongside (not against) a live Godot+Chrome session.
##
##   Godot --path game --headless --script res://tests/PlaytestRunner.gd

const World = preload("res://scripts/WorldBuilder.gd")
const Contract = preload("res://scripts/PayloadContract.gd")
const Config = preload("res://scripts/GameConfig.gd")
const ActionCosts = preload("res://scripts/ActionEconomy.gd")
const MovementRules = preload("res://scripts/MovementContext.gd")
const Maneuvers = preload("res://scripts/ManeuverState.gd")
const UnitScript = preload("res://scripts/Unit.gd")
const PathScript = preload("res://scripts/Pathfinder.gd")
const Tactics = preload("res://scripts/AITactics.gd")
const TutorialGuide = preload("res://scripts/TutorialDirector.gd")
const SquadSpawn = preload("res://scripts/SquadSpawner.gd")
const Ballistics = preload("res://scripts/Ballistics.gd")

var failures: Array[String] = []
var passed: int = 0
var started_ms: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	started_ms = Time.get_ticks_msec()
	print("PLAYTEST: Battle/Star.SOL comprehensive suite starting")
	_test_determinism_matrix()
	_test_payload_edge_cases()
	_test_action_economy_matrix()
	_test_cover_and_los()
	await _test_login_and_launcher()
	await _test_faction_deploy_matrix()
	await _test_guided_proving_ground()
	await _test_terrain_destruction()
	await _test_full_combat_micro()
	await _test_extraction_paths()
	await _test_turn_cycle_integrity()
	await _test_busy_lock_during_ai()
	_test_ai_cover_and_flank()
	var elapsed = Time.get_ticks_msec() - started_ms
	if failures.is_empty():
		print("PASS: PlaytestRunner %d checks in %d ms" % [passed, elapsed])
		quit(0)
	else:
		print("FAIL: PlaytestRunner %d passed, %d failed in %d ms" % [passed, failures.size(), elapsed])
		for failure in failures:
			push_error("FAIL: " + failure)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failures.append(message)

func _test_determinism_matrix() -> void:
	print("  [1] determinism matrix")
	for seed_value in [1, 77, 84021, 999999, 2147483647]:
		var a = World.generate_cells(seed_value)
		var b = World.generate_cells(seed_value)
		_expect(a.size() == Config.GRID_W * Config.GRID_H, "cell count for seed %d" % seed_value)
		_expect(_cell_sig(a) == _cell_sig(b), "seed %d not deterministic" % seed_value)
	var s1 = _cell_sig(World.generate_cells(100))
	var s2 = _cell_sig(World.generate_cells(101))
	_expect(s1 != s2, "adjacent seeds produced identical maps")
	for team in [Config.FACTION_HAD, Config.FACTION_SYND, Config.FACTION_TIME]:
		var pads = World.spawn_cells(team)
		_expect(pads.size() == 3, "spawn pad size for team %d" % team)
		for cell in pads:
			_expect(World.generate_cells(84021).has(cell), "spawn outside map team %d" % team)

func _cell_sig(cells: Dictionary) -> String:
	var rows: Array = []
	for x in Config.GRID_W:
		for y in Config.GRID_H:
			var d: Dictionary = cells.get(Vector2i(x, y), {})
			rows.append([x, y, int(d.get("type", -1)), int(d.get("z", -1))])
	return JSON.stringify(rows)

func _test_payload_edge_cases() -> void:
	print("  [2] payload contract edge cases")
	var legacy = {
		"type": "tactical_state",
		"deploy": {
			"sector": "Edge",
			"faction": "SYND // METROPOLIS",
			"seed": 42,
			"squad": [{"name": "A"}, {"name": "B"}],
			"objectives": ["Survive"],
			"resources": {"neural": 3, "capital": 9}
		}
	}
	var n = Contract.normalize_deploy(legacy)
	_expect(n["type"] == "deploy", "legacy envelope normalize")
	_expect(int(n["seed"]) == 42, "legacy seed preserved")
	_expect(Contract.validate_deploy(n).is_empty(), "normalized valid")
	var galaxy = {
		"gzg": "galaxy-message",
		"version": "1.0",
		"id": "playtest-deploy-42",
		"type": "dealer.deploy",
		"payload": {
			"schema": "gzg.battlestar.deploy/1.0",
			"deploy": legacy["deploy"]
		}
	}
	var galaxy_n = Contract.normalize_deploy(galaxy)
	_expect(int(galaxy_n["seed"]) == 42, "galaxy seed preserved")
	_expect(galaxy_n["galaxy_message_id"] == "playtest-deploy-42", "galaxy id preserved")
	_expect(Contract.validate_deploy(galaxy_n).is_empty(), "galaxy deploy valid")

	var zero_seed = Contract.normalize_deploy({"type": "deploy", "sector": "X", "faction": "HAD", "seed": 0})
	_expect(int(zero_seed["seed"]) > 0, "zero seed falls back")

	var empty_squad = Contract.normalize_deploy({"type": "deploy", "sector": "X", "faction": "HAD", "seed": 5})
	_expect(empty_squad["squad"] is Array and not empty_squad["squad"].is_empty(), "empty squad filled")

	var bad = n.duplicate(true)
	bad["sector"] = "   "
	_expect(not Contract.validate_deploy(bad).is_empty(), "blank sector rejected")

	var no_type = n.duplicate(true)
	no_type["type"] = "extraction"
	_expect(not Contract.validate_deploy(no_type).is_empty(), "wrong type rejected")

func _test_action_economy_matrix() -> void:
	print("  [3] action economy matrix")
	_expect(Config.MAX_AP == 10, "MAX_AP budget")
	var u = UnitScript.new()
	u.ap = Config.MAX_AP
	u.max_ap = Config.MAX_AP
	u.z = 0
	u.stance = "stand"
	u.move_mode = "run"
	u.cover_monkey_active = false
	u.hovering = false
	u.flying = false
	var cells = {
		Vector2i(0, 0): {"z": 0},
		Vector2i(1, 0): {"z": 0},
		Vector2i(2, 0): {"z": 2},
		Vector2i(3, 0): {"z": 0}
	}
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	_expect(ActionCosts.path_cost(u, path, cells) == 1 + 1 + 2, "run+elevation cost")
	u.stance = "crouch"
	_expect(ActionCosts.path_cost(u, path, cells) == 2 + 2 + 2, "crouch elevation")
	u.stance = "prone"
	_expect(ActionCosts.path_cost(u, path, cells) == 3 + 3 + 2, "prone elevation")
	u.stance = "stand"
	u.cover_monkey_active = true
	_expect(ActionCosts.path_cost(u, path, cells) == 2 + 2 + 2, "cover monkey surcharge")
	u.cover_monkey_active = false
	u.flying = true
	_expect(ActionCosts.flight_cost(Vector2i(0, 0), 0, Vector2i(3, 0), 2) >= Config.MOVE_COST, "flight cost floor")
	var items: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	_expect(ActionCosts.weapon_cost(items.get("t1_rifle", {})) == 4, "rifle AP")
	_expect(int(items.get("rock", {}).get("range", 0)) >= 3, "rock throw range restored")
	_expect(bool(items.get("t3_railgun", {}).get("penetrates_cover", false)), "rail penetrates")

func _test_cover_and_los() -> void:
	print("  [4] cover + LOS")
	var path_rules = preload("res://scripts/Pathfinder.gd").new()
	var unit = UnitScript.new()
	unit.alive = true
	unit.stance = "stand"
	unit.cell = Vector2i(2, 2)
	unit.z = 0
	unit.taking_cover = false
	var cover = Vector2i(3, 2)
	var cells = {
		unit.cell: {"type": Config.FLOOR, "z": 0},
		cover: {"type": Config.COVER, "z": 3},
		Vector2i(4, 2): {"type": Config.FLOOR, "z": 0},
		Vector2i(2, 3): {"type": Config.FLOOR, "z": 0}
	}
	_expect(MovementRules.cover_options(unit, cells) == [cover], "adjacent cover option")
	_expect(not path_rules.has_los(unit.cell, Vector2i(4, 2), cells, 0, 0), "cover blocks LOS")
	_expect(path_rules.has_los(unit.cell, Vector2i(4, 2), cells, 0, 0, cover), "lean ignore face opens LOS")
	_expect(path_rules.has_los(unit.cell, Vector2i(4, 2), cells, 0, 0, Config.INVALID_CELL, true), "penetration opens LOS")
	unit.taking_cover = true
	unit.cover_cell = cover
	_expect(MovementRules.movement_locked(unit), "cover locks movement")
	_expect(MovementRules.can_lean(unit, "left"), "lean available in cover")
	unit.cover_monkey_active = true
	_expect(not MovementRules.movement_locked(unit), "cover monkey unlocks movement")

func _test_login_and_launcher() -> void:
	print("  [5] login + launcher surfaces")
	var game_state = root.get_node_or_null("GameState")
	_expect(game_state != null, "GameState autoload present")
	if game_state != null:
		game_state.session_active = false
		game_state.commander_callsign = ""
		game_state.commander_faction = ""
	var packed = load("res://StratLayer.tscn") as PackedScene
	_expect(packed != null, "StratLayer.tscn loads")
	if packed == null:
		return
	var strat = packed.instantiate()
	root.add_child(strat)
	await process_frame
	_expect(strat.ui_layer != null, "UI layer exists")
	_expect(strat.callsign_input != null, "callsign field on login")
	_expect(strat.faction_select != null and strat.faction_select.item_count == 3, "3 factions on login")
	# Simulate login
	strat.callsign_input.text = "PLAYTEST_CMDR"
	strat.faction_select.select(0)
	strat._on_login_pressed()
	await process_frame
	_expect(game_state.session_active, "session active after login")
	_expect(game_state.commander_callsign == "PLAYTEST_CMDR", "callsign stored")
	_expect(strat.ui_layer.get_child_count() > 0, "launcher UI rebuilt")
	strat.free()
	await process_frame

func _test_faction_deploy_matrix() -> void:
	print("  [6] faction deploy matrix")
	var bridge = root.get_node_or_null("PayloadBridge")
	_expect(bridge != null, "PayloadBridge present")
	if bridge == null:
		return
	var factions = [
		{"faction": "HAD // VANGUARD", "expect": Config.FACTION_HAD},
		{"faction": "EFD Defense", "expect": Config.FACTION_HAD},
		{"faction": "SYND // METROPOLIS", "expect": Config.FACTION_SYND},
		{"faction": "Metropoli Alpha", "expect": Config.FACTION_SYND},
		{"faction": "Kaiju/Aliens // HOST", "expect": Config.FACTION_TIME},
		{"faction": "Timecorps", "expect": Config.FACTION_TIME}
	]
	for fac in factions:
		bridge.set_payload({
			"type": "deploy",
			"sector": "Playtest Sector",
			"faction": fac["faction"],
			"seed": 84021,
			"squad": [
				{"name": "Alpha"},
				{"name": "Bravo"},
				{"name": "Charlie"}
			],
			"objectives": ["Playtest"],
			"resources": {"neural": 1, "capital": 1}
		})
		var main_packed = load("res://Main.tscn") as PackedScene
		var main = main_packed.instantiate()
		root.add_child(main)
		await process_frame
		await process_frame
		_expect(main.player_faction == int(fac["expect"]), "faction map failed for %s" % fac["faction"])
		_expect(main.units.size() == 9, "9 units for %s" % fac["faction"])
		_expect(
			main.tactical_ui.turn_label.text.contains(Config.faction_name(int(fac["expect"]))),
			"turn banner vocabulary failed for %s" % fac["faction"]
		)
		_expect(
			main.tactical_ui.phase_help_label.text.contains("END TURN")
			and main.tactical_ui.phase_help_label.text.contains("EXTRACT/F8"),
			"first-turn consequence line failed for %s" % fac["faction"]
		)
		var player_alive = 0
		var bots = 0
		var pilots = 0
		var commanders = 0
		for u in main.units:
			if u.alive and u.team == main.player_faction:
				player_alive += 1
				if bool(u.is_squad_bot):
					bots += 1
				if bool(u.player_controlled):
					pilots += 1
				if bool(u.is_commander):
					commanders += 1
		_expect(player_alive == 3, "3 player units for %s" % fac["faction"])
		_expect(commanders == 1, "one commander for %s" % fac["faction"])
		_expect(bots == 2, "two squad bots for %s" % fac["faction"])
		_expect(pilots == 1, "exactly one human pilot for %s" % fac["faction"])
		_expect(main.selected != null and main.selected.team == main.player_faction, "selected player unit for %s" % fac["faction"])
		_expect(bool(main.selected.player_controlled), "selected is human pilot for %s" % fac["faction"])
		_expect(bool(main.selected.is_commander), "selected is commander for %s" % fac["faction"])
		main.free()
		await process_frame
		var router = root.get_node_or_null("ActionRouter")
		if router:
			router.bind(null)

func _test_guided_proving_ground() -> void:
	print("  [7] guided Proving Ground")
	var bridge = root.get_node_or_null("PayloadBridge")
	var router = root.get_node_or_null("ActionRouter")
	var game_state = root.get_node_or_null("GameState")
	_expect(bridge != null and router != null and game_state != null, "tutorial autoloads present")
	if bridge == null or router == null or game_state == null:
		return

	var recovery_tutorial = TutorialGuide.new()
	_expect(
		recovery_tutorial.begin(
			{"sector": "Proving Ground"},
			Config.FACTION_HAD,
			4
		),
		"AP-recovery tutorial fixture activates (M01-004)"
	)
	recovery_tutorial.step = TutorialGuide.Step.DEFENSE
	recovery_tutorial.set_cover_available(false)
	recovery_tutorial.set_defense_affordable(false)
	var recovery_snapshot: Dictionary = recovery_tutorial.current_snapshot()
	_expect(
		not bool(recovery_snapshot.get("defense_affordable", true))
		and String(recovery_snapshot.get("body", "")).contains("END TURN"),
		"0 AP defense guidance names the recovery action (M01-004)"
	)
	var recovery_commander := {
		"alive": true,
		"is_commander": true,
		"team": Config.FACTION_HAD
	}
	_expect(
		not recovery_tutorial.observe_action("endturn", recovery_commander)
		and recovery_tutorial.step == TutorialGuide.Step.DEFENSE,
		"End Turn retains the DEFENSE checkpoint (M01-004)"
	)
	_expect(
		not recovery_tutorial.observe_record({
			"record_type": "event",
			"event": "turn_started",
			"payload": {"active_team": Config.FACTION_HAD, "round": 5}
		})
		and recovery_tutorial.step == TutorialGuide.Step.DEFENSE,
		"the recovery turn returns to the retained DEFENSE checkpoint (M01-004)"
	)
	recovery_tutorial.set_defense_affordable(true)
	_expect(
		bool(recovery_tutorial.current_snapshot().get("defense_affordable", false)),
		"refreshed AP restores affordable defense guidance (M01-004)"
	)
	_expect(
		recovery_tutorial.observe_action("brace", recovery_commander)
		and recovery_tutorial.step == TutorialGuide.Step.ATTACK,
		"accepted Brace advances the recovered tutorial (M01-004)"
	)

	var factions = [
		{"name": "HAD", "team": Config.FACTION_HAD},
		{"name": "SYND", "team": Config.FACTION_SYND},
		{"name": "TIMECORPS", "team": Config.FACTION_TIME}
	]
	for faction in factions:
		bridge.set_payload({
			"type": "deploy",
			"sector": "Proving Ground",
			"faction": faction["name"],
			"seed": 999999,
			"squad": [{"name": "Recruit-1", "cls": "Scout"}],
			"objectives": ["Complete Guided Proving Ground"],
			"resources": {"neural": 0, "capital": 0}
		})
		var main = (load("res://Main.tscn") as PackedScene).instantiate()
		root.add_child(main)
		await process_frame
		await process_frame
		_expect(main.player_faction == int(faction["team"]), "tutorial faction map for %s" % faction["name"])
		_expect(
			main.units.size() == 4,
			"tutorial has one Commander, two targets, and Haili for %s" % faction["name"]
		)
		_expect(main.tutorial != null and bool(main.tutorial.active), "tutorial director active for %s" % faction["name"])
		_expect(main.tactical_ui.tutorial_panel.visible, "tutorial panel visible for %s" % faction["name"])

		var commander = null
		var targets: Array = []
		var instructor = null
		for unit in main.units:
			if unit.team == main.player_faction:
				commander = unit
			elif String(unit.name) == SquadSpawn.INSTRUCTOR_NAME:
				instructor = unit
			else:
				targets.append(unit)
		_expect(commander != null and bool(commander.is_commander), "tutorial Commander exists for %s" % faction["name"])
		_expect(targets.size() == 2, "tutorial targets are hostile for %s" % faction["name"])
		if commander != null:
			for target in targets:
				var distance := absi(target.cell.x - commander.cell.x) + absi(target.cell.y - commander.cell.y)
				_expect(distance <= 3, "tutorial target is reachable for %s" % faction["name"])

		# The armed instructor is the only tutorial agent with a real action pool.
		# The dummies teach the action surface; Haili makes positional play
		# observable in the guided scenario instead of headless-only.
		_expect(instructor != null, "guided tutorial provides the armed instructor for %s" % faction["name"])
		if instructor != null:
			_expect(
				int(instructor.team) != int(main.player_faction),
				"the instructor is not hostile for %s" % faction["name"]
			)
			_expect(
				int(instructor.max_ap) == Config.MAX_AP and int(instructor.ap) == Config.MAX_AP,
				"the instructor has no Base-10 action pool for %s" % faction["name"]
			)
			_expect(
				(instructor.skills as Array).size() > 1,
				"the instructor is unarmed for %s" % faction["name"]
			)
			for dummy in targets:
				_expect(
					int(dummy.max_ap) == 0,
					"a target dummy gained an action pool for %s" % faction["name"]
				)
			if commander != null:
				var instructor_distance := absi(instructor.cell.x - commander.cell.x) + absi(
					instructor.cell.y - commander.cell.y
				)
				_expect(
					instructor_distance > 3,
					"the instructor crowds the one-turn melee lane for %s" % faction["name"]
				)

		if int(faction["team"]) == Config.FACTION_HAD and commander != null and targets.size() == 2:
			_expect(
				main.tutorial.current_snapshot()["step_key"] == "select_commander",
				"tutorial begins at selection"
			)
			var commander_row: Dictionary = {}
			for row in main.tactical_ui.roster_rows:
				if row.get("unit") == commander:
					commander_row = row
					break
			_expect(not commander_row.is_empty(), "Commander roster row exists (M01-001)")
			var actions_before_select: int = game_state.action_records.size()
			if not commander_row.is_empty():
				commander_row["btn"].pressed.emit()
				await process_frame
			_expect(main.selected == commander, "roster row selects the Commander (M01-001)")
			_expect(
				main.tutorial.current_snapshot()["step_key"] == "move",
				"roster row press advances the guided tutorial (M01-001)"
			)
			var routed_select := false
			var routed_select_actor := false
			for record in game_state.action_records.slice(actions_before_select):
				if String(record.get("action", "")) == "select" and bool(record.get("accepted", false)):
					routed_select = true
					var actor_ref: Dictionary = record.get("actor", {})
					routed_select_actor = int(actor_ref.get("unit_id", -1)) == int(commander.unit_id)
			_expect(routed_select, "select crosses the action boundary and reaches the ledger (M01-001)")
			_expect(routed_select_actor, "routed select preserves Commander identity (M01-001)")

			var observation: Dictionary = main._build_web_observation()
			var tutorial_observation: Dictionary = observation.get("tutorial", {})
			_expect(
				String(observation.get("kind", "")) == "observation"
				and String(tutorial_observation.get("step", "")) == "move"
				and int(tutorial_observation.get("display_step", 0)) == 2,
				"observation preserves guided step fields (M01-003)"
			)
			var actor_observation: Dictionary = observation.get("actor", {})
			var actor_cell: Dictionary = actor_observation.get("cell", {})
			_expect(
				int(actor_observation.get("unit_id", -1)) == int(commander.unit_id)
				and int(actor_cell.get("x", -1)) == commander.cell.x
				and int(actor_cell.get("y", -1)) == commander.cell.y,
				"observation actor matches the selected Commander (M01-003)"
			)
			_expect(
				int(actor_observation.get("ap", -1)) == int(commander.ap),
				"observation actor AP matches simulation authority (M01-003)"
			)
			var viewport_observation: Dictionary = observation.get("viewport", {})
			_expect(
				int(viewport_observation.get("w", 0)) > 0
				and int(viewport_observation.get("h", 0)) > 0,
				"observation publishes a positive viewport (M01-003)"
			)
			var camera: Camera3D = main.camera_controller.camera
			var original_camera_transform := camera.global_transform
			var view_signature: String = main._observation_view_signature()
			_expect(
				not view_signature.is_empty(),
				"observation view signature tracks the live camera and viewport (M01-005)"
			)
			camera.global_position += Vector3(0.25, 0.0, 0.0)
			var shifted_view_signature: String = main._observation_view_signature()
			camera.global_transform = original_camera_transform
			_expect(
				shifted_view_signature != view_signature,
				"camera motion invalidates published screen positions (M01-005)"
			)
			var move_observations: Array = observation.get("move_targets", [])
			var chebyshev_only_target_published := false
			for entry in move_observations:
				var entry_cell: Dictionary = entry.get("cell", {})
				var delta_x := absi(int(entry_cell.get("x", commander.cell.x)) - commander.cell.x)
				var delta_y := absi(int(entry_cell.get("y", commander.cell.y)) - commander.cell.y)
				if maxi(delta_x, delta_y) <= main.OBSERVATION_RADIUS and delta_x + delta_y > main.OBSERVATION_RADIUS:
					chebyshev_only_target_published = true
			_expect(
				not move_observations.is_empty()
				and move_observations.size() <= main.OBSERVATION_MOVE_CAP
				and chebyshev_only_target_published,
				"observation publishes a bounded legal move list (M01-003)"
			)
			var move_costs_valid := true
			var move_screens_valid := true
			var move_order_valid := true
			var previous_move := Vector2i(-1, -1)
			var has_previous_move := false
			for entry in move_observations:
				var entry_cost := int(entry.get("ap", -1))
				if entry_cost <= 0 or entry_cost > int(commander.ap):
					move_costs_valid = false
				var entry_cell: Dictionary = entry.get("cell", {})
				var current_move := Vector2i(
					int(entry_cell.get("x", -1)),
					int(entry_cell.get("y", -1))
				)
				if (
					has_previous_move
					and (
						current_move.y < previous_move.y
						or (
							current_move.y == previous_move.y
							and current_move.x < previous_move.x
						)
					)
				):
					move_order_valid = false
				previous_move = current_move
				has_previous_move = true
				var entry_screen = entry.get("screen", {})
				if not (entry_screen is Dictionary) or not entry_screen.has("x") or not entry_screen.has("y"):
					move_screens_valid = false
			_expect(move_costs_valid, "published move costs fit the remaining AP pool (M01-003)")
			_expect(
				move_screens_valid and move_order_valid,
				"published move targets include screen positions in row-major order (M01-003)"
			)

			var published_cover_cells: Array[Vector2i] = []
			for entry in observation.get("cover_faces", []):
				var cell_data: Dictionary = entry.get("cell", {})
				published_cover_cells.append(Vector2i(
					int(cell_data.get("x", -1)),
					int(cell_data.get("y", -1))
				))
			var authoritative_cover_cells: Array[Vector2i] = main.cover_options(commander)
			if authoritative_cover_cells.size() > main.OBSERVATION_COVER_CAP:
				authoritative_cover_cells.resize(main.OBSERVATION_COVER_CAP)
			_expect(
				published_cover_cells.size() <= main.OBSERVATION_COVER_CAP
				and published_cover_cells == authoritative_cover_cells,
				"published cover faces match the UI authority and cap (M01-003)"
			)

			var attack_observations: Array = observation.get("attack_targets", [])
			var attacks_valid: bool = attack_observations.size() <= main.OBSERVATION_ATTACK_CAP
			var pathfinder = root.get_node("Pathfinder")
			for entry in attack_observations:
				var hostile = main.get_unit_by_id(int(entry.get("unit_id", -1)))
				if (
					hostile == null
					or not hostile.alive
					or hostile.team == commander.team
					or hostile.node == null
					or not is_instance_valid(hostile.node)
					or not bool(hostile.node.visible)
				):
					attacks_valid = false
					continue
				var distance: int = pathfinder.cheb(hostile.cell, commander.cell)
				if (
					distance > main.OBSERVATION_RADIUS
					or bool(entry.get("adjacent", false))
					!= pathfinder.is_adjacent(hostile.cell, commander.cell)
				):
					attacks_valid = false
			_expect(attacks_valid, "published attack targets are living hostiles with correct adjacency (M01-003)")
			_expect(
				JSON.stringify(observation).length() <= 16384,
				"observation payload remains bounded (M01-003)"
			)
			var saved_ap := int(commander.ap)
			commander.ap = 0
			var zero_ap_observation: Dictionary = main._build_web_observation()
			commander.ap = saved_ap
			_expect(
				Array(zero_ap_observation.get("move_targets", [])).is_empty(),
				"0 AP publishes no legal move targets (M01-003)"
			)

			var move_target: Vector2i = World.spawn_cells(Config.FACTION_HAD)[1]
			var published_preferred := false
			for entry in move_observations:
				var cell_data: Dictionary = entry.get("cell", {})
				var candidate := Vector2i(
					int(cell_data.get("x", -1)),
					int(cell_data.get("y", -1))
				)
				if candidate == move_target:
					published_preferred = true
					break
			if not published_preferred and not move_observations.is_empty():
				var first_cell: Dictionary = move_observations[0].get("cell", {})
				move_target = Vector2i(
					int(first_cell.get("x", -1)),
					int(first_cell.get("y", -1))
				)
			_expect(
				router.request_action(commander, "move", move_target),
				"a published move target is accepted by ActionRouter (M01-003)"
			)
			var move_guard := 0
			while main.busy and move_guard < 120:
				await process_frame
				move_guard += 1
			_expect(move_guard < 120, "tutorial move resolved")
			_expect(main.tutorial.current_snapshot()["step_key"] == "defense", "movement advances to defense")
			_expect(not bool(main.tutorial.cover_available), "clear training lane explains cover fallback")
			var post_move_ap := int(commander.ap)
			commander.ap = 0
			main._update_ui()
			var zero_ap_guidance: Dictionary = main.tutorial.current_snapshot()
			_expect(
				not bool(zero_ap_guidance.get("defense_affordable", true))
				and String(zero_ap_guidance.get("body", "")).contains("END TURN"),
				"live 0 AP state publishes recovery guidance (M01-004)"
			)
			commander.ap = post_move_ap
			main._update_ui()
			_expect(
				bool(main.tutorial.current_snapshot().get("defense_affordable", false)),
				"live AP restoration republishes affordable defense (M01-004)"
			)

			_expect(router.request_action(commander, "brace"), "tutorial Brace accepted")
			_expect(main.tutorial.current_snapshot()["step_key"] == "attack", "defense advances to attack")
			var adjacent_target = null
			for target in targets:
				if absi(commander.cell.x - target.cell.x) + absi(commander.cell.y - target.cell.y) == 1:
					adjacent_target = target
					break
			_expect(adjacent_target != null, "tutorial provides adjacent basic-attack target")
			if adjacent_target != null:
				_expect(
					router.request_action(commander, "melee", adjacent_target.cell),
					"tutorial basic attack accepted"
				)
			var attack_guard := 0
			while main.busy and attack_guard < 120:
				await process_frame
				attack_guard += 1
			_expect(attack_guard < 120, "tutorial attack resolved")
			_expect(main.tutorial.current_snapshot()["step_key"] == "end_turn", "attack advances to End Turn")

			_expect(router.request_action(commander, "endturn"), "tutorial End Turn accepted")
			_expect(
				main.tutorial.current_snapshot()["step_key"] == "observe_phases",
				"End Turn advances to phase observation"
			)
			# End Turn is intentionally deferred so the accepted action record is
			# committed before autonomous phases begin.
			await process_frame
			await process_frame
			var turn_guard := 0
			while (main.turn != main.player_faction or main.busy) and turn_guard < 180:
				await process_frame
				turn_guard += 1
			_expect(turn_guard < 180, "tutorial faction cycle returned control")
			_expect(main.global_turn == 2, "tutorial returned on turn 2")
			_expect(main.tutorial.current_snapshot()["step_key"] == "extract", "returned turn exposes extraction")

			game_state.record_event("mission_resolved", {"outcome": "SUCCESS", "note": "test"})
			_expect(bool(main.tutorial.current_snapshot()["complete"]), "mission result completes tutorial")
			_expect(
				main.tactical_ui.tutorial_title_label.text.contains("PROVING GROUND COMPLETE"),
				"completion remains visible in the tutorial panel"
			)

		await process_frame
		main.free()
		await process_frame
		router.bind(null)

func _test_terrain_destruction() -> void:
	print("  [8a] cover destruction under live fire (M03-005)")
	var bridge = root.get_node_or_null("PayloadBridge")
	if bridge:
		bridge.set_payload({
			"type": "deploy",
			"sector": "Destruction Micro",
			"faction": "HAD",
			"seed": 84021,
			"squad": [{"name": "Gunner"}, {"name": "B"}, {"name": "C"}],
			"objectives": ["Break cover"],
			"resources": {"neural": 0, "capital": 0}
		})
	var main = (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var shooter = main.selected
	var hostile = null
	for unit in main.units:
		if unit != null and bool(unit.alive) and int(unit.team) != int(main.player_faction):
			hostile = unit
			break
	_expect(shooter != null and hostile != null, "destruction micro has a shooter and a target")
	if shooter == null or hostile == null:
		main.free()
		return

	# Stand a wall between them, and put the target directly behind it.
	var wall_cell: Vector2i = Vector2i(shooter.cell) + Vector2i(2, 0)
	var target_cell: Vector2i = Vector2i(shooter.cell) + Vector2i(3, 0)
	if not main.cells.has(wall_cell) or not main.cells.has(target_cell):
		main.free()
		return
	main.cells[wall_cell] = World.material_cell(Config.COVER, 3)
	main.cells[target_cell] = World.material_cell(Config.FLOOR, 0)
	hostile.cell = target_cell
	hostile.z = 0

	_expect(
		main._in_cover(Vector2i(shooter.cell), target_cell) == 2,
		"the interposed wall does not read as full cover"
	)
	var integrity_before: int = Ballistics.density_of(main.cells[wall_cell])
	var changes_before: int = main.terrain_changes.size()

	# A rifle round works the material whether or not it gets through.
	var delta: Dictionary = main.damage_terrain(wall_cell, 28, "rifle", shooter)
	_expect(not delta.is_empty(), "live fire recorded no terrain change")
	_expect(
		Ballistics.density_of(main.cells[wall_cell]) < integrity_before,
		"the wall did not lose integrity"
	)
	_expect(
		main.terrain_changes.size() == changes_before + 1,
		"the terrain change was not appended to the mission record"
	)
	var game_state = root.get_node_or_null("GameState")
	_expect(game_state != null, "destruction micro has the ledger authority")
	var recorded := 0
	for record in (game_state.event_records if game_state != null else []):
		if String(record.get("event", "")) == "terrain_damaged":
			recorded += 1
	_expect(recorded > 0, "terrain damage was not recorded in the ledger")

	# Sustained fire destroys it, and cover scoring follows the material down.
	var destroy_guard := 0
	while Ballistics.effective_cover_level(main.cells[wall_cell]) > 0 and destroy_guard < 30:
		main.damage_terrain(wall_cell, 28, "rifle", shooter)
		destroy_guard += 1
	_expect(destroy_guard < 30, "sustained fire never destroyed the wall")
	_expect(
		main._in_cover(Vector2i(shooter.cell), target_cell) == 0,
		"destroyed cover still protects the target"
	)
	_expect(
		int(main.cells[wall_cell]["type"]) == Config.FLOOR,
		"destroyed cover is still a cover tile"
	)
	var destroyed_recorded := false
	for record in (game_state.event_records if game_state != null else []):
		if String(record.get("event", "")) == "terrain_damaged":
			var payload = record.get("payload", {})
			if payload is Dictionary and bool((payload as Dictionary).get("destroyed", false)):
				destroyed_recorded = true
	_expect(destroyed_recorded, "cover destruction was not recorded as destroyed")
	# Nothing further to take from open ground.
	_expect(
		main.damage_terrain(wall_cell, 28, "rifle", shooter).is_empty(),
		"open ground kept taking terrain damage"
	)

	# BUGFIX-003: rebuilding a damaged tile must leave exactly one tile for that cell,
	# addressable by its canonical name. `queue_free` defers, so the replacement used
	# to be added while the old node was still a child, and Godot renamed the new one
	# to avoid the collision — orphaning tiles and pointing later lookups at a dying
	# node.
	var tile_cell: Vector2i = Vector2i(shooter.cell) + Vector2i(0, 3)
	if main.cells.has(tile_cell) and main.tiles_root != null:
		var tile_name := "Tile_%d_%d" % [tile_cell.x, tile_cell.y]
		main.cells[tile_cell] = World.material_cell(Config.COVER, 5)
		main._rebuild_tile(tile_cell)
		var children_after_first: int = main.tiles_root.get_child_count()
		for _rebuild in range(4):
			main.cells[tile_cell] = World.material_cell(Config.COVER, 4)
			main._rebuild_tile(tile_cell)
		_expect(
			main.tiles_root.get_child_count() == children_after_first,
			"repeated tile rebuilds leaked nodes (%d -> %d)" % [
				children_after_first,
				main.tiles_root.get_child_count()
			]
		)
		var named := 0
		for child in main.tiles_root.get_children():
			if String(child.name).begins_with(tile_name):
				named += 1
		_expect(
			named == 1,
			"cell %s has %d tiles after rebuilds; exactly one must own the name" % [
				str(tile_cell),
				named
			]
		)
		var addressable = main.tiles_root.get_node_or_null(tile_name)
		_expect(
			addressable != null and is_instance_valid(addressable),
			"the rebuilt tile is not addressable by its canonical name"
		)

	# BUGFIX-005: a blast must not reach a unit through a wall it did not breach. Cover
	# between the blast centre and a unit costs the unit one extra halving.
	var path_authority = root.get_node_or_null("Pathfinder")
	if hostile != null and path_authority != null:
		var blast_centre: Vector2i = Vector2i(hostile.cell) + Vector2i(2, 0)
		var screen_cell: Vector2i = Vector2i(hostile.cell) + Vector2i(1, 0)
		if main.cells.has(blast_centre) and main.cells.has(screen_cell):
			var centre_z: int = int(main.cells[blast_centre].get("z", 0))
			# Open ground first: the unit is exposed.
			main.cells[screen_cell] = World.material_cell(Config.FLOOR, 0)
			_expect(
				path_authority.has_los(
					blast_centre, Vector2i(hostile.cell), main.cells, centre_z, int(hostile.z)
				),
				"an open lane between blast and unit does not report line of sight"
			)
			# Now interpose a wall taller than both.
			main.cells[screen_cell] = World.material_cell(Config.COVER, 4)
			_expect(
				not path_authority.has_los(
					blast_centre, Vector2i(hostile.cell), main.cells, centre_z, int(hostile.z)
				),
				"a wall between blast and unit still reports line of sight, so blasts pass through cover"
			)
			# The extra halving is what the shield is worth.
			var exposed_damage: int = maxi(int(round(8.0 / pow(2.0, 1.0))), 1)
			var shielded_damage: int = maxi(int(round(8.0 / pow(2.0, 2.0))), 1)
			_expect(
				shielded_damage < exposed_damage,
				"blast shielding does not reduce damage"
			)
			main.cells[screen_cell] = World.material_cell(Config.FLOOR, 0)

	# BUGFIX-003 follow-up: the damaged-material appearance only became reachable once
	# tile lookups resolved to the live node, so assert it actually lands.
	if main.cells.has(tile_cell) and main.tiles_root != null:
		var pristine_name := "Tile_%d_%d" % [tile_cell.x, tile_cell.y]
		main.cells[tile_cell] = World.material_cell(Config.COVER, 4)
		main._rebuild_tile(tile_cell)
		var pristine_tile = main.tiles_root.get_node_or_null(pristine_name)
		_expect(
			pristine_tile != null and pristine_tile.material_override == null,
			"undamaged terrain carries a damage override"
		)
		main.cells[tile_cell] = Ballistics.degrade_cell(main.cells[tile_cell], 200)
		_expect(
			String(main.cells[tile_cell].get("material", "")) == "rubble",
			"the test cell did not degrade to rubble"
		)
		main._rebuild_tile(tile_cell)
		var wrecked = main.tiles_root.get_node_or_null(pristine_name)
		_expect(
			wrecked != null and wrecked.material_override != null,
			"destroyed terrain does not look destroyed"
		)

	# BUGFIX-002: a blast works each cell once. Before the guard, every victim also
	# re-damaged the cover in its own firing lane, so terrain wear scaled with how
	# many units happened to be standing nearby.
	var blast_wall: Vector2i = Vector2i(shooter.cell) + Vector2i(4, 0)
	if main.cells.has(blast_wall):
		var combat = main.combat
		_expect(combat != null, "destruction micro cannot reach the combat authority")
		if combat != null:
			# One victim beside the wall.
			main.cells[blast_wall] = World.material_cell(Config.COVER, 4)
			var lone_before: int = Ballistics.density_of(main.cells[blast_wall])
			combat._resolving_blast = true
			main.damage_terrain(blast_wall, 12, "grenade", shooter)
			combat._resolving_blast = false
			var lone_loss: int = lone_before - Ballistics.density_of(main.cells[blast_wall])

			# The same blast with a crowd must cost the wall exactly the same.
			main.cells[blast_wall] = World.material_cell(Config.COVER, 4)
			var crowd_before: int = Ballistics.density_of(main.cells[blast_wall])
			combat._resolving_blast = true
			main.damage_terrain(blast_wall, 12, "grenade", shooter)
			for _victim in range(3):
				# What the per-shot path would have added, had the guard not held.
				if not combat._resolving_blast:
					main.damage_terrain(blast_wall, 12, "grenade", shooter)
			combat._resolving_blast = false
			var crowd_loss: int = crowd_before - Ballistics.density_of(main.cells[blast_wall])
			_expect(
				lone_loss > 0,
				"a grenade did not work the wall at all"
			)
			_expect(
				crowd_loss == lone_loss,
				"blast terrain damage scaled with the number of units hit (%d vs %d)" % [
					crowd_loss,
					lone_loss
				]
			)

	# BUGFIX-001: destroying a unit's cover must release it without charging AP, and
	# must not be able to fail. Routing it through the ordinary leave_cover verb
	# charged the victim for someone else's shot and silently failed at zero AP,
	# leaving them flagged in cover, movement-locked, behind rubble, forever.
	var pinned = null
	for unit in main.units:
		if unit != null and bool(unit.alive) and int(unit.team) != int(main.player_faction):
			pinned = unit
			break
	if pinned != null:
		var shelter: Vector2i = Vector2i(pinned.cell) + Vector2i(1, 0)
		if main.cells.has(shelter):
			main.cells[shelter] = World.material_cell(Config.COVER, 3)
			pinned.taking_cover = true
			pinned.cover_cell = shelter
			pinned.ap = 0
			var ap_before: int = pinned.ap
			var guard := 0
			while Ballistics.effective_cover_level(main.cells[shelter]) >= 2 and guard < 30:
				main.damage_terrain(shelter, 30, "rifle", shooter)
				guard += 1
			_expect(guard < 30, "the pinning wall never dropped below full cover")
			_expect(
				not bool(pinned.taking_cover),
				"a unit at zero AP stayed locked in cover that was destroyed"
			)
			_expect(
				int(pinned.ap) == ap_before,
				"destroying cover charged the victim AP for someone else's shot"
			)
			_expect(
				Vector2i(pinned.cover_cell) == main.INVALID_CELL,
				"a released unit still points at its destroyed cover cell"
			)
			var released := false
			for record in (game_state.event_records if game_state != null else []):
				if String(record.get("event", "")) == "cover_left":
					var payload = record.get("payload", {})
					if payload is Dictionary and String((payload as Dictionary).get("source", "")) == "cover_destroyed":
						released = true
						_expect(
							int((payload as Dictionary).get("ap_spent", -1)) == 0,
							"the cover-destroyed release recorded an AP cost"
						)
			_expect(released, "cover destruction was not recorded as a release")

	main.free()
	await process_frame
	var router = root.get_node_or_null("ActionRouter")
	if router != null:
		router.bind(null)

func _test_full_combat_micro() -> void:
	print("  [8] combat micro-loop")
	var bridge = root.get_node_or_null("PayloadBridge")
	if bridge:
		bridge.set_payload({
			"type": "deploy",
			"sector": "Combat Micro",
			"faction": "HAD",
			"seed": 84021,
			"squad": [{"name": "Lead"}, {"name": "Gun"}, {"name": "Scout"}],
			"objectives": ["Fight"],
			"resources": {"neural": 0, "capital": 0}
		})
	var main = (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var router = root.get_node_or_null("ActionRouter")
	_expect(router != null and router.game == main, "router bound")
	if router == null or main.selected == null:
		main.free()
		return

	var actor = main.selected
	var start_ap: int = actor.ap
	_expect(router.request_action(actor, "toggle_run"), "toggle run")
	_expect(actor.move_mode == "sprint" or actor.move_mode == "run", "move mode toggled")

	# Grab loot if standing on debris, else move toward nearest debris
	if main.debris.has(actor.cell):
		_expect(router.request_action(actor, "grab"), "grab underfoot")
	else:
		var moved = false
		for cell in main.debris.keys():
			var path = root.get_node("Pathfinder").find_path(actor.cell, cell, main.cells, main.units)
			if path.size() >= 2:
				var step: Vector2i = path[1]
				if router.request_action(actor, "move", step):
					await create_timer(0.4).timeout
					moved = true
					break
		_expect(moved or main.debris.is_empty(), "move toward loot or no loot")

	# Brace / crouch cycle
	actor.ap = Config.MAX_AP
	_expect(router.request_action(actor, "brace"), "brace")
	_expect(actor.blocking, "blocking after brace")
	_expect(router.request_action(actor, "crouch"), "crouch")
	_expect(actor.stance == "crouch", "crouch stance")

	# Authority: cannot command hostile
	var hostile = null
	for u in main.units:
		if u.alive and u.team != main.player_faction:
			hostile = u
			break
	if hostile != null:
		_expect(not router.request_action(hostile, "brace"), "hostile action rejected on player turn")

	# Authority: cannot command squad bots without Remotes
	var bot = null
	for u in main.units:
		if u.alive and u.team == main.player_faction and bool(u.is_squad_bot):
			bot = u
			break
	if bot != null:
		_expect(not router.request_action(bot, "brace"), "squad bot action rejected without remotes")
		# Remotes requires God Mode
		main.dev_god_mode = false
		_expect(not router.request_action(actor, "remotes", bot.cell), "remotes blocked without god mode")
		main.dev_god_mode = true
		_expect(router.request_action(actor, "remotes", bot.cell), "remotes login to bot")
		_expect(bool(bot.player_controlled) and not bool(actor.player_controlled), "pilot link transferred to bot")
		_expect(router.request_action(bot, "remotes_home"), "remotes return home")
		_expect(bool(actor.player_controlled) and not bool(bot.player_controlled), "pilot returned to commander")
		main.dev_god_mode = false

	# Melee if adjacent enemy exists, else skip
	var adj = null
	for u in main.units:
		if u.alive and u.team != actor.team and root.get_node("Pathfinder").is_adjacent(actor.cell, u.cell):
			adj = u
			break
	if adj != null:
		actor.ap = Config.MAX_AP
		var ok = router.request_action(actor, "melee", adj.cell)
		_expect(ok, "melee adjacent")
		await create_timer(0.5).timeout

	# Insufficient AP must not false-accept melee
	actor.ap = 0
	if adj != null and adj.alive:
		_expect(not router.request_action(actor, "melee", adj.cell), "0 AP melee rejected")

	_expect(start_ap == Config.MAX_AP, "baseline max AP sanity")
	main.free()
	await process_frame
	if router:
		router.bind(null)

func _test_extraction_paths() -> void:
	print("  [9] extraction paths")
	var bridge = root.get_node_or_null("PayloadBridge")
	if bridge:
		bridge.set_payload({
			"type": "deploy",
			"sector": "Extract Test",
			"faction": "HAD",
			"seed": 12345,
			"squad": [{"name": "Solo"}, {"name": "Two"}, {"name": "Three"}],
			"objectives": ["Extract"],
			"resources": {"neural": 0, "capital": 0}
		})
	var main = (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	_expect(not main.game_over, "mission starts open")

	# Victory: wipe hostiles
	for u in main.units:
		if u.team != main.player_faction:
			u.alive = false
	main._check_end()
	await create_timer(0.1).timeout
	_expect(main.game_over, "victory sets game_over")
	# Idempotent
	main._check_end()
	await process_frame

	main.free()
	await process_frame

	# Defeat path on fresh scene
	if bridge:
		bridge.set_payload({
			"type": "deploy",
			"sector": "Defeat Test",
			"faction": "HAD",
			"seed": 12346,
			"squad": [{"name": "Doomed"}],
			"objectives": ["Die"],
			"resources": {"neural": 0, "capital": 0}
		})
	main = (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	for u in main.units:
		if u.team == main.player_faction:
			u.alive = false
	main._check_end()
	await create_timer(0.1).timeout
	_expect(main.game_over, "defeat sets game_over")
	main.free()
	await process_frame
	var router = root.get_node_or_null("ActionRouter")
	if router:
		router.bind(null)

func _test_turn_cycle_integrity() -> void:
	print("  [10] turn cycle integrity")
	var bridge = root.get_node_or_null("PayloadBridge")
	if bridge:
		bridge.set_payload({
			"type": "deploy",
			"sector": "Turn Cycle",
			"faction": "HAD",
			"seed": 555,
			"squad": [{"name": "A"}, {"name": "B"}, {"name": "C"}],
			"objectives": ["Cycle"],
			"resources": {"neural": 0, "capital": 0}
		})
	var main = (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	for u in main.units:
		if u.team != main.player_faction:
			u.alive = false
			if is_instance_valid(u.node):
				u.node.visible = false
	var start_round: int = main.global_turn
	var game_state = root.get_node_or_null("GameState")
	for cycle in 3:
		_expect(main.turn == main.player_faction, "player turn at cycle start %d" % cycle)
		main._end_turn()
		var guard = 0
		while (main.turn != main.player_faction or main.busy) and guard < 150:
			await process_frame
			guard += 1
		_expect(guard < 150, "turn cycle stalled at %d" % cycle)
		_expect(main.global_turn == start_round + cycle + 1, "round counter at cycle %d" % cycle)
		if game_state:
			_expect(int(game_state.turn) == main.turn, "GameState.turn sync cycle %d" % cycle)
	main.free()
	await process_frame
	var router = root.get_node_or_null("ActionRouter")
	if router:
		router.bind(null)

func _test_busy_lock_during_ai() -> void:
	print("  [11] busy lock during AI flag")
	var bridge = root.get_node_or_null("PayloadBridge")
	if bridge:
		bridge.set_payload({
			"type": "deploy",
			"sector": "Busy Lock",
			"faction": "HAD",
			"seed": 777,
			"squad": [{"name": "A"}, {"name": "B"}, {"name": "C"}],
			"objectives": ["Lock"],
			"resources": {"neural": 0, "capital": 0}
		})
	var main = (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	_expect(main.has_method("set_action_busy"), "set_action_busy exists")
	main._ai_turn_active = true
	main.busy = true
	main.set_action_busy(false)
	_expect(main.busy, "AI turn holds busy lock against clear")
	main._ai_turn_active = false
	main.set_action_busy(false)
	_expect(not main.busy, "busy clears when AI flag down")
	# Player cannot act while busy
	main.busy = true
	var router = root.get_node_or_null("ActionRouter")
	if router and main.selected:
		_expect(not router.request_action(main.selected, "brace"), "busy blocks player brace")
	main.busy = false
	main.free()
	await process_frame
	if router:
		router.bind(null)

func _test_ai_cover_and_flank() -> void:
	print("  [12] AI cover + flank tactics (M03)")
	var pathfinder = PathScript.new()

	var cells := {}
	for x in range(0, 8):
		for y in range(0, 8):
			cells[Vector2i(x, y)] = {"type": Config.FLOOR, "z": 0}
	cells[Vector2i(4, 2)] = {"type": Config.COVER, "z": 3}
	cells[Vector2i(4, 4)] = {"type": Config.HALF_COVER, "z": 1}
	cells[Vector2i(1, 3)] = {"type": Config.COVER, "z": 3}

	# cover_level reads the face between shooter and target cell
	_expect(Tactics.cover_level(Vector2i(6, 2), Vector2i(3, 2), cells) == 2, "full cover face scores 2")
	_expect(Tactics.cover_level(Vector2i(6, 4), Vector2i(3, 4), cells) == 1, "half cover face scores 1")
	_expect(Tactics.cover_level(Vector2i(6, 6), Vector2i(3, 6), cells) == 0, "open ground scores 0")
	_expect(Tactics.cover_level(Vector2i(1, 5), Vector2i(1, 2), cells) == 2, "cover face resolves on the y axis")

	var defender = UnitScript.new()
	defender.alive = true
	defender.team = 0
	defender.unit_id = 1
	defender.cell = Vector2i(3, 6)
	defender.z = 0
	defender.hp = 10
	defender.max_hp = 10
	defender.ap = 8
	defender.max_ap = 10
	defender.stance = "stand"

	var hostile = UnitScript.new()
	hostile.alive = true
	hostile.team = 1
	hostile.unit_id = 2
	hostile.cell = Vector2i(6, 6)
	hostile.z = 0
	hostile.hp = 10
	hostile.max_hp = 10
	hostile.ap = 8
	hostile.max_ap = 10

	var units: Array = [defender, hostile]

	# exposure counts hostiles holding line of sight
	_expect(Tactics.exposure_count(Vector2i(3, 6), defender, units, cells, pathfinder) == 1, "open cell exposed to one hostile")
	cells[Vector2i(5, 6)] = {"type": Config.COVER, "z": 3}
	_expect(Tactics.exposure_count(Vector2i(3, 6), defender, units, cells, pathfinder) == 0, "interposed cover removes exposure")
	cells[Vector2i(5, 6)] = {"type": Config.FLOOR, "z": 0}

	var corpse = UnitScript.new()
	corpse.alive = false
	corpse.team = 1
	corpse.unit_id = 3
	corpse.cell = Vector2i(3, 7)
	corpse.z = 0
	_expect(Tactics.exposure_count(Vector2i(3, 6), defender, [defender, hostile, corpse], cells, pathfinder) == 1, "dead hostiles do not contribute exposure")

	# AP reserve gate — movement must never spend the attack away
	defender.ap = 5
	_expect(Tactics.can_afford_step_with_reserve(defender, Vector2i(4, 6), cells, 4), "step allowed when reserve is preserved")
	_expect(not Tactics.can_afford_step_with_reserve(defender, Vector2i(4, 6), cells, 5), "step refused when it would break reserve")
	_expect(not Tactics.can_afford_step_with_reserve(defender, Vector2i(99, 99), cells, 0), "step refused off-grid")
	_expect(not Tactics.can_afford_step_with_reserve(null, Vector2i(4, 6), cells, 0), "step refused for null unit")

	# positioning guards — states with their own movement grammar opt out
	var melee_profile := {"cost": Config.MELEE_COST, "range": 1, "penetrates_cover": false}
	var profile := {"cost": 2, "range": 6, "penetrates_cover": false}
	defender.ap = 8
	_expect(Tactics.positioning_candidates(defender, units, cells, pathfinder, melee_profile).is_empty(), "melee profile defers to the approach fallback")
	defender.flying = true
	_expect(Tactics.positioning_candidates(defender, units, cells, pathfinder, profile).is_empty(), "flying unit yields no positioning")
	defender.flying = false
	defender.hovering = true
	_expect(Tactics.positioning_candidates(defender, units, cells, pathfinder, profile).is_empty(), "hovering unit yields no positioning")
	defender.hovering = false
	defender.stance = "prone"
	_expect(Tactics.positioning_candidates(defender, units, cells, pathfinder, profile).is_empty(), "prone unit yields no positioning")
	defender.stance = "stand"
	_expect(Tactics.positioning_candidates(defender, [defender], cells, pathfinder, profile).is_empty(), "no hostile yields no positioning")
	defender.alive = false
	_expect(Tactics.positioning_candidates(defender, units, cells, pathfinder, profile).is_empty(), "dead unit yields no positioning")
	defender.alive = true

	# candidate shape and determinism — replay integrity depends on this
	var first := Tactics.positioning_candidates(defender, units, cells, pathfinder, profile)
	var second := Tactics.positioning_candidates(defender, units, cells, pathfinder, profile)
	var stable := first.size() == second.size()
	var keyed := true
	var scored := true
	for i in first.size():
		var candidate: Dictionary = first[i]
		if not candidate.has("score") or not candidate.has("tie"):
			keyed = false
		if not candidate.has("key"):
			scored = false
		if stable and String(candidate.get("tie", "")) != String(second[i].get("tie", "")):
			stable = false
	_expect(keyed, "every positioning candidate carries score and tie")
	_expect(scored, "every positioning candidate carries an action key")
	_expect(stable, "positioning candidates are deterministic across identical calls")

	# scoring hierarchy: tactics must outrank AIBehavior approach (50) and step (35)
	if not first.is_empty():
		var top := -1.0
		for candidate in first:
			top = maxf(top, float(candidate.get("score", 0.0)))
		_expect(top > 50.0, "tactical positioning outranks the approach fallback")
	else:
		_expect(false, "ranged engagement produced positioning candidates")

	_test_m03_golden_standoff(pathfinder)

func _test_m03_golden_standoff(pathfinder) -> void:
	print("  [12a] seeded ranged standoff golden cases (M03-001)")
	var scenario_seed := 1167583760
	var layout_rng := RandomNumberGenerator.new()
	layout_rng.seed = scenario_seed
	var lane_y := layout_rng.randi_range(2, 4)
	var item_db = root.get_node_or_null("ItemDB")
	var behavior = root.get_node_or_null("AIBehavior")
	_expect(
		item_db != null and behavior != null,
		"seeded standoff has ItemDB and AIBehavior authorities (M03-001)"
	)
	if item_db == null or behavior == null:
		return

	var standoff_cells := _m03_floor_cells(10, 8)
	var ranger_cell := Vector2i(1, lane_y)
	var target_cell := Vector2i(7, lane_y)
	var cover_cell := Vector2i(3, lane_y + 1)
	var cover_slot := Vector2i(2, lane_y + 1)
	standoff_cells[cover_cell] = {"type": Config.COVER, "z": 3}

	var ranger = _m03_unit(
		"STANDOFF-RANGER",
		1,
		301,
		ranger_cell,
		10,
		{"t1_pistol": 1}
	)
	var target = _m03_unit(
		"STANDOFF-TARGET",
		0,
		101,
		target_cell,
		10,
		{"t1_rifle": 1}
	)
	var standoff_units: Array = [ranger, target]
	var pistol: Dictionary = item_db.get_item("t1_pistol")
	var pistol_profile := {
		"cost": ActionCosts.weapon_cost(pistol),
		"range": int(pistol.get("range", 1)),
		"penetrates_cover": bool(pistol.get("penetrates_cover", false))
	}
	_expect(
		not pistol.is_empty()
		and String(pistol.get("category", "")) == "ranged"
		and pathfinder.cheb(ranger_cell, target_cell) > 1
		and pathfinder.cheb(ranger_cell, target_cell) <= int(pistol_profile["range"]),
		"seeded standoff arms a ranged Agent at legal standoff distance (M03-001)"
	)

	# Golden 1: open fire is legal, but a short route drops exposure while
	# retaining both the Take Cover cost and the pistol's attack reserve.
	var cover_candidates := Tactics.positioning_candidates(
		ranger,
		standoff_units,
		standoff_cells,
		pathfinder,
		pistol_profile
	)
	var cover_winner: Dictionary = cover_candidates[0] if not cover_candidates.is_empty() else {}
	var cover_value = cover_winner.get("value", {})
	var cover_path: Array = (
		cover_value.get("path", [])
		if cover_value is Dictionary
		else []
	)
	_expect(
		String(cover_winner.get("key", "")) == "seek_cover",
		"golden cover case chooses seek_cover over fire and approach (M03-001)"
	)
	_expect(
		cover_path.size() >= 2
		and Vector2i(cover_path.back()) == cover_slot
		and Vector2i(cover_value.get("cover", Config.INVALID_CELL)) == cover_cell,
		"golden cover route reaches the seeded protective face (M03-001)"
	)
	_expect(
		is_equal_approx(float(cover_winner.get("score", 0.0)), 79.0)
		and String(cover_winner.get("rationale", "")).contains("retain 7 AP"),
		"golden cover score preserves deterministic exposure and AP math (M03-001)"
	)

	var decision_rng_a := RandomNumberGenerator.new()
	decision_rng_a.seed = scenario_seed
	var decision_a: Dictionary = behavior.score_actions(
		ranger,
		standoff_units,
		standoff_cells,
		{},
		decision_rng_a
	)
	var decision_rng_b := RandomNumberGenerator.new()
	decision_rng_b.seed = scenario_seed
	var decision_b: Dictionary = behavior.score_actions(
		ranger,
		standoff_units,
		standoff_cells,
		{},
		decision_rng_b
	)
	_expect(
		String(decision_a.get("decision", "")) == "seek_cover"
		and String(decision_a.get("rationale", "")).begins_with("cover route"),
		"integrated AIBehavior emits the M03 cover signature in the seeded standoff (M03-001)"
	)
	_expect(
		String(decision_a.get("decision", "")) == String(decision_b.get("decision", ""))
		and String(decision_a.get("rationale", "")) == String(decision_b.get("rationale", ""))
		and is_equal_approx(
			float(decision_a.get("score", 0.0)),
			float(decision_b.get("score", -1.0))
		)
		and decision_a.get("seek_cover", {}) == decision_b.get("seek_cover", {}),
		"seeded standoff decision and route replay identically (M03-001)"
	)

	# Golden 2: a committed unit leans when its cover face opens a legal lane.
	ranger.cell = cover_slot
	ranger.taking_cover = true
	ranger.cover_cell = cover_cell
	ranger.lean = "none"
	ranger.ap = 10
	var committed := Tactics.positioning_candidates(
		ranger,
		standoff_units,
		standoff_cells,
		pathfinder,
		pistol_profile
	)
	var committed_winner: Dictionary = committed[0] if not committed.is_empty() else {}
	_expect(
		String(committed_winner.get("key", "")) == "lean_cover"
		and is_equal_approx(float(committed_winner.get("score", 0.0)), 96.0)
		and String(committed_winner.get("rationale", "")).contains("retain 9 AP"),
		"golden committed-cover case leans and retains attack AP (M03-001)"
	)

	# Golden 3: a second obstruction means leaning cannot create a lane, so
	# committed cover is released instead of trapping the Agent indefinitely.
	var lane_blocker := Vector2i(5, lane_y)
	standoff_cells[lane_blocker] = {"type": Config.COVER, "z": 3}
	var blocked := Tactics.positioning_candidates(
		ranger,
		standoff_units,
		standoff_cells,
		pathfinder,
		pistol_profile
	)
	var blocked_winner: Dictionary = blocked[0] if not blocked.is_empty() else {}
	_expect(
		String(blocked_winner.get("key", "")) == "leave_cover"
		and String(blocked_winner.get("rationale", "")).begins_with("cover has no legal attack lane"),
		"golden blocked-lane case releases committed cover (M03-001)"
	)

	# Golden 4: when a central obstacle blocks the current lane and there is no
	# immediate protective face, the deterministic winner is a simple flank.
	var flank_cells := _m03_floor_cells(10, 8)
	flank_cells[Vector2i(4, lane_y)] = {"type": Config.COVER, "z": 3}
	ranger.cell = ranger_cell
	ranger.taking_cover = false
	ranger.cover_cell = Config.INVALID_CELL
	ranger.lean = "none"
	ranger.ap = 10
	var flank_candidates := Tactics.positioning_candidates(
		ranger,
		standoff_units,
		flank_cells,
		pathfinder,
		pistol_profile
	)
	var flank_winner: Dictionary = flank_candidates[0] if not flank_candidates.is_empty() else {}
	var flank_path: Array = (
		flank_winner.get("value", [])
		if flank_winner.get("value", []) is Array
		else []
	)
	_expect(
		String(flank_winner.get("key", "")) == "flank"
		and String(flank_winner.get("rationale", "")).begins_with("simple flank"),
		"golden blocked-lane case chooses a simple flank (M03-001)"
	)
	_expect(
		flank_path.size() >= 2
		and pathfinder.has_los(
			Vector2i(flank_path.back()),
			target.cell,
			flank_cells,
			0,
			target.z
		)
		and ranger.ap - ActionCosts.path_cost(ranger, flank_path, flank_cells)
			>= int(pistol_profile["cost"]),
		"golden flank opens LOS without spending the attack reserve (M03-001)"
	)

	var flank_rng := RandomNumberGenerator.new()
	flank_rng.seed = scenario_seed + 1
	var flank_decision: Dictionary = behavior.score_actions(
		ranger,
		standoff_units,
		flank_cells,
		{},
		flank_rng
	)
	_expect(
		String(flank_decision.get("decision", "")) == "flank"
		and String(flank_decision.get("rationale", "")).begins_with("simple flank"),
		"integrated AIBehavior emits the M03 flank signature in the seeded standoff (M03-001)"
	)

func _m03_floor_cells(width: int, height: int) -> Dictionary:
	var cells: Dictionary = {}
	for x in range(width):
		for y in range(height):
			cells[Vector2i(x, y)] = {"type": Config.FLOOR, "z": 0}
	return cells

func _m03_unit(
	unit_name: String,
	team: int,
	unit_id: int,
	cell: Vector2i,
	ap: int,
	inventory: Dictionary
):
	var unit = UnitScript.new()
	unit.name = unit_name
	unit.alive = true
	unit.team = team
	unit.unit_id = unit_id
	unit.cell = cell
	unit.z = 0
	unit.hp = 10
	unit.max_hp = 10
	unit.ap = ap
	unit.max_ap = 10
	unit.stance = "stand"
	unit.inv = inventory.duplicate(true)
	return unit
