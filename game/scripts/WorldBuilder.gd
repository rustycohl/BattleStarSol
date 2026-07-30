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

			# Every faction receives a level insertion footprint so units never
			# spawn on a column. Flattening the whole four-deep pad also erased
			# every cover face beside the insertion point, which is why the guided
			# lane had nothing to take cover behind. Only the insertion cells and
			# their step-off ring are levelled now; the rest of the pad keeps its
			# generated terrain, so cover near a spawn occurs naturally.
			if _inside_spawn_footprint(c, width, height):
				h = 0

			var t: int = Config.COVER if h >= 3 else (Config.HALF_COVER if h > 0 else Config.FLOOR)
			cells[c] = material_cell(t, h)
	return cells

## Terrain material. Cover is a consequence of what a cell is made of and how
## thick it is, not a painted flag: `density` and `integrity` are what penetration
## and destruction read, and what cover scoring is derived from.
static func material_cell(cell_type: int, height: int) -> Dictionary:
	var density := 0
	var material := "open"
	if cell_type == Config.COVER:
		# Taller columns are thicker, so they stop more and last longer.
		density = clampi(60 + (height - 3) * 12, 60, 100)
		material = "hard"
	elif cell_type == Config.HALF_COVER:
		density = clampi(20 + (height - 1) * 10, 20, 45)
		material = "soft"
	return {
		"type": cell_type,
		"z": height,
		"density": density,
		"integrity": density,
		"material": material,
		# The tier count the column started at. Fixed for the cell's life, so the material
		# each tier needs to stay up stays fixed as the column is worn down. Without it,
		# capacity per tier would fall with the height and the last tier would never fail.
		"tiers": height,
		"climbable": height > 0 and height <= 2
	}

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

## Levels only the cells a squad actually stands on plus one step off each, so
## nobody spawns on a column and nobody is walled in — while leaving the rest of
## the old pad free to generate real terrain, and therefore real cover.
static func _inside_spawn_footprint(c: Vector2i, width: int, height: int) -> bool:
	for team in [Config.FACTION_HAD, Config.FACTION_SYND, Config.FACTION_TIME]:
		for cell in spawn_cells(team, width, height):
			if absi(c.x - cell.x) + absi(c.y - cell.y) <= 1:
				return true
	return false

## Retained for reference: the historical four-deep flattened pad.
static func _inside_spawn_pad(c: Vector2i, width: int, height: int) -> bool:
	var left := c.x < SPAWN_PAD_DEPTH
	var right := c.x >= width - SPAWN_PAD_DEPTH
	var top := c.y < SPAWN_PAD_DEPTH
	var bottom := c.y >= height - SPAWN_PAD_DEPTH
	return (left and top) or (right and bottom) or (left and bottom)

## Naturally occurring cover near a faction's insertion point, read out of the
## generated terrain rather than painted into it. Used for evidence and tests: the
## tutorial teaches cover only because the environment provides it.
static func cover_near_spawn(
	cells: Dictionary,
	player_faction: int,
	radius: int = 3,
	width: int = Config.GRID_W,
	height: int = Config.GRID_H
) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var player_cells := spawn_cells(player_faction, width, height)
	if player_cells.is_empty():
		return found
	var start: Vector2i = player_cells[0]
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var candidate := start + Vector2i(dx, dy)
			var data = cells.get(candidate, null)
			if not (data is Dictionary):
				continue
			if int((data as Dictionary).get("type", -1)) == Config.COVER:
				found.append(candidate)
	found.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := absi(a.x - start.x) + absi(a.y - start.y)
		var db := absi(b.x - start.x) + absi(b.y - start.y)
		if da != db:
			return da < db
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y
	)
	return found

## Every field a terrain cell must carry. `material_cell` is the only thing that should ever
## produce one, and this is what "produced by the authority" looks like from the outside.
##
## This exists because of a defect that no behavioural test could have caught. The Standoff
## sector built a cell by hand as `{"type": COVER, "z": 3}`, and it *behaved correctly* —
## `Ballistics.density_of` falls back to the type's implied material for pre-material fixtures
## and reached the identical density. The only symptom was that the terrain ledger recorded an
## empty `material_before`, which the reproduction schema types loosely enough to validate. A
## compatibility default absorbed a special case in silence.
##
## Every `get(key, default)` in an authority is a place that can happen. The defaults are almost
## all correct — a missing cell reading as open ground is the conservative answer — so the
## remedy is not to remove them. It is to assert the *shape* of what enters the model, which is
## what defaults cannot do.
const CELL_FIELDS := ["type", "z", "density", "integrity", "material", "tiers", "climbable"]

## Fields a cell may additionally carry once it has been worked on.
const CELL_OPTIONAL_FIELDS := ["tiers_lost"]

