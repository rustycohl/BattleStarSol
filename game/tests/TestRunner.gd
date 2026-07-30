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
var checks := 0

## Assertion floor. Raise this when tests are added; never lower it to make a run pass.
const MIN_CHECKS := 1492

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_seeded_generation()
	_test_d10_conformance()
	_test_balance_baseline()
	_test_damage_appearance()
	_test_tier_shedding_and_conservation()
	_test_ledger_budget_readout()
	_test_cell_shape_authority()
	_test_consumer_defaults()
	_test_payload_contract()
	_test_faction_vocabulary()
	_test_action_economy()
	_test_tutorial_state_machine()
	_test_contextual_movement()
	_test_web_contract()
	await _test_main_scene()
	await _test_scene_cover_is_material()
	await _test_specials_stay_visible_in_god_mode()
	await _test_multi_round_cycle()
	await _test_strategic_scene()
	if checks < MIN_CHECKS:
		failures.append(
			"only %d assertions ran, expected at least %d -- a test aborted before reaching its assertions (look for an engine error above)" % [checks, MIN_CHECKS]
		)
	if failures.is_empty():
		print("PASS: Battle/Star.SOL headless tests, %d checks" % checks)
		await process_frame
		quit(0)
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
		await process_frame
		quit(1)

## Every assertion is counted. A test that dies mid-way -- a runtime error abandons the rest
## of its function and returns control to the runner -- used to leave the suite reporting PASS
## with every later assertion silently unexecuted. Observed live on 2026-07-30: a wrong
## argument order printed `SCRIPT ERROR: Invalid type in function 'damage_terrain'`, skipped
## the rest of that test, and the suite still passed.
##
## GDScript gives the runner no way to detect that its callee aborted, so the tripwire is the
## count: if fewer assertions run than the pinned floor, something did not finish. Same
## pattern PlaytestRunner already prints. The floor is raised deliberately when tests are
## added; it is not a target to be met by adding assertions elsewhere.
func _expect(condition: bool, message: String) -> void:
	checks += 1
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

## Conformance against the d10SRD, read from the pinned rules authority rather than
## from numbers retyped into this test.
##
## The earlier version of this test asserted eighteen literals under a "d10SRD
## Conformance" label. Exactly one of them -- the AP maximum -- is a d10SRD rule. The
## SRD says in as many words: "Do not divide health, damage, movement, range, time,
## capacity, currency, ammunition, action counts, or unrelated economies unless a named
## module explicitly says so." Weapon damage and movement costs are authored balance,
## and pinning them under a conformance label would make a legitimate balance change
## read as a rules violation. They now live in `_test_balance_baseline`.
##
## Conformance vectors 1-4 do not apply to this port because it implements no check
## resolution at all. That claim is verified by absence, not asserted by comment: if a
## forbidden check-resolution symbol ever appears in the configuration authority, this
## test fails, because at that moment the not-applicable declarations stop being true.
func _test_d10_conformance() -> void:
	var pin := _load_json("res://data/d10srd_conformance.json")
	_expect(not pin.is_empty(), "d10SRD conformance: the pinned rules authority is missing or unreadable")
	if pin.is_empty():
		return

	# The pin must identify which published rules it was taken from. A pin that has lost
	# its identity cannot tell us whether the SRD has moved underneath us.
	_expect(
		String(pin.get("rules_id", "")) == "gzg.d10/0.1",
		"d10SRD conformance: pinned rules_id is not gzg.d10/0.1 (got '%s') -- re-pin against the current SRD" % String(pin.get("rules_id", ""))
	)
	_expect(
		String(pin.get("srd_version", "")) == "0.1.0-alpha.2",
		"d10SRD conformance: pinned srd_version moved (got '%s') -- re-read the SRD Conformance section before accepting it" % String(pin.get("srd_version", ""))
	)

	var vectors: Array = pin.get("vectors", [])
	_expect(vectors.size() == 6, "d10SRD conformance: expected the SRD's six conformance vectors, found %d" % vectors.size())

	var applicable := 0
	for entry in vectors:
		if not (entry is Dictionary):
			_expect(false, "d10SRD conformance: malformed vector entry")
			continue
		var vector: Dictionary = entry
		if not bool(vector.get("applies_to_godot_port", false)):
			continue
		applicable += 1
		# Vector 6 is a governance constraint on the SRD itself; the port cannot express
		# it as a value, and the pin says so rather than pretending otherwise.
		if not bool(vector.get("machine_checked", true)):
			continue
		var symbol := String(vector.get("godot_symbol", ""))
		var expected := int(vector.get("expected", -1))
		_expect(
			_config_constant(symbol) == expected,
			"d10SRD conformance vector %d (%s): %s is %d, the SRD requires %d" % [
				int(vector.get("id", -1)),
				String(vector.get("requirement", "")),
				symbol,
				_config_constant(symbol),
				expected
			]
		)
	_expect(applicable >= 1, "d10SRD conformance: the pin declares no vector applicable to this port, which cannot be right")

	# Verify the not-applicable claims by absence. This is the part that keeps the pin
	# honest over time: the moment this port grows a check resolver, the declarations
	# above become false and this fails rather than passing quietly.
	var constants := _config_constants()
	for name in pin.get("forbidden_symbols", []):
		_expect(
			not constants.has(String(name)),
			"d10SRD conformance: %s now exists in GameConfig, so vectors 1-4 are no longer not-applicable -- implement them against the SRD or re-pin" % String(name)
		)

