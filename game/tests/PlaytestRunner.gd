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
	await _test_full_combat_micro()
	await _test_extraction_paths()
	await _test_turn_cycle_integrity()
	await _test_busy_lock_during_ai()
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

func _test_full_combat_micro() -> void:
	print("  [7] combat micro-loop")
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
	print("  [8] extraction paths")
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
	print("  [9] turn cycle integrity")
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
	print("  [10] busy lock during AI flag")
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