## "" when the cell has the shape the model expects, otherwise why not. Pure, so a headless
## test can walk a whole grid with it.
static func cell_shape_error(cell_data) -> String:
	if not (cell_data is Dictionary):
		return "not a Dictionary"
	var data: Dictionary = cell_data
	var missing: Array = []
	for field in CELL_FIELDS:
		if not data.has(field):
			missing.append(field)
	if not missing.is_empty():
		return "missing %s (has %s)" % [str(missing), str(data.keys())]
	var unknown: Array = []
	for key in data.keys():
		var name := String(key)
		if not CELL_FIELDS.has(name) and not CELL_OPTIONAL_FIELDS.has(name):
			unknown.append(name)
	if not unknown.is_empty():
		return "carries unrecognised field(s) %s" % str(unknown)
	if int(data["density"]) < 0 or int(data["integrity"]) < 0:
		return "negative material (density %d, integrity %d)" % [int(data["density"]), int(data["integrity"])]
	if int(data["integrity"]) > int(data["density"]):
		return "integrity %d exceeds the density %d it started with" % [int(data["integrity"]), int(data["density"])]
	if int(data["tiers"]) < int(data["z"]):
		return "z %d exceeds the %d tiers it started with" % [int(data["z"]), int(data["tiers"])]
	return ""

## Below this fraction of its original material, a cell has taken a hit worth showing.
## Not zero: floating-point division on an undamaged cell must not register as wear.
const WEAR_VISIBLE_AT := 0.995

## Scorched-ground darkening for a cell with nothing left standing. Also the ceiling on
## the continuous curve below, so nothing can look worse than rubble.
const RUBBLE_DARKEN := 0.55

## How fast damage darkens a surface. Chosen so the single continuous formula reproduces
## both constants the old three-state version used: at the soft-cover threshold (integrity
## just under half its original density) it lands on 0.30, and at total loss it reaches
## 0.60 and clamps to RUBBLE_DARKEN.
const DARKEN_PER_DAMAGE := 0.6

## How much of its original material a cell still has: 1.0 pristine, 0.0 nothing left.
##
## Pure, so the appearance model can be asserted headlessly without building a scene —
## the same reason `HudLayout` exists for the HUD and `Ballistics` for combat.
##
## `density` is what the material started as and `integrity` is what is left, so the ratio
## is already in the data. Nothing new is stored to support the visuals.
static func wear_of(cell_data) -> float:
	if not (cell_data is Dictionary):
		return 1.0
	var data: Dictionary = cell_data
	var started := int(data.get("density", 0))
	if started <= 0:
		# Open ground has no material to lose, so it cannot be worn. Rubble is the
		# exception: it *is* the end state and carries density 0 by construction, so the
		# material tag is what separates "never had anything" from "lost everything".
		return 0.0 if String(data.get("material", "")) == "rubble" else 1.0
	if not data.has("integrity"):
		# Pre-material cells — including the golden fixtures — imply full material from
		# their type, exactly as `Ballistics.density_of` treats them.
		return 1.0
	return clampf(float(int(data["integrity"])) / float(started), 0.0, 1.0)

## How a cell should look, derived from how much material it has lost.
##
## The destruction model has always been continuous — integrity runs from its original
## density down to zero — while the visuals were three discrete states and only two of them
## drew anything at all. A hard wall at 51 of 100 integrity is one shot from collapsing and
## rendered identical to an untouched one. This makes the appearance follow the number.
static func damage_appearance(cell_data) -> Dictionary:
	var wear := wear_of(cell_data)
	var material := ""
	if cell_data is Dictionary:
		material = String((cell_data as Dictionary).get("material", ""))
	# Wear decides *whether* a cell looks damaged. The material only decides *how* damage
	# reads once there is damage to show.
	#
	# The order matters and the first version got it wrong. `material_cell` names
	# HALF_COVER's material "soft" as a description of what it is made of, while
	# `degrade_cell` writes "soft" to mean a hard wall worked down to soft — the same string
	# for two different things. Testing the material before wear classified every untouched
	# half-cover tile on the board as damaged, which would have duplicated a material per
	# tile and leaned them all. Every invariant still held; the numbers printed in a table
	# are what showed it.
	var state := "pristine"
	if material == "rubble" or wear <= 0.0:
		state = "rubble"
	elif wear >= WEAR_VISIBLE_AT:
		state = "pristine"
	elif material == "soft":
		state = "soft"
	else:
		state = "worn"
	var damage := 1.0 - wear
	var appearance := {
		"state": state,
		"wear": wear,
		"damage": damage,
		"draws": state != "pristine",
		"darken": 0.0,
		"scorched": false,
		"yaw_deg": 0.0,
		"tilt_deg": 0.0
	}
	if state == "pristine":
		return appearance
	appearance["darken"] = minf(damage * DARKEN_PER_DAMAGE, RUBBLE_DARKEN)
	match state:
		"rubble":
			# Nothing standing: dark, matte, faintly warm from the detonation, and
			# rotated off-grid so the ground reads as disturbed.
			appearance["darken"] = RUBBLE_DARKEN
			appearance["scorched"] = true
			appearance["yaw_deg"] = _visual_jitter(cell_data, 31, 23, 11.0)
		"soft":
			# Worked down to soft material: cracked, dulled, and leaning.
			appearance["tilt_deg"] = _visual_jitter(cell_data, 13, 29, 4.0)
		"worn":
			# Still standing and still hard. It darkens and roughens with each hit, and
			# it does not lean, because leaning is what soft material does.
			pass
	return appearance

