extends Node

var items: Dictionary = {}

func _ready() -> void:
	_load_items()

func _load_items() -> void:
	var path = "res://data/items.json"
	if not FileAccess.file_exists(path):
		push_warning("ItemDB: data/items.json not found.")
		return

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("ItemDB: Failed to open items.json")
		return

	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	if err == OK:
		items = json.data
		print("ItemDB: Loaded %d items." % items.size())
	else:
		push_error("ItemDB: JSON Parse Error at line %d: %s" % [json.get_error_line(), json.get_error_message()])

func get_item(id: String) -> Dictionary:
	return items.get(id, {})

func has_item(id: String) -> bool:
	return items.has(id)

func get_random_by_tier(tier: int, rng: RandomNumberGenerator = null) -> String:
	var candidates = []
	for id in items:
		if items[id].get("tier", 0) == tier:
			candidates.append(id)
	if candidates.size() > 0:
		candidates.sort()
		if rng:
			return candidates[rng.randi_range(0, candidates.size() - 1)]
		return candidates[0]
	return "rock" # fallback

func get_all_weapons() -> Array:
	var w = []
	var GameState = Engine.get_main_loop().root.get_node_or_null("GameState")
	var unlocked = GameState.unlocked_tiers if GameState else [0, 1]
	for id in items:
		if items[id].get("category", "") in ["melee", "ranged"]:
			if items[id].get("tier", 0) in unlocked:
				w.append(id)
	return w
