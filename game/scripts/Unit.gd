extends RefCounted
class_name Unit

const Config = preload("res://scripts/GameConfig.gd")
const ManeuverStateScript = preload("res://scripts/ManeuverState.gd")

var name: String = "Unit"
var team: int
var cell: Vector2i
var hp: int
var max_hp: int
var armor: int = 0
var max_armor: int = 0
var ap: int
var max_ap: int
var inv: Dictionary
var skills: Array = []
var left := ""
var right := ""
var two_handed := false
var blocking: bool = false
var dodging: bool = false
var flipping: bool = false
var hovering: bool = false
var flying: bool = false
var wall_running: bool = false
var stance: String = "stand"
var lean: String = "none"
var taking_cover: bool = false
var cover_cell: Vector2i = Config.INVALID_CELL
var cover_monkey_active: bool = false
var frenzied: bool = false
var z: int = 0
var move_mode: String = "run"
var run_distance_this_turn: int = 0
var sprint_distance_this_turn: int = 0
var sprint_distance_total: int = 0
var last_move_direction: Vector2i = Vector2i.ZERO
var maneuver: Dictionary = ManeuverStateScript.grounded()
var prone_orient: String = "down"
var node: Node3D
var fig: Node3D
var body_col: Color = Color.WHITE
var label: Label3D
var alive: bool = true
var unit_id: int = 0
## Permanent role: fireteam lead / human home body.
var is_commander: bool = false
## Permanent: spawned as a squad ally that runs on utility AI unless remoted.
var is_squad_bot: bool = false
## Runtime: currently receives human input (commander by default, or a Remotes login).
var player_controlled: bool = false

func has_special(special_name: String, dev_specials: bool = false) -> bool:
	return dev_specials or skills.has(special_name)

func is_human_pilot() -> bool:
	return player_controlled and alive

func is_airborne_maneuver() -> bool:
	return ManeuverStateScript.is_airborne(maneuver)

func is_wall_maneuver() -> bool:
	return ManeuverStateScript.is_wall_running(maneuver)

func record_ground_step(mode: String) -> void:
	if mode == "sprint":
		sprint_distance_this_turn += 1
		sprint_distance_total += 1
	else:
		run_distance_this_turn += 1

func reset_turn_momentum() -> void:
	run_distance_this_turn = 0
	sprint_distance_this_turn = 0

func has_item(kind: String) -> bool:
	return kind != "" and kind != "fist" and int(inv.get(kind, 0)) > 0

func grip_str() -> String:
	if two_handed:
		return "[2H %s]" % (right.left(6).capitalize() if right != "" else "-")
	var l: String = left.left(4).capitalize() if left != "" else "-"
	var r: String = right.left(4).capitalize() if right != "" else "-"
	return "[%s|%s]" % [l, r]

