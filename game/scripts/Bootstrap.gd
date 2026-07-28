extends Node

## Chooses the correct entry surface without maintaining separate Godot projects.
## Native builds start at the strategic launcher. Web exports are tactical embeds.

func _ready() -> void:
	var target := "res://Main.tscn" if OS.has_feature("web") else "res://StratLayer.tscn"
	get_tree().change_scene_to_file.call_deferred(target)
