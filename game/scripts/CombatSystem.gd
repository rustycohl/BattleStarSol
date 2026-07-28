extends Node
class_name CombatSystem

const Config = preload("res://scripts/GameConfig.gd")

var main: Node

func setup(m: Node) -> void:
	main = m

func execute_melee(attacker: Unit, target: Unit, use_offhand: bool) -> void:
	if attacker.ap < Config.MELEE_COST:
		main._hint("Not enough AP to strike.")
		return
	var a: Dictionary = main.inventory.hand_item(attacker, use_offhand)
	var kind: String = a["kind"]
	var dir: Vector2i = target.cell - attacker.cell

	if kind == "":
		_do_bash(attacker, target, "fist", false)
		return

	var item = ItemDB.get_item(kind)
	if not item.is_empty() and item.get("category", "") == "melee":
		if a["two"] and (kind == "spear" or kind == "club" or kind == "stringedbow"):
			_do_sweep(attacker, dir, kind)
		else:
			_do_bash(attacker, target, kind, a["two"])
	else:
		_do_bash(attacker, target, kind, a["two"])

## Synchronous preflight used by perform_action so false "accepted" intents are not recorded.
func can_attempt_ranged(attacker: Unit, target: Unit, use_offhand: bool) -> bool:
	var a: Dictionary = main.inventory.hand_item(attacker, use_offhand)
	var kind: String = a["kind"]
	if kind == "":
		main._hint("No weapon ready in that hand.")
		return false
	var item = ItemDB.get_item(kind)
	if item.is_empty():
		main._hint("Unknown weapon: %s." % kind)
		return false
	if kind == "arrow":
		main._hint("Arrows must be fired from a bow.")
		return false
	var rng = int(item.get("range", 1))
	var cost = ActionEconomy.weapon_cost(item)
	var penetrates_cover := bool(item.get("penetrates_cover", false))
	var ignored_cover := Config.INVALID_CELL
	if attacker.taking_cover and attacker.lean != "none":
		ignored_cover = attacker.cover_cell
	if Pathfinder.cheb(attacker.cell, target.cell) > rng:
		main._hint("Target out of range for %s (Range %d)." % [item.get("name", kind), rng])
		return false
	if not Pathfinder.has_los(
		attacker.cell,
		target.cell,
		main.cells,
		attacker.z,
		target.z,
		ignored_cover,
		penetrates_cover
	):
		if attacker.taking_cover and attacker.lean == "none":
			main._hint("Selected cover blocks the shot. Lean or use a cover-penetrating weapon.")
		else:
			main._hint("No line of sight.")
		return false
	if kind == "stringedbow" and int(attacker.inv.get("arrow", 0)) <= 0:
		main._hint("Need arrows and %d AP." % cost)
		return false
	if attacker.ap < cost:
		main._hint("Not enough AP (%d) to fire %s." % [cost, kind])
		return false
	if kind == "spear" or kind == "stringedbow":
		var line := Pathfinder.line(attacker.cell, target.cell, rng, main.cells, attacker.z, ignored_cover)
		if not line.has(target.cell):
			main._hint("Cover blocks trajectory.")
			return false
	return true

func execute_ranged(attacker: Unit, target: Unit, use_offhand: bool) -> void:
	if not can_attempt_ranged(attacker, target, use_offhand):
		return
	var a: Dictionary = main.inventory.hand_item(attacker, use_offhand)
	var kind: String = a["kind"]
	var item = ItemDB.get_item(kind)
	var rng = int(item.get("range", 1))
	var cost = ActionEconomy.weapon_cost(item)
	var dmg = int(item.get("dmg", 1))

	if kind == "spear":
		_try_spear_click(attacker, target, cost, dmg, rng)
	elif kind == "stringedbow":
		_try_fire_bow(attacker, target, cost, dmg, rng)
	else:
		_do_generic_ranged(attacker, target, kind, cost, dmg, item.get("category", "") == "melee")

