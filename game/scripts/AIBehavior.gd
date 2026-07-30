extends Node

# AIBehavior.gd — Behavioral enemy decision scoring ("rip and tear")

const Tactics = preload("res://scripts/AITactics.gd")

func _vertical_score(u, target_cell: Vector2i, cells: Dictionary) -> float:
	var my_h: int = cells.get(u.cell, {}).get("z", 0)
	var tgt_h: int = cells.get(target_cell, {}).get("z", 0)
	return float(tgt_h - my_h) * 8.0

# Difficulty-scaled score jitter (purely behavioral — see GameConfig.Difficulty).
# Higher modes play more consistently; Rip and Tear is the most chaotic.
func _jit(rng: RandomNumberGenerator) -> float:
	return rng.randf() * GameConfig.ai_jitter_amp(GameState.difficulty)

func score_actions(
	u,
	units: Array,
	cells: Dictionary,
	debris: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var attack_profile := _attack_profile(u)

	# 1. Block decision if low HP (skipped entirely on Rip and Tear — pure aggression)
	if GameConfig.ai_uses_defense(GameState.difficulty) and u.hp <= int(u.max_hp * GameConfig.LOW_HP_BLOCK_THRESHOLD) and u.ap >= GameConfig.BLOCK_COST and not u.blocking:
		var score = 100.0 + float(u.max_hp - u.hp) * 2.0 + _jit(rng)
		candidates.append({"key": "block", "value": true, "score": score})

	# 2. Adjacent melee attack (highest priority when in range)
	var adj_player = _adjacent_player(u, units)
	if adj_player != null and u.ap >= GameConfig.MELEE_COST:
		var score = 85.0 + _vertical_score(u, adj_player.cell, cells) + _jit(rng)
		candidates.append({"key": "melee", "value": adj_player, "score": score})

	# 3. Loot debris if unarmed
	if _total_weapons(u) == 0:
		if debris.has(u.cell) and u.ap >= GameConfig.GRAB_COST:
			var score = 65.0 + _jit(rng)
			candidates.append({"key": "grab", "value": true, "score": score})
		var dpath := Pathfinder.nearest_debris_path(u.cell, debris, cells, units)
		if not dpath.is_empty():
			var score = 55.0 + _jit(rng)
			candidates.append({"key": "approach", "value": dpath, "score": score})

	# 4/5. Generic Ranged / Thrown Weapons
	for kind in u.inv.keys():
		if int(u.inv.get(kind, 0)) <= 0: continue
		var ItemDB = Engine.get_main_loop().root.get_node_or_null("ItemDB")
		var item = ItemDB.get_item(kind) if ItemDB else {}
		if item.is_empty(): continue

		var cost = ActionEconomy.weapon_cost(item)
		var range_cells = int(item.get("range", 1))
		var cat = item.get("category", "")
		var dmg = int(item.get("dmg", 1))
		var ignored_cover := (
			Vector2i(u.cover_cell)
			if bool(u.taking_cover) and String(u.lean) != "none"
			else GameConfig.INVALID_CELL
		)
		var penetrates_cover := bool(item.get("penetrates_cover", false))

		if u.ap >= cost and (cat == "ranged" or (cat == "melee" and range_cells > 1)):
			if kind == "arrow":
				continue
			if kind == "stringedbow" and int(u.inv.get("arrow", 0)) <= 0:
				continue

			if kind == "spear" or kind == "stringedbow":
				var sline := _enemy_spear_line(
					u,
					units,
					cells,
					range_cells,
					ignored_cover,
					penetrates_cover
				)
				if not sline.is_empty():
					var tgt_cell: Vector2i = sline[sline.size() - 1]
					var score = 75.0 + _vertical_score(u, tgt_cell, cells) + _jit(rng)
					# Hack: We map generic piercing to throw_spear or fire_bow in the return
					var act_key = "throw_spear" if kind == "spear" else "fire_bow"
					candidates.append({"key": act_key, "value": {"line": sline, "kind": kind, "cost": cost, "dmg": dmg}, "score": score})
			else:
				var tgt = _throw_target(
					u,
					kind,
					units,
					cells,
					range_cells,
					ignored_cover,
					penetrates_cover
				)
				if tgt != null:
					var score = 65.0 + _vertical_score(u, tgt.cell, cells) + _jit(rng)
					candidates.append({"key": "throw_item", "value": {"target": tgt, "kind": kind, "cost": cost, "dmg": dmg}, "score": score})

	# 6. Bow Assembly & Firing
	if int(u.inv.get("bow", 0)) > 0 and int(u.inv.get("string", 0)) > 0 and u.ap >= GameConfig.ASSEMBLE_COST:
		candidates.append({"key": "assemble_auto", "value": null, "score": 75.0 + _jit(rng)})

	if int(u.inv.get("stringedbow", 0)) > 0 and int(u.inv.get("arrow", 0)) > 0 and u.ap >= GameConfig.BOW_COST:
		var target = _nearest_player(u, units)
		if target != null:
			var bow_item = {}
			var ItemDBNode = Engine.get_main_loop().root.get_node_or_null("ItemDB")
			if ItemDBNode:
				bow_item = ItemDBNode.get_item("stringedbow")
			var bow_range := int(bow_item.get("range", GameConfig.BOW_RANGE)) if not bow_item.is_empty() else GameConfig.BOW_RANGE
			var bow_cost := ActionEconomy.weapon_cost(bow_item) if not bow_item.is_empty() else GameConfig.BOW_COST
			var bow_dmg := int(bow_item.get("dmg", GameConfig.BOW_DMG)) if not bow_item.is_empty() else GameConfig.BOW_DMG
			var bow_cover := (
				Vector2i(u.cover_cell)
				if bool(u.taking_cover) and String(u.lean) != "none"
				else GameConfig.INVALID_CELL
			)
			var bow_line := Pathfinder.line(
				u.cell,
				target.cell,
				bow_range,
				cells,
				u.z,
				bow_cover
			)
			if not bow_line.is_empty() and bow_line.has(target.cell):
				var score = 85.0 + _vertical_score(u, target.cell, cells) + _jit(rng)
				# Always emit a Dictionary so Main._enemy_act can read line/cost/dmg
				# (a raw Array here previously typed as Dictionary and crashed AI turns).
				candidates.append({
					"key": "fire_bow",
					"value": {"line": bow_line, "kind": "stringedbow", "cost": bow_cost, "dmg": bow_dmg},
					"score": score
				})

	# 7. Advanced Mobility (Gated by God Mode)
	var main_node = Engine.get_main_loop().root.get_node_or_null("Main")
	var dev_god_mode = main_node.dev_god_mode if main_node else false

	if dev_god_mode:
		var target = _nearest_player(u, units)
		if target != null:
			# FLIGHT EVALUATION
			if not u.flying and u.ap >= GameConfig.FLIGHT_TOGGLE_COST:
				# Score flight if the target is significantly higher and we have the special
				if main_node._special_enabled(u, "flight") and _vertical_score(u, target.cell, cells) > 16.0:
					var score = 70.0 + _jit(rng)
					candidates.append({"key": "toggle_flight", "value": true, "score": score})
			
			# WALL RUN EVALUATION
			if main_node._special_enabled(u, "wall_run") and u.ap >= GameConfig.WALL_RUN_COST:
				# Simple heuristic: if a wall-run towards the target is valid, score it.
				# We check adjacent cells in the direction of the target.
				var dir_x = sign(target.cell.x - u.cell.x)
				var dir_y = sign(target.cell.y - u.cell.y)
				var potential_targets = [
					Vector2i(u.cell.x + dir_x, u.cell.y),
					Vector2i(u.cell.x, u.cell.y + dir_y)
				]
				for pt in potential_targets:
					if pt != u.cell and main_node._wall_run_target_valid(u, pt):
						# Must bring us closer to target vertically or horizontally
						var score = 65.0 + _vertical_score(u, pt, cells) + _jit(rng)
						candidates.append({"key": "wall_run", "value": pt, "score": score})
						break # only need one valid wall run candidate

	# 8. Current-cover and bounded positional tactics. These candidates use the
	# same path, LOS, cover, and AP authorities as player actions.
	candidates.append_array(
		Tactics.positioning_candidates(
			u,
			units,
			cells,
			Pathfinder,
			attack_profile
		)
	)

	# 8. Aggressive approach and greedy fallback. Positional movement retains
	# enough AP for the cheapest available attack instead of spending to zero.
	if not bool(u.taking_cover):
		var attack_reserve := int(attack_profile.get("cost", GameConfig.MELEE_COST))
		var path := _best_approach(u, units, cells)
		if (
			not path.is_empty()
			and path.size() >= 2
			and Tactics.can_afford_step_with_reserve(
				u,
				Vector2i(path[1]),
				cells,
				attack_reserve
			)
		):
			var end_cell: Vector2i = path[path.size() - 1]
			var score = 50.0 + _vertical_score(u, end_cell, cells) + _jit(rng)
			candidates.append({
				"key": "approach",
				"value": path,
				"score": score,
				"rationale": "direct approach; retain %d AP attack reserve" % attack_reserve
			})

		var greedy := _greedy_step(u, units, cells)
		if (
			greedy != GameConfig.INVALID_CELL
			and Tactics.can_afford_step_with_reserve(
				u,
				greedy,
				cells,
				attack_reserve
			)
		):
			var score = 35.0 + _jit(rng)
			candidates.append({
				"key": "step",
				"value": greedy,
				"score": score,
				"rationale": "greedy legal step; retain %d AP attack reserve" % attack_reserve
			})

	if candidates.is_empty():
		return {}

	for i in candidates.size():
		var candidate: Dictionary = candidates[i]
		if not candidate.has("tie"):
			candidate["tie"] = "%s:%06d" % [String(candidate.get("key", "")), i]
		if not candidate.has("rationale"):
			candidate["rationale"] = _default_rationale(String(candidate.get("key", "")))

	candidates.sort_custom(func(a, b):
		var a_score := float(a.get("score", 0.0))
		var b_score := float(b.get("score", 0.0))
		if not is_equal_approx(a_score, b_score):
			return a_score > b_score
		return String(a.get("tie", "")) < String(b.get("tie", ""))
	)

	var winner: Dictionary = candidates[0]
	var res := {
		"decision": String(winner["key"]),
		"rationale": String(winner.get("rationale", "")),
		"score": snappedf(float(winner.get("score", 0.0)), 0.001)
	}
	res[winner["key"]] = winner["value"]
	return res

func _adjacent_player(u, units: Array):
	var best = null
	var best_hp: int = 9999
	for p in units:
		if p.alive and p.team != u.team and Pathfinder.is_adjacent(u.cell, p.cell):
			if p.hp < best_hp:
				best = p
				best_hp = p.hp
	return best

func _total_weapons(u) -> int:
	var t := 0
	for k in u.inv.keys():
		var ItemDB = Engine.get_main_loop().root.get_node_or_null("ItemDB")
		var item = ItemDB.get_item(k) if ItemDB else {}
		if not item.is_empty() and (item.get("category", "") == "melee" or item.get("category", "") == "ranged"):
			t += int(u.inv.get(k, 0))
	return t

func _attack_profile(u) -> Dictionary:
	var best := {
		"kind": "fist",
		"cost": GameConfig.MELEE_COST,
		"range": 1,
		"penetrates_cover": false
	}
	var ItemDBNode = Engine.get_main_loop().root.get_node_or_null("ItemDB")
	if ItemDBNode == null:
		return best
	for kind in u.inv.keys():
		if int(u.inv.get(kind, 0)) <= 0 or kind in ["arrow", "bow", "string"]:
			continue
		if kind == "stringedbow" and int(u.inv.get("arrow", 0)) <= 0:
			continue
		var item: Dictionary = ItemDBNode.get_item(kind)
		if item.is_empty():
			continue
		var category := String(item.get("category", ""))
		var item_range := int(item.get("range", 1))
		if category != "ranged" and item_range <= 1:
			continue
		var item_cost := ActionEconomy.weapon_cost(item)
		if (
			item_cost < int(best["cost"])
			or (
				item_cost == int(best["cost"])
				and item_range > int(best["range"])
			)
		):
			best = {
				"kind": String(kind),
				"cost": item_cost,
				"range": item_range,
				"penetrates_cover": bool(item.get("penetrates_cover", false))
			}
	return best

func _throw_target(
	u,
	_kind: String,
	units: Array,
	cells: Dictionary,
	rng: int,
	ignored_cover: Vector2i = GameConfig.INVALID_CELL,
	penetrates_cover: bool = false
):
	var best = null
	var bd := 1 << 30
	for p in units:
		if not (p.alive and p.team != u.team):
			continue
		if (
			Pathfinder.cheb(u.cell, p.cell) <= rng
			and Pathfinder.has_los(
				u.cell,
				p.cell,
				cells,
				u.z,
				p.z,
				ignored_cover,
				penetrates_cover
			)
		):
			var d := Pathfinder.cheb(u.cell, p.cell)
			if d < bd:
				bd = d
				best = p
	return best

func _enemy_spear_line(
	u,
	units: Array,
	cells: Dictionary,
	rng: int,
	ignored_cover: Vector2i = GameConfig.INVALID_CELL,
	penetrates_cover: bool = false
) -> Array[Vector2i]:
	var best_target = null
	var bd := 1 << 30
	for p in units:
		if not (p.alive and p.team != u.team):
			continue
		if Pathfinder.cheb(u.cell, p.cell) > rng:
			continue
		var line := Pathfinder.line(
			u.cell,
			p.cell,
			rng,
			cells,
			u.z,
			ignored_cover,
			penetrates_cover
		)
		if not line.has(p.cell):
			continue
		if line.size() < bd:
			bd = line.size()
			best_target = p
	if best_target == null:
		return []
	return Pathfinder.line(
		u.cell,
		best_target.cell,
		rng,
		cells,
		u.z,
		ignored_cover,
		penetrates_cover
	)

func _default_rationale(action: String) -> String:
	match action:
		"block":
			return "low health defense"
		"melee":
			return "adjacent hostile"
		"grab":
			return "recover weapon at current position"
		"throw_spear", "throw_item", "fire_bow":
			return "legal ranged attack"
		"assemble_auto", "assemble":
			return "assemble available weapon"
	return "highest deterministic legal utility"

func _best_approach(u, units: Array, cells: Dictionary) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	for p in units:
		if not (p.alive and p.team != u.team):
			continue
		var path: Array[Vector2i] = []
		if get_tree().current_scene and get_tree().current_scene.has_method("get_smart_path"):
			path = get_tree().current_scene.get_smart_path(u.cell, p.cell)
		else:
			path = Pathfinder.path_toward(u.cell, p.cell, cells, units)

		if path.size() >= 2 and (best.is_empty() or path.size() < best.size()):
			best = path
	return best

func _greedy_step(u, units: Array, cells: Dictionary) -> Vector2i:
	var target = _nearest_player(u, units)
	if target == null:
		return GameConfig.INVALID_CELL
	var best := GameConfig.INVALID_CELL
	var best_d := absi(u.cell.x - target.cell.x) + absi(u.cell.y - target.cell.y)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = u.cell + d
		if not Pathfinder.cell_free(n, cells, units):
			continue
		var nd := absi(n.x - target.cell.x) + absi(n.y - target.cell.y)
		if nd < best_d:
			best_d = nd
			best = n
	return best

func _nearest_player(u, units: Array):
	var best = null
	var bd := 1 << 30
	for p in units:
		if p.alive and p.team != u.team:
			var d := absi(p.cell.x - u.cell.x) + absi(p.cell.y - u.cell.y)
			if d < bd:
				bd = d
				best = p
	return best
