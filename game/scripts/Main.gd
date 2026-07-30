extends Node3D
# Battle/Star.Sol  -  Phase 1i+ Playbook Implementation
# Features:
#   - 10x10 Grid Scaling with procedural cover placement.
#   - Centralized GameState, Pathfinder, AIBehavior, Economy, Narrative, CameraController singletons.
#   - Smooth & tactical orbit/zoom/pan camera system with target focusing.
#   - Unified perform_action() dispatcher for hotkeys and UI; scripted AI
#     migration is tracked as the next architecture step.
#   - Purely behavioral "Rip and Tear" enemy AI scoring engine.
#   - Articulated posture figures with crouching block, low-HP stagger (<30% HP), and two-handed carry.
#   - Dynamic HUD with vitals, clickable weapon/action buttons, squad roster, NEURAL token widget, DAO voting, and Narrative log panel.

const Config = preload("res://scripts/GameConfig.gd")
const BattlestarTacticalUI = preload("res://scripts/TacticalUI.gd")
const MovementRules = preload("res://scripts/MovementContext.gd")
const Maneuvers = preload("res://scripts/ManeuverState.gd")
# Explicit preloads so Main compiles even before .godot global class cache exists
# (missing cache was a crash loop after monorepo consolidation wiped .godot/).
const UnitScript = preload("res://scripts/Unit.gd")
const WorldBuilderScript = preload("res://scripts/WorldBuilder.gd")
const Ballistics = preload("res://scripts/Ballistics.gd")
const AITacticsScript = preload("res://scripts/AITactics.gd")
const CombatSystemScript = preload("res://scripts/CombatSystem.gd")
const InventorySystemScript = preload("res://scripts/InventorySystem.gd")
const Pilot = preload("res://scripts/PilotControl.gd")
const TurnDir = preload("res://scripts/TurnDirector.gd")
const SquadSpawn = preload("res://scripts/SquadSpawner.gd")
const MissionResolver = preload("res://scripts/MissionResolver.gd")
const Tutorial = preload("res://scripts/TutorialDirector.gd")
# Aliases
const GRID_W = Config.GRID_W
const GRID_H = Config.GRID_H
var cell_size: float = 2.0
const MAX_AP = Config.MAX_AP
const MOVE_COST = Config.MOVE_COST
const MELEE_COST = Config.MELEE_COST
const BLOCK_COST = Config.BLOCK_COST
const BLOCK_REDUCTION = Config.BLOCK_REDUCTION
const COVER_REDUCTION = Config.COVER_REDUCTION
const GRAB_COST = Config.GRAB_COST
const UNIT_HP = Config.UNIT_HP

const FLOOR = Config.FLOOR
const COVER = Config.COVER
const FACTION_HAD = Config.FACTION_HAD
const FACTION_SYND = Config.FACTION_SYND
const FACTION_TIME = Config.FACTION_TIME

const KINDS = Config.KINDS
const ENEMY_WEAPONS = Config.ENEMY_WEAPONS
const CODES = Config.CODES
const INVALID_CELL = Config.INVALID_CELL
const OBSERVATION_RADIUS := 2
const OBSERVATION_MOVE_CAP := 12
const OBSERVATION_COVER_CAP := 8
const OBSERVATION_ATTACK_CAP := 8
const OBSERVATION_VIEW_INTERVAL := 0.10

# ---------- Unit ----------
# ---------- State ----------
var cells = {}
## Untyped Array avoids hard-depends on global class_name cache for boot.
var units: Array = []
var debris = {}
var debris_nodes = {}
var selected = null
var turn: int = FACTION_HAD
var player_faction: int = FACTION_HAD
var global_turn: int = 1
var dev_god_mode: bool = false
var _busy_state = false
## When true, the AI faction turn owns the busy lock. Combat animations must not
## clear busy mid-loop or the player can inject actions between enemy units.
var _ai_turn_active: bool = false
var busy: bool:
	get:
		return _busy_state
	set(value):
		if _busy_state == value:
			return
		_busy_state = value
		# Animated actions deliberately refresh while busy so their controls lock.
		# Every busy -> ready transition must then publish the ready state too.
		# Keeping that rule here prevents individual movement implementations from
		# stranding the action bar until an unrelated control (such as God Mode)
		# happens to force another refresh.
		if not _busy_state and is_inside_tree():
			call_deferred("_refresh_interaction_ui")
var game_over = false
var pending_target_action = ""
var pending_target_z = -1
var mission_seed: int = 84021
var sim_rng = RandomNumberGenerator.new()
var visual_rng = RandomNumberGenerator.new()

# ---------- Controller / Subsystems ----------
var camera_controller: Node3D = null
## Ordered terrain damage for this mission, in the order it happened.
var terrain_changes: Array[Dictionary] = []
var combat
var inventory
var turn_director = TurnDir.new()

# ---------- Nodes / UI ----------
var tiles_root: Node3D
var highlight_root: Node3D
var sel_ring: MeshInstance3D

var tactical_ui: BattlestarTacticalUI
var sfx_player: AudioStreamPlayer
var tutorial = null
var _observation_last: String = ""
var _observation_view_elapsed: float = 0.0
var _observation_view_last: String = ""

func _ready() -> void:
	cell_size = Config.cell_size
	_setup_input_map()
	mission_seed = PayloadBridge.get_seed() if PayloadBridge.has_payload() else 84021
	if mission_seed <= 0:
		mission_seed = 84021
	sim_rng.seed = mission_seed + 15485863
	visual_rng.seed = mission_seed + 32452843
	var payload = PayloadBridge.get_payload() if PayloadBridge.has_payload() else {}
	GameState.begin_mission(
		mission_seed,
		int(payload.get("generator_version", 1)),
		String(payload.get("rules_version", "alpha-1"))
	)
	if Narrative and Narrative.has_method("configure_seed"):
		Narrative.configure_seed(mission_seed)

	var env = WorldBuilderScript.build_environment(self)
	tiles_root = env["tiles_root"]
	highlight_root = env["highlight_root"]

	cells = WorldBuilderScript.build_grid(self, tiles_root, mission_seed)

	sel_ring = WorldBuilderScript.build_ring(self)

	_build_camera_controller()

	tactical_ui = BattlestarTacticalUI.new(self)
	add_child(tactical_ui)

	combat = CombatSystemScript.new()
	combat.setup(self)
	add_child(combat)

	inventory = InventorySystemScript.new()
	inventory.setup(self)
	add_child(inventory)

	sfx_player = AudioStreamPlayer.new()
	sfx_player.bus = "SFX"
	add_child(sfx_player)

	# Reuse the mission payload already loaded above for GameState.begin_mission.
	player_faction = SquadSpawn.resolve_player_faction(payload, String(GameState.commander_faction))
	turn = player_faction
	GameState.turn = turn
	GameState.turn_count = global_turn
	turn_director.bind(self)

	_spawn_squads()
	_setup_action_router()
	_setup_tutorial(payload)
	WorldBuilderScript.scatter_weapons(self, mission_seed)
	tactical_ui.build_roster()
	_auto_select()
	_update_ui()
	var sector = String(payload.get("sector", ""))

	var brief = Narrative.generate_mission_brief() if Narrative else "Squad inserted."
	if sector == "Proving Ground":
		brief = "GUIDED PROVING GROUND ACTIVE: follow the objective panel. F8 is always available for extraction."
	elif sector == "Standoff":
		brief = "STANDOFF SIMULATION: End turn to observe AI cover and flank behavior."
	else:
		brief = "%s | Pilot: Commander. Agents are autonomous until Remotes (God Mode)." % brief

	_hint(brief)
	# Web startup can finish the CanvasLayer one frame after the tactical state.
	# Publish one authoritative ready-state refresh after both are in the tree.
	call_deferred("_refresh_interaction_ui")

# ==========================================================
#  BUILD (world)
# ==========================================================


func _build_camera_controller() -> void:
	var CamScript = load("res://scripts/CameraController.gd")
	camera_controller = Node3D.new()
	camera_controller.set_script(CamScript)
	camera_controller.position = _cell_to_world(Vector2i(int(GRID_W / 2.0), int(GRID_H / 2.0)))
	add_child(camera_controller)
	camera_controller.set_motion_scale(_detect_motion_scale())

## Reads the host's reduced-motion preference. Only the Web export can ask; any
## failure or unavailable host keeps the authored motion rather than guessing.
func _detect_motion_scale() -> float:
	if not OS.has_feature("web"):
		return 1.0
	var reduced = JavaScriptBridge.eval(
		"(function(){try{return !!(window.matchMedia"
		+ " && window.matchMedia('(prefers-reduced-motion: reduce)').matches);}"
		+ "catch(e){return false;}})()",
		true
	)
	return 0.0 if bool(reduced) else 1.0

# ==========================================================
#  UNITS + FIGURES (Posture Communication)
# ==========================================================
func _spawn_squads() -> void:
	var payload = PayloadBridge.get_payload() if PayloadBridge.has_payload() else {}
	SquadSpawn.spawn_into(self, player_faction, payload)
	GameState.units = units

func _empty_counts() -> Dictionary:
	return {}

func _make_unit(team: int, cell: Vector2i):
	var root = Node3D.new()
	add_child(root)
	root.position = _cell_to_world(cell)

	var fig = Node3D.new()
	root.add_child(fig)

	var lbl = Label3D.new()
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.fixed_size = true
	lbl.pixel_size = 0.0009
	lbl.position = Vector3(0, 2.6, 0)
	root.add_child(lbl)

	var u = UnitScript.new()
	u.team = team
	u.cell = cell
	u.z = int(cells.get(cell, {}).get("z", 0))
	u.hp = UNIT_HP
	u.max_hp = UNIT_HP

	if team == FACTION_HAD:
		u.max_armor = 8
	elif team == FACTION_SYND:
		u.max_armor = 4
	else:
		u.max_armor = 6
	u.armor = u.max_armor

	u.ap = MAX_AP
	u.max_ap = MAX_AP
	u.inv = _empty_counts()
	u.node = root
	u.fig = fig
	u.label = lbl
	u.body_col = GameConfig.faction_color(team) # EFD cyan / Metropoli amber / Kaiju green (canon)
	units.append(u)
	u.unit_id = units.size()
	_refresh_label(u)
	return u



# ==========================================================
#  UNIFIED ACTION DISPATCHER
# ==========================================================
## Combat / movement systems call this instead of assigning busy directly so an
## in-progress AI faction turn cannot be unlocked by the first finishing animation.
func set_action_busy(value: bool) -> void:
	if not value and _ai_turn_active:
		return
	busy = value