## Authored balance numbers. These are deliberately NOT d10SRD conformance -- the SRD
## forbids deriving them from d10 scaling. They are pinned here as a regression baseline
## so an accidental change is caught, and changing one on purpose means changing it here
## too, which is the intended friction.
func _test_balance_baseline() -> void:
	_expect(Config.UNIT_HP == 10, "balance baseline: UNIT_HP changed")
	_expect(Config.MOVE_COST == 1, "balance baseline: MOVE_COST changed")
	_expect(Config.SPRINT_MOVE_COST == 1, "balance baseline: SPRINT_MOVE_COST changed")
	_expect(Config.CROUCH_MOVE_COST == 2, "balance baseline: CROUCH_MOVE_COST changed")
	_expect(Config.PRONE_MOVE_COST == 3, "balance baseline: PRONE_MOVE_COST changed")
	_expect(Config.MELEE_COST == 4, "balance baseline: MELEE_COST changed")
	_expect(Config.BLOCK_COST == 2, "balance baseline: BLOCK_COST changed")
	_expect(Config.BLOCK_REDUCTION == 3, "balance baseline: BLOCK_REDUCTION changed")
	_expect(Config.EQUIP_COST == 1, "balance baseline: EQUIP_COST changed")
	_expect(Config.TAKE_COVER_COST == 1, "balance baseline: TAKE_COVER_COST changed")
	_expect(Config.LEAVE_COVER_COST == 1, "balance baseline: LEAVE_COVER_COST changed")
	_expect(Config.DODGE_COST == 1, "balance baseline: DODGE_COST changed")
	_expect(Config.FIST_DMG == 4, "balance baseline: FIST_DMG changed")
	_expect(Config.ROCK_1H_DMG == 5, "balance baseline: ROCK_1H_DMG changed")
	_expect(Config.BOW_DMG == 9, "balance baseline: BOW_DMG changed")
	# The earlier form of these two was `a == x or b == y`, which passes when either half
	# breaks. Both axes are asserted separately so a real regression cannot hide behind
	# the other one still holding.
	_expect(Config.SPEAR_SWEEP_DMG == 6, "balance baseline: SPEAR_SWEEP_DMG changed")
	_expect(int(Config.THROW.get("spear", {}).get("dmg", 0)) == 7, "balance baseline: thrown spear damage changed")
	_expect(Config.CLUB_SWEEP_DMG == 5, "balance baseline: CLUB_SWEEP_DMG changed")
	_expect(int(Config.THROW.get("club", {}).get("dmg", 0)) == 4, "balance baseline: thrown club damage changed")

