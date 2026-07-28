extends SceneTree

const World = preload("res://scripts/WorldBuilder.gd")
const Contract = preload("res://scripts/PayloadContract.gd")
const Config = preload("res://scripts/GameConfig.gd")
const ActionCosts = preload("res://scripts/ActionEconomy.gd")
const MovementRules = preload("res://scripts/MovementContext.gd")
const Maneuvers = preload("res://scripts/ManeuverState.gd")
const PathScript = preload("res://scripts/Pathfinder.gd")
const UnitScript = preload("res://scripts/Unit.gd")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_seeded_generation()
	_test_payload_contract()
	_test_action_economy()
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
	_expect(main.tactical_ui.get_node_or_null("EventPanel") != null, "ephemeral tactical feed is not separated from persistent squad status")
	_expect(main.tactical_ui.get_node_or_null("ActionDock") != null, "responsive bottom action dock is missing")
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