func perform_action(
	actor,
	action: String,
	target_cell: Vector2i = INVALID_CELL,
	use_offhand: bool = false,
	target_z: int = -1
) -> bool:
	if busy or game_over:
		return false

	if action != "endturn":
		if actor == null or not actor.alive:
			return false
		# Only the active faction may act. (Previously, player turn allowed
		# commanding any unit - including hostiles - via the router/hotkeys.)
		if actor.team != turn:
			return false
		# Human may only drive the active pilot (Commander, or a Remotes login).
		# Inspect-select / remotes plumbing are not command verbs.
		if not Pilot.can_human_command(actor, player_faction, turn, action):
			if action != "select" and actor.team == player_faction and bool(actor.is_squad_bot):
				_hint("%s is autonomous. Enable God Mode and use Remotes to pilot." % actor.name)
			return false
		if MovementRules.action_locked(actor, action):
			_hint("%s cannot use %s during the current movement commitment." % [actor.name, action.replace("_", " ")])
			return false

	match action:
		"select":
			selected = actor
			if camera_controller and actor.node:
				camera_controller.focus_unit(actor.node)
			_update_ui()
			if actor.team == player_faction and not Pilot.is_human_pilot(actor):
				_hint("Observing %s (AI agent). Remotes required to pilot." % actor.name)
			else:
				_hint("Selected %s." % actor.name)
			return true

		"move":
			if target_cell != INVALID_CELL:
				var path = Pathfinder.find_path(actor.cell, target_cell, cells, units, actor.flying or actor.hovering)
				if path.size() >= 2:
					var valid_path: Array[Vector2i] = ActionEconomy.affordable_path(actor, path, cells)
					if valid_path.size() >= 2:
						if actor.taking_cover and actor.cover_monkey_active:
							_leave_cover_state(actor, 0, "cover_monkey_move")
						_move_unit(actor, valid_path)
						return true
			return false

		"melee":
			var melee_target = _unit_at(target_cell)
			if melee_target == null or not melee_target.alive or melee_target.team == actor.team:
				return false
			if not Pathfinder.is_adjacent(actor.cell, melee_target.cell):
				return false
			if actor.ap < Config.MELEE_COST:
				_hint("Not enough AP to strike.")
				return false
			combat.execute_melee(actor, melee_target, use_offhand)
			return true

		"ranged":
			var ranged_target = _unit_at(target_cell)
			if ranged_target == null or not ranged_target.alive or ranged_target.team == actor.team:
				return false
			if not combat.can_attempt_ranged(actor, ranged_target, use_offhand):
				return false
			combat.execute_ranged(actor, ranged_target, use_offhand)
			return true

		"jump":
			if _jump_target_valid(actor, target_cell):
				_resolve_jump_action(actor, target_cell)
				return true
			return false

		"fly_to":
			if _flight_target_valid(actor, target_cell, target_z):
				var flight_cost = ActionEconomy.flight_cost(actor.cell, actor.z, target_cell, target_z)
				_fly_unit(actor, target_cell, target_z, flight_cost)
				return true
			return false

		"toggle_walk":
			actor.move_mode = "run"
			_update_ui()
			_hint("%s is now %sING." % [actor.name, actor.move_mode.to_upper()])
			return true

		"toggle_run":
			if actor.stance != "stand":
				_hint("%s cannot sprint while %s." % [actor.name, actor.stance])
				return false
			if actor.move_mode == "run":
				actor.move_mode = "sprint"
			else:
				actor.move_mode = "run"
			_update_ui()
			_hint("%s is now %sING." % [actor.name, actor.move_mode.to_upper()])
			return true

		"toggle_orient":
			if actor.stance == "prone":
				if actor.prone_orient == "down": actor.prone_orient = "up"
				else: actor.prone_orient = "down"
				actor.update_figure()
				_update_ui()
				_hint("%s is now face %s." % [actor.name, actor.prone_orient])
			return true

		"dodge":
			if actor.ap >= Config.DODGE_COST:
				actor.ap -= Config.DODGE_COST
				actor.dodging = true
				_update_ui()
				if Narrative: Narrative.generate_mobility_narrative(actor.name, "DODGE")
				_hint("%s is dodging!" % actor.name)
				return true
			return false

		"flip":
			if (
				_special_enabled(actor, "flip")
				and Maneuvers.is_airborne(actor.maneuver)
				and actor.ap >= Config.FLIP_COST
			):
				_flip_airborne(actor)
				return true
			return false

		"hover":
			if actor.ap >= Config.HOVER_COST:
				actor.ap -= Config.HOVER_COST
				actor.hovering = not actor.hovering
				_refresh_label(actor)
				_update_ui()
				if Narrative: Narrative.generate_mobility_narrative(actor.name, "HOVER")
				_hint("%s hovering: %s" % [actor.name, actor.hovering])
				return true
			return false

		"toggle_flight":
			if actor.ap >= Config.FLIGHT_TOGGLE_COST:
				var terrain_z = int(cells.get(actor.cell, {}).get("z", 0))
				if actor.flying and actor.z > terrain_z:
					_hint("%s must land before disengaging flight." % actor.name)
					return false
				actor.ap -= Config.FLIGHT_TOGGLE_COST
				actor.flying = not actor.flying
				_refresh_label(actor)
				_update_ui()
				if Narrative: Narrative.generate_mobility_narrative(actor.name, "FLIGHT")
				_hint("%s flight mode: %s" % [actor.name, actor.flying])
				return true
			return false

		"wall_run":
			if _special_enabled(actor, "wall_run") and _wall_run_target_valid(actor, target_cell):
				_resolve_wall_run(actor, target_cell)
				return true
			return false

		"wall_jump":
			if _special_enabled(actor, "wall_jump") and _wall_jump_target_valid(actor, target_cell):
				_resolve_wall_jump(actor, target_cell)
				return true
			return false

		"toggle_free_fly":
			if camera_controller and camera_controller.has_method("toggle_free_fly"):
				var active: bool = camera_controller.toggle_free_fly()
				if Narrative: Narrative.generate_mobility_narrative(actor.name if actor else "DRONE", "FREE FLY DRONE CAM")
				_hint("REMOTE DRONE / FREE FLY CAM: %s (WASD + Q/E to fly)" % ["ACTIVE" if active else "DISABLED"])
				_update_ui()
				return true
			return false

		"grab":
			if debris.has(actor.cell) and actor.ap >= GRAB_COST:
				var desc = _debris_str(actor.cell)
				if inventory.grab(actor):
					_hint("%s grabbed: %s" % [actor.name, desc])
					return true
			return false

		"assemble_auto":
			if inventory.assemble(actor):
				return true
			return false

		"brace":
			if not actor.blocking and actor.ap >= BLOCK_COST:
				actor.ap -= BLOCK_COST
				actor.blocking = true
				_refresh_label(actor)
				_update_ui()
				_hint("%s is bracing." % actor.name)
				return true
			return false

		"take_cover":
			var take_cover_cost = ActionEconomy.fixed_cost("take_cover")
			if actor.ap < take_cover_cost or not MovementRules.can_take_cover(actor, target_cell, cells):
				return false
			_enter_cover_state(actor, target_cell, take_cover_cost, "manual")
			return true

		"leave_cover":
			var leave_cover_cost = ActionEconomy.fixed_cost("leave_cover")
			if actor.ap < leave_cover_cost or not MovementRules.can_leave_cover(actor):
				return false
			_leave_cover_state(actor, leave_cover_cost, "manual")
			return true

		"cover_monkey":
			if not _special_enabled(actor, "cover_monkey"):
				return false
			actor.cover_monkey_active = not actor.cover_monkey_active
			GameState.record_event("special_stance_changed", {
				"actor": actor.unit_id,
				"special": "cover_monkey",
				"active": actor.cover_monkey_active
			})
			_update_ui()
			_hint("%s Cover Monkey stance: %s." % [actor.name, "ON" if actor.cover_monkey_active else "OFF"])
			return true

		"remotes":
			# Dev-gated special: jack the pilot link into a squad bot (or home body).
			if not dev_god_mode and not _special_enabled(actor, "remotes"):
				_hint("Remotes is a developer special. Toggle God Mode to unlock.")
				return false
			if target_cell != INVALID_CELL:
				var remote_target = _unit_at(target_cell)
				if remote_target == null:
					_hint("Remotes: no unit at that cell.")
					return false
				return _remotes_login(remote_target)
			# Observing a squad bot: one-click login into that agent.
			if actor != null and actor.team == player_faction and bool(actor.is_squad_bot):
				return _remotes_login(actor)
			# Already jacked into a bot with no target: return to Commander.
			var pilot = _active_human_pilot()
			if pilot != null and not bool(pilot.is_commander):
				return _remotes_return_home()
			return begin_targeting("remotes")

		"remotes_home":
			if not dev_god_mode and not _special_enabled(actor if actor != null else _active_human_pilot(), "remotes"):
				_hint("Remotes is a developer special. Toggle God Mode to unlock.")
				return false
			return _remotes_return_home()

		"crouch":
			if actor.ap >= Config.CROUCH_COST:
				actor.ap -= Config.CROUCH_COST
				actor.stance = "stand" if actor.stance == "crouch" else "crouch"
				if actor.stance != "stand":
					actor.move_mode = "run"
				_refresh_label(actor)
				_update_ui()
				_hint("%s stance: %s" % [actor.name, actor.stance])
				return true
			return false

		"prone":
			if actor.ap >= Config.PRONE_COST:
				actor.ap -= Config.PRONE_COST
				actor.stance = "stand" if actor.stance == "prone" else "prone"
				if actor.stance != "stand":
					actor.move_mode = "run"
				_refresh_label(actor)
				_update_ui()
				_hint("%s stance: %s" % [actor.name, actor.stance])
				return true
			return false

		"lean_l":
			if actor.ap >= Config.LEAN_COST and MovementRules.can_lean(actor, "left"):
				actor.ap -= Config.LEAN_COST
				actor.lean = "none" if actor.lean == "left" else "left"
				_refresh_label(actor)
				_update_ui()
				_hint("%s lean: %s" % [actor.name, actor.lean])
				return true
			return false

		"lean_r":
			if actor.ap >= Config.LEAN_COST and MovementRules.can_lean(actor, "right"):
				actor.ap -= Config.LEAN_COST
				actor.lean = "none" if actor.lean == "right" else "right"
				_refresh_label(actor)
				_update_ui()
				_hint("%s lean: %s" % [actor.name, actor.lean])
				return true
			return false

		"assemble":
			return inventory.assemble(actor)

		"endturn":
			if turn == player_faction:
				# Finish player phase: allied agents resolve on AI, then next faction.
				call_deferred("_player_finish_turn")
				return true
			return false

		"equip_fist":
			if actor.left == "" and actor.right == "" and not actor.two_handed:
				return true
			if actor.ap < Config.EQUIP_COST:
				_hint("Not enough AP to change equipment.")
				return false
			actor.ap -= Config.EQUIP_COST
			actor.left = ""; actor.right = ""; actor.two_handed = false
			_refresh_label(actor); _update_ui(); return true

		_:
			if action.begins_with("equip_"):
				var kind = action.substr(6)
				var item = ItemDB.get_item(kind)
				if item.is_empty(): return false
				if not actor.has_item(kind):
					_hint("%s is not in inventory." % item.get("name", kind))
					return false
				if actor.ap < Config.EQUIP_COST:
					_hint("Not enough AP to ready %s." % item.get("name", kind))
					return false

				# Determine handedness
				var item_name = item.get("name", kind).to_lower()
				var is_two = item_name.contains("rifle") or item_name.contains("shotgun") or item_name.contains("sniper") or kind == "spear" or kind == "club"

				var equipped = _grip_two(actor, kind) if is_two else _grip_1h(actor, kind, use_offhand)
				if equipped:
					actor.ap -= Config.EQUIP_COST
					_update_ui()
				return equipped
			return false

# ==========================================================
#  INVENTORY / HANDS / DEBRIS
# ==========================================================

func _grip_two(u, kind: String) -> bool:
	u.two_handed = true
	u.right = kind
	u.left = ""
	_refresh_label(u)
	_update_ui()
	return true

func _grip_1h(u, kind: String, offhand: bool) -> bool:
	u.two_handed = false
	if offhand:
		u.left = kind
	else:
		u.right = kind
	_refresh_label(u)
	_update_ui()
	return true

func _add_debris(cell: Vector2i, kind: String, count: int) -> void:
	if count <= 0:
		return
	var d: Dictionary = debris.get(cell, _empty_counts())
	d[kind] = int(d.get(kind, 0)) + count
	debris[cell] = d
	GameState.debris = debris
	_refresh_debris_visual(cell)

func _remove_debris(cell: Vector2i) -> void:
	debris.erase(cell)
	GameState.debris = debris
	if debris_nodes.has(cell):
		debris_nodes[cell].queue_free()
		debris_nodes.erase(cell)

func _debris_total(cell: Vector2i) -> int:
	if not debris.has(cell): return 0
	var t = 0
	for k in debris[cell].keys():
		t += int(debris[cell][k])
	return t

func _debris_str(cell: Vector2i) -> String:
	if not debris.has(cell):
		return ""
	return inventory.inv_str(debris[cell])

func _mini(col: Color, size: Vector3, pos: Vector3, holder: Node3D) -> void:
	var mi = MeshInstance3D.new()
	var bx = BoxMesh.new()
	bx.size = size
	var m = StandardMaterial3D.new()
	m.albedo_color = col
	bx.material = m
	mi.mesh = bx
	mi.position = pos
	holder.add_child(mi)

func _refresh_debris_visual(cell: Vector2i) -> void:
	if debris_nodes.has(cell):
		debris_nodes[cell].queue_free()
		debris_nodes.erase(cell)
	if _debris_total(cell) <= 0:
		return
	var holder = Node3D.new()
	holder.name = "Loot_%d_%d" % [cell.x, cell.y]
	holder.position = _cell_to_world(cell)
	add_child(holder)
	var d: Dictionary = debris[cell]

	# A persistent emissive locator keeps equipment readable from BEV/OTS
	# without replacing the physical item meshes.
	var beacon = MeshInstance3D.new()
	var disc = CylinderMesh.new()
	disc.top_radius = 0.48
	disc.bottom_radius = 0.48
	disc.height = 0.05
	var beacon_mat = StandardMaterial3D.new()
	beacon_mat.albedo_color = Color(0.08, 0.82, 1.0, 0.72)
	beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beacon_mat.emission_enabled = true
	beacon_mat.emission = Color(0.08, 0.82, 1.0)
	beacon_mat.emission_energy_multiplier = 2.0
	disc.material = beacon_mat
	beacon.mesh = disc
	beacon.position = Vector3(0, 0.08, 0)
	holder.add_child(beacon)

	# Deprecated presentation experiment, retained for a future UI/readability
	# pass. The physical item mesh and emissive ground locator remain active.
	# var loot_label = Label3D.new()
	# loot_label.text = "LOOT"
	# loot_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# loot_label.no_depth_test = true
	# loot_label.fixed_size = true
	# loot_label.pixel_size = 0.0008
	# loot_label.modulate = Color(0.25, 0.9, 1.0)
	# loot_label.position = Vector3(0, 0.85, 0)
	# holder.add_child(loot_label)

	for k in d.keys():
		if int(d[k]) <= 0:
			continue
		match k:
			"rock":
				var mi = MeshInstance3D.new()
				var sph = SphereMesh.new()
				sph.radius = 0.22
				sph.height = 0.44
				var m = StandardMaterial3D.new()
				m.albedo_color = Color(0.52, 0.49, 0.44)
				sph.material = m
				mi.mesh = sph
				mi.position = Vector3(-0.3, 0.22, 0)
				holder.add_child(mi)
			"spear":
				_mini(Color(0.75, 0.68, 0.5), Vector3(0.08, 0.08, 1.5), Vector3(0.1, 0.1, 0), holder)
			"club":
				_mini(Color(0.5, 0.38, 0.25), Vector3(0.18, 0.18, 0.8), Vector3(0.35, 0.14, 0.1), holder)
			"bow":
				_mini(Color(0.55, 0.4, 0.2), Vector3(0.1, 0.9, 0.1), Vector3(0.0, 0.45, -0.3), holder)
			"string":
				_mini(Color(0.85, 0.85, 0.8), Vector3(0.04, 0.04, 0.7), Vector3(-0.1, 0.06, 0.35), holder)
			"arrow":
				_mini(Color(0.8, 0.75, 0.55), Vector3(0.05, 0.05, 0.9), Vector3(0.2, 0.08, 0.2), holder)
			"stringedbow":
				_mini(Color(0.6, 0.45, 0.25), Vector3(0.1, 1.0, 0.1), Vector3(0.0, 0.5, 0.2), holder)
			_:
				# Generic item crate/box
				var mi = MeshInstance3D.new()
				var bx = BoxMesh.new()
				bx.size = Vector3(0.35, 0.25, 0.25)
				var m = StandardMaterial3D.new()
				m.albedo_color = Color(0.2, 0.2, 0.25)
				m.metallic = 0.8
				m.roughness = 0.4
				m.emission_enabled = true
				m.emission = Color(0.1, 0.8, 1.0)
				m.emission_energy_multiplier = 1.2
				bx.material = m
				mi.mesh = bx
				mi.position = Vector3(
					visual_rng.randf_range(-0.1, 0.1),
					0.125,
					visual_rng.randf_range(-0.1, 0.1)
				)
				holder.add_child(mi)
	debris_nodes[cell] = holder