func _do_generic_ranged(attacker: Unit, target: Unit, kind: String, cost: int, dmg: int, is_thrown: bool) -> void:
	if Engine.get_main_loop().root.has_node("AudioSystem"):
		Engine.get_main_loop().root.get_node("AudioSystem").play_3d(kind, attacker.node.position)
	main.set_action_busy(true)
	attacker.ap -= cost
	if is_thrown:
		attacker.inv[kind] = int(attacker.inv.get(kind, 0)) - 1
		main._refresh_label(attacker)

	var landing := target.cell
	var proj := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, 0.08, 0.3)
	if is_thrown:
		mat.albedo_color = Color(0.55, 0.45, 0.35)
		bm.size = Vector3(0.16, 0.16, 0.5)
	else:
		mat.albedo_color = Color(1, 1, 0)
		mat.emission_enabled = true
		mat.emission = Color(1, 0.8, 0.2)
		mat.emission_energy_multiplier = 4.0
	bm.material = mat
	proj.mesh = bm
	main.add_child(proj)

	var start = attacker.node.position + Vector3(0, 1.2, 0)
	var endp = main._cell_to_world(landing) + Vector3(0, 1.2, 0)
	proj.position = start
	if start.distance_squared_to(endp) > 0.001:
		var dir_v = (endp - start).normalized()
		if absf(dir_v.dot(Vector3.UP)) < 0.99:
			proj.look_at(endp, Vector3.UP)
		else:
			proj.look_at(endp, Vector3.RIGHT)
	var tw := create_tween()
	tw.tween_property(proj, "position", endp, 0.08 if not is_thrown else 0.16)
	await tw.finished
	proj.queue_free()

	var dealt := apply_damage(target, dmg, true, attacker.cell, kind, attacker)
	if is_thrown:
		main._add_debris(landing, kind, 1)
	main._hint("%s hit for %d." % [kind.capitalize(), dealt])
	main._update_ui()
	main._check_end()
	main.set_action_busy(false)

func _try_spear_click(attacker: Unit, target: Unit, cost: int, dmg: int, rng: int) -> void:
	if attacker.ap < cost or Pathfinder.cheb(attacker.cell, target.cell) > rng:
		main._hint("Spear out of range or insufficient AP.")
		return
	var ignored_cover := attacker.cover_cell if attacker.taking_cover and attacker.lean != "none" else Config.INVALID_CELL
	var line := Pathfinder.line(attacker.cell, target.cell, rng, main.cells, attacker.z, ignored_cover)
	if not line.has(target.cell):
		main._hint("Cover blocks spear trajectory.")
		return
	_do_spear(attacker, line, cost, dmg)

func _try_fire_bow(attacker: Unit, target: Unit, cost: int, dmg: int, rng: int) -> void:
	if int(attacker.inv.get("arrow", 0)) <= 0 or attacker.ap < cost:
		main._hint("Need arrows and %d AP." % cost)
		return
	if Pathfinder.cheb(attacker.cell, target.cell) > rng:
		main._hint("Out of bow range.")
		return
	var ignored_cover := attacker.cover_cell if attacker.taking_cover and attacker.lean != "none" else Config.INVALID_CELL
	var line := Pathfinder.line(attacker.cell, target.cell, rng, main.cells, attacker.z, ignored_cover)
	if not line.has(target.cell):
		main._hint("Cover blocks arrow.")
		return
	_do_fire_bow(attacker, line, cost, dmg)

func _melee_dmg(kind: String, two: bool) -> int:
	if kind == "fist" or kind == "": return Config.FIST_DMG

	var item = ItemDB.get_item(kind)
	if not item.is_empty():
		var d = int(item.get("dmg", 1))
		if item.get("category", "melee") == "ranged":
			return maxi(int(d / 2.0), 2)
		if two: return int(d * 1.5)
		return d

	match kind:
		"rock": return Config.ROCK_2H_DMG if two else Config.ROCK_1H_DMG
		"spear": return Config.SPEAR_SWEEP_DMG
		"club": return Config.CLUB_SWEEP_DMG
		"stringedbow": return Config.STRUNG_MELEE_DMG
		"bow": return Config.BOW_MELEE_DMG
		"string": return Config.STRING_MELEE_DMG
		_: return Config.FIST_DMG