func update_figure() -> void:
	if fig == null: return

	if has_meta("is_glb_model") and get_meta("is_glb_model"):
		return

	var fac_name = Config.faction_name(team).to_lower().replace("/", "_")
	var role_name = "standard"
	if "Scout" in name or "Beta" in name or "Delta" in name: role_name = "scout"
	elif "Heavy" in name or "Gamma" in name or "Phi" in name: role_name = "heavy"

	var glb_path = "res://models/%s/%s.glb" % [fac_name, role_name]
	if ResourceLoader.exists(glb_path):
		for c in fig.get_children(): c.queue_free()
		var packed = load(glb_path) as PackedScene
		if packed:
			fig.add_child(packed.instantiate())
			set_meta("is_glb_model", true)
			return

	for c in fig.get_children():
		c.queue_free()

	var fac_col := body_col
	var base_col := Color(0.04, 0.04, 0.05)

	var braced := blocking
	var low_hp := (hp < max_hp * 0.3)
	var by := 0.0
	var lean_x := 0.0
	var lean_z := 0.0
	var root_rot := Vector3.ZERO
	var leg_scale := 0.7

	if stance == "crouch":
		by = -0.35
		leg_scale = 0.35
	elif stance == "prone":
		if prone_orient == "up":
			root_rot = Vector3(90, 0, 0)
			by = -0.3
		else:
			root_rot = Vector3(-90, 0, 0)
			by = -0.5

	if flying or hovering or is_airborne_maneuver():
		by += 0.45
		root_rot.x += 18.0
		leg_scale = 0.45
	elif wall_running:
		by += 0.2
		root_rot.z += 15.0

	if lean == "left": lean_z = 25.0
	elif lean == "right": lean_z = -25.0

	if braced:
		by -= 0.10
		lean_x = 16.0
	elif low_hp:
		by -= 0.05
		lean_x = 12.0

	fig.rotation_degrees = root_rot

	# Legs
	_fig_capsule(0.12, leg_scale, Vector3(-0.16, by + (leg_scale/2.0), 0), base_col, Vector3.ZERO, true)
	_fig_capsule(0.12, leg_scale, Vector3(0.16, by + (leg_scale/2.0), 0), base_col, Vector3.ZERO, true)

	var torso_y = by + leg_scale + 0.25
	var torso_w = 0.55 if role_name == "heavy" else (0.35 if role_name == "scout" else 0.45)

	# Torso
	_fig_capsule(torso_w / 2.0, 0.7, Vector3(0, torso_y, 0), base_col, Vector3(lean_x, 0, lean_z), true)

	# Armor Plating
	_fig_box(Vector3(torso_w + 0.05, 0.2, 0.35), Vector3(0, torso_y + 0.1, 0), fac_col, Vector3(lean_x, 0, lean_z), false, 0.5)
	_fig_box(Vector3(torso_w, 0.15, 0.38), Vector3(0, torso_y - 0.2, 0), Color(0.1, 0.1, 0.1), Vector3(lean_x, 0, lean_z))

	# Props based on role
	if role_name == "heavy":
		_fig_box(Vector3(0.4, 0.5, 0.25), Vector3(0, torso_y, -0.25), base_col, Vector3(lean_x, 0, lean_z), true)
		_fig_cylinder(0.1, 0.5, Vector3(-0.15, torso_y + 0.1, -0.35), fac_col, Vector3(lean_x, 0, lean_z), false, 1.2)
		_fig_cylinder(0.1, 0.5, Vector3(0.15, torso_y + 0.1, -0.35), fac_col, Vector3(lean_x, 0, lean_z), false, 1.2)
	elif role_name == "scout":
		_fig_cylinder(0.02, 0.6, Vector3(0.15, torso_y + 0.4, -0.15), Color(0.8, 0.8, 0.8), Vector3(lean_x, 0, lean_z), true)

	var head_y = torso_y + 0.48
	# Head
	_fig_sphere(0.2, 0.4, Vector3(0, head_y, lean_x * 0.004), base_col, Vector3(0, 0, lean_z), true)
	# Visor
	_fig_box(Vector3(0.28, 0.08, 0.2), Vector3(0, head_y + 0.05, lean_x * 0.004 + 0.15), fac_col, Vector3(0, 0, lean_z), false, 5.0)

	var larm := Vector3(12, 0, 6)
	var rarm := Vector3(12, 0, -6)
	if braced:
		larm = Vector3(100, 0, 22)
		rarm = Vector3(100, 0, -22)
	elif two_handed and has_item(right):
		larm = Vector3(78, 0, 10)
		rarm = Vector3(78, 0, -10)
	elif low_hp:
		larm = Vector3(35, 0, 15)
		rarm = Vector3(35, 0, -15)
	else:
		if left != "" and has_item(left): larm = Vector3(70, 0, 8)
		if right != "" and has_item(right): rarm = Vector3(70, 0, -8)

	var arm_y = torso_y + 0.15
	var arm_x = 0.32 if role_name == "heavy" else (0.24 if role_name == "scout" else 0.28)

	# Arms
	_fig_capsule(0.08, 0.6, Vector3(-arm_x, arm_y, 0.06), base_col, larm, true)
	_fig_capsule(0.08, 0.6, Vector3(arm_x, arm_y, 0.06), base_col, rarm, true)

	# Shoulder Pads
	_fig_sphere(0.12, 0.24, Vector3(-arm_x, arm_y + 0.2, 0.06), fac_col, larm, false, 0.5)
	_fig_sphere(0.12, 0.24, Vector3(arm_x, arm_y + 0.2, 0.06), fac_col, rarm, false, 0.5)

	if two_handed and has_item(right):
		_fig_item(right, Vector3(0, arm_y, 0.55))
	else:
		if right != "" and has_item(right):
			_fig_item(right, Vector3(arm_x + 0.1, torso_y, 0.35))
		if left != "" and has_item(left):
			_fig_item(left, Vector3(-arm_x - 0.1, torso_y, 0.35))

	if int(inv.get("arrow", 0)) > 0:
		_fig_box(Vector3(0.16, 0.7, 0.16), Vector3(0.14, torso_y + 0.1, -0.26), Color(0.4, 0.3, 0.2), Vector3(16, 0, 14))