# ==========================================================
#  INPUT & CAMERA INTERACTION
# ==========================================================
func _setup_input_map() -> void:
	# Define actions and default key bindings (mirroring existing shortcuts)
	var actions = {
		"camera_up": [KEY_W, KEY_UP],
		"camera_down": [KEY_S, KEY_DOWN],
		"camera_left": [KEY_A, KEY_LEFT],
		"camera_right": [KEY_D, KEY_RIGHT],
		"camera_elevate": [KEY_E],
		"camera_descend": [KEY_Q],
		# Tab is reserved for keyboard focus traversal. Binding it to the help
		# overlay made the tactical controls unreachable without a mouse: the
		# first Tab opened help and focused its close button, and every later
		# Tab toggled the overlay instead of advancing focus.
		"toggle_legend": [KEY_F1],
		# Adaptive HUD. Tab stays reserved for focus traversal.
		"hud_next_surface": [KEY_F2],
		"hud_cycle_opacity": [KEY_F3],
		"hud_toggle_park": [KEY_F4],
		"close_legend": [KEY_ESCAPE],
		"end_turn": [KEY_SPACE, KEY_ENTER],
		"emergency_evac": [KEY_F8],
		"brace": [KEY_B],
		"take_cover": [KEY_T],
		"crouch": [KEY_C],
		"prone": [KEY_P],
		# Lean was bound to Q and E, which camera_descend and camera_elevate already
		# claimed. Nothing consumes the event — Main polls `lean_left` in its input
		# handler while CameraController independently polls `camera_descend` — so a
		# single Q press did both: the unit leaned and the camera dropped. Bracket keys
		# read as lean direction and collide with nothing.
		"lean_left": [KEY_BRACKETLEFT],
		"lean_right": [KEY_BRACKETRIGHT],
		"jump": [KEY_J],
		"toggle_run": [KEY_M],
		"toggle_orient": [KEY_N],
		"dodge": [KEY_Z],
		"flip": [KEY_X],
		"hover": [KEY_H],
		"toggle_flight": [KEY_V],
		"flight_up": [KEY_PAGEUP],
		"flight_down": [KEY_PAGEDOWN],
		"flight_land": [KEY_L],
		"grab": [KEY_G],
		"assemble": [KEY_F]
	}
	for action_name in actions.keys():
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		for key in actions[action_name]:
			var ev = InputEventKey.new()
			ev.keycode = key
			ev.pressed = false
			InputMap.action_add_event(action_name, ev)