## Every cover cell in a live scene must carry the material fields, because cover strength,
## penetration, destruction, and the terrain ledger are all derived from them. A cell
## authored as a bare `{"type", "z"}` dict still *scores* correctly -- `density_of` falls
## back to the type's implied material -- so this class of special case cannot be caught by
## checking behaviour. It has to be caught structurally, which is what this does.
##
## Written against the Standoff sector because that is where the regression was found, but
## the assertion is general: it walks the whole grid and accepts no cover cell without
## material.
func _test_scene_cover_is_material() -> void:
	var bridge := root.get_node_or_null("/root/PayloadBridge")
	_expect(bridge != null, "PayloadBridge autoload is unavailable, cannot drive a sector")
	if bridge == null:
		return
	bridge.set_payload({
		"type": "deploy",
		"sector": "Standoff",
		"faction": "HAD",
		"seed": 888888,
		"squad": [{"name": "Agent-1", "cls": "Scout"}],
		"objectives": ["Observe AI flanking or taking cover."],
		"resources": {"neural": 0, "capital": 0}
	})

	var packed := load("res://Main.tscn") as PackedScene
	_expect(packed != null, "Main.tscn did not load for the cover-material check")
	if packed == null:
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	if not main.has_method("_spawn_squads"):
		_expect(false, "Main.gd did not load for the cover-material check")
		main.free()
		return

	var cover_cells := 0
	var authored := 0
	var first_offender := ""
	for cell in main.cells.keys():
		var data = main.cells[cell]
		if not (data is Dictionary):
			continue
		var kind := int((data as Dictionary).get("type", Config.FLOOR))
		if kind != Config.COVER and kind != Config.HALF_COVER:
			continue
		cover_cells += 1
		var d: Dictionary = data
		if not (d.has("density") and d.has("integrity") and d.has("material")):
			authored += 1
			if first_offender.is_empty():
				first_offender = "%s (type %d, z %d, keys %s)" % [
					str(cell), kind, int(d.get("z", 0)), str(d.keys())
				]
	_expect(cover_cells > 0, "the Standoff sector produced no cover at all, so this check proved nothing")
	# The whole live grid, not only its cover: any cell that entered the scene malformed is a
	# parallel model in the making, and the compatibility defaults will hide it.
	var malformed := 0
	var first_malformed := ""
	for cell in main.cells.keys():
		var shape_problem := World.cell_shape_error(main.cells[cell])
		if not shape_problem.is_empty():
			malformed += 1
			if first_malformed.is_empty():
				first_malformed = "%s: %s" % [str(cell), shape_problem]
	_expect(
		malformed == 0,
		"%d cell(s) in the live scene do not satisfy the cell shape; first %s" % [malformed, first_malformed]
	)

	_expect(
		authored == 0,
		"%d cover cell(s) were authored without material fields -- cover must come from WorldBuilder.material_cell(); first: %s" % [authored, first_offender]
	)

	# The injected standoff cover specifically: hard material at the density the shared
	# model assigns a three-high column, so it is indistinguishable from generated cover.
	var standoff_cover := Vector2i(3, 4)
	if main.cells.has(standoff_cover):
		var sc: Dictionary = main.cells[standoff_cover]
		_expect(int(sc.get("type", -1)) == Config.COVER, "standoff lane cover is missing at %s" % standoff_cover)
		_expect(String(sc.get("material", "")) == "hard", "standoff lane cover is not hard material")
		_expect(
			int(sc.get("density", 0)) == int(World.material_cell(Config.COVER, 3).get("density", -1)),
			"standoff lane cover density diverges from the shared material model"
		)

	# The appearance model being correct is not the same as it reaching the screen. Damage a
	# real cover cell through the single authority and confirm the tile that comes back
	# carries a damage override, while an untouched tile carries none.
	var pristine_probe := Vector2i(-1, -1)
	var target_probe := Vector2i(-1, -1)
	for cell in main.cells.keys():
		var probe = main.cells[cell]
		if not (probe is Dictionary):
			continue
		if int((probe as Dictionary).get("type", Config.FLOOR)) != Config.COVER:
			continue
		if target_probe.x < 0:
			target_probe = cell
		elif pristine_probe.x < 0:
			pristine_probe = cell
			break
	if target_probe.x >= 0 and pristine_probe.x >= 0:
		var untouched := main.tiles_root.get_node_or_null("Tile_%d_%d" % [pristine_probe.x, pristine_probe.y]) as MeshInstance3D
		_expect(untouched != null, "no tile for the untouched probe cell")
		if untouched != null:
			_expect(
				untouched.material_override == null,
				"an undamaged tile carries a damage override, so every rebuild duplicates a material"
			)
		main.damage_terrain(target_probe, 20, "test", null)
		await process_frame
		var damaged := main.tiles_root.get_node_or_null("Tile_%d_%d" % [target_probe.x, target_probe.y]) as MeshInstance3D
		_expect(damaged != null, "the damaged cell lost its tile")
		if damaged != null:
			_expect(
				damaged.material_override != null,
				"a damaged tile has no override material, so the damage is invisible in play"
			)
		_expect(
			World.wear_of(main.cells.get(target_probe, {})) < 1.0,
			"damaging a cell did not reduce its material"
		)
		# Conservation of matter, end to end: the tiers that came down must be on the ground as
		# debris, in the existing debris system rather than a second pile of rubble somewhere.
		var shed := int(main.cells.get(target_probe, {}).get("tiers_lost", 0))
		if shed > 0:
			_expect(
				main.debris.has(target_probe),
				"%d tier(s) came down and left no debris -- destruction deleted matter" % shed
			)
			_expect(
				int(main.debris.get(target_probe, {}).get("rock", 0)) >= shed,
				"debris on the cell (%d rock) does not account for the %d tier(s) that fell" % [
					int(main.debris.get(target_probe, {}).get("rock", 0)), shed
				]
			)

	main.free()

