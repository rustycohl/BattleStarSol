extends RefCounted
class_name WorldBuilder

const Config = preload("res://scripts/GameConfig.gd")
const SPAWN_PAD_DEPTH := 4

static func build_environment(parent: Node3D) -> Dictionary:
	var wenv := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.02, 0.08) # Darker background

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.1, 0.15, 0.2) # Cooler, darker ambient
	env.ambient_light_energy = 0.4

	env.fog_enabled = true
	env.fog_light_color = Color(0.15, 0.05, 0.25)
	env.fog_density = 0.04 # Denser fog for atmosphere
	env.fog_aerial_perspective = 0.9

	# Glow/bloom is a known AMD Radeon GL Compatibility crash vector on some
	# driver builds. Keep the scene readable without post-process bloom.
	env.glow_enabled = false

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 3.5

	wenv.environment = env
	parent.add_child(wenv)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -45, 0)
	sun.light_color = Color(1.0, 0.7, 0.4)
	sun.light_energy = 1.6 # Stronger sun
	# Shadows off by default for driver stability (can re-enable after GPU QA).
	sun.shadow_enabled = false
	parent.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 135, 0)
	fill.light_color = Color(0.15, 0.3, 0.6)
	fill.light_energy = 0.8
	fill.shadow_enabled = false
	parent.add_child(fill)

	# The simulation is grid-authoritative. Keep presentation tiles on a plain
	# node so runtime navigation-mesh baking cannot become a second pathfinding
	# system or introduce GPU readback stalls.
	var tiles_root = Node3D.new()
	tiles_root.name = "Tiles"
	parent.add_child(tiles_root)

	var highlight_root = Node3D.new()
	parent.add_child(highlight_root)

	return {
		"tiles_root": tiles_root,
		"highlight_root": highlight_root
	}

static func generate_cells(
	map_seed: int,
	width: int = Config.GRID_W,
	height: int = Config.GRID_H
) -> Dictionary:
	var cells := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed if map_seed > 0 else 84021

	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.12

	for x in width:
		for y in height:
			var c := Vector2i(x, y)
			var noise_val = (noise.get_noise_2d(x, y) + 1.0) / 2.0
			var roll := rng.randf()
			var h := 0

			# Most of the board is intentionally readable, walkable ground.
			# Earlier builds turned nearly every cell into an independent
			# column and then dropped units on top of the tallest ones.
			if roll < 0.10:
				h = rng.randi_range(3, 6)
			elif noise_val > 0.68:
				h = 2
			elif noise_val > 0.50:
				h = 1

			# Every faction receives a deterministic, level insertion pad.
			# This also keeps old seeds playable after the 10x10 -> 20x20
			# expansion.
			if _inside_spawn_pad(c, width, height):
				h = 0

			var t: int = Config.COVER if h >= 3 else (Config.HALF_COVER if h > 0 else Config.FLOOR)
			cells[c] = {
				"type": t,
				"z": h,
				"density": (100 if t == Config.COVER else 0),
				"climbable": h > 0 and h <= 2
			}
	return cells

static func spawn_cells(
	team: int,
	width: int = Config.GRID_W,
	height: int = Config.GRID_H
) -> Array[Vector2i]:
	match team:
		Config.FACTION_HAD:
			return [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)]
		Config.FACTION_SYND:
			return [
				Vector2i(width - 2, height - 2),
				Vector2i(width - 3, height - 2),
				Vector2i(width - 2, height - 3)
			]
		Config.FACTION_TIME:
			return [
				Vector2i(1, height - 2),
				Vector2i(2, height - 2),
				Vector2i(1, height - 3)
			]
	return []

static func _inside_spawn_pad(c: Vector2i, width: int, height: int) -> bool:
	var left := c.x < SPAWN_PAD_DEPTH
	var right := c.x >= width - SPAWN_PAD_DEPTH
	var top := c.y < SPAWN_PAD_DEPTH
	var bottom := c.y >= height - SPAWN_PAD_DEPTH
	return (left and top) or (right and bottom) or (left and bottom)

static func build_grid(parent: Node3D, tiles_root: Node3D, map_seed: int) -> Dictionary:
	var cells := generate_cells(map_seed)
	for x in Config.GRID_W:
		for y in Config.GRID_H:
			var c := Vector2i(x, y)
			var data: Dictionary = cells[c]
			_spawn_tile(tiles_root, c, int(data["type"]), int(data["z"]), map_seed)

	var game_state = parent.get_node_or_null("/root/GameState")
	if game_state:
		game_state.cells = cells
	return cells