func _unhandled_input(event: InputEvent) -> void:
	if camera_controller == null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_on_click(event.shift_pressed)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			camera_controller.dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if pending_target_action == "flight":
				adjust_flight_layer(1)
			else:
				camera_controller.zoom(-2.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if pending_target_action == "flight":
				adjust_flight_layer(-1)
			else:
				camera_controller.zoom(2.0)
	elif event is InputEventMouseMotion and camera_controller.dragging:
		camera_controller.orbit(event.relative.x * 0.4, event.relative.y * 0.4)
	elif event is InputEventKey and event.pressed:
		if Input.is_action_just_pressed("toggle_legend"):
			if tactical_ui and tactical_ui.has_method("toggle_help"):
				tactical_ui.toggle_help()
			return
		if Input.is_action_just_pressed("close_legend") and tactical_ui and tactical_ui.has_method("is_help_visible") and tactical_ui.is_help_visible():
			tactical_ui.set_help_visible(false)
			return
		if event.keycode == KEY_ESCAPE and not pending_target_action.is_empty():
			cancel_targeting()
			return
		var can_act = turn == player_faction and not busy and not game_over
		if Input.is_action_just_pressed("emergency_evac"):
			if can_act:
				_do_evac()
			return
		if Input.is_action_just_pressed("end_turn"):
			if can_act:
				var end_actor = _active_human_pilot()
				if end_actor == null:
					end_actor = selected
				ActionRouter.request_action(end_actor, "endturn")
			return
		if not (can_act and selected != null and selected.alive and _unit_accepts_human_input(selected)):
			return
		# Action shortcuts via InputMap
		if Input.is_action_just_pressed("brace"):
			ActionRouter.request_action(selected, "brace")
		elif Input.is_action_just_pressed("take_cover"):
			if selected.taking_cover:
				ActionRouter.request_action(selected, "leave_cover")
			else:
				begin_targeting("take_cover")
		elif Input.is_action_just_pressed("crouch"):
			ActionRouter.request_action(selected, "crouch")
		elif Input.is_action_just_pressed("prone"):
			ActionRouter.request_action(selected, "prone")
		elif Input.is_action_just_pressed("lean_left"):
			ActionRouter.request_action(selected, "lean_l")
		elif Input.is_action_just_pressed("lean_right"):
			ActionRouter.request_action(selected, "lean_r")
		elif Input.is_action_just_pressed("jump"):
			begin_targeting("jump")
		elif Input.is_action_just_pressed("toggle_run"):
			ActionRouter.request_action(selected, "toggle_run")
		elif Input.is_action_just_pressed("toggle_orient"):
			ActionRouter.request_action(selected, "toggle_orient")
		elif Input.is_action_just_pressed("dodge"):
			ActionRouter.request_action(selected, "dodge")
		elif Input.is_action_just_pressed("flip"):
			ActionRouter.request_action(selected, "flip")
		elif Input.is_action_just_pressed("hover"):
			ActionRouter.request_action(selected, "hover")
		elif Input.is_action_just_pressed("toggle_flight"):
			begin_targeting("flight")
		elif Input.is_action_just_pressed("flight_up"):
			adjust_flight_layer(1)
		elif Input.is_action_just_pressed("flight_down"):
			adjust_flight_layer(-1)
		elif Input.is_action_just_pressed("flight_land"):
			land_selected_unit()
		elif Input.is_action_just_pressed("grab"):
			ActionRouter.request_action(selected, "grab")
		elif Input.is_action_just_pressed("assemble"):
			ActionRouter.request_action(selected, "assemble")

func _process(delta: float) -> void:
	if not busy and turn == player_faction and not game_over:
		_update_hover()
	_refresh_web_observation_for_view(delta)

# ==========================================================
#  ACTIONS & COMBAT RESOLUTION
# ==========================================================
func begin_targeting(action: String) -> bool:
	if busy or game_over or turn != player_faction:
		return false
	if action == "remotes":
		if not dev_god_mode:
			_hint("Remotes is a developer special. Toggle God Mode to unlock.")
			return false
		pending_target_action = "remotes"
		pending_target_z = -1
		_hint("REMOTES: click a squad agent to pilot, or the Commander to return home. [Esc] cancels.")
		_update_ui()
		return true
	if selected == null or not selected.alive:
		return false
	if not _unit_accepts_human_input(selected) and action != "remotes":
		_hint("Select your active pilot (or use Remotes) before targeting.")
		return false
	match action:
		"take_cover":
			if selected.taking_cover:
				return false
			if selected.ap < Config.TAKE_COVER_COST:
				_hint("Not enough AP to take cover.")
				return false
			var available_cover = cover_options(selected)
			if available_cover.is_empty():
				_hint("No usable cover is adjacent to %s." % selected.name)
				return false
			pending_target_action = "take_cover"
			pending_target_z = -1
			_hint("TAKE COVER: choose an adjacent cover face. [Esc] cancels.")
			_update_ui()
			return true
		"jump":
			if selected.ap < Config.JUMP_COST:
				_hint("Not enough AP to jump.")
				return false
			if (
				not Maneuvers.is_airborne(selected.maneuver)
				and not MovementRules.can_initiate_jump(
					selected,
					_special_enabled(selected, "precision_jump")
				)
			):
				_hint("Jump requires movement momentum or the Precision Jump special.")
				return false
			pending_target_action = "jump"
			pending_target_z = -1
			if Maneuvers.is_airborne(selected.maneuver):
				_hint("AIRBORNE JUMP: choose the landing/revector tile within two spaces. [Esc] cancels.")
			else:
				_hint("JUMP TARGETING: choose a tile two spaces away to enter the air anchor. [Esc] cancels.")
			_update_ui()
			return true
		"wall_run":
			if selected.ap < Config.WALL_RUN_COST:
				_hint("Not enough AP for a Wall Run segment.")
				return false
			if Maneuvers.is_wall_running(selected.maneuver):
				return ActionRouter.request_action(selected, "wall_run")
			var walls = wall_run_options(selected)
			if walls.is_empty():
				_hint("Wall Run requires actual Run/Sprint momentum and an adjacent continuous wall.")
				return false
			pending_target_action = "wall_run"
			pending_target_z = -1
			_hint("WALL RUN: choose an adjacent runnable wall face. [Esc] cancels.")
			_update_ui()
			return true
		"wall_jump":
			if not MovementRules.can_wall_jump(selected) or selected.ap < Config.WALL_JUMP_COST:
				_hint("Wall Jump requires active wall contact and sufficient AP.")
				return false
			pending_target_action = "wall_jump"
			pending_target_z = -1
			_hint("WALL JUMP: choose an outward landing column within two spaces. [Esc] cancels.")
			_update_ui()
			return true
		"flight":
			if not selected.flying:
				if not ActionRouter.request_action(selected, "toggle_flight"):
					return false
			var terrain_z = int(cells.get(selected.cell, {}).get("z", 0))
			pending_target_action = "flight"
			pending_target_z = clampi(maxi(selected.z, terrain_z + 1), 0, Config.MAX_FLIGHT_Z)
			_hint("FLIGHT TARGETING: aim at the air cube; wheel changes altitude (%d). Click terrain level to land. [Esc] cancels." % pending_target_z)
			_update_ui()
			return true
	return false

func cancel_targeting() -> void:
	pending_target_action = ""
	pending_target_z = -1
	_clear_highlights()
	_hint("Targeting cancelled.")
	_update_ui()

func adjust_flight_layer(delta: int) -> bool:
	if pending_target_action != "flight":
		if not begin_targeting("flight"):
			return false
	pending_target_z = clampi(pending_target_z + delta, 0, Config.MAX_FLIGHT_Z)
	_hint("FLIGHT TARGETING: altitude %d. Click the highlighted cube; wheel changes altitude." % pending_target_z)
	_update_ui()
	return true

func land_selected_unit() -> bool:
	if selected == null or not selected.flying:
		_hint("No airborne unit selected.")
		return false
	var terrain_z = int(cells.get(selected.cell, {}).get("z", 0))
	if not ActionRouter.request_action(selected, "fly_to", selected.cell, false, terrain_z):
		_hint("Not enough AP to land here.")
		return false
	pending_target_action = ""
	pending_target_z = -1
	return true

func _on_click(use_offhand: bool) -> void:
	if busy or game_over or turn != player_faction:
		return
	var cell = _mouse_cell_at_level(pending_target_z) if pending_target_action == "flight" else _mouse_cell()
	if cell == INVALID_CELL:
		return

	if pending_target_action == "remotes":
		var remote_occ = _unit_at(cell)
		if remote_occ == null or remote_occ.team != player_faction:
			_hint("Remotes: choose one of your squad units.")
			return
		var remotes_actor = _active_human_pilot()
		if remotes_actor == null:
			remotes_actor = _get_commander()
		if remotes_actor == null:
			remotes_actor = selected
		if ActionRouter.request_action(remotes_actor, "remotes", cell):
			pending_target_action = ""
			pending_target_z = -1
		return
	if pending_target_action == "take_cover":
		if ActionRouter.request_action(selected, "take_cover", cell):
			pending_target_action = ""
			pending_target_z = -1
		else:
			_hint("Invalid cover: choose a highlighted adjacent cover face.")
		return
	if pending_target_action == "jump":
		if ActionRouter.request_action(selected, "jump", cell):
			pending_target_action = ""
			pending_target_z = -1
		else:
			_hint("Invalid jump: choose an empty tile exactly two spaces away and within %d height levels." % Config.MAX_JUMP_STEP)
		return
	if pending_target_action == "wall_run":
		if ActionRouter.request_action(selected, "wall_run", cell):
			pending_target_action = ""
			pending_target_z = -1
		else:
			_hint("Invalid Wall Run face: build momentum and choose an adjacent wall above the unit.")
		return
	if pending_target_action == "wall_jump":
		if ActionRouter.request_action(selected, "wall_jump", cell):
			pending_target_action = ""
			pending_target_z = -1
		else:
			_hint("Invalid Wall Jump: choose an empty outward tile within two spaces.")
		return
	if pending_target_action == "flight":
		if ActionRouter.request_action(selected, "fly_to", cell, false, pending_target_z):
			pending_target_action = ""
			pending_target_z = -1
		else:
			_hint("Invalid flight cube: it is occupied, below terrain, or beyond remaining AP.")
		return

	var occ = _unit_at(cell)

	if occ != null and occ.alive and occ.team == player_faction:
		if occ == selected and debris.has(cell) and _unit_accepts_human_input(selected):
			ActionRouter.request_action(selected, "grab")
		else:
			# M01-001: selection is a recorded action. Bypassing ActionRouter
			# strands the guided tutorial and omits the action from replay.
			ActionRouter.request_action(occ, "select")
		return

	if selected == null:
		return
	if not _unit_accepts_human_input(selected):
		return

	if occ != null and occ.alive and occ.team != player_faction:
		if Pathfinder.is_adjacent(selected.cell, cell):
			ActionRouter.request_action(selected, "melee", cell, use_offhand)
		else:
			ActionRouter.request_action(selected, "ranged", cell, use_offhand)
		return

	if _cell_free(cell):
		ActionRouter.request_action(selected, "move", cell)


func _move_unit(u, path: Array[Vector2i]) -> void:
	set_action_busy(true)
	_clear_highlights()
	var start_cell = u.cell
	var start_z = u.z
	var start_ap = u.ap
	for i in range(1, path.size()):
		var target = path[i]
		_play_sfx("footstep", u.node.position)
		var terrain_z: int = cells[target].get("z", 0) if cells.has(target) else 0
		var target_z = terrain_z
		if u.hovering or u.flying:
			target_z = max(terrain_z, u.z)

		var final_pos = _cell_to_world(target)
		final_pos.y = target_z * Config.HEIGHT_STEP # Force Y to match Z level
		_face_unit_toward(u, final_pos)

		var duration = 0.15
		var bop_height = 0.12
		var tilt = 15.0

		if String(u.stance) == "prone":
			duration = 0.4
			bop_height = 0.03
			tilt = 0.0
		elif String(u.stance) == "crouch":
			duration = 0.25
			bop_height = 0.06
			tilt = 8.0
		else:
			if String(u.move_mode) == "sprint":
				duration = 0.1
				bop_height = 0.15
				tilt = 25.0
			elif String(u.move_mode) == "walk":
				duration = 0.3
				bop_height = 0.05
				tilt = 5.0

		var tw = create_tween()
		var drop_dist = u.z - target_z
		if target_z > u.z:
			var mid_pos = u.node.position.lerp(final_pos, 0.5)
			mid_pos.y += 0.8
			tw.tween_property(u.node, "position", mid_pos, duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(u.node, "position", final_pos, duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		else:
			tw.tween_property(u.node, "position", final_pos, duration)

		var tw_fig = create_tween()
		var base_y = 0.0
		tw_fig.tween_property(u.fig, "position:y", base_y + bop_height, duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw_fig.tween_property(u.fig, "position:y", base_y, duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

		var base_rot = u.fig.rotation_degrees
		if tilt > 0.0:
			var tw_rot = create_tween()
			tw_rot.tween_property(u.fig, "rotation_degrees:x", base_rot.x - tilt, duration * 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw_rot.tween_property(u.fig, "rotation_degrees:x", base_rot.x, duration * 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

		await tw.finished
		u.fig.position.y = base_y
		u.fig.rotation_degrees = base_rot

		var cost = ActionEconomy.movement_step_cost(u, u.z, target_z)

		u.cell = target
		u.z = target_z
		u.ap -= cost

		if drop_dist > 0 and not (u.hovering or u.flying):
			combat.apply_fall_damage(u, drop_dist)
			if not u.alive:
				break
		u.last_move_direction = target - path[i - 1]
		u.record_ground_step(u.move_mode)
		_update_ui()
	set_action_busy(false)
	GameState.record_event("movement_resolved", {
		"actor": u.unit_id,
		"from": {"x": start_cell.x, "y": start_cell.y, "z": start_z},
		"to": {"x": u.cell.x, "y": u.cell.y, "z": u.z},
		"ap_spent": start_ap - u.ap,
		"mode": u.move_mode
	})
	if not u.alive:
		_check_end()
		return
	if u.cover_monkey_active and u.alive:
		_auto_cover_monkey(u)
	if debris.has(u.cell):
		_hint("LOOT UNDERFOOT: %s. Click %s again or use Grab Loot (G)." % [_debris_str(u.cell), u.name])

func _compile_salvage() -> Array:
	var mtype = "covert"
	if GameState and GameState.get("mission_type"):
		mtype = String(GameState.mission_type)
	return MissionResolver.compile_salvage(units, debris, player_faction, mtype, sim_rng)

func _check_end() -> void:
	if game_over:
		return # Idempotent: a killing blow must not fire the end sequence twice.
	var pl = MissionResolver.count_living(units, player_faction)
	var en = MissionResolver.count_hostiles(units, player_faction)
	if en == 0:
		game_over = true
		_hint("VICTORY - All hostiles down. Extracting...")
		await get_tree().create_timer(2.0).timeout
		if not is_inside_tree(): return
		var salvage = _compile_salvage()
		var gains = MissionResolver.build_gains(salvage)
		if GameState:
			GameState.commit_extraction()
		GameState.record_event("mission_resolved", {"outcome": "SUCCESS", "survivors": pl})
		PayloadBridge.push_extraction({
			"outcome": "SUCCESS",
			"survivors": pl,
			"gains": gains,
			"replay": GameState.replay_bundle()
		})
		_return_after_extraction()
	elif pl == 0:
		game_over = true
		_hint("DEFEAT - Squad eliminated. Loot lost.")
		await get_tree().create_timer(2.0).timeout
		if not is_inside_tree(): return
		if GameState: GameState.fail_extraction()
		GameState.record_event("mission_resolved", {"outcome": "FAILURE", "survivors": 0})
		PayloadBridge.push_extraction({
			"outcome": "FAILURE",
			"survivors": 0,
			"replay": GameState.replay_bundle()
		})
		_return_after_extraction()

func _do_evac() -> void:
	if game_over: return
	game_over = true
	_hint("EMERGENCY EVAC INITIATED...")
	await get_tree().create_timer(1.5).timeout
	if not is_inside_tree(): return
	var salvage = _compile_salvage()
	var gains = MissionResolver.build_gains(salvage)
	var pl = MissionResolver.count_living(units, player_faction)
	if GameState:
		GameState.commit_extraction()
	GameState.record_event("mission_resolved", {"outcome": "SUCCESS", "survivors": pl, "note": "evac"})
	PayloadBridge.push_extraction({
		"outcome": "SUCCESS",
		"survivors": pl,
		"gains": gains,
		"note": "evac",
		"replay": GameState.replay_bundle()
	})
	_return_after_extraction()

func _return_after_extraction() -> void:
	# In Web builds the tactical scene is mounted inside battlestar.html. That
	# host receives the extraction payload, restores the A.T.L.A.S. snapshot,
	# and closes or redirects the tactical page. Loading StratLayer.tscn here
	# would instead replace the iframe with a fresh covert-ingress/login screen.
	if OS.has_feature("web"):
		return
	get_tree().change_scene_to_file.call_deferred("res://StratLayer.tscn")

# ==========================================================
#  ENEMY TURN EXECUTION
# ==========================================================
func _end_turn() -> void:
	if game_over:
		return
	selected = null
	pending_target_action = ""
	pending_target_z = -1
	_clear_highlights()
	_update_ui()

	turn = (turn + 1) % 3
	# Keep singleton in lockstep with the tactical authority (avoid GameState.set_turn,
	# which also bumps turn_count whenever team wraps to HAD).
	GameState.turn = turn
	if turn == 0:
		global_turn += 1
		GameState.turn_count = global_turn
		if Narrative: Narrative.log_event("GLOBAL TURN %d INITIATED" % global_turn, "system")
	GameState.record_event("turn_started", {"round": global_turn, "active_team": turn})

	if turn == player_faction:
		_ai_turn_active = false
		set_action_busy(false)
		turn_director.refresh_team_ap(player_faction, false)
		_auto_select()
		_update_ui()
		var pilot = Pilot.get_active_pilot(units, player_faction)
		var pilot_name = pilot.name if pilot else "Commander"
		_hint("Your turn (T%d). Piloting %s. Agents resolve on End Turn." % [global_turn, pilot_name])
	else:
		var fac_name = GameConfig.faction_name(turn)
		_hint("%s Turn..." % fac_name)
		await _run_ai_turn(turn)
		if not game_over:
			call_deferred("_end_turn")


func _run_ai_turn(faction: int) -> void:
	_ai_turn_active = true
	set_action_busy(true)
	turn_director.refresh_team_ap(faction, true)

	for u in units:
		if not u.alive or u.team != faction:
			continue
		# Skip empty-AP units (e.g. Proving Ground dummies) without spinning the guard loop.
		if u.max_ap <= 0 or u.ap <= 0:
			continue
		# Never auto-resolve a human-piloted body (defensive if turn misrouted).
		if Pilot.is_human_pilot(u):
			continue
		await _enemy_act(u)
		if game_over:
			break
	_ai_turn_active = false
	set_action_busy(false)

func _enemy_act(u) -> void:
	var guard = 0
	while u.alive and u.ap > 0 and not game_over and guard < Config.AI_GUARD_LIMIT:
		guard += 1
		var start_ap = u.ap
		var action_scores = AIBehavior.score_actions(u, units, cells, debris, sim_rng)
		if action_scores.is_empty():
			break
		var decision := String(action_scores.get("decision", "unknown"))
		var rationale := String(action_scores.get("rationale", "highest legal utility"))
		var decision_message := "%s [%s]: %s" % [
			u.name,
			decision.replace("_", " "),
			rationale
		]
		GameState.record_event("agent_decision", {
			"actor": u.unit_id,
			"team": u.team,
			"round": global_turn,
			"position": {"x": u.cell.x, "y": u.cell.y, "z": u.z},
			"ap_before": start_ap,
			"decision": decision,
			"rationale": rationale,
			"score": float(action_scores.get("score", 0.0))
		})
		if Narrative:
			Narrative.log_event(decision_message, "ai")
		_hint(decision_message)

		if action_scores.has("block"):
			u.blocking = true
			u.ap -= BLOCK_COST
			_refresh_label(u)
			break
		elif action_scores.has("take_cover"):
			var ai_cover := Vector2i(action_scores["take_cover"])
			if (
				MovementRules.can_take_cover(u, ai_cover, cells)
				and u.ap >= Config.TAKE_COVER_COST
			):
				_enter_cover_state(u, ai_cover, Config.TAKE_COVER_COST, "agent_ai")
			break
		elif action_scores.has("lean_cover"):
			if (
				MovementRules.can_lean(u, "left")
				and u.ap >= Config.LEAN_COST
			):
				u.ap -= Config.LEAN_COST
				u.lean = "left"
				_refresh_label(u)
				_update_ui()
			else:
				break
		elif action_scores.has("leave_cover"):
			if (
				MovementRules.can_leave_cover(u)
				and u.ap >= Config.LEAVE_COVER_COST
			):
				_leave_cover_state(u, Config.LEAVE_COVER_COST, "agent_ai")
			else:
				break
		elif action_scores.has("melee"):
			var tgt = action_scores["melee"]
			if is_instance_valid(tgt) and tgt.alive:
				var best_k = ""
				var best_d = Config.FIST_DMG
				var best_two = false
				for k in u.inv.keys():
					if int(u.inv.get(k, 0)) > 0:
						var item = ItemDB.get_item(k)
						var nm = item.get("name", k).to_lower()
						var two = nm.contains("rifle") or nm.contains("shotgun") or nm.contains("sniper") or k == "spear" or k == "club"
						var d = combat._melee_dmg(k, two)
						if d > best_d:
							best_d = d
							best_k = k
							best_two = two

				if best_two and (best_k == "spear" or best_k == "club" or best_k == "stringedbow"):
					var dir: Vector2i = tgt.cell - u.cell
					await combat._do_sweep(u, dir, best_k)
				else:
					await combat._do_bash(u, tgt, best_k, best_two)
			else:
				break
		elif action_scores.has("grab"):
			inventory.grab(u)
		elif action_scores.has("throw_spear"):
			var info: Dictionary = action_scores["throw_spear"]
			if not info["line"].is_empty():
				await combat._do_spear(u, info["line"], info["cost"], info["dmg"])
			else:
				break
		elif action_scores.has("throw_item"):
			var info: Dictionary = action_scores["throw_item"]
			if info.has("target") and is_instance_valid(info["target"]) and info["target"].alive:
				var is_thrown = ItemDB.get_item(info["kind"]).get("category", "") == "melee"
				await combat._do_generic_ranged(u, info["target"], info["kind"], info["cost"], info["dmg"], is_thrown)
			else:
				break
		elif action_scores.has("assemble_auto"):
			u.left = "bow"
			u.right = "string"
			u.two_handed = false
			inventory.assemble(u)
		elif action_scores.has("assemble"):
			inventory.assemble(u)
		elif action_scores.has("fire_bow"):
			# AIBehavior historically mixed Array (raw line) and Dictionary payloads.
			var raw_bow = action_scores["fire_bow"]
			var bow_info: Dictionary = {}
			if raw_bow is Dictionary:
				bow_info = raw_bow
			elif raw_bow is Array:
				bow_info = {
					"line": raw_bow,
					"cost": Config.BOW_COST,
					"dmg": Config.BOW_DMG
				}
			else:
				break
			var bow_line: Array = bow_info.get("line", [])
			if not bow_line.is_empty():
				await combat._do_fire_bow(
					u,
					bow_line,
					int(bow_info.get("cost", Config.BOW_COST)),
					int(bow_info.get("dmg", Config.BOW_DMG))
				)
			else:
				break
		elif action_scores.has("approach"):
			var path: Array = action_scores["approach"]
			if path.size() >= 2:
				await _step_enemy(u, Vector2i(path[1]))
			else:
				break
		elif action_scores.has("seek_cover"):
			var cover_route: Dictionary = action_scores["seek_cover"]
			var cover_path: Array = cover_route.get("path", [])
			if cover_path.size() >= 2:
				await _step_enemy(u, Vector2i(cover_path[1]))
			else:
				break
		elif action_scores.has("flank"):
			var flank_path: Array = action_scores["flank"]
			if flank_path.size() >= 2:
				await _step_enemy(u, Vector2i(flank_path[1]))
			else:
				break
		elif action_scores.has("step"):
			var step_cell: Vector2i = action_scores["step"]
			if step_cell != INVALID_CELL:
				await _step_enemy(u, step_cell)
			else:
				break
		else:
			break

		if u.ap >= start_ap:
			break

	await get_tree().process_frame

func _step_enemy(u, step: Vector2i) -> void:
	if u == null or not u.alive or u.node == null or not is_instance_valid(u.node):
		return
	if MovementRules.movement_locked(u) or Maneuvers.is_committed(u.maneuver):
		return
	if not cells.has(step):
		return
	# Occupied destination (except self) is illegal; skip rather than stack units.
	var occupant = _unit_at(step)
	if occupant != null and occupant != u:
		return
	var target_z: int = cells[step].get("z", 0)
	var mcost = ActionEconomy.movement_step_cost(u, u.z, target_z)
	if u.ap < mcost:
		return
	var previous_cell = u.cell
	var previous_z = u.z
	u.cell = step
	u.z = target_z
	u.last_move_direction = step - previous_cell
	_face_unit_toward(u, _cell_to_world(step))
	var tw = create_tween()
	tw.tween_property(u.node, "position", _cell_to_world(step), 0.07)
	await tw.finished
	var drop_dist = previous_z - target_z
	if drop_dist > 0 and not (u.hovering or u.flying):
		combat.apply_fall_damage(u, drop_dist)

	if not u.alive:
		_check_end()
		return

	u.ap -= mcost
	u.record_ground_step(u.move_mode)

# ==========================================================
#  HOVER & HIGHLIGHT PREVIEW
# ==========================================================
func _update_hover() -> void:
	_clear_highlights()
	if selected == null:
		return
	if pending_target_action == "flight":
		var air_cell = _mouse_cell_at_level(pending_target_z)
		if air_cell == INVALID_CELL:
			return
		var flight_ok = _flight_target_valid(selected, air_cell, pending_target_z)
		_highlight_air_cube(
			air_cell,
			pending_target_z,
			Color(0.20, 0.95, 1.0, 0.26) if flight_ok else Color(1.0, 0.22, 0.18, 0.24)
		)
		return

	var cell = _mouse_cell()
	if cell == INVALID_CELL:
		return
	if pending_target_action == "take_cover":
		var cover_ok = MovementRules.can_take_cover(selected, cell, cells)
		_highlight_tile(
			cell,
			Color(0.20, 0.95, 1.0) if cover_ok else Color(1.0, 0.22, 0.18)
		)
		return
	if pending_target_action == "jump":
		_highlight_tile(
			cell,
			Color(0.35, 1.0, 0.48) if _jump_target_valid(selected, cell) else Color(1.0, 0.22, 0.18)
		)
		return
	if pending_target_action == "wall_run":
		_highlight_tile(
			cell,
			Color(0.85, 0.45, 1.0) if _wall_run_target_valid(selected, cell) else Color(1.0, 0.22, 0.18)
		)
		return
	if pending_target_action == "wall_jump":
		_highlight_tile(
			cell,
			Color(1.0, 0.72, 0.20) if _wall_jump_target_valid(selected, cell) else Color(1.0, 0.22, 0.18)
		)
		return
	var occ = _unit_at(cell)
	if occ != null and occ.alive and occ.team != player_faction:
		_highlight_tile(cell, Color(1.0, 0.45, 0.1))
		return
	if not _cell_free(cell):
		return
	var path = Pathfinder.find_path(selected.cell, cell, cells, units, selected.flying or selected.hovering)
	if path.is_empty():
		return
	var cost = ActionEconomy.path_cost(selected, path, cells)
	_draw_path(path, selected.ap)
	_hint("MOVE PREVIEW: %d AP / %d remaining" % [cost, maxi(selected.ap - cost, 0)])


func _cell_to_world(c: Vector2i) -> Vector3:
	var height_units = 0.0
	if cells.has(c):
		var hz: int = cells[c].get("z", 0)
		height_units = float(hz)
	return Config.cell_to_world(c, height_units)

func get_smart_path(start_cell: Vector2i, goal_cell: Vector2i) -> Array[Vector2i]:
	return Pathfinder.path_toward(start_cell, goal_cell, cells, units)

func _resolve_jump_action(u, target: Vector2i) -> void:
	if Maneuvers.is_airborne(u.maneuver):
		_complete_jump(u, target)
	else:
		_begin_jump_anchor(u, target)

func _begin_jump_anchor(u, target: Vector2i) -> void:
	set_action_busy(true)
	_clear_highlights()
	var start_cell = u.cell
	var start_z = u.z
	var terrain_z = int(cells.get(target, {}).get("z", 0))
	var anchor_z = maxi(maxi(start_z, terrain_z) + 1, 1)
	u.ap -= Config.JUMP_COST
	u.maneuver = Maneuvers.airborne(
		start_cell,
		start_z,
		target,
		anchor_z,
		target,
		terrain_z,
		1,
		u.run_distance_this_turn,
		u.sprint_distance_this_turn,
		Config.JUMP_COST,
		global_turn,
		"jump"
	)
	var final_pos = _cell_to_world(target)
	final_pos.y = float(anchor_z) * Config.HEIGHT_STEP
	_face_unit_toward(u, final_pos)
	var mid_pos = u.node.position.lerp(final_pos, 0.5)
	mid_pos.y = maxf(u.node.position.y, final_pos.y) + 1.2
	var tw = create_tween()
	tw.tween_property(u.node, "position", mid_pos, 0.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(u.node, "position", final_pos, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	u.cell = target
	u.z = anchor_z
	u.update_figure()
	GameState.record_event("jump_anchor_reached", {
		"actor": u.unit_id,
		"from": {"x": start_cell.x, "y": start_cell.y, "z": start_z},
		"anchor": {"x": u.cell.x, "y": u.cell.y, "z": u.z},
		"planned_landing": {"x": target.x, "y": target.y, "z": terrain_z},
		"momentum": u.maneuver.get("momentum", {}).duplicate(true),
		"ap_spent": Config.JUMP_COST
	})
	_refresh_label(u)
	_update_ui()
	_hint("%s reaches an airborne jump anchor. Attack, Flip, or spend AP to complete the jump." % u.name)
	set_action_busy(false)

func _complete_jump(u, target: Vector2i) -> void:
	set_action_busy(true)
	_clear_highlights()
	var start_cell = u.cell
	var start_z = u.z
	var terrain_z = int(cells.get(target, {}).get("z", 0))
	u.ap -= Config.JUMP_COST
	var final_pos = _cell_to_world(target)
	final_pos.y = float(terrain_z) * Config.HEIGHT_STEP
	_face_unit_toward(u, final_pos)
	var tw = create_tween()
	if target != start_cell:
		var mid_pos = u.node.position.lerp(final_pos, 0.5)
		mid_pos.y = maxf(u.node.position.y, final_pos.y) + 1.0
		tw.tween_property(u.node, "position", mid_pos, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(u.node, "position", final_pos, 0.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	u.cell = target
	u.z = terrain_z
	u.maneuver = Maneuvers.grounded("jump_completed")
	u.wall_running = false
	u.flipping = false
	u.update_figure()
	GameState.record_event("jump_resolved", {
		"actor": u.unit_id,
		"from": {"x": start_cell.x, "y": start_cell.y, "z": start_z},
		"to": {"x": u.cell.x, "y": u.cell.y, "z": u.z},
		"ap_spent": Config.JUMP_COST,
		"stage": 2
	})
	_refresh_label(u)
	_update_ui()
	_hint("%s completes the jump and lands." % u.name)
	set_action_busy(false)

func _jump_target_valid(u, target: Vector2i) -> bool:
	if u == null or target == INVALID_CELL or not cells.has(target) or u.ap < Config.JUMP_COST:
		return false
	var occupied = _unit_at(target)
	if occupied != null and occupied != u:
		return false
	var distance = absi(u.cell.x - target.x) + absi(u.cell.y - target.y)
	var target_height = int(cells.get(target, {}).get("z", 0))
	if Maneuvers.is_airborne(u.maneuver):
		return (
			distance <= 2
			and int(cells[target].get("type", FLOOR)) == FLOOR
			and target_height <= u.z + Config.MAX_JUMP_STEP
		)
	if not MovementRules.can_initiate_jump(u, _special_enabled(u, "precision_jump")):
		return false
	return (
		distance == 2
		and _cell_free(target)
		and absi(target_height - u.z) <= Config.MAX_JUMP_STEP
	)

func _wall_run_target_valid(u, target: Vector2i) -> bool:
	if u == null or u.ap < Config.WALL_RUN_COST:
		return false
	if Maneuvers.is_wall_running(u.maneuver):
		var active_wall = Maneuvers.vector2(u.maneuver.get("wall_cell", {}), INVALID_CELL)
		return (
			(target == INVALID_CELL or target == active_wall)
			and MovementRules.can_continue_wall_run(u, cells)
		)
	return MovementRules.can_begin_wall_run(u, target, cells)

func _resolve_wall_run(u, target: Vector2i) -> void:
	set_action_busy(true)
	_clear_highlights()
	var continuing = Maneuvers.is_wall_running(u.maneuver)
	var wall_cell = target
	if continuing:
		wall_cell = Maneuvers.vector2(u.maneuver.get("wall_cell", {}), INVALID_CELL)
	var start_z = u.z
	var next_z = u.z + 1
	u.ap -= Config.WALL_RUN_COST
	if continuing:
		var next_state = u.maneuver.duplicate(true)
		next_state["stage"] = int(next_state.get("stage", 1)) + 1
		next_state["anchor"] = Maneuvers.point(u.cell, next_z)
		next_state["wall_cell"] = Maneuvers.point(wall_cell, next_z)
		next_state["ap_spent"] = int(next_state.get("ap_spent", 0)) + Config.WALL_RUN_COST
		u.maneuver = Maneuvers.normalize(next_state)
	else:
		var wall_normal = u.cell - wall_cell
		var forward = u.last_move_direction
		if forward == Vector2i.ZERO or forward == wall_normal or forward == -wall_normal:
			forward = Vector2i(-wall_normal.y, wall_normal.x)
		u.maneuver = Maneuvers.wall_run(
			u.cell,
			u.z,
			u.cell,
			next_z,
			wall_cell,
			wall_normal,
			forward,
			u.run_distance_this_turn,
			u.sprint_distance_this_turn,
			Config.WALL_RUN_COST,
			global_turn
		)
	u.wall_running = true
	_face_unit_toward(u, _cell_to_world(wall_cell))
	var final_pos = u.node.position
	final_pos.y = float(next_z) * Config.HEIGHT_STEP
	var tw = create_tween()
	tw.tween_property(u.node, "position", final_pos, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished
	u.z = next_z
	u.update_figure()
	GameState.record_event("wall_run_segment", {
		"actor": u.unit_id,
		"wall": {"x": wall_cell.x, "y": wall_cell.y},
		"from_z": start_z,
		"to_z": u.z,
		"ap_spent": Config.WALL_RUN_COST,
		"stage": int(u.maneuver.get("stage", 1))
	})
	_refresh_label(u)
	_update_ui()
	if Narrative:
		Narrative.generate_mobility_narrative(u.name, "WALL RUN")
	_hint("%s treats the selected wall as local ground." % u.name)
	set_action_busy(false)

func _wall_jump_target_valid(u, target: Vector2i) -> bool:
	if (
		u == null
		or target == INVALID_CELL
		or not cells.has(target)
		or u.ap < Config.WALL_JUMP_COST
		or not MovementRules.can_wall_jump(u)
		or not _cell_free(target)
	):
		return false
	var distance = absi(u.cell.x - target.x) + absi(u.cell.y - target.y)
	if distance < 1 or distance > 2:
		return false
	var normal = Maneuvers.vector2(u.maneuver.get("wall_normal", {}), Vector2i.ZERO)
	var delta = target - u.cell
	if delta.x * normal.x + delta.y * normal.y < 0:
		return false
	var terrain_z = int(cells[target].get("z", 0))
	return terrain_z <= u.z + Config.MAX_JUMP_STEP

func _resolve_wall_jump(u, target: Vector2i) -> void:
	set_action_busy(true)
	_clear_highlights()
	var start_cell = u.cell
	var start_z = u.z
	var terrain_z = int(cells.get(target, {}).get("z", 0))
	var anchor_z = maxi(u.z, terrain_z + 1)
	var wall_cell = Maneuvers.vector2(u.maneuver.get("wall_cell", {}), INVALID_CELL)
	u.ap -= Config.WALL_JUMP_COST
	u.wall_running = false
	u.maneuver = Maneuvers.airborne(
		start_cell,
		start_z,
		target,
		anchor_z,
		target,
		terrain_z,
		1,
		u.run_distance_this_turn,
		u.sprint_distance_this_turn,
		Config.WALL_JUMP_COST,
		global_turn,
		"wall_jump"
	)
	var final_pos = _cell_to_world(target)
	final_pos.y = float(anchor_z) * Config.HEIGHT_STEP
	_face_unit_toward(u, final_pos)
	var mid_pos = u.node.position.lerp(final_pos, 0.5)
	mid_pos.y = maxf(u.node.position.y, final_pos.y) + 1.0
	var tw = create_tween()
	tw.tween_property(u.node, "position", mid_pos, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(u.node, "position", final_pos, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	u.cell = target
	u.z = anchor_z
	u.update_figure()
	GameState.record_event("wall_jump_anchor_reached", {
		"actor": u.unit_id,
		"wall": {"x": wall_cell.x, "y": wall_cell.y},
		"from": {"x": start_cell.x, "y": start_cell.y, "z": start_z},
		"anchor": {"x": u.cell.x, "y": u.cell.y, "z": u.z},
		"ap_spent": Config.WALL_JUMP_COST
	})
	_refresh_label(u)
	_update_ui()
	if Narrative:
		Narrative.generate_mobility_narrative(u.name, "WALL JUMP")
	_hint("%s wall-jumps into an airborne maneuver." % u.name)
	set_action_busy(false)

func _flip_airborne(u) -> void:
	set_action_busy(true)
	u.ap -= Config.FLIP_COST
	u.flipping = true
	var start_rotation = u.node.rotation
	var tw = create_tween()
	tw.tween_property(u.node, "rotation", start_rotation + Vector3(0, 0, TAU), 0.32).set_trans(Tween.TRANS_SINE)
	await tw.finished
	u.node.rotation = start_rotation
	GameState.record_event("airborne_dodge", {
		"actor": u.unit_id,
		"method": "flip",
		"position": {"x": u.cell.x, "y": u.cell.y, "z": u.z},
		"ap_spent": Config.FLIP_COST
	})
	_update_ui()
	if Narrative:
		Narrative.generate_mobility_narrative(u.name, "FLIP")
	_hint("%s executes an airborne Dodge roll." % u.name)
	set_action_busy(false)

func schedule_maneuver_support_check(u) -> void:
	if u != null:
		call_deferred("_resolve_maneuver_support_after_action", u)

func _resolve_maneuver_support_after_action(u) -> void:
	await get_tree().process_frame
	while busy and not game_over:
		await get_tree().process_frame
	if (
		u == null
		or not u.alive
		or u.ap > 0
		or not Maneuvers.is_committed(u.maneuver)
	):
		return
	await _detach_maneuver(u, "ap_exhausted")

func _detach_maneuver(u, reason: String) -> void:
	if u == null or not u.alive or not Maneuvers.is_committed(u.maneuver):
		return
	set_action_busy(true)
	var previous_phase = String(u.maneuver.get("phase", Maneuvers.GROUNDED))
	var start_z = u.z
	var start_hp = u.hp
	var terrain_z = int(cells.get(u.cell, {}).get("z", 0))
	var drop_distance = maxi(start_z - terrain_z, 0)
	if u.node != null:
		var final_pos = _cell_to_world(u.cell)
		final_pos.y = float(terrain_z) * Config.HEIGHT_STEP
		var tw = create_tween()
		tw.tween_property(u.node, "position", final_pos, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await tw.finished
	u.z = terrain_z
	u.maneuver = Maneuvers.grounded(reason)
	u.wall_running = false
	u.flipping = false
	if drop_distance > 0:
		combat.apply_fall_damage(u, drop_distance)
		if u.alive:
			u.stance = "prone"
	var fall_damage = maxi(start_hp - u.hp, 0)
	if u.alive:
		u.update_figure()
	GameState.record_event("maneuver_detached", {
		"actor": u.unit_id,
		"phase": previous_phase,
		"reason": reason,
		"drop": drop_distance,
		"damage": fall_damage,
		"recovery": "prone" if drop_distance > 0 and u.alive else "grounded"
	})
	_refresh_label(u)
	_update_ui()
	var result_message = "%s loses support, falls, and recovers prone." % u.name
	if reason == "ap_exhausted":
		result_message = (
			"AIRBORNE AP EXHAUSTED - %s detaches, falls %d level(s), takes %d damage, and lands PRONE."
			% [u.name, drop_distance, fall_damage]
		)
	if Narrative:
		Narrative.log_event(result_message, "tactical")
	_hint(result_message)
	set_action_busy(false)

func _flight_target_valid(u, target: Vector2i, target_height: int) -> bool:
	if u == null or not u.flying or target == INVALID_CELL or not cells.has(target):
		return false
	if target_height < int(cells[target].get("z", 0)) or target_height > Config.MAX_FLIGHT_Z:
		return false
	var occupied = _unit_at(target)
	if occupied != null and occupied != u:
		return false
	var flight_cost = ActionEconomy.flight_cost(u.cell, u.z, target, target_height)
	return (target != u.cell or target_height != u.z) and flight_cost <= u.ap

func _fly_unit(u, target: Vector2i, target_height: int, cost: int) -> void:
	set_action_busy(true)
	_clear_highlights()
	var start_cell = u.cell
	var start_z = u.z
	u.ap -= cost
	var start_pos = u.node.position
	var final_pos = _cell_to_world(target)
	final_pos.y = target_height * Config.HEIGHT_STEP
	_face_unit_toward(u, final_pos)
	var mid_pos = start_pos.lerp(final_pos, 0.5)
	mid_pos.y = maxf(start_pos.y, final_pos.y) + 0.8
	var tw = create_tween()
	tw.tween_property(u.node, "position", mid_pos, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(u.node, "position", final_pos, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	u.cell = target
	u.z = target_height
	var terrain_z = int(cells[target].get("z", 0))
	if target_height == terrain_z:
		u.flying = false
		if Narrative:
			Narrative.generate_mobility_narrative(u.name, "LAND")
	else:
		u.flying = true
		if Narrative:
			Narrative.generate_mobility_narrative(u.name, "FLIGHT")
	GameState.record_event("flight_resolved", {
		"actor": u.unit_id,
		"from": {"x": start_cell.x, "y": start_cell.y, "z": start_z},
		"to": {"x": u.cell.x, "y": u.cell.y, "z": u.z},
		"ap_spent": cost,
		"landed": not u.flying
	})
	_refresh_label(u)
	_update_ui()
	set_action_busy(false)

func _face_unit_toward(u, target_world: Vector3) -> void:
	if u == null or u.node == null:
		return
	var direction = target_world - u.node.position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	# Godot models face local -Z by default.
	u.node.rotation.y = atan2(-direction.x, -direction.z)

func _world_to_cell(p: Vector3) -> Vector2i:
	return Config.world_to_cell(p)

func _mouse_cell() -> Vector2i:
	if camera_controller == null or camera_controller.camera == null:
		return INVALID_CELL
	var cam: Camera3D = camera_controller.camera
	var mp = get_viewport().get_mouse_position()
	var from = cam.project_ray_origin(mp)
	var dir = cam.project_ray_normal(mp).normalized()
	# Height-aware pick: march the ray, return the first cell whose voxel top it descends into.
	var step = maxf(cell_size * 0.3, 0.25)
	var t = 0.0
	while t < 240.0:
		var pos = from + dir * t
		var c = _world_to_cell(pos)
		if c.x >= 0 and c.y >= 0 and c.x < GRID_W and c.y < GRID_H:
			var top_y = 0.0
			if cells.has(c):
				top_y = float(cells[c].get("z", 0)) * Config.HEIGHT_STEP
			if pos.y <= top_y + 0.05:
				return c
		t += step
	# fallback: flat ground plane
	if absf(dir.y) > 0.0001:
		var tp = -from.y / dir.y
		if tp > 0.0:
			var c2 = _world_to_cell(from + dir * tp)
			if c2.x >= 0 and c2.y >= 0 and c2.x < GRID_W and c2.y < GRID_H:
				return c2
	return INVALID_CELL

func _mouse_cell_at_level(level: int) -> Vector2i:
	if camera_controller == null or camera_controller.camera == null or level < 0:
		return INVALID_CELL
	var cam: Camera3D = camera_controller.camera
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = cam.project_ray_origin(mouse_pos)
	var ray_direction = cam.project_ray_normal(mouse_pos).normalized()
	if absf(ray_direction.y) <= 0.0001:
		return INVALID_CELL
	var plane_y = float(level) * Config.HEIGHT_STEP
	var ray_distance = (plane_y - ray_origin.y) / ray_direction.y
	if ray_distance <= 0.0:
		return INVALID_CELL
	var target = _world_to_cell(ray_origin + ray_direction * ray_distance)
	if target.x < 0 or target.y < 0 or target.x >= GRID_W or target.y >= GRID_H:
		return INVALID_CELL
	return target

func _unit_at(c: Vector2i) :
	for u in units:
		if u.alive and u.cell == c:
			return u
	return null

func _cell_free(c: Vector2i) -> bool:
	return Pathfinder.cell_free(c, cells, units)

## Single authority for terrain damage: it changes the cell, rebuilds the tile so
## the world matches the simulation, and records the change in the ledger. Returns
## the recorded delta, or an empty dictionary when nothing changed.
func damage_terrain(cell: Vector2i, damage: int, weapon: String = "", attacker = null) -> Dictionary:
	if damage <= 0 or not cells.has(cell):
		return {}
	var before: Dictionary = cells[cell]
	var integrity_before := Ballistics.density_of(before)
	if integrity_before <= 0:
		return {}
	var after: Dictionary = Ballistics.degrade_cell(before, damage)
	var integrity_after := Ballistics.density_of(after)
	# The two defaults differ on purpose. A cell missing `type` entirely must compare unequal so
	# the change is still recorded rather than silently dropped as a no-op; matching defaults
	# would make "no type before" and "no type after" look identical.
	if integrity_after == integrity_before and int(after.get("type", -1)) == int(before.get("type", -2)):
		return {}
	cells[cell] = after
	if GameState:
		GameState.cells = cells
	# Conservation of matter: a tier that fails does not cease to exist, it comes down. Each
	# lost tier becomes debris on the cell through the existing debris system — the same
	# rocks a unit can pick up and throw — rather than a second inventory of rubble. Without
	# this, destruction quietly deleted material from the world and the simulation stopped
	# holding water.
	var tiers_lost := int(after.get("tiers_lost", 0))
	if tiers_lost > 0:
		_add_debris(cell, "rock", tiers_lost)
	var cover_before := Ballistics.effective_cover_level(before)
	var cover_after := Ballistics.effective_cover_level(after)
	# Redraw whenever the tile should *look* different, not only when it crosses a height or
	# cover threshold. The old condition was `z changed or cover level changed`, both of which
	# are threshold crossings, so a wall could take three rounds, lose a third of its
	# material, and never be redrawn — which is why damage appeared to arrive in three sudden
	# jumps rather than accumulating. The signature includes type and z, so it subsumes both
	# of the conditions it replaces.
	if WorldBuilderScript.tile_visual_signature(before) != WorldBuilderScript.tile_visual_signature(after):
		_rebuild_tile(cell)
	var delta := {
		"cell": {"x": cell.x, "y": cell.y, "z": int(before.get("z", 0))},
		"weapon": weapon,
		"attacker": int(attacker.unit_id) if attacker != null else 0,
		"material_before": String(before.get("material", "")),
		"material_after": String(after.get("material", "")),
		"integrity_before": integrity_before,
		"integrity_after": integrity_after,
		"cover_before": cover_before,
		"cover_after": cover_after,
		"destroyed": cover_after == 0 and cover_before > 0
	}
	terrain_changes.append(delta)
	GameState.record_event("terrain_damaged", delta)
	if bool(delta["destroyed"]):
		_hint("Cover destroyed at %d,%d." % [cell.x, cell.y])
	# A unit committed to cover that no longer protects is released rather than
	# left holding a wall that is not there. This is not their action: routing it
	# through the ordinary leave_cover verb charged them AP for someone else's shot,
	# and silently failed when they had none — leaving them flagged as in cover,
	# movement-locked, behind rubble, permanently.
	if cover_after < 2:
		for unit in units:
			if unit != null and bool(unit.taking_cover) and Vector2i(unit.cover_cell) == cell:
				_leave_cover_state(unit, 0, "cover_destroyed")
	return delta

func _rebuild_tile(cell: Vector2i) -> void:
	if tiles_root == null or not is_instance_valid(tiles_root):
		return
	var existing := tiles_root.get_node_or_null("Tile_%d_%d" % [cell.x, cell.y])
	if existing != null:
		# `queue_free` alone defers removal to the end of the frame, so the
		# replacement was added while the old node was still a child and Godot
		# renamed it to avoid the collision. Detaching first frees the name
		# immediately, which keeps exactly one addressable tile per cell.
		tiles_root.remove_child(existing)
		existing.queue_free()
	var data: Dictionary = cells.get(cell, {})
	WorldBuilderScript.spawn_tile(
		tiles_root,
		cell,
		int(data.get("type", Config.FLOOR)),
		int(data.get("z", 0)),
		mission_seed,
		# The whole cell, not just its material tag. Appearance is derived from the
		# integrity it has left against the density it started with, so a wall that has
		# taken four rounds looks like a wall that has taken four rounds instead of
		# staying pristine until it crosses a threshold.
		data
	)

## Elevation-aware: the caller supplies the shooter's and target's heights so a
## wall the shooter can see over stops protecting.
func _in_cover(from_c: Vector2i, target_c: Vector2i, from_z: int = 0, target_z: int = 0) -> int:
	# Derived from the material still standing in the lane, so a wall shot to
	# rubble stops reducing damage without a second rule.
	return AITacticsScript.cover_level(from_c, target_c, cells, from_z, target_z)

func cover_options(unit) -> Array[Vector2i]:
	return MovementRules.cover_options(unit, cells)

func wall_run_options(unit) -> Array[Vector2i]:
	return MovementRules.wall_options(unit, cells)

func can_begin_jump(unit) -> bool:
	if unit == null:
		return false
	if Maneuvers.is_airborne(unit.maneuver):
		return unit.ap >= Config.JUMP_COST
	return (
		unit.ap >= Config.JUMP_COST
		and MovementRules.can_initiate_jump(unit, _special_enabled(unit, "precision_jump"))
	)

func _special_enabled(unit, special_name: String) -> bool:
	# Pre-alpha: specials (including Remotes) ride the developer God Mode toggle
	# unless the unit already carries the skill token.
	return unit != null and unit.has_special(special_name, dev_god_mode)

func _unit_accepts_human_input(unit) -> bool:
	return Pilot.is_human_pilot(unit)

func _get_commander():
	return Pilot.get_commander(units, player_faction)

func _active_human_pilot():
	return Pilot.get_active_pilot(units, player_faction)

func _set_human_pilot(unit) -> void:
	if not Pilot.set_human_pilot(units, player_faction, unit):
		return
	selected = unit
	if unit != null and unit.node != null and camera_controller:
		camera_controller.focus_unit(unit.node)
	_update_ui()

func _remotes_login(target) -> bool:
	var result: Dictionary = Pilot.remotes_login(units, player_faction, target)
	if not bool(result.get("ok", false)):
		_hint("Remotes: %s." % String(result.get("reason", "failed")))
		return false
	var pilot = result.get("pilot", null)
	selected = pilot
	if pilot != null and pilot.node != null and camera_controller:
		camera_controller.focus_unit(pilot.node)
	GameState.record_event("remotes_login", {
		"pilot": pilot.unit_id if pilot else 0,
		"name": String(pilot.name) if pilot else "",
		"reason": String(result.get("reason", ""))
	})
	if String(result.get("reason", "")) == "home":
		_hint("REMOTES: returned to Commander (%s)." % (pilot.name if pilot else "?"))
	else:
		_hint("REMOTES LINK: now piloting %s. End Turn still runs remaining AI agents." % (pilot.name if pilot else "?"))
	_update_ui()
	return true

func _remotes_return_home() -> bool:
	var result: Dictionary = Pilot.remotes_return_home(units, player_faction)
	if not bool(result.get("ok", false)):
		_hint("Remotes: %s." % String(result.get("reason", "failed")))
		return false
	var pilot = result.get("pilot", null)
	selected = pilot
	if pilot != null and pilot.node != null and camera_controller:
		camera_controller.focus_unit(pilot.node)
	GameState.record_event("remotes_home", {"pilot": pilot.unit_id if pilot else 0})
	_hint("REMOTES: returned to Commander (%s)." % (pilot.name if pilot else "?"))
	_update_ui()
	return true

## Player pressed End Turn: resolve autonomous squad bots, then advance factions.
func _player_finish_turn() -> void:
	if busy or game_over or turn != player_faction:
		return
	pending_target_action = ""
	pending_target_z = -1
	_clear_highlights()
	await _run_ally_bot_turn()
	if game_over or not is_inside_tree():
		return
	await _end_turn()

## Utility-AI pass for squad bots that are not currently player-controlled.
func _run_ally_bot_turn() -> void:
	var bots: Array = turn_director.ally_bots_ready_to_act(player_faction)
	if bots.is_empty():
		return
	_ai_turn_active = true
	set_action_busy(true)
	_hint("Allied agents executing...")
	_update_ui()
	for u in bots:
		if not u.alive or game_over:
			break
		# Do not re-grant AP; they already refreshed at the start of the player phase.
		await _enemy_act(u)
		if game_over:
			break
	_ai_turn_active = false
	set_action_busy(false)
	_update_ui()

func _enter_cover_state(unit, target: Vector2i, cost: int, source: String) -> void:
	unit.ap -= maxi(cost, 0)
	unit.taking_cover = true
	unit.cover_cell = target
	unit.blocking = true
	unit.lean = "none"
	_face_unit_toward(unit, _cell_to_world(target))
	GameState.record_event("cover_entered", {
		"actor": unit.unit_id,
		"position": {"x": unit.cell.x, "y": unit.cell.y, "z": unit.z},
		"cover": {"x": target.x, "y": target.y},
		"ap_spent": maxi(cost, 0),
		"source": source
	})
	_refresh_label(unit)
	_update_ui()
	if source == "cover_monkey":
		_hint("%s slides into cover and braces." % unit.name)
	else:
		_hint("%s takes cover and braces. Movement is committed until cover is released." % unit.name)

func _leave_cover_state(unit, cost: int, source: String) -> void:
	var previous_cover = unit.cover_cell
	unit.ap -= maxi(cost, 0)
	unit.taking_cover = false
	unit.cover_cell = INVALID_CELL
	unit.blocking = false
	unit.lean = "none"
	GameState.record_event("cover_left", {
		"actor": unit.unit_id,
		"position": {"x": unit.cell.x, "y": unit.cell.y, "z": unit.z},
		"cover": {"x": previous_cover.x, "y": previous_cover.y},
		"ap_spent": maxi(cost, 0),
		"source": source
	})
	_refresh_label(unit)
	_update_ui()
	if source != "cover_monkey_move":
		_hint("%s leaves cover." % unit.name)

func _auto_cover_monkey(unit) -> void:
	var options = cover_options(unit)
	if options.is_empty():
		return
	var nearest_hostile = null
	var nearest_distance = 1_000_000
	for other in units:
		if not other.alive or other.team == unit.team:
			continue
		var distance = absi(unit.cell.x - other.cell.x) + absi(unit.cell.y - other.cell.y)
		if distance < nearest_distance or (
			distance == nearest_distance
			and (nearest_hostile == null or other.unit_id < nearest_hostile.unit_id)
		):
			nearest_distance = distance
			nearest_hostile = other
	var best: Vector2i = options[0]
	var best_score = -1_000_000
	for option in options:
		var score = 0
		if nearest_hostile != null:
			var cover_direction: Vector2i = option - unit.cell
			var threat_delta: Vector2i = nearest_hostile.cell - unit.cell
			score += cover_direction.x * signi(threat_delta.x)
			score += cover_direction.y * signi(threat_delta.y)
		if (
			score > best_score
			or (
				score == best_score
				and (option.x < best.x or (option.x == best.x and option.y < best.y))
			)
		):
			best = option
			best_score = score
	_enter_cover_state(unit, best, 0, "cover_monkey")

func _clear_highlights() -> void:
	for child in highlight_root.get_children():
		child.queue_free()

func _highlight_tile(c: Vector2i, col: Color) -> void:
	if c.x < 0 or c.y < 0 or c.x >= GRID_W or c.y >= GRID_H:
		return
	var mi = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(cell_size * 0.9, 0.08, cell_size * 0.9)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col * 0.6
	box.material = mat
	mi.mesh = box
	mi.position = _cell_to_world(c) + Vector3(0, 0.16, 0)
	highlight_root.add_child(mi)

func _highlight_air_cube(c: Vector2i, level: int, col: Color) -> void:
	if not cells.has(c):
		return
	var mi = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(cell_size * 0.82, 1.35, cell_size * 0.82)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(col.r, col.g, col.b)
	mat.emission_energy_multiplier = 1.5
	box.material = mat
	mi.mesh = box
	var world_pos = _cell_to_world(c)
	world_pos.y = float(level) * Config.HEIGHT_STEP
	mi.position = world_pos
	highlight_root.add_child(mi)

func _draw_path(path: Array[Vector2i], budget: int) -> void:
	if selected == null:
		return
	var cumulative_cost = 0
	var current_z = selected.z
	for i in range(1, path.size()):
		var next_z = int(cells.get(path[i], {}).get("z", 0))
		if selected.hovering or selected.flying:
			next_z = maxi(next_z, current_z)
		cumulative_cost += ActionEconomy.movement_step_cost(selected, current_z, next_z)
		var within = cumulative_cost <= budget
		var col: Color = Color(0.20, 0.90, 1.0) if within else Color(0.90, 0.25, 0.25)
		_highlight_tile(path[i], col)
		current_z = next_z

func _auto_select() -> void:
	var pick = Pilot.pick_default_selection(units, player_faction)
	if pick == null:
		for u in units:
			if u.alive and u.team == player_faction:
				pick = u
				break
	selected = pick
	if selected != null and selected.node != null and camera_controller:
		camera_controller.focus_unit(selected.node)

func _refresh_label(u) -> void:
	if u == null:
		return
	if u.label != null and is_instance_valid(u.label):
		var b = "  [B]" if u.blocking else ""
		var a = "  [A: %d]" % u.armor if u.armor > 0 else ""
		u.label.text = "%d%s%s" % [max(u.hp, 0), a, b]
	if u.fig != null and is_instance_valid(u.fig):
		u.update_figure()

func _hp_color(u) -> Color:
	var r = float(u.hp) / float(u.max_hp)
	if r > 0.6: return Color(0.3, 0.85, 0.4)
	elif r > 0.3: return Color(0.95, 0.8, 0.2)
	return Color(0.95, 0.3, 0.25)

func _update_ui() -> void:
	if tutorial != null and bool(tutorial.active):
		var tutorial_commander = _get_commander()
		tutorial.set_defense_affordable(
			tutorial_commander != null and int(tutorial_commander.ap) >= BLOCK_COST
		)
	if tactical_ui:
		tactical_ui.update_ui()

	if sel_ring:
		if selected != null and selected.alive and selected.node != null and is_instance_valid(selected.node):
			sel_ring.visible = true
			sel_ring.position = selected.node.position + Vector3(0, 0.05, 0)
		else:
			sel_ring.visible = false

	# Soft AP coaching only when the HUD is idle — never stomp maneuver/combat results
	# (deferred busy->ready refresh used to overwrite AIRBORNE AP EXHAUSTED, etc.).
	if turn == player_faction and not game_over and not busy and tactical_ui and tactical_ui.hint_label:
		var current_hint := String(tactical_ui.hint_label.text)
		var critical := (
			current_hint.contains("AIRBORNE")
			or current_hint.contains("VICTORY")
			or current_hint.contains("DEFEAT")
			or current_hint.contains("REMOTES")
			or current_hint.contains("hit")
			or current_hint.contains("FALL")
		)
		if not critical:
			var pilot = _active_human_pilot()
			if pilot != null and int(pilot.ap) <= 0:
				_hint("Pilot AP exhausted - End Turn to run allied agents, then enemies.")
			elif pilot == null:
				var any_ap = false
				for u in units:
					if u.alive and u.team == player_faction and u.ap > 0:
						any_ap = true
						break
				if not any_ap:
					_hint("Squad AP Exhausted - Pass Turn [SPACE / End Turn]")

	_update_fov()
	_publish_web_observation()

func _refresh_interaction_ui() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or busy:
		return
	_update_ui()

func _update_fov() -> void:
	if dev_god_mode:
		for u in units:
			if u.node: u.node.visible = u.alive
		return

	var player_cells = []
	for u in units:
		if u.team == player_faction and u.alive:
			player_cells.append(u.cell)

	for u in units:
		if u.team != player_faction and u.node:
			var vis = false
			for pc in player_cells:
				var dist = abs(pc.x - u.cell.x) + abs(pc.y - u.cell.y)
				if dist <= Config.TACTICAL_SENSOR_RADIUS:
					vis = true
					break
			u.node.visible = vis and u.alive

func _hint(msg: String) -> void:
	if tactical_ui and tactical_ui.has_method("hint"):
		tactical_ui.hint(msg)

func _play_sfx(sound_name: String, pos: Variant = null) -> void:
	var aud = get_node_or_null("/root/AudioSystem")
	if aud:
		if pos != null:
			aud.play_3d(sound_name, pos)
		else:
			aud.play_2d(sound_name)

func _setup_action_router() -> void:
	ActionRouter.bind(self)

func _setup_tutorial(payload: Dictionary) -> void:
	tutorial = Tutorial.new()
	tutorial.guidance_changed.connect(_on_tutorial_guidance)
	GameState.action_performed.connect(_on_tutorial_action)
	GameState.record_added.connect(_on_tutorial_record)
	tutorial.begin(payload, player_faction, global_turn)

func _on_tutorial_guidance(snapshot: Dictionary) -> void:
	if tactical_ui and tactical_ui.has_method("set_tutorial_guidance"):
		tactical_ui.set_tutorial_guidance(snapshot)
	if bool(snapshot.get("active", false)):
		GameState.record_event("tutorial_step_changed", {
			"step": String(snapshot.get("step_key", "")),
			"display_step": int(snapshot.get("display_step", 0)),
			"total_steps": int(snapshot.get("total_steps", 0)),
			"complete": bool(snapshot.get("complete", false))
		})
	_publish_web_observation()

func _build_web_observation() -> Dictionary:
	if tutorial == null or not bool(tutorial.active):
		return {}

	var raw_tutorial: Dictionary = tutorial.current_snapshot()
	var tutorial_snapshot := {
		"step": String(raw_tutorial.get("step_key", "")),
		"display_step": int(raw_tutorial.get("display_step", 0)),
		"total_steps": int(raw_tutorial.get("total_steps", 0)),
		"complete": bool(raw_tutorial.get("complete", false)),
		"cover_available": bool(raw_tutorial.get("cover_available", false)),
		"defense_affordable": bool(raw_tutorial.get("defense_affordable", true))
	}
	var viewport_size := get_viewport().get_visible_rect().size
	var observation := {
		"kind": "observation",
		"round": global_turn,
		"active_team": turn,
		"viewport": {
			"w": maxi(roundi(viewport_size.x), 0),
			"h": maxi(roundi(viewport_size.y), 0)
		},
		"tutorial": tutorial_snapshot,
		"accessibility": _observation_accessibility(),
		"layout": _observation_layout(),
		"actor": {},
		"move_targets": [],
		"cover_faces": [],
		"attack_targets": []
	}

	var actor = selected
	if actor == null or not bool(actor.alive) or int(actor.team) != player_faction:
		actor = _get_commander()
	if actor == null or not bool(actor.alive):
		return {}

	var actor_screen = _screen_of_cell(actor.cell)
	if (
		actor.node == null
		or not is_instance_valid(actor.node)
		or actor_screen == null
	):
		return {}
	observation["actor"] = {
		"name": String(actor.name),
		"unit_id": int(actor.unit_id),
		"team": int(actor.team),
		"cell": {"x": actor.cell.x, "y": actor.cell.y, "z": int(actor.z)},
		"ap": int(actor.ap),
		"is_commander": bool(actor.is_commander),
		"screen": actor_screen
	}

	var move_targets: Array = []
	for dy in range(-OBSERVATION_RADIUS, OBSERVATION_RADIUS + 1):
		for dx in range(-OBSERVATION_RADIUS, OBSERVATION_RADIUS + 1):
			var candidate: Vector2i = actor.cell + Vector2i(dx, dy)
			if candidate == actor.cell or not _cell_free(candidate):
				continue
			var path = Pathfinder.find_path(
				actor.cell,
				candidate,
				cells,
				units,
				bool(actor.flying) or bool(actor.hovering)
			)
			if path.size() < 2:
				continue
			var affordable: Array[Vector2i] = ActionEconomy.affordable_path(actor, path, cells)
			if affordable.size() != path.size() or affordable.back() != candidate:
				continue
			var cost := int(ActionEconomy.path_cost(actor, path, cells))
			if cost <= 0 or cost > int(actor.ap):
				continue
			var screen = _screen_of_cell(candidate)
			if screen == null:
				continue
			move_targets.append({
				"cell": _observation_cell(candidate),
				"ap": cost,
				"screen": screen
			})
	observation["move_targets"] = move_targets.slice(
		0,
		mini(move_targets.size(), OBSERVATION_MOVE_CAP)
	)

	var cover_faces: Array = []
	for cover_cell in cover_options(actor):
		if cover_faces.size() >= OBSERVATION_COVER_CAP:
			break
		var screen = _screen_of_cell(cover_cell)
		if screen == null:
			continue
		cover_faces.append({
			"cell": _observation_cell(cover_cell),
			"screen": screen
		})
	observation["cover_faces"] = cover_faces

	var attack_targets: Array = []
	for hostile in units:
		if (
			hostile == null
			or not bool(hostile.alive)
			or int(hostile.team) == int(actor.team)
		):
			continue
		var distance: int = Pathfinder.cheb(actor.cell, hostile.cell)
		if distance > OBSERVATION_RADIUS:
			continue
		if (
			hostile.node == null
			or not is_instance_valid(hostile.node)
			or not bool(hostile.node.visible)
		):
			continue
		var screen = _screen_of_cell(hostile.cell)
		if screen == null:
			continue
		attack_targets.append({
			"unit_id": int(hostile.unit_id),
			"cell": _observation_cell(hostile.cell),
			"adjacent": Pathfinder.is_adjacent(actor.cell, hostile.cell),
			"screen": screen
		})
		if attack_targets.size() >= OBSERVATION_ATTACK_CAP:
			break
	observation["attack_targets"] = attack_targets
	return observation

## Bounded accessibility state. Presentation preferences only: no host, profile,
## user-agent, or media-query surface beyond the single reduced-motion answer.
func _observation_accessibility() -> Dictionary:
	var reduced_motion := false
	var motion_scale := 1.0
	if camera_controller != null and is_instance_valid(camera_controller):
		motion_scale = float(camera_controller.motion_scale)
		reduced_motion = bool(camera_controller.is_reduced_motion())
	var focused_control := ""
	var focus_order: Array = []
	if tactical_ui != null and is_instance_valid(tactical_ui):
		focused_control = String(tactical_ui.focused_control_key)
		focus_order = Array(tactical_ui.FOCUS_ORDER_KEYS)
	return {
		"reduced_motion": reduced_motion,
		"motion_scale": motion_scale,
		"focus_order": focus_order,
		"focused_control": focused_control,
		"focused_control_is_core": focus_order.has(focused_control)
	}

## Publishes the layout metrics the HUD actually applied, so a live viewport
## matrix asserts against the same authority the game used to place the panels.
func _observation_layout() -> Dictionary:
	if tactical_ui == null or not is_instance_valid(tactical_ui):
		return {}
	var metrics: Dictionary = tactical_ui.last_layout_metrics
	if metrics.is_empty():
		return {}
	return {
		"tutorial_left": float(metrics.get("tutorial_left", 0.0)),
		"tutorial_clearance": float(metrics.get("tutorial_clearance", 0.0)),
		"tutorial_bottom": float(metrics.get("tutorial_bottom", 0.0)),
		"action_dock_left": float(metrics.get("action_dock_left", 0.0)),
		"action_dock_clearance": float(metrics.get("action_dock_clearance", 0.0)),
		"action_dock_top": float(metrics.get("action_dock_top", 0.0)),
		"action_dock_height": float(metrics.get("action_dock_height", 0.0)),
		"status_rail_bottom": float(metrics.get("status_rail_bottom", 0.0)),
		"event_rail_top": float(metrics.get("event_rail_top", 0.0)),
		"event_rail_bottom": float(metrics.get("event_rail_bottom", 0.0)),
		"event_rail_height": float(metrics.get("event_rail_height", 0.0)),
		"event_rail_cramped": bool(metrics.get("event_rail_cramped", false)),
		"tutorial_dock_clear": bool(metrics.get("tutorial_dock_clear", false)),
		"event_rail_visible": bool(metrics.get("event_rail_visible", false)),
		"constrained": bool(metrics.get("constrained", true)),
		"auto_parked": Array(metrics.get("auto_parked", [])),
		"surface_opacity": _observation_surface_opacity()
	}

## Per-surface transparency, so a live run can prove the adaptive HUD state rather
## than inferring it from a screenshot.
func _observation_surface_opacity() -> Dictionary:
	var opacity := {}
	if tactical_ui == null or not is_instance_valid(tactical_ui):
		return opacity
	for key in tactical_ui.surface_keys():
		var surface: Dictionary = tactical_ui.surface_state(String(key))
		opacity[String(key)] = snappedf(float(surface.get("opacity", 1.0)), 0.01)
	return opacity

func _observation_cell(cell: Vector2i) -> Dictionary:
	return {
		"x": cell.x,
		"y": cell.y
	}

func _screen_of_cell(cell: Vector2i):
	if (
		camera_controller == null
		or camera_controller.camera == null
		or not is_instance_valid(camera_controller.camera)
	):
		return null
	var camera: Camera3D = camera_controller.camera
	var world_position := _cell_to_world(cell) + Vector3(0.0, 0.2, 0.0)
	if camera.is_position_behind(world_position):
		return null
	var projected := camera.unproject_position(world_position)
	return {"x": roundi(projected.x), "y": roundi(projected.y)}

func _observation_view_signature() -> String:
	if (
		camera_controller == null
		or camera_controller.camera == null
		or not is_instance_valid(camera_controller.camera)
	):
		return ""
	var camera: Camera3D = camera_controller.camera
	var position := camera.global_position
	var rotation := camera.global_rotation
	var viewport_size := get_viewport().get_visible_rect().size
	return "%.3f|%.3f|%.3f|%.4f|%.4f|%.4f|%d|%d" % [
		position.x,
		position.y,
		position.z,
		rotation.x,
		rotation.y,
		rotation.z,
		roundi(viewport_size.x),
		roundi(viewport_size.y)
	]

func _refresh_web_observation_for_view(delta: float) -> void:
	if (
		not OS.has_feature("web")
		or tutorial == null
		or not bool(tutorial.active)
	):
		return
	_observation_view_elapsed += delta
	if _observation_view_elapsed < OBSERVATION_VIEW_INTERVAL:
		return
	_observation_view_elapsed = 0.0
	var signature := _observation_view_signature()
	if signature.is_empty() or signature == _observation_view_last:
		return
	_observation_view_last = signature
	_publish_web_observation()

func _publish_web_observation() -> void:
	if not OS.has_feature("web"):
		return
	var observation := _build_web_observation()
	if observation.is_empty():
		return
	var serialized := JSON.stringify(observation)
	if serialized == _observation_last:
		return
	_observation_last = serialized
	JavaScriptBridge.eval(
		"window.__gzg_observation = %s; console.log('[GZG-OBS] ' + JSON.stringify(window.__gzg_observation));"
		% serialized
	)

func _on_tutorial_action(action: String, actor, _target_cell: Vector2i) -> void:
	if tutorial != null:
		tutorial.observe_action(action, actor)

func _on_tutorial_record(record: Dictionary) -> void:
	if tutorial == null or not bool(tutorial.active):
		return
	if (
		String(record.get("record_type", "")) == "event"
		and String(record.get("event", "")) == "movement_resolved"
	):
		var payload = record.get("payload", {})
		if payload is Dictionary:
			var moved_unit = get_unit_by_id(int(payload.get("actor", -1)))
			if moved_unit != null:
				tutorial.set_cover_available(not cover_options(moved_unit).is_empty())
				tutorial.set_defense_affordable(int(moved_unit.ap) >= BLOCK_COST)
	tutorial.observe_record(record)

func get_unit_by_id(uid: int) :
	for u in units:
		if u.unit_id == uid:
			return u
	return null

func refresh_unit(u) -> void:
	if u == null: return
	u.update_figure()
	_refresh_label(u)
	_update_ui()

func serialize_units() -> Array:
	var out: Array = []
	for u in units:
		out.append(u.to_dict())
	return out