func _do_bash(attacker: Unit, target: Unit, kind: String, two: bool) -> void:
	main.set_action_busy(true)
	attacker.ap -= Config.MELEE_COST
	var dmg := _melee_dmg(kind, two)
	await _lunge(attacker, target.cell)
	var dealt := apply_damage(target, dmg, false, attacker.cell, kind, attacker)
	main._hint("%s hits %s for %d damage." % [attacker.name, target.name, dealt])
	main._update_ui()
	main._check_end()
	main.set_action_busy(false)

func _do_sweep(attacker: Unit, dir: Vector2i, kind: String) -> void:
	main.set_action_busy(true)
	attacker.ap -= Config.MELEE_COST
	var dmg := _melee_dmg(kind, true)
	await _lunge(attacker, attacker.cell + dir)
	var hits := 0
	var front: Vector2i = attacker.cell + dir
	var perp := Vector2i(dir.y, dir.x)
	for c in [front, front + perp, front - perp]:
		var v: Unit = main._unit_at(c)
		if v != null and v != attacker and v.alive:
			apply_damage(v, dmg, false, attacker.cell, kind, attacker)
			hits += 1
	main._hint("%s sweep hits %d target(s) for %d." % [kind.capitalize(), hits, dmg])
	main._update_ui()
	main._check_end()
	main.set_action_busy(false)

func _knockback(target: Unit, dir: Vector2i) -> void:
	var dest := target.cell + dir
	if Pathfinder.cell_free(dest, main.cells, main.units):
		var previous_z := target.z
		var dest_z: int = main.cells[dest].get("z", 0)

		# Prevent knocking UP walls
		if dest_z > previous_z + 1:
			return

		target.cell = dest
		target.z = dest_z

		var final_pos: Vector3 = main._cell_to_world(dest)
		final_pos.y = float(dest_z) * Config.HEIGHT_STEP

		var tw := main.create_tween()
		tw.tween_property(target.node, "position", final_pos, 0.15)
		await tw.finished

		var drop_dist := previous_z - dest_z
		if drop_dist > 0 and not (target.hovering or target.flying):
			apply_fall_damage(target, drop_dist)

func _lunge(u: Unit, toward_cell: Vector2i) -> void:
	if Engine.get_main_loop().root.has_node("AudioSystem"):
		Engine.get_main_loop().root.get_node("AudioSystem").play_3d("melee_swing", u.node.position)
	var orig := u.node.position
	var toward: Vector3 = main._cell_to_world(toward_cell)
	var tw := create_tween()
	tw.tween_property(u.node, "position", orig.lerp(toward, 0.35), 0.08)
	tw.tween_property(u.node, "position", orig, 0.08)
	await tw.finished

func _do_spear(attacker: Unit, line: Array[Vector2i], cost: int, dmg: int) -> void:
	main.set_action_busy(true)
	attacker.ap -= cost
	attacker.inv["spear"] = int(attacker.inv.get("spear", 0)) - 1
	await _perform_pierce(attacker, line, dmg, "spear")
	main.set_action_busy(false)

func _do_fire_bow(attacker: Unit, line: Array, cost: int, dmg: int) -> void:
	main.set_action_busy(true)
	attacker.ap -= cost
	attacker.inv["arrow"] = int(attacker.inv.get("arrow", 0)) - 1
	await _perform_pierce(attacker, line, dmg, "arrow")
	main.set_action_busy(false)

