extends Node

# Pathfinder.gd — Grid pathfinding and line-of-sight utility singleton

func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

func is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1

func unit_at(c: Vector2i, units: Array):
	for u in units:
		if u.alive and u.cell == c:
			return u
	return null

func cell_free(c: Vector2i, cells: Dictionary, units: Array) -> bool:
	return cells.has(c) and unit_at(c, units) == null

func get_z(c: Vector2i, cells: Dictionary) -> int:
	if not cells.has(c): return 0
	return cells[c].get("z", 0)

func find_path(start: Vector2i, goal: Vector2i, cells: Dictionary, units: Array, is_flying: bool = false) -> Array[Vector2i]:
	if start == goal:
		return [start]
	if not cell_free(goal, cells, units):
		return []

	var frontier := [start]
	var came := { start: start }
	var cost_so_far := { start: 0 }
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	while not frontier.is_empty():
		# Simple priority queue extraction
		var cur: Vector2i = frontier[0]
		var cur_cost = cost_so_far[cur]
		var cur_idx = 0
		for i in range(1, frontier.size()):
			if cost_so_far[frontier[i]] < cur_cost:
				cur = frontier[i]
				cur_cost = cost_so_far[cur]
				cur_idx = i
		frontier.remove_at(cur_idx)

		if cur == goal:
			break

		var cur_z = get_z(cur, cells)
		for d in dirs:
			var nx: Vector2i = cur + d
			if not cell_free(nx, cells, units):
				continue

			var nx_z = get_z(nx, cells)
			var height_delta := absi(nx_z - cur_z)
			if height_delta > GameConfig.MAX_WALK_STEP and not is_flying:
				continue
			var move_cost = 1
			if height_delta > 0 and not is_flying:
				move_cost += height_delta # Mantle penalty

			var new_cost = cost_so_far[cur] + move_cost
			if not cost_so_far.has(nx) or new_cost < cost_so_far[nx]:
				cost_so_far[nx] = new_cost
				came[nx] = cur
				if not frontier.has(nx):
					frontier.append(nx)

	if not came.has(goal):
		return []
	return _reconstruct(came, start, goal)

func _reconstruct(came: Dictionary, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [goal]
	var cur := goal
	while cur != start:
		cur = came[cur]
		path.append(cur)
	path.reverse()
	return path

func path_toward(start: Vector2i, target_cell: Vector2i, cells: Dictionary, units: Array, is_flying: bool = false) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var g: Vector2i = target_cell + d
		if not cell_free(g, cells, units):
			continue
		var p := find_path(start, g, cells, units, is_flying)
		if p.size() >= 2 and (best.is_empty() or p.size() < best.size()):
			best = p
	return best

func nearest_debris_path(u_cell: Vector2i, debris: Dictionary, cells: Dictionary, units: Array, is_flying: bool = false) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	for cell in debris.keys():
		var p := find_path(u_cell, cell, cells, units, is_flying)
		if p.size() >= 2 and (best.is_empty() or p.size() < best.size()):
			best = p
	return best

func has_los(
	a: Vector2i,
	b: Vector2i,
	cells: Dictionary,
	a_z: int = -1,
	b_z: int = -1,
	ignored_cover: Vector2i = GameConfig.INVALID_CELL,
	penetrates_cover: bool = false
) -> bool:
	var az: int = a_z if a_z >= 0 else (cells.get(a, {}).get("z", 0) if cells.has(a) else 0)
	var bz: int = b_z if b_z >= 0 else (cells.get(b, {}).get("z", 0) if cells.has(b) else 0)
	var ray_h: int = maxi(az, bz)

	var x0 := a.x
	var y0 := a.y
	var dx := absi(b.x - x0)
	var dy := absi(b.y - y0)
	var sx := 1 if x0 < b.x else -1
	var sy := 1 if y0 < b.y else -1
	var err := dx - dy
	while true:
		if not (x0 == a.x and y0 == a.y) and not (x0 == b.x and y0 == b.y):
			var c := Vector2i(x0, y0)
			if (
				not penetrates_cover
				and c != ignored_cover
				and cells.has(c)
				and cells[c].get("type", GameConfig.FLOOR) == GameConfig.COVER
			):
				var cz: int = cells[c].get("z", 0)
				if cz >= ray_h:
					return false
		if x0 == b.x and y0 == b.y:
			break
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
	return true

func line(
	a: Vector2i,
	target: Vector2i,
	rng: int,
	cells: Dictionary,
	a_z: int = -1,
	ignored_cover: Vector2i = GameConfig.INVALID_CELL,
	penetrates_cover: bool = false
) -> Array[Vector2i]:
	var az: int = a_z if a_z >= 0 else (cells.get(a, {}).get("z", 0) if cells.has(a) else 0)
	var out: Array[Vector2i] = []
	var dir := target - a
	if dir == Vector2i.ZERO:
		return out
	var far := a + dir * (GameConfig.GRID_W + GameConfig.GRID_H)
	var x0 := a.x
	var y0 := a.y
	var dx := absi(far.x - x0)
	var dy := absi(far.y - y0)
	var sx := 1 if x0 < far.x else -1
	var sy := 1 if y0 < far.y else -1
	var err := dx - dy
	while true:
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
		var c := Vector2i(x0, y0)
		if c.x < 0 or c.y < 0 or c.x >= GameConfig.GRID_W or c.y >= GameConfig.GRID_H:
			break
		if cheb(a, c) > rng:
			break
		if (
			not penetrates_cover
			and c != ignored_cover
			and cells.has(c)
			and cells[c].get("type", GameConfig.FLOOR) == GameConfig.COVER
		):
			var cz: int = cells[c].get("z", 0)
			if cz >= az:
				break
		out.append(c)
		if c == far:
			break
	return out
