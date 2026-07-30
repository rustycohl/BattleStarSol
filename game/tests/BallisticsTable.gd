extends SceneTree

## Ballistics balance table.
##
##   Godot --path game --headless --script res://tests/BallisticsTable.gd
##
## Emits every shipped ranged weapon against every cover class the terrain
## generator can produce, using the same derivation the simulation uses. It
## asserts nothing: it is the evidence a balance decision is made from.

const Config = preload("res://scripts/GameConfig.gd")
const World = preload("res://scripts/WorldBuilder.gd")
const Ballistics = preload("res://scripts/Ballistics.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var items = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	if not (items is Dictionary):
		print("BALLISTICS_TABLE_ERROR no item data")
		quit(1)
		return

	# Cover classes the generator actually produces: hard columns are height 3-6,
	# soft cover is height 1-2.
	var cover_classes: Array = []
	for height in [1, 2, 3, 4, 5, 6]:
		var cell_type: int = Config.COVER if height >= 3 else Config.HALF_COVER
		var cell: Dictionary = World.material_cell(cell_type, height)
		cover_classes.append({
			"height": height,
			"class": String(cell["material"]),
			"density": int(cell["density"]),
			"cover_level": Ballistics.effective_cover_level(cell)
		})

	var weapons: Array = []
	var keys: Array = (items as Dictionary).keys()
	keys.sort()
	for key in keys:
		var item = (items as Dictionary)[key]
		if not (item is Dictionary):
			continue
		var data: Dictionary = item
		if String(data.get("category", "")) != "ranged":
			continue
		var penetration := Ballistics.penetration_for_item(data)
		var against: Array = []
		for cover_class in cover_classes:
			var cell := World.material_cell(
				Config.COVER if int(cover_class["height"]) >= 3 else Config.HALF_COVER,
				int(cover_class["height"])
			)
			var shot: Dictionary = Ballistics.resolve_item_penetration(cell, data, 100)
			against.append({
				"cover": "%s h%d d%d" % [
					String(cover_class["class"]),
					int(cover_class["height"]),
					int(cover_class["density"])
				],
				"outcome": String(shot["outcome"]),
				"power_through": int(shot["power_through"]),
				"shots_to_break": _shots_to_break(cell, data)
			})
		weapons.append({
			"kind": String(key),
			"name": String(data.get("name", key)),
			"damage": int(data.get("dmg", 0)),
			"range": int(data.get("range", 0)),
			"armor_pierce": int(data.get("armor_pierce", 0)),
			"damage_type": String(data.get("damage_type", "kinetic")),
			"penetrates_cover": bool(data.get("penetrates_cover", false)),
			"penetration": penetration,
			"against": against
		})

	var stopped_somewhere := 0
	var through_everything := 0
	for weapon in weapons:
		var stopped := false
		var through := true
		for row in weapon["against"]:
			if String(row["outcome"]) == "stopped":
				stopped = true
				through = false
		if stopped:
			stopped_somewhere += 1
		if through:
			through_everything += 1

	var document := {
		"schema": "gzg.battlestar.ballistics-table/1.0",
		"engine": Engine.get_version_info().get("string", ""),
		"derivation": "penetration = armor_pierce * 9 + damage-type bonus, clamped 0-100; penetrates_cover reads as 100",
		"damage_type_bonus": Ballistics.DAMAGE_TYPE_PENETRATION,
		"hard_cover_floor": Ballistics.HARD_COVER_FLOOR,
		"rubble_floor": Ballistics.RUBBLE_FLOOR,
		"cover_classes": cover_classes,
		"weapons": weapons,
		"summary": {
			"ranged_weapons": weapons.size(),
			"stopped_by_some_cover": stopped_somewhere,
			"penetrate_every_cover": through_everything
		}
	}
	print("BALLISTICS_TABLE_BEGIN")
	print(JSON.stringify(document, "  "))
	print("BALLISTICS_TABLE_END")
	quit(0)

## How many hits from this weapon reduce the cell out of cover entirely.
func _shots_to_break(cell: Dictionary, item: Dictionary) -> int:
	var working := cell.duplicate(true)
	var shots := 0
	while Ballistics.effective_cover_level(working) > 0 and shots < 99:
		var shot: Dictionary = Ballistics.resolve_item_penetration(working, item, 100)
		var damage := int(shot["damage_to_cover"])
		if damage <= 0:
			return -1
		working = Ballistics.degrade_cell(working, damage)
		shots += 1
	return shots