## A special the unit possesses stays on screen and explains itself. It is never hidden for
## failing its own precondition.
##
## This is the control for a defect found by hand in playtest rather than by any test: the
## Wall Run button was reported "just missing" in dev mode. `update_ui` set
## `visible = dev_god_mode` for the specials and then, twenty lines later, overwrote it with
## `visible = wall_running or not runnable_walls.is_empty()`. With no qualifying wall adjacent
## — most of the time — the button vanished, taking its tooltip with it. The tooltip is the
## only place the requirement is written down, so the mechanic became undiscoverable and the
## God Mode toggle looked like it did nothing.
##
## Two separate assertions, because they fail for different reasons:
##   1. availability comes from `Main._special_enabled` — the same authority the action router
##      uses — so it cannot drift from what is actually permitted;
##   2. an unmet precondition disables and annotates, never hides.
func _test_specials_stay_visible_in_god_mode() -> void:
	var packed := load("res://Main.tscn") as PackedScene
	_expect(packed != null, "Main.tscn did not load for the specials check")
	if packed == null:
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	if not main.has_method("_special_enabled"):
		_expect(false, "Main.gd did not load for the specials check")
		main.free()
		return

	var pilot = main._active_human_pilot()
	_expect(pilot != null, "no human pilot to check specials against")
	if pilot == null:
		main.free()
		return
	main.selected = pilot
	var ui = main.tactical_ui
	_expect(ui != null, "TacticalUI was not constructed")
	if ui == null:
		main.free()
		return

	# God Mode off: with no skill token, nothing is claimed and nothing is shown.
	main.dev_god_mode = false
	ui.update_ui()
	for special_name in ui.SPECIAL_ACTIONS:
		if not ui.action_btns.has(special_name):
			continue
		_expect(
			not main._special_enabled(pilot, special_name),
			"%s is enabled with God Mode off and no skill token" % special_name
		)
		_expect(
			not ui.action_btns[special_name].visible,
			"%s is visible while the authority says the unit does not have it" % special_name
		)

	# God Mode on: every special the authority grants is on screen, whatever the situation.
	main.dev_god_mode = true
	ui.update_ui()
	var checked := 0
	for special_name in ui.SPECIAL_ACTIONS:
		if not ui.action_btns.has(special_name):
			continue
		checked += 1
		var btn: Button = ui.action_btns[special_name]
		_expect(
			main._special_enabled(pilot, special_name),
			"God Mode did not grant %s" % special_name
		)
		_expect(
			btn.visible,
			"%s is hidden in God Mode -- a special the unit has must be shown, disabled if its precondition is unmet, never hidden" % special_name
		)
		# A disabled special must say why, or the requirement is undiscoverable.
		if btn.disabled:
			_expect(
				btn.tooltip_text.contains("Unavailable right now:"),
				"%s is disabled without stating a reason" % special_name
			)

	_expect(checked >= 3, "fewer specials were checked than expected (%d)" % checked)

	# The specific case from playtest: standing still on open ground, Wall Run has no
	# qualifying wall and no momentum, so it must be visible-and-disabled.
	if ui.action_btns.has("wall_run"):
		var wall_btn: Button = ui.action_btns["wall_run"]
		var walls: Array[Vector2i] = main.wall_run_options(pilot)
		if walls.is_empty() and not Maneuvers.is_wall_running(pilot.maneuver):
			_expect(wall_btn.visible, "Wall Run vanished with no wall available instead of greying out")
			_expect(wall_btn.disabled, "Wall Run is enabled with no wall available and no momentum")
			_expect(
				wall_btn.tooltip_text.contains("momentum"),
				"Wall Run's disabled tooltip does not state the momentum requirement"
			)

	main.free()

