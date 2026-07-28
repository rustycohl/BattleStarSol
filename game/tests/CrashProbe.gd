extends SceneTree
func _init():
	print("PROBE autoloads:")
	for n in ["GameConfig","GameState","Narrative","PayloadBridge","ItemDB","ActionRouter","AudioSystem"]:
		var node = root.get_node_or_null("/root/" + n)
		print("  ", n, ": ", node)
	print("PROBE loading Main.tscn...")
	var packed = load("res://Main.tscn")
	print("  packed=", packed)
	if packed:
		var inst = packed.instantiate()
		print("  instantiated type=", inst.get_class())
		root.add_child(inst)
		print("  added OK, units=", inst.get("units"))
	print("PROBE done")
	quit(0)