func _fig_box(size: Vector3, pos: Vector3, col: Color, rot_deg := Vector3.ZERO, is_metal := false, emissive_mul := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.6 if is_metal else 0.85
	m.metallic = 0.4 if is_metal else 0.1
	if emissive_mul > 0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emissive_mul
	bx.material = m
	mi.mesh = bx
	mi.position = pos
	mi.rotation_degrees = rot_deg
	fig.add_child(mi)

func _fig_capsule(radius: float, height: float, pos: Vector3, col: Color, rot_deg := Vector3.ZERO, is_metal := false, emissive_mul := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = height
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.6 if is_metal else 0.85
	m.metallic = 0.4 if is_metal else 0.1
	if emissive_mul > 0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emissive_mul
	cap.material = m
	mi.mesh = cap
	mi.position = pos
	mi.rotation_degrees = rot_deg
	fig.add_child(mi)

func _fig_sphere(radius: float, height: float, pos: Vector3, col: Color, rot_deg := Vector3.ZERO, is_metal := false, emissive_mul := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = radius
	sph.height = height
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.6 if is_metal else 0.85
	m.metallic = 0.4 if is_metal else 0.1
	if emissive_mul > 0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emissive_mul
	sph.material = m
	mi.mesh = sph
	mi.position = pos
	mi.rotation_degrees = rot_deg
	fig.add_child(mi)

func _fig_cylinder(radius: float, height: float, pos: Vector3, col: Color, rot_deg := Vector3.ZERO, is_metal := false, emissive_mul := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.6 if is_metal else 0.85
	m.metallic = 0.4 if is_metal else 0.1
	if emissive_mul > 0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emissive_mul
	cyl.material = m
	mi.mesh = cyl
	mi.position = pos
	mi.rotation_degrees = rot_deg
	fig.add_child(mi)

func _fig_item(kind: String, pos: Vector3) -> void:
	var item_root = Node3D.new()
	item_root.position = pos
	var emissive_color := Color.BLACK
	var col := Color.WHITE

	if kind == "rock":
		var s := SphereMesh.new()
		s.radius = 0.16
		s.height = 0.32
		var m = StandardMaterial3D.new()
		m.albedo_color = Color(0.35, 0.32, 0.3)
		m.roughness = 0.95
		s.material = m
		var mi = MeshInstance3D.new()
		mi.mesh = s
		item_root.add_child(mi)
	elif kind == "spear" or kind == "arrow":
		var b := BoxMesh.new()
		b.size = Vector3(0.07, 0.07, 1.3)
		var m = StandardMaterial3D.new()
		m.albedo_color = Color(0.45, 0.38, 0.25)
		b.material = m
		var mi = MeshInstance3D.new()
		mi.mesh = b
		mi.rotation_degrees = Vector3(90, 0, 0)
		item_root.add_child(mi)
	elif kind == "club":
		var b := BoxMesh.new()
		b.size = Vector3(0.16, 0.16, 0.7)
		var m = StandardMaterial3D.new()
		m.albedo_color = Color(0.3, 0.2, 0.15)
		b.material = m
		var mi = MeshInstance3D.new()
		mi.mesh = b
		mi.rotation_degrees = Vector3(55, 0, 0)
		item_root.add_child(mi)
	elif kind == "bow" or kind == "stringedbow":
		var c = CylinderMesh.new()
		c.top_radius = 0.04
		c.bottom_radius = 0.04
		c.height = 0.9
		var m = StandardMaterial3D.new()
		m.albedo_color = Color(0.4, 0.25, 0.15)
		c.material = m
		var mi = MeshInstance3D.new()
		mi.mesh = c
		item_root.add_child(mi)
	elif kind == "string":
		var c = CylinderMesh.new()
		c.top_radius = 0.02
		c.bottom_radius = 0.02
		c.height = 0.5
		var m = StandardMaterial3D.new()
		m.albedo_color = Color(0.85, 0.85, 0.8)
		c.material = m
		var mi = MeshInstance3D.new()
		mi.mesh = c
		item_root.add_child(mi)
	else:
		var ItemDB = Engine.get_main_loop().root.get_node_or_null("ItemDB")
		var item = ItemDB.get_item(kind) if ItemDB else {}
		if item.is_empty(): return

		var tier = int(item.get("tier", 1))
		if tier == 1: col = Color(0.15, 0.15, 0.15)
		elif tier == 2:
			col = Color(0.1, 0.1, 0.15)
			emissive_color = Color(1, 0.1, 0.1)
		elif tier == 3:
			col = Color(0.2, 0.25, 0.3)
			emissive_color = Color(0.1, 0.8, 1)
		elif tier == 4:
			col = Color(0.1, 0.1, 0.1)
			emissive_color = Color(0.2, 1, 0.2)
		elif tier == 5:
			col = Color(0.05, 0.05, 0.05)
			emissive_color = Color(0.9, 0.1, 1)
		else:
			col = Color(0.4, 0.4, 0.4)

		var is_ranged = item.get("range", 1) > 1

		var m_base = StandardMaterial3D.new()
		m_base.albedo_color = col
		m_base.roughness = 0.4
		m_base.metallic = 0.6

		var m_glow = StandardMaterial3D.new()
		if emissive_color != Color.BLACK:
			m_glow.albedo_color = emissive_color
			m_glow.emission_enabled = true
			m_glow.emission = emissive_color
			m_glow.emission_energy_multiplier = 4.0
		else:
			m_glow = m_base

		item_root.rotation_degrees = Vector3(90, 0, 0)

		if is_ranged:
			# Rifle composite
			# Stock
			var stock = BoxMesh.new()
			stock.size = Vector3(0.08, 0.25, 0.15)
			stock.material = m_base
			var mi_stock = MeshInstance3D.new()
			mi_stock.mesh = stock
			mi_stock.position = Vector3(0, -0.3, 0)
			item_root.add_child(mi_stock)

			# Barrel
			var barrel = CylinderMesh.new()
			barrel.top_radius = 0.03
			barrel.bottom_radius = 0.04
			barrel.height = 0.6
			barrel.material = m_base
			var mi_barrel = MeshInstance3D.new()
			mi_barrel.mesh = barrel
			mi_barrel.position = Vector3(0, 0.15, 0)
			item_root.add_child(mi_barrel)

			# Scope / Core
			var core = CylinderMesh.new()
			core.top_radius = 0.02
			core.bottom_radius = 0.02
			core.height = 0.2
			core.material = m_glow
			var mi_core = MeshInstance3D.new()
			mi_core.mesh = core
			mi_core.position = Vector3(0, 0, 0.1)
			item_root.add_child(mi_core)
		else:
			# Melee composite (Energy sword / hammer)
			var hilt = CylinderMesh.new()
			hilt.top_radius = 0.03
			hilt.bottom_radius = 0.03
			hilt.height = 0.3
			hilt.material = m_base
			var mi_hilt = MeshInstance3D.new()
			mi_hilt.mesh = hilt
			mi_hilt.position = Vector3(0, -0.3, 0)
			item_root.add_child(mi_hilt)

			var blade = BoxMesh.new()
			blade.size = Vector3(0.04, 0.6, 0.1)
			blade.material = m_glow
			var mi_blade = MeshInstance3D.new()
			mi_blade.mesh = blade
			mi_blade.position = Vector3(0, 0.15, 0)
			item_root.add_child(mi_blade)

	fig.add_child(item_root)

func to_dict() -> Dictionary:
	return {
		"unit_id": unit_id, "name": name,
		"team": team, "cell": [cell.x, cell.y], "hp": hp, "max_hp": max_hp,
		"ap": ap, "max_ap": max_ap, "inv": inv.duplicate(),
		"skills": skills.duplicate(),
		"left": left, "right": right, "two_handed": two_handed,
		"blocking": blocking, "dodging": dodging, "flipping": flipping,
		"hovering": hovering, "flying": flying, "wall_running": wall_running,
		"stance": stance, "lean": lean, "taking_cover": taking_cover,
		"cover_cell": [cover_cell.x, cover_cell.y],
		"cover_monkey_active": cover_monkey_active,
		"z": z, "move_mode": move_mode,
		"run_distance_this_turn": run_distance_this_turn,
		"sprint_distance_this_turn": sprint_distance_this_turn,
		"sprint_distance_total": sprint_distance_total,
		"last_move_direction": [last_move_direction.x, last_move_direction.y],
		"maneuver": ManeuverStateScript.normalize(maneuver),
		"prone_orient": prone_orient, "alive": alive,
		"is_commander": is_commander,
		"is_squad_bot": is_squad_bot,
		"player_controlled": player_controlled
	}

func apply_dict(d: Dictionary) -> void:
	name = String(d.get("name", name))
	team = int(d.get("team", team))
	is_commander = bool(d.get("is_commander", is_commander))
	is_squad_bot = bool(d.get("is_squad_bot", is_squad_bot))
	player_controlled = bool(d.get("player_controlled", player_controlled))
	if d.has("cell"):
		var c = d["cell"]
		cell = Vector2i(int(c[0]), int(c[1]))
	hp = int(d.get("hp", hp)); max_hp = int(d.get("max_hp", max_hp))
	ap = int(d.get("ap", ap)); max_ap = int(d.get("max_ap", max_ap))
	inv = (d.get("inv", inv) as Dictionary).duplicate()
	skills = (d.get("skills", skills) as Array).duplicate()
	left = String(d.get("left", left)); right = String(d.get("right", right))
	two_handed = bool(d.get("two_handed", two_handed))
	blocking = bool(d.get("blocking", blocking)); dodging = bool(d.get("dodging", dodging))
	flipping = bool(d.get("flipping", flipping)); hovering = bool(d.get("hovering", hovering))
	flying = bool(d.get("flying", flying)); wall_running = bool(d.get("wall_running", wall_running))
	stance = String(d.get("stance", stance)); lean = String(d.get("lean", lean))
	taking_cover = bool(d.get("taking_cover", taking_cover))
	if d.has("cover_cell"):
		var cover_data = d["cover_cell"]
		cover_cell = Vector2i(int(cover_data[0]), int(cover_data[1]))
	cover_monkey_active = bool(d.get("cover_monkey_active", cover_monkey_active))
	z = int(d.get("z", z)); move_mode = String(d.get("move_mode", move_mode))
	run_distance_this_turn = maxi(int(d.get("run_distance_this_turn", run_distance_this_turn)), 0)
	sprint_distance_this_turn = maxi(int(d.get("sprint_distance_this_turn", sprint_distance_this_turn)), 0)
	sprint_distance_total = maxi(int(d.get("sprint_distance_total", sprint_distance_total)), 0)
	if d.has("last_move_direction"):
		var move_direction = d["last_move_direction"]
		last_move_direction = Vector2i(int(move_direction[0]), int(move_direction[1]))
	maneuver = ManeuverStateScript.normalize(d.get("maneuver", maneuver))
	prone_orient = String(d.get("prone_orient", prone_orient))
	alive = bool(d.get("alive", alive))