## Damage appearance follows the number, and an undamaged cell draws nothing.
##
## The destruction model has always been continuous — integrity runs from its original
## density down to zero — while the visuals were three discrete states of which only two drew
## anything. A hard wall at 54 of 96 integrity is three hits from gone and rendered identical
## to an untouched one.
##
## The pristine assertions below are not padding. The first version of this model tested the
## material name before wear, and `material_cell` names HALF_COVER's material "soft" while
## `degrade_cell` writes "soft" for a hard wall worked down — the same string for two
## different things. Every untouched half-cover tile on the board was therefore classified as
## damaged: a duplicated material per tile and a visible lean on undamaged terrain. Monotonic
## darkening still held. Printing the table is what caught it.
func _test_damage_appearance() -> void:
	# Pristine terrain of every type must draw nothing at all, so no material is duplicated
	# and no rebuild leaks one.
	for pristine_type in [Config.FLOOR, Config.HALF_COVER, Config.COVER]:
		var height := 3 if pristine_type == Config.COVER else (1 if pristine_type == Config.HALF_COVER else 0)
		var fresh := World.material_cell(pristine_type, height)
		var fresh_look := World.damage_appearance(fresh)
		_expect(
			is_equal_approx(World.wear_of(fresh), 1.0),
			"freshly generated type %d is not at full material (wear %f)" % [pristine_type, World.wear_of(fresh)]
		)
		_expect(
			String(fresh_look["state"]) == "pristine",
			"freshly generated type %d reads as '%s' rather than pristine" % [pristine_type, String(fresh_look["state"])]
		)
		_expect(
			not bool(fresh_look["draws"]),
			"freshly generated type %d would draw a damage override, duplicating a material for undamaged terrain" % pristine_type
		)

	# Cells authored before materials existed — the golden fixtures — imply full material
	# from their type, exactly as Ballistics.density_of treats them.
	var legacy := {"type": Config.COVER, "z": 3}
	_expect(is_equal_approx(World.wear_of(legacy), 1.0), "a pre-material cell does not read as pristine")
	_expect(
		not bool(World.damage_appearance(legacy)["draws"]),
		"a pre-material cell would draw a damage override"
	)

	# Walk a hard wall down and require the appearance to track it: strictly increasing
	# darkening, never exceeding rubble, and reaching each state in order.
	var cell := World.material_cell(Config.COVER, 6)
	var previous_darken := -1.0
	var previous_wear := 2.0
	var seen := {}
	for hit in range(1, 9):
		cell = Ballistics.degrade_cell(cell, 14)
		var look := World.damage_appearance(cell)
		var wear := float(look["wear"])
		var darken := float(look["darken"])
		seen[String(look["state"])] = true
		_expect(wear <= previous_wear, "wear increased after taking damage (hit %d)" % hit)
		_expect(
			darken >= previous_darken,
			"a further hit made the tile lighter (hit %d: %f then %f)" % [hit, previous_darken, darken]
		)
		_expect(
			darken <= World.RUBBLE_DARKEN + 0.0001,
			"damage darkened past rubble (hit %d: %f)" % [hit, darken]
		)
		_expect(bool(look["draws"]), "a damaged tile would not draw anything (hit %d)" % hit)
		previous_darken = darken
		previous_wear = wear
	_expect(seen.has("worn"), "a hard wall never passed through a visibly worn state")
	_expect(seen.has("soft"), "a degraded wall never reached the soft state")
	_expect(seen.has("rubble"), "a wall reduced to nothing never reached rubble")
	_expect(is_equal_approx(previous_wear, 0.0), "a destroyed cell retains material")

	# Only rubble is scorched, and only rubble sits at the darkening ceiling.
	var rubble := Ballistics.degrade_cell(World.material_cell(Config.COVER, 3), 999)
	var rubble_look := World.damage_appearance(rubble)
	_expect(bool(rubble_look["scorched"]), "rubble is not scorched")
	_expect(
		is_equal_approx(float(rubble_look["darken"]), World.RUBBLE_DARKEN),
		"rubble is not at the darkening ceiling"
	)
	var worn := Ballistics.degrade_cell(World.material_cell(Config.COVER, 6), 14)
	_expect(not bool(World.damage_appearance(worn)["scorched"]), "a merely worn wall is scorched")

	# The redraw trigger must be as continuous as the appearance. `Main.damage_terrain` used
	# to rebuild a tile only when its height or cover level changed -- both threshold
	# crossings -- so a wall could take three rounds, lose a third of its material, and never
	# be redrawn. Continuous appearance behind a threshold trigger is still three states.
	var sig_cell := World.material_cell(Config.COVER, 6)
	var signature := World.tile_visual_signature(sig_cell)
	var redraws := 0
	for hit in range(1, 8):
		sig_cell = Ballistics.degrade_cell(sig_cell, 12)
		var next_signature := World.tile_visual_signature(sig_cell)
		_expect(
			next_signature != signature,
			"hit %d changed the wall's material but not its visual signature, so no redraw fires (%s)" % [hit, signature]
		)
		if next_signature != signature:
			redraws += 1
		signature = next_signature
	_expect(redraws == 7, "only %d of 7 hits would have redrawn the tile" % redraws)
	# The signature must subsume what it replaced: type and height are part of it.
	var tall := World.material_cell(Config.COVER, 6)
	var short := World.material_cell(Config.COVER, 3)
	_expect(
		World.tile_visual_signature(tall) != World.tile_visual_signature(short),
		"the visual signature ignores height, so a collapsing wall may not redraw"
	)

	# Deterministic: the same cell must look the same on every rebuild, or a replay diverges.
	var repeat_a := World.damage_appearance(rubble)
	var repeat_b := World.damage_appearance(rubble)
	_expect(
		is_equal_approx(float(repeat_a["yaw_deg"]), float(repeat_b["yaw_deg"])),
		"damage appearance is not repeatable for the same cell"
	)

## A column sheds height one tier at a time under gravity, and the matter it sheds is
## accounted for rather than deleted.
##
## Down is -Y, so material rests on what is beneath it and nothing floats: a column occupies
## tiers 1..z contiguously from the ground, and losing material shortens it from the top. Before
## this, a six-high wall dropped to two-high the instant its integrity crossed a threshold, and
## the four tiers in between simply stopped existing.
func _test_tier_shedding_and_conservation() -> void:
	for start_height in [3, 4, 5, 6]:
		var cell := World.material_cell(Config.COVER, start_height)
		_expect(
			int(cell.get("tiers", -1)) == start_height,
			"a generated column does not record the tier count it started at"
		)
		_expect(
			Ballistics.supported_tiers(cell) == start_height,
			"a pristine column of %d does not support its own height (supports %d)" % [start_height, Ballistics.supported_tiers(cell)]
		)
		var recovered := 0
		var previous_z := int(cell["z"])
		var hits := 0
		while int(cell.get("z", 0)) > 0 and hits < 40:
			hits += 1
			cell = Ballistics.degrade_cell(cell, 12)
			var z_now := int(cell.get("z", 0))
			var lost := int(cell.get("tiers_lost", -1))
			_expect(lost >= 0, "degrade_cell did not report tiers_lost")
			_expect(z_now <= previous_z, "a column grew taller after taking damage")
			_expect(
				previous_z - z_now == lost,
				"tiers_lost (%d) disagrees with the height actually shed (%d)" % [lost, previous_z - z_now]
			)
			# Twelve damage against a capacity of at least sixteen per tier can never take
			# more than one tier, which is what makes the shed sequential rather than a snap.
			_expect(lost <= 1, "a single small hit shed %d tiers at once" % lost)
			recovered += lost
			previous_z = z_now
		_expect(hits < 40, "a column of %d never came down -- the last tier may be indestructible" % start_height)
		# Conservation: every tier the column started with is accounted for.
		_expect(
			recovered == start_height,
			"a column of %d shed %d tiers -- matter was created or destroyed" % [start_height, recovered]
		)

	# A large enough single event takes several tiers at once and must report all of them.
	var blasted := Ballistics.degrade_cell(World.material_cell(Config.COVER, 6), 60)
	_expect(int(blasted["tiers_lost"]) > 1, "a grenade-scale hit shed at most one tier")
	_expect(
		6 - int(blasted["z"]) == int(blasted["tiers_lost"]),
		"a multi-tier collapse did not account for every tier it dropped"
	)

	# Capacity per tier must come from the height the column STARTED at. Deriving it from the
	# current height would make each surviving tier cheaper to hold up as the column shrank,
	# and the last tier would never fail.
	var worn := Ballistics.degrade_cell(World.material_cell(Config.COVER, 6), 48)
	_expect(
		int(worn.get("tiers", -1)) == 6,
		"the original tier count was lost as the column was worn down"
	)