func _perform_pierce(attacker: Unit, line: Array, dmg: int, drop_kind: String) -> void:
	if line.is_empty():
		return
	if attacker.node == null or not is_instance_valid(attacker.node):
		return
	if Engine.get_main_loop().root.has_node("AudioSystem"):
		Engine.get_main_loop().root.get_node("AudioSystem").play_3d("pierce_" + drop_kind, attacker.node.position)
	main._refresh_label(attacker)
	var landing: Vector2i = line[line.size() - 1]
	var shaft := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(0.1, 0.1, 1.3)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.78, 0.7, 0.5)
	bar.material = m
	shaft.mesh = bar
	main.add_child(shaft)
	var start := attacker.node.position + Vector3(0, 1.1, 0)
	var endp: Vector3 = main._cell_to_world(landing) + Vector3(0, 1.1, 0)
	shaft.position = start
	if start.distance_squared_to(endp) > 0.001:
		var dir_v = (endp - start).normalized()
		if absf(dir_v.dot(Vector3.UP)) < 0.99:
			shaft.look_at(endp, Vector3.UP)
		else:
			shaft.look_at(endp, Vector3.RIGHT)
	var tw := create_tween()
	tw.tween_property(shaft, "position", endp, 0.28)
	await tw.finished
	shaft.queue_free()
	var _hits := 0
	for c in line:
		var v: Unit = main._unit_at(c)
		if v != null and v != attacker and v.alive:
			apply_damage(v, dmg, false, attacker.cell, drop_kind, attacker)
			_hits += 1
	main._add_debris(landing, drop_kind, 1)
	main._update_ui()
	main._check_end()

func apply_damage(target: Unit, base_dmg: int, is_ranged: bool, from_c: Vector2i, weapon: String = "fist", attacker: Unit = null) -> int:
	if not is_instance_valid(target.node) or not target.alive:
		return 0
	if target.flipping and main.sim_rng.randf() < 0.75:
		main._hint("%s FLIPPED over attack!" % target.name)
		GameState.record_event("attack_avoided", {
			"target": target.unit_id,
			"attacker": attacker.unit_id if attacker != null else 0,
			"weapon": weapon,
			"method": "flip"
		})
		return 0
	elif target.dodging and main.sim_rng.randf() < 0.50:
		main._hint("%s DODGED attack!" % target.name)
		GameState.record_event("attack_avoided", {
			"target": target.unit_id,
			"attacker": attacker.unit_id if attacker != null else 0,
			"weapon": weapon,
			"method": "dodge"
		})
		return 0

	var dmg_f := float(base_dmg)
	if attacker != null and attacker.frenzied:
		dmg_f += 1.0
	if target.frenzied:
		dmg_f += 1.0
	var is_kinetic := true
	var dmg_type := "kinetic"
	var a_pierce := 0

	if is_ranged:
		var weapon_item: Dictionary = ItemDB.get_item(weapon)
		var penetrates_cover := bool(weapon_item.get("penetrates_cover", false))
		dmg_type = String(weapon_item.get("damage_type", "kinetic"))
		a_pierce = int(weapon_item.get("armor_pierce", 0))
		is_kinetic = (dmg_type == "kinetic")

		var cover_state: int = main._in_cover(from_c, target.cell)
		if target.stance == "crouch" and cover_state == 1:
			cover_state = 2 # Crouching behind half-cover gives full-cover benefit

		if cover_state == 2 and not penetrates_cover:
			dmg_f -= Config.COVER_REDUCTION
		elif cover_state == 1 and not penetrates_cover:
			dmg_f -= Config.HALF_COVER_REDUCTION

		if target.stance == "crouch":
			dmg_f *= 0.75
		elif target.stance == "prone":
			dmg_f *= 0.50
		if target.lean != "none":
			dmg_f *= 0.75
	else:
		# Melee weapons can also carry typed damage from ItemDB (e.g. thermal blades).
		var melee_item: Dictionary = ItemDB.get_item(weapon)
		if not melee_item.is_empty():
			dmg_type = String(melee_item.get("damage_type", "kinetic"))
			a_pierce = int(melee_item.get("armor_pierce", 0))
			is_kinetic = (dmg_type == "kinetic")
		if target.stance == "prone":
			dmg_f *= 1.5

	if target.blocking:
		dmg_f -= Config.BLOCK_REDUCTION

	if attacker != null and attacker.z > target.z:
		dmg_f += float(Config.HIGH_GROUND_BONUS * (attacker.z - target.z))

	# Armor Mitigation & Degradation
	var armor_before := target.armor
	var eff_armor = maxi(target.armor - a_pierce, 0)
	if is_kinetic:
		if eff_armor > 0:
			dmg_f = maxf(dmg_f - float(eff_armor), 1.0)
		target.armor = maxi(target.armor - 1, 0) # Kinetic ablates 1 armor
	elif dmg_type == "thermal":
		target.armor = maxi(target.armor - 2, 0) # Thermal burns 2 armor rapidly, but ignores armor reduction
	# Rail ignores armor and doesn't ablate it

	var dmg := maxi(int(round(dmg_f)), 1)

	var hp_before := target.hp
	target.hp -= dmg
	GameState.record_event("damage_resolved", {
		"target": target.unit_id,
		"attacker": attacker.unit_id if attacker != null else 0,
		"weapon": weapon,
		"damage": dmg,
		"hp_before": hp_before,
		"hp_after": target.hp,
		"ranged": is_ranged
	})
	main._refresh_label(target)

	if target.hp < target.max_hp * 0.3 and target.alive:
		if Narrative:
			Narrative.generate_stagger_narrative(target.name)

	if target.hp <= 0 and target.alive:
		kill_unit(target, attacker, weapon)
	else:
		if armor_before > 0 and target.armor == 0 and target.max_armor > 0:
			main._hint("Armor COMPROMISED!")
		elif eff_armor > 0 and is_kinetic:
			main._hint("Armor Mitigated Damage!")

	return dmg

