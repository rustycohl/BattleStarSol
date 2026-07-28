extends Node
class_name InventorySystem

const Config = preload("res://scripts/GameConfig.gd")

var main: Node

func setup(m: Node) -> void:
	main = m

func has_item(u: Unit, kind: String) -> bool:
	return kind != "" and kind != "fist" and int(u.inv.get(kind, 0)) > 0

func hand_item(u: Unit, use_offhand: bool) -> Dictionary:
	if u.two_handed:
		if has_item(u, u.right):
			return {"kind": u.right, "two": true}
		return {"kind": "", "two": false}
	var k: String = u.left if use_offhand else u.right
	if k != "" and not has_item(u, k):
		k = ""
	return {"kind": k, "two": false}

func inv_str(inv: Dictionary) -> String:
	var s := ""
	for k in inv.keys():
		if int(inv.get(k, 0)) > 0:
			var code = k.left(4).capitalize()
			s += "%s:%d " % [code, int(inv[k])]
	return s

func grab(u: Unit) -> bool:
	if not main.debris.has(u.cell) or u.ap < Config.GRAB_COST:
		return false
	var collected: Dictionary = main.debris[u.cell].duplicate(true)
	u.ap -= Config.GRAB_COST
	for k in main.debris[u.cell].keys():
		u.inv[k] = int(u.inv.get(k, 0)) + int(main.debris[u.cell].get(k, 0))
	main._remove_debris(u.cell)
	main._refresh_label(u)
	main._update_ui()
	GameState.record_event("loot_collected", {
		"actor": u.unit_id,
		"cell": {"x": u.cell.x, "y": u.cell.y, "z": u.z},
		"items": collected,
		"ap_spent": Config.GRAB_COST
	})
	return true

func assemble(u: Unit) -> bool:
	if u.two_handed:
		main._hint("Free hands required to string bow.")
		return false
	var ok := (u.left == "bow" and u.right == "string") or (u.left == "string" and u.right == "bow")
	if not ok or u.ap < Config.ASSEMBLE_COST:
		main._hint("Hold bow & string in separate hands + %d AP." % Config.ASSEMBLE_COST)
		return false
	u.ap -= Config.ASSEMBLE_COST
	u.inv["bow"] = int(u.inv.get("bow", 0)) - 1
	u.inv["string"] = int(u.inv.get("string", 0)) - 1
	u.inv["stringedbow"] = int(u.inv.get("stringedbow", 0)) + 1
	u.two_handed = true
	u.right = "stringedbow"
	u.left = ""
	main._refresh_label(u)
	main._update_ui()
	if Narrative:
		Narrative.generate_assemble_narrative(u.name)
	GameState.record_event("item_assembled", {
		"actor": u.unit_id,
		"recipe": "bow+string",
		"result": "stringedbow",
		"ap_spent": Config.ASSEMBLE_COST
	})
	return true