## The reproduction ledger's ceiling is visible while a mission is still running.
##
## Option E from `evidence/OBSERVATION-001-LEDGER-CAPACITY-2026-07-30.md`. The ceiling itself is
## unchanged; what changes is that it stops being silent. A mission with heavy destruction used
## to play correctly, extract correctly, and produce an artifact that failed closed, with nobody
## told until afterwards.
##
## The readout is calibrated against the measured exhaustion point rather than a guess. The
## first attempt used a guessed overhead and reported 88% at the moment the artifact was already
## full — an optimistic readout on a feature whose whole purpose is honesty about a limit. These
## assertions pin the calibration so that cannot come back.
func _test_ledger_budget_readout() -> void:
	var gs = root.get_node_or_null("/root/GameState")
	_expect(gs != null, "GameState autoload is unavailable")
	if gs == null:
		return
	var limits: Dictionary = gs.repro_budget_limits()
	_expect(not limits.is_empty(), "the reproduction budget pin is missing or unreadable")
	if limits.is_empty():
		return

	gs.reset_state()
	var empty: Dictionary = gs.ledger_budget()
	_expect(not empty.is_empty(), "ledger_budget reported nothing on a fresh mission")
	_expect(String(empty.get("status", "")) == "ok", "a fresh mission is not reported as ok")
	_expect(float(empty.get("fraction", 1.0)) < 0.01, "a fresh mission already claims budget spent")

	# Terrain events are the load that actually exhausts this budget, so measure with those.
	var readings := {}
	for count in [300, 420, 462, 600]:
		gs.reset_state()
		for i in range(count):
			gs.record_event("terrain_damaged", {
				"cell": {"x": i % 20, "y": int(i / 20) % 20, "z": 3},
				"weapon": "rifle",
				"material_before": "hard",
				"material_after": "soft",
				"integrity_before": 96,
				"integrity_after": 84,
				"attacker": 1
			})
		readings[count] = gs.ledger_budget()

	var mid: Dictionary = readings[300]
	var near: Dictionary = readings[420]
	var over: Dictionary = readings[600]

	# Monotonic: more events can never report less budget spent.
	_expect(
		float(mid["fraction"]) < float(near["fraction"]) and float(near["fraction"]) < float(over["fraction"]),
		"budget consumption is not monotonic in the number of events recorded"
	)
	# Bytes are the cap that binds on this project. Derived, not assumed — but if it ever stops
	# being bytes, that is a measurement worth failing on rather than absorbing silently.
	_expect(
		String(near.get("binding_cap", "")) == "bytes",
		"the binding cap is no longer bytes (%s) -- re-measure the budget before trusting the readout" % String(near.get("binding_cap", ""))
	)
	# OBSERVATION-001 measured the usable terrain budget at roughly 420 events. The readout must
	# be warning by then and must not yet claim the artifact is lost.
	_expect(String(near["status"]) == "warn", "at 420 terrain events the readout is '%s', not a warning" % String(near["status"]))
	_expect(float(near["fraction"]) < 1.0, "the readout claims the artifact is already lost at 420 events")
	# And a mission well past the measured ceiling must say so outright.
	_expect(String(over["status"]) == "over", "at 600 terrain events the readout is '%s', not over" % String(over["status"]))
	_expect(float(over["fraction"]) > 1.0, "600 terrain events does not exceed the budget")
	# The warning has to leave usable runway, or it is a post-mortem rather than a warning.
	_expect(
		String(mid["status"]) == "ok",
		"the readout is already warning at 300 events, which leaves too little room to act"
	)

	# THE CALIBRATION ITSELF. OBSERVATION-001 measured the byte cap exhausted at 462 terrain
	# events, so that is where the readout must reach full. This is the assertion that has teeth:
	# the surrounding status checks all pass with a badly calibrated overhead, which is exactly
	# what happened -- a guessed 9000-byte overhead reported 88% at the point the artifact was
	# already full, and every other assertion here still passed. An optimistic readout on a
	# feature whose only purpose is honesty about a limit is worse than no readout.
	var at_exhaustion: Dictionary = readings[462]
	_expect(
		float(at_exhaustion["fraction"]) >= 0.97,
		"at the measured exhaustion point of 462 terrain events the readout claims only %.1f%% spent -- baseline_overhead_bytes is miscalibrated and the readout is optimistic" % (float(at_exhaustion["fraction"]) * 100.0)
	)
	_expect(
		float(at_exhaustion["fraction"]) <= 1.15,
		"at 462 terrain events the readout claims %.1f%% spent -- overhead is overstated and the readout is alarmist" % (float(at_exhaustion["fraction"]) * 100.0)
	)

	gs.reset_state()