func apply_fall_damage(target: Unit, z_drop: int) -> void:
	if z_drop <= 1:
		return
	var base_fall_dmg := (z_drop - 1) * 3
	var final_dmg = base_fall_dmg
	if target.stance == "roll" or target.stance == "prone":
		final_dmg = max(0, final_dmg - 6)
		main._hint("%s rolled to mitigate fall!" % target.name)
	elif target.stance == "crouch":
		final_dmg = int(final_dmg * 0.5)
		main._hint("%s crouched to absorb fall!" % target.name)

	if final_dmg > 0:
		var hp_before := target.hp
		target.hp -= final_dmg
		GameState.record_event("damage_resolved", {
			"target": target.unit_id,
			"attacker": 0,
			"weapon": "gravity",
			"damage": final_dmg,
			"hp_before": hp_before,
			"hp_after": target.hp,
			"ranged": false
		})
		main._hint("%s took %d FALL DAMAGE!" % [target.name, final_dmg])
		main._refresh_label(target)
		if target.hp <= 0 and target.alive:
			kill_unit(target, null, "gravity")
			main._check_end()

func kill_unit(u: Unit, attacker: Unit = null, weapon: String = "fist") -> void:
	if u == null or not u.alive:
		return
	u.alive = false
	GameState.record_event("unit_killed", {
		"target": u.unit_id,
		"attacker": attacker.unit_id if attacker != null else 0,
		"weapon": weapon,
		"cell": {"x": u.cell.x, "y": u.cell.y, "z": u.z}
	})
	var death_pos := Vector3.ZERO
	if u.node != null and is_instance_valid(u.node):
		death_pos = u.node.position
	if Engine.get_main_loop().root.has_node("AudioSystem"):
		Engine.get_main_loop().root.get_node("AudioSystem").play_3d("death", death_pos)
	for k in u.inv.keys():
		if int(u.inv.get(k, 0)) > 0:
			main._add_debris(u.cell, k, int(u.inv[k]))
			u.inv[k] = 0
	if main.selected == u:
		main.selected = null
	if u.node != null and is_instance_valid(u.node):
		u.node.queue_free()
		u.node = null
		u.fig = null
		u.label = null
		u.node = null
		u.fig = null
		u.label = null
	if main.selected == u:
		main.selected = null

	if u.team != main.player_faction and GameState:
		var nf = main.sim_rng.randi_range(100, 500)
		GameState.add_loot("fiat", nf)
		GameState.add_loot("neural", 25)
		main._hint("Loot Collected: +$" + str(nf) + " / +25 NEURAL")

	if attacker != null and attacker.team == main.player_faction and Economy:
		Economy.earn_neural(50, "Hostile Elimination")
		if Narrative:
			Narrative.generate_kill_narrative(attacker.name, u.name, weapon)

	main._check_end()