static func _spawn_tile(tiles_root: Node3D, c: Vector2i, _t: int, h: int, map_seed: int) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Tile_%d_%d" % [c.x, c.y]
	mi.set_meta("cell", c)
	var box := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.85

	var world_pos := Config.cell_to_world(c)

	if h > 3:
		box.size = Vector3(Config.cell_size * 0.96, h * Config.HEIGHT_STEP, Config.cell_size * 0.96)
		if (c.x + c.y) % 3 == 0:
			# Sci-Fi Crates
			var v := 0.15 + fmod(float(c.x * 7 + c.y * 13), 5.0) * 0.02
			mat.albedo_color = Color(v, v + 0.05, v + 0.08)
			mat.metallic = 0.8
			mat.roughness = 0.3
			mat.emission_enabled = true
			mat.emission = Color(0.1, 0.8, 1.0) if (c.x % 2 == 0) else Color(1.0, 0.4, 0.1)
			mat.emission_energy_multiplier = 0.5
			mi.rotation_degrees.y = float(c.x * 90)
		else:
			# Ruined Concrete Pillars
			var v := 0.08 + fmod(float(c.x * 7 + c.y * 13), 5.0) * 0.01
			mat.albedo_color = Color(v, v, v + 0.02)
			mat.metallic = 0.1
			mat.roughness = 0.9
			var visual_hash := absi((c.x * 73856093) ^ (c.y * 19349663) ^ map_seed)
			mi.rotation_degrees.y = float(visual_hash % 31) - 15.0
			mi.rotation_degrees.x = float(int(visual_hash / 31) % 11) - 5.0

		mi.position = world_pos + Vector3(0, (h * Config.HEIGHT_STEP) / 2.0, 0)
	elif h > 0:
		box.size = Vector3(Config.cell_size * 0.96, h * Config.HEIGHT_STEP, Config.cell_size * 0.96)
		var shade := 0.15 + h * 0.02
		var noise_v := fmod(float(c.x * 3 + c.y * 7), 4.0) * 0.02
		mat.albedo_color = Color(shade + 0.15 + noise_v, shade + 0.05, shade - 0.05)
		mat.metallic = 0.0
		mat.roughness = 0.95
		mi.position = world_pos + Vector3(0, (h * Config.HEIGHT_STEP) / 2.0, 0)
	else:
		box.size = Vector3(Config.cell_size * 0.96, 0.2, Config.cell_size * 0.96)
		var checker := 0.03 if (c.x + c.y) % 2 == 0 else 0.0
		var noise_v := fmod(float(c.x * 11 + c.y * 17), 6.0) * 0.01
		mat.albedo_color = Color(0.12 + checker + noise_v, 0.10 + checker, 0.09)
		mat.metallic = 0.15
		mat.roughness = 0.85
		mi.position = world_pos + Vector3(0, -0.1, 0)

	box.material = mat
	mi.mesh = box
	tiles_root.add_child(mi)

static func build_ring(parent: Node3D) -> MeshInstance3D:
	var sel_ring = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.95
	disc.bottom_radius = 0.95
	disc.height = 0.05
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.8, 0.92, 0.45)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.2, 0.8, 0.92)
	m.emission_energy_multiplier = 1.2
	disc.material = m
	sel_ring.mesh = disc
	sel_ring.visible = false
	parent.add_child(sel_ring)
	return sel_ring

static func scatter_weapons(main: Node3D, map_seed: int) -> void:
	var ItemDB = main.get_node_or_null("/root/ItemDB")
	var weapons = []
	if ItemDB: weapons = ItemDB.get_all_weapons()

	if weapons.is_empty():
		weapons = ["rock", "club", "spear"]
	weapons.sort()

	var rng := RandomNumberGenerator.new()
	rng.seed = (map_seed if map_seed > 0 else 84021) + 104729

	var candidates := _loot_candidates(main)
	var placed := 0
	while placed < 12 and not candidates.is_empty():
		var pick := rng.randi_range(0, candidates.size() - 1)
		var c: Vector2i = candidates[pick]
		candidates.remove_at(pick)
		var w = weapons[rng.randi_range(0, weapons.size() - 1)]
		main._add_debris(c, w, 1)
		placed += 1

	_scatter_one(main, "string", 2, rng)
	_scatter_one(main, "arrow", 3, rng)

static func _scatter_one(main: Node3D, kind: String, n: int, rng: RandomNumberGenerator) -> void:
	var placed := 0
	var candidates := _loot_candidates(main)
	while placed < n and not candidates.is_empty():
		var pick := rng.randi_range(0, candidates.size() - 1)
		var c: Vector2i = candidates[pick]
		candidates.remove_at(pick)
		var count := 3 if kind == "arrow" else 1
		main._add_debris(c, kind, count)
		placed += 1

static func _loot_candidates(main: Node3D) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for x in Config.GRID_W:
		for y in Config.GRID_H:
			var c := Vector2i(x, y)
			if not main._cell_free(c) or main.debris.has(c):
				continue
			# Loot should be discoverable on navigable surfaces, not buried
			# among or stranded on top of procedural towers.
			if int(main.cells.get(c, {}).get("z", 99)) <= Config.MAX_WALK_STEP:
				candidates.append(c)
	return candidates