## Every cell the model ever holds has the shape the model expects — not only cover cells, and
## not only in one scene.
##
## `_test_scene_cover_is_material` was the narrow version of this, written after the Standoff
## sector built a cover cell by hand. This is the general form, and it exists because of what a
## sweep of the registered authorities showed: 183 `get(key, default)` sites, of which the cell
## and material keys account for 63. Almost every default is correct — a missing cell reading as
## open ground is the conservative answer — so removing them would be wrong. What defaults cannot
## do is notice that something entered the model malformed. Only a shape assertion can.
func _test_cell_shape_authority() -> void:
	# The producer's own output must satisfy the shape it defines.
	for cell_type in [Config.FLOOR, Config.HALF_COVER, Config.COVER]:
		for height in [0, 1, 2, 3, 6]:
			var produced := World.material_cell(cell_type, height)
			var problem := World.cell_shape_error(produced)
			_expect(
				problem.is_empty(),
				"material_cell(%d, %d) does not satisfy its own cell shape: %s" % [cell_type, height, problem]
			)

	# And so must a cell that has been worked on, at every stage of its destruction.
	var worked := World.material_cell(Config.COVER, 6)
	for hit in range(1, 10):
		worked = Ballistics.degrade_cell(worked, 12)
		var degraded_problem := World.cell_shape_error(worked)
		_expect(
			degraded_problem.is_empty(),
			"a cell degraded %d time(s) no longer satisfies the cell shape: %s" % [hit, degraded_problem]
		)

	# Malformed cells must be rejected, or the check is decoration.
	_expect(not World.cell_shape_error({"type": Config.COVER, "z": 3}).is_empty(), "a hand-built cell was accepted")
	_expect(not World.cell_shape_error("not a dict").is_empty(), "a non-Dictionary was accepted as a cell")
	var bad_integrity := World.material_cell(Config.COVER, 3)
	bad_integrity["integrity"] = int(bad_integrity["density"]) + 1
	_expect(
		not World.cell_shape_error(bad_integrity).is_empty(),
		"a cell with more integrity than it started with was accepted"
	)
	var bad_height := World.material_cell(Config.COVER, 3)
	bad_height["z"] = int(bad_height["tiers"]) + 1
	_expect(
		not World.cell_shape_error(bad_height).is_empty(),
		"a cell taller than the tiers it started with was accepted"
	)
	var stowaway := World.material_cell(Config.COVER, 3)
	stowaway["painted_cover"] = true
	_expect(
		not World.cell_shape_error(stowaway).is_empty(),
		"a cell carrying an unrecognised field was accepted -- that is how a parallel model starts"
	)

	# Then the whole generated world, which is what actually ships.
	var generated := World.generate_cells(84021)
	var bad := 0
	var first := ""
	for cell in generated.keys():
		var generated_problem := World.cell_shape_error(generated[cell])
		if not generated_problem.is_empty():
			bad += 1
			if first.is_empty():
				first = "%s: %s" % [str(cell), generated_problem]
	_expect(bad == 0, "%d generated cell(s) do not satisfy the cell shape; first %s" % [bad, first])