## Darkening steps finer than this are not worth a rebuild. Roughly 28 distinguishable steps
## between pristine and rubble, which is far more than a player can see and far fewer than one
## rebuild per point of integrity.
const DARKEN_QUANTUM := 0.02

## Everything about a cell that changes how its tile is drawn, as one comparable string.
##
## This exists because appearance being continuous is useless if the *redraw* is not.
## `Main.damage_terrain` used to rebuild a tile only when the cell's height or its cover level
## changed, both of which are threshold crossings — so a wall could take three rifle rounds,
## lose a third of its material, and never be redrawn. The old three-state visual was not
## merely coarse; it was the only thing the rebuild trigger could ever express.
##
## Height and type are included, so this fully subsumes the height and cover-level conditions
## it replaces: crossing a cover threshold changes the state, and crossing a height change
## changes `z`.
static func tile_visual_signature(cell_data) -> String:
	if not (cell_data is Dictionary):
		return "none"
	var data: Dictionary = cell_data
	var look := damage_appearance(data)
	var darken_step := int(round(float(look["darken"]) / DARKEN_QUANTUM))
	return "%d|%d|%s|%d|%s" % [
		int(data.get("type", Config.FLOOR)),
		int(data.get("z", 0)),
		String(look["state"]),
		darken_step,
		"1" if bool(look["scorched"]) else "0"
	]

## Deterministic per-cell visual variation. Derived from the coordinates so a rebuild of the
## same cell looks the same every time, which a replay depends on.
static func _visual_jitter(cell_data, a: int, b: int, spread: float) -> float:
	var cell := Vector2i.ZERO
	if cell_data is Dictionary and (cell_data as Dictionary).has("cell"):
		cell = (cell_data as Dictionary)["cell"]
	var span := int(spread * 2.0) + 1
	return float(absi(cell.x * a + cell.y * b) % span) - spread

static func build_grid(
	parent: Node3D,
	tiles_root: Node3D,
	map_seed: int
) -> Dictionary:
	var cells := generate_cells(map_seed)
	for x in Config.GRID_W:
		for y in Config.GRID_H:
			var c := Vector2i(x, y)
			var data: Dictionary = cells[c]
			# Pass the cell through, so a map that arrives already damaged — an imported
			# strategic hand-off or a replayed mission — builds looking damaged instead of
			# rendering pristine until something hits it again.
			spawn_tile(tiles_root, c, int(data["type"]), int(data["z"]), map_seed, data)

	var game_state = parent.get_node_or_null("/root/GameState")
	if game_state:
		game_state.cells = cells
	return cells

## Public so a mid-mission terrain change can rebuild exactly one tile. `cell_data` is the
## cell itself, so appearance is derived from the material it has left rather than passed in
## as a separate label that could disagree with it.
static func spawn_tile(
	tiles_root: Node3D,
	c: Vector2i,
	t: int,
	h: int,
	map_seed: int,
	cell_data: Dictionary = {}
) -> void:
	_spawn_tile(tiles_root, c, t, h, map_seed)
	# `cell` is only needed so the deterministic jitter matches the coordinate being drawn;
	# the caller's dictionary is not mutated.
	var described := cell_data.duplicate()
	described["cell"] = c
	var look := damage_appearance(described)
	# An undamaged tile must be left exactly as `_spawn_tile` built it. An earlier version
	# duplicated the material and attached an override for pristine terrain too, which leaked
	# a material per rebuild and meant no override actually distinguished damage.
	if not bool(look.get("draws", false)):
		return
	var tile := tiles_root.get_node_or_null("Tile_%d_%d" % [c.x, c.y]) as MeshInstance3D
	if tile == null:
		return
	var surface := tile.get_active_material(0) as StandardMaterial3D
	if surface == null:
		return
	surface = surface.duplicate() as StandardMaterial3D
	surface.albedo_color = surface.albedo_color.darkened(float(look["darken"]))
	# Damage is matte. Anything that was polished stops being polished once it is broken.
	surface.roughness = 1.0
	surface.metallic = 0.0
	if bool(look.get("scorched", false)):
		surface.emission_enabled = true
		surface.emission = Color(0.35, 0.12, 0.05)
		surface.emission_energy_multiplier = 0.25
	else:
		# A pillar that was emissive when pristine loses its glow as it is worked down, in
		# step with the darkening rather than all at once.
		surface.emission_energy_multiplier = surface.emission_energy_multiplier * float(look["wear"])
	#  rather than a per-surface override: it is what the rest of this
	# codebase and the playtest suite already assert on, and the tiles are single-surface.
	tile.material_override = surface
	var yaw := float(look.get("yaw_deg", 0.0))
	var tilt := float(look.get("tilt_deg", 0.0))
	if not is_zero_approx(yaw):
		tile.rotation_degrees.y = yaw
	if not is_zero_approx(tilt):
		tile.rotation_degrees.z = tilt

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