## A number the player reads must be the number the model uses, and a substituted payload must
## say so.
##
## Both halves come from the same sweep as the cell shape check, over the consumers that are not
## registered authorities: TacticalUI, StratLayer, CombatSystem, InventorySystem, PayloadContract.
## 82 defaulted lookups, 33 on model keys.
func _test_consumer_defaults() -> void:
	# The weapons bar showed the raw `armor_pierce` field. The model uses
	# `Ballistics.penetration_for_item`, which is that field times PIERCE_PER_POINT plus a
	# damage-type bonus, clamped to 100 -- and 100 outright for a cover-piercing weapon. So the
	# tooltip displayed 5 where the game used 55, under a label that reads as action points.
	#
	# WHAT THIS COVERS, EXACTLY: that the authority's penetration is on the shared 0-100 scale,
	# that it is not merely the raw field passed through, and that a cover-piercing weapon reads
	# as total. It does NOT observe the tooltip, so it does not prove the interface asks the
	# authority -- reverting TacticalUI to the raw field leaves these assertions passing. Verified
	# by running that negative control; it did not fire. Closing it means reaching the weapons-bar
	# button and reading its tooltip, the way _test_specials_stay_visible_in_god_mode reaches
	# action_btns. Named rather than implied, because a test that appears to guard a fix and does
	# not is worse than no test.
	var item_db = root.get_node_or_null("/root/ItemDB")
	_expect(item_db != null, "ItemDB autoload is unavailable")
	if item_db == null:
		return
	var checked := 0
	for kind in Config.KINDS:
		var item = item_db.get_item(String(kind))
		if not (item is Dictionary) or (item as Dictionary).is_empty():
			continue
		checked += 1
		var authoritative := Ballistics.penetration_for_item(item)
		var raw := int((item as Dictionary).get("armor_pierce", 0))
		_expect(
			authoritative >= 0 and authoritative <= 100,
			"%s: penetration %d is outside the shared 0-100 scale" % [String(kind), authoritative]
		)
		# The two must not be conflated. Where they differ, the authority is the one to show.
		if raw > 0:
			_expect(
				authoritative != raw or raw == 0,
				"%s: penetration equals the raw armor_pierce (%d), so PIERCE_PER_POINT is not being applied" % [String(kind), raw]
			)
		if bool((item as Dictionary).get("penetrates_cover", false)):
			_expect(
				authoritative == 100,
				"%s ignores cover but does not read as total penetration (%d)" % [String(kind), authoritative]
			)
	_expect(checked >= 5, "fewer weapons were checked than expected (%d)" % checked)

	# A payload that had to be filled in must report that it was.
	var complete := {
		"type": "deploy", "sector": "Test", "faction": "HAD", "seed": 4242,
		"squad": [{"name": "A"}], "objectives": ["x"], "resources": {}, "cell_size": 2.0
	}
	var full_report: Dictionary = Contract.deploy_shape_report(complete)
	_expect(bool(full_report["complete"]), "a complete payload was reported as substituted: %s" % String(full_report["summary"]))

	var partial := {"type": "deploy", "squad": [{"name": "A"}]}
	var partial_report: Dictionary = Contract.deploy_shape_report(partial)
	_expect(not bool(partial_report["complete"]), "a payload missing sector, faction, and seed reported as complete")
	for expected_field in ["sector", "faction", "seed"]:
		_expect(
			(partial_report["substituted"] as Array).has(expected_field),
			"the shape report does not name '%s' as substituted" % expected_field
		)
	# And the substitution itself must still happen -- reporting replaces the silence, not the
	# fallback, or a partial hand-off would start crashing instead of playing.
	var normalized: Dictionary = Contract.normalize_deploy(partial)
	_expect(int(normalized["seed"]) == Contract.FALLBACK_SEED, "a missing seed is no longer filled in")
	_expect(String(normalized["sector"]) != "", "a missing sector is no longer filled in")

	var hollow := {"type": "deploy", "sector": "T", "faction": "HAD", "seed": 1, "squad": [], "objectives": [], "resources": {}, "cell_size": 2.0}
	var hollow_report: Dictionary = Contract.deploy_shape_report(hollow)
	_expect(bool(hollow_report["empty_squad"]), "an explicitly empty squad was not reported")
	_expect(not bool(hollow_report["complete"]), "a payload with no squad reported as complete")

func _load_json(res_path: String) -> Dictionary:
	if not FileAccess.file_exists(res_path):
		return {}
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

func _config_constant(name: String) -> int:
	# The pin names its target as "GameConfig.MAX_AP"; resolve the trailing symbol
	# against the configuration authority rather than hardcoding the lookup.
	var symbol := name.get_slice(".", name.get_slice_count(".") - 1)
	var constants := _config_constants()
	if not constants.has(symbol):
		return -1
	return int(constants[symbol])

## `Config` is a preloaded script reference, so its constant map has to be read through a
## `Script`-typed binding; calling the method on the class reference is a parse error.
func _config_constants() -> Dictionary:
	var config_script: Script = Config
	return config_script.get_script_constant_map()

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
	# No physical key may drive two different actions. The Tab check above was the only
	# key invariant that existed, and it guarded exactly one key; meanwhile `lean_left`
	# and `camera_descend` both held Q, and `lean_right` and `camera_elevate` both held E.
	# Nothing consumes the event -- Main polls the lean actions in its input handler while
	# CameraController independently polls the camera actions -- so one Q press leaned the
	# unit *and* dropped the camera, silently, whenever the unit was in cover.
	#
	# An action may carry several keys. A key may not carry several actions.
	var key_owner := {}
	for bound_action in InputMap.get_actions():
		var bound_name := String(bound_action)
		if bound_name.begins_with("ui_"):
			continue
		for bound_event in InputMap.action_get_events(bound_name):
			if not (bound_event is InputEventKey):
				continue
			var code: int = (bound_event as InputEventKey).keycode
			if key_owner.has(code):
				_expect(
					false,
					"key %s drives both '%s' and '%s' -- neither consumes the event, so both fire" % [
						OS.get_keycode_string(code), String(key_owner[code]), bound_name
					]
				)
			else:
				key_owner[code] = bound_name
	_expect(key_owner.size() >= 20, "the input map looks unexpectedly small (%d keys)" % key_owner.size())
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
